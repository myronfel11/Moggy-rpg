class_name CraftingPanel
extends MenuPanel
## The Fabricator's menu: every recipe with what it needs, what you have, and a Craft button
## that only works when everything is there.
##
## Crafting happens on this machine only, for this machine's player, and changes only that
## player's inventory and unlocks (each player owns their own progress).

const OWNED_COLOR := Color(0.55, 1.0, 0.7)
const MISSING_COLOR := Color(1.0, 0.5, 0.5)

var station: CraftingStation

var _rows: VBoxContainer
var _buttons: Dictionary = {}


func _build(box: VBoxContainer) -> void:
	box.add_child(make_label("FABRICATOR - craft gear and characters"))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 2)
	box.add_child(_rows)
	_refresh()


## Crafts [param recipe] if allowed. Returns true if something was crafted.
func craft(recipe: Recipe) -> bool:
	var crafted := station.try_craft(player, recipe)
	_refresh()
	return crafted


## The Craft button for a recipe (used by tests).
func get_craft_button(recipe: Recipe) -> Button:
	return _buttons.get(recipe.resource_path) as Button


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for recipe in station.recipe_book.recipes:
		if recipe == null:
			continue
		var header := HBoxContainer.new()
		var title := make_label(recipe.get_result_name() + ("  (character)" if recipe.result_character != null else ""))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var button := make_button("Crafted" if recipe.is_owned_by(player) else "Craft")
		button.disabled = not station.can_craft(player, recipe)
		button.pressed.connect(craft.bind(recipe))
		header.add_child(button)
		_buttons[recipe.resource_path] = button
		_rows.add_child(header)
		var costs := HBoxContainer.new()
		costs.add_theme_constant_override(&"separation", 8)
		var owned := recipe.is_owned_by(player)
		for cost in recipe.costs:
			var have := player.inventory.get_count(cost.item)
			var enough := have >= cost.amount
			# Nothing is "missing" for something already crafted.
			var suffix := "" if enough or owned else " missing"
			var label := make_label("%s %d/%d%s" % [cost.item.display_name, mini(have, cost.amount), cost.amount, suffix])
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			label.modulate = OWNED_COLOR if enough else MISSING_COLOR
			if recipe.is_owned_by(player):
				label.modulate.a = 0.45
			costs.add_child(label)
		_rows.add_child(costs)
