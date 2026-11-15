class_name CharacterPassive
extends Node2D
## Base for a character's always-on movement passive (Venza's skating, future ones).
##
## The Player creates the passive from CharacterData.passive_scene and calls these hooks.
## It runs on every peer: the owner uses it to move, other peers use it only to show
## effects (trails) from the player's synced flags.

var player: Player


## Called once after the passive is added under the player.
func setup(p_player: Player) -> void:
	player = p_player


## Owner only, every movement tick in the normal state. Set player.velocity and return
## true to take over movement this tick; return false to let normal running happen.
func handle_movement(_delta: float) -> bool:
	return false


## Owner only, right after the player moved (collisions from this move are available).
func after_move(_delta: float) -> void:
	pass


## Owner only: the player is about to dash. Return a direction to replace the dash
## direction (for example a kick off a wall), or Vector2.ZERO to keep it.
func dash_direction_override() -> Vector2:
	return Vector2.ZERO


## Owner only: cancel whatever the passive is doing (death, respawn, other movement).
func interrupt() -> void:
	pass
