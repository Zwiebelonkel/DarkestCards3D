extends Control
class_name PackShopUI

signal pack_buy_pressed(pack_id: String)

const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@onready var balance_label: Label = $Panel/MarginContainer/VBoxContainer/BalanceLabel
@onready var pack_option: OptionButton = $Panel/MarginContainer/VBoxContainer/PackOption
@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/InfoLabel
@onready var buy_button: Button = $Panel/MarginContainer/VBoxContainer/BuyButton
@onready var message_label: Label = $Panel/MarginContainer/VBoxContainer/MessageLabel

var pack_entries: Array[Dictionary] = []
var selected_pack_id := ""
var message_tween: Tween = null


func _ready() -> void:
	buy_button.pressed.connect(_on_buy_pressed)
	pack_option.item_selected.connect(_on_pack_selected)

	refresh_balance()
	show_message("")


func set_packs(packs: Dictionary) -> void:
	pack_entries.clear()
	pack_option.clear()

	for pack_id in packs.keys():
		var data: Dictionary = packs[pack_id]

		pack_entries.append({
			"id": str(pack_id),
			"data": data
		})

		pack_option.add_item(str(data.get("name", pack_id)))

	if pack_entries.is_empty():
		info_label.text = "NO PACKS AVAILABLE"
		buy_button.disabled = true
		return

	pack_option.selected = 0
	_on_pack_selected(0)


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


func _on_pack_selected(index: int) -> void:
	if index < 0 or index >= pack_entries.size():
		return

	var entry := pack_entries[index]
	var data: Dictionary = entry.get("data", {})

	selected_pack_id = str(entry.get("id", ""))

	var name := str(data.get("name", selected_pack_id))
	var cost := int(data.get("cost", 0))
	var card_count := int(data.get("card_count", 0))
	var description := str(data.get("description", ""))

	info_label.text = "%s\nPRICE: %d SOUL COINS\nCARDS: %d\n%s" % [
		name,
		cost,
		card_count,
		description
	]

	buy_button.disabled = selected_pack_id == ""


func _on_buy_pressed() -> void:
	if selected_pack_id == "":
		return

	pack_buy_pressed.emit(selected_pack_id)
	
func set_buy_locked(locked: bool) -> void:
	buy_button.disabled = locked
	pack_option.disabled = locked
