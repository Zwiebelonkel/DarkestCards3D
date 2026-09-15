extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var wall: UpgradeWallCollection
var focus: ScreenCameraFocus


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func wait_until(predicate: Callable, timeout_msec: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run wall_collection_focus_test using the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	for card_id in ["corpse", "slot_room_key", "clicker", "clicker_upgrade"]:
		CollectionManager.add_card(card_id)
	for card_id in CollectionManager.STARTING_HAND_CARD_IDS:
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
		preview.size = Vector2(viewport.size)
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
	focus = main.screen_camera_focus
	_move_pointer(Vector2(-50, -50))
	await settle(0.5)
	var hub_origin := main.camera_pivot.global_position
	var camera_basis := main.main_camera.basis
	var base_fov := main.main_camera.fov
	var base_position := main.main_camera.position
	check(not focus.is_focused() and not wall.focus_area.input_ray_pickable, "hub starts with the distant wall focus disabled")
	main._on_room_door_activated(main.hub_door)
	check(await wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "door flight reaches the room with the wall collection")
	await _turn_to(wall.view_side)
	check(wall._interaction_enabled and wall.focus_area.input_ray_pickable, "looking toward the collection enables its whole backing as a hover target")
	check(focus._screens.get(wall.focus_area, -1) == wall.view_side, "wall shares the PackShop camera-focus controller")
	await _capture("before")
	# This point lies between the title and the cards: focus must not require
	# hovering an owned card, and must still work with an empty collection.
	var gap_point := main.main_camera.unproject_position(wall.to_global(Vector3(0, 1.32, 0.14)))
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(gap_point) and wall._card_at(gap_point).is_empty(), "projected hover point is a visible backing gap rather than a card")
	var old_distance := main.main_camera.global_position.distance_to(wall.global_position)
	_move_pointer(gap_point)
	await settle(0.45)
	check(focus.is_focused() and focus._hovered_screen == wall.focus_area, "real pointer hover over the backing gap starts wall focus")
	check(main.main_camera.global_position.distance_to(wall.global_position) < old_distance - 0.5, "hover moves the camera visibly closer to the collection")
	check(is_equal_approx(main.main_camera.fov, focus.focus_fov) and main.main_camera.fov < base_fov, "wall hover applies the same closer field of view as the PackShop")
	var focused_position := main.main_camera.position
	var stable := true
	for sample in range(12):
		await settle(0.05)
		stable = stable and focus.is_focused() and main.main_camera.position.distance_to(focused_position) < 0.002
	check(stable, "a stationary pointer never makes the camera oscillate while its projected hover position moves")
	await _capture("focused")
	var flying_card: Card3D = wall._cards["starting_hand_3"]
	var wall_transform := flying_card.global_transform
	_click(main.main_camera.unproject_position(flying_card.global_position))
	check(wall.is_detail_open() and wall._detail_card == flying_card and flying_card.global_transform.is_equal_approx(wall_transform), "the real clicked Card3D starts flying from its exact captured wall transform")
	check(_count_cards(wall) == 7, "opening creates no second copy of the selected wall card")
	await settle(0.15)
	var entry_position := flying_card.global_position
	check(entry_position.distance_to(wall_transform.origin) > 0.1, "the card visibly travels between its wall slot and the detail view")
	check(not main._can_travel_between_rooms() and focus.is_focused(), "entry flight locks room controls and holds camera focus")
	await _capture("card-entry")
	await settle(0.45)
	check(wall.is_detail_open() and wall._detail_id == "starting_hand_3", "a real card click still opens the intended detail after camera movement")
	check(flying_card.global_position.distance_to(entry_position) > 0.1 and _card_is_framed(flying_card), "entry ends at a fully framed detail position after passing through its intermediate position")
	check(wall._detail_controls.find_children("*", "Button", true, false).is_empty(), "the detail displays no Back or Escape button")
	await _capture("card-detail")
	_move_pointer(Vector2(-50, -50))
	await settle(0.45)
	check(focus.is_focused() and main.main_camera.position.distance_to(focused_position) < 0.002, "open camera-relative detail keeps its focus even when the pointer leaves the wall")
	check(not main._can_travel_between_rooms(), "detail retains the existing room-travel guard")
	var detail_position := flying_card.global_position
	_escape()
	check(wall.is_detail_open() and not main._can_travel_between_rooms() and focus.is_focused(), "closing starts a return flight without prematurely unlocking controls or camera")
	var closing_side := main._active_side
	main._begin_turn(1)
	check(main._active_side == closing_side, "turning remains blocked while the card flies back")
	await settle(0.15)
	check(flying_card.global_position.distance_to(detail_position) > 0.1 and flying_card.global_position.distance_to(wall_transform.origin) > 0.05, "return flight visibly passes between the detail and its original wall slot")
	check(wall.is_detail_open() and focus.is_focused() and main.main_camera.position.distance_to(focused_position) < 0.002, "camera stays still throughout the unfinished return flight")
	var return_position := flying_card.global_position
	wall.close_detail()
	check(flying_card.global_position.is_equal_approx(return_position), "repeated close requests do not snap or restart the returning card")
	await _capture("card-return")
	await settle(0.85)
	check(not wall.is_detail_open() and not main.pause_menu.visible, "Escape closes the focused detail without opening Pause")
	check(wall._cards["starting_hand_3"] == flying_card and flying_card.global_transform.is_equal_approx(wall_transform) and _count_cards(wall) == 7, "return restores the same card to its original wall slot without leaving a duplicate")
	check(_at_base(base_position, base_fov), "closing detail after a real pointer exit restores the original camera position and field of view")
	await _capture("released")
	await _focus_wall()
	await _click_card("clicker_upgrade")
	check(wall.is_detail_open(), "another card can be opened after returning from the first detail")
	_click(Vector2(45, 45))
	await settle(0.65)
	check(not wall.is_detail_open(), "an actual background click returns the card without a visible close button")
	_move_pointer(Vector2(-50, -50))
	await settle(0.45)
	check(_at_base(base_position, base_fov), "leaving after the background click returns smoothly to the room view")
	await _focus_wall()
	# Reuse a card already verified visible above. Later progression rows
	# may sit below the grouped wall's scroll window.
	var rapid_card: Card3D = wall._cards["starting_hand_3"]
	_click(main.main_camera.unproject_position(rapid_card.global_position))
	await settle(0.1)
	var interrupted_position := rapid_card.global_position
	_click(Vector2(45, 45))
	check(wall.is_detail_open() and rapid_card.global_position.is_equal_approx(interrupted_position), "a background click during entry reverses the current card without teleporting")
	await settle(0.7)
	check(not wall.is_detail_open() and wall._cards["starting_hand_3"] == rapid_card and rapid_card.position.is_equal_approx(wall._base_positions["starting_hand_3"]) and _count_cards(wall) == 7, "rapid open-close finishes with one card in the correct slot")
	_move_pointer(Vector2(-50, -50))
	await settle(0.45)
	await _focus_wall()
	main.pause_menu.open()
	await settle(0.45)
	check(main.pause_menu.visible and not focus.is_focused() and _at_base(base_position, base_fov), "Pause interrupts collection hover and leaves no displaced camera")
	_move_pointer(Vector2(-50, -50))
	main.pause_menu.close()
	await settle(0.15)
	check(wall._interaction_enabled and _at_base(base_position, base_fov), "resuming restores wall input without resuming an obsolete camera tween")
	await _focus_wall()
	main._begin_turn(1)
	await settle(0.5)
	check(main._active_side != wall.view_side and not focus.is_focused() and not wall.focus_area.input_ray_pickable, "turning away cancels wall focus and makes the wall inactive")
	check(_at_base(base_position, base_fov) and main.main_camera.basis.is_equal_approx(camera_basis), "turning away leaves no camera position, field-of-view or rotation drift")
	_move_pointer(Vector2(-50, -50))
	await _turn_to(wall.view_side)
	await _focus_wall()
	main._on_room_door_activated(main.return_door)
	_move_pointer(Vector2(-50, -50))
	check(await wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "return door accepts travel after hovering the collection")
	await settle(0.4)
	check(_at_base(base_position, base_fov) and main.camera_pivot.global_position.is_equal_approx(hub_origin), "return flight restores the hub camera with no leaked wall focus")
	check(not wall.focus_area.input_ray_pickable, "collection focus stays disabled in the other room")
	await _turn_to(1)
	var pack_screen := main.scene_pivot.get_node("PackShopMachine/ScreenArea") as Area3D
	_move_pointer(main.main_camera.unproject_position(pack_screen.global_position))
	await settle(0.45)
	check(focus.is_focused() and focus._hovered_screen == pack_screen and is_equal_approx(main.main_camera.fov, focus.focus_fov), "the existing PackShop hover still focuses correctly after a wall visit")
	_move_pointer(Vector2(-50, -50))
	await settle(0.45)
	check(_at_base(base_position, base_fov), "PackShop mouse exit still restores the same camera baseline")
	main.queue_free()
	await settle()
	print("WALL_COLLECTION_FOCUS_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _at_base(position: Vector3, fov: float) -> bool:
	return not focus.is_focused() and main.main_camera.position.distance_to(position) < 0.002 and absf(main.main_camera.fov - fov) < 0.002


func _count_cards(node: Node) -> int:
	var count := 1 if node is Card3D else 0
	for child in node.get_children():
		count += _count_cards(child)
	return count


func _card_is_framed(card: Card3D) -> bool:
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner := card.to_global(Vector3(x * UpgradeWallCollection.CARD_SIZE.x * 0.5, y * UpgradeWallCollection.CARD_SIZE.y * 0.5, 0))
			if not screen.has_point(main.main_camera.unproject_position(corner)):
				return false
	return true


func _turn_to(side: int) -> void:
	while main._active_side != side:
		main._begin_turn(-1)
		await settle(0.15)
	await settle(0.4)


func _focus_wall() -> void:
	_move_pointer(main.main_camera.unproject_position(wall.global_position))
	await settle(0.45)


func _click_card(card_id: String) -> void:
	var card: Card3D = wall._cards[card_id]
	_click(main.main_camera.unproject_position(card.global_position))
	await settle(0.55)


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
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


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://wall-focus-%s.png" % stage) == OK, "saved wall-focus screenshot: " + stage)
