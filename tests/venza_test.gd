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
	await _test_abilities()
	await _test_zenith()
	await _test_grapple()


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
	# A new player carries two starter weapons; free a slot so the pistols go in hand.
	var one_slot: Array[WeaponData] = [_player.loadout[0]]
	_player.set_loadout(one_slot)
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
	await _fire_for(60, Vector2.LEFT)
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


func _spawn_ready(at: Vector2) -> Enemy:
	var enemy := _arena.spawn_enemy(HOUND, at)
	await _frames(int(Enemy.SPAWN_TIME * 60.0) + 2)
	return enemy


func _clear_enemies() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if not enemy.is_dead():
			enemy.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(20)


func _test_abilities() -> void:
	print("Abilities")
	var abilities := _player.abilities
	_check(abilities.abilities.size() == 3 and abilities.zenith != null, "Venza has three abilities and a Zenith")
	_place(Vector2(200.0, 192.0))

	# 1: Speed Boost
	_check(abilities.use(0), "Boost starts")
	_check(is_equal_approx(_player.get_speed_multiplier(), 1.6) and _player.has_flag(Player.FLAG_BOOSTED), "Boost raises speed by 60%")
	_check(not abilities.use(0) and is_equal_approx(_player.get_speed_multiplier(), 1.6), "Boost cannot be stacked or reused while active")
	_player.input.move = Vector2.RIGHT
	await _frames(30)
	_check(_player.velocity.length() > _player.max_speed * 1.55, "boosted running is faster (%.0f)" % _player.velocity.length())
	_player.input.move = Vector2.ZERO
	await _frames(int(abilities.get_ability(0).data.duration * 60.0))
	_check(is_equal_approx(_player.get_speed_multiplier(), 1.0) and not _player.has_flag(Player.FLAG_BOOSTED), "Boost ends and speed returns to normal")
	_check(not abilities.use(0), "Boost is on cooldown afterwards")

	# 2: Fade (invisibility)
	_place(Vector2(200.0, 192.0))
	var hound := await _spawn_ready(Vector2(240.0, 192.0))
	_check(hound.find_target() == _player, "an enemy targets the visible player")
	_check(abilities.use(1), "Fade starts")
	_check(_player.has_flag(Player.FLAG_INVISIBLE) and hound.find_target() == null, "an invisible player is not chosen as a target")
	await _frames(30)
	_check(_player.modulate.a < 0.5, "she is drawn faded")
	_player.input.press_attack()
	await _frames(3)
	_check(not _player.has_flag(Player.FLAG_INVISIBLE) and hound.find_target() == _player, "attacking ends Fade and enemies see her again")
	abilities.get_ability(1)._cooldown_left = 0.0
	abilities.use(1)
	# Hits she takes freeze her briefly (hit-stop), which also pauses ability timers.
	await _until(func() -> bool: return not abilities.get_ability(1).is_active(), int(abilities.get_ability(1).data.duration * 60.0) + 120)
	await _frames(2)
	_check(not _player.has_flag(Player.FLAG_INVISIBLE) and _player.modulate.a > 0.99, "Fade wears off on its own")
	await _clear_enemies()

	# 3: Rush (dash attack) through three enemies
	_player.remove_from_group(&"players")
	_place(Vector2(200.0, 192.0))
	var line: Array[Enemy] = []
	for x: float in [230.0, 255.0, 280.0]:
		line.append(_arena.spawn_enemy(HOUND, Vector2(x, 192.0)))
	await _frames(int(Enemy.SPAWN_TIME * 60.0) + 2)
	_player.input.move = Vector2.RIGHT
	var start_x := _player.global_position.x
	_check(abilities.use(2), "Rush starts")
	_check(_player.is_in_custom_motion() and _player.hurtbox.invulnerable, "she is untouchable during Rush")
	await _frames(25)
	var each_once := true
	for enemy in line:
		each_once = each_once and is_equal_approx(enemy.health.current, HOUND.max_health - 20.0)
	_check(each_once, "Rush hits each enemy in its path exactly once")
	_check(_player.global_position.x - start_x > 85.0, "Rush carries her about 95 px (%.0f)" % (_player.global_position.x - start_x))
	_player.input.move = Vector2.ZERO
	await _clear_enemies()

	_place(Vector2(620.0, 192.0))
	abilities.get_ability(2)._cooldown_left = 0.0
	_player.input.move = Vector2.RIGHT
	abilities.use(2)
	await _frames(25)
	_check(_player.global_position.x < 640.0, "Rush cannot pass through a wall")
	_player.input.move = Vector2.ZERO
	_player.add_to_group(&"players")
	await _frames(10)


func _test_zenith() -> void:
	print("Zenith")
	var abilities := _player.abilities
	_player.remove_from_group(&"players")
	_place(Vector2(320.0, 192.0))
	abilities.set_zenith_charge(0.0)
	_check(not abilities.use(3), "Zenith cannot start without charge")

	var hound := await _spawn_ready(Vector2(360.0, 192.0))
	_player.input.aim_direction = Vector2.RIGHT
	_player.input.attack_held = true
	await _until(func() -> bool: return hound.is_dead(), 240)
	_player.input.attack_held = false
	_check(is_equal_approx(abilities.zenith_charge, HOUND.zenith_value), "a pistol kill gives full charge (%.1f)" % abilities.zenith_charge)
	_check(abilities.get_zenith_charge_hint() == "", "no hint while holding the pistols")
	await _frames(20)

	_player.equip(_player.weapons[0])
	_check(abilities.get_zenith_charge_hint().contains("Only Twin Sparrows kills"), "holding another weapon shows a hint")
	hound = await _spawn_ready(Vector2(345.0, 192.0))
	_player.input.attack_held = true
	await _until(func() -> bool: return hound.is_dead(), 240)
	_player.input.attack_held = false
	_check(is_equal_approx(abilities.zenith_charge, HOUND.zenith_value), "a kill with another weapon gives nothing (%.1f)" % abilities.zenith_charge)
	await _frames(20)
	hound = await _spawn_ready(Vector2(345.0, 150.0))
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(5)
	_check(is_equal_approx(abilities.zenith_charge, HOUND.zenith_value * 1.5), "a kill by someone else gives half (%.1f)" % abilities.zenith_charge)

	# Without the pistols in either slot, the hint points to the Armory.
	var saved_loadout := _player.loadout.duplicate()
	var no_pistols: Array[WeaponData] = [_player.weapons[0]]
	_player.set_loadout(no_pistols)
	_check(abilities.get_zenith_charge_hint().contains("Equip Twin Sparrows at the Armory"), "without the pistols carried, the hint says to equip them")
	_player.set_loadout(saved_loadout)
	_player.equip(PISTOLS)

	abilities.set_zenith_charge(100.0)
	await _frames(2)
	_check(_player.has_flag(Player.FLAG_ZENITH_READY), "a full bar makes the crown glow (Zenith ready)")
	var only_blade: Array[WeaponData] = [_player.weapons[0]]
	_player.set_loadout(only_blade)
	await _frames(2)
	_check(abilities.get_zenith_block_reason().begins_with("Equip Twin Sparrows") and not abilities.use(3), "Zenith needs the pistols in a slot")
	var both: Array[WeaponData] = [PISTOLS, _player.weapons[0]]
	_player.set_loadout(both)
	await _frames(2)
	_check(abilities.use(3), "Zenith starts with a full bar and the pistols carried")
	_check(is_equal_approx(abilities.zenith_charge, 0.0) and _player.has_flag(Player.FLAG_ZENITH_ACTIVE), "starting Zenith spends the charge")
	_check(_player.is_in_custom_motion() and _player.hurtbox.invulnerable, "she is frozen and untouchable while transforming")
	await _frames(30)
	_check(_player.weapon.data.id == &"venza_arm_blades", "the pistols become arm blades")
	_player.input.press_swap()
	await _frames(3)
	_check(_player.weapon.data.id == &"venza_arm_blades", "weapons cannot be swapped during Zenith")

	# Auto-lock: a hound behind a pillar is ignored; one in the open is lunged at.
	_place(Vector2(140.0, 112.0))
	await _spawn_ready(Vector2(215.0, 112.0))
	var blades := _player.weapon as ZenithBlades
	_check(blades.pick_target(Vector2.RIGHT) == null, "enemies behind walls are not locked onto")
	await _clear_enemies()
	_place(Vector2(320.0, 192.0))
	var target := await _spawn_ready(Vector2(390.0, 192.0))
	var second := await _spawn_ready(Vector2(390.0, 240.0))
	_check(blades.pick_target(Vector2.RIGHT) == target, "the enemy where she aims is chosen first")
	_player.input.aim_direction = Vector2.RIGHT
	_player.input.press_attack()
	await _frames(2)
	_check(_player.is_in_custom_motion(), "attacking lunges at the target")
	await _until(func() -> bool: return not _player.is_in_custom_motion(), 30)
	await _frames(8)
	_check(target.is_dead(), "the lunge ends in a slash that kills it")
	_check(is_equal_approx(abilities.zenith_charge, 0.0), "kills during Zenith give no charge")
	await _frames(15)
	_player.input.press_attack()
	await _frames(2)
	second.hurtbox.receive_hit(HitInfo.new(9999.0))
	var settled := await _until(func() -> bool: return not _player.is_in_custom_motion(), 30)
	_check(settled, "a target dying mid-lunge does not leave her stuck")
	await _clear_enemies()

	var zenith := abilities.zenith
	await _until(func() -> bool: return not zenith.is_active(), 60 * 11)
	_check(_player.weapon.data == PISTOLS, "the pistols return when Zenith ends")
	_check(not _player.has_flag(Player.FLAG_ZENITH_ACTIVE) and not _player.has_flag(Player.FLAG_ZENITH_READY), "the crown returns to normal")
	_check(not abilities.use(3), "the bar must be charged again")

	abilities.set_zenith_charge(100.0)
	abilities.use(3)
	await _frames(30)
	_player.hurtbox.invulnerable = false
	_player.hurtbox.receive_hit(HitInfo.new(10000000.0))
	await _frames(2)
	_check(not zenith.is_active() and _player.weapon.data == PISTOLS, "dying ends Zenith and gives the pistols back")
	_player.respawn(Vector2(320.0, 192.0))
	_player.health.setup(1000000.0)
	_player.add_to_group(&"players")
	await _frames(70)


func _test_grapple() -> void:
	print("Grapple")
	_player.set_character(load("res://characters/data/volt.tres") as CharacterData)
	_check(_player.passive == null and _player.abilities.abilities.is_empty(), "back to a character without Venza's kit")
	var anchor := Vector2(320.0, 112.0)
	_place(Vector2(250.0, 112.0))
	_player.input.aim_direction = Vector2.RIGHT
	_player.input.grapple_held = true
	await _frames(2)
	var grapple := _player.grapple
	_check(grapple.attached and _player.has_flag(Player.FLAG_GRAPPLING), "any character can grapple onto an anchor post")
	_check(absf(grapple.anchor.x - (anchor.x - 4.0)) < 1.5, "the hook catches on the post's surface")
	var length := grapple.rope_length
	var longest := 0.0
	var fastest := 0.0
	var clear := true
	_player.input.move = Vector2.UP
	for i in 150:
		await get_tree().physics_frame
		var offset := _player.global_position - grapple.anchor
		longest = maxf(longest, offset.length())
		fastest = maxf(fastest, _player.velocity.length())
		_player.input.move = offset.normalized().orthogonal()
		clear = clear and (absf(_player.global_position.x - anchor.x) > 8.0 or absf(_player.global_position.y - anchor.y) > 8.0)
	_check(longest <= length + 3.0, "the rope never stretches (%.0f of %.0f)" % [longest, length])
	_check(fastest > _player.max_speed * 1.5 and fastest <= grapple.max_swing_speed + 1.0, "swinging builds speed up to the cap (%.0f)" % fastest)
	_check(clear, "she never passes through the post")
	var before := _player.velocity.length()
	_player.input.grapple_held = false
	_player.input.move = Vector2.ZERO
	await _frames(1)
	_check(not grapple.attached and not _player.has_flag(Player.FLAG_GRAPPLING) and _player.state == Player.State.MOVE, "letting go releases the rope")
	_check(_player.velocity.length() >= before * 0.95, "releasing keeps the momentum (%.0f from %.0f)" % [_player.velocity.length(), before])
	await _frames(10)
	_check(_player.velocity.length() > _player.max_speed, "the launch carries for a moment (%.0f)" % _player.velocity.length())
	await _frames(60)

	_place(Vector2(320.0, 192.0))
	_player.input.aim_direction = Vector2(1.0, 0.35).normalized()
	_player.input.grapple_held = true
	await _frames(2)
	_check(not grapple.attached, "the hook misses when nothing is in range")
	_player.input.grapple_held = false
	await _frames(2)
