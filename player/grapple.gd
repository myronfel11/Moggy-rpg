class_name Grapple
extends Node2D
## Grappling hook, available to every character. Hold Grapple (right mouse) to fire it
## where you aim; it catches on walls, pillars and anchor posts within range.
##
## Top-down swinging: the rope sets a maximum distance from the anchor. Steering pushes the
## player; when the rope is taut, any movement away from the anchor is turned into movement
## around it with the same speed, so the player orbits and can build speed by steering
## along the circle. Releasing keeps that velocity (plus a small boost), and the momentum
## rule in Player lets it carry. Dash while attached lets go and dashes.
##
## Only the owner simulates the swing; other peers see the rope from the synced
## GRAPPLING flag and anchor position, and the player's synced position.

## Longest rope, in pixels.
@export var grapple_range := 150.0
## How hard steering pushes while attached, in pixels per second squared.
@export var swing_acceleration := 520.0
## Swinging never gets faster than this.
@export var max_swing_speed := 340.0
## Speed multiplier when letting go.
@export var release_boost := 1.1
## Seconds before trying again after a miss.
@export var miss_lockout := 0.3
## If a wall blocks the rope for this long, the grapple lets go.
@export var line_break_time := 0.15
## The rope is never shorter than this.
@export var min_rope := 18.0

var player: Player
var attached := false
var anchor := Vector2.ZERO
var rope_length := 0.0

var _anchor_body: RID
var _lockout := 0.0
var _blocked_time := 0.0
var _was_held := false
var _whiff_point := Vector2.ZERO
var _whiff_left := 0.0

@onready var _rope: Line2D = $Rope


func setup(p_player: Player) -> void:
	player = p_player
	_rope.top_level = true
	_rope.global_position = Vector2.ZERO


## Owner only, every physics frame.
func update(delta: float) -> void:
	_lockout = maxf(0.0, _lockout - delta)
	var held := player.input.grapple_held
	if held and not _was_held and not attached and _lockout <= 0.0 and player.state == Player.State.MOVE:
		try_attach(player.input.aim_direction)
	if attached and not held:
		release()
	_was_held = held


## Fires the hook along [param direction]. Returns true if it caught on something.
func try_attach(direction: Vector2) -> bool:
	var from := player.global_position
	var to := from + direction.normalized() * grapple_range
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_lockout = miss_lockout
		_whiff_point = to
		_whiff_left = 0.12
		return false
	anchor = hit.position
	_anchor_body = hit.rid
	rope_length = maxf(from.distance_to(anchor), min_rope)
	attached = true
	_blocked_time = 0.0
	player.net_grapple_anchor = anchor
	player.set_flag(Player.FLAG_GRAPPLING, true)
	player.begin_custom_motion(_swing, true)
	return true


## Lets go, keeping the swing's momentum.
func release() -> void:
	if not attached:
		return
	attached = false
	player.set_flag(Player.FLAG_GRAPPLING, false)
	player.velocity *= release_boost
	if player.is_in_custom_motion():
		player.end_custom_motion()


## Lets go without a boost (death, another ability taking over movement).
func cancel() -> void:
	if not attached:
		return
	attached = false
	player.set_flag(Player.FLAG_GRAPPLING, false)


func _swing(delta: float) -> bool:
	if not attached:
		return false
	if player.input.has_dash_buffered():
		# Let go; the dash happens next frame from normal movement.
		release()
		return false
	var velocity := player.velocity + player.input.move * swing_acceleration * delta
	var offset := player.global_position - anchor
	var distance := offset.length()
	if distance > 0.01 and distance >= rope_length - 0.5:
		var outward := offset / distance
		var away := velocity.dot(outward)
		if away > 0.0:
			# Taut rope: keep the speed, but only around the anchor.
			var speed := velocity.length()
			velocity -= outward * away
			if velocity.length() > 0.01:
				velocity = velocity.normalized() * speed
		if distance > rope_length + 1.0:
			velocity -= outward * (distance - rope_length) * 10.0
	if velocity.length() > max_swing_speed:
		velocity = velocity.normalized() * max_swing_speed
	player.velocity = velocity
	if _rope_blocked():
		_blocked_time += delta
		if _blocked_time >= line_break_time:
			release()
			return false
	else:
		_blocked_time = 0.0
	return true


## True if a wall is between the player and the anchor. The wall or post the hook is on
## does not count, so the player can swing all the way round a post.
func _rope_blocked() -> bool:
	var to_player := player.global_position - anchor
	if to_player.length() < 3.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(player.global_position, anchor, Layers.WORLD, [_anchor_body])
	return not player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _process(delta: float) -> void:
	if player == null:
		return
	_whiff_left = maxf(0.0, _whiff_left - delta)
	var grappling := player.has_flag(Player.FLAG_GRAPPLING) and player.is_alive()
	_rope.clear_points()
	if grappling:
		var end := anchor if player.is_local() else player.net_grapple_anchor
		var start := player.global_position
		# Bow the rope slightly against the direction of travel so it looks like it trails.
		var along := end - start
		var bow := along.orthogonal().normalized() * clampf(player.velocity.length() * 0.02, 1.0, 6.0)
		if player.velocity.dot(along.orthogonal()) > 0.0:
			bow = -bow
		_rope.add_point(start)
		_rope.add_point((start + end) * 0.5 + bow)
		_rope.add_point(end)
		_rope.default_color.a = 0.95
	elif _whiff_left > 0.0 and player.is_local():
		_rope.add_point(player.global_position)
		_rope.add_point(player.global_position.lerp(_whiff_point, 1.0 - _whiff_left / 0.12))
		_rope.default_color.a = 0.5
