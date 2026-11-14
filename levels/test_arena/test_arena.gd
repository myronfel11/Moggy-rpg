extends Node2D
## The Milestone 1 test room: one arena, endless waves.
##
## This root script only introduces the pieces to each other (camera, wave director,
## HUD). It runs after all its children are ready, so every piece exists by then.

## Tests switch this off so they can spawn enemies themselves.
@export var auto_start := true

@onready var _player: Player = $Entities/Player
@onready var _entities: Node2D = $Entities
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _director: WaveDirector = $WaveDirector
@onready var _station: CraftingStation = $CraftingStation
@onready var _camera: GameCamera = $GameCamera
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_camera.target = _player
	_camera.snap_to_target()
	_director.setup(_player, _entities, _spawn_points)
	_hud.bind(_player, _director, _station)
	if auto_start:
		_director.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
