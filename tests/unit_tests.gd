extends Node
## Fast checks of individual building blocks. Run with tools\test.cmd.
##
## Deliberately tiny: a check is a true/false condition with a label. No test framework.

var _checks := 0
var _failures := 0


func _ready() -> void:
	_test_health()
	_test_hurtbox()
	_test_weapon_data()
	_test_swing_shape()
	_test_enemy_data()
	_test_input_map()
	_test_inventory()
	_test_drops()
	_test_armor()
	_test_recipe()
	_test_mission_rewards()
	print("UNIT TESTS: %d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _test_health() -> void:
	print("HealthComponent")
	var health := HealthComponent.new()
	add_child(health)
	health.setup(50.0)
	var deaths := [0]
	health.died.connect(func() -> void: deaths[0] += 1)
	_check(health.current == 50.0, "setup fills to the new maximum")
	_check(health.take_damage(20.0) == 20.0 and health.current == 30.0, "damage is subtracted")
	_check(health.take_damage(-5.0) == 0.0 and health.current == 30.0, "negative damage is ignored")
	_check(health.take_damage(100.0) == 30.0, "overkill only deals what was left")
	_check(health.is_dead() and deaths[0] == 1, "dies exactly once at zero")
	_check(health.take_damage(5.0) == 0.0 and deaths[0] == 1, "the dead take no damage")
	health.reset()
	_check(not health.is_dead() and health.current == 50.0, "reset refills")
	health.queue_free()


func _test_hurtbox() -> void:
	print("Hurtbox")
	var health := HealthComponent.new()
	add_child(health)
	health.setup(40.0)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	add_child(hurtbox)
	var hits := [0]
	hurtbox.hit_received.connect(func(_hit: HitInfo) -> void: hits[0] += 1)
	var hit := HitInfo.new(15.0, 100.0, Vector2.RIGHT, 0.05, null)
	_check(hurtbox.receive_hit(hit), "a hit connects")
	_check(health.current == 25.0 and hits[0] == 1, "the hit reaches health and is announced")
	hurtbox.invulnerable = true
	_check(not hurtbox.receive_hit(hit) and health.current == 25.0, "invulnerable ignores hits")
	hurtbox.invulnerable = false
	hurtbox.receive_hit(HitInfo.new(999.0))
	_check(health.is_dead(), "lethal hit kills")
	_check(not hurtbox.receive_hit(hit) and hits[0] == 2, "the dead cannot be hit again")
	hurtbox.queue_free()
	health.queue_free()


func _test_weapon_data() -> void:
	print("Weapon data")
	var weapon := load("res://weapons/data/pulse_blade.tres") as MeleeSwingData
	_check(weapon != null, "pulse_blade.tres loads as MeleeSwingData")
	if weapon == null:
		return
	_check(weapon.id == &"pulse_blade" and weapon.display_name != "", "has an id and a name")
	_check(weapon.damage > 0.0 and weapon.reach > 0.0, "has damage and reach")
	_check(weapon.active_time >= 0.05, "active window is long enough to register")
	_check(weapon.behavior_scene != null, "points at a behaviour scene")
	if weapon.behavior_scene != null:
		var behavior := weapon.behavior_scene.instantiate()
		_check(behavior is MeleeSwing, "the behaviour scene is a MeleeSwing")
		behavior.free()


func _test_swing_shape() -> void:
	print("Swing hit area")
	var sector := MeleeSwing.build_sector(30.0, 110.0)
	_check(sector.size() == 12, "a slice is the centre plus 11 edge points")
	_check(sector[0] == Vector2.ZERO, "a slice starts at the wielder")
	var on_edge := true
	for i in range(1, sector.size()):
		on_edge = on_edge and is_equal_approx(sector[i].length(), 30.0)
	_check(on_edge, "edge points sit exactly at reach")
	_check(is_equal_approx(rad_to_deg(sector[1].angle()), -55.0), "slice starts at minus half the arc")
	_check(is_equal_approx(rad_to_deg(sector[11].angle()), 55.0), "slice ends at plus half the arc")
	var circle := MeleeSwing.build_sector(30.0, 360.0)
	_check(circle.size() == 10 and circle[0] != Vector2.ZERO, "a full spin is a ring with no centre")


func _test_enemy_data() -> void:
	print("Enemy data")
	var hound := load("res://enemies/data/scrap_hound.tres") as ChaserData
	_check(hound != null, "scrap_hound.tres loads as ChaserData")
	if hound == null:
		return
	_check(hound.id == &"scrap_hound" and hound.max_health > 0.0, "has an id and health")
	_check(hound.lunge_speed * hound.lunge_duration > hound.attack_range, "lunge can reach its target")
	_check(hound.windup > Chaser.AIM_LOCK_TIME, "windup is longer than the aim lock")
	_check(hound.scene != null, "points at an enemy scene")
	if hound.scene != null:
		var enemy := hound.scene.instantiate()
		_check(enemy is Chaser, "the enemy scene is a Chaser")
		enemy.free()


func _test_input_map() -> void:
	print("Input map")
	var actions: Array[StringName] = [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"dash", &"attack", &"interact", &"swap_weapon",
	]
	for action in actions:
		var bound := InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty()
		_check(bound, "'%s' is bound to a key or button" % action)


func _cost(item: ItemData, amount: int) -> ItemAmount:
	var cost := ItemAmount.new()
	cost.item = item
	cost.amount = amount
	return cost


func _test_inventory() -> void:
	print("Inventory")
	var scrap := load("res://items/data/scrap.tres") as ItemData
	var core := load("res://items/data/volt_core.tres") as ItemData
	_check(scrap != null and core != null, "material files load")
	if scrap == null or core == null:
		return
	var inventory := Inventory.new()
	add_child(inventory)
	var changes := [0]
	inventory.changed.connect(func(_item: ItemData, _count: int, _change: int) -> void: changes[0] += 1)
	_check(inventory.get_count(scrap) == 0, "starts empty")
	inventory.add(scrap, 5)
	inventory.add(scrap, 2)
	inventory.add(core)
	_check(inventory.get_count(scrap) == 7 and inventory.get_count(core) == 1, "adding stacks up per item")
	_check(changes[0] == 3, "every change is announced")
	inventory.add(scrap, 0)
	inventory.add(null, 3)
	_check(inventory.get_count(scrap) == 7 and changes[0] == 3, "empty adds are ignored")
	var costs: Array[ItemAmount] = [_cost(scrap, 4), _cost(core, 2)]
	_check(not inventory.can_afford(costs), "cannot afford a cost when one item is short")
	_check(not inventory.spend(costs) and inventory.get_count(scrap) == 7, "a failed purchase takes nothing")
	inventory.add(core)
	_check(inventory.spend(costs), "can spend once everything is covered")
	_check(inventory.get_count(scrap) == 3 and inventory.get_count(core) == 0, "spending removes exactly the cost")
	_check(inventory.get_items().size() == 2, "remembers which items have been seen")
	inventory.queue_free()


func _test_drops() -> void:
	print("Drops")
	var entry := DropEntry.new()
	entry.item = load("res://items/data/scrap.tres") as ItemData
	entry.min_amount = 2
	entry.max_amount = 4
	entry.chance = 1.0
	var within_range := true
	for i in 200:
		var amount := entry.roll()
		within_range = within_range and amount >= 2 and amount <= 4
	_check(within_range, "a certain drop always gives an amount inside its range")
	entry.chance = 0.0
	var never := true
	for i in 200:
		never = never and entry.roll() == 0
	_check(never, "a zero-chance drop never drops")
	entry.chance = 0.2
	var landed := 0
	for i in 5000:
		if entry.roll() > 0:
			landed += 1
	_check(landed > 800 and landed < 1200, "a 20%% drop lands about one time in five (%d of 5000)" % landed)
	var hound := load("res://enemies/data/scrap_hound.tres") as ChaserData
	var listed := hound != null and hound.drops.size() == 2
	_check(listed and hound.drops[0].item != null and hound.drops[1].item != null, "the hound's loot list loads")
	if not listed:
		return
	var scrap_path := hound.drops[0].item.resource_path
	var core_path := hound.drops[1].item.resource_path
	var sensible := true
	var cores_seen := 0
	for i in 500:
		var pieces := Enemy.roll_drops(hound.drops)
		var scraps := pieces.count(scrap_path)
		var cores := pieces.count(core_path)
		cores_seen += cores
		sensible = sensible and scraps >= 1 and scraps <= 2 and cores <= 1 and pieces.size() == scraps + cores
	_check(sensible, "one roll of the hound's loot gives 1-2 Scrap and at most 1 Volt Core")
	_check(cores_seen > 50 and cores_seen < 150, "Volt Cores drop about one kill in five (%d of 500)" % cores_seen)


func _test_armor() -> void:
	print("Armour")
	var health := HealthComponent.new()
	add_child(health)
	health.setup(100.0)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	hurtbox.armor = 9.0
	add_child(hurtbox)
	var light := HitInfo.new(12.0)
	hurtbox.receive_hit(light)
	_check(light.dealt == 3.0 and health.current == 97.0, "armour removes a flat amount from a hit")
	var tiny := HitInfo.new(4.0)
	hurtbox.receive_hit(tiny)
	_check(tiny.dealt == 1.0 and health.current == 96.0, "a hit always deals at least 1")
	var heavy := HitInfo.new(36.0)
	hurtbox.receive_hit(heavy)
	_check(heavy.dealt == 27.0, "a heavy hit keeps most of its damage")
	hurtbox.queue_free()
	health.queue_free()

	var blade := load("res://weapons/data/pulse_blade.tres") as WeaponData
	var breaker := load("res://weapons/data/breaker.tres") as MeleeSwingData
	var brute := load("res://enemies/data/plated_brute.tres") as ChaserData
	_check(breaker != null and breaker.behavior_scene != null, "breaker.tres loads as MeleeSwingData")
	_check(brute != null and brute.scene != null, "plated_brute.tres loads as ChaserData")
	if blade == null or breaker == null or brute == null:
		return
	var blade_hits := ceili(brute.max_health / maxf(blade.damage - brute.armor, Hurtbox.MIN_DAMAGE))
	var breaker_hits := ceili(brute.max_health / maxf(breaker.damage - brute.armor, Hurtbox.MIN_DAMAGE))
	_check(
		blade_hits >= breaker_hits * 4,
		"a brute takes far fewer Breaker hits than blade hits (%d vs %d)" % [breaker_hits, blade_hits]
	)
	var hound := load("res://enemies/data/scrap_hound.tres") as ChaserData
	_check(breaker.damage >= hound.max_health, "the Breaker fells a hound in one hit")

	# The starter gun trades damage for range: weaker than the blade up close.
	var gun := load("res://weapons/data/spark_pistol.tres") as ProjectileWeaponData
	_check(gun != null and gun.behavior_scene != null, "spark_pistol.tres loads as ProjectileWeaponData")
	if gun == null:
		return
	var blade_dps := blade.damage / (blade.windup + blade.active_time + blade.recovery)
	var gun_dps := gun.damage / gun.fire_interval
	_check(gun_dps < blade_dps, "the Spark Pistol does less damage per second than the blade (%.0f vs %.0f)" % [gun_dps, blade_dps])
	_check(gun.projectile_range > (blade as MeleeSwingData).reach * 4.0, "the Spark Pistol reaches far beyond the blade")


func _test_recipe() -> void:
	print("Recipe")
	var recipe := load("res://crafting/data/breaker_recipe.tres") as Recipe
	_check(recipe != null, "breaker_recipe.tres loads as Recipe")
	if recipe == null:
		return
	_check(recipe.result != null and recipe.result.id == &"breaker", "it produces the Breaker")
	_check(recipe.costs.size() == 2, "it lists two material costs")
	var complete := true
	for cost in recipe.costs:
		complete = complete and cost != null and cost.item != null and cost.amount > 0
	_check(complete, "every cost names an item and an amount")


func _test_mission_rewards() -> void:
	print("Mission rewards")
	var expected := {
		"res://missions/data/crown.tres": ["Venza Crown", 0.15],
		"res://missions/data/suit.tres": ["Venza Suit", 0.40],
		"res://missions/data/weapon.tres": ["Venza Weapon Components", 0.35],
	}
	for path: String in expected:
		var mission := load(path) as MissionData
		var ok := mission != null and mission.reward_item != null
		ok = ok and mission.reward_item.display_name == expected[path][0]
		ok = ok and is_equal_approx(mission.reward_chance, expected[path][1])
		_check(ok, "%s rewards %s at %d%%" % [path.get_file(), expected[path][0], roundi(expected[path][1] * 100.0)])

	var test_mission := (load("res://missions/data/crown.tres") as MissionData).duplicate() as MissionData
	for chance: float in [0.0, 0.15, 1.0]:
		test_mission.reward_chance = chance
		var hits := 0
		for i in 4000:
			if Arena.roll_reward(test_mission) != "":
				hits += 1
		var expected_hits := chance * 4000.0
		_check(absf(hits - expected_hits) <= maxf(4000.0 * 0.025, 0.5), "a %d%% reward lands about %d times in 4000 (got %d)" % [roundi(chance * 100.0), roundi(expected_hits), hits])
	test_mission.reward_chance = 1.0
	_check(Arena.roll_reward(test_mission) == test_mission.reward_item.resource_path, "a successful roll returns the reward item")
	_check(Arena.roll_reward(load("res://missions/data/endless_siege.tres") as MissionData) == "", "a mission without a featured reward never awards one")

	var crown_mission := load("res://missions/data/crown.tres") as MissionData
	var won := Arena.describe_result(crown_mission, true, crown_mission.reward_item.resource_path)
	var missed := Arena.describe_result(crown_mission, true, "")
	_check(won.contains("MISSION COMPLETE") and won.contains("Reward: Venza Crown"), "a won reward is announced")
	_check(missed.contains("No Venza Crown this time (15% chance)"), "a missed reward is announced with its chance")
	_check(Arena.describe_result(crown_mission, false, "") == "MISSION FAILED", "a failed mission announces no reward")
	_check(MissionPanel.describe(crown_mission, null).contains("Venza Crown - 15% on completion"), "the mission menu text shows reward and chance")
