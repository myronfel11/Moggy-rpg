class_name Inventory
extends Node
## The materials one player is carrying, as a count per item.
##
## It is a child of a Player, never something global, so that in co-op every player has
## their own. It knows nothing about recipes or weapons. It only counts, and announces
## changes so the HUD can update.

## Emitted whenever a count changes. [param change] is positive for gains and negative
## for spending.
signal changed(item: ItemData, count: int, change: int)

var _counts: Dictionary[StringName, int] = {}
## Items in the order they were first picked up, so the HUD list does not jump around.
var _items: Array[ItemData] = []


func add(item: ItemData, amount := 1) -> void:
	if item == null or amount <= 0:
		return
	if not _counts.has(item.id):
		_items.append(item)
	_counts[item.id] = get_count(item) + amount
	changed.emit(item, _counts[item.id], amount)


func get_count(item: ItemData) -> int:
	return _counts.get(item.id, 0)


## Every item ever picked up, including ones now at zero.
func get_items() -> Array[ItemData]:
	return _items


## Item file path -> count, for saving. Items at zero are left out.
func get_counts() -> Dictionary:
	var counts := {}
	for item in _items:
		if get_count(item) > 0:
			counts[item.resource_path] = get_count(item)
	return counts


## Replaces everything with the given item file path -> count (from a save).
func set_counts(counts: Dictionary) -> void:
	_counts.clear()
	_items.clear()
	for path: String in counts:
		var item := load(path) as ItemData
		if item != null:
			add(item, int(counts[path]))


## True if the player holds enough of everything in [param costs].
## A cost list should name each item only once.
func can_afford(costs: Array[ItemAmount]) -> bool:
	for cost in costs:
		if get_count(cost.item) < cost.amount:
			return false
	return true


## Removes everything in [param costs], or nothing at all if the player cannot afford it.
## Returns true if the items were spent.
func spend(costs: Array[ItemAmount]) -> bool:
	if not can_afford(costs):
		return false
	for cost in costs:
		_counts[cost.item.id] = get_count(cost.item) - cost.amount
		changed.emit(cost.item, _counts[cost.item.id], -cost.amount)
	return true
