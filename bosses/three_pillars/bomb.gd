class_name Bomb
extends Station
## A bomb dropped by a defeated sentinel. Hold E to pick it up, carry it to the Warden and
## hold E there to slam it in (SlamPoint). Weapons cannot touch it (it has no hurtbox).
##
## The host owns it: who carries it (carrier_peer) and where it lies are synced. Picking it
## up is only a request; the host gives it to the first valid one, so two players finishing
## the hold together cannot both get it. While carried it rides above the carrier on every
## screen, and the carrier's own machine slows them a little.

const CARRY_SPEED_KEY := &"carrying_bomb"

## Which sentinel dropped it (0 to 2). Set through spawn props.
var slot := 0
## Synced: the network peer carrying it, 0 when it lies on the ground.
var carrier_peer := 0

var _time := 0.0


func _ready() -> void:
	super()
	add_to_group(&"bombs")
	var encounter := _encounter()
	hold_time = encounter.data.pickup_hold if encounter != null else 1.0


func _encounter() -> BossEncounter:
	return get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter


func get_prompt(player: Player) -> String:
	if carrier_peer != 0:
		return ""
	var encounter := _encounter()
	if encounter != null and encounter.get_carried_slot(player.peer_id) >= 0:
		return "You are already carrying a bomb"
	return "Hold E to Pick Up Bomb"


func can_interact(player: Player) -> bool:
	var encounter := _encounter()
	return carrier_peer == 0 and encounter != null and encounter.get_carried_slot(player.peer_id) < 0


func _complete(player: Player) -> void:
	var encounter := _encounter()
	if encounter != null:
		encounter.ask_pickup(slot, player)


func _process(delta: float) -> void:
	_time += delta
	var level := get_level()
	if carrier_peer != 0 and level != null:
		var carrier := level.get_player_by_peer(carrier_peer)
		if carrier != null:
			global_position = carrier.global_position + Vector2(0.0, -15.0)
	# The carrier's own machine applies the carrying slow-down.
	if level != null and level.local_player != null and is_instance_valid(level.local_player):
		var mine := carrier_peer == level.local_player.peer_id
		if mine:
			var encounter := _encounter()
			level.local_player.set_speed_multiplier(CARRY_SPEED_KEY, encounter.data.carry_speed if encounter != null else 0.85)
		elif _was_mine:
			level.local_player.clear_speed_multiplier(CARRY_SPEED_KEY)
		_was_mine = mine
	queue_redraw()


var _was_mine := false


func _exit_tree() -> void:
	if not _was_mine:
		return
	var level := get_level()
	if level != null and level.local_player != null and is_instance_valid(level.local_player):
		level.local_player.clear_speed_multiplier(CARRY_SPEED_KEY)


func _draw() -> void:
	var encounter := _encounter()
	var color: Color = encounter.data.slot_colors[slot] if encounter != null else Color.WHITE
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	if carrier_peer == 0:
		# On the ground: a beacon ring so it can be found in a busy fight.
		draw_arc(Vector2.ZERO, 12.0 + 4.0 * pulse, 0.0, TAU, 24, Color(color, 0.5 * (1.0 - pulse)), 1.5)
	draw_circle(Vector2.ZERO, 6.0, Color(0.12, 0.1, 0.16))
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 20, color, 2.0)
	draw_circle(Vector2.ZERO, 2.5, Color(color, 0.6 + 0.4 * pulse))
	draw_line(Vector2(3.0, -5.0), Vector2(6.0, -9.0), Color(1.0, 0.9, 0.6), 1.0)
