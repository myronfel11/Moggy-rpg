class_name Pillar
extends StaticBody2D
## One of the three pillars. Solid scenery with no hurtbox, so no weapon can harm it: only a
## tracking ball of its own colour (slot) destroys it, decided by the encounter on the host.
## Every peer shows the state from the encounter's synced slot states.

## Which sentinel and colour this pillar belongs to (0 to 2).
@export var slot := 0

var intact := true

var _color := Color.WHITE
var _time := 0.0
var _burst := 0.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(&"pillars")


func setup_color(color: Color) -> void:
	_color = color


## Shows the pillar standing or as rubble. [param animate] plays the collapse.
func set_intact(value: bool, animate := false) -> void:
	if value == intact:
		return
	intact = value
	_shape.set_deferred(&"disabled", not value)
	if not value and animate:
		_burst = 0.6
	elif value:
		_burst = 0.4


func _process(delta: float) -> void:
	_time += delta
	_burst = maxf(0.0, _burst - delta)
	queue_redraw()


func _draw() -> void:
	if intact:
		var glow := 0.6 + 0.25 * sin(_time * 3.0 + slot)
		draw_circle(Vector2.ZERO, 17.0, Color(_color, 0.12 * glow))
		draw_circle(Vector2.ZERO, 12.0, Color(0.1, 0.1, 0.16))
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color(_color, glow), 2.0)
		draw_circle(Vector2.ZERO, 4.0, Color(_color, glow))
	else:
		# Rubble.
		var rubble := Color(0.28, 0.27, 0.33)
		for offset: Vector2 in [Vector2(-6, 2), Vector2(4, -3), Vector2(2, 6), Vector2(-3, -6), Vector2(7, 4)]:
			draw_rect(Rect2(offset - Vector2(2.5, 2.0), Vector2(5.0, 4.0)), rubble)
	if _burst > 0.0:
		# Collapse (or restore) flash: an expanding ring.
		var progress := 1.0 - _burst / 0.6
		draw_arc(Vector2.ZERO, 12.0 + 40.0 * progress, 0.0, TAU, 32, Color(_color, 1.0 - progress), 3.0)
