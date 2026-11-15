class_name DashAttack
extends AbilityBehavior
## Ability: a fast, damaging dash. Every enemy she passes through is hit once.
##
## Moves the player through Player.begin_custom_motion, so normal wall collision applies
## and she can never pass through walls. She is untouchable during it, and leaves it no
## slower than she entered, so it chains with skating.

## How far the dash goes, in pixels.
@export var distance := 95.0
## Dash speed in pixels per second.
@export var speed := 620.0
@export var damage := 20.0
@export var knockback := 220.0
@export var hit_stop := 0.03

var _direction := Vector2.RIGHT
var _entry_speed := 0.0
var _travelled := 0.0

@onready var _hitbox: Hitbox = $Hitbox


func _on_setup() -> void:
	_hitbox.collision_mask = Layers.ENEMY_HURTBOX
	_hitbox.weapon_id = data.id
	_hitbox.landed.connect(func(_hurtbox: Hurtbox, _hit: HitInfo) -> void: player.shake_camera(0.3))


func _is_self_timed() -> bool:
	return true


func can_activate() -> bool:
	return super() and not player.is_in_custom_motion()


func _on_activate() -> void:
	var input := player.input
	_direction = input.move.normalized() if input.move.length() > 0.1 else input.aim_direction
	_entry_speed = player.velocity.length()
	_travelled = 0.0
	var time := distance / speed
	player.grant_invulnerability(time + 0.05)
	player.spawn_ghosts_for(time)
	player.visual.flash(0.12, data.color)
	_hitbox.activate(damage, knockback, hit_stop, player)
	player.begin_custom_motion(_step)


func _step(delta: float) -> bool:
	if not _active:
		return false
	player.velocity = _direction * speed
	_travelled += speed * delta
	if _travelled >= distance:
		player.velocity = _direction * maxf(player.max_speed, _entry_speed)
		end()
		return false
	return true


func _on_end() -> void:
	_hitbox.deactivate()
	if player.is_in_custom_motion():
		player.end_custom_motion()


func show_remote(started: bool) -> void:
	if started:
		player.spawn_ghosts_for(distance / speed)
		player.visual.flash(0.12, data.color)


func _draw() -> void:
	pass
