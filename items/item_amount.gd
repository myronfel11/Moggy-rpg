class_name ItemAmount
extends Resource
## "This many of this item". Used as one line of a recipe's cost.

@export var item: ItemData
@export_range(1, 999) var amount := 1
