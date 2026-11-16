extends Node
## Runs the arena with a bot, then saves a picture of the screen.
##
## Usage (opens a window and runs in real time):
##   godot --path <project> res://tests/screenshot.tscn -- --out=C:/somewhere/shot.png --frames=200
##
## --frames is how long to play first (60 frames = 1 second). --when picks the moment:
##   --when=swing      the player mid-swing (default)
##   --when=telegraph  an enemy about to lunge
##   --when=brute      fighting a Plated Brute (waits for one to appear)
##   --when=station    standing at the Fabricator with enough materials
##   --when=crafted    just after crafting at the Fabricator
##   --when=zenith_hint  Venza holding the blade, so the Zenith charge hint shows

const ARENA := preload("res://levels/test_arena/test_arena.tscn")
## Give up waiting for the chosen moment after this many extra frames.
const MAX_EXTRA_FRAMES := 4200
const BRUTE_DISTANCE := 70.0


func _ready() -> void:
	var out := "user://screenshot.png"
	var frames := 200
	var when := "swing"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument.begins_with("--frames="):
			frames = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--when="):
			when = argument.trim_prefix("--when=")

	var arena := ARENA.instantiate()
	add_child(arena)
	var player := (arena as Arena).local_player
	# The Fabricator lives in the hub now; put one in the arena for these tests.
	var station := preload("res://crafting/crafting_station.tscn").instantiate() as CraftingStation
	station.position = Vector2(320.0, 96.0)
	arena.add_child(station)
	player.input.use_device = false
	if when == "zenith_hint":
		# Venza holding a weapon other than her pistols, so the Zenith hint shows.
		var venza := load("res://characters/data/venza.tres") as CharacterData
		player.unlock_character(venza)
		player.set_character(venza)
		var blade_and_pistols: Array[WeaponData] = [player.weapons[0], venza.signature_weapon]
		player.set_loadout(blade_and_pistols)
		player.equip(player.weapons[0])
		player.abilities.set_zenith_charge(35.0)

	var frame := 0
	while frame < frames + MAX_EXTRA_FRAMES:
		TestBot.swing_and_dodge(player)
		await get_tree().physics_frame
		frame += 1
		if frame >= frames and _is_the_moment(when, player):
			break

	if when == "station" or when == "crafted":
		TestBot.stop(player)
		var recipe := station.get_next_recipe(player)
		if recipe != null:
			for cost in recipe.costs:
				player.inventory.add(cost.item, cost.amount)
		player.global_position = station.global_position + Vector2(0.0, 24.0)
		player.velocity = Vector2.ZERO
		await _frames(12)
		if when == "crafted":
			player.input.press_interact()
			await _frames(12)

	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1000:
		image.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var error := image.save_png(out)
	print("Screenshot: ", out, " ", image.get_size(), " frame=", frame, " error=", error)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _is_the_moment(when: String, player: Player) -> bool:
	match when:
		"telegraph":
			return _any_chaser(func(chaser: Chaser) -> bool: return chaser.is_lunge_locked())
		"brute":
			return player.weapon.is_busy() and _any_chaser(func(chaser: Chaser) -> bool:
				var near := chaser.global_position.distance_to(player.global_position) < BRUTE_DISTANCE
				return near and chaser.data.armor > 0.0
			)
		"station", "crafted":
			return true
		_:
			return player.weapon != null and player.weapon.is_busy()


func _any_chaser(condition: Callable) -> bool:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var chaser := node as Chaser
		if chaser != null and not chaser.is_dead() and condition.call(chaser):
			return true
	return false
