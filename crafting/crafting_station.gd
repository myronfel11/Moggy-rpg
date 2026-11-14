class_name CraftingStation
extends Node2D
## A place where a player standing nearby can turn materials into gear.
##
## The station offers its recipes in order: the "next" recipe for a player is the first
## one whose result they do not own yet. That gives every player one clear goal at a time.
##
## It never reads the keyboard. Each Player announces "I pressed interact" with a signal,
## and the station listens to the players currently inside its range. That keeps it
## working for scripted tests now and for several players later.

signal player_entered(player: Player)
signal player_exited(player: Player)
signal crafted(player: Player, recipe: Recipe)

## Recipes in the order they should be crafted.
@export var recipes: Array[Recipe] = []

var _players_in_range: Array[Player] = []

@onready var _range: Area2D = $Range


func _ready() -> void:
	_range.body_entered.connect(_on_body_entered)
	_range.body_exited.connect(_on_body_exited)


func is_in_range(player: Player) -> bool:
	return _players_in_range.has(player)


## The first recipe this player has not crafted yet, or null when none are left.
func get_next_recipe(player: Player) -> Recipe:
	for recipe in recipes:
		if recipe != null and not player.owns_weapon(recipe.result):
			return recipe
	return null


## Crafts the player's next recipe if they can afford it. The new weapon is equipped
## straight away. Returns true if something was crafted.
func try_craft(player: Player) -> bool:
	var recipe := get_next_recipe(player)
	if recipe == null or not player.inventory.spend(recipe.costs):
		return false
	player.unlock_weapon(recipe.result)
	crafted.emit(player, recipe)
	return true


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	# Crafting changes the inventory, which only the player's own peer may do.
	if player == null or not player.is_local() or _players_in_range.has(player):
		return
	_players_in_range.append(player)
	player.interact_requested.connect(_on_interact_requested)
	player_entered.emit(player)


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null or not _players_in_range.has(player):
		return
	_players_in_range.erase(player)
	player.interact_requested.disconnect(_on_interact_requested)
	player_exited.emit(player)


func _on_interact_requested(player: Player) -> void:
	try_craft(player)
