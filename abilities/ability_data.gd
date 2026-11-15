class_name AbilityData
extends Resource
## A character ability (keys 1 to 3), stored as a .tres file. Same idea as weapons: this
## file holds the numbers, behavior_scene holds the code. Many characters can share one
## behaviour with different numbers.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## The scene that performs the ability. Its root script must extend AbilityBehavior.
@export var behavior_scene: PackedScene
## Seconds before the ability can be used again, counted from when it is used.
@export var cooldown := 10.0
## How long the effect lasts, in seconds (0 for instant abilities).
@export var duration := 0.0
## Colour for the HUD box and effects.
@export var color := Color(1.0, 0.5, 0.85)
## If true, attacking ends the effect early (used by invisibility).
@export var breaks_on_attack := false
