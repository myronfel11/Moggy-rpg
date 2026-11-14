class_name Pickup
extends Node2D
## A material lying on the ground.
##
## It pops out of a dead enemy, slides to a stop, then flies to any player who comes
## near (the "magnet") and joins that player's inventory on contact. The magnet matters
## for feel: collecting loot should never mean carefully walking over every piece.

const SCATTER_SPEED_MIN := 50.0
const SCATTER_SPEED_MAX := 120.0
const SCATTER_FRICTION := 420.0
## Seconds before a fresh drop can be collected, so the pop-out is visible.
const PICKUP_DELAY := 0.3
## Distance in pixels at which the pickup starts flying to a player.
const MAGNET_RADIUS := 44.0
const MAGNET_ACCELERATION := 1200.0
const MAGNET_SPEED := 280.0
const COLLECT_RADIUS := 7.0

var item: ItemData
var amount := 1

var _velocity := Vector2.ZERO
var _age := 0.0


func _ready() -> void:
	add_to_group(&"pickups")
	var speed := randf_range(SCATTER_SPEED_MIN, SCATTER_SPEED_MAX)
	_velocity = Vector2.from_angle(randf() * TAU) * speed


func _physics_process(delta: float) -> void:
	_age += delta
	var player := _player_in_magnet_range() if _age >= PICKUP_DELAY else null
	if player == null:
		_velocity = _velocity.move_toward(Vector2.ZERO, SCATTER_FRICTION * delta)
	else:
		var to_player := player.global_position - global_position
		if to_player.length() <= COLLECT_RADIUS:
			player.inventory.add(item, amount)
			queue_free()
			return
		var wanted := to_player.normalized() * MAGNET_SPEED
		_velocity = _velocity.move_toward(wanted, MAGNET_ACCELERATION * delta)
	position += _velocity * delta
	if _is_special():
		queue_redraw()


## The nearest living player close enough to attract this pickup, or null.
func _player_in_magnet_range() -> Player:
	var best: Player = null
	var best_distance := MAGNET_RADIUS * MAGNET_RADIUS
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = player
	return best


func _is_special() -> bool:
	return item != null and item.rarity != ItemData.Rarity.COMMON


# --- Placeholder visuals -------------------------------------------------------------
# Common items are a small square. Rarer items are a larger, pulsing, outlined diamond.

func _draw() -> void:
	if item == null:
		return
	if not _is_special():
		draw_rect(Rect2(-1.5, -1.5, 3.0, 3.0), item.color)
		return
	var radius := 3.0 + 0.8 * sin(_age * 9.0)
	var diamond := PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius, 0.0), Vector2(0.0, radius), Vector2(-radius, 0.0),
	])
	draw_colored_polygon(diamond, item.color)
	diamond.append(diamond[0])
	draw_polyline(diamond, Color.WHITE, 1.0)
