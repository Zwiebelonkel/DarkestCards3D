extends Node

signal satan_voice_settings_changed
signal microphone_test_state_changed(is_active: bool)
signal presentation_settings_changed
signal cheat_rarities_changed

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULT_FRAME_LIMIT := 60
const DEFAULT_LANGUAGE := "de"
const DEFAULT_FULLSCREEN := true
const DEFAULT_DAMAGE_NUMBERS_ENABLED := true
const DEFAULT_TURN_ARROWS_ENABLED := true
const DEFAULT_SCALE_3D := 1.0
const DEFAULT_MASTER_VOLUME := 0.3
const DEFAULT_MUSIC_VOLUME := 0.3
const DEFAULT_SFX_VOLUME := 0.3
const DEFAULT_SATAN_VOICE_ENABLED := false
const DEFAULT_SATAN_VOICE_PITCH := 0.62
const DEFAULT_SATAN_VOICE_VOLUME := 0.3
const DEFAULT_MICROPHONE_GAIN := 1.0
const MIN_MICROPHONE_GAIN := 0.0
const MAX_MICROPHONE_GAIN := 5.0
const SATAN_VOICE_CHAT_ENABLED_KEY := "satan_voice_chat_enabled"

var frame_limit := DEFAULT_FRAME_LIMIT
var language := DEFAULT_LANGUAGE
var fullscreen := DEFAULT_FULLSCREEN
var damage_numbers_enabled := DEFAULT_DAMAGE_NUMBERS_ENABLED
var turn_arrows_enabled := DEFAULT_TURN_ARROWS_ENABLED
var scale_3d := DEFAULT_SCALE_3D
var master_volume := DEFAULT_MASTER_VOLUME
var music_volume := DEFAULT_MUSIC_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
var satan_voice_enabled := DEFAULT_SATAN_VOICE_ENABLED
var satan_voice_pitch := DEFAULT_SATAN_VOICE_PITCH
var satan_voice_volume := DEFAULT_SATAN_VOICE_VOLUME
var microphone_gain := DEFAULT_MICROPHONE_GAIN
var microphone_test_active := false
var _cheat_enabled_rarities: Array[String] = CardDatabase.REWARD_RARITIES.duplicate()


func _ready() -> void:
	load_settings()
	apply_settings()


func set_frame_limit(value: int) -> void:
	frame_limit = maxi(value, 0)
	Engine.max_fps = frame_limit
	save_settings()


func set_language(value: String) -> void:
	language = _supported_language(value)
	Localization.set_locale(language)
	save_settings()


func _supported_language(value: String) -> String:
	var normalized := value.to_lower().replace("-", "_").get_slice("_", 0)
	return normalized if normalized in Localization.SUPPORTED_LOCALES else "en"


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()


func set_scale_3d(value: float) -> void:
	scale_3d = clampf(value, 0.5, 2.0)
	get_tree().root.scaling_3d_scale = scale_3d
	save_settings()


func set_damage_numbers_enabled(enabled: bool) -> void:
	if damage_numbers_enabled == enabled:
		return
	damage_numbers_enabled = enabled
	save_settings()
	presentation_settings_changed.emit()


func set_turn_arrows_enabled(enabled: bool) -> void:
	if turn_arrows_enabled == enabled:
		return
	turn_arrows_enabled = enabled
	save_settings()
	presentation_settings_changed.emit()


func is_cheat_rarity_enabled(rarity: String) -> bool:
	return _cheat_enabled_rarities.has(rarity.to_lower().strip_edges())


func set_cheat_rarity_enabled(rarity: String, enabled: bool) -> bool:
	var normalized := rarity.to_lower().strip_edges()
	if not CardDatabase.REWARD_RARITIES.has(normalized):
		return false
	if is_cheat_rarity_enabled(normalized) == enabled:
		return true
	if not enabled and _cheat_enabled_rarities.size() <= 1:
		return false
	if enabled:
		_cheat_enabled_rarities.append(normalized)
	else:
		_cheat_enabled_rarities.erase(normalized)
	_sync_cheat_rarities()
	save_settings()
	return true


func _load_cheat_rarities(value: Variant) -> void:
	_cheat_enabled_rarities.clear()
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			if not entry is String:
				continue
			var rarity := str(entry).to_lower().strip_edges()
			if CardDatabase.REWARD_RARITIES.has(rarity) and not _cheat_enabled_rarities.has(rarity):
				_cheat_enabled_rarities.append(rarity)
	if _cheat_enabled_rarities.is_empty():
		_cheat_enabled_rarities.assign(CardDatabase.REWARD_RARITIES)
	_sync_cheat_rarities()


func _sync_cheat_rarities() -> void:
	CardDatabase.set_cheat_reward_rarities(_cheat_enabled_rarities)
	cheat_rarities_changed.emit()


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


func set_satan_voice_enabled(enabled: bool) -> void:
	satan_voice_enabled = enabled
	save_settings()
	satan_voice_settings_changed.emit()


func set_satan_voice_pitch(value: float) -> void:
	satan_voice_pitch = clampf(value, 0.35, 0.9)
	save_settings()
	satan_voice_settings_changed.emit()


func set_satan_voice_volume(value: float) -> void:
	satan_voice_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("SatanVoice", satan_voice_volume)
	save_settings()
	satan_voice_settings_changed.emit()


func set_microphone_gain(value: float) -> void:
	microphone_gain = clampf(value, MIN_MICROPHONE_GAIN, MAX_MICROPHONE_GAIN)
	save_settings()
	satan_voice_settings_changed.emit()


func set_microphone_test_active(is_active: bool) -> void:
	if microphone_test_active == is_active:
		return
	microphone_test_active = is_active
	microphone_test_state_changed.emit(microphone_test_active)


func apply_settings() -> void:
	_sync_cheat_rarities()
	Localization.set_locale(language)
	Engine.max_fps = frame_limit
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().root.scaling_3d_scale = scale_3d
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("SatanVoice", satan_voice_volume)
	satan_voice_settings_changed.emit()
	presentation_settings_changed.emit()


func load_settings() -> void:
	# These options did not exist in older profiles. Missing keys (or a new
	# profile) always restore the original visible presentation.
	damage_numbers_enabled = DEFAULT_DAMAGE_NUMBERS_ENABLED
	turn_arrows_enabled = DEFAULT_TURN_ARROWS_ENABLED
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		_load_cheat_rarities(CardDatabase.REWARD_RARITIES)
		return
	_load_cheat_rarities(config.get_value(SECTION, "cheat_enabled_rarities", CardDatabase.REWARD_RARITIES))
	frame_limit = int(config.get_value(SECTION, "frame_limit", frame_limit))
	language = _supported_language(str(config.get_value(SECTION, "language", DEFAULT_LANGUAGE)))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", fullscreen))
	damage_numbers_enabled = bool(config.get_value(SECTION, "damage_numbers_enabled", DEFAULT_DAMAGE_NUMBERS_ENABLED))
	turn_arrows_enabled = bool(config.get_value(SECTION, "turn_arrows_enabled", DEFAULT_TURN_ARROWS_ENABLED))
	scale_3d = float(config.get_value(SECTION, "scale_3d", scale_3d))
	master_volume = float(config.get_value(SECTION, "master_volume", master_volume))
	music_volume = float(config.get_value(SECTION, "music_volume", music_volume))
	sfx_volume = float(config.get_value(SECTION, "sfx_volume", sfx_volume))
	satan_voice_enabled = bool(config.get_value(
		# Deliberately do not migrate the former `satan_voice_enabled` value:
		# that opt-in covered local snippets, not live microphone transmission.
		SECTION, SATAN_VOICE_CHAT_ENABLED_KEY, DEFAULT_SATAN_VOICE_ENABLED
	))
	satan_voice_pitch = clampf(float(config.get_value(
		SECTION, "satan_voice_pitch", satan_voice_pitch
	)), 0.35, 0.9)
	satan_voice_volume = clampf(float(config.get_value(
		SECTION, "satan_voice_volume", satan_voice_volume
	)), 0.0, 1.0)
	microphone_gain = clampf(float(config.get_value(
		SECTION, "microphone_gain", microphone_gain
	)), MIN_MICROPHONE_GAIN, MAX_MICROPHONE_GAIN)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "frame_limit", frame_limit)
	config.set_value(SECTION, "language", language)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "damage_numbers_enabled", damage_numbers_enabled)
	config.set_value(SECTION, "turn_arrows_enabled", turn_arrows_enabled)
	config.set_value(SECTION, "cheat_enabled_rarities", _cheat_enabled_rarities)
	config.set_value(SECTION, "scale_3d", scale_3d)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.set_value(SECTION, SATAN_VOICE_CHAT_ENABLED_KEY, satan_voice_enabled)
	config.set_value(SECTION, "satan_voice_pitch", satan_voice_pitch)
	config.set_value(SECTION, "satan_voice_volume", satan_voice_volume)
	config.set_value(SECTION, "microphone_gain", microphone_gain)
	config.save(CONFIG_PATH)


func reset_to_defaults(save_after_reset := true) -> void:
	_cheat_enabled_rarities.assign(CardDatabase.REWARD_RARITIES)
	frame_limit = DEFAULT_FRAME_LIMIT
	language = DEFAULT_LANGUAGE
	fullscreen = DEFAULT_FULLSCREEN
	damage_numbers_enabled = DEFAULT_DAMAGE_NUMBERS_ENABLED
	turn_arrows_enabled = DEFAULT_TURN_ARROWS_ENABLED
	scale_3d = DEFAULT_SCALE_3D
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	satan_voice_enabled = DEFAULT_SATAN_VOICE_ENABLED
	satan_voice_pitch = DEFAULT_SATAN_VOICE_PITCH
	satan_voice_volume = DEFAULT_SATAN_VOICE_VOLUME
	microphone_gain = DEFAULT_MICROPHONE_GAIN
	apply_settings()
	if save_after_reset:
		save_settings()


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(value, 0.0001, 1.0)))
	AudioServer.set_bus_mute(index, value <= 0.0)
