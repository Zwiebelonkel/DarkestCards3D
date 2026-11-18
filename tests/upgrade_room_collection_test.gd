extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var wall: UpgradeWallCollection


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


func _wait_until(predicate: Callable, timeout_msec: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run upgrade_room_collection_test using the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	for card_id in ["corpse", "slot_room_key", "clicker", "clicker_upgrade", "clicker_upgrade"]:
		CollectionManager.add_card(card_id)
	for card_id in CollectionManager.STARTING_HAND_CARD_IDS:
		CollectionManager.add_card(card_id)
	CollectionManager.unlock_slot_room()
	var inventory_before := CollectionManager.get_owned_cards()
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
	wall = main.upgrade_collection
	await settle(0.5)
	var normal := main.scene_pivot.get_node("Collection") as CollectionScreen
	check(is_instance_valid(wall) and wall.get_parent() == main.empty_room, "second room owns its independent wall collection")
	check(_normal_ids(normal) == ["corpse"], "hub collection shows combat cards without access keys or upgrade cards")
	check(wall._cards.size() == 8 and wall._cards.has("slot_room_key") and not wall._cards.has("corpse"), "wall retains the used access key alongside seven owned upgrade types")
	check(CollectionManager.is_access_key_used("slot_room_key") and wall._rows[int(wall._card_rows["slot_room_key"])]["group"] == "upgrade_group_access", "using the slot-room key preserves its special-card display in the access group")
	check(wall._amount_labels["clicker_upgrade"].text.contains("2"), "duplicate upgrades display their owned quantity")
	check(not wall._interaction_enabled, "wall ignores input while player is in the hub")
	wall.open_detail("clicker")
	check(not wall.is_detail_open(), "hidden-room upgrade cannot be opened through its direct interaction entry point")
	check(CollectionManager.get_starting_hand_slot_count() == 5 and CollectionManager.get_clicker_upgrade_count() == 2, "separating displays preserves starting slots and clicker upgrades")
	main._on_room_door_activated(main.hub_door)
	check(main._room_transition_active and not wall._interaction_enabled, "camera flight keeps wall input disabled")
	check(await _wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "normal door transition arrives in second room")
	while main._active_side != wall.view_side:
		main._begin_turn(-1)
		await settle(0.12)
	await settle(0.3)
	check(wall._interaction_enabled and main.side_label.text == "Upgrade-Sammlung", "turning toward mounted collection enables it and updates the room hint")
	var visible_count := 0
	for card_id: String in wall._cards:
		var card: Card3D = wall._cards[card_id]
		var point := main.main_camera.unproject_position(card.global_position)
		if Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point) and wall._card_at(point) == card_id:
			visible_count += 1
	check(visible_count == 6 and not wall._cards["starting_hand_5"].visible, "separate Clicker and Starting Hand rows show six cards with the final tier below")
	wall._set_scroll_row(int(wall._card_rows["starting_hand_5"]))
	var last_upgrade: Card3D = wall._cards["starting_hand_5"]
	check(wall._card_at(main.main_camera.unproject_position(last_upgrade.global_position)) == "starting_hand_5", "scrolling reaches the last tier with the real camera ray")
	wall._set_scroll_row(0)
	await capture("wall")
	await _click_card("starting_hand_3")
	check(wall.is_detail_open() and str(wall._detail_card.card_data.get("id")) == "starting_hand_3", "actual wall click opens the chosen real card's detail")
	check(not main._can_travel_between_rooms() and not main.slot_machine.interaction_enabled, "card detail blocks room travel and other room interactions")
	var side_before := main._active_side
	main._begin_turn(1)
	check(main._active_side == side_before, "A/D cannot rotate away with an upgrade detail open")
	check(wall._detail_controls.get_global_rect().size == Vector2(viewport.size), "detail overlay covers the viewport to prevent click-through")
	check(wall._detail_controls.find_children("*", "Button", true, false).is_empty(), "detail has no visible Back or Escape button")
	await capture("detail")
	_escape()
	check(wall.is_detail_open() and not main._can_travel_between_rooms(), "Escape starts a return flight that keeps room controls locked")
	await settle(0.65)
	check(not wall.is_detail_open() and not main.pause_menu.visible and not get_tree().paused, "Escape closes only the upgrade detail and restores room controls")
	await _click_card("clicker_upgrade")
	var flying_card := wall._detail_card
	main.pause_menu.open()
	check(not wall.is_detail_open() and not wall._interaction_enabled, "opening Pause closes the detail and disables wall input")
	check(wall._cards["clicker_upgrade"] == flying_card and flying_card.position.is_equal_approx(wall._base_positions["clicker_upgrade"]), "Pause immediately returns the same card to the wall before freezing the tree")
	main.pause_menu.close()
	await settle()
	check(wall._interaction_enabled, "resuming restores wall interaction")
	await _click_card("clicker_upgrade")
	var inspected_card := wall._detail_card
	CollectionManager.add_card("clicker_upgrade")
	await settle()
	check(wall.is_detail_open() and wall._detail_caption.text.contains("3") and wall._amount_labels["clicker_upgrade"].text.contains("3"), "newly acquired copies update both wall count and open detail immediately")
	check(wall._detail_card == inspected_card, "collection refresh preserves the exact flying card instead of cloning or replacing it")
	_click(Vector2(45, 45))
	await settle(0.65)
	check(not wall.is_detail_open() and wall._cards["clicker_upgrade"] == inspected_card, "actual background click returns the existing card to its wall slot")
	check(CollectionManager.get_starting_hand_slot_count() == 5 and CollectionManager.get_amount("corpse") == inventory_before["corpse"] and CollectionManager.get_amount("slot_room_key") == 1, "reading wall details never consumes or changes combat cards, key or unlocks")
	main._begin_turn(-1)
	await settle(0.15)
	check(not wall._interaction_enabled, "turning away disables wall hover and card clicks")
	main._on_room_door_activated(main.return_door)
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "return door still brings player back to hub")
	check(not wall._interaction_enabled and _normal_ids(normal) == ["corpse"], "returning keeps combat cards and special access keys in their separate collections")
	# A reset/refreshed profile can remove every wall card while Main persists.
	CollectionManager.collection = {"cards": {"corpse": 1}, "instances": []}
	var changed: Array[String] = ["slot_room_key", "clicker", "clicker_upgrade", "starting_hand_1", "starting_hand_2", "starting_hand_3", "starting_hand_4", "starting_hand_5"]
	CollectionManager.collection_changed.emit(changed)
	await settle()
	check(wall._cards.is_empty() and wall._empty_label.visible, "removing all upgrades and access keys refreshes the wall to its empty state")
	CollectionManager.add_card("clicker")
	await settle()
	check(wall._cards.size() == 1 and wall._cards.has("clicker") and not wall._empty_label.visible, "a new upgrade appears on the separate wall without rebuilding Main")
	main.queue_free()
	await settle()
	print("UPGRADE_ROOM_COLLECTION_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _normal_ids(screen: CollectionScreen) -> Array[String]:
	var ids: Array[String] = []
	for row: Array in screen._row_cards.values():
		for card: Card3D in row:
			ids.append(str(card.card_data.get("id", "")))
	ids.sort()
	return ids


func _click_card(card_id: String) -> void:
	var card: Card3D = wall._cards[card_id]
	_click(main.main_camera.unproject_position(card.global_position))
	await settle(0.55)


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)


func _escape() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		viewport.push_input(key, true)


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://upgrade-room-%s.png" % stage) == OK, "saved wall screenshot: " + stage)
