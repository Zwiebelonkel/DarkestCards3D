extends Control
class_name SettingsMenu

signal closed

const MICROPHONE_TEST_CONTROLLER_SCRIPT := preload(
	"res://scripts/ui/MicrophoneTestController.gd"
)
const SETTINGS_CONTROL_OUTLINES := preload("res://scripts/ui/SettingsControlOutlines.gd")

@onready var frame_limit_spin_box: SpinBox = %FrameLimitSpinBox
@onready var language_option_button: OptionButton = %LanguageOptionButton
@onready var settings_panel: PanelContainer = %PanelContainer
@onready var fullscreen_check_box: CheckBox = %FullscreenCheckBox
@onready var damage_numbers_check_box: CheckBox = %DamageNumbersCheckBox
@onready var turn_arrows_check_box: CheckBox = %TurnArrowsCheckBox
@onready var scale_3d_slider: HSlider = %Scale3DSlider
@onready var scale_3d_value_label: Label = %Scale3DValueLabel
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var satan_voice_enabled_check_box: CheckBox = %SatanVoiceEnabledCheckBox
@onready var satan_voice_pitch_slider: HSlider = %SatanVoicePitchSlider
@onready var satan_voice_pitch_value: Label = %SatanVoicePitchValue
@onready var microphone_gain_slider: HSlider = %MicrophoneGainSlider
@onready var microphone_gain_value: Label = %MicrophoneGainValue
@onready var satan_voice_volume_slider: HSlider = %SatanVoiceVolumeSlider
@onready var satan_voice_volume_value: Label = %SatanVoiceVolumeValue
@onready var mic_test_level_meter: ProgressBar = %MicTestLevelMeter
@onready var mic_test_level_value: Label = %MicTestLevelValue
@onready var mic_test_status_label: Label = %MicTestStatusLabel
@onready var mic_test_start_button: Button = %MicTestStartButton
@onready var mic_test_monitor_button: Button = %MicTestMonitorButton
@onready var mic_test_stop_button: Button = %MicTestStopButton
@onready var mic_test_satan_portrait: SatanVoicePortrait = %MicTestSatanPortrait
@onready var mic_test_satan_state_label: Label = %MicTestSatanStateLabel
@onready var mic_test_satan_hint_label: Label = %MicTestSatanHintLabel
@onready var close_button: Button = %CloseButton
var cheats_toggle: Button
var cheats_actions: VBoxContainer
var cheat_level_button: Button
var cheat_story_level_button: Button
var cheat_coins_button: Button
var cheat_starting_hand_button: Button
var cheat_access_keys_button: Button
var cheat_weed_button: Button
var cheat_characters_button: Button
var cheat_brain_timer_button: Button
var cheat_rarity_check_boxes: Dictionary = {}
var cheat_status: Label

var _microphone_test: MicrophoneTestController = null
var _cheat_status_source := ""
var _cheat_status_arguments: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_cheats_section()
	for locale: String in Localization.SUPPORTED_LOCALES:
		language_option_button.add_item(str(Localization.LANGUAGE_NAMES[locale]))
	language_option_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_option_button.item_selected.connect(_on_language_selected)
	Localization.locale_changed.connect(_on_locale_changed)
	SETTINGS_CONTROL_OUTLINES.apply_to(self)
	_fit_slider_rows()
	resized.connect(_update_settings_panel_size)
	_update_settings_panel_size()
	_microphone_test = MICROPHONE_TEST_CONTROLLER_SCRIPT.new()
	_microphone_test.name = "MicrophoneTestController"
	add_child(_microphone_test)
	_populate_from_settings()
	frame_limit_spin_box.value_changed.connect(func(value: float): SettingsManager.set_frame_limit(int(value)))
	fullscreen_check_box.toggled.connect(SettingsManager.set_fullscreen)
	damage_numbers_check_box.toggled.connect(SettingsManager.set_damage_numbers_enabled)
	turn_arrows_check_box.toggled.connect(SettingsManager.set_turn_arrows_enabled)
	SettingsManager.presentation_settings_changed.connect(_refresh_presentation_options)
	SettingsManager.character_appearance_changed.connect(_refresh_microphone_avatar)
	scale_3d_slider.value_changed.connect(_set_scale_3d)
	master_slider.value_changed.connect(SettingsManager.set_master_volume)
	music_slider.value_changed.connect(SettingsManager.set_music_volume)
	sfx_slider.value_changed.connect(SettingsManager.set_sfx_volume)
	satan_voice_enabled_check_box.toggled.connect(_set_satan_voice_enabled)
	satan_voice_pitch_slider.value_changed.connect(_set_satan_voice_pitch)
	microphone_gain_slider.value_changed.connect(_set_microphone_gain)
	satan_voice_volume_slider.value_changed.connect(_set_satan_voice_volume)
	mic_test_start_button.pressed.connect(_start_microphone_test)
	mic_test_monitor_button.pressed.connect(_toggle_live_microphone_test)
	mic_test_stop_button.pressed.connect(_stop_microphone_test)
	close_button.pressed.connect(close)
	cheats_toggle.toggled.connect(func(expanded: bool) -> void: cheats_actions.visible = expanded)
	cheat_level_button.pressed.connect(_cheat_level_up)
	cheat_story_level_button.pressed.connect(_cheat_story_level_up)
	cheat_coins_button.pressed.connect(_cheat_add_coins)
	cheat_starting_hand_button.pressed.connect(_cheat_unlock_starting_hand)
	cheat_access_keys_button.pressed.connect(_cheat_grant_access_keys)
	cheat_weed_button.pressed.connect(_cheat_drop_weed)
	cheat_characters_button.pressed.connect(_cheat_unlock_characters)
	cheat_brain_timer_button.pressed.connect(_cheat_reset_brain_timer)
	SettingsManager.cheat_rarities_changed.connect(_refresh_cheat_rarities)
	_refresh_cheat_controls()
	visibility_changed.connect(_on_visibility_changed)
	_refresh_microphone_test_ui()
	_on_locale_changed()


func _process(_delta: float) -> void:
	if visible:
		_refresh_microphone_test_ui()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	visible = true
	_populate_from_settings()
	cheat_status.text = ""
	_cheat_status_source = ""
	_cheat_status_arguments.clear()
	_refresh_cheat_controls()
	language_option_button.grab_focus()


func close() -> void:
	_shutdown_microphone_test()
	visible = false
	closed.emit()


func _populate_from_settings() -> void:
	_refresh_microphone_avatar()
	language_option_button.select(Localization.SUPPORTED_LOCALES.find(Localization.get_locale()))
	frame_limit_spin_box.set_value_no_signal(SettingsManager.frame_limit)
	fullscreen_check_box.set_pressed_no_signal(SettingsManager.fullscreen)
	_refresh_presentation_options()
	scale_3d_slider.set_value_no_signal(SettingsManager.scale_3d)
	master_slider.set_value_no_signal(SettingsManager.master_volume)
	music_slider.set_value_no_signal(SettingsManager.music_volume)
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume)
	satan_voice_enabled_check_box.set_pressed_no_signal(SettingsManager.satan_voice_enabled)
	satan_voice_pitch_slider.set_value_no_signal(SettingsManager.satan_voice_pitch)
	microphone_gain_slider.min_value = SettingsManager.MIN_MICROPHONE_GAIN
	microphone_gain_slider.max_value = SettingsManager.MAX_MICROPHONE_GAIN
	microphone_gain_slider.set_value_no_signal(SettingsManager.microphone_gain)
	satan_voice_volume_slider.max_value = SettingsManager.MAX_SATAN_VOICE_VOLUME
	satan_voice_volume_slider.set_value_no_signal(SettingsManager.satan_voice_volume)
	_update_scale_3d_label(SettingsManager.scale_3d)
	_update_satan_voice_labels()
	_update_satan_voice_controls(SettingsManager.satan_voice_enabled)
	frame_limit_spin_box.suffix = Localization.text(" FPS (0 = unlimited)")


func _on_language_selected(index: int) -> void:
	SettingsManager.set_language(Localization.SUPPORTED_LOCALES[index])


func _refresh_presentation_options() -> void:
	damage_numbers_check_box.set_pressed_no_signal(SettingsManager.damage_numbers_enabled)
	turn_arrows_check_box.set_pressed_no_signal(SettingsManager.turn_arrows_enabled)


func _on_locale_changed(_locale: String = "") -> void:
	language_option_button.select(Localization.SUPPORTED_LOCALES.find(Localization.get_locale()))
	frame_limit_spin_box.suffix = Localization.text(" FPS (0 = unlimited)")
	cheat_status.text = Localization.format_text(_cheat_status_source, _cheat_status_arguments) if not _cheat_status_arguments.is_empty() else Localization.text(_cheat_status_source)
	_refresh_cheat_rarities()
	_refresh_microphone_test_ui()
	_refresh_package_button()


func _set_cheat_status(source: String, arguments: Array = []) -> void:
	_cheat_status_source = source
	_cheat_status_arguments = arguments.duplicate()
	cheat_status.text = Localization.format_text(source, arguments) if not arguments.is_empty() else Localization.text(source)


func _set_scale_3d(value: float) -> void:
	SettingsManager.set_scale_3d(value)
	_update_scale_3d_label(value)


func _fit_slider_rows() -> void:
	# Let the controls use the panel width instead of relying on the pitch
	# row's former oversized gap to establish the scroll content minimum size.
	var content := $CenterContainer/PanelContainer/ScrollContainer/MarginContainer as MarginContainer
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slider: HSlider in [satan_voice_pitch_slider, microphone_gain_slider, satan_voice_volume_slider]:
		var row := slider.get_parent() as HBoxContainer
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)


func _build_cheats_section() -> void:
	var column := $CenterContainer/PanelContainer/ScrollContainer/MarginContainer/VBoxContainer as VBoxContainer
	var section := VBoxContainer.new()
	section.name = "CheatsSection"
	section.add_theme_constant_override("separation", 8)
	column.add_child(section)
	column.move_child(section, column.get_node("SatanVoiceSeparator").get_index())
	section.add_child(HSeparator.new())
	cheats_toggle = _make_cheat_button("CheatsToggle", "Cheats", section)
	cheats_toggle.add_theme_font_size_override("font_size", 20)
	cheats_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cheats_toggle.toggle_mode = true
	cheats_actions = VBoxContainer.new()
	cheats_actions.name = "CheatsActions"
	cheats_actions.add_theme_constant_override("separation", 8)
	cheats_actions.hide()
	section.add_child(cheats_actions)
	cheat_level_button = _make_cheat_button("CheatLevelButton", "Level +1", cheats_actions)
	cheat_level_button.tooltip_text = "Steigt um ein Level auf, inklusive des normalen Levelbonus."
	cheat_story_level_button = _make_cheat_button("CheatStoryLevelButton", "Story-Level +1", cheats_actions)
	cheat_coins_button = _make_cheat_button("CheatCoinsButton", "+50 Soul Coins", cheats_actions)
	cheat_starting_hand_button = _make_cheat_button("CheatStartingHandButton", "Startdeck-Karten freischalten", cheats_actions)
	cheat_starting_hand_button.tooltip_text = "Erhält Starthand I–V und schaltet alle fünf Startplätze frei."
	cheat_access_keys_button = _make_cheat_button("CheatAccessKeysButton", "Alle Access Keys erhalten", cheats_actions)
	cheat_weed_button = _make_cheat_button("CheatWeedButton", "Weed-Paket fallen lassen", cheats_actions)
	_build_cheat_rarities()
	cheat_characters_button = _make_cheat_button("CheatCharactersButton", "Alle Charaktere freischalten", cheats_actions)
	cheat_characters_button.tooltip_text = "Befreit alle Charaktere und öffnet ihre Bereiche. Dialogfortschritt bleibt erhalten."
	cheat_brain_timer_button = _make_cheat_button("CheatBrainTimerButton", "Brain Timer zurücksetzen", cheats_actions)
	cheat_brain_timer_button.tooltip_text = "Setzt Spielzeit und Satan-Szene zurück, damit sie erneut ausgelöst werden kann."
	cheat_status = Label.new()
	cheat_status.name = "CheatStatus"
	cheat_status.add_theme_font_override("font", preload("res://fonts/VCR_OSD_MONO_1.001.ttf"))
	cheat_status.add_theme_font_size_override("font_size", 14)
	cheat_status.add_theme_color_override("font_color", Color(0.85, 0.72, 0.44))
	cheat_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cheats_actions.add_child(cheat_status)


func _build_cheat_rarities() -> void:
	var title := Label.new()
	title.name = "CheatRaritiesLabel"
	title.text = "Seltenheiten für Drops"
	title.add_theme_font_override("font", preload("res://fonts/VCR_OSD_MONO_1.001.ttf"))
	cheats_actions.add_child(title)
	var hint := Label.new()
	hint.name = "CheatRaritiesHint"
	hint.text = "Zufällige Kartenbelohnungen verwenden nur angehakte Seltenheiten. Mindestens eine bleibt aktiv."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", preload("res://fonts/VCR_OSD_MONO_1.001.ttf"))
	hint.add_theme_font_size_override("font_size", 14)
	cheats_actions.add_child(hint)
	var grid := GridContainer.new()
	grid.name = "CheatRaritiesGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	cheats_actions.add_child(grid)
	for rarity: String in CardDatabase.REWARD_RARITIES:
		var check_box := CheckBox.new()
		check_box.name = "CheatRarity_" + rarity
		check_box.custom_minimum_size.y = 34
		check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check_box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		check_box.add_theme_font_override("font", preload("res://fonts/VCR_OSD_MONO_1.001.ttf"))
		var color := RarityEffectsData.get_color(rarity).lightened(0.3)
		check_box.add_theme_color_override("font_color", color)
		check_box.add_theme_color_override("font_pressed_color", color)
		check_box.add_theme_color_override("font_hover_color", color.lightened(0.2))
		check_box.toggled.connect(_on_cheat_rarity_toggled.bind(rarity))
		grid.add_child(check_box)
		cheat_rarity_check_boxes[rarity] = check_box


func _on_cheat_rarity_toggled(enabled: bool, rarity: String) -> void:
	if not SettingsManager.set_cheat_rarity_enabled(rarity, enabled):
		_set_cheat_status("Mindestens eine Seltenheit muss aktiviert bleiben.")
	_refresh_cheat_rarities()


func _refresh_cheat_rarities() -> void:
	for rarity: String in cheat_rarity_check_boxes:
		var check_box := cheat_rarity_check_boxes[rarity] as CheckBox
		check_box.text = Localization.rarity_name(rarity)
		check_box.set_pressed_no_signal(SettingsManager.is_cheat_rarity_enabled(rarity))


func _make_cheat_button(node_name: String, text: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_override("font", preload("res://fonts/VCR_OSD_MONO_1.001.ttf"))
	parent.add_child(button)
	return button


func _cheat_level_up() -> void:
	# Use normal progression, including its level bonus, while retaining the
	# current XP amount inside the next level. Thresholds only grow with level.
	var reward := GameCurrency.add_xp(GameCurrency.get_xp_required())
	_set_cheat_status("Level %d erreicht · +%s Soul Coins Levelbonus", [GameCurrency.get_level(), GameCurrency.format_coins(float(reward.get("coins_awarded", 0)))])


func _cheat_story_level_up() -> void:
	var next := GameCurrency.story_completed_level + 1
	if GameCurrency.award_story_win(next).is_empty():
		return
	_refresh_cheat_controls()
	cheat_status.text = "Story-Level %d abgeschlossen" % GameCurrency.story_completed_level


func _cheat_add_coins() -> void:
	var before := GameCurrency.get_coins()
	GameCurrency.add_coins(50.0)
	_set_cheat_status("+%s Soul Coins · Kontostand: %s", [GameCurrency.format_coins(GameCurrency.get_coins() - before, true), GameCurrency.format_coins()])


func _cheat_drop_weed() -> void:
	GameCurrency.request_admin_weed_drop()
	_set_cheat_status("Das Paket fällt, sobald du zum freien Spieltisch zurückkehrst.")


func _cheat_grant_access_keys() -> void:
	var instances: Array[Dictionary] = []
	for card: Dictionary in CardDatabase.get_all_cards():
		var card_id := str(card.get("id", ""))
		if CardData.is_access_key(card) and CollectionManager.get_amount(card_id) == 0:
			instances.append(CardData.create_instance(card_id))
	var result := CollectionManager.add_card_instances(instances)
	if result.get("success", false):
		_set_cheat_status("Alle Access Keys erhalten · Schlüsselablage aktualisiert")
	else:
		_set_cheat_status("Access Keys konnten nicht gespeichert werden.")


func _cheat_unlock_characters() -> void:
	if GameCurrency.cheat_unlock_all_characters():
		_set_cheat_status("Alle Charaktere freigeschaltet · Dialoge bleiben erhalten")
	else:
		_set_cheat_status("Charaktere konnten nicht freigeschaltet werden.")


func _cheat_reset_brain_timer() -> void:
	if PlaytimeManager.reset_timer() == OK:
		_set_cheat_status("Brain Timer und Satan-Szene zurückgesetzt.")
	else:
		_set_cheat_status("Brain Timer zurückgesetzt, konnte aber nicht gespeichert werden.")


func _cheat_unlock_starting_hand() -> void:
	for card_id in CollectionManager.STARTING_HAND_CARD_IDS:
		if CollectionManager.get_amount(card_id) == 0:
			CollectionManager.add_card(card_id)
	get_tree().call_group("collection_screens", "refresh_starting_hand_unlocks")
	_refresh_cheat_controls()
	_set_cheat_status("Alle 5 Startplätze freigeschaltet · Starthand I–V erhalten")


func _refresh_cheat_controls() -> void:
	cheat_story_level_button.disabled = not GameCurrency.is_story_level_unlocked(GameCurrency.story_completed_level + 1)
	cheat_starting_hand_button.disabled = CollectionManager.get_starting_hand_slot_count() >= 5
	_refresh_package_button()
	_refresh_cheat_rarities()


func _refresh_package_button() -> void:
	var labels := {"weed": "Weed-Paket fallen lassen", "cocaine": "Kokain-Paket fallen lassen", "mdma": "MDMA-Paket fallen lassen"}
	cheat_weed_button.text = Localization.text(labels[GameCurrency.get_story_package_kind()])


func _update_scale_3d_label(value: float) -> void:
	scale_3d_value_label.text = "%d%%" % roundi(value * 100.0)


func _set_satan_voice_enabled(enabled: bool) -> void:
	SettingsManager.set_satan_voice_enabled(enabled)
	_update_satan_voice_controls(enabled)


func _set_satan_voice_pitch(value: float) -> void:
	SettingsManager.set_satan_voice_pitch(value)
	if _microphone_test != null:
		_microphone_test.refresh_monitor_pitch()
	_update_satan_voice_labels()


func _set_satan_voice_volume(value: float) -> void:
	SettingsManager.set_satan_voice_volume(value)
	_update_satan_voice_labels()


func _set_microphone_gain(value: float) -> void:
	SettingsManager.set_microphone_gain(value)
	_update_satan_voice_labels()


func _update_satan_voice_labels() -> void:
	satan_voice_pitch_value.text = "%d%%" % roundi(satan_voice_pitch_slider.value * 100.0)
	microphone_gain_value.text = "%d%%" % roundi(microphone_gain_slider.value * 100.0)
	satan_voice_volume_value.text = "%d%%" % roundi(satan_voice_volume_slider.value * 100.0)


func _update_satan_voice_controls(_enabled: bool) -> void:
	# Voice controls can be configured before opting in.
	satan_voice_pitch_slider.editable = true
	microphone_gain_slider.editable = true
	satan_voice_volume_slider.editable = true
	_refresh_microphone_test_ui()


func _update_settings_panel_size() -> void:
	if settings_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	settings_panel.custom_minimum_size = Vector2(
		maxf(minf(660.0, viewport_size.x - 32.0), 420.0),
		maxf(minf(680.0, viewport_size.y - 32.0), 180.0)
	)


func _start_microphone_test() -> void:
	if _microphone_test == null:
		return
	_microphone_test.start_listening()
	_refresh_microphone_test_ui()


func _toggle_live_microphone_test() -> void:
	if _microphone_test == null:
		return
	if _microphone_test.test_state == MicrophoneTestController.TestState.MONITORING:
		_microphone_test.stop_monitoring()
	else:
		_microphone_test.start_monitoring()
	_refresh_microphone_test_ui()


func _stop_microphone_test() -> void:
	if _microphone_test == null:
		return
	_microphone_test.stop_session()
	_refresh_microphone_test_ui()


func _refresh_microphone_test_ui() -> void:
	if _microphone_test == null or not is_instance_valid(_microphone_test):
		return

	var state := _microphone_test.test_state
	var is_starting := state == MicrophoneTestController.TestState.STARTING
	var is_listening := state == MicrophoneTestController.TestState.LISTENING
	var is_monitoring := state == MicrophoneTestController.TestState.MONITORING
	var is_stopping := state == MicrophoneTestController.TestState.STOPPING
	var has_live_level := is_listening or is_monitoring
	var is_active := _microphone_test.is_session_active()

	mic_test_level_meter.value = _microphone_test.input_level_db
	mic_test_level_value.text = (
		"< -60 dB"
		if has_live_level and _microphone_test.input_level_db <= -59.5
		else "%d dB" % roundi(_microphone_test.input_level_db)
		if has_live_level
		else "— dB"
	)
	mic_test_status_label.text = _microphone_test.status_text
	_update_microphone_test_satan_preview(has_live_level)

	mic_test_start_button.disabled = is_active
	mic_test_monitor_button.text = "Stop Live Test" if is_monitoring else "Live Satan Test"
	mic_test_monitor_button.disabled = is_starting or is_stopping
	mic_test_stop_button.disabled = not is_active or is_stopping


func _refresh_microphone_avatar() -> void:
	if is_instance_valid(mic_test_satan_portrait):
		# Use the saved local composite in every voice state. The portrait's
		# independent voice-level shake continues without changing image frames.
		mic_test_satan_portrait.set_character_appearance(SettingsManager.get_character_appearance())


func _update_microphone_test_satan_preview(is_active: bool) -> void:
	if (
		mic_test_satan_portrait == null
		or not is_instance_valid(mic_test_satan_portrait)
	):
		return

	if not is_active:
		mic_test_satan_portrait.set_activity(
			MicrophoneTestController.InputVoiceActivity.SILENT
		)
		mic_test_satan_portrait.set_voice_level(0.0)
		mic_test_satan_portrait.reset_shake()
		mic_test_satan_portrait.modulate = Color(0.48, 0.45, 0.47, 1.0)
		mic_test_satan_state_label.text = "MIC OFF"
		mic_test_satan_state_label.add_theme_color_override(
			"font_color",
			Color(0.56, 0.52, 0.57, 1.0)
		)
		mic_test_satan_hint_label.text = "Start the microphone test to see your character react to your voice."
		return

	var activity := _microphone_test.input_voice_activity
	var level := _microphone_test.input_voice_level
	mic_test_satan_portrait.modulate = Color.WHITE
	mic_test_satan_portrait.set_activity(activity)
	mic_test_satan_portrait.set_voice_level(
		level
		if activity != MicrophoneTestController.InputVoiceActivity.SILENT
		else 0.0
	)

	match activity:
		MicrophoneTestController.InputVoiceActivity.LOUD:
			mic_test_satan_state_label.text = "LOUD!"
			mic_test_satan_state_label.add_theme_color_override(
				"font_color",
				Color(1.0, 0.24, 0.2, 1.0)
			)
			mic_test_satan_hint_label.text = "Louder input makes your character shake more."
		MicrophoneTestController.InputVoiceActivity.SPEAKING:
			mic_test_satan_state_label.text = "SPEAKING"
			mic_test_satan_state_label.add_theme_color_override(
				"font_color",
				Color(1.0, 0.52, 0.4, 1.0)
			)
			mic_test_satan_hint_label.text = "This is how the other player sees your voice."
		_:
			mic_test_satan_state_label.text = "QUIET"
			mic_test_satan_state_label.add_theme_color_override(
				"font_color",
				Color(0.68, 0.65, 0.7, 1.0)
			)
			mic_test_satan_hint_label.text = "Speak into your microphone."


func _shutdown_microphone_test() -> void:
	if _microphone_test == null or not is_instance_valid(_microphone_test):
		return
	_microphone_test.shutdown()
	_update_microphone_test_satan_preview(false)
	_refresh_microphone_test_ui()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_shutdown_microphone_test()


func _exit_tree() -> void:
	_shutdown_microphone_test()
