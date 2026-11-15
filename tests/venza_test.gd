extends Node
## Venza's base kit in the real arena with scripted input: Twin Sparrows pistols, skating,
## wall riding and trails. Run with tools\test.cmd:
##   godot --headless --fixed-fps 60 --path <project> res://tests/venza_test.tscn

const ARENA := preload("res://levels/test_arena/test_arena.tscn")
const VENZA := preload("res://characters/data/venza.tres")
const PISTOLS := preload("res://weapons/data/twin_sparrows.tres")
const HOUND := preload("res://enemies/data/scrap_hound.tres")

var _checks := 0
var _failures := 0
var _arena: Arena
var _player: Player
var _bullets: Array[int] = []
var _bullet_start: Dictionary = {}
var _bullet_end: Dictionary = {}


func _ready() -> void:
	await _run()
	print("VENZA TEST: %d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _run() -> void:
	_arena = ARENA.instantiate() as Arena
	_arena.auto_start = false
	add_child(_arena)
	await _frames(2)
	_player = _arena.local_player
	_player.input.use_device = false
	get_tree().node_added.connect(_on_node_added)
	await _test_unlock()
	await _test_pistols()
	await _test_skating()
	await _test_wall_riding()
	await _test_trails()


func _on_node_added(node: Node) -> void:
	var bullet := node as Projectile
	if bullet == null:
		return
	var id := bullet.get_instance_id()
	_bullets.append(id)
	bullet.tree_exiting.connect(func() -> void: _bullet_end[id] = bullet.global_position)
	(func() -> void:
		if is_instance_valid(bullet):
			_bullet_start[id] = bullet.global_position
	).call_deferred()


func _place(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.input.move = Vector2.ZERO
	_player.input.skate_held = false
	_player.input.attack_held = false


func _test_unlock() -> void:
	print("Unlocking Venza")
	_player.unlock_character(VENZA)
	_player.set_character(VENZA)
	_check(_player.character == VENZA, "Venza can be played once unlocked")
	_check(_player.passive is Skating, "Venza has the skating passive")
	_check(_player.owns_weapon(PISTOLS), "unlocking Venza grants the Twin Sparrows")
	_check(_player.weapon != null and _player.weapon.data == PISTOLS, "the pistols go into the free slot and are equipped")
	_check(is_equal_approx(_player.health.max_health, VENZA.max_health), "Venza uses her own health")
	_player.health.setup(1000000.0)


func _fire_for(frames: int, aim: Vector2) -> void:
	_player.input.aim_direction = aim
	_player.input.attack_held = true
	await _frames(frames)
	_player.input.attack_held = false
	await _frames(40)


func _test_pistols() -> void:
	print("Twin Sparrows")
	_player.remove_from_group(&"players")
	_place(Vector2(320.0, 192.0))
	_bullets.clear()
	await _fire_for(60, Vector2.UP)
	var expected := 1.0 / PISTOLS.fire_interval
	_check(absf(_bullets.size() - expected) <= 2.0, "about %d shots per second while held (got %d)" % [roundi(expected), _bullets.size()])
	var longest := 0.0
	for id: int in _bullets:
		if _bullet_start.has(id) and _bullet_end.has(id):
			longest = maxf(longest, (_bullet_end[id] as Vector2).distance_to(_bullet_start[id]))
	_check(absf(longest - PISTOLS.projectile_range) < 15.0, "bullets fizzle at their range (%.0f of %.0f px)" % [longest, PISTOLS.projectile_range])

	_place(Vector2(610.0, 192.0))
	_bullets.clear()
	await _fire_for(20, Vector2.RIGHT)
	var through := false
	for id: int in _bullets:
		through = through or (_bullet_end.has(id) and (_bullet_end[id] as Vector2).x > 641.0)
	_check(not _bullets.is_empty() and not through, "bullets stop at walls")

	_place(Vector2(320.0, 192.0))
	var hound := _arena.spawn_enemy(HOUND, Vector2(320.0, 150.0))
	await _frames(int(Enemy.SPAWN_TIME * 60.0) + 2)
	var start_health := hound.health.current
	var staggered := [false]
	_player.input.aim_direction = Vector2.UP
	_player.input.attack_held = true
	for i in 20:
		await get_tree().physics_frame
		staggered[0] = staggered[0] or hound._stagger > 0.0
	_player.input.attack_held = false
	var lost := start_health - hound.health.current
	_check(lost > 0.0 and is_equal_approx(fmod(lost, PISTOLS.damage), 0.0), "each bullet deals %.0f damage (lost %.0f)" % [PISTOLS.damage, lost])
	_check(not staggered[0], "a stream of bullets never stuns the enemy")
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(40)
	_player.add_to_group(&"players")


func _test_skating() -> void:
	print("Skating")
	_place(Vector2(60.0, 192.0))
	_player.input.move = Vector2.RIGHT
	await _frames(45)
	var running := _player.velocity.length()
	_check(absf(running - _player.max_speed) < 1.0, "without Skate she runs at normal speed")
	_player.input.skate_held = true
	await _frames(45)
	var skating := _player.velocity.length()
	_check(skating > _player.max_speed * 1.45, "skating is much faster than running (%.0f vs %.0f)" % [skating, running])
	_check(_player.has_flag(Player.FLAG_SKATING), "the skating flag is set for teammates to see")
	_player.input.move = Vector2.ZERO
	await _frames(15)
	_check(_player.velocity.length() > _player.max_speed * 1.15, "letting go of direction keys coasts instead of stopping (%.0f)" % _player.velocity.length())
	_player.input.skate_held = false
	var coasting := _player.velocity.length()
	await _frames(3)
	var after := _player.velocity.length()
	_check(after < coasting and after > _player.max_speed, "releasing Skate bleeds the extra speed off gradually (%.0f to %.0f)" % [coasting, after])
	await _frames(60)
	_check(_player.velocity.length() < 1.0, "she comes to a stop")
	_check(not _player.has_flag(Player.FLAG_SKATING), "the skating flag clears")


func _skating() -> Skating:
	return _player.passive as Skating


func _test_wall_riding() -> void:
	print("Wall riding")
	_place(Vector2(320.0, 40.0))
	_player.input.skate_held = true
	_player.input.move = Vector2(0.6, -0.8)
	var rode := await _until(func() -> bool: return _skating().riding, 90)
	_check(rode, "skating into a wall starts a wall ride")
	_check(_player.has_flag(Player.FLAG_WALL_RIDING), "the wall-riding flag is set")
	var fastest := 0.0
	var riding_frames := 0
	var inside := true
	for i in 600:
		await get_tree().physics_frame
		if _skating().riding:
			riding_frames += 1
			fastest = maxf(fastest, _skating()._ride_speed)
		var at := _player.global_position
		inside = inside and at.x > -1.0 and at.x < 641.0 and at.y > -1.0 and at.y < 385.0
	_check(fastest <= _skating().wall_ride_max_speed + 0.5, "riding speed is capped (fastest %.0f)" % fastest)
	_check(fastest > _skating().wall_ride_min_speed, "riding builds speed")
	_check(inside, "she never leaves the arena through a wall")
	_check(riding_frames > 60, "she keeps riding along walls and round corners (%d frames)" % riding_frames)

	_place(Vector2(320.0, 40.0))
	_player.input.skate_held = true
	_player.input.move = Vector2(0.6, -0.8)
	await _until(func() -> bool: return _skating().riding, 90)
	await _frames(10)
	var normal := _skating().get_wall_normal()
	_player.input.press_dash()
	await _frames(2)
	_check(not _skating().riding, "dashing leaves the wall")
	_check(_player.velocity.normalized().dot(normal) > 0.3, "the dash kicks off away from the wall")
	await _frames(30)

	# The top edge of the north-west pillar is 32 px long: ride it and run off the end.
	_place(Vector2(166.0, 86.0))
	_player.input.skate_held = true
	_player.input.move = Vector2(0.6, 0.8)
	var on_pillar := await _until(func() -> bool: return _skating().riding, 30)
	_check(on_pillar, "she rides the top of a pillar")
	var left := await _until(func() -> bool: return not _skating().riding, 90)
	_check(left, "the ride ends when the wall ends")
	_check(_player.velocity.length() > _player.max_speed, "she keeps her speed off the end of the wall (%.0f)" % _player.velocity.length())
	_place(Vector2(320.0, 192.0))
	await _frames(30)


func _test_trails() -> void:
	print("Trails")
	_place(Vector2(60.0, 192.0))
	_player.input.skate_held = true
	_player.input.move = Vector2.RIGHT
	var trails := _player.passive.find_children("*", "Trail", true, false)
	var most := 0
	for i in 120:
		await get_tree().process_frame
		for trail: Trail in trails:
			most = maxi(most, trail.get_point_count())
		if _player.global_position.x > 560.0:
			_player.input.move = Vector2.LEFT
		elif _player.global_position.x < 80.0:
			_player.input.move = Vector2.RIGHT
	_check(trails.size() == 2 and most > 3, "two trails follow her while skating")
	_check(most <= (trails[0] as Trail).max_points, "trail length stays capped (%d points)" % most)
	_player.input.skate_held = false
	_player.input.move = Vector2.ZERO
	await get_tree().create_timer(1.0).timeout
	var left_over := 0
	for trail: Trail in trails:
		left_over += trail.get_point_count()
	_check(left_over == 0, "trails fade away after she stops skating")
