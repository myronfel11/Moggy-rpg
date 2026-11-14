class_name NetworkSession
extends Node
## Starts, joins and ends a co-op session.
##
## Uses Godot's built-in ENet networking with direct IP addresses (same PC or LAN).
## Swapping to Steam networking later only changes this file: everything else talks to
## Godot's high-level multiplayer API, which works the same over any transport.
##
## When no session is running, the game uses an offline peer. Offline, this machine is
## peer 1 and counts as the host, so all host-only code runs as normal in solo play.

signal connected
signal failed(reason: String)
signal ended(reason: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4


func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: connected.emit())
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		failed.emit("Could not connect")
	)
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		ended.emit("Host left")
	)


func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	return error


func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	return error


## Ends any session and goes back to offline play.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
