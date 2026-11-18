extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var dialog: DealerDialogue


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + message)


func settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run in an isolated project; never use player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	GameCurrency._rescued_npcs["dealer"] = true
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	CollectionManager.add_card("black_market_access")
	check(CollectionManager.use_access_key("black_market_access"), "dealer fixture explicitly activates Black Market access")
	Localization.set_locale("de")
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
	main.room_travel_duration = 0.15
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	viewport.add_child(main)
	dialog = main.dealer_dialogue
	_move_pointer(Vector2(-50, -50))
	await settle(0.5)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "dealer cannot be opened from the hub")
	var entrance := main.get_node("ProgressionAreas/BlackMarket") as ProgressionArea
	main._on_room_door_activated(entrance.door)
	await settle(0.6)
	check(main._active_room == 4 and dialog.interaction_enabled, "real travel enables the dealer in the Black Market")
	check(dialog.actor == main.get_node("BlackMarketRoom/Kiosk/Dealer"), "dialog uses the authored dealer sprite")
	var point := main.main_camera.unproject_position(dialog.npc_area.global_position)
	check(viewport.get_visible_rect().has_point(point) and dialog._pointer_hits_area(point), "actual dealer hit box is visible and unobstructed")
	var idle_texture := dialog.actor.texture
	dialog.actor.frame = 7
	dialog.actor.set("_frame_timer", 0.04)
	_move_pointer(point)
	dialog._update_pointer_hover()
	check(dialog.actor.texture.resource_path == "res://assets/characters/baclmarketDealer/dealerHover.png" and dialog.actor.frame == 7 and is_equal_approx(dialog.actor.get("_frame_timer"), 0.04), "dealer hover preserves the current frame and its elapsed time")
	_move_pointer(Vector2(-50, -50))
	dialog._update_pointer_hover()
	check(dialog.actor.texture == idle_texture and dialog.actor.frame == 7 and is_equal_approx(dialog.actor.get("_frame_timer"), 0.04), "leaving the dealer restores idle without restarting the loop")
	_move_pointer(point)
	await settle(0.2)
	check(dialog.actor.texture.resource_path.ends_with("dealerHover.png") and dialog.actor.frame != 7, "dealer hover animation continues advancing")
	_click(point)
	await settle()
	check(dialog.is_dialog_open() and dialog._is_typing(), "actual dealer pointer click opens a typewriter sentence")
	check(dialog.actor.texture == idle_texture, "dealer dialog clears the hover hint")
	check(dialog._laugh_audio._laughing and dialog._laugh_audio.stream.resource_path.ends_with("satanVoice.mp3"), "dealer speaks using the existing voice sound")
	var max_dealer_pitch := pow(2.0, (6.0 + dialog.voice_pitch_offset) / 12.0)
	var min_other_pitch := pow(2.0, -4.0 / 12.0)
	check(max_dealer_pitch < min_other_pitch and dialog._laugh_audio.pitch_scale <= max_dealer_pitch, "every dealer voice pitch stays below the other characters")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "conversation locks turning, travel and journal")
	check(not main.black_market_board.interaction_enabled and not main.level_progress._enabled, "conversation disables shopping and progression clicks")
	var snapshot := CollectionManager.collection.duplicate(true)
	var coins := GameCurrency.get_coin_cents()
	check(not main.black_market_board.purchase_offer(0).get("ok", false), "direct shop callbacks cannot buy through the dialog")
	_key(KEY_J)
	main.turn_arrows.turn_requested.emit(1)
	check(dialog.is_dialog_open() and main._active_side == 0 and not main.journal.is_active(), "keyboard and arrow callbacks cannot escape the modal")
	_click(Vector2(640, 650))
	check(dialog._text_finished and not dialog._laugh_audio._laughing and not dialog._laugh_audio.playing, "first dialog click reveals the whole line and stops the voice")
	if DisplayServer.get_name() != "headless":
		await settle(0.1)
		RenderingServer.force_draw(false)
		check(viewport.get_texture().get_image().save_png("res://dealer-dialogue.png") == OK, "captured actual dealer and dialog")
	_click(Vector2(640, 650))
	await settle(0.28)
	check(not dialog.is_dialog_open() and main.black_market_board.interaction_enabled and main._can_turn(), "second dialog click restores shopping and navigation")
	check(CollectionManager.collection == snapshot and GameCurrency.get_coin_cents() == coins, "conversations preserve cards and coins")
	var seen := {}
	dialog._rng.seed = 82061
	var previous := dialog._last_sentence_index
	var no_repeats := true
	for index in range(80):
		dialog.open_dialog()
		no_repeats = no_repeats and previous != dialog._last_sentence_index
		previous = dialog._last_sentence_index
		seen[previous] = true
		dialog.close_dialog()
		await settle(0.28)
	check(no_repeats and seen.size() == dialog._get_sentences().size(), "private random dialog selection covers all lines without immediate repeats")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		dialog.open_dialog()
		dialog._advance_dialog_text(0.3)
		var translated := dialog._body_label.text
		check(not translated.is_empty() and (locale == "de" or translated != dialog._message), "dealer sentence is translated in " + locale)
		dialog._advance_dialog_text(50.0)
		check(dialog._text_finished and not dialog._laugh_audio.playing, "natural sentence completion silences voice in " + locale)
		dialog.close_dialog()
		await settle(0.28)
	Localization.set_locale("de")
	dialog.open_dialog()
	_key(KEY_ESCAPE)
	await settle(0.28)
	check(not dialog.is_dialog_open() and not main.pause_menu.visible, "Escape closes only the dialog")
	dialog.open_dialog()
	get_tree().paused = true
	await settle(0.28)
	check(not dialog.is_dialog_open() and not dialog._laugh_audio.playing, "pause immediately closes dialog and stops voice")
	get_tree().paused = false
	await settle()
	main._request_turn(1)
	await settle(0.2)
	check(not dialog.open_dialog() and not dialog.npc_area.input_ray_pickable, "other market facing cannot activate the dealer")
	main._request_turn(-1)
	await settle(0.2)
	check(dialog.interaction_enabled and main.black_market_board.interaction_enabled, "returning to the kiosk restores dealer and board")
	_move_pointer(main.main_camera.unproject_position(main.black_market_board.focus_area.global_position))
	await settle(0.8)
	check(main.screen_camera_focus.is_focused(), "offer-board hover still focuses the shared camera")
	_move_pointer(Vector2(-50, -50))
	await settle(0.8)
	main._on_room_door_activated(main.get_node("BlackMarketRoom/ReturnDoor"))
	await settle(0.6)
	check(main._active_room == 0 and not dialog.open_dialog(), "leaving the market disables remote dealer interaction")
	main.queue_free()
	await settle()
	viewport.queue_free()
	print("DEALER_DIALOGUE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		viewport.push_input(event, true)
