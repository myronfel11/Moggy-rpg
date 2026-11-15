class_name Sentinel
extends Enemy
## A mini-boss turret tied to one pillar (its slot). It never moves; it fires tracking
## balls in its slot's colour at players. While its pillar stands it is shielded: hits do
## nothing except flash the shield. The encounter (host) decides `shielded`; it is synced.

const BALL_SCENE := "res://bosses/three_pillars/tracking_ball.tscn"
const SHIELD_RADIUS := 17.0

## Which pillar this sentinel belongs to (0 to 2). Set through spawn props.
var slot := 0
## Synced: true while its pillar stands.
var shielded := true

var _fire_left := 0.0
var _block_flash := 0.0
var _time := 0.0


func _ready() -> void:
	super()
	add_to_group(&"sentinels")
	hurtbox.hit_blocked.connect(func(_hit: HitInfo) -> void: _block_flash = 0.15)
	var body := visual.get_node_or_null(^"Body") as Polygon2D
	if body != null:
		body.color = slot_color()
	# Stagger the first shots so the three sentinels do not fire together.
	_fire_left = 1.5 + slot * 1.3


func slot_color() -> Color:
	var encounter := _encounter()
	if encounter != null and slot < encounter.data.slot_colors.size():
		return encounter.data.slot_colors[slot]
	return Color.WHITE


func _encounter() -> BossEncounter:
	return get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter


func _think(delta: float) -> void:
	velocity = Vector2.ZERO
	var encounter := _encounter()
	if encounter == null or not encounter.sentinels_active():
		return
	_fire_left -= delta
	if _fire_left > 0.0:
		return
	_fire_left = encounter.data.fire_interval
	fire()


## Host: launches a tracking ball at the nearest targetable player. Returns the ball.
func fire() -> TrackingBall:
	var encounter := _encounter()
	if encounter == null or encounter.count_balls(slot) >= encounter.data.max_balls_each:
		return null
	var target := _nearest_targetable()
	if target == null:
		return null
	var direction := (target.global_position - global_position).normalized()
	var level := get_tree().get_first_node_in_group(&"level") as Level
	return level.spawn_scene(BALL_SCENE, global_position + direction * 16.0, {
		"slot": slot, "target_peer": target.peer_id, "direction": direction,
	}) as TrackingBall


func _nearest_targetable() -> Player:
	var best: Player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or not player.is_targetable():
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_block_flash = maxf(0.0, _block_flash - delta)
	hurtbox.invulnerable = _spawn_left > 0.0 or shielded
	queue_redraw()


func _draw() -> void:
	if _dead or not shielded:
		return
	var color := slot_color()
	var alpha := 0.55 + 0.2 * sin(_time * 4.0)
	if _block_flash > 0.0:
		color = Color.WHITE
		alpha = 1.0
	var points := PackedVector2Array()
	for i in 7:
		points.append(Vector2.from_angle(TAU * i / 6.0 + _time * 0.6) * SHIELD_RADIUS)
	draw_polyline(points, Color(color, alpha), 2.0)
	draw_circle(Vector2.ZERO, SHIELD_RADIUS - 1.0, Color(color, 0.08))
