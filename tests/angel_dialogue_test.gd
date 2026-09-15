extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var screen: CollectionScreen
var dialog: AngelDialogue
var modal_events: Array[bool] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.04) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner; never run against player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	Localization.set_locale("de")
	CollectionManager.add_card_instance({"card_id": "corpse", "instance_id": "angel-unit-corpse", "level": 1, "effects": [], "is_holo": false})
	DeckManager.add_card("corpse")
	CollectionManager.mark_card_seen("corpse")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.detail_duration = 0.03
	screen.deck_fan_duration = 0.03
	screen.deck_fan_stagger = 0.0
	viewport.add_child(screen)
	dialog = screen.angel_dialog
	screen.angel_dialog_changed.connect(func(opened: bool): modal_events.append(opened))
	_move_pointer(Vector2(-50, -50))
	await settle(0.3)
	var before := _state()
	var files_before := _files()
	var camera_transform := screen.camera.global_transform
	var camera_fov := screen.camera.fov
	var actor_scale := dialog.actor.scale
	check(dialog.actor == screen.get_node("angel") and dialog.npc_area.input_ray_pickable, "standalone collection exposes its existing angel actor and click area")
	var point := _visible_angel_point()
	check(viewport.get_visible_rect().has_point(point), "standalone angel click area projects into the viewport")
	_move_pointer(point)
	await settle(0.2)
	check(screen.camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(screen.camera.fov, camera_fov) and dialog.actor.scale.is_equal_approx(actor_scale), "standalone hover keeps camera transform, FOV and angel scale unchanged")
	await _check_foreground_card(point)
	_click(point)
	await settle()
	check(screen.is_angel_dialog_open() and modal_events == [true], "actual standalone pointer click opens one modal")
	check(screen.camera.global_transform.is_equal_approx(camera_transform) and dialog.actor.scale.is_equal_approx(actor_scale), "opening preserves the original collection framing")
	check(dialog._body_label.visible_characters > 0 and dialog._body_label.visible_characters < dialog._body_label.get_total_character_count(), "the sentence reveals gradually while the dialog processes")
	check(dialog._laugh_audio._laughing and dialog._laugh_audio.stream.resource_path.ends_with("satanVoice.mp3") and dialog._laugh_audio.bus == &"SFX", "typing uses the existing Satan voice on the SFX bus")
	_key(KEY_ESCAPE)
	check(not dialog.is_dialog_open() and modal_events == [true, false], "Escape closes exactly one standalone modal")
	await _check_typewriter_and_clicks()
	_check_randomness()
	await _check_localization_and_layout()
	await _check_contexts()
	check(_state() == before, "all angel conversations preserve inventory, discovery, upgrades, deck, currency and progression")
	check(_files() == files_before, "angel interactions and locale changes preserve every isolated profile and settings file byte")
	screen.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	print("ANGEL_DIALOGUE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_typewriter_and_clicks() -> void:
	check(dialog.open_dialog(), "a fresh sentence can open after Escape")
	dialog.set_process(false)
	check(not _has_sentence_end_player(), "the angel has no sentenceEnd audio node or player")
	check(dialog._body_label.visible_characters == 0 and not dialog._text_finished, "a fresh sentence starts unrevealed and unfinished")
	dialog._advance_dialog_text(0.1)
	check(dialog._body_label.visible_characters > 0 and dialog._body_label.visible_characters < dialog._body_label.get_total_character_count() and dialog._laugh_audio._laughing, "a short typewriter step advances only part of the sentence")
	dialog._advance_dialog_text(100.0)
	check(dialog._text_finished and dialog._body_label.visible_characters == -1 and not dialog._laugh_audio._laughing and not _has_sentence_end_player(), "natural sentence completion reveals all text and stops the voice without an ending sound")
	dialog._advance_dialog_text(100.0)
	check(dialog._text_finished and not dialog._laugh_audio._laughing and not _has_sentence_end_player(), "further typewriter updates keep the completed sentence silent")
	var selected := dialog._last_sentence_index
	Localization.set_locale("en")
	check(dialog._last_sentence_index == selected and dialog._text_finished and not dialog._laugh_audio._laughing, "changing the completed sentence language retains its identity without replaying audio")
	check(dialog._layer.find_children("*", "BaseButton", true, false).is_empty(), "the angel dialog contains no buttons, including hidden controls")
	await get_tree().process_frame
	_click(dialog._body_label.get_global_rect().get_center())
	check(not dialog.is_dialog_open(), "clicking naturally completed text dismisses its sentence after a locale change")
	for target in ["title", "text", "padding", "outside"]:
		check(dialog.open_dialog(), "a new sentence opens for the %s click test" % target)
		await get_tree().process_frame
		var point := _dialog_point(target)
		modal_events.clear()
		_mouse_button(point, false)
		check(dialog.is_dialog_open() and dialog._body_label.visible_characters == 0 and not dialog._text_finished, "a release over %s cannot reveal or close fresh text" % target)
		_mouse_button(point, true)
		check(dialog.is_dialog_open() and dialog._body_label.visible_characters == -1 and dialog._text_finished and not dialog._laugh_audio._laughing and not _has_sentence_end_player() and modal_events.is_empty(), "one press over %s reveals all text and stops the voice without an ending sound or closing" % target)
		_mouse_button(point, false)
		await get_tree().process_frame
		check(dialog.is_dialog_open() and modal_events.is_empty(), "the reveal release over %s cannot also close the dialog" % target)
		_mouse_button(point, true)
		check(not dialog.is_dialog_open() and not dialog._laugh_audio._laughing and modal_events == [false], "the next press over %s closes once and leaves the voice stopped" % target)
		_mouse_button(point, false)
		check(not dialog.is_dialog_open() and modal_events == [false], "the close release over %s cannot reopen or emit another transition" % target)
	for targets in [["text", "outside"], ["outside", "title"]]:
		dialog.open_dialog()
		await get_tree().process_frame
		_click(_dialog_point(targets[0]))
		check(dialog.is_dialog_open() and dialog._body_label.visible_characters == -1 and dialog._text_finished and not dialog._laugh_audio._laughing, "a mixed %s-to-%s sequence first reveals the sentence and stops its voice" % targets)
		_click(_dialog_point(targets[1]))
		check(not dialog.is_dialog_open() and not dialog._laugh_audio._laughing, "a mixed %s-to-%s sequence then closes the sentence" % targets)
	dialog.open_dialog()
	dialog._advance_dialog_text(0.4)
	selected = dialog._last_sentence_index
	Localization.set_locale("fr")
	check(dialog._last_sentence_index == selected and dialog._message == AngelDialogueContent.SENTENCES[selected] and dialog._body_label.text == Localization.text(dialog._message), "a locale change during typing preserves the selected source sentence")
	check(dialog._body_label.visible_characters > 0 and dialog._body_label.visible_characters < dialog._body_label.get_total_character_count() and not dialog._text_finished, "locale changes preserve partial progress without an early ending")
	dialog.close_dialog()
	dialog.set_process(true)
	Localization.set_locale("de")


func _has_sentence_end_player() -> bool:
	if dialog.find_child("AngelSentenceEnd", true, false) != null:
		return true
	for child in dialog.find_children("*", "", true, false):
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D or child is AudioStreamPlayer3D:
			var stream: AudioStream = child.get("stream")
			if stream != null and stream.resource_path.ends_with("sentenceEnd.mp3"):
				return true
	return false


func _dialog_point(target: String) -> Vector2:
	match target:
		"title":
			return dialog._title_label.get_global_rect().get_center()
		"text":
			return dialog._body_label.get_global_rect().get_center()
		"padding":
			return dialog._panel.get_global_rect().position + Vector2(6, 6)
	return Vector2(8, 8)


func _check_randomness() -> void:
	check(AngelDialogueContent.SENTENCES.size() == 20, "the authored conversation catalog contains exactly twenty sentences")
	var sources := {}
	for sentence in AngelDialogueContent.SENTENCES:
		sources[sentence] = true
	check(sources.size() == 20, "all twenty source sentences are distinct")
	seed(827362)
	var expected := randi()
	seed(827362)
	dialog._rng.seed = 617392
	var observed := {}
	var previous := dialog._last_sentence_index
	var valid := true
	var no_repeats := true
	for attempt in range(300):
		valid = dialog.open_dialog() and valid
		var index := dialog._last_sentence_index
		valid = valid and index >= 0 and index < 20 and dialog._message == AngelDialogueContent.SENTENCES[index] and dialog._body_label.text == Localization.text(dialog._message)
		no_repeats = no_repeats and index != previous
		observed[index] = true
		previous = index
		dialog.close_dialog()
	check(valid and no_repeats, "three hundred openings select exactly one catalog sentence without adjacent repeats")
	check(observed.size() == 20, "the deterministic private-RNG fixture reaches every authored sentence")
	check(randi() == expected, "sentence choice and voice startup do not consume gameplay's global RNG")


func _check_localization_and_layout() -> void:
	dialog.set_process(false)
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		var visited := {}
		for attempt in range(400):
			dialog.open_dialog()
			var index := dialog._last_sentence_index
			if not visited.has(index):
				visited[index] = true
				var text: String = Localization.text(AngelDialogueContent.SENTENCES[index])
				check(not text.strip_edges().is_empty() and (locale == "de" or text != AngelDialogueContent.SENTENCES[index]) and text.count(".") == 1 and not text.contains("\n"), "sentence %02d is translated as one sentence in %s" % [index + 1, locale])
				dialog.continue_dialog()
				await get_tree().process_frame
				check(dialog._body_label.text == text and dialog._body_label.get_content_height() <= dialog._body_label.size.y + 1.0 and dialog._panel.get_global_rect().encloses(dialog._body_label.get_global_rect()), "sentence %02d fits the actual %s dialog text area" % [index + 1, locale])
			dialog.close_dialog()
			if visited.size() == 20:
				break
		check(visited.size() == 20, "all twenty %s sentences receive a real dialog layout check" % locale)
	Localization.set_locale("de")
	dialog.set_process(true)


func _check_contexts() -> void:
	screen.set_angel_context_enabled(false)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "an explicitly disabled collection context cannot open or receive angel clicks")
	screen.set_angel_context_enabled(true)
	check(dialog.open_dialog(), "the standalone context can be enabled again")
	screen.set_angel_context_enabled(true)
	check(dialog.is_dialog_open(), "a repeated valid context refresh retains the current sentence")
	screen.suspend_deck_input(true)
	await settle()
	check(not dialog.is_dialog_open() and not dialog.npc_area.input_ray_pickable and not dialog.open_dialog(), "suspended collection input closes and disables the angel")
	screen.suspend_deck_input(false)
	await settle()
	dialog.open_dialog()
	screen.hide()
	await settle()
	check(not dialog.is_dialog_open() and not dialog._layer.visible and not dialog.npc_area.input_ray_pickable and not dialog._laugh_audio._laughing, "hiding the collection closes its modal and silences its voice")
	screen.show()
	await settle()
	var card: Card3D = screen._base_positions.keys()[0]
	await screen._open_detail_card(card)
	await settle()
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "an open card detail disables angel interaction")
	await screen._close_detail_card()
	await settle()
	await screen._open_deck_fan()
	await settle()
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "an open deck fan disables angel interaction")
	await screen._close_deck_fan()
	await settle()
	check(dialog.open_dialog(), "normal collection interaction recovers after closing detail and fan")
	screen._detail_tween_running = true
	await settle()
	check(not dialog.is_dialog_open() and not dialog.npc_area.input_ray_pickable, "an externally started detail transition closes an existing conversation")
	screen._detail_tween_running = false
	await settle()
	dialog.open_dialog()
	screen._deck_fan_tween_running = true
	await settle()
	check(not dialog.is_dialog_open() and not dialog.npc_area.input_ray_pickable, "an externally started deck fan transition closes an existing conversation")
	screen._deck_fan_tween_running = false
	await settle()
	dialog.open_dialog()
	var original_camera := screen.camera
	screen.camera = null
	await settle()
	check(not dialog.is_dialog_open() and not dialog.npc_area.input_ray_pickable and not dialog.open_dialog(), "losing the collection camera closes and disables the dialog")
	screen.camera = original_camera
	await settle()
	check(dialog.open_dialog(), "restoring the collection camera restores angel interaction")
	var replacement := Camera3D.new()
	viewport.add_child(replacement)
	replacement.make_current()
	await settle()
	check(not dialog.is_dialog_open() and not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "a different active camera closes and disables the original angel")
	original_camera.make_current()
	replacement.queue_free()
	await settle()
	dialog.close_dialog()


func _visible_angel_point() -> Vector2:
	# The standalone camera shows the lower part of the authored sprite; its
	# world-space midpoint need not be on screen. Pick an actual visible ray.
	var shape := (dialog.npc_area.get_child(0) as CollisionShape3D).shape as BoxShape3D
	for fraction in [0.0, -0.2, -0.4, 0.2, 0.4]:
		var point := screen.camera.unproject_position(dialog.npc_area.to_global(Vector3(0, shape.size.y * fraction, 0)))
		if viewport.get_visible_rect().grow(-8).has_point(point) and dialog._pointer_hits_area(point):
			return point
	return Vector2(-1, -1)


func _check_foreground_card(point: Vector2) -> void:
	var blocker := CollectionScreen.CARD_SCENE.instantiate() as Card3D
	viewport.add_child(blocker)
	blocker.setup(CardDatabase.get_card("corpse"))
	blocker.global_transform = Transform3D(screen.camera.global_basis, screen.camera.project_position(point, 2.0))
	var clicks: Array[int] = []
	blocker.area.input_event.connect(func(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicks.append(1)
	)
	await settle()
	check(not dialog._pointer_hits_area(point), "a real foreground Card3D wins the nearest ray in front of the angel")
	_click(point)
	await settle()
	check(clicks.size() == 1 and not dialog.is_dialog_open(), "a pointer click on the overlapping card reaches it once without opening the rear angel")
	blocker.queue_free()
	await settle()
	check(dialog._pointer_hits_area(point), "removing the foreground card restores the same angel ray target")


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click(point: Vector2) -> void:
	_mouse_button(point, true)
	_mouse_button(point, false)


func _mouse_button(point: Vector2, pressed: bool) -> void:
	_move_pointer(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)


func _state() -> Dictionary:
	return {"collection": CollectionManager.collection.duplicate(true), "upgrades": CardUpgradeManager.upgrades.duplicate(true), "deck": DeckManager.battle_deck.duplicate(), "ids": DeckManager.deck_instance_ids.duplicate(), "starting": DeckManager.starting_deck_indices.duplicate(), "coins": GameCurrency.get_coin_cents(), "level": GameCurrency.level, "xp": GameCurrency.xp}


func _files() -> Dictionary:
	var result := {}
	var paths: Array[String] = [SaveSlots.REGISTRY_PATH, SettingsManager.CONFIG_PATH]
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			paths.append(SaveSlots.get_slot_directory(slot).path_join(file_name))
	for path in paths:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result
