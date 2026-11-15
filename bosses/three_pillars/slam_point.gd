class_name SlamPoint
extends Station
## The spot on the Warden where a carried bomb is slammed in: hold E within range while
## carrying a bomb. Like picking up, finishing the hold is only a request; the host checks
## that this player really carries a bomb and is close enough, and counts it exactly once.


func _ready() -> void:
	super()
	var encounter := _encounter()
	if encounter != null:
		hold_time = encounter.data.slam_hold
		var shape := $Range/CollisionShape2D.shape as CircleShape2D
		shape.radius = encounter.data.slam_range


func _encounter() -> BossEncounter:
	return get_tree().get_first_node_in_group(&"boss_encounter") as BossEncounter


func get_prompt(player: Player) -> String:
	return "Hold E to Slam Bomb" if can_interact(player) else ""


func can_interact(player: Player) -> bool:
	var encounter := _encounter()
	return encounter != null and encounter.is_mechanics_state() and encounter.get_carried_slot(player.peer_id) >= 0


func _complete(player: Player) -> void:
	var encounter := _encounter()
	if encounter != null:
		encounter.ask_slam(player)
