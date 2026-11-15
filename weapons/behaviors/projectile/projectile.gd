class_name Projectile
extends Hitbox
## One bullet. Flies straight, hits the first enemy it touches, and disappears on that hit,
## on a wall, or at the end of its range.
##
## It is a Hitbox, so damage, armour, co-op hit forwarding and "hit each target once" all
## work exactly as for melee weapons. Walls are checked with a ray from the bullet's last
## position to its new one, so even very fast bullets cannot skip through thin walls.
## On other peers' screens bullets are cosmetic (they never deal damage).

var velocity := Vector2.ZERO
var max_distance := 200.0
var color := Color.WHITE
## The weapon that fired this bullet (may be freed if the player swaps weapons).
var weapon: WeaponBehavior

var _travelled := 0.0
var _done := false


func _ready() -> void:
	landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := velocity * delta
	var from := global_position
	var to := from + step
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD)
	var wall := get_world_2d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		global_position = wall.position
		_finish()
		return
	global_position = to
	_travelled += step.length()
	queue_redraw()
	super(delta)
	if not _done and _travelled >= max_distance:
		_finish()


func _on_landed(hurtbox: Hurtbox, hit: HitInfo) -> void:
	if is_instance_valid(weapon):
		weapon.hit_landed.emit(hurtbox, hit)
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	deactivate()
	queue_free()


func _draw() -> void:
	# A short streak pointing backwards along the flight path.
	var tail := -velocity.normalized() * 6.0
	draw_line(tail, Vector2.ZERO, color, 1.5)
	draw_circle(Vector2.ZERO, 1.2, Color.WHITE)
