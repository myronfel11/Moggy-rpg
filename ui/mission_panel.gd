class_name MissionPanel
extends MenuPanel
## The navigation console's menu: pick a mission and (host only) start it for everyone.

var hub: Hub
var missions: Array[MissionData] = []
var selected: MissionData

var _list: VBoxContainer
var _details: Label
var _start: Button


func _build(box: VBoxContainer) -> void:
	box.add_child(make_label("NAVIGATION - choose a mission"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 2)
	box.add_child(_list)
	var group := ButtonGroup.new()
	var profile := hub.get_profile()
	for mission in missions:
		var done := " (cleared)" if profile.has_completed(mission.resource_path) else ""
		var button := make_button(mission.display_name + done)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(select.bind(mission))
		_list.add_child(button)
	_details = make_label("", true)
	_details.custom_minimum_size = Vector2(0.0, 48.0)
	box.add_child(_details)
	_start = make_button("Start mission")
	_start.pressed.connect(start)
	box.add_child(_start)
	if not multiplayer.is_server():
		_start.disabled = true
		box.add_child(make_label("Only the host can start a mission.", true))
	if not missions.is_empty():
		(_list.get_child(0) as Button).button_pressed = true
		select(missions[0])


func select(mission: MissionData) -> void:
	selected = mission
	var length := "%d waves" % mission.waves_to_clear if mission.waves_to_clear > 0 else "Endless"
	_details.text = "%s\n%s" % [length, mission.description]


## Starts the selected mission for everyone. Host only.
func start() -> void:
	if selected == null or not multiplayer.is_server():
		return
	hub.start_mission(selected)
	close()
