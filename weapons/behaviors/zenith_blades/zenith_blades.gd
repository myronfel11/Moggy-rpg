class_name ZenithBlades
extends MeleeSwing
## Venza's Zenith arm blades. An attack locks onto a nearby enemy, lunges to it and slashes;
## holding attack chains from target to target. With nothing in range it is a fast slash
## where she aims, so the player stays in control.
##
## Targets must be alive, within lock_radius, and have no wall between her and them. The
## lunge uses normal collision (custom motion), so it can never pass through walls. A
## target that dies or moves away mid-lunge is replaced by the next valid one, or the
## lunge ends in a slash where she is.

var _blades: ZenithBladesData
var _target: Enemy
var _last_struck: Enemy
var _lunging := false
var _lunge_time := 0.0


func _on_setup() -> void:
	super()
	_blades = data as ZenithBladesData


func try_attack(aim_direction: Vector2) -> bool:
	if _phase != Phase.READY or _lunging:
		return false
	# Other peers' copies only show the slash; the owner does the lunging.
	if deals_damage:
		var target := pick_target(aim_direction)
		if target != null:
			_start_lunge(target)
			return true
	return super(aim_direction)


func is_busy() -> bool:
	return _lunging or super()


func cancel() -> void:
	if _lunging:
		_lunging = false
		if is_instance_valid(wielder) and wielder.is_in_custom_motion():
			wielder.end_custom_motion()
	super()


## The best enemy to lunge at, or null. Prefers the nearest one roughly where she aims,
## then the nearest overall; skips the one just struck when there is another choice.
func pick_target(aim_direction: Vector2) -> Enemy:
	var candidates: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or enemy.hurtbox.invulnerable:
			continue
		if enemy.global_position.distance_to(wielder.global_position) > _blades.lock_radius:
			continue
		if not _clear_line_to(enemy.global_position):
			continue
		candidates.append(enemy)
	if candidates.size() > 1 and is_instance_valid(_last_struck):
		candidates.erase(_last_struck)
	var best: Enemy = null
	var best_distance := INF
	var max_angle := deg_to_rad(_blades.lock_angle)
	for preferring_aim: bool in [true, false]:
		for enemy in candidates:
			var offset := enemy.global_position - wielder.global_position
			if preferring_aim and absf(aim_direction.angle_to(offset)) > max_angle:
				continue
			if offset.length() < best_distance:
				best_distance = offset.length()
				best = enemy
		if best != null:
			return best
	return null


## True if no wall lies between the wielder and [param point].
func _clear_line_to(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(wielder.global_position, point, Layers.WORLD)
	return wielder.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _start_lunge(target: Enemy) -> void:
	_target = target
	_lunging = true
	_lunge_time = 0.0
	wielder.grant_invulnerability(_blades.lunge_max_time + 0.1)
	(wielder as Player).begin_custom_motion(_lunge_step)
	queue_redraw()


func _lunge_step(delta: float) -> bool:
	if not _lunging:
		return false
	_lunge_time += delta
	if not is_instance_valid(_target) or _target.is_dead():
		_target = pick_target(wielder.velocity.normalized() if wielder.velocity.length() > 1.0 else Vector2.RIGHT)
		if _target == null:
			_finish_lunge(wielder.velocity.normalized() if wielder.velocity.length() > 1.0 else Vector2.RIGHT)
			return false
	var offset := _target.global_position - wielder.global_position
	var distance := offset.length()
	var direction := offset / distance if distance > 0.001 else Vector2.RIGHT
	if distance <= _blades.stop_distance or _lunge_time >= _blades.lunge_max_time:
		_finish_lunge(direction)
		return false
	if _lunge_time > 0.05 and wielder.get_slide_collision_count() > 0 and wielder.get_real_velocity().length() < _blades.lunge_dash_speed * 0.3:
		# Blocked by a wall: stop and slash rather than grinding against it.
		_finish_lunge(direction)
		return false
	wielder.velocity = direction * _blades.lunge_dash_speed
	return true


func _finish_lunge(direction: Vector2) -> void:
	_lunging = false
	if is_instance_valid(_target) and not _target.is_dead():
		_last_struck = _target
	wielder.velocity = direction * (wielder as Player).max_speed
	(wielder as Player).weapon_pivot.rotation = direction.angle()
	super.try_attack(direction)


func _draw() -> void:
	super()
	if _lunging and _swing != null:
		# A blade trail along the lunge.
		draw_line(Vector2(-14.0, 0.0), Vector2(_swing.reach * 0.6, 0.0), Color(_swing.color, 0.6), 3.0)
