class_name BossBar
extends Control
## Boss HUD for "The Three Pillars", drawn at the top of the screen:
##   - the boss's name and what to do now ("BREAK THE PILLARS", "ATTACK!")
##   - the shield in three parts (one per bomb) and, below it, the health bar with a notch
##     at the 50% gate
##   - revives the team has left
##   - a big "TARGETED" warning while the laser is aimed at this machine's player
## It only reads the encounter and boss; it changes nothing.

const BAR_WIDTH := 220.0
const TOP := 30.0
const SHIELD_COLOR := Color(0.55, 0.85, 1.0)
const HEALTH_COLOR := Color(1.0, 0.3, 0.35)

var _level: Level
var _encounter: BossEncounter
var _time := 0.0


func bind(level: Level, encounter: BossEncounter) -> void:
	_level = level
	_encounter = encounter
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(480.0, 270.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _encounter == null:
		return
	var boss := get_tree().get_first_node_in_group(&"pillar_boss") as PillarBoss
	var font := ThemeDB.fallback_font
	var left := (size.x - BAR_WIDTH) * 0.5
	var data := _encounter.data
	draw_string(font, Vector2(left, TOP), data.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	draw_string(font, Vector2(left, TOP), _phase_text(), HORIZONTAL_ALIGNMENT_RIGHT, BAR_WIDTH, 8, _phase_color())
	# Shield: three segments.
	var shield := _encounter.get_shield_ratio()
	var segment := (BAR_WIDTH - 4.0) / 3.0
	for i in 3:
		var rect := Rect2(left + i * (segment + 2.0), TOP + 3.0, segment, 3.0)
		draw_rect(rect, Color(0.05, 0.05, 0.1, 0.85))
		var fill := clampf(shield * 3.0 - i, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), SHIELD_COLOR)
	# Health with the 50% notch.
	var health_rect := Rect2(left, TOP + 8.0, BAR_WIDTH, 5.0)
	draw_rect(health_rect, Color(0.05, 0.05, 0.1, 0.85))
	if boss != null and boss.health.max_health > 0.0:
		var ratio := boss.health.current / boss.health.max_health
		var color := HEALTH_COLOR if _encounter.is_boss_vulnerable() else Color(HEALTH_COLOR, 0.45)
		draw_rect(Rect2(health_rect.position, Vector2(BAR_WIDTH * ratio, 5.0)), color)
	var notch := left + BAR_WIDTH * data.health_gate
	draw_line(Vector2(notch, TOP + 7.0), Vector2(notch, TOP + 14.0), Color.WHITE, 1.0)
	draw_string(font, Vector2(left, TOP + 22.0), "REVIVES %d" % _encounter.revives_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.7))
	# Laser warning for this machine's player.
	if boss != null and _level != null and _level.local_player != null and boss.is_charging_at(_level.local_player.peer_id):
		var locked := boss.laser_phase == PillarBoss.Laser.LOCK
		var blink := fmod(_time, 0.2 if locked else 0.4) < (0.1 if locked else 0.25)
		var text := "LOCKED - MOVE!" if locked else "TARGETED"
		draw_string(font, Vector2(0.0, 70.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1.0, 0.25, 0.25) if blink else Color(1.0, 1.0, 1.0))


func _phase_text() -> String:
	match _encounter.state:
		BossEncounter.State.ENCOUNTER_START:
			return "AWAKENING"
		BossEncounter.State.SHIELDED_MECHANICS, BossEncounter.State.SHIELDED_MECHANICS_2:
			return "SHIELDED - BREAK THE PILLARS"
		BossEncounter.State.DAMAGE_PHASE_1, BossEncounter.State.FINAL_DAMAGE_PHASE:
			return "VULNERABLE - ATTACK!"
		BossEncounter.State.HEALTH_GATE_TRANSITION:
			return "SHIELD RESTORING"
		BossEncounter.State.BOSS_DEFEATED:
			return "DEFEATED"
		_:
			return "FAILED"


func _phase_color() -> Color:
	if _encounter.is_boss_vulnerable():
		return Color(1.0, 0.9, 0.3, 0.7 + 0.3 * sin(_time * 8.0))
	return Color(0.75, 0.85, 1.0)
