class_name Level
extends Node2D
## Base class for every room players can be in: the hub and mission arenas.
##
## Handles what all rooms share: one player per connected peer, created through
## EntitySpawner so every peer builds the same nodes; the version check when a client
## joins; camera and HUD for this machine's player; loading this machine's saved profile
## into its player; teammate joined/left messages; and asking Main to travel elsewhere.
##
## Subclasses override _setup_level() and _start_level() and add their own nodes.
## Required child nodes: Entities, EntitySpawner, PlayerStart, GameCamera, HUD.

## Emitted on every peer when any player appears.
signal player_spawned(player: Player)
## Emitted once, when this machine's own player appears.
signal local_player_ready(player: Player)
## Emitted on every peer when any player disappears (left or disconnected).
signal player_left(peer_id: int)
## Host only: asks Main to replace this level for everyone.
signal change_level_requested(scene_path: String, mission_path: String)

const PLAYER_SCENE := preload("res://player/player.tscn")
const HUB_SCENE := "res://levels/hub/hub.tscn"
## Gap between players who spawn at the same time, in pixels.
const PLAYER_SPACING := 20.0
## Seconds between telling a refused client why and disconnecting it.
const REJECT_DELAY := 0.5
## Seconds the "mission complete/failed" message shows before returning to the hub.
const END_DELAY := 4.0
## Seconds the mission result stays on screen.
const RESULT_TIME := 3.6

## Recipes shown in the HUD goal line and offered by any Fabricator in this level.
@export var recipe_book: RecipeBook = preload("res://crafting/data/recipe_book.tres")

## This machine's player. Null until it has spawned.
var local_player: Player
## The MissionData file this level was started for, or "" (set by Main before _ready).
var mission_path := ""
## The mission loaded from mission_path, or null (hub, tests).
var mission: MissionData

## Host: the end of the mission was already announced.
var _end_sent := false
## Every peer: the end-of-mission message was already handled (no double rewards).
var _end_received := false

@onready var _entities: Node2D = $Entities
@onready var _entity_spawner: MultiplayerSpawner = $EntitySpawner
@onready var _player_start: Marker2D = $PlayerStart
@onready var _camera: GameCamera = $GameCamera
@onready var _hud: Hud = $HUD


func _ready() -> void:
	add_to_group(&"level")
	_entity_spawner.spawn_function = _spawn_entity
	_entity_spawner.spawned.connect(_on_entity_spawned)
	if mission_path != "":
		mission = load(mission_path) as MissionData
	_setup_level()
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_spawn_player(multiplayer.get_unique_id())
		_start_level()
	else:
		_request_player.rpc_id(1, _get_session_version())


## Override: prepare the level. Runs on every peer before any player spawns.
func _setup_level() -> void:
	pass


## Override: start the level's activity. Host only, after the host's player spawned.
func _start_level() -> void:
	pass


## Override: the wave director to show on the HUD, if this level has one.
func _get_director() -> WaveDirector:
	return null


## The start point, used for first spawns and respawns.
func get_player_start() -> Vector2:
	return _player_start.global_position


func get_players() -> Array[Player]:
	var players: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.is_inside_tree():
			players.append(player)
	return players


func get_hud() -> Hud:
	return _hud


## The player controlled by network peer [param peer], or null.
func get_player_by_peer(peer: int) -> Player:
	for player in get_players():
		if player.peer_id == peer:
			return player
	return null


## This machine's saved progress. Without Main (tests), a temporary unsaved one.
func get_profile() -> PlayerProfile:
	var profile := get_tree().get_first_node_in_group(&"player_profile") as PlayerProfile
	if profile == null:
		profile = PlayerProfile.new()
		profile.persistent = false
		add_child(profile)
	return profile


## A joining client asks for its player. The host refuses a client running a different
## build, because mismatched code or scenes break the session in confusing ways.
@rpc("any_peer", "call_remote", "reliable")
func _request_player(version: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var own_version := _get_session_version()
	if version != own_version:
		var reason := "Version mismatch: host has %s, you have %s. Both pull the latest main." % [
			own_version, version,
		]
		_rejected.rpc_id(peer, reason)
		# Let the message arrive before hanging up.
		await get_tree().create_timer(REJECT_DELAY).timeout
		if multiplayer.has_multiplayer_peer() and peer in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_spawn_player(peer)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	var session := _get_session()
	if session != null:
		session.set_end_reason(reason)


func _get_session() -> NetworkSession:
	return get_tree().get_first_node_in_group(&"network_session") as NetworkSession


func _get_session_version() -> String:
	var session := _get_session()
	if session != null:
		return session.get_game_version()
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func _spawn_player(peer: int) -> void:
	if _entities.has_node(NodePath("Player%d" % peer)):
		return
	var offset := Vector2(PLAYER_SPACING * get_players().size(), 0.0)
	var player := _spawn({"kind": "player", "peer": peer, "position": get_player_start() + offset}) as Player
	_on_entity_spawned(player)


## Spawns through the MultiplayerSpawner when online, and directly when offline.
func _spawn(data: Dictionary) -> Node:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return _entity_spawner.spawn(data)
	var node := _spawn_entity(data)
	_entities.add_child(node, true)
	return node


## Builds a player (or, in subclasses, other entities) from spawn data. Runs on every peer
## with the same data.
func _spawn_entity(data: Dictionary) -> Node:
	if data.get("kind", "") == "player":
		var peer: int = data.peer
		var player := PLAYER_SCENE.instantiate() as Player
		player.name = "Player%d" % peer
		player.peer_id = peer
		player.position = data.position
		player.net_position = data.position
		player.set_multiplayer_authority(peer)
		return player
	if data.get("kind", "") == "enemy":
		var type := load(data.data) as EnemyData
		var enemy := type.scene.instantiate() as Enemy
		enemy.data = type
		enemy.position = data.position
		enemy.net_position = data.position
		for property: String in data.get("props", {}):
			enemy.set(property, data.props[property])
		return enemy
	if data.get("kind", "") == "scene":
		# Any other host-created object (boss projectiles, bombs): a scene plus properties.
		var node := (load(data.path) as PackedScene).instantiate()
		node.set(&"position", data.position)
		for property: String in data.get("props", {}):
			node.set(property, data.props[property])
		return node
	push_error("Unknown spawn data: %s" % data)
	return Node.new()


## Creates an enemy on every peer. Host only. [param props] are set on it before it is
## added (for example which pillar a boss turret belongs to).
func spawn_enemy(type: EnemyData, at: Vector2, props := {}) -> Enemy:
	return _spawn({"kind": "enemy", "data": type.resource_path, "position": at, "props": props}) as Enemy


## Creates any scene on every peer. Host only. Its name is kept unique automatically.
func spawn_scene(path: String, at: Vector2, props := {}) -> Node:
	return _spawn({"kind": "scene", "path": path, "position": at, "props": props})


## Rolls a mission's featured reward once. Returns the item's file path, or "" if the roll
## missed or the mission has no featured reward.
static func roll_reward(for_mission: MissionData) -> String:
	if for_mission == null or for_mission.reward_item == null:
		return ""
	if randf() < for_mission.reward_chance:
		return for_mission.reward_item.resource_path
	return ""


## Text for the end-of-mission message.
static func describe_result(for_mission: MissionData, success: bool, reward_path: String) -> String:
	if not success:
		return "MISSION FAILED"
	if for_mission == null or for_mission.reward_item == null:
		return "MISSION COMPLETE"
	var item_name := for_mission.reward_item.display_name
	if reward_path != "":
		return "MISSION COMPLETE\nReward: %s" % item_name
	return "MISSION COMPLETE\nNo %s this time (%d%% chance)" % [
		item_name, roundi(for_mission.reward_chance * 100.0),
	]


## Ends the mission for everyone: result message, reward, then back to the hub. Host only;
## a second call does nothing.
func finish_mission(success: bool) -> void:
	if not multiplayer.is_server() or _end_sent:
		return
	_end_sent = true
	# The host rolls once for the whole group: everyone gets the reward or nobody does.
	var reward_path := roll_reward(mission) if success else ""
	_announce_end.rpc(success, reward_path)
	await get_tree().create_timer(END_DELAY, false).timeout
	if is_inside_tree():
		change_level_requested.emit(HUB_SCENE, "")


## On every peer: show the result, give this machine's player the reward, hand over loot
## still on the ground, record the clear. Runs at most once per mission.
@rpc("authority", "call_local", "reliable")
func _announce_end(success: bool, reward_path: String) -> void:
	if _end_received:
		return
	_end_received = true
	_hud.show_message(describe_result(mission, success, reward_path), RESULT_TIME)
	if local_player != null and is_instance_valid(local_player) and reward_path != "":
		local_player.inventory.add(load(reward_path) as ItemData)
	if local_player != null and is_instance_valid(local_player):
		for node in get_tree().get_nodes_in_group(&"pickups"):
			var pickup := node as Pickup
			if pickup != null and not pickup.is_queued_for_deletion():
				local_player.inventory.add(pickup.item, pickup.amount)
				pickup.queue_free()
	if success and mission != null:
		get_profile().mark_mission_completed(mission.resource_path)


func _on_entity_spawned(node: Node) -> void:
	var player := node as Player
	if player == null:
		return
	player_spawned.emit(player)
	var peer := player.peer_id
	player.tree_exiting.connect(func() -> void: _on_player_exiting.call_deferred(peer))
	if not player.is_local():
		_hud.show_message("TEAMMATE JOINED")
	if player.is_local() and local_player == null:
		local_player = player
		var profile := get_profile()
		profile.apply_to(player)
		profile.watch(player)
		_camera.target = player
		_camera.snap_to_target()
		_hud.bind(player, recipe_book, _get_director())
		local_player_ready.emit(player)


## Runs a moment after a player node is removed. If the whole level is closing, it is no
## longer in the tree by then and stays quiet.
func _on_player_exiting(peer: int) -> void:
	if not is_inside_tree():
		return
	player_left.emit(peer)
	if local_player == null or not is_instance_valid(local_player) or local_player.peer_id != peer:
		_hud.show_message("TEAMMATE LEFT")


func _on_peer_disconnected(peer: int) -> void:
	var player := _entities.get_node_or_null(NodePath("Player%d" % peer))
	if player != null:
		player.queue_free()
