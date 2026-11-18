extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var gate: Node3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use an isolated project copy with redirected saves.")
		get_tree().quit(1)
		return
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	GameCurrency.set_process(false)
	CollectionManager.add_card("graveyard_key")
	check(CollectionManager.use_access_key("graveyard_key"), "fixture unlocks the graveyard with its real key")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.05
	main.settle_duration = 0.04
	main.room_travel_duration = 0.4
	viewport.add_child(main)
	gate = main.crypt_gate
	_move_pointer(Vector2(-40, -40))
	await _settle(0.6)
	check(not gate.interaction_enabled, "remote crypt cannot be interacted with from the hub")
	check(gate.hinge.get_child_count() == 9, "all seven bars and both rails move as one grille")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.area_id == "graveyard":
			entrance = area.door
	main._on_room_door_activated(entrance)
	check(await _wait_until(func(): return main._active_room == 2 and not main._room_transition_active), "the normal doorway flight enters the graveyard")
	await _settle(0.2)
	var home := main.camera_pivot.global_transform
	var eye_before := main.main_camera.global_position
	var hitbox_pose: Transform3D = gate.gate_area.global_transform
	_move_pointer(main.main_camera.unproject_position(gate.gate_area.global_position))
	await _settle(0.4)
	check(gate._hovered and absf(gate.hinge.rotation.y) > 0.01 and absf(gate.hinge.rotation.y) < deg_to_rad(6.0), "real pointer hover gently swings the grille")
	check(main.main_camera.global_position.is_equal_approx(eye_before) and not main._room_transition_active, "hover alone leaves the player at the graveyard viewpoint")
	check(gate.gate_area.global_transform.is_equal_approx(hitbox_pose), "the hover hit box remains fixed while the grille moves")
	await _capture("hover")
	await _settle(0.4)
	check(gate._hovered and is_equal_approx(gate.hinge.rotation.y, deg_to_rad(gate.hover_angle_degrees)), "a stationary pointer keeps a stable hover pose")
	_move_pointer(Vector2(-40, -40))
	await _settle(0.4)
	check(not gate._hovered and is_zero_approx(gate.hinge.rotation.y), "leaving the grille gently restores its closed pose")
	var cards_before := CollectionManager.collection.duplicate(true)
	var coins_before := GameCurrency.get_coin_cents()
	_click_gate()
	check(main._room_transition_active and main._crypt_gate_close and not main._can_turn(), "a real left click starts a walk and blocks competing turns")
	_click_gate()
	check(await _wait_until(func(): return not main._room_transition_active), "the walk completes even after a repeated click")
	var close_pose := main.main_camera.global_transform
	check(main._active_room == 2 and main.main_camera == viewport.get_camera_3d(), "approaching preserves the room and its shared camera")
	check(close_pose.is_equal_approx(gate.get_approach_camera_pose()), "the camera stops at the authored position directly in front of the grille")
	check(main.main_camera.global_position.distance_to(gate.gate_area.global_position) < eye_before.distance_to(gate.gate_area.global_position) * 0.4, "the player actually travels toward the grille")
	_move_pointer(Vector2(-40, -40))
	await _settle(0.4)
	check(main.main_camera.global_transform.is_equal_approx(close_pose), "moving the pointer away keeps the player in front of the crypt")
	await _capture("close")
	_button(MOUSE_BUTTON_RIGHT, Vector2(640, 360))
	check(await _wait_until(func(): return not main._room_transition_active), "right click finishes the return walk")
	check(not main._crypt_gate_close and main.camera_pivot.global_transform.is_equal_approx(home), "right click restores the exact original graveyard viewpoint")
	await _settle(0.1)
	_click_gate()
	await _wait_until(func(): return not main._room_transition_active)
	_escape()
	check(await _wait_until(func(): return not main._room_transition_active), "Escape finishes the return walk")
	check(not main._crypt_gate_close and not main.pause_menu.visible and main.camera_pivot.global_transform.is_equal_approx(home), "Escape returns from the grille without opening the pause menu")
	await _settle(0.1)
	_click_gate()
	await _wait_until(func(): return not main._room_transition_active)
	var crypt_pivot := main.camera_pivot.global_transform
	for step in range(4):
		await _press_turn(KEY_A)
		check(await _wait_until(func(): return main._phase == MainScene.Phase.IDLE), "a real A key completes a turn at the crypt")
		check(main._crypt_gate_close and not main._room_transition_active and main.camera_pivot.global_position.is_equal_approx(crypt_pivot.origin), "turning at the crypt keeps the player at the new viewpoint")
	check(main.main_camera.global_transform.is_equal_approx(close_pose), "a full turn at the crypt restores the exact near view without camera drift")
	for step in range(2):
		await _press_turn(KEY_A)
		await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(main._active_side == 2 and not main.graveyard_jester.interaction_enabled, "the player can face the crossing without activating the distant Jester")
	var visual := gate.return_beacon.get_node("Visual") as Node3D
	_move_pointer(Vector2(-40, -40))
	await _settle(0.15)
	check(not visual.visible, "the return beacon stays hidden without a crossing hover")
	var crossing_point := main.main_camera.unproject_position(gate.return_beacon.global_position + Vector3.UP * 0.4)
	_move_pointer(crossing_point)
	await _settle(0.2)
	check(visual.visible and not main._room_transition_active, "hovering the crossing reveals a small beacon without moving the player")
	await _capture("beacon-context")
	await _measure_beacon_cost(crossing_point)
	await _settle(0.2)
	check(visual.visible, "the beacon remains stable under a stationary pointer")
	_move_pointer(Vector2(-40, -40))
	await _settle(0.15)
	check(not visual.visible and main._crypt_gate_close, "moving off the crossing hides the beacon while staying at the crypt")
	_button(MOUSE_BUTTON_LEFT, Vector2(20, 20))
	check(not main._room_transition_active and main._crypt_gate_close, "clicking away from the crossing does not walk back")
	_move_pointer(crossing_point)
	await _settle(0.1)
	main.pause_menu.open()
	check(not visual.visible, "Pause immediately hides the crossing beacon")
	_button(MOUSE_BUTTON_LEFT, crossing_point)
	check(main._crypt_gate_close and not main._room_transition_active, "the crossing cannot be clicked through Pause")
	main.pause_menu.close()
	await _settle(0.1)
	main._toggle_journal()
	check(main._is_journal_active() and not visual.visible, "the journal also hides the crossing beacon")
	_button(MOUSE_BUTTON_LEFT, crossing_point)
	check(main._crypt_gate_close and not main._room_transition_active, "the crossing cannot be clicked through the journal")
	main.journal.close_journal(true)
	await _settle(0.1)
	var return_heading := -main.main_camera.global_basis.z
	return_heading.y = 0.0
	return_heading = return_heading.normalized()
	_button(MOUSE_BUTTON_LEFT, crossing_point)
	check(main._room_transition_active and not visual.visible, "a real left click on the crossing starts the return walk and hides its beacon")
	var kept_heading := true
	while main._room_transition_active:
		var heading := -main.main_camera.global_basis.z
		heading.y = 0.0
		kept_heading = kept_heading and heading.normalized().dot(return_heading) > 0.999
		await get_tree().process_frame
	check(kept_heading, "the complete beacon return walk keeps looking ahead without turning toward the crypt")
	check(await _wait_until(func(): return not main._room_transition_active), "the crossing walk finishes")
	check(not main._crypt_gate_close and main._active_side == 2 and main.camera_pivot.global_position.is_equal_approx(home.origin), "clicking the crossing restores its original position while preserving the current facing")
	await _capture("beacon-returned")
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	await _settle(0.1)
	main.pause_menu.open()
	check(not gate.interaction_enabled, "opening Pause immediately disables the crypt")
	_click_gate()
	check(not main._crypt_gate_close and not main._room_transition_active, "the pause overlay blocks clicks on the grille")
	main.pause_menu.close()
	await _settle(0.1)
	main._toggle_journal()
	check(main._is_journal_active() and not gate.interaction_enabled, "the journal immediately blocks crypt interaction")
	_click_gate()
	check(not main._crypt_gate_close, "a click through the journal cannot approach the crypt")
	main.journal.close_journal(true)
	_move_pointer(Vector2(-40, -40))
	await _settle(0.1)
	check(CollectionManager.collection == cards_before and GameCurrency.get_coin_cents() == coins_before, "crypt exploration leaves cards and currency unchanged")
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	main._on_room_door_activated(main.get_node("GraveyardRoom/ReturnDoor") as HospitalDoor)
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "the normal return door remains usable after crypt exploration")
	check(not gate.interaction_enabled and not main._crypt_gate_close, "leaving the graveyard clears crypt interaction")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	await _capture_beacon_views()
	print("CRYPT_GATE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _button(button: MouseButton, point: Vector2) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = button
		click.pressed = pressed
		viewport.push_input(click, true)


func _click_gate() -> void:
	_button(MOUSE_BUTTON_LEFT, main.main_camera.unproject_position(gate.gate_area.global_position))


func _escape() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		viewport.push_input(key, true)


func _press_turn(code: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame
		await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://crypt-gate-%s.png" % stage)


func _measure_beacon_cost(crossing_point: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var report := {}
	for enabled in [false, true]:
		_move_pointer(crossing_point if enabled else Vector2(-40, -40))
		await _settle(0.2)
		var samples: Array[float] = []
		var draws := 0.0
		var previous := Time.get_ticks_usec()
		for frame in range(30):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous) / 1000.0)
			previous = now
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var total := 0.0
		for sample in samples:
			total += sample
		samples.sort()
		report["visible" if enabled else "hidden"] = {"frames": samples.size(), "average_frame_ms": total / samples.size(), "p95_frame_ms": samples[28], "average_draw_calls": draws / samples.size()}
	var file := FileAccess.open("res://crypt-beacon-cost.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))


func _capture_beacon_views() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var isolated := SubViewport.new()
	isolated.size = Vector2i(512, 512)
	isolated.own_world_3d = true
	isolated.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(isolated)
	var beacon := (load("res://scenes/props/TravelBeacon.tscn") as PackedScene).instantiate() as Node3D
	isolated.add_child(beacon)
	(beacon.get_node("Visual") as Node3D).show()
	var camera := Camera3D.new()
	camera.fov = 45.0
	isolated.add_child(camera)
	camera.make_current()
	var shots := {"front": Vector3(0, 1.3, 2.4), "back": Vector3(0, 1.3, -2.4), "left": Vector3(-2.4, 1.3, 0), "right": Vector3(2.4, 1.3, 0)}
	for angle: String in shots:
		camera.position = shots[angle]
		camera.look_at(Vector3(0, 0.4, 0), Vector3.UP)
		await _settle(0.06)
		await RenderingServer.frame_post_draw
		check(isolated.get_texture().get_image().save_png("res://crypt-beacon-%s.png" % angle) == OK, "beacon isolated capture: " + angle)
	isolated.queue_free()
	await get_tree().process_frame
