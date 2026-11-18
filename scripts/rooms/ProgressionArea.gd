extends Node3D
class_name ProgressionArea
## Card-locked world entrance with shared-camera travel to a connected room.

signal screen_open_changed(open: bool)
signal travel_requested(door: HospitalDoor)

const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@export var area_id := ""
@export var display_name := ""
@export var accent_color := Color("c59b62")
## Connected rooms live in Main and use its existing shared-camera travel.
@export var room_index := 0
@export_group("Future shop inventory")
## A separate pool intentionally does not fall back to the regular pack shop.
@export var shop_pool := ""
@export var shop_card_ids: PackedStringArray = []

@onready var door: HospitalDoor = $Door

var _interaction_enabled := false
var _screen: CanvasLayer
var _heading: Label
var _return_button: Button


func _enter_tree() -> void:
	# Assign before the child's _ready so HospitalDoor subscribes to unlocks.
	get_node("Door").area_id = area_id


func _ready() -> void:
	door.activated.connect(_on_door_activated)
	door.set_interaction_enabled(false)
	if room_index == 0:
		_build_screen()
	CollectionManager.collection_changed.connect(_refresh)
	Localization.locale_changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	door.set_interaction_enabled(enabled and not is_open())


func is_open() -> bool:
	return is_instance_valid(_screen) and _screen.visible


func open() -> bool:
	if not _interaction_enabled or is_open() or get_tree().paused or not is_visible_in_tree():
		return false
	if area_id.is_empty() or not CollectionManager.has_area_access(area_id):
		return false
	if room_index > 0:
		travel_requested.emit(door)
		return true
	door.set_travel_open(true)
	_screen.show()
	door.set_interaction_enabled(false)
	screen_open_changed.emit(true)
	if is_instance_valid(_return_button):
		_return_button.grab_focus()
	return true


func close() -> void:
	if not is_open():
		return
	_screen.hide()
	door.set_travel_open(false)
	screen_open_changed.emit(false)
	door.set_interaction_enabled(_interaction_enabled)


func get_shop_price(base_price: float) -> float:
	# This pool can later supply its own offers and prices. It never inherits
	# Dealer License's normal-shop discount when configured as black_market.
	return GameCurrency.get_shop_price(base_price, shop_pool)


func get_shop_card_ids() -> PackedStringArray:
	return shop_card_ids.duplicate()


func _on_door_activated(_door: HospitalDoor) -> void:
	open()


func _refresh(_card_ids: Array[String] = []) -> void:
	var accessible := CollectionManager.has_area_access(area_id)
	if is_open() and not accessible:
		close()
	if is_instance_valid(_heading):
		_heading.text = Localization.text(display_name).to_upper()
		_return_button.text = Localization.text("Zurück")


func _build_screen() -> void:
	_screen = CanvasLayer.new()
	_screen.name = "DestinationScreen"
	_screen.layer = 40
	add_child(_screen)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.018, 0.021, 0.026, 0.98)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17171a")
	style.border_color = accent_color
	style.set_border_width_all(2)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	content.add_theme_font_override("font", FONT)
	panel.add_child(content)
	_heading = Label.new()
	_heading.add_theme_color_override("font_color", accent_color)
	_heading.add_theme_font_size_override("font_size", 30)
	content.add_child(_heading)
	_return_button = Button.new()
	_return_button.custom_minimum_size.y = 48
	_return_button.pressed.connect(close)
	content.add_child(_return_button)
	_screen.hide()
