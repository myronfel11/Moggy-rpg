class_name PillarBoss
extends Enemy
## The Warden: the giant central boss of "The Three Pillars". It never moves. Its shield is
## up until the encounter says otherwise, and it fires a charged sniper laser.
##
## The laser is a cycle the host runs (IDLE, ACQUIRE, CHARGE, LOCK, FIRE, RECOVER). The
## phase, time left, direction and target are synced, so every peer draws the same
## telegraph (laser_telegraph.gd). When a peer sees the beam fire it checks only its own
## player against the beam: a dodge that worked on your screen always counts, and
## invulnerability (a dash, Rush, a Zenith lunge) protects you as it does from any attack.
## The beam passes through walls and hits everyone along it.

enum Laser { IDLE, ACQUIRE, CHARGE, LOCK, FIRE, RECOVER }

## A player's body radius, added to the beam's half width when checking hits.
const PLAYER_RADIUS := 5.0
## Laser lines are drawn this long, enough to cross the whole arena.
const BEAM_LENGTH := 1200.0
const SHIELD_RADIUS := 36.0

## Synced: which step of the laser cycle is running.
var laser_phase := Laser.IDLE
## Synced: seconds left in the current step.
var laser_time_left := 0.0
## Synced: where the laser points (unit vector).
var laser_dir := Vector2.DOWN
## Synced: the targeted player's network peer, 0 for none.
var laser_target_peer := 0
## Synced: whether weapons can damage the boss right now (set by the encounter).
var vulnerable := false
## Host only: the encounter turns the laser on and off.
var laser_enabled := false

var _last_target_peer := 0
var _seen_phase := Laser.IDLE
var _pulse := 0.0


func _ready() -> void:
	super()
	add_to_group(&"pillar_boss")


## The encounter's settings (shared with every peer through the arena scene).
func settings() -> ThreePillarsData:
	var encounter := get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter
	return encounter.data if encounter != null and encounter.data != null else load(BossEncounter.DATA_PATH) as ThreePillarsData


## True if [param point] is inside a beam fired from [param origin] along [param direction].
static func in_beam(origin: Vector2, direction: Vector2, point: Vector2, half_width: float) -> bool:
	var offset := point - origin
	if offset.dot(direction) < 0.0:
		return false
	return absf(offset.cross(direction)) <= half_width + PLAYER_RADIUS


func is_charging_at(peer: int) -> bool:
	return laser_target_peer == peer and laser_phase in [Laser.ACQUIRE, Laser.CHARGE, Laser.LOCK]


func _think(delta: float) -> void:
	velocity = Vector2.ZERO
	_update_laser(delta)


## Host: advances the laser cycle.
func _update_laser(delta: float) -> void:
	if not laser_enabled:
		if laser_phase != Laser.IDLE:
			_set_phase(Laser.IDLE, settings().idle_time)
			laser_target_peer = 0
		return
	var tuning := settings()
	laser_time_left -= delta
	match laser_phase:
		Laser.IDLE:
			if laser_time_left > 0.0:
				return
			var target := _pick_target()
			if target == null:
				laser_time_left = 0.3
				return
			laser_target_peer = target.peer_id
			_last_target_peer = target.peer_id
			laser_dir = _direction_to(target)
			_set_phase(Laser.ACQUIRE, tuning.acquire_time)
		Laser.ACQUIRE, Laser.CHARGE:
			var target := _level().get_player_by_peer(laser_target_peer) if _level() != null else null
			if target == null or not target.is_targetable():
				# The target died, left or turned invisible: start over.
				laser_target_peer = 0
				_set_phase(Laser.IDLE, 0.5)
				return
			laser_dir = _direction_to(target)
			if laser_time_left <= 0.0:
				if laser_phase == Laser.ACQUIRE:
					_set_phase(Laser.CHARGE, tuning.charge_time)
				else:
					_set_phase(Laser.LOCK, tuning.lock_time)
		Laser.LOCK:
			if laser_time_left <= 0.0:
				_set_phase(Laser.FIRE, tuning.fire_time)
		Laser.FIRE:
			if laser_time_left <= 0.0:
				_set_phase(Laser.RECOVER, tuning.recover_time)
		Laser.RECOVER:
			if laser_time_left <= 0.0:
				laser_target_peer = 0
				_set_phase(Laser.IDLE, tuning.idle_time)


func _set_phase(phase: Laser, seconds: float) -> void:
	laser_phase = phase
	laser_time_left = seconds


func _direction_to(player: Player) -> Vector2:
	var offset := player.global_position - global_position
	return offset.normalized() if offset.length() > 0.5 else laser_dir


## A random player that can be targeted, avoiding the last target when there is a choice.
func _pick_target() -> Player:
	var level := _level()
	if level == null:
		return null
	var choices: Array[Player] = []
	for player in level.get_players():
		if player.is_targetable():
			choices.append(player)
	if choices.size() > 1:
		choices = choices.filter(func(p: Player) -> bool: return p.peer_id != _last_target_peer)
	return choices.pick_random() if not choices.is_empty() else null


func _level() -> Level:
	return get_tree().get_first_node_in_group(&"level") as Level


func _process(delta: float) -> void:
	if _dead:
		return
	hurtbox.invulnerable = _spawn_left > 0.0 or not vulnerable
	if laser_phase == Laser.FIRE and _seen_phase != Laser.FIRE:
		_on_fire_seen()
	_seen_phase = laser_phase
	_burst = maxf(0.0, _burst - delta)
	# The eye swells while charging.
	_pulse += delta * (14.0 if laser_phase in [Laser.CHARGE, Laser.LOCK] else 3.0)
	var eye := visual.get_node_or_null(^"Eye") as Node2D
	if eye != null:
		var grow := 1.0
		if laser_phase == Laser.CHARGE:
			grow = 1.0 + 0.6 * (1.0 - laser_time_left / maxf(settings().charge_time, 0.01))
		elif laser_phase == Laser.LOCK:
			grow = 1.7
		eye.scale = Vector2.ONE * (grow + 0.08 * sin(_pulse))
	queue_redraw()


## Every peer: the beam just fired. Check only this machine's own player.
func _on_fire_seen() -> void:
	get_tree().call_group(&"game_camera", &"add_trauma", 0.7)
	visual.flash(0.2, Color(1.0, 0.4, 0.4))
	var level := _level()
	if level == null or level.local_player == null or not is_instance_valid(level.local_player):
		return
	var player := level.local_player
	if not player.is_alive() or player.hurtbox.invulnerable:
		return
	if in_beam(global_position, laser_dir, player.global_position, settings().beam_half_width):
		player.hurtbox.receive_hit(HitInfo.new(100000000.0, 0.0, laser_dir, 0.0))


## Every peer: a bomb was slammed in (a burst at the boss).
func play_slam_effect() -> void:
	_burst = 0.5
	_burst_color = Color(1.0, 0.85, 0.4)
	visual.flash(0.3, Color(1.0, 0.85, 0.4))


## Every peer: the shield shattered (a bigger burst).
func play_shield_break_effect() -> void:
	_burst = 0.8
	_burst_color = Color(0.55, 0.85, 1.0)
	visual.flash(0.5, Color.WHITE)


var _burst := 0.0
var _burst_color := Color.WHITE


func _draw() -> void:
	if _burst > 0.0:
		var progress := 1.0 - _burst / 0.8
		draw_arc(Vector2.ZERO, SHIELD_RADIUS + 70.0 * progress, 0.0, TAU, 40, Color(_burst_color, 1.0 - progress), 4.0)
		draw_arc(Vector2.ZERO, SHIELD_RADIUS + 40.0 * progress, 0.0, TAU, 40, Color(_burst_color, 0.6 * (1.0 - progress)), 2.0)
	if _dead or vulnerable:
		return
	# The shield: a ring split into three parts, one per bomb still needed.
	var encounter := get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter
	var remaining := 3 if encounter == null else 3 - encounter.get_bombs_delivered()
	var color := Color(0.55, 0.85, 1.0, 0.75 + 0.15 * sin(_pulse * 0.5))
	for i in 3:
		var start := -PI * 0.5 + TAU * i / 3.0 + 0.08
		var end := start + TAU / 3.0 - 0.16
		var part := color if i < remaining else Color(color, 0.12)
		draw_arc(Vector2.ZERO, SHIELD_RADIUS, start, end, 18, part, 3.0)
