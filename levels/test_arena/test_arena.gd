class_name Arena
extends Node2D
## The test room: one arena, endless waves, one player per connected peer.
##
## Players and enemies are created through EntitySpawner so that, in co-op, every peer
## builds the same nodes with the same names. The host spawns everything; clients only
## ask for their own player. Offline (solo and tests) this machine is the host.

## Emitted on every peer when any player appears.
signal player_spawned(player: Player)
## Emitted once, when this machine's own player appears.
signal local_player_ready(player: Player)

const PLAYER_SCENE := preload("res://player/player.tscn")
## Gap between players who spawn at the same time, in pixels.
const PLAYER_SPACING := 20.0

## Tests switch this off so they can spawn enemies themselves.
@export var auto_start := true

## This machine's player. Null until it has spawned.
var local_player: Player

@onready var _entities: Node2D = $Entities
@onready var _entity_spawner: MultiplayerSpawner = $EntitySpawner
@onready var _player_start: Marker2D = $PlayerStart
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _director: WaveDirector = $WaveDirector
@onready var _station: CraftingStation = $CraftingStation
@onready var _camera: GameCamera = $GameCamera
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_entity_spawner.spawn_function = _spawn_entity
	_entity_spawner.spawned.connect(_on_entity_spawned)
	_director.setup(self, _spawn_points)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_spawn_player(multiplayer.get_unique_id())
		if auto_start:
			_director.start()
	else:
		_request_player.rpc_id(1)


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


## Creates an enemy on every peer. Host only.
func spawn_enemy(type: EnemyData, at: Vector2) -> Enemy:
	var data := {"kind": "enemy", "data": type.resource_path, "position": at}
	var enemy := _spawn(data) as Enemy
	return enemy


@rpc("any_peer", "call_remote", "reliable")
func _request_player() -> void:
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_remote_sender_id())


func _spawn_player(peer: int) -> void:
	if _entities.has_node(NodePath("Player%d" % peer)):
		return
	var offset := Vector2(PLAYER_SPACING * get_players().size(), 0.0)
	var player := _spawn({"kind": "player", "peer": peer, "position": get_player_start() + offset}) as Player
	_on_entity_spawned(player)


## Spawns through the MultiplayerSpawner when it is allowed to, and directly otherwise.
func _spawn(data: Dictionary) -> Node:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return _entity_spawner.spawn(data)
	var node := _spawn_entity(data)
	_entities.add_child(node, true)
	return node


## Builds a player or enemy from spawn data. Runs on every peer with the same data.
func _spawn_entity(data: Dictionary) -> Node:
	match data.get("kind", ""):
		"player":
			var peer: int = data.peer
			var player := PLAYER_SCENE.instantiate() as Player
			player.name = "Player%d" % peer
			player.peer_id = peer
			player.position = data.position
			player.net_position = data.position
			player.set_multiplayer_authority(peer)
			return player
		"enemy":
			var type := load(data.data) as EnemyData
			var enemy := type.scene.instantiate() as Enemy
			enemy.data = type
			enemy.position = data.position
			enemy.net_position = data.position
			return enemy
	push_error("Unknown spawn data: %s" % data)
	return Node.new()


func _on_entity_spawned(node: Node) -> void:
	var player := node as Player
	if player == null:
		return
	player_spawned.emit(player)
	if player.is_local() and local_player == null:
		local_player = player
		_camera.target = player
		_camera.snap_to_target()
		_hud.bind(player, _director, _station)
		local_player_ready.emit(player)


func _on_peer_disconnected(peer: int) -> void:
	var player := _entities.get_node_or_null(NodePath("Player%d" % peer))
	if player != null:
		player.queue_free()
