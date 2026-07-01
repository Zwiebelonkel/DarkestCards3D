extends Node

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"

var frame_limit := 60
var fullscreen := false
var scale_3d := 1.0
var master_volume := 1.0
var music_volume := 1.0
var sfx_volume := 1.0


func _ready() -> void:
	load_settings()
	apply_settings()


func set_frame_limit(value: int) -> void:
	frame_limit = maxi(value, 0)
	Engine.max_fps = frame_limit
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()


func set_scale_3d(value: float) -> void:
	scale_3d = clampf(value, 0.5, 2.0)
	get_tree().root.scaling_3d_scale = scale_3d
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("Master", master_volume)
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("Music", music_volume)
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("SFX", sfx_volume)
	save_settings()


func apply_settings() -> void:
	Engine.max_fps = frame_limit
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().root.scaling_3d_scale = scale_3d
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	frame_limit = int(config.get_value(SECTION, "frame_limit", frame_limit))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", fullscreen))
	scale_3d = float(config.get_value(SECTION, "scale_3d", scale_3d))
	master_volume = float(config.get_value(SECTION, "master_volume", master_volume))
	music_volume = float(config.get_value(SECTION, "music_volume", music_volume))
	sfx_volume = float(config.get_value(SECTION, "sfx_volume", sfx_volume))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "frame_limit", frame_limit)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "scale_3d", scale_3d)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.save(CONFIG_PATH)


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(value, 0.0001, 1.0)))
	AudioServer.set_bus_mute(index, value <= 0.0)
