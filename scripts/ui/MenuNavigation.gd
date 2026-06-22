extends CanvasLayer
class_name MenuNavigation

const MAIN_MENU_SCENE := "res://scenes/main/MainMenu.tscn"

@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	menu_button.pressed.connect(_go_to_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_to_main_menu()


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
