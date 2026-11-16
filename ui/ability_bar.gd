class_name AbilityBar
extends Control
## HUD strip for abilities: one box per ability (key number, name, cooldown sweep) and the
## Zenith bar (charge, "READY [4]", or the time left while active). Hidden for characters
## with no abilities. Only reads from PlayerAbilities; never changes anything.

const BOX_SIZE := Vector2(30.0, 14.0)
const ZENITH_WIDTH := 84.0
const FONT_SIZE := 8

var _abilities: PlayerAbilities
var _boxes: Array[Dictionary] = []
var _zenith_fill: ColorRect
var _zenith_back: ColorRect
var _zenith_label: Label
## Above the Zenith bar: how to charge it, when the current setup cannot.
var _zenith_hint: Label
var _time := 0.0


## Shows the abilities of [param abilities] (call again after a character change).
func bind(abilities: PlayerAbilities) -> void:
	_abilities = abilities
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_boxes.clear()
	_zenith_fill = null
	if _abilities == null:
		return
	var x := 0.0
	for i in _abilities.abilities.size():
		var ability := _abilities.abilities[i]
		var back := ColorRect.new()
		back.position = Vector2(x, 0.0)
		back.size = BOX_SIZE
		back.color = Color(0.03, 0.03, 0.07, 0.85)
		add_child(back)
		var fill := ColorRect.new()
		fill.size = BOX_SIZE
		fill.color = Color(ability.data.color, 0.35)
		back.add_child(fill)
		var label := _label("%d %s" % [i + 1, ability.data.display_name])
		label.position = Vector2(2.0, 0.0)
		label.size = BOX_SIZE
		back.add_child(label)
		_boxes.append({"ability": ability, "fill": fill, "label": label})
		x += BOX_SIZE.x + 3.0
	if _abilities.zenith != null:
		_zenith_back = ColorRect.new()
		_zenith_back.position = Vector2(x + 6.0, 6.0)
		_zenith_back.size = Vector2(ZENITH_WIDTH, 5.0)
		_zenith_back.color = Color(0.03, 0.03, 0.07, 0.85)
		add_child(_zenith_back)
		_zenith_fill = ColorRect.new()
		_zenith_fill.size = Vector2(0.0, 5.0)
		_zenith_fill.color = _abilities.zenith.data.color
		_zenith_back.add_child(_zenith_fill)
		_zenith_label = _label("ZENITH")
		_zenith_label.position = Vector2(x + 6.0, -9.0)
		add_child(_zenith_label)
		_zenith_hint = _label("")
		_zenith_hint.position = Vector2(x + 6.0, -19.0)
		_zenith_hint.modulate = Color(1.0, 0.75, 0.4)
		# Outline keeps it readable over the arena and over centre-screen messages.
		_zenith_hint.add_theme_constant_override(&"outline_size", 4)
		_zenith_hint.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		add_child(_zenith_hint)
	visible = not _boxes.is_empty() or _abilities.zenith != null


func _process(delta: float) -> void:
	_time += delta
	if _abilities == null or not is_instance_valid(_abilities):
		return
	for box in _boxes:
		var ability: AbilityBehavior = box.ability
		var fill: ColorRect = box.fill
		var label: Label = box.label
		if ability.is_active():
			fill.size.x = BOX_SIZE.x
			fill.color.a = 0.75
		else:
			fill.size.x = BOX_SIZE.x * ability.get_ready_ratio()
			fill.color.a = 0.45 if ability.get_ready_ratio() >= 1.0 else 0.2
		label.modulate.a = 1.0 if ability.get_ready_ratio() >= 1.0 or ability.is_active() else 0.5
	if _zenith_fill == null:
		return
	var zenith := _abilities.zenith
	_zenith_hint.text = _abilities.get_zenith_charge_hint()
	_zenith_hint.visible = _zenith_hint.text != ""
	if zenith.is_active():
		var left := zenith.get_active_left()
		_zenith_fill.size.x = ZENITH_WIDTH * clampf(left / maxf(zenith.data.duration, 0.01), 0.0, 1.0)
		_zenith_label.text = "ZENITH  %.1fs" % left
		_zenith_label.modulate = Color.WHITE
		return
	_zenith_fill.size.x = ZENITH_WIDTH * _abilities.zenith_charge / PlayerAbilities.ZENITH_FULL
	var reason := _abilities.get_zenith_block_reason()
	if reason == "":
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		_zenith_label.text = "ZENITH READY [4]"
		_zenith_label.modulate = Color(zenith.data.color, pulse + 0.2)
	elif reason == "Charging":
		_zenith_label.text = "ZENITH  %d%%" % int(_abilities.zenith_charge)
		_zenith_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	else:
		_zenith_label.text = reason
		_zenith_label.modulate = Color(1.0, 0.6, 0.6)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
