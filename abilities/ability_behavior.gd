class_name AbilityBehavior
extends Node2D
## Base class for abilities. Handles cooldown and duration bookkeeping; subclasses
## override _on_activate, _on_tick, _on_end and show_remote.
##
## Abilities run on the owning player's machine. Other peers only show effects, through
## show_remote() (called from PlayerAbilities' network message) and the player's synced
## status flags.

var data: AbilityData
var player: Player

var _cooldown_left := 0.0
var _active_left := 0.0
var _active := false


func setup(p_data: AbilityData, p_player: Player) -> void:
	data = p_data
	player = p_player
	_on_setup()


## Override: one-time setup after data and player are set.
func _on_setup() -> void:
	pass


func is_active() -> bool:
	return _active


func get_cooldown_left() -> float:
	return _cooldown_left


## 0 just used, 1 ready.
func get_ready_ratio() -> float:
	if data.cooldown <= 0.0:
		return 1.0
	return 1.0 - _cooldown_left / data.cooldown


## Seconds of effect remaining (0 when not active).
func get_active_left() -> float:
	return _active_left if _active else 0.0


func can_activate() -> bool:
	return not _active and _cooldown_left <= 0.0 and player.is_alive()


## Starts the ability if allowed. Returns true if it started.
func activate() -> bool:
	if not can_activate():
		return false
	_cooldown_left = data.cooldown
	_active = true
	_active_left = data.duration
	_on_activate()
	if _active and data.duration <= 0.0 and not _is_self_timed():
		end()
	return true


## Called every physics frame on the owner.
func tick(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not _active:
		return
	_on_tick(delta)
	if _active and data.duration > 0.0 and not _is_self_timed():
		_active_left -= delta
		if _active_left <= 0.0:
			end()


## Ends the effect now (timer ran out, death, or interrupted).
func end() -> void:
	if not _active:
		return
	_active = false
	_active_left = 0.0
	_on_end()
	if player != null and player.abilities != null:
		player.abilities.announce_end(self)


## Ends the effect without waiting (death, level change). Cooldown is kept.
func cancel() -> void:
	end()


## The player attacked. Ends the effect if this ability breaks on attack.
func notify_attacked() -> void:
	if _active and data.breaks_on_attack:
		end()


## Override: true if the ability ends itself instead of on a timer (for example a dash
## that ends when it has travelled its distance).
func _is_self_timed() -> bool:
	return false


func _on_activate() -> void:
	pass


func _on_tick(_delta: float) -> void:
	pass


func _on_end() -> void:
	pass


## Override: show the effect on another peer's copy of the player.
func show_remote(_started: bool) -> void:
	pass
