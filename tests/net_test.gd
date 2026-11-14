extends Node
## Co-op test: two real game processes on this PC, one hosting and one joining.
##
## Run by tools\test_net.cmd, which starts the host in the background and then the client:
##   godot --headless --path <project> res://tests/net_test.tscn -- --role=host --port=24600
##   godot --headless --path <project> res://tests/net_test.tscn -- --role=client --port=24600
## Each prints "NET TEST PASS" or "NET TEST FAIL: <reason>" and exits 0 or 1.
##
## The host spawns one Scrap Hound. The client's player, driven by a bot, kills it.
## That proves: joining, player spawning and ownership, enemy replication, a client's hit
## reaching the host, the death reaching the client, and per-player loot.

const MAIN := preload("res://main/main.tscn")
const ARENA := preload("res://levels/test_arena/test_arena.tscn")
const TIMEOUT := 40.0
## The client waits this long before joining, so the host is listening first.
const JOIN_DELAY := 2.0

var _failed := false
var _main: Main


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
	print("host: waiting for the client's player")
	if not await _wait_for(func() -> bool: return arena.get_players().size() == 2, 20.0):
		_fail("the client's player never appeared on the host")
		return
	var remote_player: Player = null
	for player in arena.get_players():
		if not player.is_local():
			remote_player = player
	_check(remote_player != null and remote_player.peer_id != 1, "the client's player belongs to the client")
	await get_tree().create_timer(1.0).timeout

	var director := arena.get_node(^"WaveDirector") as WaveDirector
	var hound := director.spawn_enemy(director.enemy_type, arena.get_player_start() + Vector2(0.0, -60.0))
	var start_position := remote_player.global_position
	var died := [false]
	hound.died.connect(func(_enemy: Enemy) -> void: died[0] = true)
	print("host: spawned a hound, waiting for the client to kill it")
	if not await _wait_for(func() -> bool: return died[0], 25.0):
		_fail("the hound never died (health %.0f)" % hound.health.current)
		return
	_check(
		remote_player.global_position.distance_to(start_position) > 10.0,
		"the client's player moved on the host's screen"
	)
	# Stay connected until the client has finished its own checks and left.
	await _wait_for(func() -> bool: return multiplayer.get_peers().is_empty(), 10.0)
	await _wait_for(func() -> bool: return arena.get_players().size() == 1, 3.0)
	_check(arena.get_players().size() == 1, "a client that leaves has its player removed")


func _run_client(port: int) -> void:
	await get_tree().create_timer(JOIN_DELAY).timeout
	_main.start_join("127.0.0.1")
	if not await _wait_for(func() -> bool:
		var arena := _main.get_arena()
		return arena != null and arena.local_player != null, 20.0):
		_fail("never got an arena with a local player")
		return
	var arena := _main.get_arena()
	var player := arena.local_player
	player.input.use_device = false
	await _wait_for(func() -> bool: return arena.get_players().size() == 2, 5.0)
	var local_count := 0
	for each in arena.get_players():
		if each.is_local():
			local_count += 1
	_check(arena.get_players().size() == 2, "the client sees both players")
	_check(local_count == 1, "exactly one player is controlled by the client")

	if not await _wait_for(func() -> bool: return not get_tree().get_nodes_in_group(&"enemies").is_empty(), 15.0):
		_fail("the host's hound never appeared on the client")
		return
	print("client: hound arrived, fighting it")
	var enemy := get_tree().get_nodes_in_group(&"enemies")[0] as Enemy
	var dead := [false]
	enemy.died.connect(func(_enemy: Enemy) -> void: dead[0] = true)
	var health_seen := [enemy.health.current]
	enemy.health.changed.connect(func(current: float, _maximum: float) -> void: health_seen[0] = current)
	var fought := await _wait_for(func() -> bool:
		if dead[0]:
			return true
		TestBot.swing_only(player)
		return false, 20.0)
	TestBot.stop(player)
	_check(fought, "the client killed the host's hound")
	_check(health_seen[0] < enemy.data.max_health, "the hound's health drop reached the client")

	var scrap := enemy.data.drops[0].item
	await _wait_for(func() -> bool: return player.inventory.get_count(scrap) > 0, 4.0)
	_check(player.inventory.get_count(scrap) > 0, "the client collected its own loot")
	await _wait_for(func() -> bool: return get_tree().get_nodes_in_group(&"enemies").is_empty(), 4.0)
	_check(get_tree().get_nodes_in_group(&"enemies").is_empty(), "the dead hound was removed on the client")


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
