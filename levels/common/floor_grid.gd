@tool
class_name FloorGrid
extends Node2D
## A flat floor with grid lines. Placeholder for real floor tiles.
##
## The grid matters even as a placeholder: on a plain background there is nothing to
## judge speed against, so movement cannot be felt properly.

## Floor size in pixels, starting at this node's position.
@export var size := Vector2(640.0, 384.0):
	set(value):
		size = value
		queue_redraw()
## Grid spacing in pixels. 16 matches the planned tile size.
@export var cell := 16:
	set(value):
		cell = maxi(value, 1)
		queue_redraw()
@export var floor_color := Color(0.06, 0.07, 0.12):
	set(value):
		floor_color = value
		queue_redraw()
@export var line_color := Color(0.1, 0.12, 0.2):
	set(value):
		line_color = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), floor_color)
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), line_color, 1.0)
		x += cell
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), line_color, 1.0)
		y += cell
