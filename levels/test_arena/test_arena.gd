class_name Arena
extends Level
## A mission room: waves of enemies in one arena.
##
## Started from the hub with a MissionData (mission_path), it ends when the mission's
## last wave is cleared or every player is down, then sends everyone back to the hub.
## Without a mission (tests, balance probe) waves go on forever, as before.

## Seconds the "mission complete/failed" message shows before returning to the hub.
const END_DELAY := 4.0
## Seconds between arriving and the first wave.
const START_DELAY := 2.0
## Seconds the mission result stays on screen.
const RESULT_TIME := 3.6

## Tests switch this off so they can spawn enemies themselves.
@export var auto_start := true

var mission: MissionData

## Host: the end of the mission was already announced.
var _end_sent := false
## Every peer: the end-of-mission message was already handled (no double rewards).
var _end_received := false

@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _director: WaveDirector = $WaveDirector


func _setup_level() -> void:
	_director.setup(self, _spawn_points)
	if mission_path != "":
		mission = load(mission_path) as MissionData
		if mission != null:
			_director.apply_mission(mission)
	_director.mission_ended.connect(_on_mission_ended)


func _start_level() -> void:
	if not auto_start:
		return
	# A moment to get bearings, and time for every client to finish building this level
	# before the host's first wave messages reach it.
	_hud.show_message(mission.display_name.to_upper() if mission != null else "GET READY")
	await get_tree().create_timer(START_DELAY, false).timeout
	if is_inside_tree():
		_director.start()


func _get_director() -> WaveDirector:
	return _director


## Creates an enemy on every peer. Host only.
func spawn_enemy(type: EnemyData, at: Vector2) -> Enemy:
	return _spawn({"kind": "enemy", "data": type.resource_path, "position": at}) as Enemy


func _spawn_entity(data: Dictionary) -> Node:
	if data.get("kind", "") == "enemy":
		var type := load(data.data) as EnemyData
		var enemy := type.scene.instantiate() as Enemy
		enemy.data = type
		enemy.position = data.position
		enemy.net_position = data.position
		return enemy
	return super(data)


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


func _on_mission_ended(success: bool) -> void:
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
