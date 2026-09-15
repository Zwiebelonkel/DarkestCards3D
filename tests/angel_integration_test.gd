extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var screen: CollectionScreen
var dialog: AngelDialogue


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func wait_until(predicate: Callable, timeout_ms: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner; never run against player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	Localization.set_locale("de")
	for id in ["corpse", "chick", "clicker"]:
		CollectionManager.add_card_instance({"card_id": id, "instance_id": "angel-hub-" + id, "level": 1, "effects": [], "is_holo": false})
		CollectionManager.mark_card_seen(id)
	DeckManager.add_card("corpse")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.05
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	viewport.add_child(main)
	screen = main.scene_pivot.get_node("Collection") as CollectionScreen
	screen.detail_duration = 0.03
	screen.deck_fan_duration = 0.03
	screen.deck_fan_stagger = 0.0
	dialog = screen.angel_dialog
	_move_pointer(Vector2(-50, -50))
	await settle(0.5)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "the hub's initial table view cannot open the collection angel")
	await _turn_to(2)
	check(main._active_room == 0 and dialog.interaction_enabled and dialog.npc_area.input_ray_pickable, "only the active hub collection side enables the angel")
	var before := _state()
	var files_before := _files()
	var camera_transform := main.main_camera.global_transform
	var camera_fov := main.main_camera.fov
	var actor_scale := dialog.actor.scale
	var point := main.main_camera.unproject_position(dialog.npc_area.global_position)
	check(viewport.get_visible_rect().has_point(point), "the real hub angel projects inside the collection view")
	_move_pointer(point)
	await settle(0.6)
	check(not main.screen_camera_focus.is_focused() and not main.screen_camera_focus._screens.has(dialog.npc_area), "hovering the angel does not register or trigger station camera focus")
	check(main.main_camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(main.main_camera.fov, camera_fov) and dialog.actor.scale.is_equal_approx(actor_scale), "real hub hover preserves camera position, rotation, FOV and angel scale")
	await _capture("hover")
	_click(point)
	check(await wait_until(func(): return dialog.is_dialog_open()), "an actual hub angel pointer click opens the sentence")
	dialog.set_process(false)
	check(not dialog._text_finished and dialog._body_label.visible_characters >= 0 and dialog._body_label.visible_characters < dialog._body_label.get_total_character_count(), "the opening pointer press and release do not also skip the fresh sentence")
	check(dialog._layer.find_children("*", "BaseButton", true, false).is_empty(), "the real hub angel dialog has no buttons")
	check(main.main_camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(main.main_camera.fov, camera_fov) and dialog.actor.scale.is_equal_approx(actor_scale), "opening the modal preserves the hub camera and angel size")
	check(main._is_angel_busy() and not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "the angel modal locks hub turning, room travel and journal opening")
	check(not main.level_progress._enabled and not main.level_progress.is_expanded(), "the angel modal stows and disables progression and coin input")
	var selected := dialog._last_sentence_index
	_key(KEY_J)
	_key(KEY_A, true)
	_key(KEY_LEFT)
	_key(KEY_RIGHT)
	main.turn_arrows.turn_requested.emit(1)
	check(dialog.is_dialog_open() and dialog._last_sentence_index == selected and not main.journal.is_active() and main._active_side == 2, "journal, debug unlock, keyboard turns and arrow callbacks cannot pass through the sentence")
	for area in main.progression_areas:
		check(not area.open(), "progression doorway %s remains blocked during the angel modal" % area.area_id)
	var rows_before := screen._row_scroll_offsets.duplicate()
	var card: Card3D = screen._base_positions.keys()[0]
	var card_point := main.main_camera.unproject_position(card.global_position)
	_click(card_point, MOUSE_BUTTON_RIGHT)
	_click(card_point, MOUSE_BUTTON_WHEEL_DOWN)
	await screen._open_detail_card(card)
	screen._on_deck_overview_pressed()
	screen._on_clear_deck_pressed()
	await screen._on_random_deck_pressed()
	check(dialog.is_dialog_open() and screen._detail_card == null and not screen._deck_fan_open and screen._row_scroll_offsets == rows_before, "card detail, row scrolling and deck controls remain blocked while reading")
	check(_state() == before and _files() == files_before, "blocked game and collection inputs cannot mutate any owned card, deck, progression or save file")
	dialog.continue_dialog()
	await _capture("dialog")
	check(dialog._body_label.text == Localization.text(AngelDialogueContent.SENTENCES[selected]), "the visible hub dialog contains exactly its chosen localized sentence")
	_key(KEY_ESCAPE)
	check(not dialog.is_dialog_open() and not main.pause_menu.visible, "Escape closes the angel without also opening Pause")
	dialog.set_process(true)
	await settle()
	check(main._can_turn() and main._can_open_journal() and main.level_progress._enabled, "closing restores normal hub navigation and progression input")
	await _check_inside_and_outside_clicks()
	await _check_context_changes()
	check(_state() == before and _files() == files_before, "context changes and all angel presentations preserve inventory and saved profile bytes")
	check(dialog.open_dialog(), "an open-dialog scene exit can be exercised")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(main), "the whole hub frees cleanly while the angel is speaking")
	viewport.queue_free()
	await get_tree().process_frame
	print("ANGEL_INTEGRATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_inside_and_outside_clicks() -> void:
	check(dialog.open_dialog(), "the angel can open again after Escape")
	dialog.set_process(false)
	var arrow_point := Vector2(20, viewport.size.y * 0.5)
	_click(arrow_point)
	check(dialog.is_dialog_open() and dialog._body_label.visible_characters == -1 and main._active_side == 2, "an outside click on the turn-arrow location reveals the sentence without turning")
	_click(arrow_point)
	await settle(0.2)
	check(not dialog.is_dialog_open() and main._active_side == 2, "a second outside click closes without falling through to the underlying turn arrow")
	check(dialog.open_dialog(), "the collection remains available after outside dismissal")
	var card: Card3D = screen._base_positions.keys()[0]
	var point := main.main_camera.unproject_position(card.global_position)
	await get_tree().process_frame
	_click(point)
	check(dialog.is_dialog_open() and dialog._body_label.visible_characters == -1 and screen._detail_card == null, "a click over a foreground card reveals the sentence without opening the card")
	_click(point)
	await settle()
	check(not dialog.is_dialog_open() and screen._detail_card == null, "dismissing over a card never also opens its detail")
	check(dialog.open_dialog(), "a new sentence can be read by clicking inside its panel")
	await get_tree().process_frame
	_click(dialog._title_label.get_global_rect().get_center())
	check(dialog.is_dialog_open() and dialog._body_label.visible_characters == -1, "the real dialog title reveals the sentence with one click")
	_click(dialog._body_label.get_global_rect().get_center())
	await settle()
	check(not dialog.is_dialog_open() and main._active_side == 2 and screen._detail_card == null, "a following text click closes without triggering the collection behind it")
	dialog.set_process(true)


func _check_context_changes() -> void:
	dialog.open_dialog()
	main.pause_menu.open()
	check(not dialog.is_dialog_open() and not dialog.npc_area.input_ray_pickable and not dialog._laugh_audio._laughing, "opening Pause immediately closes the dialog and disables and silences the angel")
	main.pause_menu.close()
	await settle()
	check(dialog.open_dialog(), "unpausing restores the angel context")
	main._room_transition_active = true
	main._update_angel_interaction()
	check(not dialog.is_dialog_open() and not dialog.open_dialog(), "a room-flight context closes and disables the dialog")
	main._room_transition_active = false
	main._update_angel_interaction()
	dialog.open_dialog()
	main._active_room = 2
	main._update_angel_interaction()
	check(not dialog.is_dialog_open() and not dialog.open_dialog(), "the same facing direction in another room cannot retain the hub angel")
	main._active_room = 0
	main._update_angel_interaction()
	await _turn_to(1)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "leaving the collection view disables the angel")
	await _turn_to(2)
	check(dialog.open_dialog(), "returning to the collection restores its original angel interaction")
	dialog.close_dialog()


func _turn_to(side: int) -> void:
	_move_pointer(Vector2(-50, -50))
	for attempt in range(8):
		if main._active_side == side:
			break
		main._request_turn(-1)
		await settle(0.18)
	check(main._active_side == side, "hub turning reaches side %d" % side)
	await settle(0.35)


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event, true)


func _key(code: Key, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		viewport.push_input(event, true)


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await settle(0.06)
	RenderingServer.force_draw(false)
	check(viewport.get_texture().get_image().save_png("res://angel-%s.png" % stage) == OK, "rendered angel evidence: " + stage)


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
