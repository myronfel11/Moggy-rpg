class_name RecipeBook
extends Resource
## Every recipe in the order players should work through them. Stored as a .tres file.
##
## Shared by the HUD goal line (shown everywhere, also during missions) and every
## Fabricator, so the "next thing to craft" is the same wherever the player looks.

## Recipes in the order they should be crafted.
@export var recipes: Array[Recipe] = []


## The first recipe this player has not crafted yet, or null when none are left.
func get_next(player: Player) -> Recipe:
	for recipe in recipes:
		if recipe != null and not recipe.is_owned_by(player):
			return recipe
	return null
