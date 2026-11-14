class_name NetworkSession
extends Node
## Starts, joins and ends a co-op session.
##
## Uses Godot's built-in ENet networking with direct IP addresses: same PC, LAN, or a
## virtual LAN such as Tailscale. Steam networking will plug in here later; everything
## else talks to Godot's high-level multiplayer API, which works the same over any transport.
##
## When no session is running, the game uses an offline peer. Offline, this machine is
## peer 1 and counts as the host, so all host-only code runs as normal in solo play.

signal connected
signal failed(reason: String)
signal ended(reason: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
## Give up joining after this many seconds without an answer from the host.
const JOIN_TIMEOUT := 10.0

## Tests set this to pretend to be a different build.
var version_override := ""

## Why the host is about to drop us (for example a version mismatch). Shown instead of
## the generic "Host left" when the disconnect arrives.
var _end_reason := ""
## Increases on every join attempt, so an old timeout knows to do nothing.
var _join_id := 0


func _ready() -> void:
	add_to_group(&"network_session")
	multiplayer.connected_to_server.connect(func() -> void:
		_join_id += 1
		connected.emit()
	)
	multiplayer.connection_failed.connect(func() -> void:
		_join_id += 1
		leave()
		failed.emit("Could not connect")
	)
	multiplayer.server_disconnected.connect(func() -> void:
		var reason := _end_reason if _end_reason != "" else "Host left"
		leave()
		ended.emit(reason)
	)


## The game build version (Project Settings > Application > Config > Version).
## Host and joiner must match.
func get_game_version() -> String:
	if version_override != "":
		return version_override
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func host(port := DEFAULT_PORT) -> Error:
	_end_reason = ""
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	return error


func join(address: String, port := DEFAULT_PORT) -> Error:
	_end_reason = ""
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_join_id += 1
	var join_id := _join_id
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if join_id == _join_id:
			_join_id += 1
			leave()
			failed.emit("No response from host")
	)
	return OK


## Remembers why the host is dropping us, so the menu can say so.
func set_end_reason(reason: String) -> void:
	_end_reason = reason


## Ends any session and goes back to offline play.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
