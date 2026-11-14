class_name Chaser
extends Enemy
## An enemy that runs at the nearest player, warns, then lunges.
##
## Its "brain" is a small state machine:
##   CHASE   - run toward the player until close enough
##   WINDUP  - stop and show a warning line (the "telegraph") so the player can react
##   LUNGE   - dash forward in a straight line; touching the player deals damage
##   RECOVER - pause, giving the player an opening
## The lunge direction keeps tracking the player during the windup and locks just
## before the lunge, so walking away is not enough but a dash or sidestep is.

enum Brain { CHASE, WINDUP, LUNGE, RECOVER }

const ACCELERATION := 600.0
const FRICTION := 900.0
## The lunge direction stops tracking the player this many seconds before the lunge.
const AIM_LOCK_TIME := 0.15
const TELEGRAPH_COLOR := Color(1.0, 0.25, 0.3)

var _chaser: ChaserData
var _brain := Brain.CHASE
var _brain_time := 0.0
var _lunge_direction := Vector2.RIGHT
var _aim_locked := false
var _telegraph_tween: Tween

@onready var _hitbox: Hitbox = $Hitbox


func _ready() -> void:
	super()
	_chaser = data as ChaserData
	assert(_chaser != null, "Chaser needs a ChaserData resource.")


func _think(delta: float) -> void:
	var target := find_target()
	match _brain:
		Brain.CHASE:
			_chase(target, delta)
		Brain.WINDUP:
			_windup(target, delta)
		Brain.LUNGE:
			velocity = _lunge_direction * _chaser.lunge_speed
			_brain_time -= delta
			if _brain_time <= 0.0:
				_hitbox.deactivate()
				_set_brain(Brain.RECOVER, _chaser.recovery)
		Brain.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
			_brain_time -= delta
			if _brain_time <= 0.0:
				_set_brain(Brain.CHASE, 0.0)
	queue_redraw()


func _chase(target: Player, delta: float) -> void:
	if target == null:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		return
	var to_target := target.global_position - global_position
	if to_target.length() <= _chaser.attack_range and can_see(target.global_position):
		_lunge_direction = _direction_or_default(to_target)
		_start_windup()
	else:
		steer_toward(target.global_position, data.move_speed, ACCELERATION, delta)


func _start_windup() -> void:
	_set_brain(Brain.WINDUP, _chaser.windup)
	_aim_locked = false
	# Squash down like a spring being compressed.
	_telegraph_tween = create_tween()
	_telegraph_tween.tween_property(visual, "scale", Vector2(1.3, 0.75), _chaser.windup)


func _windup(target: Player, delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	if _brain_time > AIM_LOCK_TIME:
		if target != null:
			_lunge_direction = _direction_or_default(target.global_position - global_position)
	elif not _aim_locked:
		# Direction is now fixed. Flash white as the "dodge now" cue.
		_aim_locked = true
		visual.flash(AIM_LOCK_TIME)
	_brain_time -= delta
	if _brain_time <= 0.0:
		_reset_telegraph()
		_set_brain(Brain.LUNGE, _chaser.lunge_duration)
		velocity = _lunge_direction * _chaser.lunge_speed
		_hitbox.activate(
			_chaser.damage, _chaser.attack_knockback, _chaser.attack_hit_stop, self
		)


## What the enemy is doing right now.
func get_brain() -> Brain:
	return _brain


## True during the last moment of the windup, when the lunge direction is fixed.
func is_lunge_locked() -> bool:
	return _brain == Brain.WINDUP and _aim_locked


func get_lunge_direction() -> Vector2:
	return _lunge_direction


func _can_be_interrupted() -> bool:
	return not (_chaser.committed_windup and _brain == Brain.WINDUP)


func _on_interrupted() -> void:
	_hitbox.deactivate()
	_reset_telegraph()
	_set_brain(Brain.CHASE, 0.0)
	queue_redraw()


func _set_brain(brain: Brain, duration: float) -> void:
	_brain = brain
	_brain_time = duration


func _reset_telegraph() -> void:
	if _telegraph_tween != null:
		_telegraph_tween.kill()
		_telegraph_tween = null
	visual.scale = Vector2.ONE


func _direction_or_default(offset: Vector2) -> Vector2:
	return offset.normalized() if offset != Vector2.ZERO else _lunge_direction


## Draws the warning line showing where the lunge will go.
func _draw() -> void:
	if _chaser == null or _dead or _brain != Brain.WINDUP:
		return
	var progress := 1.0 - _brain_time / maxf(_chaser.windup, 0.001)
	var length := _chaser.lunge_speed * _chaser.lunge_duration
	var color := TELEGRAPH_COLOR
	color.a = 0.2 + 0.6 * progress
	draw_line(Vector2.ZERO, _lunge_direction * length, color, 1.0)
