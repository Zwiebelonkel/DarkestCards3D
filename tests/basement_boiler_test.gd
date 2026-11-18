extends Node3D
## Real viewport input, room travel and shared camera ownership for cosmetic boilers.

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var focus: ScreenCameraFocus
var boilers: Array[BasementBoiler] = []
var saved_files := {}
var saved_collection := {}
var saved_catalog: Array[Dictionary] = []
var saved_coins := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 8000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run only in an isolated project copy with redirected saves.")
		get_tree().quit(1)
		return
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	CollectionManager.add_card("basement_key")
	check(CollectionManager.use_access_key("basement_key"), "boiler fixture explicitly activates basement access")
	# Resolve the unrelated encounter in this fixture so cardinal turns stay free.
	GameCurrency._basement_cat_choice = "shot"
	GameCurrency.coins = 42.75
	check(GameCurrency.save(), "the isolated boiler fixture saves successfully")
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
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.14
	main.settle_duration = 0.06
	main.room_travel_duration = 0.35
	viewport.add_child(main)
	focus = main.screen_camera_focus
	for child in main.get_node("BasementRoom/BoilerEquipment").get_children():
		if child is BasementBoiler:
			boilers.append(child as BasementBoiler)
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	check(boilers.size() == 4 and main.basement_boilers.size() == 4, "all four authored boilers have their own interactive controller")
	if boilers.size() != 4:
		_finish()
		return
	check(_all_disabled(), "the hub cannot hover or operate remote basement boilers")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.room_index == 3:
			entrance = area.door
	await _face_door(entrance)
	await _click_at(main.main_camera.unproject_position(entrance.doorway_area.global_position))
	check(main._room_transition_active and _all_disabled(), "a real basement door click starts travel with boiler input disabled")
	check(await _wait_until(func(): return main._active_room == 3 and not main._room_transition_active), "the physical doorway flight arrives in the basement")
	await _settle(0.2)
	await _turn_to(boilers[0].view_side)
	saved_files = _profile_files()
	saved_collection = CollectionManager.collection.duplicate(true)
	saved_catalog = CardDatabase.cards.duplicate(true)
	saved_coins = GameCurrency.get_coin_cents()
	for boiler in boilers:
		await _check_boiler(boiler)
	await _check_pressure_limits(boilers[0])
	await _check_direct_refocus()
	await _check_input_gates(boilers[0])
	check(CollectionManager.collection == saved_collection and GameCurrency.get_coin_cents() == saved_coins, "turning the valves changes neither cards nor currency")
	check(CardDatabase.cards == saved_catalog and _profile_files() == saved_files, "cosmetic boiler interaction leaves the catalog and all profile save bytes unchanged")
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	var return_door := main.get_node("BasementRoom/ReturnDoor") as HospitalDoor
	await _face_door(return_door)
	await _click_at(main.main_camera.unproject_position(return_door.doorway_area.global_position))
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "the real return door remains usable after boiler interaction")
	check(_all_disabled() and not focus.is_focused(), "leaving the basement releases boiler input and camera focus")
	_finish()


func _check_boiler(boiler: BasementBoiler) -> void:
	await _hover_boiler(boiler)
	var label := str(boiler.name)
	check(boiler.interaction_enabled and boiler.wheel_area.input_ray_pickable, label + " enables its own wheel in the visible basement view")
	check(focus.is_focused() and focus._hovered_screen == boiler.focus_area, label + " real body hover selects this boiler's camera focus")
	var focused_pose := main.main_camera.transform
	await _settle(0.25)
	check(main.main_camera.transform.is_equal_approx(focused_pose), label + " focus stays stable with a stationary pointer")
	await _capture(label + "-focused")
	var wheel := boiler.get_node("RedValveWheel") as Node3D
	var spoke_a := boiler.get_node("WheelSpokeA") as Node3D
	var spoke_b := boiler.get_node("WheelSpokeB") as Node3D
	var needle := boiler.needle
	var digits := boiler.digits
	var wheel_before := wheel.transform
	var spoke_a_before := spoke_a.transform
	var spoke_b_before := spoke_b.transform
	var needle_before := needle.transform
	var pressure_before := boiler.pressure
	var digits_before := digits.text
	var untouched := {}
	for other in boilers:
		if other != boiler:
			untouched[other] = other.pressure
	await _begin_drag(boiler)
	check(boiler.is_dragging(), label + " real left press on the wheel begins circular dragging")
	if not boiler.is_dragging():
		return
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "an active valve drag owns navigation until released")
	seed(671342)
	var expected_random := randi()
	seed(671342)
	check(_wheel_point(boiler, -PI * 0.5).x > _wheel_point(boiler, 0.0).x,
		label + " clockwise gesture moves from the wheel top toward screen right")
	_rotate_pointer(boiler, 0.0, -PI * 0.65)
	check(randi() == expected_random, label + " circular dragging leaves the shared battle and reward RNG untouched")
	check(boiler.pressure > pressure_before and boiler.pressure <= 6.0, label + " clockwise input raises pressure within the gauge range")
	check(needle.rotation.z < deg_to_rad(135.0 - pressure_before * 45.0), label + " higher pressure turns the needle clockwise along the printed scale")
	check(not wheel.transform.is_equal_approx(wheel_before) and not spoke_a.transform.is_equal_approx(spoke_a_before) and not spoke_b.transform.is_equal_approx(spoke_b_before), label + " turns the complete valve wheel and both spokes together")
	check(not needle.transform.is_equal_approx(needle_before) and digits.text != digits_before and absf(digits.text.to_float() - boiler.pressure) <= 0.051, label + " moves its needle and updates the displayed pressure together")
	check(digits.is_rolling(), label + " real valve input starts the mechanical number drums")
	var independent := true
	for other: BasementBoiler in untouched:
		independent = independent and is_equal_approx(other.pressure, float(untouched[other]))
	check(independent, label + " leaves every other boiler's pressure unchanged")
	var pressure_forward := boiler.pressure
	_rotate_pointer(boiler, -PI * 0.65, -PI * 0.25)
	check(boiler.pressure < pressure_forward, label + " counterclockwise input lowers pressure")
	await _capture(label + "-turned")
	_move_pointer(Vector2(-40, -40), true)
	await _settle(0.2)
	check(boiler.is_dragging() and focus.is_focused() and focus._hovered_screen == boiler.focus_area and main.main_camera.transform.is_equal_approx(focused_pose), label + " retains camera framing while dragging outside the boiler")
	_send_button(Vector2(-40, -40), false)
	await _settle(0.5)
	check(not boiler.is_dragging() and not focus.is_focused() and main._can_turn(), label + " releasing outside ends dragging and returns the camera")
	check(not digits.is_rolling() and is_equal_approx(digits._roll_steps, boiler.pressure * 10.0), label + " released number drums seat on the exact displayed tenth")
	var released_pressure := boiler.pressure
	_move_pointer(_wheel_point(boiler, PI))
	await _settle(0.1)
	check(is_equal_approx(boiler.pressure, released_pressure), label + " pointer movement after release cannot keep turning the wheel")


func _check_pressure_limits(boiler: BasementBoiler) -> void:
	await _hover_boiler(boiler)
	await _begin_drag(boiler)
	# Multiple complete revolutions exercise the angle wrap at +/-PI.
	for turn in range(3):
		_rotate_pointer(boiler, -TAU * turn, -TAU * (turn + 1))
	check(is_equal_approx(boiler.pressure, 6.0) and boiler.digits.text == "6.0", "clockwise turns cross the angle wrap and clamp at six bar")
	var high_tip := boiler.needle.basis * Vector3.UP
	check(high_tip.x > 0 and high_tip.y < 0, "six-bar pointer reaches the lower-right end of the printed scale")
	var end_angle := -TAU * 3
	_rotate_pointer(boiler, end_angle, end_angle + 0.1)
	check(boiler.pressure < 6.0, "reversing immediately leaves the upper stop without a dead zone")
	for turn in range(3):
		_rotate_pointer(boiler, end_angle + 0.1 + TAU * turn, end_angle + 0.1 + TAU * (turn + 1))
	check(is_zero_approx(boiler.pressure) and boiler.digits.text == "0.0", "counterclockwise turns cross the angle wrap and clamp at zero bar")
	var low_tip := boiler.needle.basis * Vector3.UP
	check(low_tip.x < 0 and low_tip.y < 0, "zero-bar pointer reaches the lower-left end of the printed scale")
	_send_button(_wheel_point(boiler, 0.1), false)
	await _settle(0.1)
	check(not boiler.is_dragging() and is_equal_approx(boiler.pressure, boiler.digits.text.to_float()), "an endpoint release preserves the exact displayed pressure")
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)


func _check_direct_refocus() -> void:
	await _hover_boiler(boilers[1])
	var before := main.main_camera.transform
	var point := _visible_focus_point(boilers[2])
	check(point.is_finite(), "the adjacent boiler remains reachable from a focused boiler")
	if not point.is_finite():
		return
	_move_pointer(point)
	await _settle(0.55)
	check(focus._hovered_screen == boilers[2].focus_area and focus._focused_screen == boilers[2].focus_area, "real hover directly into another boiler on the same side replaces the focus target")
	check(not main.main_camera.transform.is_equal_approx(before), "direct boiler-to-boiler focus also updates the camera pose")
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)


func _check_input_gates(boiler: BasementBoiler) -> void:
	await _hover_boiler(boiler)
	main._toggle_journal()
	await _settle(0.1)
	check(main._is_journal_active() and _all_disabled() and not focus.is_focused(), "opening the real journal disables boiler input and releases focus")
	var before := boiler.pressure
	await _click_at(_wheel_point(boiler, 0.0))
	check(not boiler.is_dragging() and is_equal_approx(boiler.pressure, before), "a journal-covered valve cannot be dragged")
	main.journal.close_journal(true)
	await _settle(0.2)
	await _hover_boiler(boiler)
	await _begin_drag(boiler)
	check(boiler.is_dragging(), "the wheel can be dragged again after the journal closes")
	main.pause_menu.open()
	await _settle(0.1)
	check(get_tree().paused and not boiler.is_dragging() and _all_disabled(), "Pause cancels an in-progress wheel drag and disables all boiler picking")
	check(not focus.is_focused() and main.main_camera.position.is_equal_approx(focus._base_position), "Pause immediately returns the camera before the tree stops")
	_send_button(Vector2(-50, -50), false)
	main.pause_menu.close()
	await _settle(0.2)
	await _hover_boiler(boiler)
	NetworkManager.current_lobby_id = 123456
	await _begin_drag(boiler)
	main.pause_menu.open()
	await _settle(0.1)
	check(not get_tree().paused and not boiler.is_dragging() and _all_disabled(), "the online pause overlay also cancels dragging while networking stays active")
	_send_button(Vector2(-50, -50), false)
	NetworkManager.current_lobby_id = 0
	main.pause_menu.close()
	_move_pointer(Vector2(-50, -50))
	await _settle(0.2)
	main._request_turn(-1)
	check(main._phase != MainScene.Phase.IDLE and _all_disabled(), "starting a normal cardinal turn disables boiler picking immediately")
	await _settle(0.4)
	await _turn_to(boiler.view_side)
	check(boiler.interaction_enabled, "settling back at the boiler wall restores interaction")


func _hover_boiler(boiler: BasementBoiler) -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.5)
	await _turn_to(boiler.view_side)
	var point := _visible_focus_point(boiler)
	check(point.is_finite(), str(boiler.name) + " exposes a visible body hover target")
	if point.is_finite():
		_move_pointer(point)
	await _settle(0.55)


func _visible_focus_point(boiler: BasementBoiler) -> Vector2:
	# Adjacent boilers may expose an edge while the camera frames their neighbor.
	for offset_z: float in [0.0, -0.7, 0.7, -0.9, 0.9]:
		for offset_y: float in [1.25, 1.8, 2.3, 0.7]:
			var target := boiler.to_global(Vector3(0.45, offset_y, offset_z))
			if main.main_camera.is_position_behind(target):
				continue
			var point := main.main_camera.unproject_position(target)
			if viewport.get_visible_rect().grow(-5).has_point(point) and focus._find_screen_under_pointer(point) == boiler.focus_area:
				return point
	return Vector2.INF


func _begin_drag(boiler: BasementBoiler) -> void:
	var point := _wheel_point(boiler, 0.0)
	check(viewport.get_visible_rect().has_point(point), str(boiler.name) + " focused camera keeps the valve visible and reachable")
	_move_pointer(point)
	await _settle(0.05)
	_send_button(point, true)
	await _settle(0.04)


func _wheel_point(boiler: BasementBoiler, angle: float) -> Vector2:
	var center := (boiler.get_node("RedValveWheel") as Node3D).position
	return main.main_camera.unproject_position(boiler.to_global(center + Vector3(0.0, cos(angle) * 0.20, sin(angle) * 0.20)))


func _rotate_pointer(boiler: BasementBoiler, from_angle: float, to_angle: float) -> void:
	for step in range(1, 17):
		_move_pointer(_wheel_point(boiler, lerpf(from_angle, to_angle, float(step) / 16.0)), true)


func _turn_to(side: int) -> void:
	for attempt in range(4):
		if main._active_side == side:
			return
		main._request_turn(-1)
		await _settle(0.4)
	check(main._active_side == side, "normal cardinal turns reach the requested basement side")


func _face_door(door: HospitalDoor) -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	for attempt in range(4):
		var target := door.doorway_area.global_position
		if not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20).has_point(main.main_camera.unproject_position(target)):
			return
		main._request_turn(-1)
		await _settle(0.4)
	check(false, "normal cardinal turns reveal the requested physical doorway")


func _all_disabled() -> bool:
	for boiler in boilers:
		if boiler.interaction_enabled or boiler.focus_area.input_ray_pickable or boiler.wheel_area.input_ray_pickable:
			return false
	return true


func _move_pointer(point: Vector2, dragging: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	viewport.push_input(event, true)


func _send_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)


func _click_at(point: Vector2) -> void:
	_move_pointer(point)
	await _settle(0.04)
	for pressed in [true, false]:
		_send_button(point, pressed)
		await get_tree().physics_frame
		await get_tree().process_frame


func _profile_files(directory: String = "res://test-user") -> Dictionary:
	var files := {}
	for filename in DirAccess.get_files_at(directory):
		var path := directory.path_join(filename)
		files[path] = FileAccess.get_file_as_bytes(path)
	for child in DirAccess.get_directories_at(directory):
		files.merge(_profile_files(directory.path_join(child)))
	return files


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _settle(0.05)
	RenderingServer.force_draw(false)
	check(viewport.get_texture().get_image().save_png("res://basement-boiler-%s.png" % stage) == OK, "rendered evidence: " + stage)


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(main):
		main.queue_free()
	print("BASEMENT_BOILER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
