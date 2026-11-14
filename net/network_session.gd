class_name NetworkSession
extends Node
## Starts, joins and ends a co-op session.
##
## Two ways to connect, both ending in a Godot MultiplayerPeer, so the rest of the game
## does not care which was used:
##   - Direct IP over ENet: same PC, LAN, or a virtual LAN such as Tailscale.
##   - Steam: the host opens a Steam lobby, others find it in a list, and game traffic goes
##     through Steam's relay servers. Works between homes with no router setup.
##
## When no session is running, the game uses an offline peer. Offline, this machine is
## peer 1 and counts as the host, so all host-only code runs as normal in solo play.
##
## Steam is only started when a Steam button is pressed, so solo play and the automated
## tests never need Steam.

signal connected
signal failed(reason: String)
signal ended(reason: String)
## A Steam lobby is ready and this machine is hosting it. Load the level now.
signal steam_hosted
## Results of find_steam_games(): an Array of {"id": int, "host": String, "players": int}.
signal steam_games_found(games: Array)
## The player accepted a Steam invite (or chose "Join game" on a friend) for this lobby.
signal steam_join_requested(lobby_id: int)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
## Give up joining after this many seconds without an answer from the host.
const JOIN_TIMEOUT := 15.0
## Steam's shared test app, used until the game has its own Steam app ID.
const STEAM_APP_ID := 480
## Our lobbies are tagged with this, because app 480 is shared with other developers.
const STEAM_LOBBY_TAG := "moggy_rpg_dev"
## Steam's result code for success.
const STEAM_RESULT_OK := 1
const STEAM_LOBBY_PUBLIC := 2
const STEAM_COMPARE_EQUAL := 0
const STEAM_DISTANCE_WORLDWIDE := 3

## Tests set this to pretend to be a different build.
var version_override := ""

## Why the host is about to drop us (for example a version mismatch). Shown instead of
## the generic "Host left" when the disconnect arrives.
var _end_reason := ""
## Increases on every join attempt, so an old timeout knows to do nothing.
var _join_id := 0
## The Steam API object once Steam has started, else null.
var _steam: Object
## The Steam lobby this machine is in, or 0.
var _lobby_id := 0
var _hosting_steam := false


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
	_start_join_timeout()
	return OK


## Fails the join if the host has not answered within JOIN_TIMEOUT seconds.
func _start_join_timeout() -> void:
	_join_id += 1
	var join_id := _join_id
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if join_id == _join_id:
			_join_id += 1
			leave()
			failed.emit("No response from host")
	)


# --- Steam -----------------------------------------------------------------------------

## Starts Steam if needed. Returns "" when Steam is ready, otherwise the reason it is not.
func start_steam() -> String:
	if _steam != null:
		return ""
	if not Engine.has_singleton("Steam") or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return "The Steam add-on is missing from this build"
	var steam := Engine.get_singleton("Steam")
	# true = GodotSteam runs Steam's callbacks every frame for us.
	var result: Dictionary = steam.call("steamInitEx", STEAM_APP_ID, true)
	if int(result.get("status", -1)) != 0:
		return "Steam is not available. Start Steam and sign in. (%s)" % result.get("verbal", "")
	_steam = steam
	_steam.connect("lobby_created", _on_steam_lobby_created)
	_steam.connect("lobby_joined", _on_steam_lobby_joined)
	_steam.connect("lobby_match_list", _on_steam_lobby_match_list)
	_steam.connect("join_requested", func(lobby_id: int, _friend_id: int) -> void:
		steam_join_requested.emit(lobby_id)
	)
	print("Steam started for ", _steam.call("getPersonaName"))
	return ""


## Opens a Steam lobby and hosts in it. Returns "" if started (steam_hosted follows),
## otherwise the reason it could not start.
func host_steam() -> String:
	var problem := start_steam()
	if problem != "":
		return problem
	leave()
	_end_reason = ""
	_hosting_steam = true
	_steam.call("createLobby", STEAM_LOBBY_PUBLIC, MAX_PLAYERS)
	return ""


## Asks Steam for open games of this version. Results arrive through steam_games_found.
func find_steam_games() -> String:
	var problem := start_steam()
	if problem != "":
		return problem
	_steam.call("addRequestLobbyListDistanceFilter", STEAM_DISTANCE_WORLDWIDE)
	_steam.call("addRequestLobbyListStringFilter", "game", STEAM_LOBBY_TAG, STEAM_COMPARE_EQUAL)
	_steam.call("addRequestLobbyListStringFilter", "version", get_game_version(), STEAM_COMPARE_EQUAL)
	_steam.call("requestLobbyList")
	return ""


## Joins a Steam game found with find_steam_games() or through an invite.
func join_steam(lobby_id: int) -> String:
	var problem := start_steam()
	if problem != "":
		return problem
	leave()
	_end_reason = ""
	_hosting_steam = false
	_steam.call("joinLobby", lobby_id)
	_start_join_timeout()
	return ""


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if not _hosting_steam:
		return
	if result != STEAM_RESULT_OK:
		_hosting_steam = false
		failed.emit("Steam could not create a game (error %d)" % result)
		return
	_lobby_id = lobby_id
	_steam.call("setLobbyData", lobby_id, "game", STEAM_LOBBY_TAG)
	_steam.call("setLobbyData", lobby_id, "version", get_game_version())
	_steam.call("setLobbyData", lobby_id, "host", _steam.call("getPersonaName"))
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var error: int = peer.call("host_with_lobby", lobby_id)
	if error != OK:
		leave()
		failed.emit("Could not host through Steam (error %d)" % error)
		return
	multiplayer.multiplayer_peer = peer
	print("Hosting Steam lobby ", lobby_id)
	steam_hosted.emit()


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# Steam also reports joining for the lobby we just created as host; nothing to do then.
	if _hosting_steam:
		return
	if response != STEAM_RESULT_OK:
		_join_id += 1
		failed.emit("Could not join that Steam game (it may be full or closed)")
		return
	_lobby_id = lobby_id
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var error: int = peer.call("connect_to_lobby", lobby_id)
	if error != OK:
		_join_id += 1
		leave()
		failed.emit("Could not connect through Steam (error %d)" % error)
		return
	multiplayer.multiplayer_peer = peer
	print("Joined Steam lobby ", lobby_id, ", connecting to the host")


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	var games := []
	for lobby_id: int in lobbies:
		games.append({
			"id": lobby_id,
			"host": _steam.call("getLobbyData", lobby_id, "host"),
			"players": _steam.call("getNumLobbyMembers", lobby_id),
		})
	steam_games_found.emit(games)


## Remembers why the host is dropping us, so the menu can say so.
func set_end_reason(reason: String) -> void:
	_end_reason = reason


## Ends any session and goes back to offline play.
func leave() -> void:
	if _lobby_id != 0 and _steam != null:
		_steam.call("leaveLobby", _lobby_id)
	_lobby_id = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
