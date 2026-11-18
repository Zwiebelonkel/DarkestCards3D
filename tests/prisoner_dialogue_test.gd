extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var dialog: AngelDialogue


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use an isolated project copy with redirected saves.")
		get_tree().quit(1)
		return
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	GameCurrency.set_process(false)
	GameCurrency._rescued_npcs["prisoner"] = true
	Localization.set_locale("de")
	CollectionManager.add_card("graveyard_key")
	check(CollectionManager.use_access_key("graveyard_key"), "fixture activates the real graveyard key")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0.0
	main.room_travel_duration = 0.3
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	var actor := main.get_node("GraveyardRoom/Crypt/Prisoner") as Sprite3D
	var authored_transform := actor.transform
	viewport.add_child(main)
	dialog = main.prisoner_dialogue
	var fart_audio := dialog.get_node("FartSound") as AudioStreamPlayer3D
	_move_pointer(Vector2(-50, -50))
	await _settle(0.5)
	check(dialog.actor == actor and actor.transform.is_equal_approx(authored_transform), "the authored Prisoner sprite keeps its position, orientation and scale")
	check(actor.billboard == BaseMaterial3D.BILLBOARD_DISABLED and (actor.material_override as StandardMaterial3D).billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "neither the Prisoner sprite nor its glowing-eye material uses billboard rendering")
	check(actor.hframes == 12 and actor.get("TOTAL_FRAMES") == 12, "the authored twelve-frame animation is preserved")
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "the prisoner cannot be activated remotely from the hub")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.area_id == "graveyard":
			entrance = area.door
	main._on_room_door_activated(entrance)
	check(await _wait_until(func(): return main._active_room == 2 and not main._room_transition_active), "the real doorway flight arrives in the graveyard")
	check(not dialog.interaction_enabled and not dialog.open_dialog(), "the crossing only allows approaching the grille, not a distant prisoner conversation")
	_button(MOUSE_BUTTON_LEFT, main.main_camera.unproject_position(main.crypt_gate.gate_area.global_position))
	check(await _wait_until(func(): return main._crypt_gate_close and not main._room_transition_active), "a real grille click walks to the crypt viewpoint")
	await _settle()
	var point := main.main_camera.unproject_position(dialog.npc_area.global_position)
	check(viewport.get_visible_rect().has_point(point) and dialog._pointer_hits_area(point), "the actual prisoner hit box is reachable through the grille")
	check(dialog.npc_area.global_transform.is_equal_approx(actor.global_transform), "the prisoner hit box matches the fixed authored sprite plane")
	var idle_texture := actor.texture
	actor.frame = 5
	actor.set("_frame_timer", 0.03)
	_move_pointer(point)
	dialog._update_pointer_hover()
	check(actor.texture.resource_path.ends_with("prisonerHover.png") and actor.frame == 5 and is_equal_approx(actor.get("_frame_timer"), 0.03), "hover switches to the authored animation while preserving its frame and timer")
	_move_pointer(Vector2(-50, -50))
	dialog._update_pointer_hover()
	check(actor.texture == idle_texture and actor.frame == 5, "leaving the prisoner restores the idle animation without restarting it")
	_move_pointer(point)
	await _settle(0.2)
	check(actor.texture.resource_path.ends_with("prisonerHover.png") and actor.frame != 5, "the prisoner hover animation continues playing")
	await _capture("hover")
	var cards_before := CollectionManager.collection.duplicate(true)
	var coins_before := GameCurrency.get_coin_cents()
	var files_before := _profile_files()
	var camera_before := main.main_camera.global_transform
	_button(MOUSE_BUTTON_LEFT, point)
	await _wait_until(func(): return dialog.is_dialog_open(), 1000)
	check(dialog.is_dialog_open() and dialog._is_typing() and dialog._message == "*Lacht*", "a real prisoner click starts the first authored dialog window")
	check(dialog._body_label.text == "*Lacht*" and not dialog._body_label.bbcode_enabled, "the first window keeps the requested asterisks literally")
	check(dialog._laugh_audio._laughing and dialog._laugh_audio.stream == main.graveyard_jester._laugh_audio.stream, "the prisoner uses the same speaking sample and syllable rhythm as the Jester")
	check(is_equal_approx(dialog._laugh_audio.get("pitch_offset_semitones"), main.graveyard_jester._laugh_audio.get("pitch_offset_semitones") - 3.0), "the prisoner's voice is three semitones lower than the Jester")
	check(dialog.find_children("*", "AudioStreamPlayer3D", true, false).size() == 2 and dialog.get_node_or_null("SentenceEndSound") == null, "the prisoner has voice and fart audio without the Jester's sentence-end sound")
	check(not fart_audio.playing and fart_audio.bus == &"SFX", "the fart uses the SFX setting and stays silent during the first window")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "the conversation locks turns, travel, beacon return and journal")
	_key(KEY_J)
	main.turn_arrows.turn_requested.emit(1)
	_button(MOUSE_BUTTON_RIGHT, Vector2(20, 20))
	check(main._crypt_gate_close and main._active_side == 0 and not main._room_transition_active and not main.journal.is_active(), "journal, turn arrows and right-click cannot escape the open dialog")
	_click_continue()
	check(dialog._message == "*Lacht*" and dialog._text_finished and not dialog._laugh_audio.playing, "the first click reveals only the current line and silences the voice")
	await _capture("laugh")
	for expected: String in ["*Lacht*", "*Furzt*", "*Lacht*"]:
		_click_continue()
		check(dialog._message == expected and dialog._is_typing(), "extra part starts in order: " + expected)
		check(fart_audio.playing == (expected == "*Furzt*"), "only the fart part plays fart audio")
		_click_continue()
		check(dialog._text_finished and dialog.is_dialog_open(), "revealing an extra part keeps it open")
	_click_continue()
	check(dialog._message == "*Scheisst sich ein*" and dialog._body_label.visible_characters == 0 and dialog._is_typing(), "the next click clears the first window and starts the second in order")
	check(dialog._laugh_audio._laughing, "the same deeper voice resumes for the second window")
	check(fart_audio.playing and fart_audio.stream.resource_path.ends_with("fart.mp3"), "entering the second window immediately plays the authored fart.mp3")
	fart_audio.stop()
	_click_continue()
	check(dialog.is_dialog_open() and dialog._text_finished and dialog._body_label.text == "*Scheisst sich ein*" and not dialog._laugh_audio.playing, "revealing the second line keeps it visible without an ending cue")
	check(not fart_audio.playing, "revealing the current line cannot restart an already finished fart")
	await _capture("second-window")
	_click_continue()
	check(await _wait_until(func(): return not dialog.is_busy()), "only a further click after the second line closes the dialog")
	check(main._crypt_gate_close and main.main_camera.global_transform.is_equal_approx(camera_before) and main._can_turn(), "closing the dialog keeps the exact near view and restores turning")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(dialog.open_dialog() and dialog._message == "*Lacht*", "reopening always starts at the first window in " + locale)
		check(dialog._body_label.text == Localization.text("*Lacht*") and (locale == "de" or dialog._body_label.text != "*Lacht*"), "the first window has a translation in " + locale)
		dialog._advance_dialog_text(20.0)
		check(dialog._text_finished and not dialog._laugh_audio.playing, "natural first-line completion is silent in " + locale)
		for expected: String in ["*Lacht*", "*Furzt*", "*Lacht*"]:
			dialog.continue_dialog()
			check(dialog._message == expected and dialog._body_label.text == Localization.text(expected), "extra translated part in " + locale)
			check(fart_audio.playing == (expected == "*Furzt*"), "extra part sound in " + locale)
			dialog._advance_dialog_text(20.0)
		dialog.continue_dialog()
		check(dialog._message == "*Scheisst sich ein*" and dialog._body_label.text == Localization.text("*Scheisst sich ein*"), "the translated second window stays in order in " + locale)
		check(fart_audio.playing, "the fart plays on entering the second window in " + locale)
		dialog._advance_dialog_text(20.0)
		check(dialog._text_finished and not dialog._laugh_audio.playing, "natural second-line completion has no end sound in " + locale)
		dialog.continue_dialog()
		await _wait_until(func(): return not dialog.is_busy())
		check(not fart_audio.playing, "closing the conversation stops the fart in " + locale)
	Localization.set_locale("de")
	dialog.open_dialog()
	_key(KEY_ESCAPE)
	await _wait_until(func(): return not dialog.is_busy())
	check(main._crypt_gate_close and not main._room_transition_active and not main.pause_menu.visible, "Escape closes the conversation without walking back or opening Pause")
	dialog.open_dialog()
	dialog.continue_dialog()
	dialog.continue_dialog()
	main.pause_menu.open()
	check(not dialog._laugh_audio.playing and not fart_audio.playing and not dialog.npc_area.input_ray_pickable, "Pause immediately stops both prisoner sounds and disables its click area")
	check(await _wait_until(func(): return not dialog.is_busy()), "the dialog finishes closing even while the game is paused")
	main.pause_menu.close()
	await _settle()
	_move_pointer(Vector2(-50, -50))
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "turning away from the crypt disables prisoner hover and clicks")
	check(actor.texture == idle_texture, "turning away clears the prisoner's hover animation")
	check(CollectionManager.collection == cards_before and GameCurrency.get_coin_cents() == coins_before and _profile_files() == files_before, "hover and conversation leave cards, currency and profile save bytes unchanged")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	print("PRISONER_DIALOGUE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _profile_files() -> Dictionary:
	var result := {}
	for filename in DirAccess.get_files_at("res://test-user/"):
		result[filename] = FileAccess.get_file_as_bytes("res://test-user/" + filename)
	return result


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _button(button: MouseButton, point: Vector2) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event, true)


func _click_continue() -> void:
	_button(MOUSE_BUTTON_LEFT, Vector2(640, 650))


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://prisoner-%s.png" % stage)
