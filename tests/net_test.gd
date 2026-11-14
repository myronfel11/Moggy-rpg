extends Node
## Co-op test: two real game processes on this PC, one hosting and one joining.
##
## Run by tools\test_net.cmd, which starts the host in the background and then the client:
##   godot --headless --path <project> res://tests/net_test.tscn -- --role=host --port=24600
##   godot --headless --path <project> res://tests/net_test.tscn -- --role=client --port=24600
## Each prints "NET TEST PASS" or "NET TEST FAIL: <reason>" and exits 0 or 1.
##
## The host spawns a Scrap Hound and hurts it before anyone joins. The client first tries to
## join with a wrong version (must be refused with a reason), then joins properly, checks it
## sees the hound already hurt, and kills it with a bot. Both sides then compare the loot
## they got from that kill, which must be identical.

const MAIN := preload("res://main/main.tscn")
const ARENA := preload("res://levels/test_arena/test_arena.tscn")
const TIMEOUT := 60.0
## The client waits this long before joining, so the host is listening first.
const JOIN_DELAY := 2.0
const EARLY_DAMAGE := 12.0

var _failed := false
var _main: Main
## The client's loot from the kill, received by the host.
var _client_loot: Variant = null


func _ready() -> void:
	var role := ""
	var port := 24600
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void: _finish("timed out"))
	_main = MAIN.instantiate() as Main
	add_child(_main)
	# Never read or write the real save file.
	_main.profile.persistent = false
	_main.profile.reset()
	if role == "host":
		await _run_host(port)
	elif role == "client":
		await _run_client(port)
	else:
		_finish("pass --role=host or --role=client")
		return
	_finish("")


func _run_host(port: int) -> void:
	if _main.session.host(port) != OK:
		_fail("could not host on port %d" % port)
		return
	var arena := ARENA.instantiate() as Arena
	arena.auto_start = false
	_main.world.add_child(arena, true)
	await get_tree().physics_frame

	# Spawn and hurt a hound before anyone joins. The host's player leaves the "players"
	# group meanwhile so the hound has nobody to chase.
	var host_player := arena.local_player
	host_player.remove_from_group(&"players")
	var director := arena.get_node(^"WaveDirector") as WaveDirector
	var hound := director.spawn_enemy(director.enemy_type, Vector2(60.0, 60.0))
	await get_tree().create_timer(Enemy.SPAWN_TIME + 0.2).timeout
	hound.health.take_damage(EARLY_DAMAGE)

	print("host: waiting for the client's player")
	if not await _wait_for(func() -> bool: return _count_players(arena) == 2, 30.0):
		_fail("the client's player never appeared on the host")
		return
	host_player.add_to_group(&"players")
	var remote_player: Player = null
	for player in arena.get_players():
		if not player.is_local():
			remote_player = player
	_check(remote_player != null and remote_player.peer_id != 1, "the client's player belongs to the client")
	var start_position := remote_player.global_position

	var died := [false]
	hound.died.connect(func(_enemy: Enemy) -> void: died[0] = true)
	print("host: waiting for the client to kill the hound")
	if not await _wait_for(func() -> bool: return died[0], 25.0):
		_fail("the hound never died (health %.0f)" % hound.health.current)
		return
	var host_loot := hound.last_loot
	_check(
		remote_player.global_position.distance_to(start_position) > 10.0,
		"the client's player moved on the host's screen"
	)
	if not await _wait_for(func() -> bool: return _client_loot != null, 10.0):
		_fail("the client never reported its loot")
		return
	_check(_sorted(host_loot) == _sorted(_client_loot), "host and client got identical drops %s" % [host_loot])

	# Stay connected until the client has finished its own checks and left.
	await _wait_for(func() -> bool: return multiplayer.get_peers().is_empty(), 10.0)
	await _wait_for(func() -> bool: return _count_players(arena) == 1, 3.0)
	_check(_count_players(arena) == 1, "a client that leaves has its player removed")


func _run_client(port: int) -> void:
	await get_tree().create_timer(JOIN_DELAY).timeout
	var status := _main.get_node(^"Menu/Panel/Status") as Label

	_main.session.version_override = "0.0.0-wrong"
	_main.start_join("127.0.0.1")
	var refused := await _wait_for(func() -> bool: return status.text.begins_with("Version mismatch"), 15.0)
	_check(refused, "a client with a different version is refused with a reason (got '%s')" % status.text)
	_main.session.version_override = ""
	await get_tree().create_timer(0.5).timeout

	_main.start_join("127.0.0.1")
	if not await _wait_for(func() -> bool:
		var arena := _main.get_arena()
		return arena != null and arena.local_player != null, 20.0):
		_fail("never got an arena with a local player (status '%s')" % status.text)
		return
	var arena := _main.get_arena()
	var player := arena.local_player
	player.input.use_device = false
	await _wait_for(func() -> bool: return _count_players(arena) == 2, 5.0)
	var local_count := 0
	for each in arena.get_players():
		if each.is_local():
			local_count += 1
	_check(_count_players(arena) == 2, "the client sees both players")
	_check(local_count == 1, "exactly one player is controlled by the client")

	if not await _wait_for(func() -> bool: return not get_tree().get_nodes_in_group(&"enemies").is_empty(), 15.0):
		_fail("the host's hound never appeared on the client")
		return
	var enemy := get_tree().get_nodes_in_group(&"enemies")[0] as Enemy
	await get_tree().physics_frame
	var expected := enemy.data.max_health - EARLY_DAMAGE
	_check(
		is_equal_approx(enemy.health.current, expected),
		"a late joiner sees the hound already hurt (%.0f of %.0f)" % [enemy.health.current, enemy.data.max_health]
	)

	print("client: fighting the hound")
	var dead := [false]
	enemy.died.connect(func(_enemy: Enemy) -> void: dead[0] = true)
	var fought := await _wait_for(func() -> bool:
		if dead[0]:
			return true
		TestBot.swing_only(player)
		return false, 20.0)
	TestBot.stop(player)
	_check(fought, "the client killed the host's hound")
	if fought:
		_report_loot.rpc_id(1, enemy.last_loot)

	var scrap := enemy.data.drops[0].item
	await _wait_for(func() -> bool: return player.inventory.get_count(scrap) > 0, 4.0)
	_check(player.inventory.get_count(scrap) > 0, "the client collected its own loot")
	await _wait_for(func() -> bool: return get_tree().get_nodes_in_group(&"enemies").is_empty(), 4.0)
	_check(get_tree().get_nodes_in_group(&"enemies").is_empty(), "the dead hound was removed on the client")
	# Give the loot report time to reach the host before leaving.
	await get_tree().create_timer(0.5).timeout


@rpc("any_peer", "call_remote", "reliable")
func _report_loot(loot: PackedStringArray) -> void:
	_client_loot = loot


func _count_players(arena: Arena) -> int:
	var count := 0
	for child in arena.get_node(^"Entities").get_children():
		if child is Player and not child.is_queued_for_deletion():
			count += 1
	return count


func _sorted(items: Variant) -> Array:
	var list := Array(items)
	list.sort()
	return list


## Calls [param condition] every physics frame until it returns true or time runs out.
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
