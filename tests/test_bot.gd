class_name TestBot
## Two scripted ways of playing, used by the tests and the balance probe.
##
##   swing_only      - walks at the nearest enemy and swings. Never dodges. If this does
##                     well, the game rewards "stand there and mash attack".
##   swing_and_dodge - the same, but sidesteps and dashes out of a lunge when an enemy
##                     flashes. If this does much better than swing_only, movement matters.
##
## Comparing the two gives a number for the design goal, even though bots cannot say
## whether the game is fun.

const APPROACH_DISTANCE := 24.0
const ATTACK_DISTANCE := 36.0
const THREAT_RADIUS := 80.0


static func nearest_enemy(player: Player) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for node in player.get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var distance := player.global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


static func swing_only(player: Player) -> void:
	var target := nearest_enemy(player)
	if target == null:
		stop(player)
		return
	var to_target := target.global_position - player.global_position
	var distance := to_target.length()
	player.input.aim_direction = to_target.normalized()
	player.input.move = to_target.normalized() if distance > APPROACH_DISTANCE else Vector2.ZERO
	player.input.attack_held = distance < ATTACK_DISTANCE


static func swing_and_dodge(player: Player) -> void:
	var threat := _nearest_threat(player)
	if threat == null:
		swing_only(player)
		return
	# Step sideways off the lunge line, to whichever side the player is already on.
	var side := threat.get_lunge_direction().orthogonal()
	if side.dot(player.global_position - threat.global_position) < 0.0:
		side = -side
	player.input.move = side
	player.input.attack_held = false
	player.input.press_dash()


static func stop(player: Player) -> void:
	player.input.move = Vector2.ZERO
	player.input.attack_held = false


## The closest enemy that is about to lunge, or is lunging, near the player.
static func _nearest_threat(player: Player) -> Chaser:
	var best: Chaser = null
	var best_distance := THREAT_RADIUS * THREAT_RADIUS
	for node in player.get_tree().get_nodes_in_group(&"enemies"):
		var chaser := node as Chaser
		if chaser == null or chaser.is_dead():
			continue
		if not (chaser.is_lunge_locked() or chaser.get_brain() == Chaser.Brain.LUNGE):
			continue
		var distance := player.global_position.distance_squared_to(chaser.global_position)
		if distance < best_distance:
			best_distance = distance
			best = chaser
	return best
