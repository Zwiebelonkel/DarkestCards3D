extends Node
## Runs through Main's real doors and pointer input in an isolated profile.

var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport
var board: BlackMarketBoard
var arrivals: Array[int] = []
var _tracking := false
var _previous_eye := Vector3.ZERO
var _flight_start := Vector3.ZERO
var _flight_max_distance := 0.0
var _flight_samples := 0
var _flight_camera_stable := true
var _flight_camera: Camera3D
var _flight_doors: Array[HospitalDoor] = []
var _crossed: Array[bool] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	print(("PASS: " if condition else "FAIL: ") + message)


func _process(_delta: float) -> void:
	if not _tracking or not is_instance_valid(main):
		return
	var eye := main.main_camera.global_position
	_flight_samples += 1
	_flight_max_distance = maxf(_flight_max_distance, eye.distance_to(_flight_start))
	_flight_camera_stable = _flight_camera_stable and main.main_camera == _flight_camera and viewport.get_camera_3d() == _flight_camera and _flight_camera.get_world_3d() == main.get_world_3d()
	for index in range(_flight_doors.size()):
		var shape := _flight_doors[index]._doorway_shape
		var box := shape.shape as BoxShape3D
		if AABB(-box.size * 0.5, box.size).intersects_segment(shape.to_local(_previous_eye), shape.to_local(eye)) != null:
			_crossed[index] = true
	_previous_eye = eye


func _settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.set_process(false)
	GameCurrency.coins = 1000000.0
	GameCurrency.save()
	SettingsManager.set_fullscreen(false)
	Localization.set_locale("en")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.1
	main.settle_duration = 0.06
	main.mouse_tilt_strength = 0.0
	main.room_travel_duration = 1.2 if DisplayServer.get_name() == "headless" else 3.2
	viewport.add_child(main)
	main.room_changed.connect(func(room: int): arrivals.append(room))
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	var area := main.get_node_or_null("ProgressionAreas/BlackMarket") as ProgressionArea
	var room := main.get_node_or_null("BlackMarketRoom") as Node3D
	check(area != null and room != null, "Main owns the physical Black Market entrance and permanent room")
	if area == null or room == null:
		_finish()
		return
	board = room.get_node_or_null("OfferBoard") as BlackMarketBoard
	var destination := room.get_node_or_null("ReturnDoor") as HospitalDoor
	var anchor := room.get_node_or_null("CameraAnchor") as Marker3D
	check(board != null and destination != null and anchor != null, "market provides its offer board, physical return door and camera anchor")
	if board == null or destination == null or anchor == null:
		_finish()
		return
	check(area.room_index == 4 and main.connected_rooms.has(4), "Black Market uses shared-camera room route 4")
	check(room.get_world_3d() == main.get_world_3d() and room.get_viewport() == viewport, "market belongs to Main's existing World3D and viewport")
	check(room.find_children("*", "Camera3D", true, false).is_empty() and room.find_children("*", "SubViewport", true, false).is_empty(), "market creates no alternate camera or destination viewport")
	check(area.find_child("DestinationScreen", true, false) == null and not area.is_open(), "Black Market no longer creates the old CanvasLayer destination screen")
	check(area.door.locked and not area.open(), "fresh profile cannot bypass Black Market access")
	check(not board.focus_area.input_ray_pickable and _offers_disabled(), "market board is inactive from the hub")
	CollectionManager.add_card("black_market_access")
	await _settle()
	check(not area.door.locked and main.hub_door.locked, "access card unlocks only the physical market entrance")
	await _face_door(area.door)
	var hub_pose := main.camera_pivot.global_transform
	var hub_side := main._active_side
	var base_camera_pose := main.main_camera.transform
	var base_fov := main.main_camera.fov
	var room_identity := room.get_instance_id()
	await _capture("entrance")
	await _fly(area.door, destination, 4, "outbound")
	if main._active_room != 4:
		_finish()
		return
	check(main.camera_pivot.global_transform.is_equal_approx(anchor.global_transform.orthonormalized()), "arrival uses the room's exact physical camera anchor")
	check(board.camera == main.main_camera and viewport.get_camera_3d() == main.main_camera, "offer board uses Main's shared active camera")
	check(room.get_instance_id() == room_identity and not area.is_open(), "entering keeps the permanent room and opens no screen")
	check(destination.doorway_area.input_ray_pickable and not main.hub_door.doorway_area.input_ray_pickable and not area.door.doorway_area.input_ray_pickable, "only the current room's physical return door accepts input")
	await _turn_to(board.view_side)
	var board_visible := true
	for corner in [Vector3(-3, -1.7, 0), Vector3(3, -1.7, 0), Vector3(-3, 1.7, 0), Vector3(3, 1.7, 0)]:
		board_visible = board_visible and viewport.get_visible_rect().has_point(main.main_camera.unproject_position(board.to_global(corner)))
	check(board_visible, "the complete daily board is visible from the room arrival camera")
	await _capture("kiosk")
	await _check_offers(base_camera_pose, base_fov)
	# An access card can disappear while visiting. The physical exit must survive.
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	await _face_door(destination)
	var saved := CollectionManager.collection.duplicate(true)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var changed: Array[String] = ["black_market_access"]
	CollectionManager.collection_changed.emit(changed)
	await _settle()
	check(area.door.locked and not destination.locked and destination.doorway_area.input_ray_pickable, "losing market access preserves the visitor's physical exit")
	await _capture("return-door")
	await _fly(destination, area.door, 0, "return")
	check(main._active_side == hub_side and main.camera_pivot.global_transform.is_equal_approx(hub_pose), "return restores the exact original hub position and cardinal view")
	check(main.main_camera.transform.is_equal_approx(base_camera_pose) and is_equal_approx(main.main_camera.fov, base_fov), "leaving clears board focus and restores the shared camera lens")
	check(not board.focus_area.input_ray_pickable and _offers_disabled(), "board cannot be purchased from after leaving its room")
	check(not area.open() and not main._room_transition_active, "lost access prevents another market entry")
	check(arrivals == [4, 0] and not get_tree().paused, "round trip emits exactly one room change per arrival and returns unpaused")
	CollectionManager.collection = saved
	CollectionManager.collection_changed.emit(changed)
	CollectionManager.save_collection()
	await _capture("hub-returned")
	_finish()


func _check_offers(base_camera_pose: Transform3D, base_fov: float) -> void:
	var focus := main.screen_camera_focus
	check(board.focus_area.input_ray_pickable and focus._screens.get(board.focus_area) == board.view_side, "current market view enables and registers the physical board focus area")
	var snapshot: Dictionary = CollectionManager.get_black_market_offers()
	var offers: Array = snapshot.get("offers", [])
	check(not str(snapshot.get("day", "")).is_empty() and offers.size() >= 2 and board.offer_areas.size() == offers.size(), "board presents the current day's independently purchasable card offers")
	if offers.size() < 2 or board.offer_areas.size() != offers.size():
		return
	var original_distance := main.main_camera.global_position.distance_to(board.focus_area.global_position)
	_move_pointer(main.main_camera.unproject_position(board.focus_area.global_position))
	await _settle(0.8)
	check(focus.is_focused() and focus._hovered_screen == board.focus_area, "actual pointer hover moves the shared camera onto the market board")
	check(main.main_camera.global_position.distance_to(board.focus_area.global_position) < original_distance - 0.3, "board hover visibly brings its offers closer")
	var focused_pose := main.main_camera.transform
	await _settle(0.5)
	check(main.main_camera.transform.is_equal_approx(focused_pose), "board framing remains stable while the pointer stays still")
	await _capture("board-focused")
	var first: Dictionary = offers[0]
	var first_card := str(first.get("card_id", ""))
	var old_upgrades := CardUpgradeManager.upgrades.duplicate(true)
	var preview_attack := int(board._cards[0].card_data.get("attack", 0))
	CardUpgradeManager.add_attack(first_card, 3)
	await _settle()
	check(int(board._cards[0].card_data.get("attack", 0)) == preview_attack + 3, "upgrade changes refresh an existing daily card preview without changing its offer")
	check(not board._cards[0].area.input_ray_pickable and board._cards[0].area.collision_layer == 0, "refreshing a card preview preserves disabled card input and its clear board hitboxes")
	CardUpgradeManager.upgrades = old_upgrades
	CardUpgradeManager.save_upgrades()
	CardUpgradeManager.upgrades_changed.emit(first_card)
	await _settle()
	check(int(board._cards[0].card_data.get("attack", 0)) == preview_attack and board.offers_snapshot == snapshot, "profile upgrade refresh restores preview stats while preserving daily stock and prices")
	var owned_before := CollectionManager.get_amount(first_card)
	var funds_before := GameCurrency.get_coin_cents()
	await _click_offer(0)
	check(CollectionManager.get_amount(first_card) == owned_before + 1, "real click on an offer directly adds its advertised card")
	check(GameCurrency.get_coin_cents() == funds_before - int(first.get("price_cents", 0)), "direct purchase charges precisely the board's advertised cents")
	var after_purchase: Dictionary = CollectionManager.get_black_market_offers()
	check(bool(after_purchase.offers[0].get("sold", false)), "purchased offer is sold for the current day")
	var bought_funds := GameCurrency.get_coin_cents()
	await _click_offer(0)
	check(CollectionManager.get_amount(first_card) == owned_before + 1 and GameCurrency.get_coin_cents() == bought_funds, "repeated click on a sold daily offer neither duplicates the card nor charges again")
	await _capture("offer-purchased")
	CollectionManager.load_collection()
	await _settle()
	check(bool(CollectionManager.get_black_market_offers().offers[0].get("sold", false)), "daily sold state survives collection reload in the real room")
	GameCurrency.coins = 0.0
	GameCurrency.coins_changed.emit(GameCurrency.coins)
	var second_card := str(offers[1].get("card_id", ""))
	var second_owned := CollectionManager.get_amount(second_card)
	await _click_offer(1)
	check(GameCurrency.get_coin_cents() == 0 and CollectionManager.get_amount(second_card) == second_owned and not bool(CollectionManager.get_black_market_offers().offers[1].get("sold", false)), "unaffordable board offer preserves money, collection and availability")
	GameCurrency.coins = 1000000.0
	GameCurrency.coins_changed.emit(GameCurrency.coins)
	await _escape()
	check(main.pause_menu.visible and get_tree().paused and main._active_room == 4, "Escape opens normal Pause while visiting the physical market")
	check(not board.focus_area.input_ray_pickable and _offers_disabled(), "Pause disables the board and every offer hitbox")
	_check_blocked_purchase("Pause")
	check(main.main_camera.transform.is_equal_approx(base_camera_pose) and is_equal_approx(main.main_camera.fov, base_fov), "Pause restores the normal camera before pausing the tree")
	await _escape()
	await _settle(0.1)
	check(not get_tree().paused and board.focus_area.input_ray_pickable, "closing Pause re-enables the market board")
	_move_pointer(Vector2(-50, -50))
	await _settle(0.7)
	check(not focus.is_focused() and main.main_camera.transform.is_equal_approx(base_camera_pose), "leaving the board with the pointer restores the normal room framing")
	await _press_key(KEY_D)
	check(main._phase != MainScene.Phase.IDLE and not board.focus_area.input_ray_pickable and _offers_disabled(), "real room turn disables the board during camera rotation")
	_check_blocked_purchase("camera rotation")
	await _settle(0.4)
	check(not board.focus_area.input_ray_pickable and _offers_disabled(), "another cardinal view cannot purchase offers behind the camera")
	_check_blocked_purchase("another cardinal view")


func _check_blocked_purchase(context: String) -> void:
	var before := CollectionManager.collection.duplicate(true)
	var cents := GameCurrency.get_coin_cents()
	var result := board.purchase_offer(1)
	check(not bool(result.get("ok", false)) and CollectionManager.collection == before and GameCurrency.get_coin_cents() == cents, context + " rejects even an already queued offer purchase without changing the profile")


func _offers_disabled() -> bool:
	for area in board.offer_areas:
		if area.input_ray_pickable:
			return false
	return true


func _fly(source: HospitalDoor, destination: HospitalDoor, expected_room: int, label: String) -> void:
	var original_room := main._active_room
	var point := main.main_camera.unproject_position(source.doorway_area.global_position)
	check(_door_visible(source), label + " source opening is visible from a normal cardinal view")
	var origin := main.main_camera.project_ray_origin(point)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + main.main_camera.project_ray_normal(point) * main.main_camera.far)
	ray.collide_with_areas = true
	check(main.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == source.doorway_area, label + " door is unobstructed to the actual camera ray")
	_flight_camera = main.main_camera
	_flight_start = main.main_camera.global_position
	_previous_eye = _flight_start
	_flight_max_distance = 0.0
	_flight_samples = 0
	_flight_camera_stable = true
	_flight_doors = [source, destination]
	_crossed = [false, false]
	_tracking = true
	await _click_at(point)
	check(main._room_transition_active and main._active_room == original_room, label + " real mouse click begins physical travel before arrival")
	if not main._room_transition_active:
		_tracking = false
		return
	check(not main._can_turn() and not main._can_travel_between_rooms() and not source.doorway_area.input_ray_pickable and not destination.doorway_area.input_ray_pickable, label + " travel blocks turning, repeat travel and both door hitboxes")
	check(not board.focus_area.input_ray_pickable and _offers_disabled(), label + " travel blocks the board and every purchase hitbox")
	_check_blocked_purchase(label + " travel")
	check(source._travel_open and destination._travel_open, label + " both physical doors open for the flight")
	await _press_key(KEY_D)
	await _escape()
	check(main._room_transition_active and not main.pause_menu.visible and not get_tree().paused, label + " turn and Escape inputs cannot interrupt travel")
	await _settle(main.room_travel_duration * 0.3)
	check(main._room_transition_active and _flight_max_distance > 0.5, label + " camera physically moves through the passage")
	await _capture(label + "-midway")
	var deadline := Time.get_ticks_msec() + 15000
	while main._room_transition_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	_tracking = false
	check(not main._room_transition_active and main._active_room == expected_room, label + " arrives at the requested physical room")
	check(_flight_camera_stable and _flight_samples >= 5, label + " retains the same Main camera and World3D throughout travel")
	check(_crossed[0] and _crossed[1], label + " sampled camera path crosses both physical doorway volumes")


func _door_visible(door: HospitalDoor) -> bool:
	var target := door.doorway_area.global_position
	return door.is_visible_in_tree() and not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20.0).has_point(main.main_camera.unproject_position(target))


func _face_door(door: HospitalDoor) -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	for _step in range(4):
		if _door_visible(door):
			return
		await _press_key(KEY_D)
		await _settle(0.4)
	check(false, str(door.get_path()) + " can be faced with normal 90-degree turns")


func _turn_to(side: int) -> void:
	_move_pointer(Vector2(-50, -50))
	for _step in range(4):
		if main._active_side == side:
			break
		await _press_key(KEY_D)
		await _settle(0.4)
	check(main._active_side == side, "normal room turns reach the board's cardinal view")
	await _settle(0.4)


func _press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_cancel"
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().process_frame


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click_offer(index: int) -> void:
	_move_pointer(main.main_camera.unproject_position(board.offer_areas[index].global_position))
	await _settle(0.55)
	await _click_at(main.main_camera.unproject_position(board.offer_areas[index].global_position))
	await _settle(0.1)


func _click_at(point: Vector2) -> void:
	_move_pointer(point)
	await _settle(0.04)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png("res://black-market-%s.png" % stage) == OK, "rendered evidence: " + stage)


func _finish() -> void:
	main.queue_free()
	print("BLACK_MARKET_ROOM_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
