class_name Station
extends Node2D
## Something in the world a player walks up to and uses with E (Fabricator, navigation
## console, armory, boss bombs).
##
## It never reads the keyboard. Each Player announces "I pressed interact" with a signal,
## and the station listens only to this machine's own player while it is in range, so
## using a station never changes another player's game. The HUD shows get_prompt() for
## whichever station the local player stands at.
##
## Hold stations (hold_time above 0) need E held instead of pressed. Progress counts on the
## player's own machine and resets the moment E is released, the player leaves the range,
## dies, or can_interact() says no; only a completed hold calls _complete().
##
## Required child: Range (Area2D watching the player body layer).

signal player_entered(player: Player)
signal player_exited(player: Player)

## Seconds E must be held. 0 means a normal press.
var hold_time := 0.0

var _players_in_range: Array[Player] = []
var _hold := 0.0

@onready var _range: Area2D = $Range


func _ready() -> void:
	add_to_group(&"stations")
	_range.body_entered.connect(_on_body_entered)
	_range.body_exited.connect(_on_body_exited)


func is_in_range(player: Player) -> bool:
	return _players_in_range.has(player)


## Override: the line the HUD shows while the player stands here ("" for none).
func get_prompt(_player: Player) -> String:
	return ""


## Override: whether this player may use the station right now.
func can_interact(_player: Player) -> bool:
	return true


## 0 to 1: how far through the hold this machine's player is (0 for press stations).
func get_hold_progress(_player: Player) -> float:
	return clampf(_hold / hold_time, 0.0, 1.0) if hold_time > 0.0 else 0.0


## Override: what happens when the player presses E here (press stations).
func _interact(_player: Player) -> void:
	pass


## Override: what happens when the player finishes holding E here (hold stations).
func _complete(_player: Player) -> void:
	pass


## The level this station is in.
func get_level() -> Level:
	return get_tree().get_first_node_in_group(&"level") as Level


func _physics_process(delta: float) -> void:
	if hold_time <= 0.0:
		return
	var holder: Player = null
	for player in _players_in_range:
		if is_instance_valid(player) and player.is_alive() and player.input.interact_held and can_interact(player):
			holder = player
	if holder == null:
		_hold = 0.0
		return
	_hold += delta
	if _hold >= hold_time:
		_hold = 0.0
		_complete(holder)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	# Only this machine's own player: using a station changes that player's progress.
	if player == null or not player.is_local() or _players_in_range.has(player):
		return
	_players_in_range.append(player)
	player.interact_requested.connect(_on_interact_pressed)
	player_entered.emit(player)


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null or not _players_in_range.has(player):
		return
	_players_in_range.erase(player)
	player.interact_requested.disconnect(_on_interact_pressed)
	_hold = 0.0
	player_exited.emit(player)


func _on_interact_pressed(player: Player) -> void:
	if hold_time <= 0.0:
		_interact(player)
