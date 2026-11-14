class_name HitInfo
extends RefCounted
## Everything a target needs to know about one hit.
##
## A Hitbox creates one of these per target and hands it to that target's Hurtbox.
## Bundling the values means new properties (status effects, crits) can be added later
## without changing every function that passes a hit along.

## Hit points the attack tries to remove, before the target's armour.
var damage: float
## Hit points actually removed, after armour. Filled in by the Hurtbox that takes the hit.
var dealt := 0.0
## Push-back speed in pixels per second.
var knockback: float
## Unit vector pointing from the attacker toward the target.
var direction: Vector2
## Seconds both attacker and target freeze on impact.
var hit_stop: float
## Who dealt the hit. May have been freed since; check is_instance_valid() before use.
var source: Node


func _init(
	p_damage := 0.0,
	p_knockback := 0.0,
	p_direction := Vector2.ZERO,
	p_hit_stop := 0.0,
	p_source: Node = null
) -> void:
	damage = p_damage
	knockback = p_knockback
	direction = p_direction
	hit_stop = p_hit_stop
	source = p_source
