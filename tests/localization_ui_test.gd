extends Control
## Real settings and lobby UI against isolated persistence and transport-free Steam.

var count := 0
var failures := 0


func check(value: bool, description: String) -> void:
	count += 1
	if not value:
		failures += 1
		push_error("MENU FAIL: " + description)
	print(("PASS " if value else "FAIL ") + description)


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Run localization_ui_test with the isolated match feature runner.")
		get_tree().quit(1)
		return
	check(true, "isolated settings only")
	var original_language := SettingsManager.language
	var original_pitch := SettingsManager.satan_voice_pitch
	var arrows := TurnArrows.new()
	add_child(arrows)
	var texture_button := TextureButton.new()
	add_child(texture_button)
	# Exercise both textless buttons and their descendants during a real switch.
	var nested_label := Label.new()
	arrows.left_button.add_child(nested_label)
	var formatted_button := Button.new()
	add_child(formatted_button)
	var formatted_source := "Level %d erreicht · +%d Soul Coins Levelbonus"
	nested_label.text = Localization.format_text(formatted_source, [3, 4])
	formatted_button.text = nested_label.text
	arrows.left_button.tooltip_text = nested_label.text
	texture_button.tooltip_text = nested_label.text
	var menu := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate() as SettingsMenu
	add_child(menu)
	menu.open()
	menu.cheats_actions.show()
	menu._set_cheat_status("Level %d erreicht · +%d Soul Coins Levelbonus", [3, 4])
	SettingsManager.set_satan_voice_pitch(0.77)
	menu._populate_from_settings()
	var mic := menu._microphone_test
	mic._set_error_immediately("Steam is not ready. Start Steam and try the microphone test again.")
	menu._refresh_microphone_test_ui()
	for locale: String in Localization.SUPPORTED_LOCALES:
		var selected_index := Localization.SUPPORTED_LOCALES.find(locale)
		menu.language_option_button.select(selected_index)
		menu.language_option_button.item_selected.emit(selected_index)
		check(SettingsManager.language == locale and Localization.get_locale() == locale, "language applies immediately: " + locale)
		var expected := Localization.format_text(formatted_source, [3, 4])
		check(nested_label.text == expected, "labels below textless arrows refresh: " + locale)
		check(formatted_button.text == expected, "formatted text buttons refresh: " + locale)
		check(arrows.left_button.tooltip_text == expected and texture_button.tooltip_text == expected, "textless button tooltips refresh: " + locale)
		check(menu.mic_test_status_label.text == Localization.text("Steam is not ready. Start Steam and try the microphone test again."), "visible mic error refreshes: " + locale)
		check(menu.cheat_status.text == Localization.format_text("Level %d erreicht · +%d Soul Coins Levelbonus", [3, 4]), "formatted cheat status refreshes: " + locale)
		check(menu.cheats_actions.visible and is_equal_approx(SettingsManager.satan_voice_pitch, 0.77) and mic.test_state == MicrophoneTestController.TestState.ERROR, "locale preserves cheat/audio/mic state: " + locale)
		var saved := ConfigFile.new()
		saved.load(SettingsManager.CONFIG_PATH)
		check(saved.get_value("settings", "language", "") == locale, "selected language is persisted: " + locale)
	SettingsManager.language = "de"
	SettingsManager.load_settings()
	check(SettingsManager.language == "pl", "saved language reloads")
	SettingsManager.set_language("pt_BR")
	check(SettingsManager.language == "en" and Localization.get_locale() == "en", "unsupported language falls back to English")
	SettingsManager.set_language("de-DE")
	check(SettingsManager.language == "de", "supported region locale normalizes")
	menu.close()
	var matchmaking := (load("res://scenes/multiplayer/MatchmakingScreen.tscn") as PackedScene).instantiate() as Matchmaking
	add_child(matchmaking)
	NetworkManager.lobby_entries = [{"id":321, "name":"Settings", "owner_name":"Close", "players":1, "spectators":0}]
	matchmaking.open()
	matchmaking._set_status("Steam konnte die Lobby nicht erstellen (Fehler %d).", true, [12])
	for locale: String in Localization.SUPPORTED_LOCALES:
		SettingsManager.set_language(locale)
		check(matchmaking.status_label.text == Localization.format_text("Steam konnte die Lobby nicht erstellen (Fehler %d).", [12]), "network error changes language without replaying request: " + locale)
		check(matchmaking.lobby_list.get_item_text(0).begins_with("Settings") and matchmaking.lobby_list.get_item_tooltip(0).contains("Close"), "lobby and user names remain verbatim: " + locale)
	NetworkManager.current_lobby_id = 321
	NetworkManager._participants = {1:{"role":"player", "name":"Settings"}}
	var names := NetworkManager.get_lobby_member_names()
	check(names[0].contains("Settings") and names[0].contains("Gracz"), "roster translates role but preserves persona")
	NetworkManager.current_lobby_id = 0
	NetworkManager._participants.clear()
	SettingsManager.set_language("pl")
	matchmaking.hide()
	menu.open()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://localization-menus-pl.png")
	menu.close()
	SettingsManager.set_satan_voice_pitch(original_pitch)
	SettingsManager.set_language(original_language)
	NetworkManager.lobby_entries.clear()
	matchmaking.queue_free()
	menu.queue_free()
	arrows.queue_free()
	texture_button.queue_free()
	formatted_button.queue_free()
	await get_tree().process_frame
	print("LOCALIZATION_UI_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", count])
	get_tree().quit(0 if failures == 0 else 1)
