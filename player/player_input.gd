class_name PlayerInput
extends Node2D
## Collects what the player wants to do, separate from what the character then does.
##
## The Player script reads only from here and never touches the keyboard or mouse
## itself. That separation is what lets the same Player be driven by:
##   - the local keyboard and mouse (use_device = true),
##   - automated tests (use_device = false, tests set the values),
##   - later, a gamepad or another player over the network.
##
## It also "buffers" button presses: a press is remembered for a short moment, so
## pressing dash or attack slightly too early still works. This is a big part of why
## controls feel responsive instead of dropping inputs.

## How long a press is remembered, in seconds.
const BUFFER_TIME := 0.12
## Mouse closer to the player than this (in pixels) does not change the aim.
const AIM_DEADZONE := 2.0

## When false, nothing is read from devices and other code sets the values below.
@export var use_device := true

## Desired movement direction. Length is 0 (no input) to 1.
var move := Vector2.ZERO
## Unit vector from the player toward the aim point.
var aim_direction := Vector2.RIGHT
## True while the attack button is held down.
var attack_held := false

var _dash_buffer := 0.0
var _attack_buffer := 0.0
var _interact_buffer := 0.0
var _swap_buffer := 0.0


## Called by the Player at the start of every physics tick.
func update(delta: float) -> void:
	_dash_buffer = maxf(0.0, _dash_buffer - delta)
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	_interact_buffer = maxf(0.0, _interact_buffer - delta)
	_swap_buffer = maxf(0.0, _swap_buffer - delta)
	if not use_device:
		return
	if Input.is_action_just_pressed(&"interact"):
		press_interact()
	if Input.is_action_just_pressed(&"swap_weapon"):
		press_swap()
	move = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > AIM_DEADZONE:
		aim_direction = to_mouse.normalized()
	attack_held = Input.is_action_pressed(&"attack")
	if Input.is_action_just_pressed(&"dash"):
		press_dash()
	if Input.is_action_just_pressed(&"attack"):
		press_attack()


func press_dash() -> void:
	_dash_buffer = BUFFER_TIME


func press_attack() -> void:
	_attack_buffer = BUFFER_TIME


## Returns true once per buffered dash press, then forgets it.
func take_dash() -> bool:
	if _dash_buffer <= 0.0:
		return false
	_dash_buffer = 0.0
	return true


func press_interact() -> void:
	_interact_buffer = BUFFER_TIME


func press_swap() -> void:
	_swap_buffer = BUFFER_TIME


## Returns true once per buffered interact press, then forgets it.
func take_interact() -> bool:
	if _interact_buffer <= 0.0:
		return false
	_interact_buffer = 0.0
	return true


## Returns true once per buffered weapon-swap press, then forgets it.
func take_swap() -> bool:
	if _swap_buffer <= 0.0:
		return false
	_swap_buffer = 0.0
	return true


## True if attack is held, or was pressed a moment ago.
func wants_attack() -> bool:
	return attack_held or _attack_buffer > 0.0


func clear_attack() -> void:
	_attack_buffer = 0.0
