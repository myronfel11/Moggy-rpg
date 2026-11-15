class_name Skating
extends CharacterPassive
## Venza's passive: energy skating.
##
## Hold Skate (Shift) while moving to skate: a higher top speed, and instead of snapping to
## the input direction she carves toward it, keeping her speed through turns. Let go of
## the direction keys and she coasts. She can shoot the whole time.
##
## Wall riding (the top-down version of wall skating): skate into a wall and she locks
## onto it, riding along it and gaining speed up to a cap. Corners carry her onto the next
## wall. She leaves the wall when Skate is released, when steering away from it, when the
## wall ends (keeping her speed), or by dashing, which kicks her off the wall.
##
## Glowing trails follow her while skating; they are visual only.

@export_group("Skating")
## Cruising speed while skating, in pixels per second (running is 120).
@export var skate_speed := 190.0
## How quickly she gets up to skating speed.
@export var skate_acceleration := 520.0
## How fast she can turn while skating, in radians per second. Lower is wider carves.
@export var turn_rate := 7.0
## Slow-down when no direction is held, or when above cruising speed.
@export var coast_friction := 140.0
## Extra slow-down when steering almost straight backwards.
@export var brake_friction := 700.0

@export_group("Wall riding")
## Speed gained per second while riding a wall.
@export var wall_ride_acceleration := 140.0
## Riding never gets faster than this.
@export var wall_ride_max_speed := 300.0
## Riding starts at least this fast.
@export var wall_ride_min_speed := 150.0
## Steering away from the wall by more than this (0 to 1) leaves it.
@export var wall_leave_threshold := 0.45
## Share of speed kept when a corner carries her onto the next wall.
@export var corner_speed_keep := 0.8

var riding := false

var _active := false
var _wall_normal := Vector2.ZERO
var _tangent := Vector2.ZERO
var _ride_speed := 0.0
var _off_wall_frames := 0

@onready var _trails: Array[Trail] = [$TrailLeft, $TrailRight]


func setup(p_player: Player) -> void:
	super(p_player)
	for trail in _trails:
		trail.follow(player)


func is_skating() -> bool:
	return _active


func get_wall_normal() -> Vector2:
	return _wall_normal


func handle_movement(delta: float) -> bool:
	var input := player.input
	if not input.skate_held:
		_set_state(false, false)
		return false
	_active = true
	var multiplier := player.get_speed_multiplier()
	if riding:
		_ride(delta, multiplier)
	else:
		_skate(delta, multiplier)
	_set_state(true, riding)
	return true


func after_move(_delta: float) -> void:
	if not _active:
		return
	if riding:
		_check_wall_contact()
	else:
		_try_start_ride()


func dash_direction_override() -> Vector2:
	if not riding:
		return Vector2.ZERO
	var kick := (_wall_normal * 0.75 + _tangent * 0.65).normalized()
	_leave_wall(false)
	return kick


func interrupt() -> void:
	_leave_wall(false)
	_set_state(false, false)


func _skate(delta: float, multiplier: float) -> void:
	var velocity := player.velocity
	var direction := player.input.move
	var target_speed := skate_speed * multiplier
	if player.weapon != null:
		target_speed *= player.weapon.get_move_speed_multiplier()
	if direction.length() < 0.1:
		player.velocity = velocity.move_toward(Vector2.ZERO, coast_friction * delta)
		return
	direction = direction.normalized()
	var speed := velocity.length()
	if speed < 1.0:
		velocity = direction
	# Carve: turn the current velocity toward the wanted direction at a limited rate.
	var angle := velocity.angle_to(direction)
	var max_turn := turn_rate * delta
	velocity = velocity.rotated(clampf(angle, -max_turn, max_turn))
	if speed < target_speed:
		speed = minf(target_speed, speed + skate_acceleration * delta)
	else:
		speed = move_toward(speed, target_speed, coast_friction * delta)
	if absf(angle) > 2.6:
		speed = maxf(0.0, speed - brake_friction * delta)
	player.velocity = velocity.normalized() * speed


func _ride(delta: float, multiplier: float) -> void:
	if player.input.move.dot(_wall_normal) > wall_leave_threshold:
		# Steering away: peel off the wall with a bit of push.
		var leave := _tangent * _ride_speed + _wall_normal * _ride_speed * 0.3
		_leave_wall(false)
		player.velocity = leave
		return
	_ride_speed = minf(_ride_speed + wall_ride_acceleration * delta, wall_ride_max_speed * multiplier)
	# A light push into the wall keeps her touching it, so the slide confirms contact.
	player.velocity = _tangent * _ride_speed - _wall_normal * 30.0


func _try_start_ride() -> void:
	var push := player.input.move
	if push.length() < 0.1:
		return
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		var normal := collision.get_normal()
		if push.normalized().dot(-normal) < 0.2:
			continue
		_wall_normal = normal
		_tangent = normal.orthogonal()
		var along := push.dot(_tangent)
		if absf(along) < 0.05:
			along = player.velocity.dot(_tangent)
		if along < 0.0:
			_tangent = -_tangent
		_ride_speed = maxf(player.velocity.length(), wall_ride_min_speed)
		riding = true
		_off_wall_frames = 0
		_set_state(true, true)
		return


func _check_wall_contact() -> void:
	var touching := false
	for i in player.get_slide_collision_count():
		var normal := player.get_slide_collision(i).get_normal()
		if normal.dot(_wall_normal) > 0.7:
			touching = true
		elif normal.dot(_wall_normal) < 0.5 and normal.dot(_tangent) < -0.5:
			# A wall straight ahead: carry over onto it, heading away from the old wall.
			var old_normal := _wall_normal
			_wall_normal = normal
			_tangent = normal.orthogonal()
			if _tangent.dot(old_normal) < 0.0:
				_tangent = -_tangent
			_ride_speed *= corner_speed_keep
			touching = true
			break
	if touching:
		_off_wall_frames = 0
		return
	_off_wall_frames += 1
	if _off_wall_frames >= 2:
		# The wall ended: keep going at riding speed.
		var keep := _tangent * _ride_speed
		_leave_wall(false)
		player.velocity = keep


func _leave_wall(_keep: bool) -> void:
	riding = false
	_off_wall_frames = 0


func _set_state(skating: bool, on_wall: bool) -> void:
	_active = skating
	if player.is_local():
		player.set_flag(Player.FLAG_SKATING, skating)
		player.set_flag(Player.FLAG_WALL_RIDING, on_wall)


func _process(_delta: float) -> void:
	if player == null:
		return
	# Every peer draws trails from the synced flags, so teammates see them too.
	var skating := player.has_flag(Player.FLAG_SKATING) and player.is_alive()
	var on_wall := player.has_flag(Player.FLAG_WALL_RIDING)
	for trail in _trails:
		trail.emitting = skating
		trail.width = 3.0 if on_wall else 2.0
