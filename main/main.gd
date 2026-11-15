class_name Main
extends Node
## Entry point: a small menu to play solo, host, or join, then loads the arena.
##
## The host adds the arena under World; the LevelSpawner copies it to every client that
## joins. Command-line shortcuts skip the menu (used by tools\host.cmd, tools\join.cmd and
## the network test): -- --solo, -- --host, -- --join=ADDRESS, plus --port=N.

const ARENA := preload("res://levels/test_arena/test_arena.tscn")

var _port := NetworkSession.DEFAULT_PORT

@onready var session: NetworkSession = $NetworkSession
@onready var world: Node = $World
@onready var _spawner: MultiplayerSpawner = $LevelSpawner
@onready var _menu: CanvasLayer = $Menu
@onready var _address: LineEdit = $Menu/Panel/Address
@onready var _status: Label = $Menu/Panel/Status
@onready var _steam_games: VBoxContainer = $Menu/Panel/SteamGames


func _ready() -> void:
	_spawner.add_spawnable_scene(ARENA.resource_path)
	$Menu/Panel/Solo.pressed.connect(start_solo)
	$Menu/Panel/Host.pressed.connect(start_host)
	$Menu/Panel/Join.pressed.connect(func() -> void: start_join(_address.text))
	$Menu/Panel/SteamHost.pressed.connect(start_steam_host)
	$Menu/Panel/SteamFind.pressed.connect(find_steam_games)
	session.connected.connect(func() -> void: _menu.visible = false)
	session.failed.connect(_back_to_menu)
	session.ended.connect(_back_to_menu)
	session.steam_hosted.connect(_load_arena)
	session.steam_games_found.connect(_show_steam_games)
	session.steam_join_requested.connect(start_steam_join)
	multiplayer.peer_connected.connect(func(id: int) -> void: print("Peer connected: ", id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: print("Peer left: ", id))

	var join_address := ""
	var mode := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument == "--solo" or argument == "--host":
			mode = argument.trim_prefix("--")
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


## The arena currently loaded, or null while on the menu.
func get_arena() -> Arena:
	return world.get_child(0) as Arena if world.get_child_count() > 0 else null


func start_solo() -> void:
	session.leave()
	_load_arena()


func start_host() -> void:
	var error := session.host(_port)
	if error != OK:
		_status.text = "Could not host on port %d (error %d)" % [_port, error]
		return
	print("Hosting on port ", _port)
	_load_arena()


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


func _load_arena() -> void:
	_clear_world()
	world.add_child(ARENA.instantiate(), true)
	_menu.visible = false


func _clear_world() -> void:
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()


func _back_to_menu(reason := "") -> void:
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
