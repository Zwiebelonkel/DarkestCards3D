extends "res://tests/basement_boiler_test.gd"


class ControlledCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save


class ControlledWallet:
	extends "res://scripts/GameCurrency.gd"
	func _ready() -> void:
		set_process(false)
	func save() -> bool:
		return true


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	# Keep the unrelated global playtime encounter out of this puzzle fixture.
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	_test_backend()
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	GameCurrency._basement_cat_choice = "shot"
	Localization.set_locale("de")
	CollectionManager.add_card("basement_key")
	CollectionManager.use_access_key("basement_key")
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
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	viewport.add_child(main)
	focus = main.screen_camera_focus
	boilers = main.basement_boilers
	await _settle(0.5)
	for index in range(4):
		check(str(boilers[index].name) == "MainBoiler_%d" % (index + 1), "puzzle pressure %d uses the numbered boiler" % (index + 1))
		boilers[index].pressure = CollectionManager.BOILER_SOLUTION[index]
		boilers[index]._update_gauge()
	await _travel_to(3)
	await _turn_to(boilers[0].view_side)
	check(CollectionManager.get_amount("jester_eye") == 0, "correct real boilers alone do not bypass cocaine consumption")
	for boiler in boilers:
		boiler.pressure = 2.8
		boiler._update_gauge()
	check(GameCurrency.consume_story_package("cocaine", true), "the package's real consumption API records first use")
	for index in range(4):
		var boiler := boilers[index]
		var target := CollectionManager.BOILER_SOLUTION[index]
		await _hover_boiler(boiler)
		await _begin_drag(boiler)
		_rotate_pointer(boiler, 0.0, (boiler.pressure - target) / BasementBoiler.PRESSURE_PER_RADIAN)
		check(boiler.digits.text == "%.1f" % target and CollectionManager.get_amount("jester_eye") == 0,
			"real input sets boiler %d and keeps the reward pending during dragging" % (index + 1))
		if index == 3:
			# Reproduce a missed release callback while retaining real valve input.
			boiler.dragging_changed.disconnect(main._on_boiler_dragging_changed)
		_send_button(_wheel_point(boiler, 0.0), false)
		await _settle(0.2)
		if index == 3:
			boiler.dragging_changed.connect(main._on_boiler_dragging_changed)
			check(CollectionManager.get_amount("jester_eye") == 1, "the settled-state check grants the eye even if the final release callback is missed")
		check(is_equal_approx(boiler.pressure, boiler.digits.text.to_float()), "boiler %d settles on exactly its displayed tenth after release" % (index + 1))
	check(CollectionManager.get_amount("jester_eye") == 1 and main.main_camera.get_node_or_null("BoilerPuzzleRewardReveal") != null,
		"releasing the solved valve grants and reveals exactly one Jester Eye")
	check(not CollectionManager.is_access_key_used("graveyard_key") and not GameCurrency.is_npc_rescued("jester"),
		"the eye is awarded with the graveyard still locked and the Jester still imprisoned")
	check(CollectionManager.exchange_jester_eye().is_empty() and CollectionManager.get_amount("jester_eye") == 1,
		"the imprisoned Jester blocks only the later exchange and leaves the owned eye intact")
	var wallet := ControlledWallet.new()
	add_child(wallet)
	wallet.cocaine_reward_unlocked = true
	wallet.cocaine_package_pending = true
	wallet.story_completed_level = 20
	check(not wallet.is_story_package_available("cocaine"), "solving the boiler puzzle ends ordinary cocaine drops")
	wallet.cocaine_package_pending = false
	wallet.award_match("win")
	check(not wallet.cocaine_package_pending, "later victories cannot queue cocaine after puzzle completion")
	wallet.free()
	await _capture("puzzle-jester-eye")
	main._try_claim_boiler_reward()
	check(CollectionManager.get_amount("jester_eye") == 1, "rechecking the solved room cannot duplicate the eye")
	await _settle(3.6)
	await _travel_to(0)
	check(not main.has_node("SatanCrucifixDialogue") and not bool(CollectionManager.collection.metadata.get("crucifix_return_dialogue_seen", false)),
		"returning with only the eye does not start or consume the cross sequence")
	main._on_access_key_requested("jester_eye")
	check(CollectionManager.get_amount("jester_eye") == 1 and CollectionManager.get_amount("crucifix") == 0,
		"the hub cannot remotely exchange the eye")
	GameCurrency._rescued_npcs["jester"] = true
	CollectionManager.add_card("graveyard_key")
	CollectionManager.use_access_key("graveyard_key")
	await _travel_to(2)
	await _turn_to(main.graveyard_jester.view_side)
	check(main._can_use_access_key("jester_eye"), "the rescued Jester accepts the owned eye in his station view")
	main.pause_menu.open()
	main._on_access_key_requested("jester_eye")
	check(CollectionManager.get_amount("jester_eye") == 1, "Pause blocks the Jester exchange")
	main.pause_menu.close()
	await _settle()
	check(main.graveyard_jester.open_dialog(), "the Jester's existing conversation still opens")
	main._on_access_key_requested("jester_eye")
	check(CollectionManager.get_amount("jester_eye") == 1, "an active Jester conversation blocks the exchange")
	main.graveyard_jester.close_dialog()
	await _wait_until(func(): return not main.graveyard_jester.is_busy())
	await _turn_to((main.graveyard_jester.view_side + 1) % 4)
	check(not main._can_use_access_key("jester_eye"), "turning away from the Jester disables his item")
	await _turn_to(main.graveyard_jester.view_side)
	main._crypt_gate_close = true
	check(not main._can_use_access_key("jester_eye"), "the prisoner viewpoint cannot use the Jester's item")
	main._crypt_gate_close = false
	# Two destinationless items must explain the one usable in this context.
	CollectionManager.add_card_instance(CardData.create_instance("toilet_paper"))
	_move_pointer(Vector2(640, 719))
	await _settle(0.8)
	var tray := main.access_key_tray
	check(tray.is_expanded() and tray._key_tiles.has("jester_eye"), "bottom-edge input opens the tray with the Jester Eye")
	check(tray.hint_label.text == Localization.text("Jester-Auge beim Jester verwenden."), "the tray explains the Jester action even alongside Toilet Paper")
	await _capture("jester-trade-tray")
	var coins_before := GameCurrency.get_coin_cents()
	if tray._key_tiles.has("jester_eye"):
		var tile: MeshInstance3D = tray._key_tiles["jester_eye"]
		await _click_at(main.main_camera.unproject_position(tile.global_position))
	await _settle(0.8)
	check(CollectionManager.get_amount("jester_eye") == 0 and CollectionManager.get_amount("crucifix") == 1,
		"a real tray click consumes the eye and grants exactly one Crucifix")
	var cross_reveal := main.main_camera.get_node_or_null("JesterCrucifixReveal") as Card3D
	check(cross_reveal != null, "the Crucifix is revealed at the Jester")
	if cross_reveal != null:
		check(not cross_reveal.top_level and not main.main_camera.is_position_behind(cross_reveal.global_position)
			and viewport.get_visible_rect().has_point(main.main_camera.unproject_position(cross_reveal.global_position)),
			"the Crucifix stays visible while tray closing refocuses the Jester camera")
	check(not tray._key_tiles.has("jester_eye") and GameCurrency.get_coin_cents() == coins_before,
		"the consumed eye leaves the tray without changing money")
	await _capture("jester-crucifix")
	main._on_access_key_requested("jester_eye")
	tray.key_requested.emit("jester_eye")
	check(CollectionManager.get_amount("crucifix") == 1, "repeated item callbacks cannot duplicate the Crucifix")
	CollectionManager.reload_profile()
	GameCurrency.reload_profile()
	check(CollectionManager.get_amount("crucifix") == 1 and CollectionManager.get_amount("jester_eye") == 0 and GameCurrency.cocaine_consumed,
		"the exchange and first cocaine use survive profile reload")
	check(CollectionManager.claim_boiler_puzzle_reward(CollectionManager.BOILER_SOLUTION).is_empty(), "consuming the eye never reopens the boiler reward")
	await _settle()
	var wall := main.upgrade_collection
	check(wall._cards.has("crucifix") and wall._rows[int(wall._card_rows["crucifix"])]["group"] == "upgrade_group_story",
		"the Crucifix appears in Story Cards beside Holy Water")
	await _settle(3.6)
	await _travel_to(0)
	check(bool(CollectionManager.collection.metadata.get("crucifix_return_dialogue_seen", false)) and CollectionManager.get_amount("crucifix") == 1,
		"the real Jester trade triggers the cross conversation on returning home and preserves the Crucifix")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	print("BOILER_PUZZLE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _travel_to(room: int) -> void:
	var door: HospitalDoor
	if room == 0:
		door = main.connected_rooms[main._active_room].get_node("ReturnDoor") as HospitalDoor
	else:
		for area in main.progression_areas:
			if area.room_index == room:
				door = area.door
	_move_pointer(Vector2(-50, -50))
	await _settle(0.5)
	await _face_door(door)
	var expects_cross_return := room == 0 and CollectionManager.has_discovered_card("crucifix") and not bool(CollectionManager.collection.metadata.get("crucifix_return_dialogue_seen", false))
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	if expects_cross_return:
		check(await _wait_until(func(): return main.has_node("SatanCrucifixDialogue")), "returning after the Jester trade starts the Crucifix Satan sequence")
		var conversation := main.get_node_or_null("SatanCrucifixDialogue")
		if conversation != null:
			for index in range(4):
				conversation._advance_dialog_text(100.0)
				conversation.continue_dialog()
	check(await _wait_until(func(): return main._active_room == room and not main._room_transition_active), "real doorway reaches room %d" % room)


func _test_backend() -> void:
	var manager := ControlledCollection.new()
	add_child(manager)
	GameCurrency.cocaine_consumed = false
	var solution: Array[float] = [3.4, 5.1, 5.8, 1.8]
	check(manager.claim_boiler_puzzle_reward(solution).is_empty(), "knowing the solution cannot bypass first cocaine use")
	GameCurrency.cocaine_consumed = true
	for index in range(4):
		for offset: float in [-0.1, 0.1]:
			var wrong := solution.duplicate()
			wrong[index] += offset
			check(manager.claim_boiler_puzzle_reward(wrong).is_empty(), "boiler %d off by %.1f cannot solve the puzzle" % [index + 1, offset])
	check(manager.claim_boiler_puzzle_reward([5.1, 3.4, 1.8, 5.8]).is_empty(), "scene child order cannot replace actual boiler numbers")
	for values: Array in [[3.4, 5.1, 5.8], [NAN, 5.1, 5.8, 1.8], [INF, 5.1, 5.8, 1.8]]:
		var invalid: Array[float] = []
		invalid.assign(values)
		check(manager.claim_boiler_puzzle_reward(invalid).is_empty(), "incomplete and nonfinite pressure inputs are rejected")
	GameCurrency.set_training_session(self, true)
	check(manager.claim_boiler_puzzle_reward(solution).is_empty(), "training cannot award the eye")
	GameCurrency.set_training_session(self, false)
	manager.reject_save = true
	var before := manager.collection.duplicate(true)
	check(manager.claim_boiler_puzzle_reward(solution).is_empty() and manager.collection == before, "a failed reward save preserves collection and completion history")
	manager.reject_save = false
	var reward := manager.claim_boiler_puzzle_reward([3.36, 5.14, 5.76, 1.84])
	check(reward.get("card_id") == "jester_eye" and manager.get_amount("jester_eye") == 1, "the displayed tenths count and a failed save can retry")
	check(manager.claim_boiler_puzzle_reward(solution).is_empty(), "the boiler reward is one-time")
	GameCurrency._rescued_npcs["jester"] = false
	check(manager.exchange_jester_eye().is_empty(), "an unrescued Jester cannot trade")
	GameCurrency._rescued_npcs["jester"] = true
	GameCurrency.set_training_session(self, true)
	check(manager.exchange_jester_eye().is_empty(), "training cannot exchange the eye")
	GameCurrency.set_training_session(self, false)
	manager.reject_save = true
	before = manager.collection.duplicate(true)
	check(manager.exchange_jester_eye().is_empty() and manager.collection == before, "a failed trade save retains the exact eye and grants no Crucifix")
	manager.reject_save = false
	reward = manager.exchange_jester_eye()
	check(reward.get("card_id") == "crucifix" and manager.get_amount("jester_eye") == 0 and manager.get_amount("crucifix") == 1, "retry atomically commits both sides of the Jester trade")
	check(manager.has_discovered_card("jester_eye") and manager.has_discovered_card("crucifix"), "consumption preserves both discovery histories")
	check(manager.claim_boiler_puzzle_reward(solution).is_empty(), "a consumed eye cannot be farmed again")
	manager.collection["cards"].erase("crucifix")
	manager.collection["instances"].clear()
	manager.add_card_instance(CardData.create_instance("jester_eye"))
	check(manager.exchange_jester_eye().is_empty() and manager.get_amount("jester_eye") == 1, "historical Crucifix ownership prevents another exchange after losing it")
	manager.free()
	var eye := CardDatabase.get_card("jester_eye")
	var cross := CardDatabase.get_card("crucifix")
	check(CardData.is_access_key(eye) and CardData.is_unique_unlock(eye) and not CardData.is_combat_card(eye) and not CardDatabase._is_random_reward(eye), "the eye behaves as a unique special tray item excluded from packs and combat")
	check(CardData.is_story_card(cross) and not CardData.is_access_key(cross) and not CardData.is_combat_card(cross) and not CardDatabase._is_random_reward(cross), "the Crucifix is a Story Card excluded from keys, packs and combat")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(not Localization.text("Jester Eye").is_empty() and not Localization.text("Crucifix").is_empty(), "both rewards have localized names in " + locale)
	Localization.set_locale("de")
	check(Localization.text("Jester Eye") == "Jester-Auge" and Localization.text("Crucifix") == "Kruzifix", "the German card names match the requested items")
	check(ResourceLoader.exists(str(eye["image"])) and ResourceLoader.exists(str(cross["image"])), "both new cards have immediately loadable native icons")
