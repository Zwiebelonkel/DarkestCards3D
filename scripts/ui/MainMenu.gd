extends Node3D
class_name MainMenu

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const PACK_OPENING_SCENE := MAIN_SCENE
const COLLECTION_SCENE := MAIN_SCENE
const GAME_TABLE_SCENE := MAIN_SCENE
const PISKEL_TOOL_SCENE := "res://scenes/ui/PiskelTool.tscn"
const RESET_SAVE_FILES := [
	"battle_deck.cfg",
	"card_upgrades.cfg",
	"collection.json",
	"currency.cfg",
	"settings.cfg"
]

@onready var pack_opening_button: Button = %PackOpeningButton
@onready var collection_button: Button = %CollectionButton
@onready var game_table_button: Button = %GameTableButton
@onready var piskel_tool_button: Button = %PiskelToolButton
@onready var settings_button: Button = %SettingsButton
@onready var reset_button: Button = %ResetButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: SettingsMenu = %SettingsMenu
@onready var reset_confirmation: ConfirmationDialog = %ResetConfirmation


func _ready() -> void:
	pack_opening_button.pressed.connect(_change_scene.bind(PACK_OPENING_SCENE))
	collection_button.pressed.connect(_change_scene.bind(COLLECTION_SCENE))
	game_table_button.pressed.connect(_change_scene.bind(GAME_TABLE_SCENE))
	piskel_tool_button.pressed.connect(_change_scene.bind(PISKEL_TOOL_SCENE))
	settings_button.pressed.connect(_open_settings)
	reset_button.pressed.connect(_open_reset_confirmation)
	reset_confirmation.confirmed.connect(_reset_game_data)
	settings_menu.closed.connect(_on_settings_closed)
	quit_button.pressed.connect(Callable(get_tree(), "quit"))
	if not NetworkManager.lobby_state_changed.is_connected(_on_online_lobby_state_changed):
		NetworkManager.lobby_state_changed.connect(_on_online_lobby_state_changed)
	if NetworkManager.has_active_session():
		call_deferred("_change_scene", MAIN_SCENE)


func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _unhandled_input(event: InputEvent) -> void:
	if settings_menu.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		settings_menu.close()


func _open_settings() -> void:
	settings_menu.open()


func _open_reset_confirmation() -> void:
	reset_confirmation.popup_centered()


func _reset_game_data() -> void:
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		push_error("Could not open user save directory for reset.")
		return

	for file_name in RESET_SAVE_FILES:
		if user_dir.file_exists(file_name):
			var error := user_dir.remove(file_name)
			if error != OK:
				push_error("Could not delete save file: %s" % file_name)

	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	CardUpgradeManager.upgrades.clear()
	GameCurrency.coins = 20
	SettingsManager.frame_limit = 60
	SettingsManager.fullscreen = false
	SettingsManager.scale_3d = 1.0
	SettingsManager.master_volume = 1.0
	SettingsManager.music_volume = 1.0
	SettingsManager.sfx_volume = 1.0
	SettingsManager.apply_settings()

	reset_button.grab_focus()


func _on_settings_closed() -> void:
	settings_button.grab_focus()


func _on_online_lobby_state_changed() -> void:
	# Accepting a Steam invite can happen from the main menu. Move into the hub;
	# GameTable will detect the active lobby and open its lobby overlay.
	if NetworkManager.current_lobby_id > 0:
		_change_scene(MAIN_SCENE)
