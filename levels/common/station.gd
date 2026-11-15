class_name Station
extends Node2D
## Something in the world a player walks up to and uses with E (Fabricator, navigation
## console, armory).
##
## It never reads the keyboard. Each Player announces "I pressed interact" with a signal,
## and the station listens only to this machine's own player while it is in range, so
## using a station never changes another player's game. The HUD shows get_prompt() for
## whichever station the local player stands at.
##
## Required child: Range (Area2D watching the player body layer).

signal player_entered(player: Player)
signal player_exited(player: Player)

var _players_in_range: Array[Player] = []

@onready var _range: Area2D = $Range


func _ready() -> void:
	add_to_group(&"stations")
	_range.body_entered.connect(_on_body_entered)
	_range.body_exited.connect(_on_body_exited)


func is_in_range(player: Player) -> bool:
	return _players_in_range.has(player)


## Override: the line the HUD shows while the player stands here.
func get_prompt(_player: Player) -> String:
	return ""


## Override: what happens when the player presses E here.
func _interact(_player: Player) -> void:
	pass


## The level this station is in.
func get_level() -> Level:
	return get_tree().get_first_node_in_group(&"level") as Level


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	# Only this machine's own player: using a station changes that player's progress.
	if player == null or not player.is_local() or _players_in_range.has(player):
		return
	_players_in_range.append(player)
	player.interact_requested.connect(_interact)
	player_entered.emit(player)


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null or not _players_in_range.has(player):
		return
	_players_in_range.erase(player)
	player.interact_requested.disconnect(_interact)
	player_exited.emit(player)
