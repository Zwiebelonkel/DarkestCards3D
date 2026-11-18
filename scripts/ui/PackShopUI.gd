extends Control
class_name PackShopUI
const UI_AUDIO := preload("res://scripts/ui/InterfaceSounds.gd")

signal pack_buy_pressed(pack_id: String)

const PACK_PREVIEW_SCENE := preload("res://scenes/PackPreviewViewport.tscn")
const PACK_ORDER := ["basic", "ultra", "god"]
const MULTI_PACK_LEVEL := 2
const PACK_ACCENTS := {
	"basic": Color(0.501961, 0.4, 0.909804, 1.0),
	"ultra": Color(0.898039, 0.321569, 0.352941, 1.0),
	"god": Color(0.835294, 0.682353, 0.262745, 1.0),
}
@onready var balance_label: Label = $OuterMargin/MainVBox/HeaderPanel/HeaderMargin/HeaderRow/BalanceChip/BalanceMargin/BalanceRow/BalanceLabel
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
var _message_source := ""
var quantity_controls: VBoxContainer
var increase_button: Button
var decrease_button: Button
var _purchase_quantity := 1


func _ready() -> void:
	_create_quantity_controls()
	UI_AUDIO.connect_buttons(self)
	Localization.locale_changed.connect(_refresh_localized_text)
	if GameCurrency.has_signal("coins_changed"):
		var coins_callback := Callable(self, "_on_coins_changed")
		if not GameCurrency.is_connected("coins_changed", coins_callback):
			GameCurrency.connect("coins_changed", coins_callback)

	if not buy_button.pressed.is_connected(_on_buy_button_pressed):
		buy_button.pressed.connect(_on_buy_button_pressed)
	if not GameCurrency.progression_changed.is_connected(_on_progression_changed):
		GameCurrency.progression_changed.connect(_on_progression_changed)
	CollectionManager.collection_changed.connect(_on_collection_changed)

	refresh_balance()
	show_message("")


func _create_quantity_controls() -> void:
	# Let longer totals grow the buy button while retaining room around its text.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var buy_style := buy_button.get_theme_stylebox(state).duplicate() as StyleBox
		buy_style.content_margin_left = 12.0
		buy_style.content_margin_right = 12.0
		buy_button.add_theme_stylebox_override(state, buy_style)
	quantity_controls = VBoxContainer.new()
	quantity_controls.name = "QuantityControls"
	quantity_controls.custom_minimum_size = Vector2(38.0, 64.0)
	quantity_controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quantity_controls.add_theme_constant_override("separation", 4)
	var info_row := buy_button.get_parent()
	info_row.add_child(quantity_controls)
	info_row.move_child(quantity_controls, buy_button.get_index())
	increase_button = _create_quantity_button("IncreaseButton", "+", "Ein weiteres Pack kaufen")
	decrease_button = _create_quantity_button("DecreaseButton", "-", "Ein Pack weniger kaufen")
	increase_button.pressed.connect(_change_purchase_quantity.bind(1))
	decrease_button.pressed.connect(_change_purchase_quantity.bind(-1))


func _create_quantity_button(node_name: String, text: String, hint: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = hint
	button.custom_minimum_size = Vector2(38.0, 30.0)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", buy_button.get_theme_font("font"))
	button.add_theme_font_size_override("font_size", 20)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(color_name, Color.WHITE)
	button.add_theme_stylebox_override("normal", _quantity_button_style(Color("a02e3a"), Color("d05260")))
	button.add_theme_stylebox_override("hover", _quantity_button_style(Color("c03b49"), Color("ed7480")))
	button.add_theme_stylebox_override("pressed", _quantity_button_style(Color("79212d"), Color("ed7480")))
	button.add_theme_stylebox_override("disabled", _quantity_button_style(Color("481b23"), Color("6c2a35")))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	quantity_controls.add_child(button)
	return button


func _quantity_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style


func get_purchase_quantity() -> int:
	return _purchase_quantity


func _maximum_affordable_quantity() -> int:
	var cost := _get_pack_price(selected_pack_id)
	if cost <= 0:
		return 1
	return maxi(1, floori(GameCurrency.get_coins() / float(cost)))


func _change_purchase_quantity(change: int) -> void:
	if locked or GameCurrency.get_level() < MULTI_PACK_LEVEL:
		return
	if selected_pack_id.is_empty() or not PackDefinition.is_unlocked(selected_pack_id, GameCurrency.get_level()):
		return
	_purchase_quantity = clampi(_purchase_quantity + change, 1, _maximum_affordable_quantity())
	_update_buy_button()
	show_message("")


func _update_quantity_controls() -> void:
	var available := GameCurrency.get_level() >= MULTI_PACK_LEVEL
	quantity_controls.visible = available
	if not available:
		_purchase_quantity = 1
	elif not locked:
		_purchase_quantity = clampi(_purchase_quantity, 1, _maximum_affordable_quantity())
	var pack_unlocked := not selected_pack_id.is_empty() and PackDefinition.is_unlocked(selected_pack_id, GameCurrency.get_level())
	increase_button.disabled = not available or locked or not pack_unlocked or _purchase_quantity >= _maximum_affordable_quantity()
	decrease_button.disabled = not available or locked or not pack_unlocked or _purchase_quantity <= 1


func set_packs(packs: Dictionary) -> void:
	pack_entries.clear()
	pack_previews.clear()
	selected_pack_id = ""
	_purchase_quantity = 1

	for child in preview_row.get_children():
		child.queue_free()

	for pack_id in _get_ordered_pack_ids(packs):
		var data: Dictionary = packs.get(pack_id, {})
		pack_entries.append({"id": pack_id, "data": data})

		var preview := PACK_PREVIEW_SCENE.instantiate() as PackPreviewViewport
		preview.pack_id = pack_id
		preview.pack_name = str(data.get("name", pack_id))
		preview.pack_cost = PackDefinition.get_price(pack_id, data)
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
	UI_AUDIO.play_click(self)

	_select_pack(pack_id)


func _select_pack(pack_id: String) -> void:
	if not pack_previews.has(pack_id):
		return

	if selected_pack_id != pack_id:
		_purchase_quantity = 1
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
	var minimum_level := PackDefinition.get_minimum_level(pack_id)
	if minimum_level > 1:
		info_description_label.text = Localization.format_text("%s Available from player level %d.", [Localization.localized_arg(str(data.get("description", "Keine Beschreibung verfügbar."))), minimum_level])
	info_meta_label.text = Localization.format_text("%d KARTEN  //  %s SOUL COINS", [
		int(data.get("card_count", 0)),
		GameCurrency.format_coins(_get_pack_price(pack_id), true),
	])


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


func _get_pack_price(pack_id: String) -> float:
	return PackDefinition.get_price(pack_id, _get_pack_data(pack_id))


func _on_buy_button_pressed() -> void:
	if locked or selected_pack_id.is_empty():
		return

	var data := _get_pack_data(selected_pack_id)
	if data.is_empty():
		show_message("DIESES PACK IST NICHT VERFÜGBAR")
		return
	if not PackDefinition.is_unlocked(selected_pack_id, GameCurrency.get_level()):
		show_message(PackDefinition.get_unlock_message(selected_pack_id))
		refresh_balance()
		return

	var cost := _get_pack_price(selected_pack_id) * _purchase_quantity
	if GameCurrency.coins < cost:
		show_message("NICHT GENUG SOUL COINS")
		refresh_balance()
		return

	pack_buy_pressed.emit(selected_pack_id)


func refresh_balance() -> void:
	var coins := GameCurrency.get_coins()
	balance_label.text = GameCurrency.format_coins(coins)

	for preview_id in pack_previews.keys():
		var preview := pack_previews[preview_id] as PackPreviewViewport
		if preview == null:
			continue

		var price := _get_pack_price(str(preview_id))
		preview.set_price(price)
		preview.set_affordable(coins >= price)
		preview.set_level_requirement(PackDefinition.get_minimum_level(str(preview_id)), GameCurrency.get_level())

	_update_buy_button()

	if not _message_active:
		_refresh_default_status()


func _on_coins_changed(_coins: float) -> void:
	refresh_balance()


func _on_collection_changed(_card_ids: Array[String]) -> void:
	refresh_balance()
	if not selected_pack_id.is_empty():
		_show_pack_info(selected_pack_id)


func _on_progression_changed(_level: int, _xp: int, _xp_required: int) -> void:
	refresh_balance()
	if not locked:
		# Do not leave an old level-lock notice visible after a level-up/reset.
		show_message("")


func _update_buy_button() -> void:
	_update_quantity_controls()
	if selected_pack_id.is_empty():
		buy_button.disabled = true
		buy_button.text = "PACK AUSWÄHLEN"
		return

	if locked:
		buy_button.disabled = true
		buy_button.text = "ÖFFNUNG LÄUFT"
		return
	if not PackDefinition.is_unlocked(selected_pack_id, GameCurrency.get_level()):
		buy_button.disabled = true
		buy_button.text = PackDefinition.get_unlock_message(selected_pack_id)
		return

	var cost := _get_pack_price(selected_pack_id) * _purchase_quantity
	var affordable := GameCurrency.coins >= cost

	buy_button.disabled = not affordable
	var purchase_text := "PACK KAUFEN" if _purchase_quantity == 1 else Localization.format_text("%d PACKS KAUFEN", [_purchase_quantity])
	buy_button.text = Localization.format_text("%s  //  %s COINS", [Localization.text(purchase_text), GameCurrency.format_coins(cost, true)]) if affordable else "ZU WENIG COINS"


func show_message(text: String) -> void:
	_message_source = text
	if message_tween:
		message_tween.kill()
		message_tween = null

	if text.strip_edges().is_empty():
		_message_active = false
		_refresh_default_status()
		return

	_message_active = true
	message_label.text = Localization.text(text).to_upper()
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

	if not PackDefinition.is_unlocked(selected_pack_id, GameCurrency.get_level()):
		message_label.text = Localization.format_text("%s  //  DEIN LEVEL: %d", [PackDefinition.get_unlock_message(selected_pack_id), GameCurrency.get_level()])
		return
	var cost := _get_pack_price(selected_pack_id) * _purchase_quantity
	if GameCurrency.coins < cost:
		message_label.text = "NICHT GENUG SOUL COINS FÜR DIESES PACK"
	else:
		message_label.text = "AUSWAHL BESTÄTIGEN, UM DAS PACK ZU KAUFEN" if _purchase_quantity == 1 else Localization.format_text("AUSWAHL BESTÄTIGEN, UM %d PACKS ZU KAUFEN", [_purchase_quantity])


func set_buy_locked(value: bool) -> void:
	locked = value

	for preview in pack_previews.values():
		var pack_preview := preview as PackPreviewViewport
		if pack_preview:
			pack_preview.set_locked(locked)

	_update_buy_button()

	if not _message_active:
		_refresh_default_status()

func _refresh_localized_text() -> void:
	if not selected_pack_id.is_empty():
		_show_pack_info(selected_pack_id)
	refresh_balance()
	_update_buy_button()
	if _message_active:
		message_label.text = Localization.text(_message_source).to_upper()
	else:
		_refresh_default_status()
