class_name Recipe
extends Resource
## What a crafting station can make, and what it costs. Stored as a .tres file.
##
## A recipe produces either a weapon (result) or a playable character
## (result_character). More kinds of result (armour, upgrades) can be added here later
## without changing the Fabricator or its menu.

## Unique name used by code and, later, by save files.
@export var id: StringName
## The weapon the player receives. Leave empty for a character recipe.
@export var result: WeaponData
## The character the player unlocks. Leave empty for a weapon recipe.
@export var result_character: CharacterData
## Materials consumed. Name each item only once.
@export var costs: Array[ItemAmount] = []


## Name of what this recipe makes.
func get_result_name() -> String:
	if result_character != null:
		return result_character.display_name
	return result.display_name if result != null else str(id)


## True if the player already has what this recipe makes (it cannot be crafted twice).
func is_owned_by(player: Player) -> bool:
	if result_character != null:
		return player.owns_character(result_character)
	return player.owns_weapon(result)


## Gives the player what this recipe makes. Does not take any materials.
func grant_to(player: Player) -> void:
	if result_character != null:
		player.unlock_character(result_character)
	elif result != null:
		player.unlock_weapon(result)
