extends Control
class_name MainMenu

const PACK_OPENING_SCENE := "res://scenes/ui/PackOpeningScreen.tscn"
const COLLECTION_SCENE := "res://scenes/ui/CollectionScreen.tscn"
const GAME_TABLE_SCENE := "res://scenes/table/GameTable.tscn"

@onready var pack_opening_button: Button = %PackOpeningButton
@onready var collection_button: Button = %CollectionButton
@onready var game_table_button: Button = %GameTableButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	pack_opening_button.pressed.connect(_change_scene.bind(PACK_OPENING_SCENE))
	collection_button.pressed.connect(_change_scene.bind(COLLECTION_SCENE))
	game_table_button.pressed.connect(_change_scene.bind(GAME_TABLE_SCENE))
	quit_button.pressed.connect(Callable(get_tree(), "quit"))


func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
