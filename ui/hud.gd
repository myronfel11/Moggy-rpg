class_name Hud
extends CanvasLayer
## On-screen display: health, dash cooldown, wave, materials, crafting goal, weapon, and
## the prompt of whatever station the player is standing at.
##
## A CanvasLayer draws on top of the game and ignores the camera, so it stays fixed on
## screen. The HUD only listens to signals and reads values; it never changes gameplay.
##
## The goal line at the top is the important part for the game's loop: it always shows
## what the player is working toward and how far along they are, in the hub and on missions.

const READY_COLOR := Color(0.3, 1.0, 0.85)
const GAIN_COLOR := Color(1.0, 1.0, 0.4)
const GAIN_FLASH_TIME := 0.5
const TOAST_TIME := 2.2
const TOAST_FADE_TIME := 0.4

var _player: Player
var _book: RecipeBook
var _director: WaveDirector
var _health_width := 0.0
var _dash_width := 0.0
## One text label per material, created the first time that material is picked up.
var _inventory_rows: Dictionary[StringName, Label] = {}
var _toast_tween: Tween

@onready var _health_fill: ColorRect = $HealthBack/HealthFill
@onready var _dash_fill: ColorRect = $DashBack/DashFill
@onready var _inventory_list: VBoxContainer = $Inventory
@onready var _goal_label: Label = $GoalLabel
@onready var _wave_label: Label = $WaveLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _weapon_label: Label = $WeaponLabel
@onready var _toast_label: Label = $ToastLabel
@onready var _status_label: Label = $StatusLabel
@onready var _ability_bar: AbilityBar = $AbilityBar
@onready var _hold_back: ColorRect = $HoldBack
@onready var _hold_fill: ColorRect = $HoldBack/HoldFill


func _ready() -> void:
	# Remember the full bar widths as laid out in the scene.
	_health_width = _health_fill.size.x
	_dash_width = _dash_fill.size.x


## Connects the HUD to this machine's player, the recipe book for the goal line, and the
## level's wave director (null in the hub).
func bind(player: Player, book: RecipeBook, director: WaveDirector = null) -> void:
	_player = player
	_book = book
	_director = director
	player.health.changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	player.inventory.changed.connect(_on_inventory_changed)
	player.weapon_changed.connect(func(_data: WeaponData) -> void: _refresh_weapon())
	player.loadout_changed.connect(_refresh_weapon)
	player.weapon_unlocked.connect(_on_weapon_unlocked)
	player.character_unlocked.connect(func(data: CharacterData) -> void:
		_show_toast("UNLOCKED: %s\nChoose her at the Armory" % data.display_name.to_upper(), 3.0)
		_refresh_goal()
	)
	_wave_label.visible = director != null
	if director != null:
		director.wave_started.connect(_on_wave_started)
		if director.wave > 0:
			_on_wave_started(director.wave, 0)
	for item in player.inventory.get_items():
		_on_inventory_changed(item, player.inventory.get_count(item), 0)
	_on_health_changed(player.health.current, player.health.max_health)
	_refresh_weapon()
	_refresh_goal()
	_ability_bar.bind(player.abilities)
	player.character_changed.connect(func(_data: CharacterData) -> void: _ability_bar.rebuild.call_deferred())


## Shows a short message in the middle of the screen (teammate joined, crafted, ...).
## Text may span two lines. [param seconds] is how long it stays before fading.
func show_message(text: String, seconds := TOAST_TIME) -> void:
	_show_toast(text, seconds)


## The message currently on screen ("" when none). Used by tests.
func get_message() -> String:
	return _toast_label.text if _toast_label.visible and _toast_label.modulate.a > 0.0 else ""


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_dash_fill.size.x = _dash_width * _player.get_dash_ready_ratio()
	_refresh_prompt()


## Shows the prompt of the station the player is standing at, if any.
func _refresh_prompt() -> void:
	var prompt := ""
	var hold := 0.0
	var holdable := false
	for node in get_tree().get_nodes_in_group(&"stations"):
		var station := node as Station
		if station == null or not station.is_in_range(_player):
			continue
		var text := station.get_prompt(_player)
		if text == "":
			continue
		prompt = text
		holdable = station.hold_time > 0.0 and station.can_interact(_player)
		hold = station.get_hold_progress(_player)
		break
	_prompt_label.visible = prompt != ""
	_prompt_label.text = prompt
	_prompt_label.modulate = READY_COLOR if prompt.begins_with("[E]") or holdable else Color.WHITE
	# Hold-E progress bar under the prompt.
	_hold_back.visible = holdable
	_hold_fill.size.x = _hold_back.size.x * hold


## Updates the goal line: the next recipe and how far along the player is.
func _refresh_goal() -> void:
	if _player == null or _book == null:
		_goal_label.text = ""
		return
	var recipe := _book.get_next(_player)
	if recipe == null:
		_goal_label.text = "ALL GEAR CRAFTED"
		_goal_label.modulate = Color.WHITE
		return
	var progress := PackedStringArray()
	var all_ready := true
	for cost in recipe.costs:
		var have := _player.inventory.get_count(cost.item)
		progress.append("%s %d/%d" % [cost.item.display_name, mini(have, cost.amount), cost.amount])
		all_ready = all_ready and have >= cost.amount
	var weapon_name := recipe.get_result_name()
	if all_ready:
		_goal_label.text = "GOAL: %s   READY - craft at the Fabricator" % weapon_name
		_goal_label.modulate = READY_COLOR
	else:
		_goal_label.text = "GOAL: %s   %s" % [weapon_name, "   ".join(progress)]
		_goal_label.modulate = Color.WHITE


func _refresh_weapon() -> void:
	if _player == null or _player.weapon == null:
		_weapon_label.text = ""
		return
	var text := _player.weapon.data.display_name
	if _player.loadout.size() > 1:
		text += "   [Q] swap"
	_weapon_label.text = text


## Returns the label for a material, adding a new row (colour swatch plus text) if needed.
func _get_inventory_row(item: ItemData) -> Label:
	if _inventory_rows.has(item.id):
		return _inventory_rows[item.id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var swatch := ColorRect.new()
	swatch.color = item.color
	swatch.custom_minimum_size = Vector2(5.0, 5.0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", 8)
	row.add_child(swatch)
	row.add_child(label)
	_inventory_list.add_child(row)
	_inventory_rows[item.id] = label
	return label


func _show_toast(text: String, seconds := TOAST_TIME) -> void:
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_label.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, TOAST_FADE_TIME)


func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := current / maximum if maximum > 0.0 else 0.0
	_health_fill.size.x = _health_width * ratio


func _on_inventory_changed(item: ItemData, count: int, change: int) -> void:
	var label := _get_inventory_row(item)
	label.text = "%s  %d" % [item.display_name, count]
	if change > 0:
		# Brief highlight so a pickup is noticed without looking away from the fight.
		label.modulate = GAIN_COLOR
		label.create_tween().tween_property(label, "modulate", Color.WHITE, GAIN_FLASH_TIME)
	_refresh_goal()


func _on_weapon_unlocked(data: WeaponData) -> void:
	if _player.loadout.has(data):
		_show_toast("CRAFTED: %s" % data.display_name.to_upper())
	else:
		_show_toast("CRAFTED: %s - equip it at the Armory" % data.display_name.to_upper())
	_refresh_goal()


func _on_wave_started(number: int, _enemy_count: int) -> void:
	var final_wave := _director.get_final_wave() if _director != null else 0
	_wave_label.text = "WAVE %d/%d" % [number, final_wave] if final_wave > 0 else "WAVE %d" % number


func _on_player_died() -> void:
	_status_label.visible = true


func _on_player_respawned() -> void:
	_status_label.visible = false
