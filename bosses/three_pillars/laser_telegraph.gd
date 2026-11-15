extends Node2D
## Draws the Warden's sniper laser telegraph on every peer, from the boss's synced values:
##   ACQUIRE - a red reticle closing in on the chosen player
##   CHARGE  - a line from the boss through the target, growing brighter and thicker
##   LOCK    - the line freezes, turns white and blinks, with "LOCKED" at the boss
##   FIRE    - a thick beam across the whole arena (it ignores walls)
##   RECOVER - the beam's afterglow fading out
## Drawn above everything else so it stays readable in a crowded fight.

const CHARGE_COLOR := Color(1.0, 0.2, 0.25)
const LOCK_COLOR := Color(1.0, 1.0, 1.0)
const BEAM_COLOR := Color(1.0, 0.35, 0.35)

var _boss: PillarBoss
var _time := 0.0


func _ready() -> void:
	_boss = get_parent() as PillarBoss
	top_level = true
	z_index = 60


func _process(delta: float) -> void:
	_time += delta
	global_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _boss == null or _boss.is_dead():
		return
	var tuning := _boss.settings()
	var origin := _boss.global_position
	var end := origin + _boss.laser_dir * PillarBoss.BEAM_LENGTH
	var target := _target_position()
	match _boss.laser_phase:
		PillarBoss.Laser.ACQUIRE:
			var progress := 1.0 - _boss.laser_time_left / maxf(tuning.acquire_time, 0.01)
			_draw_reticle(target, lerpf(18.0, 9.0, progress), Color(CHARGE_COLOR, 0.5 + 0.5 * progress))
		PillarBoss.Laser.CHARGE:
			var progress := clampf(1.0 - _boss.laser_time_left / maxf(tuning.charge_time, 0.01), 0.0, 1.0)
			var glow := Color(CHARGE_COLOR, 0.15 + 0.35 * progress)
			draw_line(origin, end, glow, 2.0 + 6.0 * progress)
			draw_line(origin, end, Color(CHARGE_COLOR, 0.45 + 0.55 * progress), 1.0 + progress)
			_draw_reticle(target, 9.0, CHARGE_COLOR)
		PillarBoss.Laser.LOCK:
			var blink := fmod(_time, 0.12) < 0.06
			draw_line(origin, end, Color(LOCK_COLOR, 0.35), 8.0)
			draw_line(origin, end, LOCK_COLOR if blink else CHARGE_COLOR, 2.0)
			_draw_text(origin + Vector2(-16.0, -44.0), "LOCKED", LOCK_COLOR if blink else CHARGE_COLOR)
		PillarBoss.Laser.FIRE:
			var width := tuning.beam_half_width * 2.0
			draw_line(origin, end, Color(BEAM_COLOR, 0.55), width + 10.0)
			draw_line(origin, end, Color(1.0, 0.85, 0.85), width)
			draw_line(origin, end, Color.WHITE, maxf(width * 0.4, 2.0))
		PillarBoss.Laser.RECOVER:
			var fade := clampf(_boss.laser_time_left / maxf(tuning.recover_time, 0.01), 0.0, 1.0)
			draw_line(origin, end, Color(BEAM_COLOR, 0.4 * fade * fade), tuning.beam_half_width * 2.0 * fade)


func _target_position() -> Vector2:
	var level := get_tree().get_first_node_in_group(&"level") as Level
	var player := level.get_player_by_peer(_boss.laser_target_peer) if level != null else null
	return player.global_position if player != null else _boss.global_position + _boss.laser_dir * 60.0


func _draw_reticle(at: Vector2, radius: float, color: Color) -> void:
	draw_arc(at, radius, 0.0, TAU, 24, color, 1.5)
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle + _time * 2.0)
		draw_line(at + direction * (radius - 4.0), at + direction * (radius + 4.0), color, 1.5)


func _draw_text(at: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
