class_name MouseIcon
extends Control
## A tiny mouse drawn in code, with one button filled in, for control hints.
## Placeholder art like everything else; swap for a sprite once real art exists.

## Which button is highlighted.
@export_enum("Left", "Right") var button := 1:
	set(value):
		button = value
		queue_redraw()
## Colour of the outline and the highlighted button.
@export var color := Color.WHITE


func _draw() -> void:
	# Body: 7 x 10 pixels, centred in this control.
	var body := Rect2(((size - Vector2(7.0, 10.0)) / 2.0).floor(), Vector2(7.0, 10.0))
	var top := body.position
	# Highlighted button (top half, one side).
	var half := Rect2(top + Vector2(1.0 if button == 0 else 4.0, 1.0), Vector2(2.0, 3.0))
	draw_rect(half, color)
	# Outline with clipped corners, so it reads as a rounded mouse.
	var w := body.size.x
	var h := body.size.y
	var points := PackedVector2Array([
		top + Vector2(1.5, 0.5), top + Vector2(w - 1.5, 0.5),
		top + Vector2(w - 0.5, 1.5), top + Vector2(w - 0.5, h - 2.5),
		top + Vector2(w - 2.5, h - 0.5), top + Vector2(2.5, h - 0.5),
		top + Vector2(0.5, h - 2.5), top + Vector2(0.5, 1.5),
		top + Vector2(1.5, 0.5),
	])
	draw_polyline(points, color, 1.0)
	# Line between the two buttons, and the bottom of the button area.
	draw_line(top + Vector2(3.5, 0.5), top + Vector2(3.5, 4.5), color, 1.0)
	draw_line(top + Vector2(0.5, 4.5), top + Vector2(w - 0.5, 4.5), color, 1.0)
