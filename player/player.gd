class_name Player
extends CharacterBody2D
## The player character: movement, dash, and using whatever weapon is equipped.
##
## Each physics tick (60 times a second) this script:
##   1. asks PlayerInput what the player wants to do,
##   2. updates its state (moving or dashing),
##   3. lets the equipped weapon advance its attack,
##   4. moves, sliding along walls.
## Weapon stats and behaviour come from a WeaponData file, so this script does not
## change when new weapons are added.

signal died
signal respawned
signal dashed
## Emitted when a different weapon is equipped.
signal weapon_changed(data: WeaponData)
## Emitted when the player presses interact. Nearby things (crafting stations) listen.
signal interact_requested(player: Player)
## Emitted when a weapon is owned for the first time (crafted).
signal weapon_unlocked(data: WeaponData)
## Emitted when the carried weapons change.
signal loadout_changed
## Emitted when the character (look) changes.
signal character_changed(data: CharacterData)

enum State { MOVE, DASH, DEAD }

const GHOST_INTERVAL := 0.035
const GHOST_FADE_TIME := 0.18
const GHOST_COLOR := Color(0.35, 0.9, 1.0, 0.55)
const BLINK_PERIOD := 0.1
const RESPAWN_PROTECTION := 1.0
const KILL_SHAKE_BONUS := 0.2
## How many weapons a player carries into a fight.
const LOADOUT_SLOTS := 2
## How quickly another peer's player glides to its reported position. Higher is snappier.
const PUPPET_SMOOTHING := 25.0
## Further off than this (respawn, lag spike), jump instead of gliding. In pixels.
const PUPPET_SNAP_DISTANCE := 64.0

@export_group("Movement")
## Top running speed in pixels per second. One floor tile is 16 pixels.
@export var max_speed := 120.0
## How fast the player reaches top speed. Higher is snappier.
@export var acceleration := 1400.0
## How fast the player stops when no direction is held. Higher means less sliding.
@export var friction := 1800.0

@export_group("Dash")
## Speed during the dash. Distance covered is dash_speed x dash_duration.
@export var dash_speed := 420.0
## How long the dash lasts, in seconds.
@export var dash_duration := 0.14
## Seconds after a dash ends before another can start.
@export var dash_cooldown := 0.45
## Extra seconds of invulnerability after the dash ends, as a small grace period.
@export var dash_iframes_extra := 0.06

@export_group("Combat")
## The weapon equipped at the start.
@export var starting_weapon: WeaponData
## Seconds of invulnerability after taking a hit, so one mistake is not several hits.
@export var hurt_iframes := 0.6
## Screen shake when the player is hit (0 to 1).
@export var hurt_shake := 0.6

## Synced to other peers, who use it to show dashing, death and respawning.
var state := State.MOVE:
	set(value):
		var was := state
		state = value
		if is_node_ready() and not is_local() and was != value:
			_on_remote_state_changed(was, value)
## The network peer that controls this player (1 is the host, or solo play).
var peer_id := 1
## Where the owner says this player is. Other peers glide toward it.
var net_position := Vector2.ZERO
## Where the owner is aiming. Other peers point the weapon this way.
var net_aim := Vector2.RIGHT
## The equipped weapon's data file, so other peers show the same weapon.
var net_weapon_path := "":
	set(value):
		net_weapon_path = value
		if is_node_ready() and not is_local():
			_equip_from_path(value)
## The character's data file, so other peers show the same character.
var net_character_path := "":
	set(value):
		net_character_path = value
		if is_node_ready() and not is_local():
			_character_from_path(value)
## The equipped weapon's behaviour node. Its stats are in weapon.data.
var weapon: WeaponBehavior
## Every weapon this player owns, in the order they were obtained.
var weapons: Array[WeaponData] = []
## The weapons carried into fights (at most LOADOUT_SLOTS). Q swaps between them.
var loadout: Array[WeaponData] = []
## How the player looks. Chosen in the armory.
var character: CharacterData

var _dash_direction := Vector2.RIGHT
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _ghost_timer := 0.0
## Seconds of invulnerability remaining ("i-frames").
var _iframes := 0.0
var _blinking := false
## Seconds of impact freeze remaining.
var _hit_stop := 0.0

@onready var input: PlayerInput = $PlayerInput
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var inventory: Inventory = $Inventory
@onready var visual: FlashVisual = $Visual
@onready var weapon_pivot: Node2D = $WeaponPivot


func _ready() -> void:
	add_to_group(&"players")
	hurtbox.hit_received.connect(_on_hit_received)
	health.died.connect(_on_died)
	var synced_weapon := net_weapon_path
	var synced_character := net_character_path
	if starting_weapon != null:
		unlock_weapon(starting_weapon)
	if not is_local():
		# Another peer's player: they drive it, this machine only displays it.
		input.use_device = false
		_equip_from_path(synced_weapon)
		_character_from_path(synced_character)
		if state == State.DEAD:
			_on_remote_state_changed(State.MOVE, State.DEAD)


## True if this machine controls this player.
func is_local() -> bool:
	return is_multiplayer_authority()


## Adds a weapon to the ones this player owns. If a loadout slot is free it goes there
## and is equipped; otherwise it waits in the armory.
func unlock_weapon(data: WeaponData) -> void:
	if data == null:
		return
	var is_new := not owns_weapon(data)
	if is_new:
		weapons.append(data)
	if not _loadout_has(data) and loadout.size() < LOADOUT_SLOTS:
		loadout.append(data)
		loadout_changed.emit()
	if _loadout_has(data):
		equip(data)
	if is_new:
		weapon_unlocked.emit(data)


## Replaces owned weapons and loadout at once (loading a saved profile).
func set_weapons(owned: Array[WeaponData], chosen: Array[WeaponData]) -> void:
	weapons.clear()
	for data in owned:
		if data != null and not owns_weapon(data):
			weapons.append(data)
	if weapons.is_empty() and starting_weapon != null:
		weapons.append(starting_weapon)
	set_loadout(chosen)


## Chooses which owned weapons to carry, in slot order. Unowned weapons and duplicates are
## dropped, extra entries beyond LOADOUT_SLOTS are ignored, and an empty loadout falls back
## to the first owned weapon. Keeps the weapon in hand if it is still carried.
func set_loadout(chosen: Array[WeaponData]) -> void:
	var cleaned: Array[WeaponData] = []
	for data in chosen:
		if data != null and owns_weapon(data) and cleaned.size() < LOADOUT_SLOTS:
			var already := false
			for picked in cleaned:
				already = already or picked.id == data.id
			if not already:
				cleaned.append(data)
	if cleaned.is_empty() and not weapons.is_empty():
		cleaned.append(weapons[0])
	loadout = cleaned
	loadout_changed.emit()
	if weapon == null or not _loadout_has(weapon.data):
		equip(loadout[0] if not loadout.is_empty() else null)


## Sets how the player looks. Other peers see it through net_character_path.
func set_character(data: CharacterData) -> void:
	if data == null:
		return
	character = data
	var body := visual.get_node_or_null(^"Body") as Polygon2D
	if body != null:
		body.color = data.color
	if is_local():
		net_character_path = data.resource_path
	character_changed.emit(data)


func _character_from_path(path: String) -> void:
	if path != "" and (character == null or character.resource_path != path):
		set_character(load(path) as CharacterData)


func _loadout_has(data: WeaponData) -> bool:
	for carried in loadout:
		if carried.id == data.id:
			return true
	return false


func owns_weapon(data: WeaponData) -> bool:
	if data == null:
		return false
	for owned in weapons:
		if owned.id == data.id:
			return true
	return false


## Equips the next weapon in the loadout, wrapping round to the first.
func swap_weapon() -> void:
	if loadout.size() < 2 or weapon == null:
		return
	var current := 0
	for i in loadout.size():
		if loadout[i].id == weapon.data.id:
			current = i
	equip(loadout[(current + 1) % loadout.size()])


## Puts the weapon described by [param data] in the player's hands.
func equip(data: WeaponData) -> void:
	if weapon != null:
		weapon.queue_free()
		weapon = null
	if data == null or data.behavior_scene == null:
		return
	weapon = data.behavior_scene.instantiate() as WeaponBehavior
	weapon_pivot.add_child(weapon)
	weapon.setup(data, self, Layers.ENEMY_HURTBOX)
	# Only the owner's copy of a weapon decides hits; other peers just show the swing.
	weapon.deals_damage = is_local()
	weapon.hit_landed.connect(_on_weapon_hit_landed)
	if is_local():
		net_weapon_path = data.resource_path
	weapon_changed.emit(data)


func _equip_from_path(path: String) -> void:
	if path == "" or (weapon != null and weapon.data.resource_path == path):
		return
	equip(load(path) as WeaponData)


func is_alive() -> bool:
	return state != State.DEAD


## 0 just after dashing, rising to 1 when the dash is ready again. Used by the HUD.
func get_dash_ready_ratio() -> float:
	if state == State.DASH:
		return 0.0
	if dash_cooldown <= 0.0:
		return 1.0
	return 1.0 - _dash_cooldown_left / dash_cooldown


## Asks the owner to respawn this player. Sent by the host (wave director).
@rpc("any_peer", "call_local", "reliable")
func net_respawn(at: Vector2) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_local() and (sender == 0 or sender == 1):
		respawn(at)


## Brings the player back to life at [param at] with full health.
func respawn(at: Vector2) -> void:
	global_position = at
	net_position = at
	velocity = Vector2.ZERO
	health.reset()
	state = State.MOVE
	_dash_cooldown_left = 0.0
	_hit_stop = 0.0
	visual.visible = true
	weapon_pivot.visible = true
	_grant_iframes(RESPAWN_PROTECTION, true)
	respawned.emit()


func _physics_process(delta: float) -> void:
	if not is_local():
		_puppet_process(delta)
		return
	# Input is read even while frozen so presses made during hit-stop are not lost.
	input.update(delta)
	net_aim = input.aim_direction
	net_position = global_position
	if state == State.DEAD:
		return
	if _hit_stop > 0.0:
		_hit_stop -= delta
		return
	_tick_timers(delta)
	_update_aim()
	match state:
		State.MOVE:
			_move_state(delta)
		State.DASH:
			_dash_state(delta)
	if weapon != null:
		weapon.tick(delta)
	move_and_slide()


func _tick_timers(delta: float) -> void:
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	if _iframes > 0.0:
		_iframes -= delta
		if _iframes <= 0.0:
			hurtbox.invulnerable = false
			_blinking = false
			visual.modulate.a = 1.0
		elif _blinking:
			var dim := fmod(_iframes, BLINK_PERIOD) < BLINK_PERIOD * 0.5
			visual.modulate.a = 0.35 if dim else 1.0


func _update_aim() -> void:
	if weapon != null and weapon.is_aim_locked():
		return
	weapon_pivot.rotation = input.aim_direction.angle()
	visual.scale.x = -1.0 if input.aim_direction.x < 0.0 else 1.0


func _move_state(delta: float) -> void:
	if _dash_cooldown_left <= 0.0 and input.take_dash():
		_start_dash()
		return
	if input.take_interact():
		interact_requested.emit(self)
	# Swapping waits for the current swing to finish rather than cutting it off.
	if weapon != null and not weapon.is_busy() and input.take_swap():
		swap_weapon()
	var speed := max_speed
	if weapon != null:
		speed *= weapon.get_move_speed_multiplier()
	# Accelerate toward the wanted velocity, or brake if no direction is held.
	var rate := acceleration if input.move != Vector2.ZERO else friction
	velocity = velocity.move_toward(input.move * speed, rate * delta)
	if weapon != null and input.wants_attack():
		if weapon.try_attack(input.aim_direction):
			input.clear_attack()
			_net_attack.rpc(input.aim_direction)


func _start_dash() -> void:
	state = State.DASH
	# Dash where the player is steering; if standing still, dash where they aim.
	_dash_direction = input.move.normalized() if input.move.length() > 0.1 else input.aim_direction
	_dash_time_left = dash_duration
	_ghost_timer = 0.0
	velocity = _dash_direction * dash_speed
	if weapon != null:
		weapon.cancel()
	_grant_iframes(dash_duration + dash_iframes_extra, false)
	dashed.emit()


func _dash_state(delta: float) -> void:
	velocity = _dash_direction * dash_speed
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = GHOST_INTERVAL
		_spawn_ghost()
	_dash_time_left -= delta
	if _dash_time_left <= 0.0:
		state = State.MOVE
		_dash_cooldown_left = dash_cooldown
		# Leave the dash at running speed so it flows straight back into movement.
		velocity = _dash_direction * max_speed


func _grant_iframes(seconds: float, blink: bool) -> void:
	_iframes = maxf(_iframes, seconds)
	_blinking = _blinking or blink
	hurtbox.invulnerable = true


## Leaves a fading copy of the player's art behind, to show the dash path.
func _spawn_ghost() -> void:
	var ghost := visual.duplicate(0) as Node2D
	get_parent().add_child(ghost)
	ghost.global_transform = visual.global_transform
	ghost.z_index = -1
	ghost.modulate = GHOST_COLOR
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, GHOST_FADE_TIME)
	tween.tween_callback(ghost.queue_free)


## Plays this player's swing on the other peers' copies.
@rpc("authority", "call_remote", "reliable")
func _net_attack(aim: Vector2) -> void:
	if weapon == null:
		return
	weapon_pivot.rotation = aim.angle()
	weapon.try_attack(aim)


## Displays another peer's player: glide to where its owner says it is.
func _puppet_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if global_position.distance_to(net_position) > PUPPET_SNAP_DISTANCE:
		global_position = net_position
	else:
		global_position = global_position.lerp(net_position, 1.0 - exp(-PUPPET_SMOOTHING * delta))
	if weapon == null or not weapon.is_aim_locked():
		weapon_pivot.rotation = net_aim.angle()
		visual.scale.x = -1.0 if net_aim.x < 0.0 else 1.0
	if state == State.DASH:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			_spawn_ghost()
	if weapon != null:
		weapon.tick(delta)


func _on_remote_state_changed(was: State, now: State) -> void:
	if now == State.DEAD:
		if weapon != null:
			weapon.cancel()
		visual.visible = false
		weapon_pivot.visible = false
		died.emit()
	elif was == State.DEAD:
		global_position = net_position
		visual.visible = true
		weapon_pivot.visible = true
		respawned.emit()


func _shake_camera(amount: float) -> void:
	get_tree().call_group(&"game_camera", &"add_trauma", amount)


func _on_weapon_hit_landed(target: Hurtbox, hit: HitInfo) -> void:
	_hit_stop = maxf(_hit_stop, hit.hit_stop)
	var shake := weapon.data.screen_shake
	if target.health != null and target.health.is_dead():
		shake += KILL_SHAKE_BONUS
	_shake_camera(shake)


func _on_hit_received(hit: HitInfo) -> void:
	if state == State.DEAD:
		return
	velocity = hit.direction * hit.knockback
	_hit_stop = maxf(_hit_stop, hit.hit_stop)
	_grant_iframes(hurt_iframes, true)
	visual.flash()
	_shake_camera(hurt_shake)


func _on_died() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	if weapon != null:
		weapon.cancel()
	hurtbox.invulnerable = true
	_iframes = 0.0
	_blinking = false
	visual.modulate.a = 1.0
	visual.visible = false
	weapon_pivot.visible = false
	_shake_camera(1.0)
	died.emit()
