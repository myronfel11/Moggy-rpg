class_name Arena
extends Level
## A mission room: waves of enemies in one arena.
##
## Started from the hub with a MissionData (mission_path), it ends when the mission's
## last wave is cleared or every player is down, then sends everyone back to the hub.
## Without a mission (tests, balance probe) waves go on forever, as before.
## Spawning enemies and ending missions live in Level, shared with the boss arena.

## Seconds between arriving and the first wave.
const START_DELAY := 2.0

## Tests switch this off so they can spawn enemies themselves.
@export var auto_start := true

@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _director: WaveDirector = $WaveDirector


func _setup_level() -> void:
	_director.setup(self, _spawn_points)
	if mission != null:
		_director.apply_mission(mission)
	_director.mission_ended.connect(finish_mission)


func _start_level() -> void:
	if not auto_start:
		return
	# A moment to get bearings, and time for every client to finish building this level
	# before the host's first wave messages reach it.
	_hud.show_message(mission.display_name.to_upper() if mission != null else "GET READY")
	await get_tree().create_timer(START_DELAY, false).timeout
	if is_inside_tree():
		_director.start()


func _get_director() -> WaveDirector:
	return _director
