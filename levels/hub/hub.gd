class_name Hub
extends Level
## The safe room where friends meet: craft at the Fabricator, set up character and weapons
## at the Armory, and pick a mission at Navigation. Nothing here can hurt anyone.
##
## The host starts missions; everyone is taken along after a short countdown.

## Seconds between pressing Start and everyone travelling.
const START_DELAY := 3.0

var _starting := false


## Starts [param mission] for everyone. Host only.
func start_mission(mission: MissionData) -> void:
	if not multiplayer.is_server() or _starting or mission == null:
		return
	_starting = true
	_announce_start.rpc(mission.display_name)
	await get_tree().create_timer(START_DELAY, false).timeout
	if is_inside_tree():
		change_level_requested.emit(mission.level_scene, mission.resource_path)


## On every peer: close any open menu and show the countdown message.
@rpc("authority", "call_local", "reliable")
func _announce_start(mission_name: String) -> void:
	get_tree().call_group(&"open_panels", &"close")
	_hud.show_message("MISSION STARTING: %s" % mission_name.to_upper())


func is_starting() -> bool:
	return _starting
