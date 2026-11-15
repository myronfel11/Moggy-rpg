class_name Invisibility
extends AbilityBehavior
## Ability: become nearly invisible for a few seconds.
##
## Sets the player's INVISIBLE flag. Enemies never pick an invisible player as a new
## target (Enemy.find_target uses Player.is_targetable), so they lose track of her; an
## attack already winding up still finishes toward where she was. The flag is synced, so
## the host's enemies see it for a teammate too. Attacking ends it early when the ability
## data says so (breaks_on_attack).


func _on_activate() -> void:
	player.set_flag(Player.FLAG_INVISIBLE, true)
	player.visual.flash(0.25, data.color)


func _on_end() -> void:
	player.set_flag(Player.FLAG_INVISIBLE, false)
	player.visual.flash(0.2, data.color)


func show_remote(_started: bool) -> void:
	player.visual.flash(0.2, data.color)
