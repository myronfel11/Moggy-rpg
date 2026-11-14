class_name WaveDirector
extends Node
## Spawns waves of enemies so there is always something to fight.
##
## Milestone 1 scaffolding: each wave is one enemy larger than the last, up to a cap.
## When the player dies everything resets. Real missions will replace this later.

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
## Seconds between the player dying and the run restarting.
@export var respawn_delay := 1.5
## Enemies will not spawn closer to the player than this, in pixels.
@export var min_spawn_distance := 110.0

var wave := 0

var _player: Player
var _entities: Node2D
var _spawn_positions: Array[Vector2] = []
var _player_start := Vector2.ZERO
var _alive := 0
var _running := false
## Increases on every reset, so timers started before the reset know to do nothing.
var _run_id := 0


## Tells the director who the player is, where to put enemies, and where they may appear.
func setup(player: Player, entities: Node2D, spawn_points: Node) -> void:
	_player = player
	_entities = entities
	_player_start = player.global_position
	for child in spawn_points.get_children():
		var marker := child as Node2D
		if marker != null:
			_spawn_positions.append(marker.global_position)
	player.died.connect(_on_player_died)


## Begins spawning waves from wave 1.
func start() -> void:
	_running = true
	wave = 0
	_next_wave()


## Spawns one enemy. Also used directly by tests.
func spawn_enemy(type: EnemyData, at: Vector2) -> Enemy:
	var enemy := type.scene.instantiate() as Enemy
	enemy.data = type
	enemy.position = at
	enemy.died.connect(_on_enemy_died)
	_entities.add_child(enemy)
	_alive += 1
	return enemy


func _next_wave() -> void:
	wave += 1
	var count := mini(first_wave_size + (wave - 1) * wave_growth, max_wave_size)
	var elites := mini(_elite_count(wave), count)
	var positions := _pick_spawn_positions(count)
	for i in count:
		spawn_enemy(elite_type if i < elites else enemy_type, positions[i])
	wave_started.emit(wave, count)


## How many of a wave's enemies are elites. Elites replace regular enemies, they are not extra.
func _elite_count(wave_number: int) -> int:
	if elite_type == null or wave_number < elite_from_wave:
		return 0
	@warning_ignore("integer_division")
	return 1 + (wave_number - elite_from_wave) / maxi(elite_every, 1)


func _pick_spawn_positions(count: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	for point in _spawn_positions:
		if point.distance_to(_player.global_position) >= min_spawn_distance:
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


func _on_player_died() -> void:
	if _running:
		_after(respawn_delay, _reset_run)


func _reset_run() -> void:
	_run_id += 1
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_alive = 0
	_player.respawn(_player_start)
	start()


## Calls [param action] after [param delay] seconds, unless the run was reset meanwhile.
func _after(delay: float, action: Callable) -> void:
	var run_id := _run_id
	await get_tree().create_timer(delay, false).timeout
	if run_id == _run_id and is_inside_tree():
		action.call()
