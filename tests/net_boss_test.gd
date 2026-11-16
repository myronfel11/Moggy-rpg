extends Node
## Co-op boss test: a real host and a real client fight parts of "The Three Pillars".
## Run by tools\test_net.cmd (host in the background, then the client):
##   godot --headless --path <project> res://tests/net_boss_test.tscn -- --role=host --port=24602
##   godot --headless --path <project> res://tests/net_boss_test.tscn -- --role=client --port=24602
##
## The two sides walk through numbered steps, telling each other when a step is done.
## Checks: same state on both screens; the client's bomb pickup request is accepted and a
## second claim refused; the client slams a bomb; the client disconnects while carrying a
## bomb and the host recovers it; the client rejoins mid-fight and sees the current state;
## the laser kill on the client is decided on the client's own machine.

const MAIN := preload("res://main/main.tscn")
const BOSS_ARENA := "res://bosses/three_pillars/boss_arena.tscn"
const BOSS_MISSION := "res://missions/data/three_pillars.tres"
const TIMEOUT := 120.0
const JOIN_DELAY := 2.0

var _failed := false
var _main: Main
## The highest step number the other side has finished.
var _their_step := 0


func _ready() -> void:
	var role := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void: _finish("timed out"))
	_main = MAIN.instantiate() as Main
	add_child(_main)
	_main.profile.persistent = false
	_main.profile.reset()
	if role == "host":
		await _run_host()
	elif role == "client":
		await _run_client()
	else:
		_finish("pass --role=host or --role=client")
		return
	_finish("")


@rpc("any_peer", "call_remote", "reliable")
func _step(number: int) -> void:
	_their_step = maxi(_their_step, number)


func _send_step(number: int) -> void:
	if multiplayer.is_server():
		_step.rpc(number)
	else:
		_step.rpc_id(1, number)


func _wait_step(number: int, seconds := 30.0) -> bool:
	return await _wait_for(func() -> bool: return _their_step >= number, seconds)


func _arena() -> BossArena:
	return _main.get_level() as BossArena


func _me() -> Player:
	var arena := _arena()
	if arena == null or arena.local_player == null or not is_instance_valid(arena.local_player):
		return null
	arena.local_player.input.use_device = false
	return arena.local_player


func _player_count() -> int:
	var arena := _arena()
	if arena == null:
		return 0
	var count := 0
	for child in arena.get_node(^"Entities").get_children():
		if child is Player and not child.is_queued_for_deletion():
			count += 1
	return count


func _remote_player() -> Player:
	var arena := _arena()
	if arena == null:
		return null
	for player in arena.get_players():
		if not player.is_local():
			return player
	return null


func _bomb(slot: int) -> Bomb:
	for node in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := node as Bomb
		if bomb != null and bomb.slot == slot and not bomb.is_queued_for_deletion():
			return bomb
	return null


# --- Host -----------------------------------------------------------------------------------

func _run_host() -> void:
	if _main.session.host(24602) != OK:
		_fail("could not host")
		return
	_main.change_level(BOSS_ARENA, BOSS_MISSION)
	if not await _wait_for(func() -> bool: return _me() != null, 10.0):
		_fail("the host never got into the boss arena")
		return
	var me := _me()
	me.health.setup(1000000.0)
	# The host hides from the laser so the test controls who is targeted.
	me.set_flag(Player.FLAG_INVISIBLE, true)
	var encounter := _arena().encounter
	await _wait_for(func() -> bool: return is_instance_valid(encounter.boss), 10.0)
	encounter.boss.laser_enabled = false
	for sentinel in encounter.sentinels:
		if is_instance_valid(sentinel):
			sentinel._fire_left = 9999.0
	if not await _wait_for(func() -> bool: return _player_count() == 2, 30.0):
		_fail("the client never arrived")
		return
	if not await _wait_step(1):
		_fail("the client never finished its first checks")
		return

	# Bomb 0: the client claims it first; the host's own later claim must be refused.
	await _expose_and_kill(encounter, 0)
	me.global_position = encounter.bombs[0].global_position + Vector2(12.0, 0.0)
	_send_step(2)
	await _wait_for(func() -> bool: return encounter.carriers[0] != 0, 15.0)
	var client_peer := _remote_player().peer_id if _remote_player() != null else -1
	_check(encounter.carriers[0] == client_peer, "the client's pickup request is accepted by the host")
	_check(not encounter.request_pickup(0, me.peer_id), "a second player cannot take a bomb that was already picked up")
	_send_step(3)
	var slammed := await _wait_for(func() -> bool: return encounter.get_slot(0) == BossEncounter.Slot.DELIVERED, 20.0)
	_check(slammed and is_equal_approx(encounter.get_shield_ratio(), 2.0 / 3.0), "the client's slam removes one third of the shield")
	await _wait_step(4)

	# Bomb 1: the client picks it up and disconnects; the host recovers it.
	await _expose_and_kill(encounter, 1)
	_send_step(5)
	await _wait_for(func() -> bool: return encounter.carriers[1] == client_peer, 20.0)
	_check(encounter.carriers[1] == client_peer, "the client picks up the second bomb")
	if not await _wait_for(func() -> bool: return _player_count() == 1, 20.0):
		_fail("the client never disconnected")
		return
	await _wait_for(func() -> bool: return encounter.get_slot(1) == BossEncounter.Slot.BOMB_DROPPED, 3.0)
	_check(encounter.get_slot(1) == BossEncounter.Slot.BOMB_DROPPED and encounter.carriers[1] == 0 and is_instance_valid(encounter.bombs[1]), "a carrier who disconnects drops the bomb")
	me.global_position = encounter.bombs[1].global_position
	await _frames(3)
	_check(encounter.request_pickup(1, me.peer_id), "the host can recover the dropped bomb")

	# The client rejoins mid-fight.
	if not await _wait_for(func() -> bool: return _player_count() == 2, 30.0):
		_fail("the client never came back")
		return
	if not await _wait_step(6):
		_fail("the rejoined client never finished its checks")
		return

	# Laser on the client: decided on the client's machine.
	var remote := _remote_player()
	var remote_died := [false]
	remote.died.connect(func() -> void: remote_died[0] = true)
	var revives_before := encounter.revives_left
	encounter.data.idle_time = 0.3
	encounter.boss.laser_enabled = true
	await _wait_step(7, 40.0)
	await _wait_for(func() -> bool: return remote_died[0], 5.0)
	encounter.boss.laser_enabled = false
	_check(remote_died[0], "the host sees the client go down from the laser")
	_check(encounter.revives_left == revives_before - 1, "the shared revive pool pays for the client's revive")
	_send_step(8)
	await _wait_for(func() -> bool: return multiplayer.get_peers().is_empty(), 15.0)


func _expose_and_kill(encounter: BossEncounter, slot: int) -> void:
	for i in encounter.data.pillar_hits:
		encounter.on_ball_hit_pillar(slot)
	await _frames(int(Enemy.SPAWN_TIME * 60.0) + 5)
	if is_instance_valid(encounter.sentinels[slot]):
		encounter.sentinels[slot].hurtbox.receive_hit(HitInfo.new(99999.0))
	await _wait_for(func() -> bool: return is_instance_valid(encounter.bombs[slot]), 5.0)
	await _frames(10)


# --- Client ---------------------------------------------------------------------------------

func _join_fight() -> bool:
	_main.start_join("127.0.0.1")
	if not await _wait_for(func() -> bool: return _main.get_level() is BossArena and _me() != null, 20.0):
		return false
	_me().health.setup(1000000.0)
	return true


func _run_client() -> void:
	await get_tree().create_timer(JOIN_DELAY).timeout
	if not await _join_fight():
		_fail("could not join the host's boss fight")
		return
	var encounter := _arena().encounter
	await _wait_for(func() -> bool: return encounter.state == BossEncounter.State.SHIELDED_MECHANICS and get_tree().get_first_node_in_group(&"pillar_boss") != null, 15.0)
	_check(encounter.state == BossEncounter.State.SHIELDED_MECHANICS, "the client sees the fight in progress")
	var boss := get_tree().get_first_node_in_group(&"pillar_boss") as PillarBoss
	_check(boss != null and boss.health.max_health > 0.0 and not boss.vulnerable, "the client sees the shielded boss")
	_check(get_tree().get_nodes_in_group(&"sentinels").size() == 3, "the client sees three sentinels")
	_send_step(1)

	# Bomb 0: hold E on it.
	await _wait_step(2)
	var me := _me()
	var bomb := _bomb(0)
	await _wait_for(func() -> bool: return _bomb(0) != null, 5.0)
	bomb = _bomb(0)
	me.global_position = bomb.global_position + Vector2(-12.0, 0.0)
	await _frames(3)
	me.input.interact_held = true
	var picked := await _wait_for(func() -> bool: return encounter.carriers[0] == me.peer_id, 10.0)
	me.input.interact_held = false
	_check(picked, "holding E on a bomb gets it from the host")
	await _frames(5)
	_check(bomb.global_position.distance_to(me.global_position) < 20.0, "the client's carried bomb rides with them")

	await _wait_step(3)
	me.global_position = boss.global_position + Vector2(0.0, 40.0)
	await _frames(3)
	me.input.interact_held = true
	var slammed := await _wait_for(func() -> bool: return encounter.get_slot(0) == BossEncounter.Slot.DELIVERED, 10.0)
	me.input.interact_held = false
	_check(slammed and is_equal_approx(encounter.get_shield_ratio(), 2.0 / 3.0), "the client sees its slam crack the shield")
	_send_step(4)

	# Bomb 1: pick it up, then disconnect while carrying it.
	await _wait_step(5)
	await _wait_for(func() -> bool: return _bomb(1) != null, 5.0)
	me.global_position = _bomb(1).global_position
	await _frames(3)
	me.input.interact_held = true
	await _wait_for(func() -> bool: return encounter.carriers[1] == me.peer_id, 10.0)
	me.input.interact_held = false
	await _frames(10)
	_main.session.leave()
	_main._back_to_menu("")
	await get_tree().create_timer(2.0).timeout

	# Rejoin mid-fight.
	if not await _join_fight():
		_fail("could not rejoin the fight")
		return
	encounter = _arena().encounter
	await _wait_for(func() -> bool: return encounter.get_slot(1) == BossEncounter.Slot.BOMB_CARRIED, 10.0)
	_check(encounter.state == BossEncounter.State.SHIELDED_MECHANICS, "a rejoining player arrives in the running fight")
	_check(encounter.get_slot(0) == BossEncounter.Slot.DELIVERED and encounter.get_slot(1) == BossEncounter.Slot.BOMB_CARRIED and encounter.get_slot(2) == BossEncounter.Slot.SHIELDED, "a rejoining player sees every slot's current state")
	await _frames(5)
	var pillars := encounter.get_pillars()
	_check(not pillars[0].intact and not pillars[1].intact and pillars[2].intact, "a rejoining player sees which pillars are down")
	_check(_bomb(1) != null and _bomb(1).carrier_peer == 1, "a rejoining player sees the host carrying the recovered bomb")
	_check(is_equal_approx(encounter.get_shield_ratio(), 2.0 / 3.0), "a rejoining player sees the shield at two thirds")
	_send_step(6)

	# Stand still and let the laser hit: the kill happens on this machine.
	me = _me()
	var died := await _wait_for(func() -> bool: return not me.is_alive(), 40.0)
	_check(died, "the laser kills the client on the client's own machine")
	_send_step(7)
	await _wait_step(8)


# --- Shared -----------------------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _check(condition: bool, label: String) -> void:
	print("  ok    " if condition else "  FAIL  ", label)
	if not condition:
		_failed = true


func _fail(reason: String) -> void:
	print("  FAIL  ", reason)
	_failed = true


func _finish(reason: String) -> void:
	if reason != "":
		_fail(reason)
	print("NET TEST FAIL" if _failed else "NET TEST PASS")
	_main.session.leave()
	get_tree().quit(1 if _failed else 0)
