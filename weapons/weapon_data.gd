class_name WeaponData
extends Resource
## The stats every weapon shares, stored as a data file (.tres).
##
## A weapon is two things:
##   1. a data file like this one, holding the numbers, and
##   2. a behaviour scene (swing, projectile, beam...) that knows how to attack.
## Many weapons can share one behaviour. Stats that only make sense for one kind of
## attack live in a subclass, e.g. MeleeSwingData adds reach and arc.

## Unique name used by code and, later, by recipes and save files.
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
@export_multiline var description := ""
## The scene that performs the attack. Its root script must extend WeaponBehavior.
@export var behavior_scene: PackedScene

@export_group("Damage")
## Hit points removed per hit.
@export var damage := 10.0
## How hard targets are pushed away, in pixels per second.
@export var knockback := 140.0
## Seconds attacker and target freeze on impact. Small values (0.03 to 0.08) add weight.
@export var hit_stop := 0.05
## Screen shake per hit (0 to 1).
@export var screen_shake := 0.4

@export_group("Timing (seconds)")
## Delay between pressing attack and the attack becoming dangerous. 0 for instant.
@export var windup := 0.0
## How long the attack can hit things. Keep at 0.05 or above so it never skips a frame.
@export var active_time := 0.09
## Pause after the attack before the next can start. Dashing cancels it.
@export var recovery := 0.19

@export_group("Wielder movement")
## Move speed multiplier while attacking. 1 = full speed, 0 = rooted in place.
@export_range(0.0, 1.0) var move_speed_multiplier := 0.55
## Forward shove toward the aim direction when the attack starts, in pixels per second.
@export var lunge_speed := 90.0
