class_name Main
extends Node
## Entry point: a small menu to play solo, host, or join, then loads the hub.
##
## The host decides which level everyone is in (hub or a mission) and adds it under World;
## the LevelSpawner copies it to every client, including ones that join later. Levels ask
## to travel with change_level_requested; only the host acts on it.
##
## Command-line shortcuts skip the menu (used by tools\host.cmd, tools\join.cmd and the
## tests): -- --solo, -- --host, -- --join=ADDRESS, --port=N.
## Save file options: --profile=NAME (separate save, e.g. a second window on one PC) and
## --no-save (keep progress in memory only).

const ARENA := preload("res://levels/test_arena/test_arena.tscn")
const HUB := preload("res://levels/hub/hub.tscn")

var _port := NetworkSession.DEFAULT_PORT
## From --mission=PATH: the first level loaded is this mission instead of the hub.
var _start_mission := ""

@onready var session: NetworkSession = $NetworkSession
@onready var profile: PlayerProfile = $Profile
@onready var world: Node = $World
@onready var _spawner: MultiplayerSpawner = $LevelSpawner
@onready var _menu: CanvasLayer = $Menu
@onready var _address: LineEdit = $Menu/Panel/Address
@onready var _status: Label = $Menu/Panel/Status
@onready var _steam_games: VBoxContainer = $Menu/Panel/SteamGames


func _ready() -> void:
	_spawner.spawn_function = _build_level
	_spawner.add_spawnable_scene(ARENA.resource_path)
	_spawner.add_spawnable_scene(HUB.resource_path)
	$Menu/Panel/Solo.pressed.connect(start_solo)
	$Menu/Panel/Host.pressed.connect(start_host)
	$Menu/Panel/Join.pressed.connect(func() -> void: start_join(_address.text))
	$Menu/Panel/SteamHost.pressed.connect(start_steam_host)
	$Menu/Panel/SteamFind.pressed.connect(find_steam_games)
	session.connected.connect(func() -> void: _menu.visible = false)
	session.failed.connect(_back_to_menu)
	session.ended.connect(_back_to_menu)
	session.steam_hosted.connect(_load_hub)
	session.steam_games_found.connect(_show_steam_games)
	session.steam_join_requested.connect(start_steam_join)
	multiplayer.peer_connected.connect(func(id: int) -> void: print("Peer connected: ", id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: print("Peer left: ", id))

	var join_address := ""
	var mode := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			profile.save_path = "user://profile_%s.json" % argument.trim_prefix("--profile=").validate_filename()
		elif argument == "--no-save":
			profile.persistent = false
	profile.load_from_disk()
	if "--dev-unlock-venza" in OS.get_cmdline_user_args():
		_dev_unlock_venza()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument == "--solo" or argument == "--host":
			mode = argument.trim_prefix("--")
		elif argument.begins_with("--mission="):
			_start_mission = argument.trim_prefix("--mission=")
		elif argument.begins_with("--join="):
			mode = "join"
			join_address = argument.trim_prefix("--join=")
	match mode:
		"solo":
			start_solo()
		"host":
			start_host()
		"join":
			start_join(join_address)


## Developer shortcut for playtesting (tools\play_venza.cmd): unlocks Venza and her
## pistols in the current profile without farming the parts. Use with a separate
## --profile so the real save is not touched.
func _dev_unlock_venza() -> void:
	var venza := "res://characters/data/venza.tres"
	var pistols := "res://weapons/data/twin_sparrows.tres"
	if not profile.characters.has(venza):
		profile.characters.append(venza)
	if not profile.weapons.has(pistols):
		profile.weapons.append(pistols)
	profile.loadout = PackedStringArray([pistols, PlayerProfile.DEFAULT_WEAPON])
	profile.character = venza
	print("Developer unlock: Venza and the Twin Sparrows")


## The level currently loaded (hub or mission), or null while on the menu.
func get_level() -> Level:
	for child in world.get_children():
		if child is Level and not child.is_queued_for_deletion():
			return child
	return null


## The mission arena currently loaded, or null.
func get_arena() -> Arena:
	return get_level() as Arena


func start_solo() -> void:
	session.leave()
	_load_hub()


func start_host() -> void:
	var error := session.host(_port)
	if error != OK:
		_status.text = "Could not host on port %d (error %d)" % [_port, error]
		return
	print("Hosting on port ", _port)
	_load_hub()


func start_join(address: String) -> void:
	if address.strip_edges() == "":
		address = "127.0.0.1"
	var error := session.join(address.strip_edges(), _port)
	if error != OK:
		_status.text = "Could not start joining (error %d)" % error
		return
	print("Joining ", address, ":", _port)
	_status.text = "Joining %s..." % address


func start_steam_host() -> void:
	_clear_steam_games()
	var problem := session.host_steam()
	_status.text = problem if problem != "" else "Opening a Steam game..."


func find_steam_games() -> void:
	_clear_steam_games()
	var problem := session.find_steam_games()
	_status.text = problem if problem != "" else "Searching Steam..."


func start_steam_join(lobby_id: int) -> void:
	_clear_steam_games()
	var problem := session.join_steam(lobby_id)
	_status.text = problem if problem != "" else "Joining through Steam..."


func _show_steam_games(games: Array) -> void:
	_clear_steam_games()
	if games.is_empty():
		_status.text = "No Steam games found. A new game can take a few seconds to show up; try again."
		return
	_status.text = "Pick a game to join:"
	for game: Dictionary in games:
		var button := Button.new()
		button.add_theme_font_size_override(&"font_size", 8)
		button.text = "Join %s (%d/%d)" % [game.host, game.players, NetworkSession.MAX_PLAYERS]
		var lobby_id: int = game.id
		button.pressed.connect(func() -> void: start_steam_join(lobby_id))
		_steam_games.add_child(button)


func _clear_steam_games() -> void:
	for child in _steam_games.get_children():
		child.queue_free()


func _load_hub() -> void:
	if _start_mission != "":
		# --mission=PATH: go straight into a mission (playtest shortcuts and tests).
		var mission := load(_start_mission) as MissionData
		_start_mission = ""
		if mission != null:
			change_level(mission.level_scene, mission.resource_path)
			return
	change_level(HUB.resource_path)


## Replaces the current level for everyone. Host only (offline counts as host).
func change_level(scene_path: String, mission_path := "") -> void:
	if not multiplayer.is_server():
		return
	profile.save_to_disk()
	_clear_world()
	var data := {"scene": scene_path, "mission": mission_path}
	var level: Level
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		level = _build_level(data)
		world.add_child(level, true)
	else:
		level = _spawner.spawn(data) as Level
	level.change_level_requested.connect(change_level)
	_menu.visible = false


## Builds a level from spawn data. Runs on the host and on every client.
func _build_level(data: Dictionary) -> Node:
	var level := (load(data.scene) as PackedScene).instantiate() as Level
	level.mission_path = data.get("mission", "")
	return level


func _clear_world() -> void:
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()


func _back_to_menu(reason := "") -> void:
	profile.save_to_disk()
	_clear_world()
	_menu.visible = true
	_status.text = reason


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _menu.visible:
		get_tree().quit()
	else:
		session.leave()
		_back_to_menu()
