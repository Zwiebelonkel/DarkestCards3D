extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with the isolated match feature test runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	for data: Dictionary in CardDatabase.get_all_cards():
		if CardData.is_combat_card(data) and not DeckManager.is_full():
			var card_id := str(data["id"])
			CollectionManager.create_card_instance(card_id)
			DeckManager.add_card(card_id)
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
	main.mouse_tilt_strength = 0
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	# Exercise and capture the deck after waking up, without waiting five
	# seconds for the unrelated startup lens animation in every UI run.
	main.wakeup_blur_duration = 0.05
	viewport.add_child(main)
	screen = main.get_node("ScenePivot/Collection") as CollectionScreen
	screen.deck_fan_duration = 0.04
	screen.deck_fan_stagger = 0
	screen.deck_fan_reflow_duration = 0.06
	await settle(0.2)
	main._begin_turn(1)
	await settle()
	main._begin_turn(1)
	await settle()
	await screen._open_deck_fan()
	await settle()
	check(main._active_side == 2 and screen._deck_fan_open, "Actual Main camera opens the collection deck")
	check(screen._starting_hand_view._frames.size() == 5 and CollectionManager.get_starting_hand_slot_count() == 0, "New collection shows five locked starting slots")
	await capture("locked")
	var first := _pick_fan_card()
	check(first != null, "Upper card fan remains reachable by the actual pointer")
	if first == null:
		_finish()
		return
	await _drag(first, screen._starting_hand_view.card_position(0))
	check(DeckManager.get_starting_deck_indices().is_empty() and DeckManager.get_deck_cards().size() == 20, "Dropping on a locked slot cannot assign or remove the deck card")
	CollectionManager.create_card_instance("starting_hand_1")
	screen._refresh_starting_hand_slots()
	first = _pick_fan_card()
	var first_index := int(first.get_meta("deck_index"))
	await _drag(first, screen._starting_hand_view.card_position(0))
	check(DeckManager.get_starting_deck_indices() == [first_index], "Real mouse drag assigns the first unlocked slot")
	check(first.global_position.distance_to(screen._starting_hand_view.card_position(0)) < 0.01, "Chosen physical card snaps into its starting slot")
	await _drag(_pick_fan_card(), screen._starting_hand_view.card_position(4))
	check(DeckManager.get_starting_deck_indices() == [first_index], "Higher tiers stay locked after acquiring only Startkarten I")
	for tier in range(2, 6):
		CollectionManager.create_card_instance("starting_hand_%d" % tier)
	screen._refresh_starting_hand_slots()
	await _drag(first, screen._starting_hand_view.card_position(2))
	var expected: Array[int] = [-1, -1, first_index]
	check(DeckManager.get_starting_deck_indices() == expected, "Dragging an assigned card to slot 3 leaves slots 1 and 2 empty")
	check(first.global_position.distance_to(screen._starting_hand_view.card_position(2)) < 0.01, "The chosen card lands in the actual third slot")
	check(screen._starting_hand_view._slot_labels[0].visible and screen._starting_hand_view._slot_labels[1].visible and not screen._starting_hand_view._slot_labels[2].visible, "Empty slots retain their drop labels beside a filled later slot")
	var fifth := _pick_fan_card()
	var fifth_index := int(fifth.get_meta("deck_index"))
	var fifth_pointer := screen.camera.unproject_position(screen._starting_hand_view.card_position(4))
	screen._starting_hand_view.highlight_drop(fifth_pointer, fifth_index)
	var fifth_color := (screen._starting_hand_view._frames[4].material_override as StandardMaterial3D).albedo_color
	var first_color := (screen._starting_hand_view._frames[0].material_override as StandardMaterial3D).albedo_color
	check(fifth_color.is_equal_approx(Color("efffb0")) and first_color.is_equal_approx(StartingHandSlots.OPEN_COLOR), "Drag highlight follows the targeted fifth slot instead of the first empty slot")
	await _drag(fifth, screen._starting_hand_view.card_position(4))
	expected.append(-1)
	expected.append(fifth_index)
	check(DeckManager.get_starting_deck_indices() == expected, "A second card can go directly into slot 5 without filling earlier gaps")
	await capture("sparse")
	var replacement := _pick_fan_card()
	var replacement_index := int(replacement.get_meta("deck_index"))
	await _drag(replacement, screen._starting_hand_view.card_position(4))
	expected[4] = replacement_index
	check(DeckManager.get_starting_deck_indices() == expected and not expected.has(fifth_index), "Dropping onto an occupied slot returns its previous card to the fan")
	check(DeckManager.get_deck_cards().size() == 20 and fifth.global_position.distance_to(screen._starting_hand_view.card_position(4)) > 0.2, "Replacing a start card preserves its deck copy and moves it back into the fan")
	await _drag(first, screen._starting_hand_view.card_position(4))
	expected[2] = replacement_index
	expected[4] = first_index
	check(DeckManager.get_starting_deck_indices() == expected, "Dragging between occupied starting slots swaps the exact two copies")
	check(replacement.global_position.distance_to(screen._starting_hand_view.card_position(2)) < 0.01, "The displaced card moves into the dragged card's previous slot")
	for slot in [1, 0, 3]:
		var card := _pick_fan_card()
		expected[slot] = int(card.get_meta("deck_index"))
		await _drag(card, screen._starting_hand_view.card_position(slot))
	check(DeckManager.get_starting_deck_indices() == expected, "All five slots retain their explicit targets regardless of drag order")
	check(DeckManager.get_deck_cards().size() == 20, "Starting cards remain in the same twenty-card deck")
	for slot in range(5):
		var card := _card_for_index(expected[slot])
		check(card.global_position.distance_to(screen._starting_hand_view.card_position(slot)) < 0.01, "Starting card %d occupies its matching table order" % (slot + 1))
	await capture("selected")
	viewport.size = Vector2i(960, 720)
	screen._reflow_deck_fan()
	await settle()
	var all_visible := true
	for card in screen._deck_fan_cards:
		for corner in [Vector3(-0.39, -0.54, 0), Vector3(0.39, -0.54, 0), Vector3(-0.39, 0.54, 0), Vector3(0.39, 0.54, 0)]:
			all_visible = all_visible and Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(screen.camera.unproject_position(card.to_global(corner)))
	check(all_visible, "Fan and all five starting cards remain inside a resized 4:3 viewport")
	await capture("4by3")
	viewport.size = Vector2i(1280, 720)
	screen._reflow_deck_fan()
	await settle()
	main._begin_turn(1)
	check(main._active_side == 2, "A/D cannot move the shared camera away while editing starting cards")
	var cancelled_card := _pick_fan_card()
	var cancelled_pointer: Vector2 = cancelled_card.get_meta("test_pointer")
	_move(cancelled_pointer)
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, true)
	await settle(0.025)
	main.pause_menu.open()
	check(screen._dragged_fan_card == null and DeckManager.get_starting_deck_indices() == expected, "Opening Pause cancels the drag without changing starting cards")
	main.pause_menu.close()
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, false)
	await settle()
	_move(cancelled_pointer)
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, true)
	await settle(0.025)
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(screen._dragged_fan_card == null and DeckManager.get_deck_cards().size() == 20, "Losing application focus cancels drag without removing a card")
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, false)
	await settle()
	_move(cancelled_pointer)
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, true)
	await settle(0.025)
	var overlay := Control.new()
	overlay.size = Vector2(viewport.size)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.add_child(overlay)
	_button(cancelled_pointer, MOUSE_BUTTON_LEFT, false)
	await settle()
	check(screen._dragged_fan_card == null and DeckManager.get_starting_deck_indices() == expected, "GUI-consumed mouse release cannot leave a stuck drag or edit the deck")
	overlay.queue_free()
	await settle()
	var removed_index := expected[1]
	await _right_click(_card_for_index(removed_index))
	expected[1] = -1
	check(DeckManager.get_starting_deck_indices() == expected and DeckManager.get_deck_cards().size() == 20, "Right-click returns a start card to the fan without shifting other slots")
	await _drag(_card_for_index(expected[0]), screen.camera.global_transform * Vector3(0, 0.65, -2.8))
	expected[0] = -1
	check(DeckManager.get_starting_deck_indices() == expected and DeckManager.get_deck_cards().size() == 20, "Dragging a starting card back to the fan leaves its specific slot empty")
	await screen._close_deck_fan()
	DeckManager.load_deck()
	await screen._open_deck_fan()
	await settle()
	check(DeckManager.get_starting_deck_indices() == expected, "Closing and reopening preserves the saved starting positions and empty slots")
	await screen._on_clear_deck_pressed()
	check(DeckManager.get_starting_deck_indices().is_empty() and screen._starting_hand_view.visible, "Clearing the deck empties all assignments and keeps the unlocked row visible")
	await screen._on_random_deck_pressed()
	check(screen._deck_fan_cards.size() == 20 and DeckManager.get_starting_deck_indices().is_empty(), "Random deck rebuild keeps all copies draggable without stale selections")
	var rebuilt := _pick_fan_card()
	var rebuilt_index := int(rebuilt.get_meta("deck_index"))
	await _drag(rebuilt, screen._starting_hand_view.card_position(0))
	check(DeckManager.get_starting_deck_indices() == [rebuilt_index], "Rebuilt fan cards retain their actual deck-copy indices")
	var outside := Vector2(20, 700)
	_move(outside)
	_button(outside, MOUSE_BUTTON_LEFT, true)
	_button(outside, MOUSE_BUTTON_LEFT, false)
	await settle(0.3)
	check(not screen._deck_fan_open and screen._starting_hand_view == null and screen.cards_root.visible, "Clicking beside the deck removes slot visuals and restores collection cards")
	main.queue_free()
	await settle()
	_finish()


func _pick_fan_card() -> Card3D:
	var selected := DeckManager.get_starting_deck_indices()
	for card in screen._deck_fan_cards:
		if selected.has(int(card.get_meta("deck_index", -1))):
			continue
		for local_y in [0.35, 0.0, -0.3]:
			var point := screen.camera.unproject_position(card.to_global(Vector3(0, local_y, 0.06)))
			var picked := screen._collection_card_under_mouse(point)
			if picked != null and not selected.has(int(picked.get_meta("deck_index", -1))):
				picked.set_meta("test_pointer", point)
				return picked
	return null


func _card_for_index(index: int) -> Card3D:
	for card in screen._deck_fan_cards:
		if int(card.get_meta("deck_index", -1)) == index:
			return card
	return null


func _drag(card: Card3D, to: Vector3) -> void:
	var from: Vector2 = card.get_meta("test_pointer", screen.camera.unproject_position(card.global_position))
	var target := screen.camera.unproject_position(to)
	_move(from)
	await settle(0.025)
	_button(from, MOUSE_BUTTON_LEFT, true)
	await settle(0.025)
	check(screen._dragged_fan_card == card, "Pointer picks exactly the intended visible card copy")
	_move(target)
	await settle(0.04)
	_button(target, MOUSE_BUTTON_LEFT, false)
	await settle(0.24)
	if is_instance_valid(card):
		card.remove_meta("test_pointer")


func _right_click(card: Card3D) -> void:
	var point := screen.camera.unproject_position(card.global_position)
	_move(point)
	await settle(0.025)
	_button(point, MOUSE_BUTTON_RIGHT, true)
	_button(point, MOUSE_BUTTON_RIGHT, false)
	await settle(0.12)


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	viewport.push_input(event, true)


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://starting-hand-%s.png" % stage)


func _finish() -> void:
	print("STARTING_HAND_UI_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
