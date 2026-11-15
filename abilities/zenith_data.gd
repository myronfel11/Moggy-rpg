class_name ZenithData
extends AbilityData
## A character's Zenith ultimate (key 4). Charged by defeating enemies; usable at 100%.
##
## The charging rules are shared by every character (PlayerAbilities); this file only says
## which weapon gives full charge and which weapon must be carried to use it.

## Kills made with this weapon give full charge; other kills give half. Empty: every kill
## by this player counts as full.
@export var charge_weapon: WeaponData
## Zenith can only be used while this weapon is in one of the two loadout slots.
@export var required_weapon: WeaponData
## Seconds of the transformation before the empowered state begins.
@export var transform_time := 0.4
