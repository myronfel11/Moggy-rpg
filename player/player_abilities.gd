class_name PlayerAbilities
extends Node2D
## A player's abilities (keys 1 to 3) and Zenith ultimate (key 4).
##
## Rebuilt whenever the player's character changes, from CharacterData.abilities and
## CharacterData.zenith. Abilities run on the owner's machine; other peers get a small
## network message so they can show the effect.
##
## Zenith charge is per player, kept here, and starts empty in every level.

signal zenith_charge_changed(charge: float)

const ZENITH_FULL := 100.0

var player: Player
## Ability behaviours for keys 1 to 3 (may be fewer).
var abilities: Array[AbilityBehavior] = []
## The Zenith behaviour, or null for characters without one.
var zenith: AbilityBehavior
var zenith_charge := 0.0


func setup(p_player: Player) -> void:
	player = p_player
	add_to_group(&"zenith_listeners")


## Builds the abilities for [param character].
func rebuild(character: CharacterData) -> void:
	for ability in abilities:
		ability.cancel()
		ability.queue_free()
	abilities.clear()
	if zenith != null:
		zenith.cancel()
		zenith.queue_free()
		zenith = null
	set_zenith_charge(0.0)
	if character == null:
		return
	for data in character.abilities:
		var ability := _create(data)
		if ability != null:
			abilities.append(ability)
	if character.zenith != null:
		zenith = _create(character.zenith)


func has_zenith() -> bool:
	return zenith != null


func is_zenith_ready() -> bool:
	return zenith != null and zenith_charge >= ZENITH_FULL and not zenith.is_active()


## Why Zenith cannot start right now, or "" if it can.
func get_zenith_block_reason() -> String:
	if zenith == null:
		return "No Zenith"
	if zenith.is_active():
		return ""
	if zenith_charge < ZENITH_FULL:
		return "Charging"
	var zenith_data := zenith.data as ZenithData
	if zenith_data != null and zenith_data.required_weapon != null and not player.carries_weapon(zenith_data.required_weapon):
		return "Equip %s to use Zenith" % zenith_data.required_weapon.display_name
	return ""


func set_zenith_charge(value: float) -> void:
	zenith_charge = clampf(value, 0.0, ZENITH_FULL)
	if player != null and player.is_local():
		player.set_flag(Player.FLAG_ZENITH_READY, is_zenith_ready())
	zenith_charge_changed.emit(zenith_charge)


## Called on every peer when an enemy dies (through the "zenith_listeners" group).
## Only this machine's own player gains charge: full for a kill made with the Zenith's
## charging weapon, and the shares set in ZenithData for other kills (own or a teammate's).
func on_enemy_killed(value: float, killer_peer: int, weapon_id: StringName) -> void:
	if player == null or not player.is_local() or zenith == null or zenith.is_active():
		return
	var zenith_data := zenith.data as ZenithData
	var share := 1.0
	if zenith_data != null:
		if killer_peer != player.peer_id:
			share = zenith_data.team_kill_share
			if zenith_data.team_kill_needs_weapon_in_hand and not _holds(zenith_data.charge_weapon):
				share = 0.0
		elif zenith_data.charge_weapon != null and weapon_id != zenith_data.charge_weapon.id:
			share = zenith_data.other_weapon_share
	if share > 0.0:
		set_zenith_charge(zenith_charge + value * share)


## A short hint while Zenith is charging and this player cannot charge it the way they are
## set up right now, or "".
func get_zenith_charge_hint() -> String:
	if zenith == null or zenith.is_active() or zenith_charge >= ZENITH_FULL:
		return ""
	var zenith_data := zenith.data as ZenithData
	if zenith_data == null or zenith_data.charge_weapon == null or zenith_data.other_weapon_share > 0.0:
		return ""
	var needed := zenith_data.charge_weapon
	if not player.carries_weapon(needed):
		return "Equip %s at the Armory to charge Zenith" % needed.display_name
	if not _holds(needed):
		return "Hold %s to charge Zenith [Q]" % needed.display_name
	return ""


## True if [param data] is the weapon in hand (or no particular weapon is needed).
func _holds(data: WeaponData) -> bool:
	if data == null:
		return true
	return player.weapon != null and player.weapon.data.id == data.id


## Owner only, every physics frame.
func tick(delta: float) -> void:
	if not player.is_alive():
		return
	for i in abilities.size():
		if player.input.take_ability(i):
			_try_activate(i)
	if zenith != null and player.input.take_ability(3):
		_try_activate(3)
	for ability in abilities:
		ability.tick(delta)
	if zenith != null:
		zenith.tick(delta)
		player.set_flag(Player.FLAG_ZENITH_READY, is_zenith_ready())


## Starts ability [param slot] (0 to 2, or 3 for Zenith). Returns true if it started.
func use(slot: int) -> bool:
	return _try_activate(slot)


func get_ability(slot: int) -> AbilityBehavior:
	if slot == 3:
		return zenith
	return abilities[slot] if slot < abilities.size() else null


## The player attacked (some effects end on attack).
func notify_attacked() -> void:
	for ability in abilities:
		ability.notify_attacked()


## Ends every effect at once (death, character change). Cooldowns are kept.
func cancel_all() -> void:
	for ability in abilities:
		ability.cancel()
	if zenith != null:
		zenith.cancel()


func _try_activate(slot: int) -> bool:
	var ability := get_ability(slot)
	if ability == null:
		return false
	if slot == 3:
		if get_zenith_block_reason() != "" or zenith.is_active():
			return false
		set_zenith_charge(0.0)
		zenith._cooldown_left = 0.0
	if not ability.activate():
		return false
	_net_ability.rpc(slot, true)
	return true


## Lets other peers show an ability's effect on this player.
@rpc("authority", "call_remote", "reliable")
func _net_ability(slot: int, started: bool) -> void:
	var ability := get_ability(slot)
	if ability != null:
		ability.show_remote(started)


## Called by abilities when their effect ends, so other peers can stop showing it.
func announce_end(ability: AbilityBehavior) -> void:
	if player == null or not player.is_local():
		return
	var slot := abilities.find(ability)
	if ability == zenith:
		slot = 3
	if slot >= 0:
		_net_ability.rpc(slot, false)


func _create(data: AbilityData) -> AbilityBehavior:
	if data == null or data.behavior_scene == null:
		return null
	var ability := data.behavior_scene.instantiate() as AbilityBehavior
	add_child(ability)
	ability.setup(data, player)
	return ability
