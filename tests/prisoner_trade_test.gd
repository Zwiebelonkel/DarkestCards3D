extends "res://tests/prisoner_dialogue_test.gd"


class ControlledCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	_test_atomic_exchange()
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	GameCurrency.reset_progression()
	GameCurrency._rescued_npcs["prisoner"] = true
	GameCurrency.set_process(false)
	Localization.set_locale("de")
	CollectionManager.add_card("graveyard_key")
	CollectionManager.use_access_key("graveyard_key")
	CollectionManager.add_card_instance(CardData.create_instance("toilet_paper"))
	CollectionManager.add_card_instance(CardData.create_instance("basement_key"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0
	main.room_travel_duration = 0.3
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	viewport.add_child(main)
	dialog = main.prisoner_dialogue
	await _settle(0.4)
	main._on_access_key_requested("toilet_paper")
	check(CollectionManager.get_amount("toilet_paper") == 1 and CollectionManager.get_amount("holy_water") == 0,
		"using Klopapier from the hub cannot remotely trade with the prisoner")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.area_id == "graveyard":
			entrance = area.door
	main._on_room_door_activated(entrance)
	check(await _wait_until(func(): return main._active_room == 2 and not main._room_transition_active), "the normal doorway enters the graveyard")
	main._on_access_key_requested("toilet_paper")
	check(not main._can_use_access_key("toilet_paper") and CollectionManager.get_amount("toilet_paper") == 1,
		"standing far from the crypt cannot use the toilet-paper card")
	_button(MOUSE_BUTTON_LEFT, main.main_camera.unproject_position(main.crypt_gate.gate_area.global_position))
	check(await _wait_until(func(): return main._crypt_gate_close and not main._room_transition_active), "the actual grille click reaches the prisoner viewpoint")
	check(main._can_use_access_key("toilet_paper") and not main._can_use_access_key("basement_key"),
		"only the prisoner's item can be used at the near view")
	main.pause_menu.open()
	main._on_access_key_requested("toilet_paper")
	check(CollectionManager.get_amount("toilet_paper") == 1, "Pause blocks the exchange")
	main.pause_menu.close()
	await _settle()
	check(dialog.open_dialog(), "the prisoner conversation opens after Pause releases input")
	main._on_access_key_requested("toilet_paper")
	check(CollectionManager.get_amount("toilet_paper") == 1, "the active conversation blocks item usage")
	dialog.close_dialog()
	await _wait_until(func(): return not dialog.is_busy())
	main._request_turn(1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(not main._can_use_access_key("toilet_paper"), "turning away from the prisoner disables the exchange")
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	_move_pointer(Vector2(640, 719))
	await _settle(0.7)
	var tray := main.access_key_tray
	check(tray.is_expanded() and tray._key_tiles.has("toilet_paper"), "bottom-edge hover opens the owned item tray directly in front of the prisoner")
	if not tray._key_tiles.has("toilet_paper"):
		get_tree().quit(1)
		return
	check(tray.hint_label.text == Localization.text("Klopapier beim Gefangenen verwenden."), "the tray explains the prisoner's item action")
	await _capture("trade-tray")
	var currency_before := GameCurrency.get_coin_cents()
	var tile: MeshInstance3D = tray._key_tiles["toilet_paper"]
	_button(MOUSE_BUTTON_LEFT, main.main_camera.unproject_position(tile.global_position))
	await _settle(0.8)
	check(CollectionManager.get_amount("toilet_paper") == 0 and CollectionManager.get_amount("holy_water") == 1,
		"a real tray click consumes Klopapier and grants exactly one Weihwasser")
	check(main.get_node_or_null("PrisonerHolyWaterReveal") != null, "the Holy Water reward is revealed in front of the exploration camera")
	check(not tray._key_tiles.has("toilet_paper") and GameCurrency.get_coin_cents() == currency_before,
		"the consumed item leaves the tray without changing money")
	await _capture("holy-water-reward")
	main._on_access_key_requested("toilet_paper")
	tray.key_requested.emit("toilet_paper")
	check(CollectionManager.get_amount("holy_water") == 1, "repeated item callbacks cannot grant additional Holy Water")
	CollectionManager.reload_profile()
	check(CollectionManager.get_amount("holy_water") == 1 and CollectionManager.get_amount("toilet_paper") == 0,
		"the exact exchange survives reloading the save slot")
	GameCurrency.weed_consumed = true
	check(CollectionManager.claim_pump_puzzle_reward([true, false, false, true, false]).is_empty(), "consuming the toilet-paper key cannot farm the pump puzzle again")
	var water := CardDatabase.get_card("holy_water")
	check(CardData.is_story_card(water) and not CardData.is_combat_card(water) and not CardData.is_access_key(water)
		and not CardDatabase._is_random_reward(water), "Holy Water is a special Story Cards item, excluded from combat, door keys and packs")
	check(Localization.text(str(water["name"])) == "Weihwasser", "the German reward name is Weihwasser")
	var wall := main.upgrade_collection
	await _settle(0.2)
	check(wall._cards.has("holy_water") and wall._rows[int(wall._card_rows["holy_water"])]["group"] == "upgrade_group_story",
		"the collection wall puts Holy Water under the new Story Cards heading")
	await _settle(3.0)
	if DisplayServer.get_name() != "headless":
		main.set_process(false)
		wall._set_scroll_row(int(wall._card_rows["holy_water"]))
		main.main_camera.global_position = wall.to_global(Vector3(0, 0, 6.5))
		main.main_camera.look_at(wall.global_position)
		await _settle(0.15)
		await _capture("story-cards-wall")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	print("PRISONER_TRADE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_atomic_exchange() -> void:
	GameCurrency._rescued_npcs["prisoner"] = true
	var manager := ControlledCollection.new()
	add_child(manager)
	check(manager.exchange_prisoner_toilet_paper().is_empty(), "the exchange requires owned toilet paper")
	manager.add_card_instance(CardData.create_instance("toilet_paper"))
	var original := manager.collection.duplicate(true)
	manager.reject_save = true
	check(manager.exchange_prisoner_toilet_paper().is_empty() and manager.collection == original,
		"a failed save retains the exact offered item and cannot grant Holy Water")
	manager.reject_save = false
	var reward := manager.exchange_prisoner_toilet_paper()
	check(reward.get("card_id") == "holy_water" and manager.get_amount("toilet_paper") == 0
		and manager.get_amount("holy_water") == 1, "retry commits both sides of the exchange together")
	check(manager.has_discovered_card("toilet_paper") and manager.has_discovered_card("holy_water"), "both acquisition histories survive consumption")
	manager.collection["cards"].erase("holy_water")
	manager.collection["instances"].clear()
	manager.add_card_instance(CardData.create_instance("toilet_paper"))
	check(manager.exchange_prisoner_toilet_paper().is_empty() and manager.get_amount("toilet_paper") == 1,
		"historical Holy Water ownership prevents duplicate exchanges even after losing the reward")
	manager.free()
