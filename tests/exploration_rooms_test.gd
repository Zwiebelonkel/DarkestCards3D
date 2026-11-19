extends Node

## Uses real Main input. Only the test harness owns an extra viewport.
var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport
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


func _settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	GameCurrency._rescued_npcs["angel"] = true
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	# Exercise room navigation without unrelated timed/story cinematics.
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	# Keep room-navigation checks independent of the one-time moral choice.
	if GameCurrency.get_basement_cat_choice().is_empty():
		GameCurrency.resolve_basement_cat_choice("spared")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
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
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.03
	main.settle_duration = 0.02
	main.mouse_tilt_strength = 0.0
	main.room_travel_duration = 1.2 if DisplayServer.get_name() == "headless" else 3.2
	viewport.add_child(main)
	main.room_changed.connect(func(room: int): arrivals.append(room))
	_move_pointer(Vector2(5, 700))
	await _settle(0.6)
	check(main._active_room == 0 and main._can_travel_between_rooms(), "Main starts in its normal hub")
	check(main.atmo.playing and not main._room_ambience_players[2].playing and not main._room_ambience_players[3].playing, "only the normal ambience plays before visiting an exploration room")
	for room_name in ["GraveyardRoom", "BasementRoom"]:
		var room := main.get_node_or_null(room_name) as Node3D
		check(room != null, room_name + " is a permanent child of Main")
		if room == null:
			continue
		check(room.get_world_3d() == main.get_world_3d() and room.get_viewport() == viewport, room_name + " uses Main's existing world and viewport")
		check(room.find_children("*", "Camera3D", true, false).is_empty() and room.find_children("*", "SubViewport", true, false).is_empty(), room_name + " has no separate camera or destination viewport")
		check(room.get_node_or_null("CameraAnchor") is Marker3D and room.get_node_or_null("ReturnDoor") is HospitalDoor, room_name + " supplies a shared-camera anchor and physical return door")
	for area in main.progression_areas:
		check(area.door.locked and not area.open(), area.area_id + " remains inaccessible with a fresh collection")
	check(main.hub_door.locked, "new room access does not bypass the independent slot-room key")
	for specification in [
		{"area": "graveyard", "card": "graveyard_key", "node": "GraveyardRoom", "index": 2, "return_side": 0},
		{"area": "basement", "card": "basement_key", "node": "BasementRoom", "index": 3, "return_side": 1},
	]:
		await _check_room(specification)
	check(arrivals == [2, 0, 3, 0], "both round trips emit exactly one room_changed event per arrival")
	check(main.hub_door.locked and not get_tree().paused, "physical room visits preserve slot access and return to an unpaused hub")
	main.queue_free()
	await _settle()
	print("EXPLORATION_ROOMS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_room(specification: Dictionary) -> void:
	var area: ProgressionArea
	for candidate in main.progression_areas:
		if candidate.area_id == specification.area:
			area = candidate
	var room := main.get_node_or_null(specification.node) as Node3D
	if area == null or room == null:
		check(false, str(specification.area) + " has its entrance and destination")
		return
	var destination := room.get_node("ReturnDoor") as HospitalDoor
	var anchor := room.get_node("CameraAnchor") as Marker3D
	var room_index := int(specification.index)
	var label := str(specification.area)
	var permanent_room_id := room.get_instance_id()
	CollectionManager.add_card(specification.card)
	check(not CollectionManager.has_area_access(specification.area), label + " ownership waits for explicit key use")
	check(CollectionManager.use_access_key(specification.card), label + " fixture explicitly activates its access key")
	await _settle()
	check(not area.door.locked, label + " key activation unlocks the existing physical entrance")
	check(area.room_index == room_index and not area.is_open(), label + " entrance requests Main travel without opening a screen")
	await _face_door(area.door)
	var hub_pose := main.camera_pivot.global_transform
	# Returns already face inward: graveyard -> table, basement -> pack shop.
	var hub_side := int(specification.return_side)
	hub_pose.basis = Basis.from_euler(Vector3(main._base_x_rotation,
		main._hub_settle_origin_y + deg_to_rad(main.rotation_step_degrees) * hub_side, 0.0))
	var camera_local_basis := main.main_camera.basis
	await _capture(label + "-hub-entrance")
	await _fly(area.door, destination, room_index, label + "-outbound")
	if main._active_room != room_index:
		return
	check(main.camera_pivot.global_transform.is_equal_approx(anchor.global_transform.orthonormalized()), label + " arrival uses its exact shared-camera anchor position and facing at unit scale")
	check(main.main_camera.basis.is_equal_approx(camera_local_basis), label + " arrival preserves Main's camera lens orientation")
	check(room.get_instance_id() == permanent_room_id and not area.is_open(), label + " arrival retains the existing room and creates no overlay")
	check(destination.doorway_area.input_ray_pickable and not main.hub_door.doorway_area.input_ray_pickable and not main.return_door.doorway_area.input_ray_pickable, label + " accepts its return door while remote doors stay inactive")
	# Local stations such as the basement boilers may focus the camera; a
	# remote hub screen must never replace that room's current focus target.
	var focus := main.screen_camera_focus
	var focused_before := focus._focused_screen
	var hovered_before := focus._hovered_screen
	var distant_focus_blocked := focus._active_room == room_index
	for screen_path in ["PackShopMachine/ScreenArea", "UpgradeMachine/ScreenArea"]:
		var hub_screen := main.scene_pivot.get_node(screen_path) as Area3D
		distant_focus_blocked = distant_focus_blocked and not focus._is_screen_available_for_active_side(hub_screen)
		hub_screen.mouse_entered.emit()
		distant_focus_blocked = distant_focus_blocked and focus._focused_screen == focused_before and focus._hovered_screen == hovered_before
	check(distant_focus_blocked, label + " rejects distant hub screen hover while preserving its own room focus")
	await _capture(label + "-arrival")
	var room_pose := main.camera_pivot.global_transform
	for key in [KEY_A, KEY_A, KEY_A, KEY_A, KEY_D, KEY_D, KEY_D, KEY_D]:
		await _press_key(key)
		await _settle(0.12)
	check(main.camera_pivot.global_transform.is_equal_approx(room_pose), label + " eight real A/D inputs preserve its center and exact cardinal facing")
	await _press_key(KEY_D)
	await _settle(0.12)
	check(absf(main.camera_pivot.global_basis.z.dot(room_pose.basis.z)) < 0.001, label + " one D key turns the shared camera by exactly 90 degrees")
	await _face_door(destination)
	await _capture(label + "-return-opening")
	await _escape()
	check(main.pause_menu.visible and get_tree().paused and main._active_room == room_index, label + " Escape opens normal Pause without returning or deleting the room")
	var paused_pose := main.camera_pivot.global_transform
	await _escape()
	await _settle()
	check(not get_tree().paused and room.get_instance_id() == permanent_room_id and main.camera_pivot.global_transform.is_equal_approx(paused_pose), label + " closing Pause restores the same physical room and pose")
	# Losing a key may lock future entry, but cannot strand a current visitor.
	var saved := CollectionManager.collection.duplicate(true)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var changed: Array[String] = [str(specification.card)]
	CollectionManager.collection_changed.emit(changed)
	await _settle()
	check(area.door.locked and not destination.locked and destination.doorway_area.input_ray_pickable and main._active_room == room_index, label + " key removal locks entry while preserving the physical return route")
	await _fly(destination, area.door, 0, label + "-return")
	check(main._active_side == hub_side and main.camera_pivot.global_transform.is_equal_approx(hub_pose), label + " return restores the original hub position facing inward toward its normal station")
	check(not area.open() and not main._room_transition_active, label + " cannot be reentered after its key was removed")
	CollectionManager.collection = saved
	CollectionManager.collection_changed.emit(changed)
	CollectionManager.save_collection()
	await _settle()
	check(not area.door.locked and main._can_travel_between_rooms(), label + " restoring the saved key makes the same entrance available again")
	await _capture(label + "-hub-returned")


func _fly(source: HospitalDoor, destination: HospitalDoor, expected_room: int, label: String) -> void:
	var original_room := main._active_room
	var previous_ambience := main._room_ambience_players.get(original_room, main.atmo) as AudioStreamPlayer
	var next_ambience := main._room_ambience_players.get(expected_room, main.atmo) as AudioStreamPlayer
	var point := main.main_camera.unproject_position(source.doorway_area.global_position)
	check(_door_visible(source), label + " source opening is visible from a normal cardinal camera view")
	var ray_origin := main.main_camera.project_ray_origin(point)
	var ray := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + main.main_camera.project_ray_normal(point) * main.main_camera.far)
	ray.collide_with_areas = true
	check(main.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == source.doorway_area, label + " source opening is unobstructed to the actual camera ray")
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
	check(main._room_transition_active and main._active_room == original_room, label + " real mouse down/up starts a flight before changing the current room")
	if not main._room_transition_active:
		_tracking = false
		return
	check(not main._can_turn() and not main._can_travel_between_rooms() and not source.doorway_area.input_ray_pickable and not destination.doorway_area.input_ray_pickable, label + " flight blocks turns, repeat travel and both doorway hitboxes")
	check(source._travel_open and destination._travel_open, label + " both physical doors open during the camera flight")
	await _press_key(KEY_D)
	await _escape()
	check(main._room_transition_active and not main.pause_menu.visible and not get_tree().paused, label + " actual turn and Escape input cannot interrupt the flight")
	await _settle(main.room_travel_duration * 0.3)
	check(main._room_transition_active and _flight_max_distance > 0.5, label + " camera visibly traverses the passage before arrival")
	check(previous_ambience.playing and next_ambience.playing and previous_ambience.volume_db < main._room_ambience_volume_db and next_ambience.volume_db > -80.0 and next_ambience.volume_db < main._room_ambience_volume_db, label + " old and new atmospheres crossfade during actual door travel")
	await _capture(label + "-midway")
	var deadline := Time.get_ticks_msec() + 15000
	while main._room_transition_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	_tracking = false
	check(not main._room_transition_active and main._active_room == expected_room, label + " finishes at the requested room")
	check(next_ambience.playing and not previous_ambience.playing and is_equal_approx(next_ambience.volume_db, main._room_ambience_volume_db), label + " arrival keeps only the destination atmosphere at its normal level")
	check((next_ambience.stream as AudioStreamMP3).loop and next_ambience.bus == &"SFX" and next_ambience.bus != main.music.bus, label + " ambience loops independently of the filtered music")
	check(_flight_camera_stable and _flight_samples >= 5, label + " keeps the same active Main camera and World3D throughout the flight")
	check(_crossed[0] and _crossed[1], label + " sampled camera path passes through both physical doorway volumes")


func _door_visible(door: HospitalDoor) -> bool:
	var target := door.doorway_area.global_position
	return door.is_visible_in_tree() and not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20.0).has_point(main.main_camera.unproject_position(target))


func _face_door(door: HospitalDoor) -> void:
	_move_pointer(Vector2(5, 700))
	await _settle(0.5)
	for _step in range(4):
		if _door_visible(door):
			return
		await _press_key(KEY_D)
		await _settle(0.12)
	check(false, str(door.get_path()) + " can be faced with normal 90-degree turns")


func _press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		# Main polls Input each frame; viewport-only input does not set it.
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


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	viewport.push_input(event, true)


func _click_at(position: Vector2) -> void:
	_move_pointer(position)
	await _settle(0.04)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://exploration-room-%s.png" % stage)
