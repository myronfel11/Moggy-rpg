class_name WeaponBehavior
extends Node2D
## Base class for attack behaviours (melee swing, projectile, beam...).
##
## The wielder owns one behaviour, placed under a pivot that rotates toward the aim
## direction. The wielder calls try_attack() when the player wants to attack and tick()
## every physics frame. Because the wielder drives tick(), freezing the wielder for
## hit-stop automatically freezes the weapon too.
##
## To add a new kind of weapon: extend this class, override the functions below, save it
## as a scene, and point a WeaponData file at that scene.

## Emitted for each target the attack damages.
signal hit_landed(hurtbox: Hurtbox, hit: HitInfo)

var data: WeaponData
var wielder: CharacterBody2D
## Physics layers this weapon can damage (see core/layers.gd).
var target_mask := 0


## Called once by the wielder right after the behaviour is added to the scene.
func setup(p_data: WeaponData, p_wielder: CharacterBody2D, p_target_mask: int) -> void:
	data = p_data
	wielder = p_wielder
	target_mask = p_target_mask
	_on_setup()


## Override to read your data and build hitboxes.
func _on_setup() -> void:
	pass


## Starts an attack if the weapon is ready. Returns true if an attack began.
func try_attack(_aim_direction: Vector2) -> bool:
	return false


## Advances the attack. Called every physics frame by the wielder.
func tick(_delta: float) -> void:
	pass


## Stops the current attack immediately (dash-cancel, death).
func cancel() -> void:
	pass


## True from the moment an attack starts until the weapon is ready again.
func is_busy() -> bool:
	return false


## While true, the wielder should not turn. Commits the player to the swing direction.
func is_aim_locked() -> bool:
	return is_busy()


## How much the wielder is slowed right now (1 = not at all).
func get_move_speed_multiplier() -> float:
	return 1.0
