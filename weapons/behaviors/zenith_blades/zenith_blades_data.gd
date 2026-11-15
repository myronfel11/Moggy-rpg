class_name ZenithBladesData
extends MeleeSwingData
## Stats for Venza's Zenith arm blades: a melee swing plus auto-lock lunges.

@export_group("Auto-lock")
## Enemies within this distance (pixels) can be locked onto.
@export var lock_radius := 110.0
## Enemies within this angle (degrees, either side) of where she aims are preferred.
@export var lock_angle := 60.0
## Lunge speed in pixels per second.
@export var lunge_dash_speed := 700.0
## A lunge never lasts longer than this, in seconds.
@export var lunge_max_time := 0.25
## The lunge stops this far from the target and slashes.
@export var stop_distance := 14.0
