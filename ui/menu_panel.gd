class_name MenuPanel
extends CanvasLayer
## Base for the station menus (mission select, armory): a centred box on top of the game.
##
## While open, the player's input is blocked so clicks and keys do not move or attack.
## Esc or E closes it. Panels belong to the level, so travelling to another level closes
## them automatically. Subclasses build their contents in _build(box).

const FONT_SIZE := 8
const BOX_SIZE := Vector2(300.0, 210.0)

var player: Player

var _box: VBoxContainer
var _frame: PanelContainer


## Opens the panel for [param for_player] (this machine's player).
func open(for_player: Player) -> void:
	player = for_player
	player.input.blocked = true
	layer = 5
	add_to_group(&"open_panels")
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var frame := PanelContainer.new()
	frame.size = BOX_SIZE
	frame.position = (Vector2(480.0, 270.0) - BOX_SIZE) * 0.5
	add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	frame.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 3)
	margin.add_child(_box)
	_build(_box)
	var close_button := make_button("Close  [Esc]")
	close_button.pressed.connect(close)
	_box.add_child(close_button)
	# Fit the box to its contents (at least BOX_SIZE tall) and keep it centred on screen.
	_frame = frame
	_fit_frame.call_deferred()


func _fit_frame() -> void:
	if not is_instance_valid(_frame):
		return
	var screen := Vector2(480.0, 270.0)
	var height := clampf(_frame.get_combined_minimum_size().y, BOX_SIZE.y, screen.y - 6.0)
	_frame.size = Vector2(BOX_SIZE.x, height)
	_frame.position = (screen - _frame.size) * 0.5


func close() -> void:
	if is_instance_valid(player):
		player.input.blocked = false
	queue_free()


## Override: fill the panel.
func _build(_container: VBoxContainer) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		close()


func make_label(text: String, dim := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		label.modulate = Color(1.0, 1.0, 1.0, 0.6)
	return label


func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _exit_tree() -> void:
	if is_instance_valid(player):
		player.input.blocked = false
