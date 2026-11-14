extends Node
## Plays the real arena with scripted input and checks what happens.
##
## This works because the Player only ever reads PlayerInput: the test switches off
## keyboard and mouse reading and sets the input values itself. Run with tools\test.cmd.

const ARENA := preload("res://levels/test_arena/test_arena.tscn")
const CENTER := Vector2(320.0, 192.0)

var _checks := 0
var _failures := 0


func _ready() -> void:
	await _run()
	print("SMOKE TEST: %d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Waits until [param condition] returns true, or [param max_frames] have passed.
func _until(condition: Callable, max_frames: int) -> void:
	for i in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _run() -> void:
	var arena := ARENA.instantiate()
	arena.set(&"auto_start", false)
	add_child(arena)
	var player := (arena as Arena).local_player
	var director := arena.get_node(^"WaveDirector") as WaveDirector
	# The Fabricator lives in the hub now; put one in the arena for these tests.
	var station := preload("res://crafting/crafting_station.tscn").instantiate() as CraftingStation
	station.position = Vector2(320.0, 96.0)
	arena.add_child(station)
	player.input.use_device = false
	await _frames(2)

	await _test_movement(player)
	await _test_dash(player)
	await _test_attack(player, director)
	await _test_hound_rules(player, director)
	await _test_enemy_attack(player, director)
	await _test_wall_detour(player, director)
	await _test_loot(player, director)
	await _test_crafting(player, station)
	await _test_armor(player, director)
	await _test_death_and_respawn(player)
	await _test_waves(player, director)


func _test_movement(player: Player) -> void:
	print("Movement")
	var start := player.global_position
	player.input.move = Vector2.RIGHT
	await _frames(30)
	_check(absf(player.velocity.x - player.max_speed) < 1.0, "reaches top speed")
	_check(player.global_position.x - start.x > 40.0, "moves in the held direction")
	_check(absf(player.global_position.y - start.y) < 0.5, "does not drift sideways")
	player.input.move = Vector2.ZERO
	await _frames(10)
	_check(player.velocity.length() < 1.0, "stops quickly when released")


func _test_dash(player: Player) -> void:
	print("Dash")
	var start := player.global_position
	player.input.aim_direction = Vector2.RIGHT
	player.input.press_dash()
	await _frames(2)
	_check(player.state == Player.State.DASH, "dash starts on press")
	_check(player.hurtbox.invulnerable, "invulnerable while dashing")
	_check(not player.hurtbox.receive_hit(HitInfo.new(50.0)), "a hit during the dash is ignored")
	await _frames(20)
	var distance := player.global_position.x - start.x
	_check(distance > 45.0 and distance < 80.0, "dash covers about 60 pixels (got %.0f)" % distance)
	_check(player.state == Player.State.MOVE, "dash ends")
	_check(not player.hurtbox.invulnerable, "invulnerability ends shortly after")
	_check(player.health.current == player.health.max_health, "no health was lost")
	player.input.press_dash()
	await _frames(2)
	_check(player.state == Player.State.MOVE, "cooldown blocks an immediate second dash")
	await _frames(40)


func _test_attack(player: Player, director: WaveDirector) -> void:
	print("Attack")
	# Enemies look for targets in the "players" group. Leaving it for this test makes the
	# enemy stand still, so only the player's attack is being measured.
	player.remove_from_group(&"players")
	var weapon_damage := player.weapon.data.damage
	var enemy := director.spawn_enemy(director.enemy_type, player.global_position + Vector2(24.0, 0.0))
	await _frames(5)
	_check(enemy.hurtbox.invulnerable, "enemy cannot be hit while fading in")
	await _frames(29)
	var health_before := enemy.health.current
	var x_before := enemy.global_position.x
	player.input.aim_direction = Vector2.RIGHT
	player.input.press_attack()
	await _frames(12)
	_check(
		is_equal_approx(enemy.health.current, health_before - weapon_damage),
		"one swing lands exactly one hit of weapon damage"
	)
	_check(enemy.global_position.x > x_before + 2.0, "the hit knocks the enemy back")

	# Swing away from the enemy: nothing behind the player should be hit.
	await _frames(20)
	var health_mid := enemy.health.current
	player.input.aim_direction = Vector2.LEFT
	player.input.press_attack()
	await _frames(8)
	_check(enemy.health.current == health_mid, "a swing facing away misses")
	await _frames(14)

	for i in 20:
		if not is_instance_valid(enemy) or enemy.is_dead():
			break
		var to_enemy := enemy.global_position - player.global_position
		player.input.aim_direction = to_enemy.normalized()
		player.input.move = to_enemy.normalized() if to_enemy.length() > 22.0 else Vector2.ZERO
		player.input.press_attack()
		await _frames(10)
	player.input.move = Vector2.ZERO
	_check(not is_instance_valid(enemy) or enemy.is_dead(), "repeated hits kill the enemy")
	await _frames(20)
	_check(not is_instance_valid(enemy), "the dead enemy is removed from the scene")
	player.add_to_group(&"players")


func _test_hound_rules(player: Player, director: WaveDirector) -> void:
	print("Scrap Hound rules")
	var normal_health := player.health.max_health
	player.health.setup(1000000.0)
	var spawn_at := player.global_position + Vector2(30.0, 0.0)
	var hound := director.spawn_enemy(director.enemy_type, spawn_at) as Chaser
	await _until(func() -> bool: return hound.get_brain() == Chaser.Brain.WINDUP, 120)
	_check(hound.get_brain() == Chaser.Brain.WINDUP, "winds up when the player is in range")
	var health_before := hound.health.current
	hound.hurtbox.receive_hit(HitInfo.new(1.0, 100.0, Vector2.RIGHT))
	await _frames(3)
	_check(hound.health.current < health_before, "a hit during the windup still deals damage")
	_check(hound.get_brain() == Chaser.Brain.WINDUP, "a hit does not cancel a committed windup")
	await _until(func() -> bool: return hound.get_brain() == Chaser.Brain.LUNGE, 120)
	_check(hound.get_brain() == Chaser.Brain.LUNGE, "the windup ends in a lunge")
	hound.hurtbox.receive_hit(HitInfo.new(1.0, 100.0, Vector2.RIGHT))
	await _frames(2)
	_check(hound.get_brain() != Chaser.Brain.LUNGE, "a hit during the lunge knocks it out of the attack")
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(20)
	player.health.setup(normal_health)


func _test_wall_detour(player: Player, director: WaveDirector) -> void:
	print("Walls")
	# A pillar exactly between enemy and player is the worst case for getting stuck.
	var normal_health := player.health.max_health
	player.health.setup(1000000.0)
	player.global_position = Vector2(222.0, 112.0)
	player.velocity = Vector2.ZERO
	var hound := director.spawn_enemy(director.enemy_type, Vector2(120.0, 112.0))
	await _until(
		func() -> bool: return hound.global_position.distance_to(player.global_position) < 45.0,
		480
	)
	_check(
		hound.global_position.distance_to(player.global_position) < 45.0,
		"an enemy walks around a pillar to reach the player"
	)
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(45)

	# A slow brute, and a player who keeps walking straight at it from the other side of
	# a pillar, placed where the balance probe once found the two stuck for good.
	# Note: this check passes even without the "keep going the same way round" rule in
	# Enemy.steer_toward, so it does not prove that rule works. The real guard against
	# that bug is the stall report in tests/bot_probe.gd.
	player.global_position = Vector2(460.0, 84.0)
	player.velocity = Vector2.ZERO
	var brute := director.spawn_enemy(director.elite_type, Vector2(459.0, 150.0))
	var brute_health := brute.health.current
	for i in 1500:
		if brute.health.current < brute_health:
			break
		TestBot.swing_only(player)
		await get_tree().physics_frame
	TestBot.stop(player)
	_check(
		brute.health.current < brute_health,
		"a slow enemy and a player on opposite sides of a pillar still meet"
	)
	brute.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(45)
	for dropped in get_tree().get_nodes_in_group(&"pickups"):
		dropped.free()
	player.health.setup(normal_health)
	player.global_position = CENTER
	player.velocity = Vector2.ZERO


func _test_enemy_attack(player: Player, director: WaveDirector) -> void:
	print("Enemy attack")
	await _frames(45)
	player.health.reset()
	var hound := director.spawn_enemy(director.enemy_type, player.global_position + Vector2(30.0, 0.0))
	await _frames(120)
	var lost := player.health.max_health - player.health.current
	_check(lost > 0.0, "a lunge damages a player who stands still")
	_check(lost <= 20.0, "post-hit invulnerability limits the damage (lost %.0f)" % lost)
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(45)


func _test_loot(player: Player, director: WaveDirector) -> void:
	print("Loot")
	# Make every drop certain for this test so it does not depend on luck.
	var drops := director.enemy_type.drops
	var original_chances: Array[float] = []
	for entry in drops:
		original_chances.append(entry.chance)
		entry.chance = 1.0
	var scrap := drops[0].item
	var core := drops[1].item
	var scrap_before := player.inventory.get_count(scrap)
	var core_before := player.inventory.get_count(core)

	# Earlier tests killed enemies elsewhere in the room; clear what they dropped so this
	# test only counts its own pieces.
	for old_pickup in get_tree().get_nodes_in_group(&"pickups"):
		old_pickup.free()

	# Pickups look for the "players" group, so leaving it keeps them on the ground.
	player.remove_from_group(&"players")
	var hound := director.spawn_enemy(director.enemy_type, player.global_position + Vector2(22.0, 0.0))
	await _frames(34)
	hound.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(2)
	var dropped := get_tree().get_nodes_in_group(&"pickups").size()
	_check(dropped >= 2, "a dead enemy drops materials (%d pieces)" % dropped)
	await _frames(40)
	_check(
		player.inventory.get_count(scrap) == scrap_before,
		"materials stay on the ground until a player is near"
	)
	player.add_to_group(&"players")
	await _frames(90)
	_check(get_tree().get_nodes_in_group(&"pickups").is_empty(), "nearby materials fly to the player")
	_check(player.inventory.get_count(scrap) > scrap_before, "collected Scrap is counted")
	_check(player.inventory.get_count(core) == core_before + 1, "collected Volt Core is counted")
	for i in drops.size():
		drops[i].chance = original_chances[i]


func _test_crafting(player: Player, station: CraftingStation) -> void:
	print("Crafting")
	var recipe := station.recipe_book.recipes[0]
	var starter := player.weapon.data
	player.input.press_interact()
	await _frames(3)
	_check(not player.owns_weapon(recipe.result), "interacting away from the station does nothing")

	player.global_position = station.global_position + Vector2(0.0, 24.0)
	player.velocity = Vector2.ZERO
	await _frames(4)
	_check(station.is_in_range(player), "the station notices a player standing next to it")
	player.input.press_interact()
	await _frames(3)
	_check(not player.owns_weapon(recipe.result), "cannot craft without the materials")

	var before := {}
	for cost in recipe.costs:
		player.inventory.add(cost.item, cost.amount)
		before[cost.item.id] = player.inventory.get_count(cost.item)
	player.input.press_interact()
	await _frames(3)
	_check(player.owns_weapon(recipe.result), "crafting with enough materials unlocks the weapon")
	_check(player.weapon.data == recipe.result, "the crafted weapon is equipped straight away")
	var exact := true
	for cost in recipe.costs:
		exact = exact and player.inventory.get_count(cost.item) == before[cost.item.id] - cost.amount
	_check(exact, "crafting spends exactly the recipe cost")
	_check(station.get_next_recipe(player) == null, "a crafted recipe is no longer offered")

	player.input.press_swap()
	await _frames(3)
	_check(player.weapon.data == starter, "swap returns to the starter weapon")
	player.input.press_swap()
	await _frames(3)
	_check(player.weapon.data == recipe.result, "swap cycles forward again")

	player.global_position = CENTER
	player.velocity = Vector2.ZERO
	await _frames(4)
	_check(not station.is_in_range(player), "the station notices the player leaving")


func _equip(player: Player, weapon_id: StringName) -> void:
	for owned in player.weapons:
		if owned.id == weapon_id:
			player.equip(owned)


func _test_armor(player: Player, director: WaveDirector) -> void:
	print("Armour")
	player.remove_from_group(&"players")
	var brute := director.spawn_enemy(director.elite_type, player.global_position + Vector2(30.0, 0.0))
	await _frames(34)
	player.input.aim_direction = Vector2.RIGHT

	_equip(player, &"pulse_blade")
	var health := brute.health.current
	player.input.press_attack()
	await _frames(14)
	var blade_damage := health - brute.health.current
	_check(is_equal_approx(blade_damage, 3.0), "the blade only chips a Plated Brute (%.0f damage)" % blade_damage)
	await _frames(20)

	_equip(player, &"breaker")
	health = brute.health.current
	player.input.press_attack()
	await _frames(40)
	var breaker_damage := health - brute.health.current
	_check(is_equal_approx(breaker_damage, 27.0), "the Breaker punches through (%.0f damage)" % breaker_damage)

	var core := director.elite_type.drops[1].item
	var cores_before := player.inventory.get_count(core)
	var brute_position := brute.global_position
	brute.hurtbox.receive_hit(HitInfo.new(9999.0))
	await _frames(30)
	player.add_to_group(&"players")
	player.global_position = brute_position
	player.velocity = Vector2.ZERO
	await _frames(60)
	_check(player.inventory.get_count(core) == cores_before + 1, "a dead brute always leaves a Volt Core")
	player.global_position = CENTER
	player.velocity = Vector2.ZERO


func _count_materials(player: Player) -> int:
	var total := 0
	for item in player.inventory.get_items():
		total += player.inventory.get_count(item)
	return total


func _test_death_and_respawn(player: Player) -> void:
	print("Death and respawn")
	var materials_before := _count_materials(player)
	var weapons_before := player.weapons.size()
	var deaths := [0]
	player.died.connect(func() -> void: deaths[0] += 1)
	player.hurtbox.receive_hit(HitInfo.new(9999.0, 0.0, Vector2.RIGHT))
	_check(not player.is_alive() and deaths[0] == 1, "the player dies at zero health")
	await _frames(5)
	player.respawn(CENTER)
	_check(player.is_alive(), "respawn revives")
	_check(player.health.current == player.health.max_health, "respawn restores health")
	_check(player.hurtbox.invulnerable, "respawn grants brief protection")
	_check(player.global_position.distance_to(CENTER) < 1.0, "respawn moves to the start point")
	_check(
		_count_materials(player) == materials_before and player.weapons.size() == weapons_before,
		"dying keeps materials and crafted weapons"
	)


func _test_waves(player: Player, director: WaveDirector) -> void:
	print("Waves")
	director.start()
	await _frames(3)
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	_check(enemies.size() == director.first_wave_size, "the first wave has %d enemies" % director.first_wave_size)
	var far_enough := true
	for enemy: Enemy in enemies:
		far_enough = far_enough and enemy.global_position.distance_to(player.global_position) > 80.0
	_check(far_enough, "enemies spawn away from the player")

	# Let a simple bot fight with effectively endless health, so the result does not
	# depend on luck: walk at the nearest enemy and swing when close.
	player.health.setup(1000000.0)
	for i in 3600:
		if director.wave >= 2:
			break
		TestBot.swing_only(player)
		await get_tree().physics_frame
	TestBot.stop(player)
	_check(director.wave >= 2, "clearing a wave starts the next one")
	await _frames(3)
	var second_wave := get_tree().get_nodes_in_group(&"enemies").size()
	_check(
		second_wave == director.first_wave_size + director.wave_growth,
		"the second wave is larger (got %d)" % second_wave
	)
	var early_elites := 0
	for enemy: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.data == director.elite_type:
			early_elites += 1
	_check(early_elites == 0, "no elites before wave %d" % director.elite_from_wave)

	for i in 7200:
		if director.wave >= director.elite_from_wave:
			break
		TestBot.swing_only(player)
		await get_tree().physics_frame
	TestBot.stop(player)
	await _frames(3)
	var elites := 0
	for enemy: Enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.data == director.elite_type and not enemy.is_dead():
			elites += 1
	_check(elites == 1, "wave %d brings one Plated Brute (got %d)" % [director.elite_from_wave, elites])

	# A player who stops fighting should eventually die, and the run should restart.
	player.health.setup(20.0)
	var respawns := [0]
	player.respawned.connect(func() -> void: respawns[0] += 1)
	for i in 3600:
		if respawns[0] > 0:
			break
		await get_tree().physics_frame
	_check(respawns[0] > 0, "an idle player dies and the run restarts")
	await _frames(3)
	_check(director.wave == 1, "the restart goes back to wave 1")
