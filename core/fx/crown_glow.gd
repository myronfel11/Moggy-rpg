class_name CrownGlow
extends Node2D
## The glow around a player's crown: pulsing with sparks when Zenith is ready, blazing
## while it is active. Reads the player's synced flags, so teammates see it too.
## Place it under the player's Visual node, at the crown.

const SPARKS := 5

var _player: Player
var _time := 0.0


func _ready() -> void:
	_player = get_parent().get_parent() as Player
	z_index = 1


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _player == null or not _player.is_alive() or _player.character == null:
		return
	var active := _player.has_flag(Player.FLAG_ZENITH_ACTIVE)
	var zenith_ready := _player.has_flag(Player.FLAG_ZENITH_READY)
	if not active and not zenith_ready:
		return
	var color := _player.character.crown_color
	var pulse := 0.5 + 0.5 * sin(_time * (14.0 if active else 6.0))
	var radius := (6.0 if active else 4.0) + pulse * (2.5 if active else 1.5)
	draw_circle(Vector2.ZERO, radius + 2.0, Color(color, 0.18 + 0.12 * pulse))
	draw_circle(Vector2.ZERO, radius, Color(color, 0.35 + 0.25 * pulse))
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 1.0, 1.0, 0.7 + 0.3 * pulse))
	for i in SPARKS:
		var angle := _time * (5.0 if active else 2.5) + TAU * i / SPARKS
		var at := Vector2.from_angle(angle) * (radius + 3.0)
		draw_rect(Rect2(at - Vector2.ONE * 0.5, Vector2.ONE), Color(1.0, 1.0, 0.85, 0.9))
