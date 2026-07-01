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

@onready var effect_option: OptionButton = $Panel/MarginContainer/VBoxContainer/EffectOption
@onready var remove_effect_button: Button =$Panel/MarginContainer/VBoxContainer/ButtonRow/RemoveButton

var selected_card_id := ""
var card_buttons: Array[Button] = []
var message_tween: Tween = null
var effect_entries: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("upgrade_ui")

	attack_button.pressed.connect(func(): attack_pressed.emit())
	health_button.pressed.connect(func(): health_pressed.emit())
	effect_button.pressed.connect(func(): effect_pressed.emit())
	remove_effect_button.pressed.connect(_on_remove_effect_button_pressed)

	if CardUpgradeManager.has_signal("upgrades_changed"):
		var callback := Callable(self, "_on_upgrades_changed")
		if not CardUpgradeManager.is_connected("upgrades_changed", callback):
			CardUpgradeManager.connect("upgrades_changed", callback)

	_set_upgrade_buttons_disabled(true)
	refresh_balance()
	show_message("")
	_refresh_effect_option("")

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
		_refresh_effect_option("")
		return

	var upgraded := CardUpgradeManager.apply_upgrades(card_id, data)

	var name := str(upgraded.get("name", card_id))
	var attack := int(upgraded.get("attack", 0))
	var hp := int(upgraded.get("defense", 0))

	_refresh_effect_option(card_id)

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

func _refresh_effect_option(card_id: String) -> void:
	effect_entries.clear()

	if effect_option == null:
		return

	effect_option.clear()

	if card_id == "":
		effect_option.add_item("NO CARD SELECTED")
		effect_option.disabled = true
		return

	effect_entries = CardUpgradeManager.get_effect_entries(card_id)

	if effect_entries.is_empty():
		effect_option.add_item("NO EFFECTS")
		effect_option.disabled = true
		return

	for entry in effect_entries:
		var source := str(entry.get("source", ""))
		var effect: Dictionary = entry.get("effect", {})

		var prefix := "BASE" if source == "base" else "UPGRADE"
		var effect_name := _format_effect_name(effect)

		effect_option.add_item("%s: %s" % [prefix, effect_name])

	effect_option.selected = 0
	effect_option.disabled = false
	
func _on_remove_effect_button_pressed() -> void:
	if selected_card_id == "":
		return

	if effect_entries.is_empty():
		return

	var selected_index := effect_option.selected

	if selected_index < 0 or selected_index >= effect_entries.size():
		return

	var entry := effect_entries[selected_index]

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
