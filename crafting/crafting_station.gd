class_name CraftingStation
extends Station
## The Fabricator: turns materials into gear and characters for the player standing at it.
##
## Pressing E opens the crafting menu. Crafting is checked and done on this machine for
## this machine's player only, so nobody can spend another player's materials.

signal crafted(player: Player, recipe: Recipe)

## Loaded when needed rather than preloaded: the panel script refers back to this class,
## and preloading each other makes a cycle that keeps both alive at exit.
const PANEL_PATH := "res://ui/crafting_panel.gd"

@export var recipe_book: RecipeBook = preload("res://crafting/data/recipe_book.tres")


## The first recipe this player has not crafted yet, or null when none are left.
func get_next_recipe(player: Player) -> Recipe:
	return recipe_book.get_next(player) if recipe_book != null else null


## True if the player can craft [param recipe] right now: not owned yet and every
## material is there.
func can_craft(player: Player, recipe: Recipe) -> bool:
	return recipe != null and not recipe.is_owned_by(player) and player.inventory.can_afford(recipe.costs)


## Crafts [param recipe] (or the player's next recipe if null). Checks ownership and
## materials again, then spends and grants together, so a double press or a stale menu can
## never take materials twice. Returns true if something was crafted.
func try_craft(player: Player, recipe: Recipe = null) -> bool:
	if recipe == null:
		recipe = get_next_recipe(player)
	if not can_craft(player, recipe) or not player.inventory.spend(recipe.costs):
		return false
	recipe.grant_to(player)
	crafted.emit(player, recipe)
	return true


func get_prompt(player: Player) -> String:
	var recipe := get_next_recipe(player)
	if recipe != null and player.inventory.can_afford(recipe.costs):
		return "[E] Fabricator: %s ready to craft" % recipe.get_result_name()
	return "[E] Fabricator"


func _interact(player: Player) -> void:
	open_panel(player)


## Opens the crafting menu for this machine's player. Returns the panel (used by tests).
func open_panel(player: Player) -> CraftingPanel:
	var level := get_level()
	if player.input.blocked:
		return null
	var panel := (load(PANEL_PATH) as GDScript).new() as CraftingPanel
	panel.station = self
	(level if level != null else get_parent()).add_child(panel)
	panel.open(player)
	return panel
