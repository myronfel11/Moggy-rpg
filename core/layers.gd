class_name Layers
## Physics layer values, matching the names in Project Settings > Layer Names > 2D Physics.
##
## Godot stores layers as bits in a number, so layer 1 is 1, layer 2 is 2, layer 3 is 4,
## layer 4 is 8 and so on. Using these names in code avoids magic numbers.

const WORLD := 1
const PLAYER_BODY := 2
const ENEMY_BODY := 4
const PLAYER_HURTBOX := 8
const ENEMY_HURTBOX := 16
