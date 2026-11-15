extends Node
## "The Three Pillars" boss encounter, offline, with shortened timings so it runs quickly.
## Run with tools\test.cmd:
##   godot --headless --fixed-fps 60 --path <project> res://tests/boss_test.tscn

const ARENA := preload("res://bosses/three_pillars/boss_arena.tscn")
const DATA := preload("res://bosses/three_pillars/data/three_pillars.tres")
const BALL := "res://bosses/three_pillars/tracking_ball.tscn"

var _checks := 0
var _failures := 0
var _arena: BossArena
var _encounter: BossEncounter
var _data: ThreePillarsData
var _player: Player


func _ready() -> void:
	await _run()
	print("BOSS TEST: %d checks, %d failed" % [_checks, _failures])
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
	_data = DATA.duplicate() as ThreePillarsData
	_data.intro_time = 0.1
	_data.acquire_time = 0.3
	_data.charge_time = 0.6
	_data.lock_time = 0.3
	_data.recover_time = 0.3
	_data.idle_time = 0.4
	_data.revive_delay = 0.5
	_data.ball_lifetime = 3.0
	_data.pickup_hold = 0.5
	_data.slam_hold = 0.5
	_data.gate_time = 0.5
	_arena = ARENA.instantiate() as BossArena
	_encounter = _arena.get_node(^"Encounter") as BossEncounter
	_encounter.data = _data
	_encounter.auto_start = false
	_arena.mission_path = "res://missions/data/three_pillars.tres"
	add_child(_arena)
	await _frames(2)
	_player = _arena.local_player
	_player.input.use_device = false
	await _test_start()
	await _test_laser()
	await _test_balls_and_pillars()
	await _test_failure()


func _place(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.input.move = Vector2.ZERO


func _boss() -> PillarBoss:
	return _encounter.boss


func _test_start() -> void:
	print("Start")
	_check(_encounter.state == BossEncounter.State.ENCOUNTER_START, "the encounter waits in ENCOUNTER_START")
	_check(not _encounter.set_state(BossEncounter.State.DAMAGE_PHASE_1) and _encounter.state == BossEncounter.State.ENCOUNTER_START, "an illegal jump to a damage phase is refused")
	_check(not BossEncounter.can_transition(BossEncounter.State.BOSS_DEFEATED, BossEncounter.State.SHIELDED_MECHANICS), "nothing can follow BOSS_DEFEATED")
	_encounter.begin()
	await _frames(2)
	_check(_encounter.state == BossEncounter.State.SHIELDED_MECHANICS, "the fight starts in SHIELDED_MECHANICS")
	_check(is_instance_valid(_boss()), "the boss is in the centre")
	var shielded := 0
	for sentinel in _encounter.sentinels:
		if is_instance_valid(sentinel) and sentinel.shielded:
			shielded += 1
		sentinel._fire_left = 999.0
	_check(shielded == 3, "three shielded sentinels spawn")
	var standing := 0
	for pillar in _encounter.get_pillars():
		if pillar.intact:
			standing += 1
		_check(pillar.get_node_or_null(^"Hurtbox") == null, "pillar %d has no hurtbox, so weapons cannot touch it" % pillar.slot)
	_check(standing == 3, "three pillars stand")
	await _frames(int(Enemy.SPAWN_TIME * 60.0) + 3)
	var boss_health := _boss().health.current
	_check(not _boss().hurtbox.receive_hit(HitInfo.new(100.0)) and _boss().health.current == boss_health, "the shielded boss takes no damage")
	var sentinel := _encounter.sentinels[1]
	var sentinel_health := sentinel.health.current
	_check(not sentinel.hurtbox.receive_hit(HitInfo.new(100.0)) and sentinel.health.current == sentinel_health, "a shielded sentinel takes no damage")
	_check(is_equal_approx(_encounter.get_shield_ratio(), 1.0), "the boss shield starts full")


func _wait_phase(phase: PillarBoss.Laser, max_frames := 600) -> bool:
	return await _until(func() -> bool: return _boss().laser_phase == phase, max_frames)


func _test_laser() -> void:
	print("Sniper laser")
	_player.health.setup(1000000.0)
	_place(Vector2(250.0, 450.0))
	_check(await _wait_phase(PillarBoss.Laser.ACQUIRE), "the boss picks a target")
	_check(_boss().laser_target_peer == _player.peer_id and _boss().is_charging_at(_player.peer_id), "the player is targeted (reticle and warning)")
	await _wait_phase(PillarBoss.Laser.CHARGE)
	var charge_start := Engine.get_physics_frames()
	var before := _boss().laser_dir
	_place(Vector2(300.0, 450.0))
	await _frames(5)
	_check(_boss().laser_dir.angle_to(before) != 0.0, "while charging the line follows the player")
	await _wait_phase(PillarBoss.Laser.LOCK)
	var charge_frames := Engine.get_physics_frames() - charge_start
	_check(absi(charge_frames - roundi(_data.charge_time * 60.0)) <= 2, "charging lasts the configured time (%d frames)" % charge_frames)
	var locked := _boss().laser_dir
	_place(Vector2(320.0, 470.0))
	await _frames(5)
	_check(_boss().laser_dir == locked, "after LOCK the direction no longer follows")
	# The player stays in the beam: back on the locked line.
	_place(_boss().global_position + locked * 150.0)
	await _wait_phase(PillarBoss.Laser.FIRE)
	await _frames(2)
	_check(not _player.is_alive(), "standing in the beam is a one-hit kill")
	var revives := _encounter.revives_left
	_check(revives == _data.revive_pool - 1, "going down uses one revive from the shared pool")
	_check(await _until(func() -> bool: return _player.is_alive(), 120), "the player comes back after the revive delay")
	_player.health.setup(1000000.0)

	# Dodge: step out of the line during LOCK.
	await _wait_phase(PillarBoss.Laser.LOCK)
	_place(_boss().global_position + _boss().laser_dir * 150.0 + _boss().laser_dir.orthogonal() * 30.0)
	await _wait_phase(PillarBoss.Laser.RECOVER)
	_check(_player.is_alive(), "stepping out of the locked line avoids the beam")

	# Invulnerability (a dash) protects even inside the beam.
	await _wait_phase(PillarBoss.Laser.LOCK)
	_place(_boss().global_position + _boss().laser_dir * 150.0)
	_player.grant_invulnerability(1.0)
	await _wait_phase(PillarBoss.Laser.RECOVER)
	_check(_player.is_alive(), "dash invulnerability protects from the beam")
	await _frames(70)

	# Behind a pillar: the beam passes through walls.
	_place(Vector2(400.0, 525.0))
	await _wait_phase(PillarBoss.Laser.LOCK)
	_place(Vector2(400.0, 525.0))
	_player.hurtbox.invulnerable = false
	await _wait_phase(PillarBoss.Laser.RECOVER)
	_check(not _player.is_alive(), "hiding behind a pillar does not stop the beam")
	await _until(func() -> bool: return _player.is_alive(), 120)
	_player.health.setup(1000000.0)

	# Nobody to target while invisible.
	await _wait_phase(PillarBoss.Laser.IDLE)
	_player.set_flag(Player.FLAG_INVISIBLE, true)
	await _frames(90)
	_check(_boss().laser_target_peer == 0, "an invisible player is not targeted")
	_player.set_flag(Player.FLAG_INVISIBLE, false)
	_check(PillarBoss.in_beam(Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 10.0), 6.0), "the beam hits a body whose edge is in it")
	_check(not PillarBoss.in_beam(Vector2.ZERO, Vector2.RIGHT, Vector2(-50.0, 0.0), 6.0), "the beam does not hit behind the boss")


func _spawn_ball(slot: int, at: Vector2, heading: Vector2) -> TrackingBall:
	return _arena.spawn_scene(BALL, at, {"slot": slot, "target_peer": _player.peer_id, "direction": heading}) as TrackingBall


func _test_balls_and_pillars() -> void:
	print("Tracking balls and pillars")
	_boss().laser_enabled = false
	await _frames(5)
	_player.health.setup(1000000.0)

	# Turning is limited, so a ball can be led and out-turned.
	_place(Vector2(600.0, 300.0))
	var ball := _spawn_ball(1, Vector2(300.0, 300.0), Vector2.LEFT)
	var sharpest := 0.0
	var last := ball.direction
	for i in 40:
		await get_tree().physics_frame
		if not is_instance_valid(ball):
			break
		sharpest = maxf(sharpest, absf(last.angle_to(ball.direction)))
		last = ball.direction
	_check(sharpest <= _data.ball_turn_rate / 60.0 + 0.001, "a ball turns at most its turn rate (%.3f rad per frame)" % sharpest)
	if is_instance_valid(ball):
		ball.pop()
	await _frames(2)

	# A ball of another colour fizzles on a pillar and leaves it standing.
	_place(Vector2(400.0, 555.0))
	var wrong := _spawn_ball(2, Vector2(400.0, 430.0), Vector2.DOWN)
	await _gone(wrong, 60)
	_check(not is_instance_valid(wrong), "a ball of the wrong colour is destroyed on the pillar")
	_check(_encounter.get_slot(0) == BossEncounter.Slot.SHIELDED and _encounter.get_pillars()[0].intact, "the pillar survives a ball of the wrong colour")

	# The matching ball brings the pillar down and drops only its sentinel's shield.
	var right := _spawn_ball(0, Vector2(400.0, 430.0), Vector2.DOWN)
	await _gone(right, 60)
	await _frames(2)
	_check(_encounter.get_slot(0) == BossEncounter.Slot.VULNERABLE, "the matching ball destroys its pillar")
	_check(not _encounter.get_pillars()[0].intact, "the pillar shows as rubble")
	_check(not _encounter.sentinels[0].shielded and _encounter.sentinels[1].shielded and _encounter.sentinels[2].shielded, "only that pillar's sentinel loses its shield")
	var again := _spawn_ball(0, Vector2(400.0, 430.0), Vector2.DOWN)
	await _gone(again, 90)
	_check(_encounter.get_slot(0) == BossEncounter.Slot.VULNERABLE, "a second ball changes nothing")
	_encounter.on_ball_hit_pillar(0)
	_check(_encounter.get_slot(0) == BossEncounter.Slot.VULNERABLE, "a repeated pillar event changes nothing")

	var sentinel := _encounter.sentinels[0]
	var health := sentinel.health.current
	_check(sentinel.hurtbox.receive_hit(HitInfo.new(40.0)) and sentinel.health.current < health, "the exposed sentinel can be damaged")

	# A ball that reaches a player hurts them and disappears.
	_place(Vector2(600.0, 480.0))
	# Wait out any invulnerability from earlier hits (a ball passes through then).
	await _until(func() -> bool: return not _player.hurtbox.invulnerable, 120)
	var before := _player.health.current
	var chaser := _spawn_ball(1, Vector2(560.0, 480.0), Vector2.RIGHT)
	await _gone(chaser, 90)
	_check(is_equal_approx(before - _player.health.current, _data.ball_damage), "a ball that touches a player deals its damage")
	_check(not is_instance_valid(chaser), "the ball is gone after hitting a player")

	# A real sentinel shot follows the player.
	_place(Vector2(250.0, 470.0))
	var shot := _encounter.sentinels[2].fire()
	_check(shot != null and shot.target_peer == _player.peer_id, "a sentinel fires a ball at the player")
	_check(_encounter.sentinels[2].fire() != null and _encounter.sentinels[2].fire() == null, "each sentinel has at most %d balls out" % _data.max_balls_each)
	await _until(func() -> bool: return _encounter.count_balls(2) == 0, 60 * 4)
	_check(_encounter.count_balls(2) == 0, "balls fizzle at the end of their lifetime")

	sentinel.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(3)
	_check(_encounter.get_slot(0) == BossEncounter.Slot.BOMB_DROPPED, "defeating the exposed sentinel moves its slot on")

	# The real mechanic: stand behind a pillar, opposite its sentinel, and let the
	# sentinel's own ball fly past the boss into the pillar.
	var pillar := _encounter.get_pillars()[1]
	var sentinel_at := _encounter.sentinels[1].global_position
	_place(pillar.global_position + (pillar.global_position - sentinel_at).normalized() * 34.0)
	# This flight is long (about 4.5 s); use the real lifetime rather than the test's short one.
	_data.ball_lifetime = DATA.ball_lifetime
	var led := _encounter.sentinels[1].fire()
	_check(led != null, "the amber sentinel fires at the player behind the amber pillar")
	await _until(func() -> bool: return _encounter.get_slot(1) != BossEncounter.Slot.SHIELDED, 60 * 8)
	_check(_encounter.get_slot(1) == BossEncounter.Slot.VULNERABLE, "a ball led past the boss breaks its own pillar")


func _test_failure() -> void:
	print("Running out of revives")
	_encounter._revives.revives_left = 0
	_encounter.revives_left = 0
	_player.hurtbox.invulnerable = false
	_player.hurtbox.receive_hit(HitInfo.new(100000000.0))
	await _frames(3)
	_check(_encounter.state == BossEncounter.State.ENCOUNTER_FAILED, "everyone down with no revives fails the encounter")
	_check(_encounter.count_balls(0) + _encounter.count_balls(1) + _encounter.count_balls(2) == 0 and not _boss().laser_enabled, "attacks stop when the encounter fails")


## Waits until [param node] has been freed (by instance id, so nothing touches it after).
func _gone(node: Node, max_frames: int) -> void:
	var id := node.get_instance_id()
	await _until(func() -> bool: return instance_from_id(id) == null, max_frames)
