extends Control
class_name UpgradeUI

signal card_selected(card_id: String)
signal attack_pressed
signal health_pressed
signal effect_pressed

const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@onready var balance_label: Label = $Panel/MarginContainer/VBoxContainer/BalanceLabel
@onready var card_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/CardScroll/CardList
@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/InfoLabel
@onready var attack_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/AttackButton
@onready var health_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/HealthButton
@onready var effect_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/EffectButton
@onready var message_label: Label = $Panel/MarginContainer/VBoxContainer/MessageLabel

var selected_card_id := ""
var card_buttons: Array[Button] = []
var message_tween: Tween = null


func _ready() -> void:
	add_to_group("upgrade_ui")

	attack_button.pressed.connect(func(): attack_pressed.emit())
	health_button.pressed.connect(func(): health_pressed.emit())
	effect_button.pressed.connect(func(): effect_pressed.emit())

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
	_set_upgrade_buttons_disabled(false)


func set_selected_card(card_id: String) -> void:
	selected_card_id = card_id

	var data := CardDatabase.get_card(card_id)

	if data.is_empty():
		info_label.text = "UNKNOWN CARD"
		return

	var upgraded := data

	if Engine.has_singleton("CardUpgradeManager"):
		upgraded = CardUpgradeManager.apply_upgrades(card_id, data)

	var name := str(upgraded.get("name", card_id))
	var attack := int(upgraded.get("attack", 0))
	var hp := int(upgraded.get("defense", 0))

	var effects_text := "None"
	var effects: Array = CardData.get_active_effects(upgraded)

	if not effects.is_empty():
		var names: Array[String] = []
		for effect in effects:
			if effect is Dictionary:
				names.append(str(effect.get("name", effect.get("type", "Effect"))))
		effects_text = ", ".join(names)

	info_label.text = "%s\nATK: %d   HP: %d\nEFFECTS: %s" % [
		name,
		attack,
		hp,
		effects_text
	]


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
