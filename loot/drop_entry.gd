class_name DropEntry
extends Resource
## One line of an enemy's loot list: which item, how likely, and how many.
##
## Every line is rolled on its own when the enemy dies, so an enemy can drop several
## different things at once.

@export var item: ItemData
## Probability that this line drops anything. 1 = always, 0.2 = one kill in five.
@export_range(0.0, 1.0) var chance := 1.0
@export_range(1, 99) var min_amount := 1
@export_range(1, 99) var max_amount := 1


## Rolls the dice once. Returns how many to drop, or 0 if the roll missed.
func roll() -> int:
	if item == null or randf() >= chance:
		return 0
	return randi_range(min_amount, maxi(min_amount, max_amount))
