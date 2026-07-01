extends Control
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
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	pack_opening_button.pressed.connect(_change_scene.bind(PACK_OPENING_SCENE))
	collection_button.pressed.connect(_change_scene.bind(COLLECTION_SCENE))
	game_table_button.pressed.connect(_change_scene.bind(GAME_TABLE_SCENE))
	piskel_tool_button.pressed.connect(_change_scene.bind(PISKEL_TOOL_SCENE))
	settings_button.pressed.connect(_open_settings)
	settings_menu.closed.connect(_on_settings_closed)
	quit_button.pressed.connect(Callable(get_tree(), "quit"))


func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _unhandled_input(event: InputEvent) -> void:
	if settings_menu.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		settings_menu.close()


func _open_settings() -> void:
	settings_menu.open()


func _on_settings_closed() -> void:
	settings_button.grab_focus()
