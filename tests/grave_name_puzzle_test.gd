extends "res://tests/basement_boiler_test.gd"

class ControlledCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save

var puzzle: Node3D
var resets := 0
var solves := 0
var captures: Array[String] = []
var diagnostics: Dictionary = {}


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://test-user/grave-puzzle")
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	GameCurrency.set_process(false)
	_test_backend()
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	CollectionManager.add_card("graveyard_key")
	CollectionManager.use_access_key("graveyard_key")
	GameCurrency._basement_cat_choice = "shot"
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.05
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	viewport.add_child(main)
	puzzle = main.grave_puzzle
	puzzle.attempt_reset.connect(func(): resets += 1)
	puzzle.puzzle_solved.connect(func(_instance: Dictionary): solves += 1)
	await _settle(0.5)
	check(puzzle.graves.size() == 4 and puzzle.areas.size() == 4, "the four authored named graves are bound in clue order")
	var authored: Node3D = load("res://scenes/rooms/Graveyard.tscn").instantiate()
	var unchanged := true
	for index in range(4):
		var original: Node3D = authored.get_node("Burials/" + puzzle.GRAVE_NODES[index])
		unchanged = unchanged and puzzle.graves[index].transform.is_equal_approx(original.transform)
		unchanged = unchanged and puzzle.graves[index].get_node("Inscription").text == original.get_node("Inscription").text
	authored.free()
	check(unchanged, "all authored grave placements, rotations and inscriptions are preserved")
	check(not puzzle.interaction_enabled and puzzle.hovered == -1, "the hub cannot interact with remote graves")
	await _travel_to(2)
	await _face_graves()
	await _capture("grave-row")
	for index in range(4):
		_move_pointer(_grave_point(index))
		await _settle()
		check(puzzle.hovered == index, "real mouse hover selects " + puzzle.GRAVE_NODES[index])
		check(puzzle.graves[index].get_node("Headstone").material_overlay == puzzle._outline,
			"the selected headstone has the yellow outline")
		await _capture("hover-%d" % index)
	for index in range(4):
		await _click_at(_grave_point(index))
	check(puzzle.attempt.is_empty() and CollectionManager.get_amount("silver_bullet") == 0 and resets == 0,
		"knowing all four names before using MDMA neither records progress nor grants the card")
	check(puzzle._voice.playing and is_equal_approx(puzzle._voice.pitch_scale, 0.28), "grave clicks play the corresponding name at a very low pitch")
	check(GameCurrency.consume_story_package("mdma", true), "the real pickup API records the required first MDMA effect")
	main.pause_menu.open()
	await _settle()
	var blocked_click := InputEventMouseButton.new()
	blocked_click.pressed = true
	blocked_click.button_index = MOUSE_BUTTON_LEFT
	puzzle.areas[0].input_event.emit(main.main_camera, blocked_click, Vector3.ZERO, Vector3.ZERO, 0)
	check(puzzle.hovered == -1 and puzzle.attempt.is_empty(), "Pause clears hover and blocks grave input")
	main.pause_menu.close()
	await _settle()
	for index in [3, 3, 3]:
		await _click_at(_grave_point(index))
	check(puzzle.attempt == ["hannah", "hannah", "hannah"] and resets == 0 and not puzzle.resetting,
		"wrong prefixes and repeated graves remain one attempt until the fourth click")
	await _click_at(_grave_point(3))
	check(puzzle.resetting and puzzle.attempt.is_empty() and not puzzle._separator.playing
		and CollectionManager.get_amount("silver_bullet") == 0, "the fourth wrong click rejects the entire attempt and lets its deep name finish")
	check(await _wait_until(func(): return puzzle._separator.playing, 6500), "the real final name completion starts the reset separator")
	await _click_at(_grave_point(0))
	check(puzzle.attempt.is_empty(), "clicks during the reset indicator cannot leak into the next attempt")
	check(await _wait_until(func(): return not puzzle.resetting, 3000) and resets == 1, "the separator completion enables a fresh four-click attempt")
	await _click_at(_grave_point(0))
	await _click_at(_grave_point(1))
	check(puzzle.attempt == ["pablo", "trinity"], "a new attempt starts from Pablo without old wrong clicks")
	main.pause_menu.open()
	await _settle(0.2)
	check(puzzle.attempt == ["pablo", "trinity"] and puzzle.hovered == -1, "pause preserves an unfinished valid attempt")
	main.pause_menu.close()
	await _settle()
	await _click_at(_grave_point(3))
	await _click_at(_grave_point(2))
	check(puzzle.resetting and solves == 0, "four distinct graves in the wrong order cannot grant the reward")
	check(await _wait_until(func(): return not puzzle.resetting, 8000) and resets == 2, "a second failed attempt resets normally")
	await _click_at(_grave_point(0))
	await _travel_to(0)
	check(puzzle.attempt.is_empty() and not puzzle._voice.playing and not puzzle._separator.playing,
		"leaving the graveyard clears an unfinished attempt and its audio")
	await _travel_to(2)
	await _face_graves()
	for index in range(4):
		await _click_at(_grave_point(index))
	check(CollectionManager.get_amount("silver_bullet") == 1 and solves == 1,
		"real clicks Pablo, Trinity, Stuart, Hannah grant exactly one Silver Bullet")
	check(main.main_camera.get_node_or_null("GravePuzzleRewardReveal") != null, "the reward uses the existing animated story-card reveal")
	await _settle(0.8)
	await _capture("silver-bullet-reveal")
	check(CardData.is_story_card(CardDatabase.get_card("silver_bullet")), "the reward belongs to the same Story Cards group as Holy Water")
	CollectionManager.load_collection()
	GameCurrency.load_currency()
	check(GameCurrency.mdma_consumed and CollectionManager.has_discovered_card("silver_bullet"), "MDMA use and puzzle completion both survive reload")
	GameCurrency.story_completed_level = 25
	GameCurrency.mdma_reward_unlocked = true
	GameCurrency.mdma_package_pending = true
	check(not GameCurrency.is_story_package_available("mdma"), "solving the graves permanently stops ordinary MDMA drops")
	GameCurrency.award_match("win")
	check(not GameCurrency.mdma_package_pending, "later wins cannot queue MDMA after its hint puzzle is solved")
	for index in range(4):
		await _click_at(_grave_point(index))
	check(CollectionManager.get_amount("silver_bullet") == 1 and solves == 1, "repeating the solution cannot duplicate the story card")
	main.queue_free()
	await _settle()
	var report := {"checks": checks, "failures": failures, "captures": captures, "diagnostics": diagnostics,
		"audio_driver": AudioServer.get_driver_name(), "grave_scene_modified_unix": FileAccess.get_modified_time("res://scenes/rooms/Graveyard.tscn")}
	var file := FileAccess.open("res://test-user/grave-puzzle/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GRAVE_NAME_PUZZLE: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_backend() -> void:
	var manager := ControlledCollection.new()
	add_child(manager)
	GameCurrency.mdma_consumed = false
	check(manager.claim_grave_puzzle_reward(CollectionManager.GRAVE_SOLUTION).is_empty(), "the saved first-use gate cannot be bypassed by knowing the answer")
	GameCurrency.mdma_consumed = true
	var invalid_awards := 0
	for code in range(256):
		var sequence: Array[String] = []
		for offset in range(4):
			sequence.append(CollectionManager.GRAVE_SOLUTION[(code >> (offset * 2)) & 3])
		if sequence != CollectionManager.GRAVE_SOLUTION and not manager.claim_grave_puzzle_reward(sequence).is_empty():
			invalid_awards += 1
	check(invalid_awards == 0, "all 255 other four-click sequences, including duplicate graves, are rejected")
	check(manager.claim_grave_puzzle_reward(["pablo", "trinity", "stuart"]).is_empty(), "an incomplete sequence is rejected")
	check(manager.claim_grave_puzzle_reward(["pablo", "trinity", "stuart", "hannah", "pablo"]).is_empty(), "an overlong sequence is rejected")
	GameCurrency.set_training_session(self, true)
	check(manager.claim_grave_puzzle_reward(CollectionManager.GRAVE_SOLUTION).is_empty(), "training cannot claim the reward")
	GameCurrency.set_training_session(self, false)
	manager.reject_save = true
	var before := manager.collection.duplicate(true)
	check(manager.claim_grave_puzzle_reward(CollectionManager.GRAVE_SOLUTION).is_empty() and manager.collection == before,
		"failed saving preserves ownership and discovery history for retry")
	manager.reject_save = false
	var reward := manager.claim_grave_puzzle_reward(CollectionManager.GRAVE_SOLUTION)
	check(reward.get("card_id") == "silver_bullet" and manager.get_amount("silver_bullet") == 1, "only the exact correct sequence commits the reward")
	manager.collection.cards.clear()
	manager.collection.instances.clear()
	check(manager.claim_grave_puzzle_reward(CollectionManager.GRAVE_SOLUTION).is_empty(), "losing the owned copy cannot reopen the one-time reward")
	manager.free()
	var card := CardDatabase.get_card("silver_bullet")
	check(CardData.is_story_card(card) and CardData.is_unique_unlock(card) and not CardData.is_access_key(card)
		and not CardData.is_combat_card(card) and not CardDatabase._is_random_reward(card),
		"Silver Bullet is a unique noncombat Story Card excluded from random packs and access keys")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(not Localization.text("Silver Bullet").is_empty(), "the reward name is localized in " + locale)
	Localization.set_locale("de")
	check(Localization.text("Silver Bullet") == "Silberne Kugel" and ResourceLoader.exists(card.image), "the requested German name and native icon are available")


func _grave_point(index: int) -> Vector2:
	return main.main_camera.unproject_position(puzzle.graves[index].get_node("Headstone").global_position)


func _face_graves() -> void:
	for side in range(4):
		await _turn_to(side)
		var point := _grave_point(0)
		if not main.main_camera.is_position_behind(puzzle.graves[0].global_position) and viewport.get_visible_rect().grow(-10).has_point(point):
			return
	check(false, "a real cardinal graveyard view exposes the authored grave row")


func _travel_to(room: int) -> void:
	var door: HospitalDoor
	if room == 0:
		door = main.connected_rooms[main._active_room].get_node("ReturnDoor") as HospitalDoor
	else:
		for area in main.progression_areas:
			if area.room_index == room:
				door = area.door
	_move_pointer(Vector2(-50, -50))
	await _settle(0.2)
	await _face_door(door)
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	check(await _wait_until(func(): return main._active_room == room and not main._room_transition_active), "room travel reaches %d" % room)
	await _settle(0.2)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var snapshot := viewport.get_texture().get_image()
	var path := "res://test-user/grave-puzzle/" + label + ".png"
	check(snapshot.save_png(path) == OK, "capture " + label)
	captures.append(path)
	diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true), "camera": str(main.main_camera.global_transform)}
