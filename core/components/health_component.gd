class_name HealthComponent
extends Node
## Tracks hit points for whatever node it is attached to.
##
## It knows nothing about players or enemies. It only counts damage and announces changes
## through signals, so the same component works on both.

signal changed(current: float, maximum: float)
signal died

@export var max_health := 100.0

var current := 0.0


func _ready() -> void:
	current = max_health


## Sets a new maximum and refills to it.
func setup(maximum: float) -> void:
	max_health = maximum
	reset()


## Refills to full.
func reset() -> void:
	current = max_health
	changed.emit(current, max_health)


## Applies damage and returns how much was actually dealt.
func take_damage(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, current)
	current -= dealt
	changed.emit(current, max_health)
	if current <= 0.0:
		died.emit()
	return dealt


func is_dead() -> bool:
	return current <= 0.0
