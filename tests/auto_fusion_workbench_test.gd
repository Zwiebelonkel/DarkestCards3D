extends "res://tests/fusion_workbench_test.gd"


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use an isolated project.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	for card_id in ["slot_room_key", "fusion_upgrade_1", "fusion_upgrade_2", "usb_stick"]:
		CollectionManager.add_card(card_id)
	for index in range(10):
		CollectionManager.add_card("corpse")
	var reserved_id: String = CollectionManager.get_instances_for_card("corpse")[0]["instance_id"]
	DeckManager.battle_deck = ["corpse"]
	DeckManager.deck_instance_ids = [reserved_id]
	CollectionManager.unlock_slot_room()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(1280, 720)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	main.wakeup_blur_duration = 0.05
	viewport.add_child(main)
	forge = main.fusion_workbench
	await settle(0.4)
	var before := CollectionManager.collection.duplicate(true)
	forge.start_auto_fusion()
	check(CollectionManager.collection == before and not forge.is_busy(), "hidden-room Auto Fuse cannot consume cards")
	main._on_room_door_activated(main.hub_door)
	check(await _wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "enter the real forge room")
	main._begin_turn(-1)
	await settle(0.35)
	_move_pointer(main.main_camera.unproject_position(forge.focus_area.global_position))
	await settle(0.5)
	for action in ["fuse", "auto_fuse", "clear"]:
		check(_visible(_button_point(action)) and forge._hit_target(_button_point(action)) == "button:" + action, "physical %s button is visible and individually reachable" % action)
	var spare: String = CollectionManager.get_instances_for_card("corpse")[1]["instance_id"]
	check(forge.select_instance(spare), "manual selection can coexist before starting Auto Fuse")
	forge.rarity_filter = "exotic"
	forge.refresh_collection()
	check(forge._inventory_cards.is_empty() and bool(forge._buttons["auto_fuse"]["enabled"]), "Auto Fuse remains available for eligible cards outside the visible rarity filter")
	forge.rarity_filter = ""
	forge.refresh_collection()
	await capture("auto-ready")
	forge.rarity_filter = "exotic"
	forge.refresh_collection()
	var results: Array = []
	forge.fusion_completed.connect(func(result: Dictionary): results.append(result.duplicate(true)))
	_click(_button_point("auto_fuse"))
	check(forge.is_busy() and not main._can_travel_between_rooms(), "actual button click starts the automatic forge animation and locks travel")
	check(results.size() == 1 and results[0].get("fusion_count", 0) == 4, "one click recursively performs all four upgraded fusions across hidden rarity groups")
	check(CollectionManager.get_amount("corpse") == 1 and DeckManager.deck_instance_ids == [reserved_id] and CollectionManager.get_amount("usb_stick") == 1, "actual Auto Fuse preserves the exact deck copy and Secret")
	var committed := CollectionManager.collection.duplicate(true)
	forge.start_auto_fusion()
	_click(_button_point("auto_fuse"))
	check(CollectionManager.collection == committed and results.size() == 1, "double clicks and direct retriggers cannot duplicate a committed batch")
	main.pause_menu.open()
	await get_tree().create_timer(0.15, true).timeout
	check(get_tree().paused and forge.is_busy() and CollectionManager.collection == committed, "pause freezes only presentation after the complete batch is saved")
	main.pause_menu.close()
	check(await _wait_until(func(): return not forge.is_busy()), "Auto Fuse finishes without dismissing each individual reward")
	await settle(0.2)
	check(forge._inventory_root.visible and not forge._result_mode and forge.selected_instance_ids.is_empty() and forge.rarity_filter.is_empty(), "finished batch restores the refreshed full inventory and clears consumed selections")
	check(not bool(forge._buttons["auto_fuse"]["enabled"]) and forge._title.text.contains("4"), "no remaining group disables Auto Fuse and the title reports completed fusions")
	check(main._can_travel_between_rooms(), "finished batch restores ordinary room controls")
	await capture("auto-result")
	Localization.set_locale("en")
	await settle()
	check(forge._title.text == "AUTO FUSE: 4 FUSIONS", "batch summary follows a language switch")
	Localization.set_locale("de")

	# A failure must keep both inputs and inventory controls ready to retry.
	for index in range(3):
		CollectionManager.add_card("corpse")
	await settle()
	before = CollectionManager.collection.duplicate(true)
	var temporary := CollectionManager.SAVE_PATH + ".fusion.tmp"
	check(DirAccess.make_dir_absolute(temporary) == OK, "force a UI batch save failure")
	forge.start_auto_fusion()
	check(not forge.is_busy() and CollectionManager.collection == before and forge._buttons["auto_fuse"]["label"].text == "FEHLGESCHLAGEN", "failed batch consumes nothing and reports failure without locking the UI")
	check(DirAccess.remove_absolute(temporary) == OK, "restore batch saving")
	forge.start_auto_fusion()
	check(forge.is_busy() and CollectionManager.get_amount("corpse") == 1, "retry saves the next batch before its animation")
	committed = CollectionManager.collection.duplicate(true)
	main.queue_free()
	await settle()
	CollectionManager.load_collection()
	check(CollectionManager.collection == JSON.parse_string(JSON.stringify(committed)), "closing the scene mid-animation preserves the entire committed result once")
	print("AUTO_FUSION_WORKBENCH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
