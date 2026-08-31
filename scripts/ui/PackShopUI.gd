extends Control
class_name PackShopUI

signal pack_buy_pressed(pack_id: String)

const PACK_PREVIEW_SCENE := preload("res://scenes/PackPreviewViewport.tscn")
const PACK_ORDER := ["basic", "ultra", "god"]
const PACK_ACCENTS := {
	"basic": Color(0.501961, 0.4, 0.909804, 1.0),
	"ultra": Color(0.898039, 0.321569, 0.352941, 1.0),
	"god": Color(0.835294, 0.682353, 0.262745, 1.0),
}

@onready var balance_label: Label = $OuterMargin/MainVBox/HeaderPanel/HeaderMargin/HeaderRow/BalanceChip/BalanceMargin/BalanceRow/BalanceText/BalanceLabel
@onready var preview_row: HBoxContainer = $OuterMargin/MainVBox/PreviewRow
@onready var info_title_label: Label = $OuterMargin/MainVBox/InfoPanel/InfoMargin/InfoRow/InfoText/InfoTitleLabel
@onready var info_description_label: Label = $OuterMargin/MainVBox/InfoPanel/InfoMargin/InfoRow/InfoText/InfoDescriptionLabel
@onready var info_meta_label: Label = $OuterMargin/MainVBox/InfoPanel/InfoMargin/InfoRow/InfoText/InfoMetaLabel
@onready var buy_button: Button = $OuterMargin/MainVBox/InfoPanel/InfoMargin/InfoRow/BuyButton
@onready var message_label: Label = $OuterMargin/MainVBox/StatusPanel/StatusMargin/StatusRow/MessageLabel

var pack_entries: Array[Dictionary] = []
var pack_previews: Dictionary = {}
var selected_pack_id := ""
var locked := false
var message_tween: Tween = null
var _message_active := false


func _ready() -> void:
	if GameCurrency.has_signal("coins_changed"):
		var coins_callback := Callable(self, "_on_coins_changed")
		if not GameCurrency.is_connected("coins_changed", coins_callback):
			GameCurrency.connect("coins_changed", coins_callback)

	if not buy_button.pressed.is_connected(_on_buy_button_pressed):
		buy_button.pressed.connect(_on_buy_button_pressed)

	refresh_balance()
	show_message("")


func set_packs(packs: Dictionary) -> void:
	pack_entries.clear()
	pack_previews.clear()
	selected_pack_id = ""

	for child in preview_row.get_children():
		child.queue_free()

	for pack_id in _get_ordered_pack_ids(packs):
		var data: Dictionary = packs.get(pack_id, {})
		pack_entries.append({"id": pack_id, "data": data})

		var preview := PACK_PREVIEW_SCENE.instantiate() as PackPreviewViewport
		preview.pack_id = pack_id
		preview.pack_name = str(data.get("name", pack_id))
		preview.pack_cost = int(data.get("cost", 0))
		preview.pack_card_count = int(data.get("card_count", 0))
		preview.pack_scene = data.get("scene", null) as PackedScene
		preview.accent_color = PACK_ACCENTS.get(pack_id, Color(0.431373, 0.160784, 0.188235, 1.0))
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_stretch_ratio = 1.0
		preview.pressed.connect(_on_pack_preview_pressed)
		preview_row.add_child(preview)
		pack_previews[pack_id] = preview

	if pack_entries.is_empty():
		_show_empty_state()
	else:
		_select_pack(str(pack_entries[0].get("id", "")))

	refresh_balance()


func _get_ordered_pack_ids(packs: Dictionary) -> Array[String]:
	var ordered_ids: Array[String] = []

	for preferred_id in PACK_ORDER:
		if packs.has(preferred_id):
			ordered_ids.append(preferred_id)

	for pack_key in packs.keys():
		var pack_id := str(pack_key)
		if not ordered_ids.has(pack_id):
			ordered_ids.append(pack_id)

	return ordered_ids


func _on_pack_preview_pressed(pack_id: String) -> void:
	if locked:
		return

	_select_pack(pack_id)


func _select_pack(pack_id: String) -> void:
	if not pack_previews.has(pack_id):
		return

	selected_pack_id = pack_id

	for preview_id in pack_previews.keys():
		var preview := pack_previews[preview_id] as PackPreviewViewport
		if preview:
			preview.set_selected(str(preview_id) == selected_pack_id)

	_show_pack_info(pack_id)
	_update_buy_button()

	if not _message_active:
		_refresh_default_status()


func _show_pack_info(pack_id: String) -> void:
	var data := _get_pack_data(pack_id)
	if data.is_empty():
		_show_empty_state()
		return

	info_title_label.text = str(data.get("name", pack_id))
	info_description_label.text = str(data.get("description", "Keine Beschreibung verfügbar."))
	info_meta_label.text = "%d KARTEN  //  %d SOUL COINS" % [
		int(data.get("card_count", 0)),
		int(data.get("cost", 0)),
	]


func _show_empty_state() -> void:
	info_title_label.text = "KEINE PACKS VERFÜGBAR"
	info_description_label.text = "Der Automat ist momentan leer."
	info_meta_label.text = "— KARTEN  //  — SOUL COINS"
	buy_button.disabled = true
	buy_button.text = "NICHT VERFÜGBAR"


func _get_pack_data(pack_id: String) -> Dictionary:
	for entry in pack_entries:
		if str(entry.get("id", "")) == pack_id:
			return entry.get("data", {}) as Dictionary

	return {}


func _on_buy_button_pressed() -> void:
	if locked or selected_pack_id.is_empty():
		return

	var data := _get_pack_data(selected_pack_id)
	if data.is_empty():
		show_message("DIESES PACK IST NICHT VERFÜGBAR")
		return

	var cost := int(data.get("cost", 0))
	if GameCurrency.coins < cost:
		show_message("NICHT GENUG SOUL COINS")
		refresh_balance()
		return

	pack_buy_pressed.emit(selected_pack_id)


func refresh_balance() -> void:
	var coins := int(GameCurrency.coins)
	balance_label.text = str(coins)

	for preview_id in pack_previews.keys():
		var preview := pack_previews[preview_id] as PackPreviewViewport
		if preview == null:
			continue

		var data := _get_pack_data(str(preview_id))
		preview.set_affordable(coins >= int(data.get("cost", 0)))

	_update_buy_button()

	if not _message_active:
		_refresh_default_status()


func _on_coins_changed(_coins: int) -> void:
	refresh_balance()


func _update_buy_button() -> void:
	if selected_pack_id.is_empty():
		buy_button.disabled = true
		buy_button.text = "PACK AUSWÄHLEN"
		return

	if locked:
		buy_button.disabled = true
		buy_button.text = "ÖFFNUNG LÄUFT"
		return

	var data := _get_pack_data(selected_pack_id)
	var cost := int(data.get("cost", 0))
	var affordable := GameCurrency.coins >= cost

	buy_button.disabled = not affordable
	buy_button.text = "PACK KAUFEN  //  %d COINS" % cost if affordable else "ZU WENIG COINS"


func show_message(text: String) -> void:
	if message_tween:
		message_tween.kill()
		message_tween = null

	if text.strip_edges().is_empty():
		_message_active = false
		_refresh_default_status()
		return

	_message_active = true
	message_label.text = text.to_upper()
	message_label.modulate.a = 1.0

	message_tween = create_tween()
	message_tween.tween_interval(1.8)
	message_tween.tween_callback(_finish_message)


func _finish_message() -> void:
	_message_active = false
	message_tween = null
	_refresh_default_status()


func _refresh_default_status() -> void:
	if locked:
		message_label.text = "PACK WIRD GEÖFFNET  //  ALLE KARTEN EINSAMMELN"
		return

	if selected_pack_id.is_empty():
		message_label.text = "WÄHLE EIN PACK AUS"
		return

	var cost := int(_get_pack_data(selected_pack_id).get("cost", 0))
	if GameCurrency.coins < cost:
		message_label.text = "NICHT GENUG SOUL COINS FÜR DIESES PACK"
	else:
		message_label.text = "AUSWAHL BESTÄTIGEN, UM DAS PACK ZU KAUFEN"


func set_buy_locked(value: bool) -> void:
	locked = value

	for preview in pack_previews.values():
		var pack_preview := preview as PackPreviewViewport
		if pack_preview:
			pack_preview.set_locked(locked)

	_update_buy_button()

	if not _message_active:
		_refresh_default_status()
