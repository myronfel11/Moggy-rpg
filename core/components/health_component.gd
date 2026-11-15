class_name HealthComponent
extends Node
## Tracks hit points for whatever node it is attached to.
##
## It knows nothing about players or enemies. It only counts damage and announces changes
## through signals, so the same component works on both.
##
## In co-op, `current` is synced from the owning peer. Its setter announces every change,
## so health bars update the same way for local damage and for synced values.

signal changed(current: float, maximum: float)
signal died
## Health was brought down to [member minimum] (only when minimum is above 0).
signal reached_minimum

@export var max_health := 100.0
## Damage cannot take health below this. 0 normally; a boss health gate raises it.
var minimum := 0.0

var current := 0.0:
	set(value):
		if is_equal_approx(value, current):
			return
		current = value
		changed.emit(current, max_health)


func _ready() -> void:
	# A co-op client may already have received a synced value; keep it.
	if current <= 0.0:
		current = max_health


## Sets a new maximum and refills to it.
func setup(maximum: float) -> void:
	max_health = maximum
	reset()


## Refills to full.
func reset() -> void:
	if is_equal_approx(current, max_health):
		changed.emit(current, max_health)
	else:
		current = max_health


## Applies damage and returns how much was actually dealt. Health never drops below
## [member minimum] (a boss's 50% gate), however big the hit.
## Only the peer that owns this character calls this; others receive the synced value.
func take_damage(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, current - minimum)
	if dealt <= 0.0:
		return 0.0
	current -= dealt
	if current <= 0.0:
		died.emit()
	elif minimum > 0.0 and current <= minimum:
		reached_minimum.emit()
	return dealt


func is_dead() -> bool:
	return current <= 0.0
