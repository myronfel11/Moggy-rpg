class_name Enemy
extends CharacterBody2D
## Base class for all enemies: health, getting hit, stagger, and dying.
##
## Each kind of enemy extends this and overrides _think() to decide what to do.
## Stats come from an EnemyData file assigned to [member data] before the enemy is
## added to the scene.

signal died(enemy: Enemy)

const PICKUP_SCENE := preload("res://loot/pickup.tscn")
const STAGGER_FRICTION := 900.0
const SPAWN_TIME := 0.5
const DEATH_TIME := 0.18
## A hit that loses more than this fraction of its damage to armour "glances off".
const GLANCING_RATIO := 0.5
## Flash colour for a glancing hit, so the player can see the weapon is not biting.
const GLANCING_FLASH := Color(0.45, 0.55, 0.75)
## How quickly a co-op client's copy glides to the host's position. Higher is snappier.
const PUPPET_SMOOTHING := 25.0
## How long an enemy walks along a wall that is blocking it, in seconds.
const DETOUR_TIME := 0.45
## For this long after a detour, hitting the same wall again continues the same way
## round instead of choosing a side afresh. Without it, a slow enemy sidesteps too short
## a distance to clear the corner, turns back, and shuffles in place forever.
const DETOUR_MEMORY := 1.2
## Moving slower than this fraction of the wanted speed counts as "blocked".
const BLOCKED_SPEED_RATIO := 0.35

var data: EnemyData
## Where the host says this enemy is. Co-op clients glide toward it.
var net_position := Vector2.ZERO

var _hit_stop := 0.0
var _stagger := 0.0
var _spawn_left := SPAWN_TIME
var _dead := false
var _detour_left := 0.0
var _detour_memory := 0.0
var _detour_direction := Vector2.ZERO

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visual: FlashVisual = $Visual


func _ready() -> void:
	assert(data != null, "Assign Enemy.data before adding the enemy to the scene.")
	add_to_group(&"enemies")
	health.setup(data.max_health)
	health.died.connect(_on_died)
	hurtbox.armor = data.armor
	hurtbox.hit_received.connect(_on_hit_received)
	var body := visual.get_node_or_null(^"Body") as Polygon2D
	if body != null:
		body.color = data.color
	# Fade in, harmless and unhittable, so nothing attacks the instant it appears.
	hurtbox.invulnerable = true
	visual.modulate.a = 0.0
	create_tween().tween_property(visual, "modulate:a", 1.0, SPAWN_TIME)


func is_dead() -> bool:
	return _dead


## The closest living player, or null. Never assumes there is only one player.
func find_target() -> Player:
	var best: Player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## Accelerates toward [param point]. If a wall blocks the way, walks along the wall for
## a moment to get around it. Without this, an enemy and a player on opposite sides of
## a pillar push at each other forever. Enough for open rooms; proper pathfinding comes
## with real level layouts.
func steer_toward(point: Vector2, speed: float, acceleration: float, delta: float) -> void:
	var direction := (point - global_position).normalized()
	_detour_memory = maxf(0.0, _detour_memory - delta)
	if _detour_left > 0.0:
		_detour_left -= delta
		direction = _detour_direction
	else:
		var wall_normal := _blocking_wall_normal(speed)
		if wall_normal != Vector2.ZERO:
			var along_wall := wall_normal.orthogonal()
			var side := along_wall.dot(direction)
			var previous := along_wall.dot(_detour_direction)
			if _detour_memory > 0.0 and absf(previous) > 0.7:
				# Still the wall we were just walking along: keep going the same way round.
				side = previous
			elif absf(side) < 0.15:
				# Facing the wall head-on: either way round is as good as the other.
				side = 1.0 if randf() < 0.5 else -1.0
			_detour_direction = along_wall * signf(side)
			_detour_left = DETOUR_TIME
			_detour_memory = DETOUR_TIME + DETOUR_MEMORY
			direction = _detour_direction
	velocity = velocity.move_toward(direction * speed, acceleration * delta)


## True if no wall lies between this enemy and [param point].
func can_see(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point, Layers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## The surface direction of a wall this enemy is stuck against, or zero if it is not stuck.
## Bumping into other enemies does not count.
func _blocking_wall_normal(speed: float) -> Vector2:
	if get_real_velocity().length() > speed * BLOCKED_SPEED_RATIO:
		return Vector2.ZERO
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if not collision.get_collider() is Enemy:
			return collision.get_normal()
	return Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _spawn_left > 0.0:
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			hurtbox.invulnerable = false
		return
	if not is_multiplayer_authority():
		# Co-op client: the host decides what this enemy does. Glide to where it says.
		global_position = global_position.lerp(net_position, 1.0 - exp(-PUPPET_SMOOTHING * delta))
		_puppet_think(delta)
		return
	if _hit_stop > 0.0:
		_hit_stop -= delta
		return
	if _stagger > 0.0:
		# Stunned: slide to a stop from the knockback, no decisions.
		_stagger -= delta
		velocity = velocity.move_toward(Vector2.ZERO, STAGGER_FRICTION * delta)
	else:
		_think(delta)
	move_and_slide()
	net_position = global_position


## Rolls each line of the loot list and scatters the results where the enemy died.
func _drop_loot() -> void:
	for entry in data.drops:
		if entry == null:
			continue
		for i in entry.roll():
			var pickup := PICKUP_SCENE.instantiate() as Pickup
			pickup.item = entry.item
			pickup.position = position
			get_parent().add_child(pickup)


## Override: decide what to do this tick by setting [member velocity].
func _think(_delta: float) -> void:
	pass


## Override: on co-op clients, show what the host's copy is doing (telegraphs, attack
## hitboxes) using the synced values. Never make decisions here.
func _puppet_think(_delta: float) -> void:
	pass


## Override: called when a hit interrupts whatever the enemy was doing.
func _on_interrupted() -> void:
	pass


## Override: return false while the enemy is doing something a hit should not cancel.
## The hit still deals damage and knockback either way.
func _can_be_interrupted() -> bool:
	return true


func _on_hit_received(hit: HitInfo) -> void:
	if _dead:
		return
	velocity = hit.direction * hit.knockback * (1.0 - data.knockback_resistance)
	_hit_stop = maxf(_hit_stop, hit.hit_stop)
	if data.stagger_time > 0.0 and _can_be_interrupted():
		_stagger = data.stagger_time
		_on_interrupted()
	var glancing := hit.dealt < hit.damage * GLANCING_RATIO
	_flash_hit(glancing)
	_net_flash.rpc(glancing)


func _flash_hit(glancing: bool) -> void:
	if glancing:
		visual.flash(0.12, GLANCING_FLASH)
	else:
		visual.flash()


@rpc("authority", "call_remote", "unreliable")
func _net_flash(glancing: bool) -> void:
	if not _dead:
		_flash_hit(glancing)


func _on_died() -> void:
	_die()
	_net_die.rpc()
	# Only the host removes the enemy; removing it also removes it on every client.
	get_tree().create_timer(DEATH_TIME, false).timeout.connect(queue_free)


## On co-op clients: the host's copy died. Play the death and drop this player's loot.
@rpc("authority", "call_remote", "reliable")
func _net_die() -> void:
	if not _dead:
		_die()


## Everything a death looks like, on every peer. Each peer rolls its own loot.
func _die() -> void:
	_dead = true
	_on_interrupted()
	collision_layer = 0
	collision_mask = 0
	hurtbox.set_deferred(&"monitorable", false)
	_drop_loot()
	died.emit(self)
	visual.flash(DEATH_TIME)
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "scale", Vector2(1.6, 1.6), DEATH_TIME)
	tween.tween_property(visual, "modulate:a", 0.0, DEATH_TIME)
