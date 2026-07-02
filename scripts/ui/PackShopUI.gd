extends Control
class_name PackShopUI

signal pack_buy_pressed(pack_id: String)

const PACK_PREVIEW_SCENE := preload("res://scenes/PackPreviewViewport.tscn")

@onready var balance_label: Label = $Panel/MarginContainer/VBoxContainer/BalanceLabel
@onready var preview_row: HBoxContainer = $Panel/MarginContainer/VBoxContainer/PreviewRow
@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/InfoLabel
@onready var message_label: Label = $Panel/MarginContainer/VBoxContainer/MessageLabel

var pack_entries: Array[Dictionary] = []
var locked := false
var message_tween: Tween = null


func _ready() -> void:
	refresh_balance()
	show_message("")


func set_packs(packs: Dictionary) -> void:
	pack_entries.clear()

	for child in preview_row.get_children():
		child.queue_free()

	for pack_id in packs.keys():
		var data: Dictionary = packs[pack_id]
		pack_entries.append({"id": str(pack_id), "data": data})

		var preview := PACK_PREVIEW_SCENE.instantiate() as PackPreviewViewport
		preview.pack_id = str(pack_id)
		preview.pack_name = str(data.get("name", pack_id))
		preview.pack_scene = data.get("scene", null)
		preview.custom_minimum_size = Vector2(220, 180)
		preview.pressed.connect(_on_pack_preview_pressed)
		preview_row.add_child(preview)

	if pack_entries.is_empty():
		info_label.text = "NO PACKS AVAILABLE"
	else:
		_show_pack_info(str(pack_entries[0].get("id", "")))


func _on_pack_preview_pressed(pack_id: String) -> void:
	if locked:
		return

	_show_pack_info(pack_id)
	pack_buy_pressed.emit(pack_id)


func _show_pack_info(pack_id: String) -> void:
	for entry in pack_entries:
		if str(entry.get("id", "")) != pack_id:
			continue

		var data: Dictionary = entry.get("data", {})
		info_label.text = "%s\nPRICE: %d SOUL COINS\nCARDS: %d\n%s" % [
			str(data.get("name", pack_id)),
			int(data.get("cost", 0)),
			int(data.get("card_count", 0)),
			str(data.get("description", ""))
		]
		return


func refresh_balance() -> void:
	balance_label.text = "SOUL COINS: " + str(GameCurrency.coins)


func show_message(text: String) -> void:
	if message_tween:
		message_tween.kill()

	if text == "":
		message_label.visible = false
		return

	message_label.text = text
	message_label.visible = true
	message_label.modulate.a = 1.0

	message_tween = create_tween()
	message_tween.tween_interval(1.2)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.25)
	message_tween.tween_callback(func(): message_label.visible = false)


func set_buy_locked(value: bool) -> void:
	locked = value
