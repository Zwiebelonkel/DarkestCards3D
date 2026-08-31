extends Control
class_name UpgradeUI

signal card_selected(card_id: String)
signal attack_pressed
signal health_pressed
signal effect_pressed
signal remove_effect_pressed(effect_source: String, effect_index: int)

const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const EFFECT_ICON_PATH := "res://assets/effects/"
const EFFECT_PLACEHOLDER := preload("res://assets/effects/placeholder.png")
const MAX_EFFECT_SLOTS := 2

const COLOR_SURFACE := Color("141118")
const COLOR_SURFACE_HIGH := Color("1d171f")
const COLOR_BORDER := Color("6e2930")
const COLOR_ACCENT := Color("d0525f")
const COLOR_TEXT := Color("f3e7e4")
const COLOR_MUTED := Color("a88e91")

@onready var balance_label: Label = %BalanceLabel
@onready var card_count_label: Label = %CardCountLabel
@onready var card_list: VBoxContainer = %CardList
@onready var selected_name_label: Label = %SelectedNameLabel
@onready var selected_rarity_label: Label = %SelectedRarityLabel
@onready var attack_value_label: Label = %AttackValueLabel
@onready var attack_bonus_label: Label = %AttackBonusLabel
@onready var health_value_label: Label = %HealthValueLabel
@onready var health_bonus_label: Label = %HealthBonusLabel
@onready var effects_count_label: Label = %EffectsCountLabel
@onready var effect_slot_1: Button = %EffectSlot1
@onready var effect_slot_2: Button = %EffectSlot2
@onready var remove_effect_button: Button = %RemoveButton
@onready var attack_button: Button = %AttackButton
@onready var health_button: Button = %HealthButton
@onready var effect_button: Button = %EffectButton
@onready var message_label: Label = %MessageLabel

var selected_card_id := ""
var card_buttons: Dictionary = {}
var effect_slot_buttons: Array[Button] = []
var effect_entries: Array[Dictionary] = []
var selected_effect_entry_index := -1
var message_tween: Tween = null

var attack_cost := 5
var health_cost := 5
var effect_cost := 12


func _ready() -> void:
	add_to_group("upgrade_ui")
	effect_slot_buttons = [effect_slot_1, effect_slot_2]

	attack_button.pressed.connect(func(): attack_pressed.emit())
	health_button.pressed.connect(func(): health_pressed.emit())
	effect_button.pressed.connect(func(): effect_pressed.emit())
	remove_effect_button.pressed.connect(_on_remove_effect_button_pressed)
	effect_slot_1.pressed.connect(_on_effect_slot_pressed.bind(0))
	effect_slot_2.pressed.connect(_on_effect_slot_pressed.bind(1))

	if CardUpgradeManager.has_signal("upgrades_changed"):
		var upgrade_callback := Callable(self, "_on_upgrades_changed")
		if not CardUpgradeManager.is_connected("upgrades_changed", upgrade_callback):
			CardUpgradeManager.connect("upgrades_changed", upgrade_callback)

	if GameCurrency.has_signal("coins_changed"):
		var coins_callback := Callable(self, "_on_coins_changed")
		if not GameCurrency.is_connected("coins_changed", coins_callback):
			GameCurrency.connect("coins_changed", coins_callback)

	configure_costs(attack_cost, health_cost, effect_cost)
	refresh_balance()
	_show_empty_selection()
	show_message("")


func configure_costs(new_attack_cost: int, new_health_cost: int, new_effect_cost: int) -> void:
	attack_cost = max(new_attack_cost, 0)
	health_cost = max(new_health_cost, 0)
	effect_cost = max(new_effect_cost, 0)

	attack_button.text = "ANGRIFF +1\n%d SOUL COINS" % attack_cost
	health_button.text = "LEBEN +1\n%d SOUL COINS" % health_cost
	effect_button.text = "EFFEKT WÜRFELN\n%d SOUL COINS" % effect_cost


func set_cards(card_ids: Array, owned_counts: Dictionary = {}) -> void:
	var previous_selection := selected_card_id

	for child in card_list.get_children():
		card_list.remove_child(child)
		child.queue_free()

	card_buttons.clear()

	var entries: Array[Dictionary] = []
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
			"rank": RarityEffectsData.rarity_rank(rarity),
			"amount": int(owned_counts.get(card_id, CollectionManager.get_amount(card_id)))
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("rank", 0)) == int(b.get("rank", 0)):
			return String(a.get("data", {}).get("name", "")).nocasecmp_to(
				String(b.get("data", {}).get("name", ""))
			) < 0
		return int(a.get("rank", 0)) > int(b.get("rank", 0))
	)

	for entry in entries:
		var card_id := str(entry.get("id", ""))
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 58)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.set_meta("owned_amount", int(entry.get("amount", 0)))
		button.pressed.connect(_on_card_button_pressed.bind(card_id, button))

		_style_card_button(button, str(entry.get("rarity", "common")))
		_update_card_button_content(card_id, button)

		card_list.add_child(button)
		card_buttons[card_id] = button

	card_count_label.text = "%d KARTENTYPEN" % entries.size()

	if previous_selection != "" and card_buttons.has(previous_selection):
		set_selected_card(previous_selection)
	else:
		selected_card_id = ""
		_show_empty_selection()


func set_selected_card(card_id: String) -> void:
	var data := CardDatabase.get_card(card_id)
	if data.is_empty():
		selected_card_id = ""
		_show_empty_selection()
		return

	selected_card_id = card_id
	_sync_card_button_selection()

	var upgraded := CardUpgradeManager.apply_upgrades(card_id, data)
	var rarity := str(data.get("rarity", "common"))
	var attack_bonus := CardUpgradeManager.get_attack_bonus(card_id)
	var health_bonus := CardUpgradeManager.get_health_bonus(card_id)

	selected_name_label.text = str(upgraded.get("name", card_id)).to_upper()
	selected_rarity_label.text = _format_rarity(rarity)
	selected_rarity_label.add_theme_color_override("font_color", _get_rarity_color(rarity))
	attack_value_label.text = str(int(upgraded.get("attack", 0)))
	attack_bonus_label.text = "+%d BONUS" % attack_bonus
	health_value_label.text = str(int(upgraded.get("defense", 0)))
	health_bonus_label.text = "+%d BONUS" % health_bonus

	if card_buttons.has(card_id):
		_update_card_button_content(card_id, card_buttons[card_id] as Button)

	_refresh_effect_slots(card_id)
	_update_upgrade_button_state()


func refresh_balance() -> void:
	balance_label.text = "%d SOUL COINS" % GameCurrency.coins


func show_message(text: String) -> void:
	if message_tween != null:
		message_tween.kill()
		message_tween = null

	if text.is_empty():
		message_label.text = " "
		message_label.modulate.a = 0.0
		return

	message_label.text = text.to_upper()
	message_label.modulate.a = 1.0

	message_tween = create_tween()
	message_tween.tween_interval(1.6)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.3)
	message_tween.tween_callback(func(): message_label.text = " ")


func _show_empty_selection() -> void:
	selected_name_label.text = "KARTE AUSWÄHLEN"
	selected_rarity_label.text = "—"
	selected_rarity_label.add_theme_color_override("font_color", COLOR_MUTED)
	attack_value_label.text = "—"
	attack_bonus_label.text = "+0 BONUS"
	health_value_label.text = "—"
	health_bonus_label.text = "+0 BONUS"
	_refresh_effect_slots("")
	_sync_card_button_selection()
	_set_upgrade_buttons_disabled(true)


func _set_upgrade_buttons_disabled(disabled: bool) -> void:
	attack_button.disabled = disabled
	health_button.disabled = disabled
	effect_button.disabled = disabled
	remove_effect_button.disabled = true


func _update_upgrade_button_state() -> void:
	if selected_card_id.is_empty():
		_set_upgrade_buttons_disabled(true)
		return

	attack_button.disabled = false
	health_button.disabled = false
	effect_button.disabled = CardUpgradeManager.get_free_effect_slots(selected_card_id) <= 0
	remove_effect_button.disabled = not _has_valid_effect_selection()


func _on_card_button_pressed(card_id: String, button: Button) -> void:
	selected_card_id = card_id
	_sync_card_button_selection()
	button.button_pressed = true
	card_selected.emit(card_id)


func _sync_card_button_selection() -> void:
	for card_id in card_buttons:
		var button := card_buttons[card_id] as Button
		button.button_pressed = str(card_id) == selected_card_id


func _update_card_button_content(card_id: String, button: Button) -> void:
	var data := CardDatabase.get_card(card_id)
	if data.is_empty():
		return

	var amount := int(button.get_meta("owned_amount", CollectionManager.get_amount(card_id)))
	var rarity := str(data.get("rarity", "common"))
	var attack_bonus := CardUpgradeManager.get_attack_bonus(card_id)
	var health_bonus := CardUpgradeManager.get_health_bonus(card_id)
	var card_name := str(data.get("name", card_id)).to_upper()

	button.text = "%s   x%d\n%s  |  +%d ATK  +%d LP" % [
		card_name,
		amount,
		_format_rarity(rarity),
		attack_bonus,
		health_bonus
	]
	button.tooltip_text = "%s · %s · %d im Besitz" % [
		str(data.get("name", card_id)),
		_format_rarity(rarity),
		amount
	]


func _style_card_button(button: Button, rarity: String) -> void:
	button.add_theme_font_override("font", VCR_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var rarity_color := _get_rarity_color(rarity)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_SURFACE
	normal.border_width_left = 5
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = rarity_color.darkened(0.15)
	normal.content_margin_left = 11.0
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_SURFACE_HIGH
	hover.border_color = rarity_color

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = rarity_color.darkened(0.62)
	pressed.border_width_left = 5
	pressed.border_width_top = 2
	pressed.border_width_right = 2
	pressed.border_width_bottom = 2
	pressed.border_color = rarity_color.lightened(0.18)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _refresh_effect_slots(card_id: String) -> void:
	selected_effect_entry_index = -1
	effect_entries.clear()
	remove_effect_button.disabled = true

	if not card_id.is_empty():
		effect_entries = CardUpgradeManager.get_effect_entries(card_id)

	effects_count_label.text = "%d / %d BELEGT" % [effect_entries.size(), MAX_EFFECT_SLOTS]

	for slot_index in range(MAX_EFFECT_SLOTS):
		var button := effect_slot_buttons[slot_index]
		button.button_pressed = false
		button.icon = null

		if card_id.is_empty():
			button.disabled = true
			button.text = "KARTE AUSWÄHLEN"
			button.tooltip_text = ""
			continue

		if slot_index >= effect_entries.size():
			button.disabled = true
			button.text = "FREIER EFFEKT-SLOT"
			button.tooltip_text = "Hier kann ein neuer Effekt hinzugefügt werden."
			continue

		var entry := effect_entries[slot_index]
		var source := str(entry.get("source", ""))
		var effect: Dictionary = entry.get("effect", {})
		var source_label := "GRUNDEFFEKT" if source == "base" else "UPGRADE"
		var effect_name := _format_effect_name(effect)

		button.disabled = false
		button.text = "%s\n%s" % [source_label, effect_name]
		button.icon = _load_effect_icon(effect)
		button.tooltip_text = "%s\n%s\nAuswählen, um den Effekt zu entfernen." % [
			effect_name,
			str(effect.get("description", ""))
		]


func _on_effect_slot_pressed(entry_index: int) -> void:
	if entry_index < 0 or entry_index >= effect_entries.size():
		_clear_effect_selection()
		return

	var clicked_button := effect_slot_buttons[entry_index]
	if selected_effect_entry_index == entry_index and not clicked_button.button_pressed:
		_clear_effect_selection()
		return

	selected_effect_entry_index = entry_index
	for index in range(effect_slot_buttons.size()):
		effect_slot_buttons[index].button_pressed = index == entry_index

	remove_effect_button.disabled = false


func _clear_effect_selection() -> void:
	selected_effect_entry_index = -1
	for button in effect_slot_buttons:
		button.button_pressed = false
	remove_effect_button.disabled = true


func _has_valid_effect_selection() -> bool:
	return selected_effect_entry_index >= 0 and selected_effect_entry_index < effect_entries.size()


func _on_remove_effect_button_pressed() -> void:
	if selected_card_id.is_empty() or not _has_valid_effect_selection():
		return

	var entry := effect_entries[selected_effect_entry_index]
	var source := str(entry.get("source", ""))
	var effect_index := int(entry.get("index", -1))
	if source.is_empty() or effect_index < 0:
		return

	remove_effect_button.disabled = true
	remove_effect_pressed.emit(source, effect_index)


func _load_effect_icon(effect: Dictionary) -> Texture2D:
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()
	if effect_type.is_empty():
		return EFFECT_PLACEHOLDER

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
	return EFFECT_PLACEHOLDER


func _format_effect_name(effect: Dictionary) -> String:
	var effect_type := str(effect.get("type", "")).to_lower()
	var translated_names := {
		"armor": "PANZERUNG",
		"regeneration": "REGENERATION",
		"poison": "GIFT",
		"lifesteal": "LEBENSRAUB",
		"thorns": "DORNEN",
		"cleave": "RUNDUMSCHLAG",
		"double_strike": "DOPPELSCHLAG",
		"stun": "BETÄUBUNG",
		"chain_attack": "KETTENANGRIFF",
		"triple_strike": "DREIFACHSCHLAG",
		"last_stand": "LETZTES GEFECHT",
		"execute": "HINRICHTUNG",
		"shield_first_hit": "ERSTSCHLAGSCHILD",
		"swarm_power": "SCHWARMKRAFT",
		"grave_return": "GRABESRÜCKKEHR",
		"deck_burn": "DECKBRAND",
		"draw_on_kill": "KARTE BEI KILL",
		"curse": "FLUCH",
		"swap_stats": "WERTE TAUSCHEN",
		"random_damage": "ZUFALLSSCHADEN",
		"bodyguard": "LEIBWACHE",
		"neighbor_heal": "NACHBARHEILUNG"
	}

	var label := str(translated_names.get(
		effect_type,
		str(effect.get("name", effect_type)).replace("_", " ").to_upper()
	))

	if effect.has("percent"):
		label += " %d%%" % int(round(float(effect.get("percent", 0.0)) * 100.0))
	elif effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			label += " %d%%" % int(round(value * 100.0))
		else:
			label += " +%d" % int(round(value))
	elif effect.has("damage") and effect.has("turns"):
		label += " %d/%d R" % [
			int(effect.get("damage", 0)),
			int(effect.get("turns", 0))
		]

	return label


func _format_rarity(rarity: String) -> String:
	match rarity.to_lower():
		"common":
			return "GEWÖHNLICH"
		"uncommon":
			return "UNGEWÖHNLICH"
		"rare":
			return "SELTEN"
		"epic":
			return "EPISCH"
		"legendary":
			return "LEGENDÄR"
		"mythic":
			return "MYTHISCH"
		"exotic":
			return "EXOTISCH"
		_:
			return rarity.replace("_", " ").to_upper()


func _get_rarity_color(rarity: String) -> Color:
	return RarityEffectsData.get_color(rarity)


func _on_upgrades_changed(card_id: String) -> void:
	refresh_balance()
	if selected_card_id == card_id:
		call_deferred("set_selected_card", card_id)


func _on_coins_changed(_coins: int) -> void:
	refresh_balance()
