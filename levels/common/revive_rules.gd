class_name ReviveRules
extends Node
## A shared pool of revives for a team (used by the boss fight). Host only.
##
## When a player goes down and revives are left, one is used straight away and the player
## comes back after revive_delay seconds. With none left the player stays down; if every
## player is down and no revive is on its way, all_players_down fires (the attempt fails).

signal all_players_down
signal revives_changed(left: int)

var revives_left := 3
var revive_delay := 5.0
## While false (fight not started, or already over) deaths are ignored.
var active := false

var _level: Level
var _pending := 0


func setup(level: Level, pool: int, delay: float) -> void:
	_level = level
	revives_left = pool
	revive_delay = delay
	level.player_spawned.connect(func(player: Player) -> void:
		player.died.connect(_on_player_died.bind(player))
	)
	level.player_left.connect(func(_peer: int) -> void: _check_everyone_down.call_deferred())


func _on_player_died(player: Player) -> void:
	if not active or not multiplayer.is_server():
		return
	if revives_left > 0:
		revives_left -= 1
		_pending += 1
		revives_changed.emit(revives_left)
		await get_tree().create_timer(revive_delay, false).timeout
		_pending -= 1
		if active and is_instance_valid(player) and not player.is_alive():
			player.net_respawn.rpc(_level.get_player_start())
		return
	_check_everyone_down()


func _check_everyone_down() -> void:
	if not active or _pending > 0 or _level == null:
		return
	for player in _level.get_players():
		if player.is_alive():
			return
	active = false
	all_players_down.emit()
