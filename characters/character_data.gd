class_name CharacterData
extends Resource
## A playable character, chosen in the armory. Stored as a .tres file.
##
## For now characters differ only in looks, so friends can tell each other apart.
## When real art exists this gains a sprite or scene field; stats per character can be
## added here later without changing how characters are chosen or saved.

@export var id: StringName
@export var display_name := ""
## Colour of the placeholder body.
@export var color := Color(0.25, 0.85, 1.0)
