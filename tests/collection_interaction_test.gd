extends Node3D

var failures := 0
var checks := 0
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(duration: float = 0.08) -> void:
	await get_tree().create_timer(duration).timeout
	# SceneTree timers run before tweens; allow a full tween step even during
	# the first long frame spent compiling card shaders in the visual run.
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	# Headless windows default to 64x64, where the menu button covers the ray target.
	get_tree().root.size = Vector2i(1280, 720)
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	var combat_ids: Array[String] = []
	for data: Dictionary in CardDatabase.get_all_cards():
		if CardData.is_combat_card(data):
			combat_ids.append(str(data["id"]))
			if combat_ids.size() == 2:
				break
	for card_id in combat_ids:
		for copy in range(12):
			CollectionManager.create_card_instance(card_id)
	CollectionManager.create_card_instance("clicker")
	CollectionManager.create_card_instance("clicker_upgrade")
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.hover_duration = 0.03
	screen.detail_duration = 0.04
	screen.add_button_slide_duration = 0.03
	screen.deck_fan_duration = 0.03
	screen.deck_fan_stagger = 0.0
	add_child(screen)
	await _settle()
	var cards: Dictionary = {}
	for card: Card3D in screen._base_positions.keys():
		cards[str(card.card_data["id"])] = card
		# Keep input enabled while removing automatic ray hits; drive the
		# actual Area3D signals independently of the desktop pointer.
		card.area.collision_layer = 0
	await get_tree().physics_frame
	await get_tree().process_frame
	screen._reset_collection_hover()
	var first: Card3D = cards[combat_ids[0]]
	var second: Card3D = cards[combat_ids[1]]
	for frame in range(120):
		if first.area.mouse_entered.is_connected(screen._on_card_hovered.bind(first)):
			break
		await get_tree().process_frame
	check(first.area.mouse_entered.is_connected(screen._on_card_hovered.bind(first)), "collection entrance animation enables its area input")
	var label := first.get_node("AmountLabel") as Label3D
	check(label.position.x > 0.0 and label.position.y > 0.4, "collection count sits at the top right of the card")
	check(label.text == "x12" and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "multi-digit amounts grow left from their right edge")

	first.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(first), "collection card lifts on its first hover")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	first.area.input_event.emit(screen.camera, click, first.global_position, Vector3.FORWARD, 0)
	first.area.mouse_exited.emit()
	await _settle()
	check(screen._detail_card == first, "click opens the hovered card in detail")
	check(screen._hovered_cards.is_empty(), "leaving the area during detail does not retain collection hover")
	await screen._close_detail_card()
	first.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(first), "the same card lifts again after closing its detail")
	first.area.mouse_entered.emit()
	first.area.mouse_exited.emit()
	await _settle()
	check(first.position.is_equal_approx(screen._base_positions[first]), "duplicate enter events do not require extra exits to lower a card")
	first.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(first), "hover remains reusable after duplicate signals")

	# Opening detail without an intervening exit also resets the hover state.
	await screen._open_detail_card(first)
	screen._show_next_detail_card(1)
	await _settle(0.1)
	await screen._close_detail_card()
	first.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(first), "original card lifts after navigating to another detail and back to collection")
	first.area.mouse_exited.emit()
	second.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(second), "another collection card also remains hoverable after detail navigation")
	await screen._open_deck_fan()
	second.area.mouse_exited.emit()
	await screen._close_deck_fan()
	second.area.mouse_entered.emit()
	await _settle()
	check(_is_raised(second), "collection hover recovers after opening and closing the deck fan")
	second.area.mouse_exited.emit()
	await _settle()

	check(not cards.has("clicker") and not cards.has("clicker_upgrade"), "upgrade cards are absent from the normal collection")
	screen._detail_card_id = "clicker"
	screen._on_add_to_deck_pressed()
	check(DeckManager.get_card_count("clicker") == 0, "stale special-card callbacks cannot add an upgrade to the deck")
	screen._detail_card_id = ""
	await screen._open_detail_card(first)
	check(screen._deck_button.visible and not screen._deck_button.disabled, "combat card restores the Add to Deck action")
	screen._on_add_to_deck_pressed()
	check(label.text == "x11", "top-right count updates after a combat card enters the deck")
	await screen._close_detail_card()
	await _check_right_click(first, second)
	await screen._open_deck_fan()
	await screen._on_random_deck_pressed()
	var all_combat := true
	for card_id in DeckManager.get_deck_cards():
		all_combat = all_combat and CardData.is_combat_card(CardDatabase.get_card(card_id))
	check(all_combat and DeckManager.get_deck_cards().size() == DeckManager.MAX_DECK_SIZE, "random deck fills with combat cards while skipping special copies")
	await screen._close_deck_fan()
	await _capture(first)
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("COLLECTION_INTERACTION_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _check_right_click(first: Card3D, second: Card3D) -> void:
	var original_camera := screen.camera.global_transform
	var original_positions := screen._base_positions.duplicate()
	var original_rotations := screen._base_rotations.duplicate()
	var original_scales := screen._base_scales.duplicate()
	screen._reset_collection_hover()
	screen.camera.global_position = Vector3(0, 0, 3)
	screen.camera.look_at(Vector3.ZERO)
	for card: Card3D in [first, second]:
		card.position = Vector3.ZERO if card == first else Vector3(0, 0, -0.2)
		card.rotation_degrees = Vector3.ZERO
		card.scale = Vector3.ONE
		screen._base_positions[card] = card.position
		screen._base_rotations[card] = card.rotation_degrees
		screen._base_scales[card] = card.scale
		card.area.collision_layer = 1
		card.area.input_ray_pickable = true
	var first_id := str(first.card_data["id"])
	var second_id := str(second.card_data["id"])
	while DeckManager.can_add_card(first_id):
		DeckManager.add_card(first_id)
	DeckManager.add_card(second_id)
	screen._refresh_collection_amount_labels()
	var label := first.get_node("AmountLabel") as Label3D
	check(label.text == "x0", "right-click fixture has every owned copy in the deck")
	await get_tree().physics_frame
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = screen.camera.unproject_position(first.global_position)
	get_viewport().push_input(motion, true)
	await _settle()
	var cursor := screen.camera.unproject_position(first.global_position)
	check(screen._collection_card_under_mouse(cursor) == first, "overlapping card picking resolves the visible front card")
	_push_right_button(cursor, true)
	check(DeckManager.get_card_count(first_id) == 11 and label.text == "x1", "right-click removes one copy even when all copies were in the deck")
	check(DeckManager.get_card_count(second_id) == 1, "the same right-click leaves the overlapping rear card in the deck")
	check(CollectionManager.get_amount(first_id) == 12, "removing from the deck preserves owned collection copies")
	_push_right_button(cursor, false)
	check(DeckManager.get_card_count(first_id) == 11, "right button release does not remove another copy")
	_push_right_button(cursor, true)
	_push_right_button(cursor, false)
	DeckManager.load_deck()
	check(DeckManager.get_card_count(first_id) == 10 and label.text == "x2", "repeated right-click removal persists and updates the available count")
	while DeckManager.remove_card(first_id):
		pass
	screen._refresh_collection_amount_labels()
	_push_right_button(cursor, true)
	_push_right_button(cursor, false)
	check(DeckManager.get_card_count(first_id) == 0 and DeckManager.get_card_count(second_id) == 1, "right-clicking a card absent from the deck does not remove the card behind it")
	DeckManager.add_card(first_id)
	first.area.input_ray_pickable = false
	_push_right_button(cursor, true)
	_push_right_button(cursor, false)
	check(DeckManager.get_card_count(first_id) == 1, "inactive collection areas cannot remove deck cards")
	first.area.input_ray_pickable = true
	await screen._open_detail_card(first)
	await get_tree().physics_frame
	_push_right_button(screen.camera.unproject_position(first.global_position), true)
	_push_right_button(screen.camera.unproject_position(first.global_position), false)
	check(DeckManager.get_card_count(first_id) == 1, "right-click is ignored while a card is in detail view")
	await screen._close_detail_card()
	for card: Card3D in [first, second]:
		card.area.input_ray_pickable = false
		card.area.collision_layer = 0
	screen._reset_collection_hover()
	screen._base_positions = original_positions
	screen._base_rotations = original_rotations
	screen._base_scales = original_scales
	for card: Card3D in [first, second]:
		card.position = original_positions[card]
		card.rotation_degrees = original_rotations[card]
		card.scale = original_scales[card]
	screen.camera.global_transform = original_camera
	screen._refresh_collection_amount_labels()
	await get_tree().physics_frame
	await screen._open_deck_fan()
	await get_tree().physics_frame
	var fan_card: Card3D = screen._deck_fan_cards.back()
	cursor = screen.camera.unproject_position(fan_card.global_position)
	var picked := screen._collection_card_under_mouse(cursor)
	check(picked != null and screen._deck_fan_cards.has(picked), "deck fan exposes its front card for right-click")
	if picked != null:
		var picked_id := str(picked.card_data["id"])
		var count_before := DeckManager.get_card_count(picked_id)
		_push_right_button(cursor, true)
		_push_right_button(cursor, false)
		check(DeckManager.get_card_count(picked_id) == count_before - 1, "right-click also removes exactly one copy from the open deck fan")
		await _settle(0.3)
	await screen._close_deck_fan()
	await _settle(0.3)


func _push_right_button(cursor: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = cursor
	event.global_position = cursor
	get_viewport().push_input(event, true)


func _is_raised(card: Card3D) -> bool:
	var target: Vector3 = screen._base_positions[card] + screen.hover_lift
	var raised := card.position.is_equal_approx(target)
	if not raised:
		print("Hover position: ", card.position, " expected: ", target, " state: ", screen._hovered_cards.has(card))
	return raised


func _capture(card: Card3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	screen._reset_collection_hover()
	for sibling: Node in screen.cards_root.get_children():
		if sibling is Node3D:
			sibling.visible = sibling == card
	card.position = Vector3.ZERO
	card.rotation_degrees = Vector3.ZERO
	card.scale = Vector3.ONE
	(card.get_node("AmountLabel") as Label3D).text = "x12"
	screen.camera.global_position = Vector3(0, 0, 2.0)
	screen.camera.look_at(Vector3.ZERO)
	screen.get_node("table").visible = false
	screen.get_node("angel").visible = false
	screen.get_node("decorations").visible = false
	screen.get_node("MenuNavigation").visible = false
	screen._deck_overview_button.visible = false
	screen.empty_label.visible = false
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.03, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	world.environment = environment
	add_child(world)
	await _settle(0.2)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("res://collection-amount-top-right.png")
