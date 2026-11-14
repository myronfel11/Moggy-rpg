class_name Hud
extends CanvasLayer
## On-screen display: health, dash cooldown, wave, materials, crafting goal, weapon.
##
## A CanvasLayer draws on top of the game and ignores the camera, so it stays fixed on
## screen. The HUD only listens to signals and reads values; it never changes gameplay.
##
## The goal line at the top is the important part for the game's loop: it always shows
## what the player is working toward and how far along they are.

const READY_COLOR := Color(0.3, 1.0, 0.85)
const GAIN_COLOR := Color(1.0, 1.0, 0.4)
const GAIN_FLASH_TIME := 0.5
const TOAST_TIME := 2.2
const TOAST_FADE_TIME := 0.4

var _player: Player
var _station: CraftingStation
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


func _ready() -> void:
	# Remember the full bar widths as laid out in the scene.
	_health_width = _health_fill.size.x
	_dash_width = _dash_fill.size.x


## Connects the HUD to the player, wave director and crafting station it should display.
func bind(player: Player, director: WaveDirector, station: CraftingStation) -> void:
	_player = player
	_station = station
	player.health.changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	player.inventory.changed.connect(_on_inventory_changed)
	player.weapon_changed.connect(_on_weapon_changed)
	director.wave_started.connect(_on_wave_started)
	station.player_entered.connect(_on_station_presence_changed)
	station.player_exited.connect(_on_station_presence_changed)
	station.crafted.connect(_on_crafted)
	_on_health_changed(player.health.current, player.health.max_health)
	_refresh_weapon()
	_refresh_crafting()


func _process(_delta: float) -> void:
	if _player != null:
		_dash_fill.size.x = _dash_width * _player.get_dash_ready_ratio()


## Updates the goal line and the prompt shown while standing at the station.
func _refresh_crafting() -> void:
	if _player == null or _station == null:
		return
	_prompt_label.visible = _station.is_in_range(_player)
	var recipe := _station.get_next_recipe(_player)
	if recipe == null:
		_goal_label.text = "ALL GEAR CRAFTED"
		_goal_label.modulate = Color.WHITE
		_prompt_label.text = "Nothing left to craft"
		_prompt_label.modulate = Color.WHITE
		return
	var progress := PackedStringArray()
	var missing := PackedStringArray()
	for cost in recipe.costs:
		var have := _player.inventory.get_count(cost.item)
		var item_name := cost.item.display_name
		progress.append("%s %d/%d" % [item_name, mini(have, cost.amount), cost.amount])
		if have < cost.amount:
			missing.append("%d %s" % [cost.amount - have, item_name])
	var weapon_name := recipe.result.display_name
	if missing.is_empty():
		_goal_label.text = "GOAL: %s   READY - craft at the Fabricator" % weapon_name
		_goal_label.modulate = READY_COLOR
		_prompt_label.text = "[E] Craft %s" % weapon_name
		_prompt_label.modulate = READY_COLOR
	else:
		_goal_label.text = "GOAL: %s   %s" % [weapon_name, "   ".join(progress)]
		_goal_label.modulate = Color.WHITE
		_prompt_label.text = "%s needs %s more" % [weapon_name, " and ".join(missing)]
		_prompt_label.modulate = Color.WHITE


func _refresh_weapon() -> void:
	if _player == null or _player.weapon == null:
		_weapon_label.text = ""
		return
	var text := _player.weapon.data.display_name
	if _player.weapons.size() > 1:
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


func _show_toast(text: String) -> void:
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_label.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_TIME)
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
	_refresh_crafting()


func _on_weapon_changed(_data: WeaponData) -> void:
	_refresh_weapon()


func _on_station_presence_changed(player: Player) -> void:
	if player == _player:
		_refresh_crafting()


func _on_crafted(player: Player, recipe: Recipe) -> void:
	if player != _player:
		return
	_show_toast("CRAFTED: %s" % recipe.result.display_name.to_upper())
	_refresh_weapon()
	_refresh_crafting()


func _on_wave_started(number: int, _enemy_count: int) -> void:
	_wave_label.text = "WAVE %d" % number


func _on_player_died() -> void:
	_status_label.visible = true


func _on_player_respawned() -> void:
	_status_label.visible = false
