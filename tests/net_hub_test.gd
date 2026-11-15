extends Node
## Co-op hub test: two real game processes on this PC going hub -> mission -> hub.
##
## Run by tools\test_net.cmd (host in the background, then the client):
##   godot --headless --path <project> res://tests/net_hub_test.tscn -- --role=host --port=24601
##   godot --headless --path <project> res://tests/net_hub_test.tscn -- --role=client --port=24601
##
## Checks: the client joins the hub; it cannot start a mission; its character and
## loadout are visible to the host; the host's mission start takes both players along;
## both down ends the mission and brings both back to the hub.

const MAIN := preload("res://main/main.tscn")
const SUIT := preload("res://missions/data/suit.tres")
const SUIT_ITEM := preload("res://items/data/venza_suit.tres")
const BREAKER := preload("res://weapons/data/breaker.tres")
const NOVA := preload("res://characters/data/nova.tres")
const TIMEOUT := 60.0
const JOIN_DELAY := 2.0

var _failed := false
var _main: Main
var _client_ready := false
var _client_suits := -1


func _ready() -> void:
	var role := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void: _finish("timed out"))
	_main = MAIN.instantiate() as Main
	add_child(_main)
	# Never read or write the real save file.
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


func _run_host() -> void:
	_main.start_host()
	if not await _wait_for(func() -> bool: return _player_count() == 2, 30.0):
		_fail("the client never arrived in the hub")
		return
	_check(_main.get_level() is Hub, "host and client meet in the hub")
	if not await _wait_for(func() -> bool: return _client_ready, 15.0):
		_fail("the client never finished its hub checks")
		return
	var remote := _remote_player()
	await _wait_for(func() -> bool: return remote.character == NOVA, 3.0)
	_check(remote.character == NOVA, "the host sees the client's chosen character in the hub")
	_check(not (_main.get_level() as Hub).is_starting(), "the client could not start a mission")

	(_main.get_level() as Hub).start_mission(SUIT)
	var arrived := await _wait_for(func() -> bool: return _main.get_arena() != null and _player_count() == 2, 15.0)
	_check(arrived, "the host's mission start takes both players along")
	if not arrived:
		return
	remote = _remote_player()
	await _wait_for(func() -> bool: return remote.weapon != null and remote.weapon.data == BREAKER, 3.0)
	_check(remote.character == NOVA, "the client's character is the same in the mission")
	_check(remote.weapon != null and remote.weapon.data == BREAKER, "the host sees the client's own weapon in the mission")

	# Clear the mission with its reward made certain: the host rolls once and both
	# players must get the Suit, each in their own inventory.
	var director := _main.get_arena().get_node(^"WaveDirector") as WaveDirector
	await _wait_for(func() -> bool: return director.wave >= 1, 10.0)
	var suit_mission: MissionData = SUIT
	suit_mission.reward_chance = 1.0
	director.mission_ended.emit(true)
	director.mission_ended.emit(true)
	var back := await _wait_for(func() -> bool: return _main.get_level() is Hub and _player_count() == 2, 15.0)
	_check(back, "clearing the mission sends both players back to the hub")
	_check(_local() != null and _local().inventory.get_count(SUIT_ITEM) == 1, "the host got the Suit exactly once")
	await _wait_for(func() -> bool: return _client_suits >= 0, 10.0)
	_check(_client_suits == 1, "the client got the Suit exactly once in its own inventory (got %d)" % _client_suits)
	await _wait_for(func() -> bool: return multiplayer.get_peers().is_empty(), 10.0)


func _run_client() -> void:
	await get_tree().create_timer(JOIN_DELAY).timeout
	_main.start_join("127.0.0.1")
	if not await _wait_for(func() -> bool: return _main.get_level() is Hub and _local() != null and _player_count() == 2, 20.0):
		_fail("never arrived in the host's hub with both players")
		return
	_check(true, "the client joins the host's hub")
	var player := _local()
	var hub := _main.get_level() as Hub
	var console := hub.get_node(^"NavigationConsole") as NavigationConsole
	var panel := console.open_panel(player)
	_check(panel != null and panel._start.disabled, "the client's Start button is disabled")
	panel.close()
	hub.start_mission(SUIT)
	_check(not hub.is_starting(), "the client cannot start a mission")

	player.unlock_weapon(BREAKER)
	player.set_loadout([BREAKER])
	player.set_character(NOVA)
	await get_tree().create_timer(0.5).timeout
	_ready_for_mission.rpc_id(1)

	var arrived := await _wait_for(func() -> bool: return _main.get_arena() != null and _local() != null, 15.0)
	_check(arrived, "the client is taken to the mission")
	if not arrived:
		return
	player = _local()
	_check(player.character == NOVA and player.loadout == [BREAKER], "the client's own character and loadout come along")
	var back := await _wait_for(func() -> bool: return _main.get_level() is Hub and _local() != null, 25.0)
	_check(back, "the client is back in the hub after the mission")
	if back:
		_check(_local().loadout == [BREAKER], "the client still has its loadout in the hub")
		_report_suits.rpc_id(1, _local().inventory.get_count(SUIT_ITEM))
		await get_tree().create_timer(0.5).timeout


@rpc("any_peer", "call_remote", "reliable")
func _report_suits(count: int) -> void:
	_client_suits = count


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_mission() -> void:
	_client_ready = true


func _local() -> Player:
	var level := _main.get_level()
	if level == null or level.local_player == null or not is_instance_valid(level.local_player):
		return null
	level.local_player.input.use_device = false
	return level.local_player


func _remote_player() -> Player:
	var level := _main.get_level()
	if level == null:
		return null
	for player in level.get_players():
		if not player.is_local():
			return player
	return null


func _player_count() -> int:
	var level := _main.get_level()
	if level == null:
		return 0
	var count := 0
	for child in level.get_node(^"Entities").get_children():
		if child is Player and not child.is_queued_for_deletion():
			count += 1
	return count


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
