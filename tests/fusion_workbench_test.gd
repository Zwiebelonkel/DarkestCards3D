extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var forge: FusionWorkbench


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_msec: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run fusion_workbench_test using the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	CardUpgradeManager.upgrades.clear()
	CardUpgradeManager.add_attack("corpse", 3)
	CardUpgradeManager.add_health("corpse", 2)
	var upgraded_copy := CollectionManager.add_card_instance(CardData.create_instance("corpse", 3, [], true))
	var upgraded_copy_id := str(upgraded_copy["instance_id"])
	for index in range(6):
		CollectionManager.add_card("corpse")
	for card_id in ["bat", "froggy", "jerk", "alpaka", "joe", "clicker", "slot_room_key", "developer"]:
		CollectionManager.add_card(card_id)
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
	await settle(0.5)
	check(is_instance_valid(forge) and forge.get_parent() == main.empty_room, "slot room owns the physical fusion workbench")
	check(forge.position.z < -4.0 and main.upgrade_collection.position.z > 4.0 and forge.view_side == 1, "forge stands opposite the upgrade board on the left side")
	check(not forge._interaction_enabled and not main._is_fusion_workbench_busy(), "forge starts inactive while player is in hub")
	var corpse_id := str(CollectionManager.get_instances_for_card("corpse")[0]["instance_id"])
	check(not forge.select_instance(corpse_id), "hidden-room inventory rejects card selection")
	main._on_room_door_activated(main.hub_door)
	check(main._room_transition_active and not forge._interaction_enabled, "room flight keeps forge interaction disabled")
	check(await _wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "normal door travel enters the slot room")
	main._begin_turn(-1)
	check(not forge._interaction_enabled, "turning toward forge does not enable input before camera settles")
	await settle(0.3)
	check(main._active_side == forge.view_side and forge._interaction_enabled and Localization.text(main.side_label.text) == Localization.text("Kartenschmiede") and main.hint_label.text.is_empty(), "left turn enables the forge without an additional room hint")
	var focus_pointer := main.main_camera.unproject_position(forge.focus_area.global_position)
	check(_visible(focus_pointer), "forge rack is reachable from the room camera before focus")
	_move_pointer(focus_pointer)
	await settle(0.6)
	check(main.screen_camera_focus.is_focused(), "hover approaches and centers the wide forge")
	check(is_equal_approx(float(forge.focus_area.get_meta("focus_distance")), 6.6), "forge uses its own full-station focus distance")
	await _check_visible_inventory()
	var upgraded_card := forge._inventory_cards[upgraded_copy_id] as Card3D
	var corpse_base := CardDatabase.get_card("corpse")
	check(int(upgraded_card.card_data.get("attack")) == int(corpse_base["attack"]) + 3 and int(upgraded_card.card_data.get("defense")) == int(corpse_base["defense"]) + 2, "inventory cards include the same purchased stat upgrades as battle cards")
	check(int(upgraded_card.card_data.get("level")) == 3 and CardData.is_holo(upgraded_card.card_data) and str(upgraded_card.card_data.get("instance_id")) == upgraded_copy_id, "inventory preserves the exact owned level and Holo copy")
	for action in ["fuse", "clear", "page_prev", "page_next", "rarity_prev", "rarity_next"]:
		var node := forge._buttons[action]["node"] as Node3D
		var half_size: Vector2 = forge._buttons[action]["size"] * 0.5
		var all_corners_visible := true
		for x_sign in [-1, 1]:
			for y_sign in [-1, 1]:
				var corner := node.to_global(Vector3(half_size.x * x_sign, half_size.y * y_sign, 0.0))
				all_corners_visible = all_corners_visible and _visible(main.main_camera.unproject_position(corner))
		check(all_corners_visible, "entire physical %s control is inside the focused camera view" % action)
	var station_text := ""
	for node: Node in forge.find_children("*", "", true, false):
		if node is Label3D:
			station_text += Localization.text((node as Label3D).text) + "\n"
	check(not station_text.contains(Localization.text("FÜNF KARTEN.")) and not station_text.contains(Localization.text("Verbraucht")) and not station_text.contains(Localization.text("LINKSKLICK")) and not station_text.contains(Localization.text("GLEICHE SELTENHEIT")), "forge has no explanatory subtitle or bottom instruction and consumption texts")
	await capture("overview")
	await _click_button("page_next")
	check(forge.page_index == 1, "physical next-page control reaches the remaining owned cards")
	await _click_button("page_prev")
	check(forge.page_index == 0, "physical previous-page control returns to first cards")
	await _click_button("rarity_next")
	check(forge.rarity_filter == "common", "physical rarity control filters ordinary cards")
	await _check_visible_inventory()
	check(forge.select_instance(upgraded_copy_id), "available copy can be selected before changing its deck reservation")
	main._begin_turn(-1)
	await settle(0.25)
	DeckManager.battle_deck.append("corpse")
	DeckManager.deck_instance_ids.append(upgraded_copy_id)
	main._begin_turn(1)
	await settle(0.35)
	check(forge.selected_instance_ids.is_empty() and not bool(forge._by_id[upgraded_copy_id]["eligible"]), "returning to the forge prunes a selected copy that entered the battle deck while away")
	check(not forge.select_instance(upgraded_copy_id), "new deck reservation rejects reselection of that same exact copy")
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	forge.refresh_collection()
	_move_pointer(main.main_camera.unproject_position(forge.focus_area.global_position))
	await settle(0.4)
	var cards_before_right_click := _physical_card_count()
	var selection_before_right_click := forge.selected_instance_ids.duplicate()
	await _click_card(upgraded_copy_id, MOUSE_BUTTON_RIGHT)
	check(_physical_card_count() == cards_before_right_click and forge.selected_instance_ids == selection_before_right_click, "right-click creates no card preview and leaves the selection unchanged")
	check(main._can_travel_between_rooms() and not main._is_fusion_workbench_busy(), "right-click leaves normal room controls available")
	var side_before := main._active_side
	main._begin_turn(1)
	check(main._active_side != side_before, "A/D can turn away immediately after right-clicking a forge card")
	await settle(0.25)
	main._begin_turn(-1)
	await settle(0.4)
	var chosen_ids: Array[String] = []
	for raw: Variant in forge._inventory_cards:
		var instance_id := str(raw)
		var card := forge._inventory_cards[instance_id] as Card3D
		if str(card.card_data.get("id", "")) == "corpse" and chosen_ids.size() < 5:
			chosen_ids.append(instance_id)
	check(chosen_ids.size() == 5, "five separate copies are available on the ordinary-card rack")
	for instance_id in chosen_ids:
		await _click_card(instance_id)
	check(forge.selected_instance_ids.size() == 5, "five actual inventory clicks fill the five fusion sockets")
	check(CollectionManager.validate_fusion(forge.selected_instance_ids).get("ok", false), "visible five-card selection satisfies the real backend rules")
	await capture("selected")
	var count_before := CollectionManager.get_card_instances().size()
	_click(_button_point("fuse"))
	check(main._is_fusion_workbench_busy() and not main._can_travel_between_rooms(), "forge click starts work and blocks premature room travel")
	main._begin_turn(1)
	check(main._active_side == side_before, "fusion animation blocks A/D rotation")
	main.pause_menu.open()
	var paused_card_transform := forge._slot_cards[0].transform
	await get_tree().create_timer(0.2, true).timeout
	check(get_tree().paused and forge._busy and forge._slot_cards[0].transform.is_equal_approx(paused_card_transform), "pause freezes the in-progress physical fusion without losing its committed reward")
	main.pause_menu.close()
	check(await _wait_until(func(): return forge._result_mode), "forging presents a physical reward card")
	await settle(0.5)
	check(CollectionManager.get_card_instances().size() == count_before - 4 and CollectionManager.get_amount("corpse") == 2, "actual forge action consumes exactly five chosen copies and grants one card")
	check(is_instance_valid(forge._reward_card) and str(forge._reward_card.card_data.get("rarity")) == "uncommon", "five common cards produce an uncommon card")
	check(CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_amount("slot_room_key") == 1 and CollectionManager.get_amount("developer") == 1, "forging preserves special upgrades, room key and highest-rarity copy")
	await capture("reward")
	var reward_card_count := _physical_card_count()
	var reward_transform := forge._reward_card.transform
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_click(main.main_camera.unproject_position(forge._reward_card.global_position), button)
		await settle()
	check(forge._result_mode and _physical_card_count() == reward_card_count and forge._reward_card.transform.is_equal_approx(reward_transform), "clicking the reward preserves its physical presentation without opening a preview")
	await _click_button("fuse")
	check(not forge._result_mode and not main._is_fusion_workbench_busy() and not main.pause_menu.visible, "physical WEITER control leaves reward presentation and releases the room controls")
	main.pause_menu.open()
	check(not forge._interaction_enabled, "pause disables forge interaction before freezing")
	check(not main.screen_camera_focus.is_focused(), "pause immediately releases the forge camera")
	main.pause_menu.close()
	await settle()
	check(forge._interaction_enabled, "resuming restores forge interaction")
	main._begin_turn(-1)
	await settle(0.3)
	check(not forge._interaction_enabled and not main.screen_camera_focus.is_focused(), "turning away disables forge picking and restores normal room framing")
	main._on_room_door_activated(main.return_door)
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "return door remains usable after fusion")
	check(not forge._interaction_enabled, "return to hub leaves hidden forge inactive")
	var collection := main.scene_pivot.get_node("Collection") as CollectionScreen
	var actual_counts := {}
	for row: Array in collection._row_cards.values():
		for card: Card3D in row:
			actual_counts[str(card.card_data.get("id", ""))] = (card.get_node("AmountLabel") as Label3D).text
	var expected_counts := {}
	for raw: Variant in CollectionManager.get_owned_cards():
		var card_id := str(raw)
		if not CardData.is_upgrade_collection_card(CardDatabase.get_card(card_id)):
			expected_counts[card_id] = "x%d" % CollectionManager.get_amount(card_id)
	check(actual_counts == expected_counts and actual_counts.get("corpse") == "x2", "returning hub collection immediately reflects consumed copies and the actual reward without reloading Main")
	main._on_room_door_activated(main.hub_door)
	check(await _wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "forge remains usable on another room visit")
	main._begin_turn(-1)
	await settle(0.3)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var changed_ids: Array[String] = []
	CollectionManager.collection_changed.emit(changed_ids)
	await settle()
	check(forge._inventory_cards.is_empty() and forge._empty_label.visible, "empty inventory replaces the rack with its physical collection hint")
	_move_pointer(main.main_camera.unproject_position(forge.focus_area.global_position))
	await settle(0.4)
	await capture("empty")
	for index in range(5):
		CollectionManager.add_card("corpse")
	await settle()
	for instance: Dictionary in CollectionManager.get_instances_for_card("corpse"):
		forge.select_instance(str(instance["instance_id"]))
	forge.start_fusion()
	check(forge._busy and CollectionManager.get_amount("corpse") == 0, "second fusion commits the five-copy exchange before its animation completes")
	main.queue_free()
	await settle()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	var saved_instances := CollectionManager.get_card_instances()
	check(saved_instances.size() == 1 and CollectionManager.get_amount("corpse") == 0 and str(CardDatabase.get_card(str(saved_instances[0]["card_id"])).get("rarity")) == "uncommon", "closing Main during forging reloads the saved reward without duplicating or restoring consumed inputs")
	print("FUSION_WORKBENCH_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _check_visible_inventory() -> void:
	var reachable := 0
	for raw: Variant in forge._inventory_cards:
		var instance_id := str(raw)
		var card := forge._inventory_cards[instance_id] as Card3D
		var point := main.main_camera.unproject_position(card.global_position)
		if _visible(point) and forge._hit_target(point) == "card:" + instance_id:
			reachable += 1
	check(reachable == forge._inventory_cards.size() and reachable > 0, "every displayed inventory card is visible and individually reachable through its real camera ray")


func _visible(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point)


func _button_point(action: String) -> Vector2:
	var node := forge._buttons[action]["node"] as Node3D
	return main.main_camera.unproject_position(node.global_position)


func _click_button(action: String) -> void:
	_click(_button_point(action))
	await settle(0.18)


func _click_card(instance_id: String, button: int = MOUSE_BUTTON_LEFT) -> void:
	if not forge._inventory_cards.has(instance_id):
		check(false, "requested inventory card remains available to click")
		return
	var card := forge._inventory_cards[instance_id] as Card3D
	_click(main.main_camera.unproject_position(card.global_position), button)
	await settle(0.28)


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = button
		click.pressed = pressed
		viewport.push_input(click, true)


func _physical_card_count() -> int:
	var count := 0
	for node: Node in forge.find_children("*", "", true, false):
		if node is Card3D:
			count += 1
	return count


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://fusion-workbench-%s.png" % stage) == OK, "saved forge screenshot: " + stage)
