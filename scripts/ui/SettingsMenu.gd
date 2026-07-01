extends Control
class_name SettingsMenu

signal closed

@onready var frame_limit_spin_box: SpinBox = %FrameLimitSpinBox
@onready var fullscreen_check_box: CheckBox = %FullscreenCheckBox
@onready var scale_3d_slider: HSlider = %Scale3DSlider
@onready var scale_3d_value_label: Label = %Scale3DValueLabel
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_populate_from_settings()
	frame_limit_spin_box.value_changed.connect(func(value: float): SettingsManager.set_frame_limit(int(value)))
	fullscreen_check_box.toggled.connect(SettingsManager.set_fullscreen)
	scale_3d_slider.value_changed.connect(_set_scale_3d)
	master_slider.value_changed.connect(SettingsManager.set_master_volume)
	music_slider.value_changed.connect(SettingsManager.set_music_volume)
	sfx_slider.value_changed.connect(SettingsManager.set_sfx_volume)
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	visible = true
	_populate_from_settings()
	close_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _populate_from_settings() -> void:
	frame_limit_spin_box.set_value_no_signal(SettingsManager.frame_limit)
	fullscreen_check_box.set_pressed_no_signal(SettingsManager.fullscreen)
	scale_3d_slider.set_value_no_signal(SettingsManager.scale_3d)
	master_slider.set_value_no_signal(SettingsManager.master_volume)
	music_slider.set_value_no_signal(SettingsManager.music_volume)
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume)
	_update_scale_3d_label(SettingsManager.scale_3d)


func _set_scale_3d(value: float) -> void:
	SettingsManager.set_scale_3d(value)
	_update_scale_3d_label(value)


func _update_scale_3d_label(value: float) -> void:
	scale_3d_value_label.text = "%d%%" % roundi(value * 100.0)
