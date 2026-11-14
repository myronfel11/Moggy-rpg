class_name WaveDirector
extends Node
## Spawns waves of enemies so there is always something to fight.
##
## Milestone scaffolding: each wave is one enemy larger than the last, up to a cap.
## Only the host runs waves; clients just hear which wave started. A dead player comes
## back after revive_delay while a teammate is still up. If everyone is down at once,
## the run resets to wave 1. Real missions will replace this later.

signal wave_started(number: int, enemy_count: int)

## The enemy to spawn.
@export var enemy_type: EnemyData
## A tougher enemy mixed into later waves. Leave empty for none.
@export var elite_type: EnemyData
## The first wave that includes an elite.
@export var elite_from_wave := 3
## After that, one more elite joins every this many waves.
@export var elite_every := 3
@export var first_wave_size := 3
## Extra enemies added each wave.
@export var wave_growth := 1
@export var max_wave_size := 8
## Seconds of calm after a wave is cleared.
@export var time_between_waves := 1.5
## Seconds between everyone being down and the run restarting.
@export var respawn_delay := 1.5
## Seconds a downed player waits to come back while a teammate is still up.
@export var revive_delay := 5.0
## Enemies will not spawn closer to any player than this, in pixels.
@export var min_spawn_distance := 110.0

var wave := 0

var _arena: Arena
var _spawn_positions: Array[Vector2] = []
var _alive := 0
var _running := false
## Increases on every reset, so timers started before the reset know to do nothing.
var _run_id := 0


## Tells the director which arena it runs and where enemies may appear.
func setup(arena: Arena, spawn_points: Node) -> void:
	_arena = arena
	for child in spawn_points.get_children():
		var marker := child as Node2D
		if marker != null:
			_spawn_positions.append(marker.global_position)
	arena.player_spawned.connect(func(player: Player) -> void:
		player.died.connect(_on_player_died.bind(player))
	)


## Begins spawning waves from wave 1. Host only.
func start() -> void:
	if not multiplayer.is_server():
		return
	_running = true
	wave = 0
	_next_wave()


## Spawns one enemy on every peer. Host only. Also used directly by tests.
func spawn_enemy(type: EnemyData, at: Vector2) -> Enemy:
	var enemy := _arena.spawn_enemy(type, at)
	enemy.died.connect(_on_enemy_died)
	_alive += 1
	return enemy


func _next_wave() -> void:
	if not multiplayer.is_server():
		return
	var number := wave + 1
	var count := mini(first_wave_size + (number - 1) * wave_growth, max_wave_size)
	var elites := mini(_elite_count(number), count)
	var positions := _pick_spawn_positions(count)
	for i in count:
		spawn_enemy(elite_type if i < elites else enemy_type, positions[i])
	_announce_wave.rpc(number, count)


@rpc("authority", "call_local", "reliable")
func _announce_wave(number: int, count: int) -> void:
	wave = number
	wave_started.emit(number, count)


## How many of a wave's enemies are elites. Elites replace regular enemies, they are not extra.
func _elite_count(wave_number: int) -> int:
	if elite_type == null or wave_number < elite_from_wave:
		return 0
	@warning_ignore("integer_division")
	return 1 + (wave_number - elite_from_wave) / maxi(elite_every, 1)


func _pick_spawn_positions(count: int) -> Array[Vector2]:
	var players := _arena.get_players()
	var candidates: Array[Vector2] = []
	for point in _spawn_positions:
		var far_enough := true
		for player in players:
			if player.is_alive() and point.distance_to(player.global_position) < min_spawn_distance:
				far_enough = false
		if far_enough:
			candidates.append(point)
	if candidates.is_empty():
		candidates = _spawn_positions.duplicate()
	candidates.shuffle()
	var picked: Array[Vector2] = []
	for i in count:
		var jitter := Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		picked.append(candidates[i % candidates.size()] + jitter)
	return picked


func _on_enemy_died(_enemy: Enemy) -> void:
	_alive -= 1
	if _running and _alive <= 0:
		_after(time_between_waves, _next_wave)


func _on_player_died(player: Player) -> void:
	if not _running or not multiplayer.is_server():
		return
	for other in _arena.get_players():
		if other.is_alive():
			_after(revive_delay, _revive.bind(player))
			return
	_after(respawn_delay, _reset_run)


func _revive(player: Player) -> void:
	if is_instance_valid(player) and not player.is_alive():
		player.net_respawn.rpc(_arena.get_player_start())


func _reset_run() -> void:
	_run_id += 1
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_alive = 0
	var players := _arena.get_players()
	for i in players.size():
		var offset := Vector2(Arena.PLAYER_SPACING * i, 0.0)
		players[i].net_respawn.rpc(_arena.get_player_start() + offset)
	start()


## Calls [param action] after [param delay] seconds, unless the run was reset meanwhile.
func _after(delay: float, action: Callable) -> void:
	var run_id := _run_id
	await get_tree().create_timer(delay, false).timeout
	if run_id == _run_id and is_inside_tree():
		action.call()
