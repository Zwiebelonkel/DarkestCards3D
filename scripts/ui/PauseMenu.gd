extends CanvasLayer
class_name PauseMenu

const MAIN_MENU_SCENE := "res://scenes/main/MainMenu.tscn"

@onready var panel: Control = %PausePanel
@onready var continue_button: Button = %ContinueButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var settings_menu: SettingsMenu = %SettingsMenu

var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings_menu.visible = false
	continue_button.pressed.connect(close)
	settings_button.pressed.connect(_open_settings)
	main_menu_button.pressed.connect(_go_to_main_menu)
	settings_menu.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if settings_menu.visible:
			settings_menu.close()
		elif _is_open:
			close()
		else:
			open()


func open() -> void:
	_is_open = true
	visible = true
	panel.visible = true
	get_tree().paused = true
	continue_button.grab_focus()


func close() -> void:
	_is_open = false
	visible = false
	settings_menu.visible = false
	get_tree().paused = false


func _open_settings() -> void:
	panel.visible = false
	settings_menu.open()


func _on_settings_closed() -> void:
	if _is_open:
		panel.visible = true
		settings_button.grab_focus()


func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
