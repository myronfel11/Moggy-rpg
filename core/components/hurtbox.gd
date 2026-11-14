class_name Hurtbox
extends Area2D
## The area where a character can be hit.
##
## A Hurtbox never looks for attacks itself. Hitboxes find it and call receive_hit().
## It sits on a "hurtbox" physics layer (player or enemy) so each attack can choose
## which side it is able to damage.

signal hit_received(hit: HitInfo)

## However much armour there is, a hit that connects always removes at least this much.
const MIN_DAMAGE := 1.0

## The health pool that hits are applied to.
@export var health: HealthComponent

## While true, hits pass through harmlessly (dash invulnerability, spawn protection).
var invulnerable := false
## Flat amount removed from every hit's damage. Because it is flat rather than a
## percentage, many light hits lose most of their damage while a few heavy hits lose little.
var armor := 0.0

## Co-op: on a peer that does not own this character, pass hits on to the owner instead
## of ignoring them. On for enemies (the host owns them, players on any peer hit them).
## Off for players (only the player's own peer decides whether they were hit, so a dodge
## that worked on their screen always counts).
@export var forward_hits_to_authority := false


## Applies a hit. Returns true if it connected, false if it was ignored.
func receive_hit(hit: HitInfo) -> bool:
	if invulnerable:
		return false
	if health != null and health.is_dead():
		return false
	hit.dealt = maxf(hit.damage - armor, MIN_DAMAGE) if hit.damage > 0.0 else 0.0
	if not is_multiplayer_authority():
		if not forward_hits_to_authority:
			return false
		_request_hit.rpc_id(
			get_multiplayer_authority(), hit.damage, hit.knockback, hit.direction, hit.hit_stop
		)
		# Counted as landed here, so the attacker still gets hit-stop and screen shake.
		return true
	if health != null:
		health.take_damage(hit.dealt)
	hit_received.emit(hit)
	return true


## A hit landed on another peer's screen, applied here by the owner.
@rpc("any_peer", "call_remote", "reliable")
func _request_hit(damage: float, knockback: float, direction: Vector2, hit_stop: float) -> void:
	if is_multiplayer_authority():
		receive_hit(HitInfo.new(damage, knockback, direction, hit_stop))
