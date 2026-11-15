class_name ArmoryPanel
extends MenuPanel
## The armory's menu: choose a character and which owned weapons go in the two slots.

var characters: Array[CharacterData] = []

var _slot_rows: Array[HBoxContainer] = []


func _build(box: VBoxContainer) -> void:
	box.add_child(make_label("ARMORY - character"))
	var character_row := HBoxContainer.new()
	var character_group := ButtonGroup.new()
	var any_locked := false
	for data in characters:
		var unlocked := player.owns_character(data)
		var button := make_button(data.display_name if unlocked else data.display_name + " (locked)")
		button.toggle_mode = true
		button.button_group = character_group
		button.modulate = data.color if unlocked else Color(0.6, 0.6, 0.6, 0.7)
		button.button_pressed = player.character == data
		button.disabled = not unlocked
		button.pressed.connect(choose_character.bind(data))
		character_row.add_child(button)
		any_locked = any_locked or not unlocked
	box.add_child(character_row)
	if any_locked:
		box.add_child(make_label("Locked characters are crafted at the Fabricator.", true))
	for slot in Player.LOADOUT_SLOTS:
		box.add_child(make_label("Weapon slot %d%s" % [slot + 1, "" if slot == 0 else " (optional)"]))
		var row := HBoxContainer.new()
		box.add_child(row)
		_slot_rows.append(row)
	_refresh_slots()


func choose_character(data: CharacterData) -> void:
	player.set_character(data)


## Puts [param weapon] in [param slot] (0-based). null empties the slot (slot 0 cannot be
## emptied). If the weapon is already in the other slot, the two slots swap.
func choose_slot(slot: int, weapon: WeaponData) -> void:
	var chosen: Array = player.loadout.duplicate()
	while chosen.size() < Player.LOADOUT_SLOTS:
		chosen.append(null)
	var previous: WeaponData = chosen[slot]
	for i in chosen.size():
		if i != slot and chosen[i] != null and weapon != null and chosen[i].id == weapon.id:
			chosen[i] = previous
	chosen[slot] = weapon
	if chosen[0] == null:
		# Slot 1 must always hold a weapon; ignore a change that would empty it.
		_refresh_slots()
		return
	var cleaned: Array[WeaponData] = []
	for data: WeaponData in chosen:
		if data != null:
			cleaned.append(data)
	player.set_loadout(cleaned)
	_refresh_slots()


func _refresh_slots() -> void:
	for slot in _slot_rows.size():
		var row := _slot_rows[slot]
		for child in row.get_children():
			child.queue_free()
		var current: WeaponData = player.loadout[slot] if slot < player.loadout.size() else null
		if slot > 0:
			var empty := make_button("Empty")
			empty.toggle_mode = true
			empty.button_pressed = current == null
			empty.pressed.connect(choose_slot.bind(slot, null))
			row.add_child(empty)
		for weapon in player.weapons:
			var button := make_button(weapon.display_name)
			button.toggle_mode = true
			button.button_pressed = current != null and current.id == weapon.id
			button.pressed.connect(choose_slot.bind(slot, weapon))
			row.add_child(button)
