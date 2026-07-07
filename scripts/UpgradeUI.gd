extends Control
class_name UpgradeUI

signal card_selected(card_id: String)
signal attack_pressed
signal health_pressed
signal effect_pressed
signal remove_effect_pressed(effect_source: String, effect_index: int)

const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@onready var balance_label: Label = $Panel/MarginContainer/VBoxContainer/BalanceLabel
@onready var card_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/CardScroll/CardList
@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/InfoLabel
@onready var attack_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/AttackButton
@onready var health_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/HealthButton
@onready var effect_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/EffectButton
@onready var message_label: Label = $Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var panel: Panel = $Panel

const EFFECT_ICON_PATH := "res://assets/effects/"
const EFFECT_PLACEHOLDER := "res://assets/effects/placeholder.png"

@onready var effect_option: OptionButton = get_node_or_null("Panel/MarginContainer/VBoxContainer/EffectOption") as OptionButton
@onready var remove_effect_button: Button = get_node_or_null("Panel/MarginContainer/VBoxContainer/ButtonRow/RemoveButton") as Button
@onready var effect_icon_row: HBoxContainer = get_node_or_null("Panel/MarginContainer/VBoxContainer/EffectIconRow") as HBoxContainer

var effect_icon_buttons: Array[Button] = []

var selected_card_id := ""
var card_buttons: Array[Button] = []
var message_tween: Tween = null
var effect_entries: Array[Dictionary] = []
var selected_effect_entry_index := -1

var pending_remove_effect_index := -1
var normal_effect_icons: Dictionary = {}


func _ready() -> void:
	add_to_group("upgrade_ui")
	
	if remove_effect_button != null:
		remove_effect_button.visible = false

	if effect_option != null:
		effect_option.visible = false

	_ensure_effect_icon_row()
	_refresh_effect_icons("")

	attack_button.pressed.connect(func(): attack_pressed.emit())
	health_button.pressed.connect(func(): health_pressed.emit())
	effect_button.pressed.connect(func(): effect_pressed.emit())
	if remove_effect_button != null:
		remove_effect_button.pressed.connect(_on_remove_effect_button_pressed)
	panel.gui_input.connect(_on_panel_gui_input)

	if CardUpgradeManager.has_signal("upgrades_changed"):
		var callback := Callable(self, "_on_upgrades_changed")
		if not CardUpgradeManager.is_connected("upgrades_changed", callback):
			CardUpgradeManager.connect("upgrades_changed", callback)

	if GameCurrency.has_signal("coins_changed"):
		var coins_callback := Callable(self, "_on_coins_changed")
		if not GameCurrency.is_connected("coins_changed", coins_callback):
			GameCurrency.connect("coins_changed", coins_callback)

	_set_upgrade_buttons_disabled(true)
	refresh_balance()
	show_message("")

func set_cards(card_ids: Array) -> void:
	for child in card_list.get_children():
		child.queue_free()

	card_buttons.clear()
	selected_card_id = ""

	var entries: Array = []

	for card_id_raw in card_ids:
		var card_id := str(card_id_raw)
		var data := CardDatabase.get_card(card_id)

		if data.is_empty():
			continue

		var rarity := str(data.get("rarity", "common"))

		entries.append({
			"id": card_id,
			"data": data,
			"rarity": rarity,
			"rank": RarityEffectsData.rarity_rank(rarity)
		})

	entries.sort_custom(func(a, b):
		if a.rank == b.rank:
			return String(a.data.get("name", "")).nocasecmp_to(String(b.data.get("name", ""))) < 0

		return a.rank > b.rank
	)

	for entry in entries:
		var button := Button.new()
		button.text = str(entry.data.get("name", entry.id))
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(_on_card_button_pressed.bind(entry.id, button))

		_style_card_button(button, entry.rarity)

		card_list.add_child(button)
		card_buttons.append(button)

	_set_upgrade_buttons_disabled(true)
	info_label.text = "SELECT CARD"
	
func _on_card_button_pressed(card_id: String, button: Button) -> void:
	selected_card_id = card_id

	for b in card_buttons:
		b.button_pressed = b == button

	card_selected.emit(card_id)
	_update_upgrade_button_state()


func set_selected_card(card_id: String) -> void:
	selected_card_id = card_id

	var data := CardDatabase.get_card(card_id)

	if data.is_empty():
		info_label.text = "UNKNOWN CARD"
		_refresh_effect_icons("")
		return

	var upgraded := CardUpgradeManager.apply_upgrades(card_id, data)

	var name := str(upgraded.get("name", card_id))
	var attack := int(upgraded.get("attack", 0))
	var hp := int(upgraded.get("defense", 0))

	_refresh_effect_icons(card_id)

	var effects_text := "None"

	if not effect_entries.is_empty():
		var names: Array[String] = []

		for entry in effect_entries:
			var source := str(entry.get("source", ""))
			var effect: Dictionary = entry.get("effect", {})

			var prefix := "BASE" if source == "base" else "UPG"
			var effect_name := _format_effect_name(effect)

			names.append("%s:%s" % [prefix, effect_name])

		effects_text = ", ".join(names)

	info_label.text = "%s\nATK: %d   HP: %d\nEFFECTS: %s" % [
		name,
		attack,
		hp,
		effects_text
	]

	_update_upgrade_button_state()

func refresh_balance() -> void:
	balance_label.text = "SOUL COINS: " + str(GameCurrency.coins)


func show_message(text: String) -> void:
	if message_label == null:
		return

	if message_tween:
		message_tween.kill()
		message_tween = null

	if text == "":
		message_label.visible = false
		return

	message_label.text = text
	message_label.visible = true
	message_label.modulate.a = 1.0

	message_tween = create_tween()
	message_tween.tween_interval(1.2)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.25)
	message_tween.tween_callback(func():
		if message_label:
			message_label.visible = false
	)


func _set_upgrade_buttons_disabled(disabled: bool) -> void:
	attack_button.disabled = disabled
	health_button.disabled = disabled
	effect_button.disabled = disabled
	if remove_effect_button != null:
		remove_effect_button.disabled = disabled

	if effect_option != null:
		effect_option.disabled = disabled


func _style_card_button(button: Button, rarity: String) -> void:
	button.add_theme_font_override("font", VCR_FONT)
	button.add_theme_font_size_override("font_size", 25)

	var rarity_color := _get_rarity_color(rarity)
	var bg := rarity_color.darkened(0.55)
	var border := rarity_color
	var hover_bg := rarity_color.darkened(0.35)
	var pressed_bg := rarity_color.darkened(0.18)
	var font_color := rarity_color.lightened(0.45)

	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = border
	normal.corner_radius_top_left = 5
	normal.corner_radius_top_right = 5
	normal.corner_radius_bottom_left = 5
	normal.corner_radius_bottom_right = 5

	var hover := StyleBoxFlat.new()
	hover.bg_color = hover_bg
	hover.border_width_left = 2
	hover.border_width_top = 2
	hover.border_width_right = 2
	hover.border_width_bottom = 2
	hover.border_color = border.lightened(0.35)
	hover.corner_radius_top_left = 5
	hover.corner_radius_top_right = 5
	hover.corner_radius_bottom_left = 5
	hover.corner_radius_bottom_right = 5

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = pressed_bg
	pressed.border_width_left = 3
	pressed.border_width_top = 3
	pressed.border_width_right = 3
	pressed.border_width_bottom = 3
	pressed.border_color = Color.WHITE
	pressed.corner_radius_top_left = 5
	pressed.corner_radius_top_right = 5
	pressed.corner_radius_bottom_left = 5
	pressed.corner_radius_bottom_right = 5

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	

func _get_rarity_color(rarity: String) -> Color:
	return RarityEffectsData.get_color(rarity)
	
func _on_upgrades_changed(card_id: String) -> void:
	refresh_balance()

	if selected_card_id == card_id:
		call_deferred("set_selected_card", card_id)


func _on_coins_changed(_coins: int) -> void:
	refresh_balance()
		
func _update_upgrade_button_state() -> void:
	if selected_card_id == "":
		_set_upgrade_buttons_disabled(true)
		return

	attack_button.disabled = false
	health_button.disabled = false

	effect_button.disabled = CardUpgradeManager.get_free_effect_slots(selected_card_id) <= 0
	remove_effect_button.disabled = CardUpgradeManager.get_effect_entries(selected_card_id).is_empty()

	if effect_option != null:
		effect_option.disabled = CardUpgradeManager.get_effect_entries(selected_card_id).is_empty()

#func _refresh_effect_option(card_id: String) -> void:
	#effect_entries.clear()
#
	#if effect_option == null:
		#return
#
	#effect_option.clear()
#
	#if card_id == "":
		#effect_option.add_item("NO CARD SELECTED")
		#effect_option.disabled = true
		#return
#
	#effect_entries = CardUpgradeManager.get_effect_entries(card_id)
#
	#if effect_entries.is_empty():
		#effect_option.add_item("NO EFFECTS")
		#effect_option.disabled = true
		#return
#
	#for entry in effect_entries:
		#var source := str(entry.get("source", ""))
		#var effect: Dictionary = entry.get("effect", {})
#
		#var prefix := "BASE" if source == "base" else "UPGRADE"
		#var effect_name := _format_effect_name(effect)
#
		#effect_option.add_item("%s: %s" % [prefix, effect_name])
#
	#effect_option.selected = 0
	#effect_option.disabled = false
	#
	
func _on_remove_effect_button_pressed() -> void:
	if selected_card_id == "":
		return

	if selected_effect_entry_index < 0 or selected_effect_entry_index >= effect_entries.size():
		return

	var entry := effect_entries[selected_effect_entry_index]
	var source := str(entry.get("source", ""))
	var effect_index := int(entry.get("index", -1))

	if source == "" or effect_index < 0:
		return

	remove_effect_pressed.emit(source, effect_index)
	
func _format_effect_name(effect: Dictionary) -> String:
	var label := str(effect.get("name", effect.get("type", "Effect")))

	label = label.replace("_", " ").capitalize()

	if effect.has("percent"):
		label += " %d%%" % int(round(float(effect.get("percent", 0.0)) * 100.0))
	elif effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			label += " %d%%" % int(round(value * 100.0))
		else:
			label += " +%d" % int(round(value))
	elif effect.has("damage") and effect.has("turns"):
		label += " %d/%dT" % [
			int(effect.get("damage", 0)),
			int(effect.get("turns", 0))
		]

	return label

func _ensure_effect_icon_row() -> void:
	if effect_icon_row != null:
		return

	effect_icon_row = HBoxContainer.new()
	effect_icon_row.name = "EffectIconRow"
	effect_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	effect_icon_row.add_theme_constant_override("separation", 10)

	var parent := info_label.get_parent()
	parent.add_child(effect_icon_row)
	parent.move_child(effect_icon_row, info_label.get_index() + 1)


func _refresh_effect_icons(card_id: String) -> void:
	pending_remove_effect_index = -1
	selected_effect_entry_index = -1
	effect_entries.clear()
	effect_icon_buttons.clear()

	if remove_effect_button != null:
		remove_effect_button.disabled = true

	_ensure_effect_icon_row()

	for child in effect_icon_row.get_children():
		child.queue_free()

	if card_id == "":
		return

	effect_entries = CardUpgradeManager.get_effect_entries(card_id)

	if effect_entries.is_empty():
		return

	for i in range(min(effect_entries.size(), 2)):
		var entry := effect_entries[i]
		var effect: Dictionary = entry.get("effect", {})

		var button := Button.new()
		button.custom_minimum_size = Vector2(54, 54)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.tooltip_text = _format_effect_name(effect)
		button.icon = _load_effect_icon(effect)
		button.expand_icon = true

		button.pressed.connect(_on_effect_icon_pressed.bind(i, button))

		_style_effect_icon_button(button)

		effect_icon_row.add_child(button)
		effect_icon_buttons.append(button)

func _load_effect_icon(effect: Dictionary) -> Texture2D:
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()

	if effect_type == "":
		return load(EFFECT_PLACEHOLDER) as Texture2D

	var file_name := effect_type

	if effect_type == "armor":
		var value := float(effect.get("value", 0.0))

		if is_equal_approx(value, 0.25):
			file_name = "armor_25"
		elif is_equal_approx(value, 0.5):
			file_name = "armor_50"
		elif is_equal_approx(value, 0.75):
			file_name = "armor_75"

	var path := EFFECT_ICON_PATH + file_name + ".png"

	if ResourceLoader.exists(path):
		return load(path) as Texture2D

	return load(EFFECT_PLACEHOLDER) as Texture2D


func _style_effect_icon_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.05, 0.06, 0.95)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.55, 0.2, 0.2, 1.0)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.07, 0.07, 1.0)
	hover.border_color = Color.WHITE

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.35, 0.08, 0.08, 1.0)
	pressed.border_color = Color.WHITE

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_effect_icon_selected(entry_index: int, button: Button) -> void:
	selected_effect_entry_index = entry_index

	for b in effect_icon_buttons:
		b.button_pressed = b == button

	if remove_effect_button != null:
		remove_effect_button.disabled = false
		
func _on_effect_icon_pressed(entry_index: int, button: Button) -> void:
	get_viewport().set_input_as_handled()

	if pending_remove_effect_index == entry_index:
		_confirm_remove_effect(entry_index)
		return

	clear_pending_remove_effect()

	pending_remove_effect_index = entry_index

	for b in effect_icon_buttons:
		b.button_pressed = b == button

	button.text = "X"
	button.add_theme_color_override("font_color", Color.RED)
	button.add_theme_font_size_override("font_size", 34)
	
func _confirm_remove_effect(entry_index: int) -> void:
	if selected_card_id == "":
		return

	if entry_index < 0 or entry_index >= effect_entries.size():
		return

	var entry := effect_entries[entry_index]

	var source := str(entry.get("source", ""))
	var effect_index := int(entry.get("index", -1))

	if source == "" or effect_index < 0:
		return

	pending_remove_effect_index = -1
	remove_effect_pressed.emit(source, effect_index)
	
func clear_pending_remove_effect() -> void:
	pending_remove_effect_index = -1

	for button in effect_icon_buttons:
		button.button_pressed = false
		button.text = ""
		button.remove_theme_color_override("font_color")
		button.remove_theme_font_size_override("font_size")
		

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clear_pending_remove_effect()
