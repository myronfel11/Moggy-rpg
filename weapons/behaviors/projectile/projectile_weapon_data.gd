class_name ProjectileWeaponData
extends WeaponData
## Stats for weapons that shoot projectiles. Used with projectile_weapon.tscn.
##
## Damage, knockback, hit-stop and screen shake come from WeaponData and apply per bullet.

@export_group("Shooting")
## Seconds between shots while the trigger is held. 0.07 is about 14 shots a second.
@export var fire_interval := 0.07
## Bullet speed in pixels per second.
@export var projectile_speed := 520.0
## How far a bullet flies before it fizzles, in pixels.
@export var projectile_range := 190.0
## Random spread of each shot in degrees (total cone width).
@export var spread_degrees := 6.0
## Two guns: shots alternate between muzzles this far either side of the aim line.
@export var muzzle_gap := 3.0
## How far in front of the wielder the muzzles are, in pixels.
@export var muzzle_distance := 9.0
## Bullet hit circle radius in pixels.
@export var projectile_radius := 2.5
@export var projectile_color := Color(1.0, 0.55, 0.85)
