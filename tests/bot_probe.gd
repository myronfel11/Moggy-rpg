extends Node
## Balance probe: a scripted bot plays for a while and this reports how it did.
##
## Not a pass/fail test. It is a measuring tool for tuning, since "is it too easy to
## just stand and swing?" can be counted even though "is it fun?" cannot.
##
## Usage:
##   godot --headless --fixed-fps 60 --path <project> res://tests/bot_probe.tscn -- --seconds=60
## Use the bot that dodges lunges (see tests/test_bot.gd):
##   ... -- --seconds=60 --bot=dodge
## Start with a crafted weapon already equipped (file name from weapons/data):
##   ... -- --seconds=60 --bot=dodge --weapon=breaker
## Try an enemy stat without editing its file:
##   ... -- --seconds=60 --set=attack_range:56 --set=windup:0.4
##
## The bots never visit the crafting station, so "recipe affordable at" is the moment
## they had collected enough, not the moment they crafted.

const ARENA := preload("res://levels/test_arena/test_arena.tscn")
## If nothing dies for this long, something is probably stuck. Print where everyone is.
const STALL_SECONDS := 45


## Prints a snapshot of the player and every enemy, for working out why a fight stalled.
func _report_stall(player: Player, at_seconds: float) -> void:
	print("  STALL at %.0f s: nothing has died for %d s" % [at_seconds, STALL_SECONDS])
	print("    player at %s  state=%s  health=%.0f  moving=%s  attacking=%s" % [
		player.global_position.round(), Player.State.keys()[player.state], player.health.current,
		player.input.move.snapped(Vector2(0.01, 0.01)), player.input.attack_held,
	])
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var chaser := enemy as Chaser
		var brain := "?" if chaser == null else str(Chaser.Brain.keys()[chaser.get_brain()])
		print("    %s at %s  health=%.0f  brain=%s  speed=%.0f  distance=%.0f  sees_player=%s" % [
			enemy.data.display_name, enemy.global_position.round(), enemy.health.current, brain,
			enemy.get_real_velocity().length(),
			enemy.global_position.distance_to(player.global_position),
			enemy.can_see(player.global_position),
		])


func _ready() -> void:
	var seconds := 60.0
	var dodge := false
	var weapon_name := ""
	var overrides := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			seconds = float(argument.trim_prefix("--seconds="))
		elif argument == "--bot=dodge":
			dodge = true
		elif argument.begins_with("--weapon="):
			weapon_name = argument.trim_prefix("--weapon=")
		elif argument.begins_with("--set="):
			var pair := argument.trim_prefix("--set=").split(":")
			if pair.size() == 2:
				overrides[pair[0]] = float(pair[1])

	var arena := ARENA.instantiate()
	arena.set(&"auto_start", false)
	add_child(arena)
	var player := (arena as Arena).local_player
	var director := arena.get_node(^"WaveDirector") as WaveDirector
	var station := arena.get_node(^"CraftingStation") as CraftingStation
	player.input.use_device = false
	for key: String in overrides:
		director.enemy_type.set(key, overrides[key])
	if weapon_name != "":
		player.unlock_weapon(load("res://weapons/data/%s.tres" % weapon_name) as WeaponData)

	var stats := {"hits": 0, "deaths": 0, "best_wave": 0, "affordable_at": -1.0, "last_kill": 0}
	var kills := {}
	var stall_reported := false
	player.hurtbox.hit_received.connect(func(_hit: HitInfo) -> void: stats.hits += 1)
	player.died.connect(func() -> void: stats.deaths += 1)
	director.wave_started.connect(func(number: int, _count: int) -> void:
		stats.best_wave = maxi(stats.best_wave, number)
	)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Enemy:
			(node as Enemy).died.connect(func(enemy: Enemy) -> void:
				var enemy_name := enemy.data.display_name
				kills[enemy_name] = kills.get(enemy_name, 0) + 1
				stats.last_kill = Engine.get_physics_frames()
			)
	)
	director.start()

	var ticks_per_second := Engine.physics_ticks_per_second
	stats.last_kill = Engine.get_physics_frames()
	for i in int(seconds * ticks_per_second):
		if dodge:
			TestBot.swing_and_dodge(player)
		else:
			TestBot.swing_only(player)
		await get_tree().physics_frame
		var quiet_ticks: int = Engine.get_physics_frames() - stats.last_kill
		if not stall_reported and quiet_ticks > STALL_SECONDS * ticks_per_second:
			stall_reported = true
			_report_stall(player, float(i) / ticks_per_second)
		if stats.affordable_at < 0.0:
			var recipe := station.get_next_recipe(player)
			if recipe != null and player.inventory.can_afford(recipe.costs):
				stats.affordable_at = float(i) / ticks_per_second

	var carried := PackedStringArray()
	for item in player.inventory.get_items():
		carried.append("%s %d" % [item.display_name, player.inventory.get_count(item)])
	var bot_name := "swing_and_dodge" if dodge else "swing_only"
	print("BOT PROBE (%s, %s, %.0f s, overrides %s)" % [
		bot_name, player.weapon.data.display_name, seconds, overrides,
	])
	print("  best wave reached    : %d" % stats.best_wave)
	print("  kills                : %s" % kills)
	print("  hits taken           : %d" % stats.hits)
	print("  deaths               : %d" % stats.deaths)
	print("  materials collected  : %s" % ", ".join(carried))
	if stats.affordable_at >= 0.0:
		print("  recipe affordable at : %.0f s" % stats.affordable_at)
	else:
		print("  recipe affordable at : never (or nothing left to craft)")
	get_tree().quit()
