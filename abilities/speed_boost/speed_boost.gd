class_name SpeedBoost
extends AbilityBehavior
## Ability: a burst of movement speed for a few seconds, running or skating.
##
## Uses the player's named speed multiplier, so using it again (or another effect with the
## same name) replaces rather than stacks, and ending it always restores normal speed.

## Movement speed multiplier while active. 1.6 is 60% faster.
@export var speed_multiplier := 1.6

const KEY := &"speed_boost"


func _on_activate() -> void:
	player.set_speed_multiplier(KEY, speed_multiplier)
	player.set_flag(Player.FLAG_BOOSTED, true)
	player.visual.flash(0.15, data.color)


func _on_end() -> void:
	player.clear_speed_multiplier(KEY)
	player.set_flag(Player.FLAG_BOOSTED, false)


func show_remote(started: bool) -> void:
	if started:
		player.visual.flash(0.15, data.color)
