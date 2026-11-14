class_name MeleeSwingData
extends WeaponData
## Stats for weapons that swing in an arc in front of the wielder.
## Used with the melee_swing.tscn behaviour.

@export_group("Swing shape")
## How far the swing reaches from the wielder's centre, in pixels.
@export var reach := 30.0
## Width of the swing in degrees. 90 is a narrow slash, 180 a half circle, 360 a full spin.
@export_range(10.0, 360.0) var arc_degrees := 110.0
## Colour of the placeholder slash effect.
@export var color := Color(0.45, 0.95, 1.0)
