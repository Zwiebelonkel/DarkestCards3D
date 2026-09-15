extends Node3D
class_name MainMenu

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const PACK_OPENING_SCENE := MAIN_SCENE
const COLLECTION_SCENE := MAIN_SCENE
const GAME_TABLE_SCENE := MAIN_SCENE
const PISKEL_TOOL_SCENE := "res://scenes/ui/PiskelTool.tscn"

@onready var pack_opening_button: Button = %PackOpeningButton
@onready var collection_button: Button = %CollectionButton
@onready var game_table_button: Button = %GameTableButton
@onready var piskel_tool_button: Button = %PiskelToolButton
@onready var settings_button: Button = %SettingsButton
@onready var reset_button: Button = %ResetButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: SettingsMenu = %SettingsMenu
@onready var reset_confirmation: ConfirmationDialog = %ResetConfirmation
@onready var level_progress: Node3D = $Camera3D/LevelProgress
@onready var slot_picker: GridContainer = %SaveSlotPicker
@onready var slot_heading: Label = %SaveSlotHeading
@onready var slot_status: Label = %SaveSlotStatus
@onready var menu_container: CenterContainer = $CenterContainer
@onready var menu_panel: PanelContainer = $CenterContainer/PanelContainer

var selected_slot: int = 1
var _reset_slot_pending: int = 1
var _launching := false
var _status_key := ""
var _status_values: Array = []
var _status_is_error := false


func _ready() -> void:
	selected_slot = SaveSlots.active_slot
	slot_picker.slot_selected.connect(_on_slot_selected)
	SaveSlots.slots_changed.connect(_refresh_slots)
	Localization.locale_changed.connect(_refresh_localized_text)
	get_viewport().size_changed.connect(_update_menu_layout)
	menu_panel.minimum_size_changed.connect(_queue_menu_layout)
	pack_opening_button.pressed.connect(_play_selected.bind(PACK_OPENING_SCENE))
	collection_button.pressed.connect(_play_selected.bind(COLLECTION_SCENE))
	game_table_button.pressed.connect(_play_selected.bind(GAME_TABLE_SCENE))
	piskel_tool_button.pressed.connect(_change_scene.bind(PISKEL_TOOL_SCENE))
	settings_button.pressed.connect(_open_settings)
	reset_button.pressed.connect(_open_reset_confirmation)
	reset_confirmation.confirmed.connect(_reset_game_data)
	settings_menu.closed.connect(_on_settings_closed)
	quit_button.pressed.connect(Callable(get_tree(), "quit"))
	_refresh_localized_text()
	call_deferred("_update_menu_layout")
	if not NetworkManager.lobby_state_changed.is_connected(_on_online_lobby_state_changed):
		NetworkManager.lobby_state_changed.connect(_on_online_lobby_state_changed)
	if NetworkManager.has_active_session():
		call_deferred("_change_scene", MAIN_SCENE)


func _process(_delta: float) -> void:
	level_progress.set_enabled(not settings_menu.visible and not reset_confirmation.visible)


func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _play_selected(scene_path: String = MAIN_SCENE) -> void:
	if _launching:
		return
	_launching = true
	var error := SaveSlots.select_slot(selected_slot)
	if error != OK:
		_launching = false
		_set_status("save_slot_load_error", [selected_slot, error], true)
		return
	error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_launching = false
		_set_status("save_slot_load_error", [selected_slot, error], true)


func _on_slot_selected(slot: int) -> void:
	selected_slot = clampi(slot, 1, SaveSlots.SLOT_COUNT)
	_set_status("", [])
	_refresh_slots()


func _refresh_slots() -> void:
	slot_picker.refresh(selected_slot)


func _refresh_localized_text() -> void:
	slot_heading.text = Localization.text("save_slot_heading")
	reset_button.text = Localization.text("Spielstand zurücksetzen")
	reset_confirmation.title = Localization.text("Spielstand zurücksetzen")
	reset_confirmation.dialog_text = Localization.format_text("save_slot_reset_confirm", [_reset_slot_pending])
	slot_status.text = Localization.format_text(_status_key, _status_values) if not _status_key.is_empty() else ""
	_refresh_slots()
	call_deferred("_update_menu_layout")


func _set_status(key: String, values: Array, is_error: bool = false) -> void:
	_status_key = key
	_status_values = values
	_status_is_error = is_error
	slot_status.text = Localization.format_text(key, values) if not key.is_empty() else ""
	slot_status.modulate = Color("ff8982") if _status_is_error else Color("bacf9d")


func _update_menu_layout() -> void:
	var width := minf(1100.0, maxf(get_viewport().get_visible_rect().size.x - 48.0, 280.0))
	menu_panel.custom_minimum_size.x = width
	menu_container.offset_left = -width * 0.5
	menu_container.offset_right = width * 0.5
	menu_container.offset_top = -menu_container.get_combined_minimum_size().y - 24.0
	menu_container.offset_bottom = -24.0


func _queue_menu_layout() -> void:
	call_deferred("_update_menu_layout")


func _unhandled_input(event: InputEvent) -> void:
	if settings_menu.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		settings_menu.close()


func _open_settings() -> void:
	settings_menu.open()


func _open_reset_confirmation() -> void:
	_reset_slot_pending = selected_slot
	reset_confirmation.dialog_text = Localization.format_text("save_slot_reset_confirm", [_reset_slot_pending])
	reset_confirmation.popup_centered()


func _reset_game_data() -> void:
	var error := SaveSlots.reset_slot(_reset_slot_pending)
	if error != OK:
		_set_status("save_slot_reset_error", [_reset_slot_pending, error], true)
	else:
		_set_status("save_slot_reset_done", [_reset_slot_pending])
	_refresh_slots()
	reset_button.grab_focus()


func _on_settings_closed() -> void:
	settings_button.grab_focus()


func _on_online_lobby_state_changed() -> void:
	# Accepting a Steam invite can happen from the main menu. Move into the hub;
	# GameTable will detect the active lobby and open its lobby overlay.
	if NetworkManager.current_lobby_id > 0:
		_change_scene(MAIN_SCENE)
