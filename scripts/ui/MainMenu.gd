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
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	pack_opening_button.pressed.connect(_change_scene.bind(PACK_OPENING_SCENE))
	collection_button.pressed.connect(_change_scene.bind(COLLECTION_SCENE))
	game_table_button.pressed.connect(_change_scene.bind(GAME_TABLE_SCENE))
	piskel_tool_button.pressed.connect(_change_scene.bind(PISKEL_TOOL_SCENE))
	quit_button.pressed.connect(Callable(get_tree(), "quit"))


func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
