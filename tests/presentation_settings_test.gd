extends Node

const SETTINGS_SCRIPT := preload("res://scripts/autoload/SettingsManager.gd")
const SETTINGS_SCENE := preload("res://scenes/ui/SettingsMenu.tscn")
const TRANSLATED_LABELS := {
	"en": ["Show damage numbers", "Show turn arrows"],
	"de": ["Schadenszahlen anzeigen", "Drehpfeile anzeigen"],
	"es": ["Mostrar números de daño", "Mostrar flechas de giro"],
	"fr": ["Afficher les valeurs de dégâts", "Afficher les flèches de rotation"],
	"pl": ["Pokaż liczby obrażeń", "Pokaż strzałki obrotu"],
}

var checks := 0
var failures := 0
var notifications: Array[Dictionary] = []
var viewport: SubViewport
var settings: SettingsMenu


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated test runner to protect real player saves.")
		get_tree().quit(1)
		return
	var gameplay_before := _gameplay_state()
	_test_loading()
	SettingsManager.presentation_settings_changed.connect(_record_notification)
	_test_setters_and_reset()
	await _test_menu()
	check(_gameplay_state() == gameplay_before, "Presentation options, resetting settings, and locale changes preserve currency, progression, collection and deck")
	SettingsManager.presentation_settings_changed.disconnect(_record_notification)
	print("PRESENTATION_SETTINGS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_loading() -> void:
	var fresh := SETTINGS_SCRIPT.new()
	check(fresh.damage_numbers_enabled and fresh.turn_arrows_enabled, "New manager defaults both presentation options to enabled")
	fresh.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.CONFIG_PATH))
	SettingsManager.damage_numbers_enabled = false
	SettingsManager.turn_arrows_enabled = false
	SettingsManager.load_settings()
	check(SettingsManager.damage_numbers_enabled and SettingsManager.turn_arrows_enabled, "A missing config restores both enabled defaults even after a prior disabled state")
	var legacy := ConfigFile.new()
	legacy.set_value(SettingsManager.SECTION, "frame_limit", 144)
	legacy.set_value(SettingsManager.SECTION, "fullscreen", false)
	legacy.set_value(SettingsManager.SECTION, "master_volume", 0.42)
	check(legacy.save(SettingsManager.CONFIG_PATH) == OK, "Legacy settings fixture is saved inside the isolated project")
	SettingsManager.damage_numbers_enabled = false
	SettingsManager.turn_arrows_enabled = false
	SettingsManager.load_settings()
	check(SettingsManager.damage_numbers_enabled and SettingsManager.turn_arrows_enabled, "Older configs without either option keep both presentations visible")
	check(SettingsManager.frame_limit == 144 and not SettingsManager.fullscreen and is_equal_approx(SettingsManager.master_volume, 0.42), "Loading old configs preserves unrelated saved options")
	legacy.set_value(SettingsManager.SECTION, "damage_numbers_enabled", false)
	legacy.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	check(not SettingsManager.damage_numbers_enabled and SettingsManager.turn_arrows_enabled, "A saved false damage option survives while a missing arrow option defaults to true")
	legacy.erase_section_key(SettingsManager.SECTION, "damage_numbers_enabled")
	legacy.set_value(SettingsManager.SECTION, "turn_arrows_enabled", false)
	legacy.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	check(SettingsManager.damage_numbers_enabled and not SettingsManager.turn_arrows_enabled, "A saved false arrow option survives while a missing damage option defaults to true")
	SettingsManager.damage_numbers_enabled = true
	SettingsManager.turn_arrows_enabled = true
	SettingsManager.save_settings()


func _test_setters_and_reset() -> void:
	var voice_before := SettingsManager.satan_voice_enabled
	var volume_before := SettingsManager.master_volume
	SettingsManager.set_damage_numbers_enabled(false)
	check(not SettingsManager.damage_numbers_enabled and SettingsManager.turn_arrows_enabled, "Disabling damage numbers preserves enabled arrows")
	check(notifications.size() == 1 and _notification_matches_saved(notifications.back()), "Damage setter emits one zero-argument notification after persisting both options")
	SettingsManager.set_damage_numbers_enabled(false)
	SettingsManager.set_turn_arrows_enabled(true)
	check(notifications.size() == 1, "No-op presentation setters do not emit redundant notifications")
	SettingsManager.set_turn_arrows_enabled(false)
	check(not SettingsManager.damage_numbers_enabled and not SettingsManager.turn_arrows_enabled, "Both presentations can be disabled independently")
	check(notifications.size() == 2 and _notification_matches_saved(notifications.back()), "Arrow setter saves before its single notification")
	var reloaded := SETTINGS_SCRIPT.new()
	reloaded.load_settings()
	check(not reloaded.damage_numbers_enabled and not reloaded.turn_arrows_enabled, "A newly created manager restores both saved false values")
	reloaded.free()
	check(SettingsManager.satan_voice_enabled == voice_before and is_equal_approx(SettingsManager.master_volume, volume_before), "Presentation setters preserve voice opt-in and volume")
	SettingsManager.apply_settings()
	check(notifications.size() == 3 and not SettingsManager.damage_numbers_enabled and not SettingsManager.turn_arrows_enabled, "Applying unchanged settings still publishes one presentation refresh")
	SettingsManager.reset_to_defaults(false)
	check(notifications.size() == 4 and SettingsManager.damage_numbers_enabled and SettingsManager.turn_arrows_enabled, "Reset without saving restores both defaults and publishes a presentation refresh")
	check(_saved_flags() == [false, false], "Reset without saving leaves the persisted disabled choices intact")
	SettingsManager.load_settings()
	SettingsManager.reset_to_defaults()
	check(notifications.size() == 5 and _saved_flags() == [true, true], "Normal reset persists both enabled defaults and publishes once")
	SettingsManager.set_fullscreen(false)


func _test_menu() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	settings = SETTINGS_SCENE.instantiate() as SettingsMenu
	viewport.add_child(settings)
	settings.open()
	await settle()
	var damage := settings.damage_numbers_check_box
	var arrows := settings.turn_arrows_check_box
	check(damage.button_pressed and arrows.button_pressed, "Opening settings displays both loaded enabled defaults")
	for checkbox: CheckBox in [damage, arrows]:
		var outlined := true
		for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			outlined = outlined and checkbox.has_theme_icon_override(icon_name)
		check(outlined, "%s uses the existing white checkbox outlines in every state" % checkbox.name)
	var notification_count := notifications.size()
	await _click(damage)
	check(not damage.button_pressed and not SettingsManager.damage_numbers_enabled and arrows.button_pressed and SettingsManager.turn_arrows_enabled, "Actual damage checkbox click disables only damage numbers")
	check(notifications.size() == notification_count + 1 and _saved_flags() == [false, true], "Damage checkbox click persists once without a refresh feedback loop")
	await _click(arrows)
	check(not arrows.button_pressed and not SettingsManager.turn_arrows_enabled and not damage.button_pressed, "Actual arrow checkbox click independently disables arrows")
	check(notifications.size() == notification_count + 2 and _saved_flags() == [false, false], "Arrow checkbox click persists once without a refresh feedback loop")
	notification_count = notifications.size()
	SettingsManager.set_damage_numbers_enabled(true)
	check(damage.button_pressed and not arrows.button_pressed and notifications.size() == notification_count + 1, "An external setter updates the open menu without redundant notifications")
	SettingsManager.apply_settings()
	check(damage.button_pressed and not arrows.button_pressed and notifications.size() == notification_count + 2, "Applying settings synchronizes checkbox presentation without changing either option")
	settings.close()
	SettingsManager.set_turn_arrows_enabled(true)
	settings.open()
	check(damage.button_pressed and arrows.button_pressed, "Reopening settings displays choices updated while the menu was closed")
	SettingsManager.set_damage_numbers_enabled(false)
	notification_count = notifications.size()
	for locale: String in TRANSLATED_LABELS:
		SettingsManager.set_language(locale)
		await settle()
		var expected: Array = TRANSLATED_LABELS[locale]
		for index in range(2):
			var checkbox: CheckBox = [damage, arrows][index]
			check(checkbox.tr(checkbox.text) == expected[index], "%s translates %s using the current native UI locale" % [locale, checkbox.name])
			check(checkbox.get_minimum_size().x <= checkbox.size.x, "%s checkbox label fits the available menu width" % locale)
		check(not damage.button_pressed and arrows.button_pressed and notifications.size() == notification_count, "%s language switch preserves presentation choices and emits no presentation changes" % locale)
	SettingsManager.reset_to_defaults()
	check(damage.button_pressed and arrows.button_pressed, "Reset immediately updates both checkboxes in an already open menu")
	settings.close()
	settings.queue_free()
	await settle()
	SettingsManager.set_damage_numbers_enabled(false)
	SettingsManager.set_turn_arrows_enabled(false)
	check(_saved_flags() == [false, false], "Presentation options remain usable after the menu is freed")
	viewport.queue_free()
	await settle()


func _record_notification() -> void:
	notifications.append({
		"flags": [SettingsManager.damage_numbers_enabled, SettingsManager.turn_arrows_enabled],
		"saved": _saved_flags(),
	})


func _notification_matches_saved(notification: Dictionary) -> bool:
	return notification["flags"] == notification["saved"]


func _saved_flags() -> Array:
	var config := ConfigFile.new()
	if config.load(SettingsManager.CONFIG_PATH) != OK:
		return []
	return [config.get_value(SettingsManager.SECTION, "damage_numbers_enabled"), config.get_value(SettingsManager.SECTION, "turn_arrows_enabled")]


func _gameplay_state() -> Array:
	return [GameCurrency.get_coin_cents(), GameCurrency.get_level(), GameCurrency.get_xp(), CollectionManager.collection.duplicate(true), DeckManager.deck_instance_ids.duplicate()]


func _click(button: CheckBox) -> void:
	var scroll := settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer
	scroll.ensure_control_visible(button)
	await settle()
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	await settle()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
		await settle()
