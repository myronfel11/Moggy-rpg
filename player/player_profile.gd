class_name PlayerProfile
extends Node
## This machine's player progress: materials, owned weapons, loadout, character and
## completed missions. Saved as JSON on this PC only; each player keeps their own.
##
## Player nodes are rebuilt whenever the group travels between the hub and a mission, so
## anything that must last lives here. Level calls apply_to() when this machine's player
## spawns and watch() to keep the profile up to date as the player plays.
##
## Everything is stored as resource file paths (res://...), which stay stable as code
## changes. Paths that no longer exist are skipped when loading.

const DEFAULT_WEAPON := "res://weapons/data/pulse_blade.tres"
const DEFAULT_CHARACTER := "res://characters/data/volt.tres"
## Pickups are saved at most this often; crafting and loadout changes save at once.
const AUTOSAVE_DELAY := 5.0
const SAVE_FORMAT := 1

## False: never touch the disk (tests, --no-save).
var persistent := true
var save_path := "user://profile.json"

## Item file path -> count.
var materials: Dictionary = {}
var weapons := PackedStringArray([DEFAULT_WEAPON])
var loadout := PackedStringArray([DEFAULT_WEAPON])
var character := DEFAULT_CHARACTER
var completed_missions := PackedStringArray()

var _save_pending := false


func _ready() -> void:
	add_to_group(&"player_profile")


func _exit_tree() -> void:
	save_to_disk()


## Back to a brand-new profile (does not touch the disk).
func reset() -> void:
	materials = {}
	weapons = PackedStringArray([DEFAULT_WEAPON])
	loadout = PackedStringArray([DEFAULT_WEAPON])
	character = DEFAULT_CHARACTER
	completed_missions = PackedStringArray()


## Loads the save file if there is one. A damaged file is renamed to *.bad and a fresh
## profile is used, so a bad save never stops the game from starting.
func load_from_disk() -> void:
	if not persistent or not FileAccess.file_exists(save_path):
		return
	var text := FileAccess.get_file_as_string(save_path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_warning("Save file %s is damaged; starting fresh and keeping it as .bad" % save_path)
		DirAccess.rename_absolute(save_path, save_path + ".bad")
		reset()
		return
	from_dictionary(data)


func save_to_disk() -> void:
	_save_pending = false
	if not persistent:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(to_dictionary(), "\t"))


func to_dictionary() -> Dictionary:
	return {
		"format": SAVE_FORMAT,
		"materials": materials,
		"weapons": Array(weapons),
		"loadout": Array(loadout),
		"character": character,
		"completed_missions": Array(completed_missions),
	}


func from_dictionary(data: Dictionary) -> void:
	reset()
	var saved_materials: Variant = data.get("materials", {})
	if saved_materials is Dictionary:
		for path: Variant in saved_materials:
			var count := int(saved_materials[path])
			if path is String and count > 0 and ResourceLoader.exists(path):
				materials[path] = count
	weapons = _existing_paths(data.get("weapons", []), weapons)
	loadout = _existing_paths(data.get("loadout", []), loadout)
	var saved_character := str(data.get("character", ""))
	if ResourceLoader.exists(saved_character):
		character = saved_character
	completed_missions = _existing_paths(data.get("completed_missions", []), PackedStringArray())


## Puts this profile onto a freshly spawned player.
func apply_to(player: Player) -> void:
	var counts := {}
	for path: String in materials:
		counts[path] = materials[path]
	player.inventory.set_counts(counts)
	var owned: Array[WeaponData] = []
	for path in weapons:
		var weapon := load(path) as WeaponData
		if weapon != null:
			owned.append(weapon)
	var chosen: Array[WeaponData] = []
	for path in loadout:
		var weapon := load(path) as WeaponData
		if weapon != null:
			chosen.append(weapon)
	player.set_weapons(owned, chosen)
	var look := load(character) as CharacterData
	if look != null:
		player.set_character(look)


## Keeps the profile in step with the player from now on.
func watch(player: Player) -> void:
	player.inventory.changed.connect(func(_item: ItemData, _count: int, _change: int) -> void:
		capture(player)
		_save_soon()
	)
	for change_signal: Signal in [player.loadout_changed, player.weapon_unlocked, player.character_changed]:
		change_signal.connect(func(_arg: Variant = null) -> void:
			capture(player)
			save_to_disk()
		)


## Copies the player's current state into the profile.
func capture(player: Player) -> void:
	materials = player.inventory.get_counts()
	weapons = PackedStringArray()
	for weapon in player.weapons:
		weapons.append(weapon.resource_path)
	loadout = PackedStringArray()
	for weapon in player.loadout:
		loadout.append(weapon.resource_path)
	if player.character != null:
		character = player.character.resource_path


func mark_mission_completed(mission_path: String) -> void:
	if not completed_missions.has(mission_path):
		completed_missions.append(mission_path)
		save_to_disk()


func has_completed(mission_path: String) -> bool:
	return completed_missions.has(mission_path)


func _save_soon() -> void:
	if _save_pending or not persistent or not is_inside_tree():
		return
	_save_pending = true
	await get_tree().create_timer(AUTOSAVE_DELAY).timeout
	if _save_pending:
		save_to_disk()


func _existing_paths(saved: Variant, fallback: PackedStringArray) -> PackedStringArray:
	if not saved is Array:
		return fallback
	var result := PackedStringArray()
	for path: Variant in saved:
		if path is String and ResourceLoader.exists(path) and not result.has(path):
			result.append(path)
	return result if not result.is_empty() or fallback.is_empty() else fallback
