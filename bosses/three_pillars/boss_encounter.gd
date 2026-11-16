class_name BossEncounter
extends Node
## The brain of "The Three Pillars". The host runs it; clients receive its state.
##
## Two kinds of state, both in one place:
##   - state: which phase of the fight it is (a strict state machine; only the transitions
##     in ALLOWED are possible, so the fight can never jump to a wrong phase).
##   - slot_states: one entry per pillar/sentinel/bomb trio, each only ever moving forward
##     (SHIELDED -> VULNERABLE -> BOMB_DROPPED <-> BOMB_CARRIED -> DELIVERED). Every event
##     checks the slot's state first, so a repeated or late event does nothing.
## Everything else is derived from these (bombs delivered, boss shield, vulnerability), so
## there are no separate flags that could disagree.

## Announced to every peer for messages and effects.
signal state_entered(state: State)

enum State {
	ENCOUNTER_START,
	SHIELDED_MECHANICS,
	DAMAGE_PHASE_1,
	HEALTH_GATE_TRANSITION,
	SHIELDED_MECHANICS_2,
	FINAL_DAMAGE_PHASE,
	BOSS_DEFEATED,
	ENCOUNTER_FAILED,
}
enum Slot { SHIELDED, VULNERABLE, BOMB_DROPPED, BOMB_CARRIED, DELIVERED }

const SLOTS := 3
## Loaded when the fight begins, not preloaded: the boss scripts refer back to this class,
## and preloading each other in a loop can leave a resource loaded without its script.
const BOSS_DATA_PATH := "res://bosses/three_pillars/data/pillar_boss.tres"
const SENTINEL_DATA_PATH := "res://bosses/three_pillars/data/sentinel.tres"
const DATA_PATH := "res://bosses/three_pillars/data/three_pillars.tres"
const BOMB_SCENE := "res://bosses/three_pillars/bomb.tscn"
## Extra distance allowed when the host checks a pickup or slam (players move a little
## between finishing the hold on their screen and the request arriving).
const REACH_SLACK := 24.0
## Seconds between the boss falling and the mission result.
const DEFEAT_DELAY := 1.5
## Which phase may follow which. Anything else is refused.
const ALLOWED := {
	State.ENCOUNTER_START: [State.SHIELDED_MECHANICS, State.ENCOUNTER_FAILED],
	State.SHIELDED_MECHANICS: [State.DAMAGE_PHASE_1, State.ENCOUNTER_FAILED],
	State.DAMAGE_PHASE_1: [State.HEALTH_GATE_TRANSITION, State.ENCOUNTER_FAILED],
	State.HEALTH_GATE_TRANSITION: [State.SHIELDED_MECHANICS_2, State.ENCOUNTER_FAILED],
	State.SHIELDED_MECHANICS_2: [State.FINAL_DAMAGE_PHASE, State.ENCOUNTER_FAILED],
	State.FINAL_DAMAGE_PHASE: [State.BOSS_DEFEATED, State.ENCOUNTER_FAILED],
	State.BOSS_DEFEATED: [],
	State.ENCOUNTER_FAILED: [],
}
const STATE_NAMES := [
	"ENCOUNTER_START", "SHIELDED_MECHANICS", "DAMAGE_PHASE_1", "HEALTH_GATE_TRANSITION",
	"SHIELDED_MECHANICS_2", "FINAL_DAMAGE_PHASE", "BOSS_DEFEATED", "ENCOUNTER_FAILED",
]

## All tunable numbers. Set in boss_arena.tscn; tests swap in a copy with short timings.
@export var data: ThreePillarsData
## Tests switch this off to drive the encounter themselves.
@export var auto_start := true

## Synced: the current phase.
var state := State.ENCOUNTER_START
## Synced: one Slot value per pillar.
var slot_states := PackedInt32Array([Slot.SHIELDED, Slot.SHIELDED, Slot.SHIELDED])
## Synced: revives the team has left.
var revives_left := 0
## Synced: per slot, the network peer carrying its bomb (0 when nobody does).
var carriers := PackedInt32Array([0, 0, 0])
## Synced: per slot, how many matching balls its pillar has taken this cycle.
var pillar_damage := PackedInt32Array([0, 0, 0])

## Host only.
var boss: PillarBoss
var sentinels: Array[Sentinel] = [null, null, null]
var bombs: Array[Bomb] = [null, null, null]

var _level: Level
var _revives: ReviveRules
var _seen_slots := PackedInt32Array([Slot.SHIELDED, Slot.SHIELDED, Slot.SHIELDED])


func _ready() -> void:
	add_to_group(&"boss_encounter")
	if data == null:
		data = load(DATA_PATH) as ThreePillarsData


## Called by the arena on every peer.
func setup(level: Level) -> void:
	_level = level
	for pillar in get_pillars():
		pillar.setup_color(data.slot_colors[pillar.slot])
	_revives = ReviveRules.new()
	add_child(_revives)
	_revives.setup(level, data.revive_pool, data.revive_delay)
	_revives.revives_changed.connect(func(left: int) -> void: revives_left = left)
	_revives.all_players_down.connect(func() -> void: fail())
	revives_left = data.revive_pool


func get_pillars() -> Array[Pillar]:
	var pillars: Array[Pillar] = [null, null, null]
	for node in get_tree().get_nodes_in_group(&"pillars"):
		var pillar := node as Pillar
		if pillar != null and pillar.slot < SLOTS:
			pillars[pillar.slot] = pillar
	return pillars


## Host: starts the fight after the intro.
func start() -> void:
	if not multiplayer.is_server():
		return
	_announce.rpc(&"intro", -1)
	await get_tree().create_timer(data.intro_time, false).timeout
	if not is_inside_tree() or state != State.ENCOUNTER_START:
		return
	begin()


## Host: spawns the boss and sentinels and enters the first mechanic phase.
func begin() -> void:
	var players := maxi(_level.get_players().size(), 1)
	var health := data.boss_health * (1.0 + data.health_per_extra_player * (players - 1))
	var center := (_level.get_node(^"BossPoint") as Node2D).global_position
	boss = _level.spawn_enemy(load(BOSS_DATA_PATH) as EnemyData, center, {"max_health_override": health}) as PillarBoss
	boss.died.connect(_on_boss_died)
	boss.health.reached_minimum.connect(_on_boss_reached_gate)
	_spawn_sentinels()
	_revives.active = true
	set_state(State.SHIELDED_MECHANICS)


func _spawn_sentinels() -> void:
	var points := _level.get_node(^"SentinelPoints").get_children()
	for i in SLOTS:
		var at := (points[i] as Node2D).global_position
		var sentinel := _level.spawn_enemy(load(SENTINEL_DATA_PATH) as EnemyData, at, {
			"slot": i, "max_health_override": data.sentinel_health,
		}) as Sentinel
		sentinel.died.connect(_on_sentinel_died.bind(i))
		sentinels[i] = sentinel


## True if [param to] may follow [param from].
static func can_transition(from: State, to: State) -> bool:
	return to in ALLOWED[from]


## Host: moves to [param to] if the transition is allowed. Returns false (and changes
## nothing) otherwise.
func set_state(to: State) -> bool:
	if not can_transition(state, to):
		push_warning("Boss encounter: refused %s -> %s" % [STATE_NAMES[state], STATE_NAMES[to]])
		return false
	state = to
	_on_state_entered(to)
	_announce.rpc(&"state", to)
	return true


func get_slot(slot: int) -> Slot:
	return slot_states[slot] as Slot


func _set_slot(slot: int, value: Slot) -> void:
	var updated := slot_states.duplicate()
	updated[slot] = value
	slot_states = updated


func is_mechanics_state() -> bool:
	return state == State.SHIELDED_MECHANICS or state == State.SHIELDED_MECHANICS_2


func is_boss_vulnerable() -> bool:
	return state == State.DAMAGE_PHASE_1 or state == State.FINAL_DAMAGE_PHASE


## Sentinels fire while the mechanics are on (they stop in damage phases and at the end).
func sentinels_active() -> bool:
	return is_mechanics_state()


func get_bombs_delivered() -> int:
	var count := 0
	for value in slot_states:
		if value == Slot.DELIVERED:
			count += 1
	return count


## The boss's shield, 1.0 (full) to 0.0, from the bombs delivered.
func get_shield_ratio() -> float:
	if is_boss_vulnerable() or state == State.BOSS_DEFEATED:
		return 0.0
	return 1.0 - float(get_bombs_delivered()) / SLOTS


func count_balls(slot: int) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"tracking_balls"):
		var ball := node as TrackingBall
		if ball != null and ball.slot == slot and not ball.is_queued_for_deletion():
			count += 1
	return count


## Bodies tracking balls fly through (the boss's core).
func get_ball_ignored_bodies() -> Array[RID]:
	var ignored: Array[RID] = []
	var current_boss := get_tree().get_first_node_in_group(&"pillar_boss") as PillarBoss
	if current_boss != null:
		var core := current_boss.get_node_or_null(^"Core") as CollisionObject2D
		if core != null:
			ignored.append(core.get_rid())
	return ignored


## Host: a tracking ball reached its own pillar.
func on_ball_hit_pillar(slot: int) -> void:
	if not multiplayer.is_server() or not is_mechanics_state() or get_slot(slot) != Slot.SHIELDED:
		return
	var updated := pillar_damage.duplicate()
	updated[slot] += 1
	# Assign a new array: the synchronizer only notices a changed value.
	pillar_damage = updated
	if updated[slot] < data.pillar_hits:
		# Send the count itself: the synced array may reach clients after this message.
		_announce.rpc(&"pillar_hit", updated[slot])
		return
	_set_slot(slot, Slot.VULNERABLE)
	_apply_shields()
	_announce.rpc(&"pillar_down", slot)


func _on_sentinel_died(enemy: Enemy, slot: int) -> void:
	sentinels[slot] = null
	if get_slot(slot) != Slot.VULNERABLE:
		return
	# Exactly one bomb per sentinel: the slot can only pass through here once per cycle.
	_set_slot(slot, Slot.BOMB_DROPPED)
	bombs[slot] = _level.spawn_scene(BOMB_SCENE, enemy.global_position, {"slot": slot}) as Bomb
	_announce.rpc(&"sentinel_down", slot)


# --- Bombs --------------------------------------------------------------------------------

## The slot whose bomb [param peer] carries, or -1.
func get_carried_slot(peer: int) -> int:
	for i in SLOTS:
		if get_slot(i) == Slot.BOMB_CARRIED and carriers[i] == peer:
			return i
	return -1


## Any peer: this machine's player finished holding E on a bomb. The host decides.
func ask_pickup(slot: int, player: Player) -> void:
	if multiplayer.is_server():
		request_pickup(slot, player.peer_id)
	else:
		_rpc_pickup.rpc_id(1, slot)


## Any peer: this machine's player finished holding E at the boss. The host decides.
func ask_slam(player: Player) -> void:
	if multiplayer.is_server():
		request_slam(player.peer_id)
	else:
		_rpc_slam.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pickup(slot: int) -> void:
	request_pickup(slot, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_slam() -> void:
	request_slam(multiplayer.get_remote_sender_id())


## Host: gives the bomb in [param slot] to [param peer] if that is allowed right now.
## Returns true if they got it. The first valid request wins; later ones find the slot
## no longer BOMB_DROPPED.
func request_pickup(slot: int, peer: int) -> bool:
	if not multiplayer.is_server() or slot < 0 or slot >= SLOTS:
		return false
	if not is_mechanics_state() or get_slot(slot) != Slot.BOMB_DROPPED or not is_instance_valid(bombs[slot]):
		return false
	var player := _level.get_player_by_peer(peer)
	if player == null or not player.is_alive() or get_carried_slot(peer) >= 0:
		return false
	var reach := (bombs[slot].get_node(^"Range/CollisionShape2D").shape as CircleShape2D).radius + REACH_SLACK
	if player.global_position.distance_to(bombs[slot].global_position) > reach:
		return false
	_set_carrier(slot, peer)
	_set_slot(slot, Slot.BOMB_CARRIED)
	bombs[slot].carrier_peer = peer
	_announce.rpc(&"bomb_picked", slot)
	return true


## Host: [param peer] slams their bomb into the boss, if allowed. Returns true if it counted.
## Each bomb counts once: its slot becomes DELIVERED and can never move back.
func request_slam(peer: int) -> bool:
	if not multiplayer.is_server() or not is_mechanics_state():
		return false
	var slot := get_carried_slot(peer)
	var player := _level.get_player_by_peer(peer)
	if slot < 0 or player == null or not player.is_alive() or not is_instance_valid(boss):
		return false
	if player.global_position.distance_to(boss.global_position) > data.slam_range + REACH_SLACK:
		return false
	_set_carrier(slot, 0)
	_set_slot(slot, Slot.DELIVERED)
	if is_instance_valid(bombs[slot]):
		bombs[slot].queue_free()
	bombs[slot] = null
	_announce.rpc(&"bomb_slammed", slot)
	if get_bombs_delivered() == SLOTS:
		set_state(State.DAMAGE_PHASE_1 if state == State.SHIELDED_MECHANICS else State.FINAL_DAMAGE_PHASE)
	return true


func _set_carrier(slot: int, peer: int) -> void:
	var updated := carriers.duplicate()
	updated[slot] = peer
	carriers = updated


## Host: a carrier who died, left or disconnected drops the bomb where they were, so the
## fight can never get stuck with a bomb nobody can reach.
func _drop_abandoned_bombs() -> void:
	for i in SLOTS:
		if get_slot(i) != Slot.BOMB_CARRIED:
			continue
		var carrier := _level.get_player_by_peer(carriers[i])
		if carrier != null and carrier.is_alive():
			continue
		_set_carrier(i, 0)
		_set_slot(i, Slot.BOMB_DROPPED)
		if is_instance_valid(bombs[i]):
			bombs[i].carrier_peer = 0
			bombs[i].position.y += 15.0
		_announce.rpc(&"bomb_dropped", i)


# --- Damage phases --------------------------------------------------------------------------

## Host: the boss's health hit the 50% floor during the first damage phase.
func _on_boss_reached_gate() -> void:
	if state != State.DAMAGE_PHASE_1:
		return
	set_state(State.HEALTH_GATE_TRANSITION)


## Host: puts every pillar, sentinel and slot back to the start of the mechanic.
func _reset_mechanics() -> void:
	_clear_balls()
	for i in SLOTS:
		if is_instance_valid(bombs[i]):
			bombs[i].queue_free()
		bombs[i] = null
		if is_instance_valid(sentinels[i]):
			sentinels[i].queue_free()
		sentinels[i] = null
	slot_states = PackedInt32Array([Slot.SHIELDED, Slot.SHIELDED, Slot.SHIELDED])
	carriers = PackedInt32Array([0, 0, 0])
	pillar_damage = PackedInt32Array([0, 0, 0])
	_spawn_sentinels()


func _after_gate() -> void:
	await get_tree().create_timer(data.gate_time, false).timeout
	if not is_inside_tree() or state != State.HEALTH_GATE_TRANSITION:
		return
	_reset_mechanics()
	set_state(State.SHIELDED_MECHANICS_2)


func _on_boss_died(_enemy: Enemy) -> void:
	if not multiplayer.is_server() or not set_state(State.BOSS_DEFEATED):
		return
	await get_tree().create_timer(DEFEAT_DELAY, false).timeout
	if is_inside_tree():
		_level.finish_mission(true)


## Host: everyone is down with no revives left.
func fail() -> void:
	if not multiplayer.is_server() or not set_state(State.ENCOUNTER_FAILED):
		return
	_level.finish_mission(false)


func _on_state_entered(to: State) -> void:
	_apply_shields()
	match to:
		State.SHIELDED_MECHANICS:
			boss.laser_enabled = true
		State.DAMAGE_PHASE_1:
			# The health gate: damage cannot take the boss below this until the gate passes.
			boss.health.minimum = boss.health.max_health * data.health_gate
			_clear_balls()
		State.HEALTH_GATE_TRANSITION:
			_after_gate()
		State.FINAL_DAMAGE_PHASE:
			boss.health.minimum = 0.0
			_clear_balls()
		State.ENCOUNTER_FAILED, State.BOSS_DEFEATED:
			_revives.active = false
			if is_instance_valid(boss):
				boss.laser_enabled = false
			_clear_balls()
			for i in SLOTS:
				if is_instance_valid(bombs[i]):
					bombs[i].queue_free()
				bombs[i] = null


## Host: sentinel shields and boss vulnerability always follow the slot and phase state.
func _apply_shields() -> void:
	for i in SLOTS:
		if is_instance_valid(sentinels[i]):
			sentinels[i].shielded = get_slot(i) == Slot.SHIELDED
	if is_instance_valid(boss):
		boss.vulnerable = is_boss_vulnerable()


func _clear_balls() -> void:
	for node in get_tree().get_nodes_in_group(&"tracking_balls"):
		(node as TrackingBall).pop()


func _process(_delta: float) -> void:
	if multiplayer.is_server() and _level != null:
		_drop_abandoned_bombs()
		_apply_shields()
	# Every peer: pillars stand exactly while their slot is SHIELDED.
	var pillars := get_pillars()
	for i in SLOTS:
		if pillars[i] != null:
			pillars[i].set_intact(get_slot(i) == Slot.SHIELDED, _seen_slots[i] == Slot.SHIELDED)
			pillars[i].set_damage(pillar_damage[i], data.pillar_hits)
	_seen_slots = slot_states.duplicate()


## Every peer: one-off messages and effects.
@rpc("authority", "call_local", "reliable")
func _announce(event: StringName, value: int) -> void:
	var hud := _level.get_hud() if _level != null else null
	match event:
		&"intro":
			if hud != null:
				hud.show_message("%s AWAKENS" % data.boss_name, data.intro_time)
		&"pillar_hit":
			if hud != null:
				hud.show_message("PILLAR CRACKED  %d/%d" % [value, data.pillar_hits], 1.5)
			get_tree().call_group(&"game_camera", &"add_trauma", 0.25)
		&"pillar_down":
			if hud != null:
				hud.show_message("PILLAR DOWN\nThe sentinel's shield is broken")
			get_tree().call_group(&"game_camera", &"add_trauma", 0.5)
		&"sentinel_down":
			if hud != null:
				hud.show_message("SENTINEL DESTROYED\nIt dropped a bomb - hold E to pick it up")
		&"bomb_picked":
			if hud != null and _level.local_player != null and carriers[value] == _level.local_player.peer_id:
				hud.show_message("Carry the bomb to the Warden\nand hold E to slam it")
		&"bomb_dropped":
			if hud != null:
				hud.show_message("A BOMB WAS DROPPED")
		&"bomb_slammed":
			get_tree().call_group(&"game_camera", &"add_trauma", 0.8)
			var current_boss := get_tree().get_first_node_in_group(&"pillar_boss") as PillarBoss
			if current_boss != null:
				current_boss.play_slam_effect()
			if hud != null:
				hud.show_message("SHIELD CRACKED  %d/3" % get_bombs_delivered())
		&"state":
			state_entered.emit(value as State)
			if hud == null:
				return
			match value:
				State.SHIELDED_MECHANICS:
					hud.show_message("Lead the tracking balls into\nthe pillars of the same colour", 3.0)
				State.DAMAGE_PHASE_1, State.FINAL_DAMAGE_PHASE:
					get_tree().call_group(&"game_camera", &"add_trauma", 1.0)
					var shield_boss := get_tree().get_first_node_in_group(&"pillar_boss") as PillarBoss
					if shield_boss != null:
						shield_boss.play_shield_break_effect()
					hud.show_message("SHIELD BROKEN\nATTACK THE WARDEN!", 3.0)
				State.HEALTH_GATE_TRANSITION:
					get_tree().call_group(&"game_camera", &"add_trauma", 0.6)
					hud.show_message("THE WARDEN RESTORES ITS SHIELD\nThe pillars rise again", data.gate_time + 0.5)
				State.SHIELDED_MECHANICS_2:
					hud.show_message("Break the pillars once more", 2.5)
				State.BOSS_DEFEATED:
					get_tree().call_group(&"game_camera", &"add_trauma", 1.0)
					hud.show_message("%s DEFEATED" % data.boss_name, 3.0)
