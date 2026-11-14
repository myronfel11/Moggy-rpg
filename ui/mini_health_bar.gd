class_name MiniHealthBar
extends Node2D
## A tiny health bar floating above a character.
##
## Hidden at full health and after death, so it only shows on things already in a fight.
## It makes the difference between weapons visible: a hit that takes a sliver off the
## bar reads very differently from one that takes a third.

@export var health: HealthComponent
## Bar width in pixels.
@export var width := 14.0
@export var fill_color := Color(1.0, 0.3, 0.35)


func _ready() -> void:
	if health != null:
		health.changed.connect(_on_health_changed)


func _on_health_changed(_current: float, _maximum: float) -> void:
	queue_redraw()


func _draw() -> void:
	if health == null or health.is_dead() or health.current >= health.max_health:
		return
	var ratio := health.current / health.max_health
	draw_rect(Rect2(-width * 0.5 - 1.0, -1.0, width + 2.0, 4.0), Color(0.0, 0.0, 0.0, 0.75))
	draw_rect(Rect2(-width * 0.5, 0.0, width * ratio, 2.0), fill_color)
