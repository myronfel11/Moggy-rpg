class_name ItemData
extends Resource
## A material that enemies drop, players carry, and recipes consume. Stored as a .tres file.
##
## Adding a new material to the game means adding one of these files. Enemies point at
## it from their drop list and recipes point at it from their costs.

enum Rarity { COMMON, UNCOMMON, RARE, VERY_RARE }

## Unique name used by code and, later, by save files.
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
@export_multiline var description := ""
## Affects how the pickup looks on the ground. Uncommon and above pulse to catch the eye.
@export var rarity := Rarity.COMMON
## Colour of the placeholder pickup and HUD icon.
@export var color := Color.WHITE
