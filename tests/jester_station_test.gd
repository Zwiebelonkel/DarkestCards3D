extends Node3D

class InputSink:
	extends Node
	var presses := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			presses += 1

var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var station: GraveyardJester
var modal_events: Array[bool] = []
var input_sink: InputSink


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	for path in [SaveSlots.SAVE_ROOT, SaveSlots.LEGACY_ROOT, SaveSlots.REGISTRY_PATH, CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path, SettingsManager.CONFIG_PATH]:
		if not str(path).begins_with("res://test-user/"):
			push_error("Use the isolated match-feature runner; this suite resets fixture profiles 1 and 2.")
			get_tree().quit(1)
			return
	GameCurrency.set_process(false)
	Localization.set_locale("de")
	if SaveSlots.select_slot(1) != OK or SaveSlots.reset_slot(1) != OK or SaveSlots.reset_slot(2) != OK:
		check(false, "isolated profiles are available for the station fixture")
		_finish()
		return
	_create_station()
	await get_tree().physics_frame
	check(station._modal_root.find_children("*", "BaseButton", true, false).is_empty(), "all Jester modal modes share a text-only panel with no buttons")
	check(not station.interaction_enabled and not station.open_dialog() and not station.open_grave("chick"), "a disabled room cannot open NPC or offering UI")
	_check_disabled_pickers()
	station.set_interaction_enabled(true)
	check(station.focus_area.collision_layer == 0 and station.focus_area.input_ray_pickable and is_equal_approx(float(station.focus_area.get_meta("focus_distance")), 6.5), "one nonblocking focus box frames the entire station")
	check(station.grave_areas.size() == 2 and station.view_side == 1, "both named graves belong to the west station")
	check(station.open_dialog() and station.is_busy() and station._body_label.text == GraveyardJester.DIALOGUE and station._body_label.visible_characters == 0, "NPC opens the four-line typewriter dialogue")
	await get_tree().create_timer(0.10).timeout
	check(station._body_label.visible_characters > 0 and station._body_label.visible_characters < station._body_label.text.length(), "dialogue reveals characters gradually")
	station.set_interaction_enabled(true)
	check(station.is_busy(), "repeated context updates do not close a valid open dialog")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	check(not station.is_busy() and not station._layer.visible, "Escape immediately closes the modal through viewport input")
	check(modal_events == [true, false], "open and close emit exactly one modal transition each")
	await _check_sentence_end_sound()
	check(station.open_grave("chick") and not station._candidate.get("ok", false) and not station._body_label.text.is_empty(), "an unowned grave explains why no copy can be offered")
	var input_count := input_sink.presses
	_click(station._panel.get_global_rect().get_center())
	check(not station.is_busy() and input_sink.presses == input_count, "clicking inside an unavailable offering closes it without passing the click through")
	station.open_grave("chick")
	_click(Vector2(8, 8))
	check(not station.is_busy(), "clicking outside an unavailable offering also closes it")
	_add("chick", "station-chick-deck")
	_add("chick", "station-chick-holo", true)
	_add("harald", "station-harald")
	DeckManager.battle_deck.assign(["chick"])
	DeckManager.deck_instance_ids.assign(["station-chick-deck"])
	check(DeckManager.save_deck(), "pin the normal Chick copy in the real combat deck")
	await get_tree().physics_frame
	# Deliberately deliver the rear NPC callback first. The nearest grave
	# still wins instead of depending on physics picking callback order.
	var grave: Area3D = station.grave_areas["chick"]
	var click := _click_at(grave.global_position)
	station.npc_area.input_event.emit(camera, click, grave.global_position, Vector3.ZERO, 0)
	check(not station.is_busy(), "rear NPC callback cannot steal a click aimed at a front grave")
	grave.input_event.emit(camera, click, grave.global_position, Vector3.ZERO, 0)
	check(station._mode == GraveyardJester.Mode.CANDIDATE and str(station._candidate.get("instance", {}).get("instance_id", "")) == "station-chick-holo", "grave picks the concrete unprotected Holo copy")
	check(is_instance_valid(station._preview_card) and CardData.is_holo(station._preview_card.card_data) and station._body_label.text.contains("Holo"), "the reviewed copy retains its Holo preview and explicit warning")
	_check_preview_pickers()
	var before := CollectionManager.collection.duplicate(true)
	var before_bytes := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	input_count = input_sink.presses
	check(station._body_label.text.contains(Localization.text("Ins Textfeld klicken: opfern · Daneben klicken: abbrechen.")), "a valid candidate explains inside confirmation and outside cancellation")
	_click(Vector2(8, 8))
	check(CollectionManager.collection == before and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == before_bytes and not is_instance_valid(station._preview_card) and input_sink.presses == input_count, "outside cancellation preserves save bytes and collection data, clears preview, and consumes the click")
	check(station.open_grave("harald") and station._candidate.get("ok", false), "review a currently free Harald before its reservation changes")
	DeckManager.battle_deck.assign(["chick", "harald"])
	DeckManager.deck_instance_ids.assign(["station-chick-deck", "station-harald"])
	check(DeckManager.save_deck(), "reserve the reviewed Harald while the confirmation is open")
	before = CollectionManager.collection.duplicate(true)
	_click(station._panel.get_global_rect().get_center())
	check(CollectionManager.collection == before and station._mode == GraveyardJester.Mode.CANDIDATE and not station._candidate.get("ok", false) and not is_instance_valid(station._preview_card), "a stale protected candidate is rejected without consumption or automatic substitution")
	check(station._body_label.text == Localization.text("Im Kampfdeck – zuerst aus dem Deck entfernen."), "the stale confirmation explains its protection failure")
	_click(station._panel.get_global_rect().get_center())
	check(not station.is_busy() and CollectionManager.collection == before, "another click closes the rejected candidate without trying a substitute")
	DeckManager.battle_deck.assign(["chick"])
	DeckManager.deck_instance_ids.assign(["station-chick-deck"])
	check(DeckManager.save_deck(), "release the second offering copy after the stale-candidate check")
	check(station.open_grave("chick"), "the same free copy can be reviewed again")
	modal_events.clear()
	_click(station._panel.get_global_rect().get_center())
	check(station._mode == GraveyardJester.Mode.OFFERING and CollectionManager.get_jester_offering_state()["offered"].has("chick"), "first confirmation commits the offering before its cosmetic flight")
	check(CollectionManager.get_amount("chick") == 1 and DeckManager.deck_instance_ids == ["station-chick-deck"], "only the reviewed Holo is consumed, preserving the pinned normal copy")
	check(is_instance_valid(station._preview_card) and station._preview_card._death_dissolve != null, "the offering uses the existing card dissolve presentation")
	var after_first := CollectionManager.collection.duplicate(true)
	station._confirm_offering()
	check(CollectionManager.collection == after_first, "confirmation cannot be repeated during the dissolve")
	check(await _wait_received(), "first offering finishes with an acknowledgement")
	check(modal_events.is_empty(), "candidate-to-flight-to-received stays one uninterrupted modal")
	check((station.get_node("Burials/Grave_27/Inscription") as Label3D).text.contains(Localization.text("Geopfert")), "the grave displays persistent completion immediately")
	input_count = input_sink.presses
	_click(station._panel.get_global_rect().get_center())
	check(not station.is_busy() and input_sink.presses == input_count, "an inside click closes the received acknowledgement without falling through")
	check(station.open_grave("chick") and not station._candidate.get("ok", false) and not is_instance_valid(station._preview_card), "an already completed grave cannot offer another copy")
	_click(Vector2(8, 8))
	check(station.open_grave("harald") and station._candidate.get("ok", false), "second grave reviews its own exact candidate")
	_click(station._panel.get_global_rect().get_center())
	var completed := CollectionManager.get_jester_offering_state()
	check(completed["completed"] and not completed["reward_instance"].is_empty(), "the second confirmation has already persisted a Secret reward")
	var reward_id := str(completed["reward_instance"].get("instance_id", ""))
	check(await _wait_received(), "second dissolve reaches the received-card presentation")
	check(is_instance_valid(station._preview_card) and station._preview_card.card_data.get("rarity") == "secret" and str(station._preview_card.card_data.get("instance_id", "")) == reward_id, "reward preview is the exact saved Secret instance")
	check(bool(station._preview_card._rarity_glow_material.get_shader_parameter("rainbow_mode")), "the revealed Secret card retains the rainbow border")
	_check_preview_pickers()
	var completed_collection := CollectionManager.collection.duplicate(true)
	Localization.set_locale("en")
	check(station._title_label.text == Localization.format_text("Erhalten: %s", [Localization.text(str(station._preview_card.card_data.get("name", "")))]) and CollectionManager.collection == completed_collection, "locale changes update reward text without rerolling or granting cards")
	input_count = input_sink.presses
	_click(Vector2(8, 8))
	check(not station.is_busy() and CollectionManager.collection == completed_collection and input_sink.presses == input_count, "an outside click closes the Secret receipt without awarding or consuming another card")
	CollectionManager.load_collection()
	station.refresh_state()
	check(CollectionManager.get_jester_offering_state()["reward_instance"].get("instance_id") == reward_id and station.open_dialog(), "saved completion and reward identity survive reload")
	check(station._body_label.text == Localization.text("Dein Opfer ist nicht vergessen."), "completed NPC acknowledges the saved offering")
	station.close_dialog()
	check(SaveSlots.select_slot(2) == OK, "switch to a fresh isolated profile")
	station.refresh_state()
	check(not (station.get_node("Burials/Grave_27/Inscription") as Label3D).text.contains(Localization.text("Geopfert")), "fresh profile removes the first profile's grave completion labels")
	_add("chick", "station-slot2-chick")
	check(station.open_grave("chick"), "new profile has its own eligible offering")
	station.offering_duration = 0.12
	var inside := station._panel.get_global_rect().get_center()
	_click(inside)
	var committed := CollectionManager.collection.duplicate(true)
	input_count = input_sink.presses
	_click(inside)
	check(not station.is_busy() and not is_instance_valid(station._preview_card) and station._offering_tween == null and CollectionManager.collection == committed and input_sink.presses == input_count, "a second immediate inside click cancels only the cosmetic flight without a duplicate offering or input fallthrough")
	station.set_interaction_enabled(false)
	await get_tree().create_timer(0.18).timeout
	check(not station.is_busy() and not station._layer.visible and CollectionManager.get_jester_offering_state()["offered"] == ["chick"], "cancelled presentation never reopens and retains the already committed offering")
	_check_disabled_pickers()
	station.set_interaction_enabled(true)
	check(station.open_grave("harald"), "missing second copy can still be inspected in the new profile")
	check(SaveSlots.select_slot(1) == OK, "restore the completed profile")
	station.refresh_state()
	check(not station.is_busy() and CollectionManager.get_jester_offering_state()["reward_instance"].get("instance_id") == reward_id, "profile changes close stale candidates and restore the original reward")
	viewport.queue_free()
	await get_tree().process_frame
	_finish()


func _check_sentence_end_sound() -> void:
	station.open_dialog()
	station.set_process(false)
	var ending := station._sentence_end_audio
	check(ending.stream == GraveyardJester.SENTENCE_END_SOUND and ending.bus == &"SFX", "sentence endings use the authored sound and SFX volume")
	var expected_characters := 0
	var sentence_index := 0
	for sentence: String in station._body_label.get_parsed_text().split("\n"):
		expected_characters += sentence.length()
		station._advance_dialog_text(100.0)
		check(station._body_label.visible_characters == expected_characters and ending.playing and not station._laugh_audio._laughing, "a slow frame stops at sentence %d and plays its ending without laughter" % (sentence_index + 1))
		station._advance_dialog_text(100.0)
		check(station._body_label.visible_characters == expected_characters, "sentence %d waits for its ending sound before more text appears" % (sentence_index + 1))
		if sentence_index == 0:
			await get_tree().create_timer(ending.stream.get_length() + 0.2).timeout
			check(not ending.playing and station._laugh_audio._laughing, "finishing the ending sound resumes the Jester voice for the next sentence")
		else:
			ending.stop()
		expected_characters += 1
		sentence_index += 1
	station._advance_dialog_text(100.0)
	check(not ending.playing and not station._laugh_audio._laughing, "completed dialogue does not repeat its final sound")
	station.close_dialog()
	for inside in [false, true]:
		station.open_dialog()
		var point := station._panel.get_global_rect().get_center() if inside else Vector2(8, 8)
		var input_count := input_sink.presses
		_click(point)
		check(station._body_label.visible_characters == -1 and ending.playing and not station._laugh_audio._laughing and input_sink.presses == input_count, "%s click reveals the entire dialogue, plays one ending and consumes the event" % ("inside" if inside else "outside"))
		_click(point)
		check(not station.is_busy() and not ending.playing and not station._laugh_audio._laughing and input_sink.presses == input_count, "%s closing click silences both voices without input fallthrough" % ("inside" if inside else "outside"))
	station.set_process(true)


func _create_station() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	add_child(viewport)
	viewport.notify_mouse_entered()
	input_sink = InputSink.new()
	viewport.add_child(input_sink)
	camera = Camera3D.new()
	camera.position = Vector3(0, 2.1, -6)
	viewport.add_child(camera)
	camera.look_at(Vector3(-4.8, 1.4, -6))
	camera.make_current()
	station = GraveyardJester.new()
	station.camera = camera
	station.offering_duration = 0.05
	var burials := Node3D.new()
	burials.name = "Burials"
	station.add_child(burials)
	for index in range(2):
		var grave := Node3D.new()
		grave.name = "Grave_%d" % (27 + index)
		grave.rotation.y = -PI * 0.5
		grave.position = Vector3(-4.44328, 0, -5.359 - index * 1.2518)
		burials.add_child(grave)
		var inscription := Label3D.new()
		inscription.name = "Inscription"
		grave.add_child(inscription)
	viewport.add_child(station)
	station.modal_changed.connect(func(opened: bool): modal_events.append(opened))


func _add(card_id: String, instance_id: String, holo: bool = false) -> void:
	check(not CollectionManager.add_card_instance({"card_id": card_id, "instance_id": instance_id, "level": 1, "effects": [], "is_holo": holo}).is_empty(), "own exact station fixture copy " + instance_id)


func _click_at(position: Vector3) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = camera.unproject_position(position)
	event.global_position = event.position
	return event


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)


func _check_preview_pickers() -> void:
	var disabled := true
	for area: Area3D in station._preview_card.find_children("*", "Area3D", true, false):
		disabled = disabled and not area.input_ray_pickable and area.collision_layer == 0
	check(disabled, "card preview and effect icons cannot steal station or GUI clicks")


func _check_disabled_pickers() -> void:
	var disabled := not station.focus_area.input_ray_pickable and station.focus_area.collision_layer == 0
	for area: Area3D in station._click_areas():
		disabled = disabled and not area.input_ray_pickable and area.collision_layer == 0
	check(disabled, "disabled station has no pickable or ray-blocking areas")


func _wait_received() -> bool:
	var deadline := Time.get_ticks_msec() + 1500
	while station._mode == GraveyardJester.Mode.OFFERING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return station._mode == GraveyardJester.Mode.RECEIVED


func _finish() -> void:
	print("JESTER_STATION_TESTS: PASS (%d checks)" % checks if failures == 0 else "JESTER_STATION_TESTS: FAIL (%d/%d)" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
