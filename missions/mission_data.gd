class_name MissionData
extends Resource
## A mission picked at the hub's navigation console. Stored as a .tres file.
##
## A new mission in an existing level is a new data file: which room, which enemies, how
## many waves. A new kind of objective (survive, escort, boss) will add fields here.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## The level scene the mission takes place in. Its root script must extend Level.
@export_file("*.tscn") var level_scene := "res://levels/test_arena/test_arena.tscn"
## Shown in the mission menu instead of "N waves" when set (for example "Boss").
@export var length_text := ""

@export_group("Waves")
## The regular enemy.
@export var enemy_type: EnemyData
## A tougher enemy mixed into later waves. Leave empty for none.
@export var elite_type: EnemyData
## The first wave that includes an elite.
@export var elite_from_wave := 3
@export var first_wave_size := 3
## Extra enemies added each wave.
@export var wave_growth := 1
@export var max_wave_size := 8
## Clearing this wave completes the mission. 0 means it never ends.
@export var waves_to_clear := 3

@export_group("Completion reward")
## The featured item this mission can award when it is cleared. Empty for none.
@export var reward_item: ItemData
## Chance (0 to 1) that clearing the mission awards reward_item. The host rolls once for
## the whole group, so everyone gets it or nobody does.
@export_range(0.0, 1.0) var reward_chance := 0.0


## "Venza Crown - 15%", or "" when the mission has no featured reward.
func describe_reward() -> String:
	if reward_item == null:
		return ""
	return "%s - %d%%" % [reward_item.display_name, roundi(reward_chance * 100.0)]
