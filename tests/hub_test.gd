extends Node
## Plays the whole hub loop offline through the real Main scene, with saving switched off:
## hub -> craft -> armory -> start a mission -> clear it -> back to the hub with the loot,
## then a failed mission, then the save file. Run with tools\test.cmd:
##   godot --headless --fixed-fps 60 --path <project> res://tests/hub_test.tscn

const MAIN := preload("res://main/main.tscn")
const SUIT := "res://missions/data/suit.tres"
const CROWN := "res://missions/data/crown.tres"
const BLADE := preload("res://weapons/data/pulse_blade.tres")
const BREAKER := preload("res://weapons/data/breaker.tres")
const EMBER := preload("res://characters/data/ember.tres")
const VOLT := preload("res://characters/data/volt.tres")
const SCRAP := preload("res://items/data/scrap.tres")
const TEST_SAVE := "user://hub_test_profile.json"

var _checks := 0
var _failures := 0
var _main: Main


func _ready() -> void:
	_main = MAIN.instantiate() as Main
	add_child(_main)
	_main.profile.persistent = false
	_main.profile.reset()
	await _run()
	print("HUB TEST: %d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _player() -> Player:
	var level := _main.get_level()
	if level == null or level.local_player == null or not is_instance_valid(level.local_player):
		return null
	level.local_player.input.use_device = false
	return level.local_player


func _run() -> void:
	await _test_arrive_in_hub()
	await _test_craft()
	await _test_armory()
	await _test_mission_success()
	await _test_mission_failure()
	_test_save_file()


func _test_arrive_in_hub() -> void:
	print("Hub")
	_main.start_solo()
	await _frames(3)
	_check(_main.get_level() is Hub, "Play solo starts in the hub")
	var player := _player()
	_check(player != null, "this machine's player is in the hub")
	_check(player.loadout.size() == 1 and player.loadout[0] == BLADE, "a new profile carries the Pulse Blade")
	_check(player.character == VOLT, "a new profile uses the first character")
	_check(get_tree().get_nodes_in_group(&"enemies").is_empty(), "the hub has no enemies")


func _test_craft() -> void:
	print("Fabricator")
	var hub := _main.get_level() as Hub
	var player := _player()
	var fabricator := hub.get_node(^"CraftingStation") as CraftingStation
	var recipe := fabricator.get_next_recipe(player)
	for cost in recipe.costs:
		player.inventory.add(cost.item, cost.amount + 2)
	player.global_position = fabricator.global_position + Vector2(0.0, 24.0)
	await _frames(4)
	_check(fabricator.is_in_range(player), "the player can stand at the Fabricator")
	_check(fabricator.get_prompt(player).begins_with("[E]"), "the HUD prompt offers crafting")
	player.input.press_interact()
	await _frames(3)
	_check(player.owns_weapon(BREAKER), "crafting in the hub unlocks the Breaker")
	_check(player.loadout.size() == 2 and player.weapon.data == BREAKER, "it goes into the free slot and is equipped")
	_check(_main.profile.weapons.has(BREAKER.resource_path), "the profile records the new weapon")
	_check(_main.profile.materials.get(SCRAP.resource_path, 0) == 2, "the profile records the spent materials")


func _test_armory() -> void:
	print("Armory")
	var hub := _main.get_level() as Hub
	var player := _player()
	var armory := hub.get_node(^"ArmoryStation") as ArmoryStation
	player.global_position = armory.global_position + Vector2(-24.0, 0.0)
	await _frames(4)
	_check(armory.is_in_range(player), "the player can stand at the Armory")
	var panel := armory.open_panel(player)
	_check(panel != null and player.input.blocked, "the armory opens and blocks movement")
	var before := player.global_position
	player.input.move = Vector2.RIGHT
	await _frames(10)
	_check(player.global_position.distance_to(before) < 1.0, "the player cannot walk while a menu is open")
	panel.choose_character(EMBER)
	_check(player.character == EMBER and _main.profile.character == EMBER.resource_path, "choosing a character changes and saves it")
	panel.choose_slot(0, BREAKER)
	_check(player.loadout == [BREAKER, BLADE], "putting slot 2's weapon in slot 1 swaps them")
	panel.choose_slot(1, null)
	_check(player.loadout == [BREAKER], "slot 2 can be emptied")
	panel.choose_slot(0, null)
	_check(player.loadout == [BREAKER], "slot 1 cannot be emptied")
	panel.choose_slot(1, BLADE)
	_check(player.loadout == [BREAKER, BLADE], "slot 2 can be filled again")
	_check(Array(_main.profile.loadout) == [BREAKER.resource_path, BLADE.resource_path], "the profile records the loadout")
	panel.close()
	await _frames(2)
	_check(not player.input.blocked, "closing the armory gives control back")
	player.input.move = Vector2.ZERO


func _test_mission_success() -> void:
	print("Mission: success")
	var hub := _main.get_level() as Hub
	var player := _player()
	var console := hub.get_node(^"NavigationConsole") as NavigationConsole
	var panel := console.open_panel(player)
	_check(panel != null and panel.missions.size() == 4, "the console lists four missions")
	var suit_mission := load(SUIT) as MissionData
	panel.select(suit_mission)
	_check(panel._details.text.contains("Venza Suit - 40% on completion"), "the menu shows the reward and its chance")
	# Make the reward certain for this run so the test does not depend on luck.
	var real_chance := suit_mission.reward_chance
	suit_mission.reward_chance = 1.0
	panel.start()
	await _frames(2)
	_check(hub.is_starting() and not player.input.blocked, "starting closes the menu and begins the countdown")
	var arrived := await _until(func() -> bool: return _main.get_arena() != null and _player() != null, 300)
	_check(arrived, "everyone travels to the mission")
	var arena := _main.get_arena()
	player = _player()
	_check(arena.mission != null and arena.mission.resource_path == SUIT, "the arena runs the chosen mission")
	_check(player.character == EMBER, "the character comes along")
	_check(player.loadout == [BREAKER, BLADE], "the loadout comes along")
	_check(player.inventory.get_count(SCRAP) == 2, "the materials come along")

	var scrap_before := player.inventory.get_count(SCRAP)
	var result_text := [""]
	var repeated := [false]
	var back := await _until(func() -> bool:
		var current := _player()
		if current == null:
			return false
		if _main.get_level() is Hub:
			return true
		var level := _main.get_arena()
		if level != null and level._end_received and not repeated[0]:
			# Deliver the end-of-mission message a second time: it must not pay out again.
			repeated[0] = true
			result_text[0] = level.get_hud().get_message()
			level._announce_end(true, suit_mission.reward_item.resource_path)
		current.health.setup(1000000.0)
		TestBot.swing_and_dodge(current)
		return false, 60 * 120)
	suit_mission.reward_chance = real_chance
	_check(back, "clearing the last wave returns everyone to the hub")
	_check(result_text[0].contains("MISSION COMPLETE") and result_text[0].contains("Reward: Venza Suit"), "the result shows the reward (got '%s')" % result_text[0].replace("\n", " / "))
	player = _player()
	_check(player != null and player.inventory.get_count(SCRAP) > scrap_before, "the loot from the mission is kept (%d Scrap)" % (player.inventory.get_count(SCRAP) if player else 0))
	_check(_main.profile.has_completed(SUIT), "the mission is marked as cleared")
	_check(player.inventory.get_count(suit_mission.reward_item) == 1, "the reward is in the inventory exactly once")
	_check(_main.profile.materials.get(suit_mission.reward_item.resource_path, 0) == 1, "the reward is saved in the profile")
	_check(player.loadout == [BREAKER, BLADE] and player.character == EMBER, "loadout and character are kept")


func _test_mission_failure() -> void:
	print("Mission: failure")
	var hub := _main.get_level() as Hub
	hub.start_mission(load(CROWN) as MissionData)
	var arrived := await _until(func() -> bool: return _main.get_arena() != null and _player() != null, 300)
	_check(arrived, "a second mission starts")
	var director := _main.get_arena().get_node(^"WaveDirector") as WaveDirector
	await _until(func() -> bool: return director.wave >= 1, 300)
	_player().hurtbox.receive_hit(HitInfo.new(1000000.0))
	var back := await _until(func() -> bool: return _main.get_level() is Hub and _player() != null, 600)
	_check(back, "everyone down ends the mission and returns to the hub")
	_check(not _main.profile.has_completed(CROWN), "a failed mission is not marked as cleared")
	var crown_item := (load(CROWN) as MissionData).reward_item
	_check(_player().inventory.get_count(crown_item) == 0, "a failed mission gives no featured reward")
	_check(_player().is_alive(), "the player is back on their feet in the hub")


func _test_save_file() -> void:
	print("Save file")
	var profile := _main.profile
	profile.persistent = true
	profile.save_path = TEST_SAVE
	profile.save_to_disk()
	var copy := PlayerProfile.new()
	copy.save_path = TEST_SAVE
	copy.load_from_disk()
	_check(copy.to_dictionary() == profile.to_dictionary(), "a saved profile loads back identically")
	profile.persistent = false
	copy.free()

	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string('{"materials": {"res://nope.tres": 5, "%s": 3}, "weapons": ["res://gone.tres"], "character": "res://x.tres"}' % SCRAP.resource_path)
	file.close()
	var odd := PlayerProfile.new()
	odd.save_path = TEST_SAVE
	odd.load_from_disk()
	_check(odd.materials.size() == 1 and odd.materials[SCRAP.resource_path] == 3, "unknown items in a save are skipped")
	_check(Array(odd.weapons) == [PlayerProfile.DEFAULT_WEAPON] and odd.character == PlayerProfile.DEFAULT_CHARACTER, "unknown weapons and characters fall back to defaults")
	odd.free()

	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var broken := PlayerProfile.new()
	broken.save_path = TEST_SAVE
	broken.load_from_disk()
	_check(FileAccess.file_exists(TEST_SAVE + ".bad"), "a damaged save is kept aside as .bad")
	_check(Array(broken.weapons) == [PlayerProfile.DEFAULT_WEAPON], "a damaged save starts a fresh profile")
	broken.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + ".bad"))
