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
## False for characters that must be crafted at the Fabricator before they can be chosen.
@export var unlocked_by_default := true
## Colour of the placeholder crown.
@export var crown_color := Color(1.0, 0.85, 0.35)

@export_group("Kit")
## Maximum health for this character.
@export var max_health := 100.0
## Weapon the player receives when this character is unlocked (owned for good, usable by
## any character). Empty for none.
@export var signature_weapon: WeaponData
## Movement passive added to the player while playing this character (for example
## skating). Its root script must extend CharacterPassive. Empty for none.
@export var passive_scene: PackedScene
## Abilities on keys 1, 2 and 3.
@export var abilities: Array[AbilityData] = []
## The Zenith ultimate on key 4. Empty for none (the Zenith bar is then hidden).
@export var zenith: ZenithData
