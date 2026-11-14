class_name FlashVisual
extends Node2D
## Parent node for a character's art. Call flash() to blink it white.
##
## Needs a ShaderMaterial using hit_flash.gdshader on this node, and "Use Parent Material"
## switched on for each child that should flash.

var _tween: Tween


## Turns the art one solid colour (white by default), then fades back over
## [param duration] seconds.
func flash(duration := 0.12, color := Color.WHITE) -> void:
	if not material is ShaderMaterial:
		return
	if _tween != null:
		_tween.kill()
	(material as ShaderMaterial).set_shader_parameter(&"flash_color", color)
	_set_flash(1.0)
	_tween = create_tween()
	_tween.tween_method(_set_flash, 1.0, 0.0, duration)


func _set_flash(amount: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"flash_amount", amount)
