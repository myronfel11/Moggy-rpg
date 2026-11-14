@tool
class_name WallBlock
extends StaticBody2D
## A solid rectangular wall, sized by one property. Placeholder for real tiles.
##
## "@tool" at the top makes this script also run inside the editor, so the wall is
## visible and resizable there, not only when the game runs. The node's position is
## the centre of the block.

## Width and height in pixels.
@export var size := Vector2(32.0, 32.0):
	set(value):
		size = value
		_refresh()
@export var fill_color := Color(0.13, 0.11, 0.24):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.62, 0.32, 1.0):
	set(value):
		edge_color = value
		queue_redraw()

var _shape: CollisionShape2D


func _ready() -> void:
	# Built in code and marked internal, so it is never saved into the scene file.
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	add_child(_shape, false, Node.INTERNAL_MODE_FRONT)
	_refresh()


func _refresh() -> void:
	if _shape != null:
		(_shape.shape as RectangleShape2D).size = size
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, fill_color)
	draw_rect(rect.grow(-0.5), edge_color, false, 1.0)
