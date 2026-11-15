class_name ZenithBladesAbility
extends AbilityBehavior
## Venza's Zenith: her pistols transform into arm blades for a limited time.
##
## A short transformation (frozen, untouchable, bright flash), then the blades replace her
## weapon until the timer runs out. Death, a level change or leaving the game end it
## safely: the weapon is restored and the flags cleared. The charge was already spent when
## it started (PlayerAbilities), so the bar must be refilled before the next use.

## The weapon used while transformed.
@export var blades: WeaponData = preload("res://weapons/data/venza_arm_blades.tres")

var _transform_left := 0.0


func _on_activate() -> void:
	var zenith_data := data as ZenithData
	_transform_left = zenith_data.transform_time if zenith_data != null else 0.4
	player.set_flag(Player.FLAG_ZENITH_ACTIVE, true)
	player.set_flag(Player.FLAG_ZENITH_READY, false)
	player.grant_invulnerability(_transform_left + 0.1)
	player.visual.flash(_transform_left, Color.WHITE)
	player.shake_camera(0.5)
	player.velocity = Vector2.ZERO
	player.begin_custom_motion(_transform_step)


func _transform_step(delta: float) -> bool:
	player.velocity = Vector2.ZERO
	_transform_left -= delta
	if _transform_left > 0.0 and _active:
		return true
	if _active:
		player.begin_weapon_override(blades)
		player.visual.flash(0.15, data.color)
	return false


func _on_end() -> void:
	if _transform_left > 0.0 and player.is_in_custom_motion():
		player.end_custom_motion()
	_transform_left = 0.0
	var zenith_data := data as ZenithData
	player.end_weapon_override(zenith_data.required_weapon if zenith_data != null else null)
	player.set_flag(Player.FLAG_ZENITH_ACTIVE, false)
	player.visual.flash(0.25, data.color)


func show_remote(_started: bool) -> void:
	player.visual.flash(0.3, Color.WHITE)
