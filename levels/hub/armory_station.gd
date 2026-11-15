class_name ArmoryStation
extends Station
## The hub's armory: choose a character and which owned weapons to carry.

const PANEL := preload("res://ui/armory_panel.gd")

## Characters offered here.
@export var characters: Array[CharacterData] = []


func get_prompt(_player: Player) -> String:
	return "[E] Armory: character and weapons"


func _interact(player: Player) -> void:
	open_panel(player)


## Opens the armory for this machine's player. Returns the panel (used by tests).
func open_panel(player: Player) -> ArmoryPanel:
	var level := get_level()
	if level == null or player.input.blocked:
		return null
	var panel := PANEL.new() as ArmoryPanel
	panel.characters = characters
	level.add_child(panel)
	panel.open(player)
	return panel
