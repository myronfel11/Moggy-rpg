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

## Host only.
var boss: PillarBoss
var sentinels: Array[Sentinel] = [null, null, null]

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
	_set_slot(slot, Slot.VULNERABLE)
	_apply_shields()
	_announce.rpc(&"pillar_down", slot)


func _on_sentinel_died(_enemy: Enemy, slot: int) -> void:
	sentinels[slot] = null
	if get_slot(slot) != Slot.VULNERABLE:
		return
	_set_slot(slot, Slot.BOMB_DROPPED)
	_announce.rpc(&"sentinel_down", slot)


func _on_boss_died(_enemy: Enemy) -> void:
	pass


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
		State.ENCOUNTER_FAILED, State.BOSS_DEFEATED:
			_revives.active = false
			if is_instance_valid(boss):
				boss.laser_enabled = false
			_clear_balls()


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
	# Every peer: pillars stand exactly while their slot is SHIELDED.
	var pillars := get_pillars()
	for i in SLOTS:
		if pillars[i] != null:
			pillars[i].set_intact(get_slot(i) == Slot.SHIELDED, _seen_slots[i] == Slot.SHIELDED)
	_seen_slots = slot_states.duplicate()


## Every peer: one-off messages and effects.
@rpc("authority", "call_local", "reliable")
func _announce(event: StringName, value: int) -> void:
	var hud := _level.get_hud() if _level != null else null
	match event:
		&"intro":
			if hud != null:
				hud.show_message("%s AWAKENS" % data.boss_name, data.intro_time)
		&"pillar_down":
			if hud != null:
				hud.show_message("PILLAR DOWN\nThe sentinel's shield is broken")
			get_tree().call_group(&"game_camera", &"add_trauma", 0.5)
		&"sentinel_down":
			if hud != null:
				hud.show_message("SENTINEL DESTROYED")
		&"state":
			state_entered.emit(value as State)
			if hud != null and value == State.SHIELDED_MECHANICS:
				hud.show_message("Lead the tracking balls into\nthe pillars of the same colour", 3.0)
