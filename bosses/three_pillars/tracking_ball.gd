class_name TrackingBall
extends Node2D
## A sentinel's tracking energy ball. The host moves it: constant speed, turning toward its
## target by at most ball_turn_rate per second, so a player can lead it around and step
## aside at the last moment. Its position is synced; every peer draws it and its trail.
##
## It is destroyed by:
##   - its own pillar (same slot, still standing): the pillar falls, the sentinel's shield drops
##   - any other wall or pillar: it fizzles (the boss's core does not stop it)
##   - touching a player: that player's own machine applies the damage and asks the host to
##     remove it (same rule as every enemy attack)
##   - running out of time

const RADIUS := 4.0

## Which sentinel fired it (0 to 2). Set through spawn props.
var slot := 0
## The player it is chasing (network peer). Set through spawn props.
var target_peer := 0
## Current heading (unit vector). Set through spawn props.
var direction := Vector2.DOWN

var _age := 0.0
var _popped := false
var _hit_local := false
var _color := Color.WHITE

@onready var _trail: Trail = $Trail


func _ready() -> void:
	add_to_group(&"tracking_balls")
	var encounter := _encounter()
	if encounter != null and slot < encounter.data.slot_colors.size():
		_color = encounter.data.slot_colors[slot]
	_trail.set_color(Color(_color, 0.8))
	_trail.follow(self)
	_trail.emitting = true


func _encounter() -> BossEncounter:
	return get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter


func _physics_process(delta: float) -> void:
	if _popped:
		return
	if multiplayer.is_server():
		_host_move(delta)
	_check_local_player()
	queue_redraw()


## Host: steer toward the target, move, and check what the ball runs into.
func _host_move(delta: float) -> void:
	var encounter := _encounter()
	if encounter == null:
		return
	var tuning := encounter.data
	_age += delta
	if _age >= tuning.ball_lifetime:
		pop()
		return
	var level := get_tree().get_first_node_in_group(&"level") as Level
	var target := level.get_player_by_peer(target_peer) if level != null else null
	if target == null or not target.is_targetable():
		target = _nearest_targetable()
		target_peer = target.peer_id if target != null else 0
	if target != null:
		var wanted := (target.global_position - global_position).normalized()
		var turn := tuning.ball_turn_rate * delta
		direction = direction.rotated(clampf(direction.angle_to(wanted), -turn, turn))
	var from := global_position
	var to := from + direction * tuning.ball_speed * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD, encounter.get_ball_ignored_bodies())
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var pillar := hit.collider as Pillar
		if pillar != null and pillar.slot == slot and pillar.intact:
			encounter.on_ball_hit_pillar(slot)
		pop()
		return
	global_position = to


## Every peer: did this ball touch this machine's own player?
func _check_local_player() -> void:
	if _hit_local:
		return
	var level := get_tree().get_first_node_in_group(&"level") as Level
	if level == null or level.local_player == null or not is_instance_valid(level.local_player):
		return
	var player := level.local_player
	if not player.is_alive() or player.hurtbox.invulnerable:
		return
	if player.global_position.distance_to(global_position) > RADIUS + PillarBoss.PLAYER_RADIUS:
		return
	_hit_local = true
	var encounter := _encounter()
	var damage := encounter.data.ball_damage if encounter != null else 15.0
	player.hurtbox.receive_hit(HitInfo.new(damage, 140.0, direction, 0.04))
	if multiplayer.is_server():
		pop()
	else:
		_request_pop.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pop() -> void:
	if multiplayer.is_server():
		pop()


## Host: removes the ball (on every peer).
func pop() -> void:
	if _popped:
		return
	_popped = true
	queue_free()


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


func _draw() -> void:
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.02)
	draw_circle(Vector2.ZERO, RADIUS + 3.0, Color(_color, 0.25))
	draw_circle(Vector2.ZERO, RADIUS, Color(_color, pulse))
	draw_circle(Vector2.ZERO, 1.5, Color.WHITE)
