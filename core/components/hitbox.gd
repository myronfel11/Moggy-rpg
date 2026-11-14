class_name Hitbox
extends Area2D
## An attack's damaging area.
##
## It is harmless until activate() is called, then damages each Hurtbox it overlaps
## exactly once until deactivate(). Its collision mask decides whose hurtboxes it can
## touch (see core/layers.gd).

signal landed(hurtbox: Hurtbox, hit: HitInfo)

var _active := false
var _wait_frames := 0
var _damage := 0.0
var _knockback := 0.0
var _hit_stop := 0.0
var _source: Node2D
var _already_hit: Array[Hurtbox] = []


## Starts damaging. Knockback pushes targets directly away from [param source].
func activate(damage: float, knockback: float, hit_stop: float, source: Node2D) -> void:
	_damage = damage
	_knockback = knockback
	_hit_stop = hit_stop
	_source = source
	_already_hit.clear()
	_active = true
	# The physics engine only refreshes overlaps once per physics step. Waiting one step
	# makes sure we test the area where it is now, not where it pointed a moment ago.
	_wait_frames = 1


func deactivate() -> void:
	_active = false


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	if _wait_frames > 0:
		_wait_frames -= 1
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or _already_hit.has(hurtbox):
			continue
		# Remember the target even if the hit is ignored, so a dodged attack stays dodged.
		_already_hit.append(hurtbox)
		var hit := HitInfo.new(_damage, _knockback, _direction_to(hurtbox), _hit_stop, _source)
		if hurtbox.receive_hit(hit):
			landed.emit(hurtbox, hit)


func _direction_to(hurtbox: Hurtbox) -> Vector2:
	if not is_instance_valid(_source):
		return Vector2.RIGHT
	var direction := (hurtbox.global_position - _source.global_position).normalized()
	return direction if direction != Vector2.ZERO else Vector2.RIGHT
