extends Node

var checks := 0
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	print(("PASS " if condition else "FAIL ") + description)


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Use isolated settings to protect the player's character.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	PlaytimeManager.complete_encounter()
	SettingsManager.set_fullscreen(false)
	SettingsManager.set_character_appearance(CharacterAppearance.DEFAULT)
	SettingsManager.character_creation_completed = false
	SettingsManager.save_settings()
	get_tree().root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	var button := table.mode_buttons.get_node("MultiplayerButton") as Table3DButton
	button.pressed.emit()
	var editor := table.multiplayer_character_customizer
	check(is_instance_valid(editor) and editor.visible, "first actual Multiplayer click opens the character editor")
	check(not table.matchmaking_screen.visible, "lobby stays closed until the character is applied")
	check(get_tree().paused and not main._can_turn(), "editor blocks background gameplay and camera controls")
	check(editor.layer > 128 and editor.process_mode == Node.PROCESS_MODE_ALWAYS, "editor remains above camera filters and works while the hub is paused")
	button.pressed.emit()
	check(table.multiplayer_character_customizer == editor, "repeated clicks cannot create duplicate editors")
	await _capture("multiplayer-first-character.png")
	var original := SettingsManager.get_character_appearance()
	editor.face_next.pressed.emit()
	editor.eye_picker.color_changed.emit(Color.html("22aaff"))
	editor.cancel_button.pressed.emit()
	check(not editor.visible and not get_tree().paused, "cancel closes the editor and restores hub processing")
	check(not SettingsManager.character_creation_completed, "cancel does not confirm character creation")
	check(SettingsManager.get_character_appearance() == original, "cancel discards appearance changes")
	check(not table.matchmaking_screen.visible and table.mode_buttons.visible, "cancel remains at the multiplayer entry button")
	SettingsManager.load_settings()
	check(not SettingsManager.character_creation_completed, "cancel also remains unconfirmed after settings reload")
	button.pressed.emit()
	check(editor.visible and editor._draft == original, "another Multiplayer click reopens the editor with the saved appearance")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	editor._input(escape)
	check(not editor.visible and not get_tree().paused and not main.pause_menu.visible, "Escape cancels creation without opening Pause")
	check(not SettingsManager.character_creation_completed and not table.matchmaking_screen.visible, "Escape leaves multiplayer blocked until Apply")
	button.pressed.emit()
	check(editor.visible, "editor appears again after Escape cancellation")
	check(editor._draft == CharacterAppearance.DEFAULT, "unchanged defaults can be explicitly confirmed")
	editor.apply_button.pressed.emit()
	check(SettingsManager.character_creation_completed, "Apply confirms creation even when defaults have not changed")
	check(not editor.visible and not get_tree().paused, "Apply closes the editor and releases its pause")
	check(table.matchmaking_screen.visible and table._table_state == GameTable.TableState.ONLINE_LOBBY, "Apply continues directly to the multiplayer lobby")
	SettingsManager.character_creation_completed = false
	SettingsManager.load_settings()
	check(SettingsManager.character_creation_completed, "confirmation survives settings reload")
	var fresh_settings := preload("res://scripts/autoload/SettingsManager.gd").new()
	fresh_settings.load_settings()
	check(fresh_settings.character_creation_completed, "a fresh settings instance restores confirmation after restart")
	fresh_settings.free()
	SaveSlots.select_slot(2)
	check(SettingsManager.character_creation_completed, "switching save slots does not repeat character creation")
	table.matchmaking_screen.back_button.pressed.emit()
	button.pressed.emit()
	check(table.matchmaking_screen.visible and not editor.visible and not get_tree().paused, "subsequent Multiplayer clicks open the lobby directly")
	table.matchmaking_screen.back_button.pressed.emit()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	table = main.get_node("ScenePivot/GameTable") as GameTable
	button = table.mode_buttons.get_node("MultiplayerButton") as Table3DButton
	button.pressed.emit()
	check(table.matchmaking_screen.visible and not is_instance_valid(table.multiplayer_character_customizer), "a fresh hub skips the editor after saved confirmation")
	table.matchmaking_screen.back_button.pressed.emit()
	var config := ConfigFile.new()
	config.load(SettingsManager.CONFIG_PATH)
	config.erase_section_key(SettingsManager.SECTION, "character_creation_completed")
	config.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	check(not SettingsManager.character_creation_completed, "legacy settings without confirmation still require explicit Apply")
	button.pressed.emit()
	check(table.multiplayer_character_customizer.visible, "legacy appearance alone does not bypass first-time creation")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not get_tree().paused, "leaving a scene during creation cannot leave the next scene paused")
	var manual_editor := CharacterCustomizer.new()
	add_child(manual_editor)
	manual_editor.open()
	manual_editor.apply_button.pressed.emit()
	check(SettingsManager.character_creation_completed, "applying through the ordinary main-menu editor also completes creation")
	manual_editor.queue_free()
	await get_tree().process_frame
	print("MULTIPLAYER_CHARACTER_CREATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in range(4):
		await RenderingServer.frame_post_draw
	var directory := "res://docs/validation/character-customization"
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_tree().root.get_texture().get_image().save_png(directory.path_join(filename)) == OK, "saved first-time editor capture")
