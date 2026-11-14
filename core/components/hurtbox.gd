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


## Applies a hit. Returns true if it connected, false if it was ignored.
func receive_hit(hit: HitInfo) -> bool:
	if invulnerable:
		return false
	hit.dealt = maxf(hit.damage - armor, MIN_DAMAGE) if hit.damage > 0.0 else 0.0
	if health != null:
		if health.is_dead():
			return false
		health.take_damage(hit.dealt)
	hit_received.emit(hit)
	return true
