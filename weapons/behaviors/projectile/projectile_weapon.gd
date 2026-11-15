class_name ProjectileWeapon
extends WeaponBehavior
## A rapid-fire gun pair: holds the trigger, alternates muzzles, sprays small bullets.
##
## Unlike melee swings there is no wind-up or recovery: it is never "busy", never locks the
## aim and never slows the wielder, so the player can shoot while running or skating.

const PROJECTILE_SCENE := preload("res://weapons/behaviors/projectile/projectile.tscn")
const FLASH_TIME := 0.045

var _gun: ProjectileWeaponData
var _cooldown := 0.0
## +1 or -1: which gun fires next.
var _side := 1.0
var _flash_left := 0.0


func _on_setup() -> void:
	_gun = data as ProjectileWeaponData
	assert(_gun != null, "ProjectileWeapon needs a ProjectileWeaponData resource.")
	queue_redraw()


func try_attack(aim_direction: Vector2) -> bool:
	if _cooldown > 0.0:
		return false
	# Add rather than set, so the part of a frame left over carries into the next shot and
	# the real fire rate matches fire_interval instead of rounding up to whole frames.
	_cooldown += _gun.fire_interval
	_fire(aim_direction)
	return true


func tick(delta: float) -> void:
	# Never more than one frame "in credit", so a pause in firing cannot bank extra shots.
	_cooldown = maxf(_cooldown - delta, -delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		queue_redraw()


func cancel() -> void:
	_flash_left = 0.0
	queue_redraw()


func is_busy() -> bool:
	return false


func is_aim_locked() -> bool:
	return false


func get_move_speed_multiplier() -> float:
	return _gun.move_speed_multiplier if _gun != null else 1.0


## True if this weapon fires fast enough that its shots should be sent unreliably over
## the network (losing a cosmetic bullet now and then is fine).
func is_rapid_fire() -> bool:
	return true


func _fire(aim_direction: Vector2) -> void:
	_side = -_side
	_flash_left = FLASH_TIME
	var spread := deg_to_rad(randf_range(-_gun.spread_degrees, _gun.spread_degrees) * 0.5)
	var direction := aim_direction.rotated(spread)
	var muzzle := _muzzle_position(aim_direction)
	var bullet := PROJECTILE_SCENE.instantiate() as Projectile
	bullet.velocity = direction * _gun.projectile_speed
	bullet.max_distance = _gun.projectile_range
	bullet.color = _gun.projectile_color
	bullet.weapon = self
	bullet.collision_mask = target_mask
	bullet.staggers = _gun.staggers
	bullet.weapon_id = _gun.id
	var parent := wielder.get_parent() if wielder.get_parent() != null else wielder
	parent.add_child(bullet)
	bullet.global_position = muzzle
	if deals_damage:
		bullet.activate(_gun.damage, _gun.knockback, _gun.hit_stop, wielder)
	queue_redraw()


func _muzzle_position(aim_direction: Vector2) -> Vector2:
	var side_offset := aim_direction.orthogonal() * _gun.muzzle_gap * _side
	return wielder.global_position + aim_direction * _gun.muzzle_distance + side_offset


# --- Placeholder visuals -------------------------------------------------------------
# Two short barrels pointing where the wielder aims, and a flash at the gun that fired.

func _draw() -> void:
	if _gun == null:
		return
	for side: float in [-1.0, 1.0]:
		var offset := Vector2(0.0, _gun.muzzle_gap * side)
		draw_line(Vector2(4.0, 0.0) + offset, Vector2(_gun.muzzle_distance, 0.0) + offset, Color(0.85, 0.85, 0.95), 2.0)
	if _flash_left > 0.0:
		var tip := Vector2(_gun.muzzle_distance + 1.5, _gun.muzzle_gap * _side)
		draw_circle(tip, 2.5, Color(1.0, 0.95, 0.7))
		draw_circle(tip, 1.2, Color.WHITE)
