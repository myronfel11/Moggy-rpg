class_name NavigationConsole
extends Station
## The hub's mission console. Anyone can look at missions; only the host can start one.

const PANEL := preload("res://ui/mission_panel.gd")

## Missions offered here, in list order.
@export var missions: Array[MissionData] = []


func get_prompt(_player: Player) -> String:
	return "[E] Choose a mission"


func _interact(player: Player) -> void:
	open_panel(player)


## Opens the mission list for this machine's player. Returns the panel (used by tests).
func open_panel(player: Player) -> MissionPanel:
	var hub := get_level() as Hub
	if hub == null or player.input.blocked:
		return null
	var panel := PANEL.new() as MissionPanel
	panel.hub = hub
	panel.missions = missions
	hub.add_child(panel)
	panel.open(player)
	return panel
