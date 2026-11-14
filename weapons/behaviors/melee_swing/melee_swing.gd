class_name MeleeSwing
extends WeaponBehavior
## A melee attack that hits everything inside an arc in front of the wielder.
##
## An attack moves through phases: WINDUP (optional delay), ACTIVE (can hit),
## RECOVERY (cannot attack again yet), then back to READY. The lengths of those phases
## come from the weapon's data file, so a quick dagger and a slow hammer are the same
## code with different numbers.

enum Phase { READY, WINDUP, ACTIVE, RECOVERY }

const ARC_POINTS := 10
const BLADE_START := 5.0

var _swing: MeleeSwingData
var _phase := Phase.READY
## Seconds left in the current phase.
var _phase_time := 0.0
## Flips each attack so consecutive swings sweep in opposite directions.
var _swing_sign := 1.0

@onready var _hitbox: Hitbox = $Hitbox
@onready var _shape: CollisionPolygon2D = $Hitbox/CollisionPolygon2D


func _on_setup() -> void:
	_swing = data as MeleeSwingData
	assert(_swing != null, "MeleeSwing needs a MeleeSwingData resource.")
	_hitbox.collision_mask = target_mask
	_shape.polygon = build_sector(_swing.reach, _swing.arc_degrees)
	_hitbox.landed.connect(_on_hitbox_landed)
	queue_redraw()


## Builds the pie-slice outline used as the hit area. Points right (angle 0) by default;
## the wielder's weapon pivot rotates it toward the aim direction.
static func build_sector(reach: float, arc_degrees: float) -> PackedVector2Array:
	var full_circle := arc_degrees >= 360.0
	var half := deg_to_rad(clampf(arc_degrees, 1.0, 360.0)) * 0.5
	var points := PackedVector2Array()
	if not full_circle:
		points.append(Vector2.ZERO)
	# A full circle's first and last points would overlap, so it uses one fewer.
	var count := ARC_POINTS if full_circle else ARC_POINTS + 1
	for i in count:
		var angle := lerpf(-half, half, float(i) / ARC_POINTS)
		points.append(Vector2.from_angle(angle) * reach)
	return points


func try_attack(aim_direction: Vector2) -> bool:
	if _phase != Phase.READY:
		return false
	_swing_sign = -_swing_sign
	wielder.velocity += aim_direction * data.lunge_speed
	if data.windup > 0.0:
		_enter(Phase.WINDUP, data.windup)
	else:
		_begin_active()
	return true


func tick(delta: float) -> void:
	if _phase == Phase.READY:
		return
	_phase_time -= delta
	if _phase_time <= 0.0:
		match _phase:
			Phase.WINDUP:
				_begin_active()
			Phase.ACTIVE:
				_hitbox.deactivate()
				_enter(Phase.RECOVERY, data.recovery)
			Phase.RECOVERY:
				_enter(Phase.READY, 0.0)
	queue_redraw()


func cancel() -> void:
	_hitbox.deactivate()
	_enter(Phase.READY, 0.0)
	queue_redraw()


func is_busy() -> bool:
	return _phase != Phase.READY


func get_move_speed_multiplier() -> float:
	if _phase == Phase.WINDUP or _phase == Phase.ACTIVE:
		return data.move_speed_multiplier
	return 1.0


func _begin_active() -> void:
	_enter(Phase.ACTIVE, data.active_time)
	if deals_damage:
		_hitbox.activate(data.damage, data.knockback, data.hit_stop, wielder)


func _enter(phase: Phase, duration: float) -> void:
	_phase = phase
	_phase_time = duration


func _on_hitbox_landed(hurtbox: Hurtbox, hit: HitInfo) -> void:
	hit_landed.emit(hurtbox, hit)


# --- Placeholder visuals -------------------------------------------------------------
# Drawn with code until real art exists. Replace with a sprite and animation later.

func _draw() -> void:
	if _swing == null:
		return
	match _phase:
		Phase.READY, Phase.WINDUP:
			# Resting blade, pointing where the player aims.
			var tip := Vector2(BLADE_START + _swing.reach * 0.5, 0.0)
			draw_line(Vector2(BLADE_START, 0.0), tip, _swing.color, 2.0)
		Phase.ACTIVE:
			var progress := 1.0 - _phase_time / maxf(data.active_time, 0.001)
			_draw_sweep(progress, 1.0)
		Phase.RECOVERY:
			var fade := _phase_time / maxf(data.recovery, 0.001)
			_draw_sweep(1.0, fade)


func _draw_sweep(progress: float, alpha: float) -> void:
	var half := deg_to_rad(_swing.arc_degrees) * 0.5
	var from := -half * _swing_sign
	var to := lerpf(from, half * _swing_sign, progress)
	if absf(to - from) > 0.01:
		var trail := _swing.color
		trail.a = 0.5 * alpha
		draw_arc(Vector2.ZERO, _swing.reach * 0.7, from, to, 12, trail, _swing.reach * 0.5)
	var edge := Vector2.from_angle(to)
	draw_line(edge * BLADE_START, edge * _swing.reach, Color(1.0, 1.0, 1.0, alpha), 2.0)
