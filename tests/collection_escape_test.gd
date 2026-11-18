extends Node3D

var failures := 0
var checks := 0
var viewport: SubViewport
var main: MainScene
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.18) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func escape(echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		event.echo = echo and pressed
		viewport.push_input(event, true)


func click(pointer: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = pointer
		viewport.push_input(event, true)


func card(card_id: String = "corpse") -> Card3D:
	for candidate: Card3D in screen._base_positions:
		if candidate.card_data["id"] == card_id:
			return candidate
	return null


func no_menu() -> bool:
	return not get_tree().paused and (not is_instance_valid(main) or not main.pause_menu.visible)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use an isolated project with redirected saves.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.clear_profile_state()
	for index in range(3):
		CollectionManager.create_card_instance("corpse")
	CollectionManager.create_card_instance("wanderer")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	main.wakeup_blur_duration = 0.02
	viewport.add_child(main)
	screen = main.get_node("ScenePivot/Collection") as CollectionScreen
	screen.detail_duration = 0.12
	screen.deck_fan_duration = 0.12
	screen.deck_fan_stagger = 0.0
	await settle(0.5)
	main._begin_turn(1)
	await settle()
	main._begin_turn(1)
	await settle()
	check(main._active_side == 2, "actual hub faces the collection")
	await _check_details()
	await _check_deck()
	escape()
	check(main.pause_menu.visible and get_tree().paused, "Escape opens Pause normally after the collection views have closed")
	escape()
	check(no_menu(), "a subsequent Escape resumes normally")
	main.queue_free()
	await settle()
	# Standalone collection keeps MenuNavigation enabled. Consuming Escape in
	# _input must also prevent an unintended change to the main menu here.
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D")
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.detail_duration = 0.05
	screen.deck_fan_duration = 0.05
	screen.deck_fan_stagger = 0.0
	viewport.add_child(screen)
	screen.camera.make_current()
	await settle()
	await screen._open_detail_card(card())
	escape()
	await settle()
	check(screen._detail_card == null and is_instance_valid(get_tree().current_scene), "standalone detail closes without navigating to the main menu")
	await screen._open_deck_fan()
	escape()
	await settle(0.35)
	check(not screen._deck_fan_open and screen.cards_root.visible, "standalone deck view also closes with Escape")
	viewport.queue_free()
	await settle()
	print("COLLECTION_ESCAPE_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _check_details() -> void:
	var selected := card()
	var original := selected.transform
	await screen._open_detail_card(selected)
	escape()
	check(screen._detail_card == null and screen._detail_tween_running, "Escape starts the same card return flight as an outside click")
	check(no_menu(), "detail Escape does not open Pause")
	escape(true)
	escape()
	check(no_menu(), "held or repeated Escape during the return flight is consumed")
	await settle(0.35)
	check(not screen._detail_tween_running and selected.transform.is_equal_approx(original), "Escape restores the card's original collection transform")
	screen._open_detail_card(selected)
	escape()
	await settle(0.5)
	check(screen._detail_card == null and not screen._detail_tween_running and no_menu(), "Escape during entry queues a complete safe return")
	await screen._open_detail_card(selected)
	screen._show_next_detail_card(1)
	escape()
	await settle(0.5)
	check(screen._detail_card == null and not screen._detail_tween_running and no_menu(), "Escape also closes after a card-switch animation")
	await screen._open_detail_card(selected)
	var center := screen.camera.unproject_position(selected.global_position)
	check(screen._detail_rotation.begin(selected, screen.camera, center), "detail drag fixture starts on the card")
	escape()
	check(not screen._detail_rotation.dragging and no_menu(), "Escape cancels a held rotation and returns the card")
	await settle(0.35)
	await screen._open_detail_card(selected)
	click(Vector2(-80, -80))
	await settle(0.35)
	check(screen._detail_card == null and no_menu(), "outside click still closes the same detail view")


func _check_deck() -> void:
	await screen._open_deck_fan()
	check(screen._deck_fan_open and screen._deck_fan_cards.is_empty(), "empty deck is visibly open")
	escape()
	check(not screen._deck_fan_open and no_menu(), "Escape closes an empty deck view without Pause")
	await settle(0.35)
	check(screen.cards_root.visible and not screen.clear_deck_button.visible and not screen.random_deck_button.visible, "closing restores the collection and hides deck controls")
	for index in range(3):
		DeckManager.add_card("corpse")
	DeckManager.add_card("wanderer")
	var original_deck := DeckManager.get_deck_cards().duplicate()
	await screen._open_deck_fan()
	check(screen._deck_fan_cards.size() == 4, "populated deck fixture shows all four copies")
	escape()
	escape()
	await settle(0.35)
	check(not screen._deck_fan_open and screen._deck_fan_cards.is_empty() and no_menu(), "Escape returns all deck cards and consumes repeat presses during exit")
	check(DeckManager.get_deck_cards() == original_deck, "closing the deck changes no saved deck cards")
	screen._open_deck_fan()
	escape()
	await settle(0.6)
	check(not screen._deck_fan_open and not screen._deck_fan_tween_running and no_menu(), "Escape during deck entry closes after the cards finish entering")
	await screen._open_deck_fan()
	var selected: Card3D = screen._deck_fan_cards[0]
	screen._start_drag_fan_card(selected, str(selected.card_data["id"]))
	check(screen._dragged_fan_card != null, "deck drag fixture is active")
	escape()
	await settle(0.35)
	check(screen._dragged_fan_card == null and not screen._deck_fan_open and no_menu(), "Escape cancels an active deck drag and closes the view")
	check(DeckManager.get_deck_cards() == original_deck, "Escape during drag does not remove a deck card")
	await screen._open_deck_fan()
	click(Vector2(-80, -80))
	await settle(0.35)
	check(not screen._deck_fan_open and no_menu(), "outside click still closes the populated deck")
