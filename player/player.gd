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

enum State { MOVE, DASH, DEAD }

const GHOST_INTERVAL := 0.035
const GHOST_FADE_TIME := 0.18
const GHOST_COLOR := Color(0.35, 0.9, 1.0, 0.55)
const BLINK_PERIOD := 0.1
const RESPAWN_PROTECTION := 1.0
const KILL_SHAKE_BONUS := 0.2

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

var state := State.MOVE
## The equipped weapon's behaviour node. Its stats are in weapon.data.
var weapon: WeaponBehavior
## Every weapon this player owns, in the order they were obtained.
var weapons: Array[WeaponData] = []

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
	if starting_weapon != null:
		unlock_weapon(starting_weapon)


## Adds a weapon to the ones this player owns (if new) and equips it.
func unlock_weapon(data: WeaponData) -> void:
	if data == null:
		return
	if not owns_weapon(data):
		weapons.append(data)
	equip(data)


func owns_weapon(data: WeaponData) -> bool:
	if data == null:
		return false
	for owned in weapons:
		if owned.id == data.id:
			return true
	return false


## Equips the next owned weapon, wrapping round to the first.
func swap_weapon() -> void:
	if weapons.size() < 2 or weapon == null:
		return
	var current := weapons.find(weapon.data)
	equip(weapons[(current + 1) % weapons.size()])


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
	weapon.hit_landed.connect(_on_weapon_hit_landed)
	weapon_changed.emit(data)


func is_alive() -> bool:
	return state != State.DEAD


## 0 just after dashing, rising to 1 when the dash is ready again. Used by the HUD.
func get_dash_ready_ratio() -> float:
	if state == State.DASH:
		return 0.0
	if dash_cooldown <= 0.0:
		return 1.0
	return 1.0 - _dash_cooldown_left / dash_cooldown


## Brings the player back to life at [param at] with full health.
func respawn(at: Vector2) -> void:
	global_position = at
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
	# Input is read even while frozen so presses made during hit-stop are not lost.
	input.update(delta)
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
