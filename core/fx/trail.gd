class_name Trail
extends Line2D
## A glowing streak that follows a node and fades out behind it.
##
## Each frame while emitting it records where the followed point is; points older than
## lifetime are dropped. The line is drawn in world space (top_level), so it stays where
## the player was. Point count is capped, so it stays cheap however long it runs.

## Seconds a point stays before disappearing.
@export var lifetime := 0.35
## Most points kept at once.
@export var max_points := 40
## Offset from the followed node, in that node's local space.
@export var offset := Vector2.ZERO

## While true, new points are added.
var emitting := false

var _target: Node2D
var _ages: PackedFloat32Array = []


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	global_rotation = 0.0
	if gradient == null:
		var fade := Gradient.new()
		var start := default_color
		start.a = 0.0
		fade.set_color(0, start)
		fade.set_color(1, default_color)
		gradient = fade
	z_index = -1


## Starts following [param node].
func follow(node: Node2D) -> void:
	_target = node


func _process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[0] > lifetime:
		remove_point(0)
		_ages.remove_at(0)
	if emitting and is_instance_valid(_target):
		add_point(_target.to_global(offset))
		_ages.append(0.0)
		while get_point_count() > max_points:
			remove_point(0)
			_ages.remove_at(0)
