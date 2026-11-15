class_name EnemyData
extends Resource
## The stats every enemy shares, stored as a data file (.tres).
##
## Same idea as WeaponData: the data file holds the numbers and points at a scene that
## holds the behaviour. Many enemies can share one behaviour. Stats that only make sense
## for one behaviour live in a subclass, e.g. ChaserData adds the lunge attack.

## Unique name used by code and, later, by drop tables and missions.
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## The enemy scene to spawn. Its root script must extend Enemy.
@export var scene: PackedScene

@export_group("Stats")
@export var max_health := 30.0
## Walking speed in pixels per second. The player runs at 120.
@export var move_speed := 70.0
## Seconds the enemy is stunned when hit. 0 means hits never interrupt it.
@export var stagger_time := 0.2
## 0 takes full knockback, 1 cannot be pushed at all.
@export_range(0.0, 1.0) var knockback_resistance := 0.0
## Flat damage removed from every hit (a hit still always deals at least 1).
## Light, fast weapons bounce off high armour; heavy weapons punch through.
@export var armor := 0.0

@export_group("Loot")
## What this enemy can drop when it dies. Every line is rolled separately.
@export var drops: Array[DropEntry] = []

@export_group("Zenith")
## Zenith charge (out of 100) for defeating this enemy: full for the killer's Zenith weapon,
## half otherwise.
@export var zenith_value := 8.0

@export_group("Look (placeholder)")
## Colour of the placeholder body shape.
@export var color := Color(1.0, 0.25, 0.45)
