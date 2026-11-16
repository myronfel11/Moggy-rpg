class_name Pillar
extends StaticBody2D
## One of the three pillars. Solid scenery with no hurtbox, so no weapon can harm it: only a
## tracking ball of its own colour (slot) destroys it, decided by the encounter on the host.
## Every peer shows the state from the encounter's synced slot states.

## Crack lines drawn across the pillar, one per hit taken.
const CRACKS := [
	[Vector2(-10, -5), Vector2(-4, -2), Vector2(-1, -7), Vector2(3, -9)],
	[Vector2(9, -2), Vector2(4, 2), Vector2(6, 7), Vector2(1, 10)],
	[Vector2(-8, 7), Vector2(-3, 3), Vector2(-6, -1), Vector2(-11, 1)],
	[Vector2(0, -11), Vector2(2, -4), Vector2(7, -5)],
	[Vector2(-2, 11), Vector2(-1, 5), Vector2(3, 4)],
]

## Which sentinel and colour this pillar belongs to (0 to 2).
@export var slot := 0

var intact := true
## Matching balls taken so far, and how many bring it down (from the encounter).
var damage_taken := 0
var hits_needed := 1

var _color := Color.WHITE
var _time := 0.0
var _burst := 0.0
var _hit_flash := 0.0

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


## Shows how many matching balls this pillar has taken out of [param needed].
## A new hit plays a small flash.
func set_damage(taken: int, needed: int) -> void:
	if taken > damage_taken and intact:
		_hit_flash = 0.3
	damage_taken = taken
	hits_needed = maxi(needed, 1)


func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
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
		# One crack per hit taken, and pips around the rim counting the hits left.
		var cracks := Color(0.02, 0.02, 0.05)
		for i in mini(damage_taken, CRACKS.size()):
			var line := PackedVector2Array(CRACKS[i])
			draw_polyline(line, cracks, 1.5)
		if hits_needed > 1:
			for i in hits_needed:
				var at := Vector2.from_angle(-PI / 2.0 + TAU * i / hits_needed) * 15.5
				var pip := Color(0.3, 0.3, 0.36) if i < damage_taken else _color
				draw_circle(at, 1.6, pip)
		if _hit_flash > 0.0:
			draw_circle(Vector2.ZERO, 12.0, Color(1, 1, 1, _hit_flash / 0.3 * 0.7))
	else:
		# Rubble.
		var rubble := Color(0.28, 0.27, 0.33)
		for offset: Vector2 in [Vector2(-6, 2), Vector2(4, -3), Vector2(2, 6), Vector2(-3, -6), Vector2(7, 4)]:
			draw_rect(Rect2(offset - Vector2(2.5, 2.0), Vector2(5.0, 4.0)), rubble)
	if _burst > 0.0:
		# Collapse (or restore) flash: an expanding ring.
		var progress := 1.0 - _burst / 0.6
		draw_arc(Vector2.ZERO, 12.0 + 40.0 * progress, 0.0, TAU, 32, Color(_color, 1.0 - progress), 3.0)
