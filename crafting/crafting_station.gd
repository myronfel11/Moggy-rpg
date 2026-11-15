class_name CraftingStation
extends Station
## The Fabricator: turns materials into gear for the player standing at it.
##
## It offers the recipe book in order: the "next" recipe for a player is the first one
## whose result they do not own yet. That gives every player one clear goal at a time.

signal crafted(player: Player, recipe: Recipe)

@export var recipe_book: RecipeBook = preload("res://crafting/data/recipe_book.tres")


## The first recipe this player has not crafted yet, or null when none are left.
func get_next_recipe(player: Player) -> Recipe:
	return recipe_book.get_next(player) if recipe_book != null else null


## Crafts the player's next recipe if they can afford it. The new weapon goes into a free
## loadout slot (and is equipped) if there is one. Returns true if something was crafted.
func try_craft(player: Player) -> bool:
	var recipe := get_next_recipe(player)
	if recipe == null or not player.inventory.spend(recipe.costs):
		return false
	player.unlock_weapon(recipe.result)
	crafted.emit(player, recipe)
	return true


func get_prompt(player: Player) -> String:
	var recipe := get_next_recipe(player)
	if recipe == null:
		return "Nothing left to craft"
	var missing := PackedStringArray()
	for cost in recipe.costs:
		var have := player.inventory.get_count(cost.item)
		if have < cost.amount:
			missing.append("%d %s" % [cost.amount - have, cost.item.display_name])
	if missing.is_empty():
		return "[E] Craft %s" % recipe.result.display_name
	return "%s needs %s more" % [recipe.result.display_name, " and ".join(missing)]


func _interact(player: Player) -> void:
	try_craft(player)
