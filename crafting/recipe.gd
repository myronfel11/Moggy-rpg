class_name Recipe
extends Resource
## What a crafting station can make, and what it costs. Stored as a .tres file.
##
## For now every recipe produces a weapon. Armour, tools and upgrades will add other
## kinds of result later.

## Unique name used by code and, later, by save files.
@export var id: StringName
## The weapon the player receives.
@export var result: WeaponData
## Materials consumed. Name each item only once.
@export var costs: Array[ItemAmount] = []
