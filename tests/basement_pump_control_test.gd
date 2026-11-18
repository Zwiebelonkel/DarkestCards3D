extends Node3D
## Real hover/click input and room travel, with player saves redirected by the runner.

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var panel: BasementPumpControl
var focus: ScreenCameraFocus


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
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	# The global timer and session logs are independent of cabinet/profile state.
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	CollectionManager.add_card("basement_key")
	check(CollectionManager.use_access_key("basement_key"), "fixture unlocks the basement through its access key")
	GameCurrency._basement_cat_choice = "shot"
	GameCurrency.coins = 42.75
	check(GameCurrency.save(), "fixture saves to its isolated profile")
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
	panel = main.basement_pump_control
	focus = main.screen_camera_focus
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	check(_all_disabled(), "the pump cabinet cannot receive input from the hub")
	check(panel.lever_up == [false, false, true, false, false], "initial positions match four green lamps and one yellow lamp")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.room_index == 3:
			entrance = area.door
	await _face_door(entrance)
	await _click_at(main.main_camera.unproject_position(entrance.doorway_area.global_position))
	check(main._room_transition_active and _all_disabled(), "actual doorway travel keeps cabinet input disabled")
	check(await _wait_until(func(): return main._active_room == 3 and not main._room_transition_active), "actual door flight enters the basement")
	await _settle(0.2)
	await _turn_to(panel.view_side)
	var saved_files := _profile_files()
	var saved_collection := CollectionManager.collection.duplicate(true)
	var saved_catalog := CardDatabase.cards.duplicate(true)
	var saved_coins := GameCurrency.get_coin_cents()
	await _hover_panel()
	var pose := main.main_camera.transform
	check(not main.main_camera.position.is_equal_approx(focus._base_position), "hover physically moves the shared camera toward the box")
	await _settle(0.3)
	check(main.main_camera.transform.is_equal_approx(pose), "stationary hover keeps the camera stable")
	await _capture("mixed")
	for index in range(5):
		var original: Array[bool] = panel.lever_up.duplicate()
		await _click_at(_lever_point(index))
		await _settle(0.2)
		check(panel.lever_up[index] != original[index], "left click flips lever %d exactly once" % index)
		check(_appearance_matches(index), "lever %d and its LED agree: up yellow, down green" % index)
		var others_unchanged := true
		for other in range(5):
			if other != index:
				others_unchanged = others_unchanged and panel.lever_up[other] == original[other] and _appearance_matches(other)
		check(others_unchanged, "lever %d leaves all other levers and lamps unchanged" % index)
		await _click_at(_lever_point(index))
		await _settle(0.2)
		check(panel.lever_up == original and _appearance_matches(index), "a second click reverses lever %d" % index)
	for index in range(5):
		if not panel.lever_up[index]:
			await _click_at(_lever_point(index))
	await _settle(0.2)
	check(panel.lever_up == [true, true, true, true, true], "all five levers can be up together")
	await _capture("all-up-yellow")
	for index in range(5):
		await _click_at(_lever_point(index))
	await _settle(0.2)
	check(panel.lever_up == [false, false, false, false, false], "all five levers can be down together")
	await _capture("all-down-green")
	# Interrupt a lever tween repeatedly, then inspect the actual final mesh pose.
	for attempt in range(3):
		await _click_at(_lever_point(1))
	await _settle(0.2)
	check(panel.lever_up == [false, true, false, false, false] and _appearance_matches(1), "rapid repeated clicks settle at the latest requested position")
	var states: Array[bool] = panel.lever_up.duplicate()
	var right_click := InputEventMouseButton.new()
	right_click.position = _lever_point(0)
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	viewport.push_input(right_click, true)
	right_click = right_click.duplicate() as InputEventMouseButton
	right_click.pressed = false
	viewport.push_input(right_click, true)
	await _settle()
	check(panel.lever_up == states, "right click does not operate a lever")
	main._toggle_journal()
	await _settle(0.35)
	check(main._is_journal_active() and _all_disabled() and not focus.is_focused(), "journal releases camera focus and blocks all levers")
	await _click_at(_lever_point(0))
	check(panel.lever_up == states, "clicks through the journal do not operate the box")
	main.journal.close_journal(true)
	await _settle(0.25)
	await _hover_panel()
	main.pause_menu.open()
	await _settle()
	check(get_tree().paused and _all_disabled() and not focus.is_focused(), "pause blocks the box and releases camera ownership")
	check(main.main_camera.position.is_equal_approx(focus._base_position), "pause restores the camera before the tree stops")
	await _click_at(_lever_point(0))
	check(panel.lever_up == states, "paused clicks cannot flip a switch")
	main.pause_menu.close()
	await _settle(0.2)
	await _hover_panel()
	NetworkManager.current_lobby_id = 123456
	main.pause_menu.open()
	await _settle()
	check(not get_tree().paused and _all_disabled() and not focus.is_focused(), "online pause also blocks input while the tree keeps running")
	await _click_at(_lever_point(0))
	check(panel.lever_up == states, "online pause clicks cannot flip a switch")
	NetworkManager.current_lobby_id = 0
	main.pause_menu.close()
	await _settle(0.2)
	await _hover_panel()
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	check(not focus.is_focused() and main.main_camera.position.is_equal_approx(focus._base_position), "moving away returns the camera to its ordinary view")
	main._request_turn(-1)
	check(main._phase != MainScene.Phase.IDLE and _all_disabled(), "starting a turn immediately blocks the switches")
	await _settle(0.4)
	check(_all_disabled(), "the cabinet remains disabled on another wall")
	var return_door := main.get_node("BasementRoom/ReturnDoor") as HospitalDoor
	await _face_door(return_door)
	await _click_at(main.main_camera.unproject_position(return_door.doorway_area.global_position))
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "the actual return door is usable after operating the box")
	await _settle(0.2)
	check(_all_disabled() and not focus.is_focused(), "leaving the basement releases cabinet input and focus")
	await _face_door(entrance)
	await _click_at(main.main_camera.unproject_position(entrance.doorway_area.global_position))
	check(await _wait_until(func(): return main._active_room == 3 and not main._room_transition_active), "the real door permits another basement visit")
	await _settle(0.2)
	await _turn_to(panel.view_side)
	await _hover_panel()
	check(panel.lever_up == states, "room travel preserves the positions during the current game session")
	check(CollectionManager.collection == saved_collection and GameCurrency.get_coin_cents() == saved_coins, "operating the box does not change cards or currency")
	check(CardDatabase.cards == saved_catalog and _profile_files() == saved_files, "operating the box leaves the catalog and profile save bytes unchanged")
	# The same physical controls now solve a one-time, post-trip puzzle.
	for index in range(5):
		if panel.lever_up[index] != CollectionManager.PUMP_SOLUTION[index]:
			await _click_at(_lever_point(index))
	check(panel.lever_up == [true, false, false, true, false] and CollectionManager.get_amount("toilet_paper") == 0,
		"the exact up-down-down-up-down solution cannot grant a key before the first weed effect")
	GameCurrency.weed_consumed = true
	check(GameCurrency.save(), "save evidence of a previously activated weed effect")
	await _click_at(_lever_point(0))
	check(CollectionManager.get_amount("toilet_paper") == 0, "a wrong first lever cannot solve the puzzle")
	await _click_at(_lever_point(0))
	await _settle(0.7)
	check(CollectionManager.get_amount("toilet_paper") == 1 and panel.get_node_or_null("PumpPuzzleRewardReveal") != null,
		"a real lever click on the unlocked solution grants and reveals Klopapier")
	await _capture("solved-key-reveal")
	var key := CardDatabase.get_card("toilet_paper")
	check(CardData.is_access_key(key) and not CardData.is_combat_card(key) and key.get("random_reward") == false,
		"Klopapier is a puzzle-only special key card")
	check(CollectionManager.get_unused_access_key_ids().has("toilet_paper") and not CollectionManager.use_access_key("toilet_paper"),
		"the new key is collected without opening any door")
	for attempt in range(2):
		await _click_at(_lever_point(0))
		await _click_at(_lever_point(0))
	check(CollectionManager.get_amount("toilet_paper") == 1, "repeated solutions cannot farm another key")
	CollectionManager.reload_profile()
	GameCurrency.load_currency()
	panel._try_claim_reward()
	check(CollectionManager.get_amount("toilet_paper") == 1 and GameCurrency.weed_consumed,
		"the first-trip gate and one-time reward survive loading the profile")
	await _settle(3.0)
	_finish()


func _hover_panel() -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	var point := main.main_camera.unproject_position(panel.focus_area.global_position)
	if not viewport.get_visible_rect().has_point(point):
		print("CABINET_DIAGNOSTIC side=", main._active_side, " point=", point, " camera=", main.main_camera.global_transform, " panel=", panel.focus_area.global_position)
	check(viewport.get_visible_rect().has_point(point) and focus._find_screen_under_pointer(point) == panel.focus_area, "the box exposes a real hover target in the normal basement view")
	_move_pointer(point)
	await _settle(0.5)
	check(focus.is_focused() and focus._focused_screen == panel.focus_area, "hover selects the box in the shared camera focus controller")
	for index in range(5):
		check(viewport.get_visible_rect().grow(-15).has_point(_lever_point(index)), "the focused view keeps lever %d visible and reachable" % index)


func _appearance_matches(index: int) -> bool:
	var lever := panel.get_node("LeverPivot%d/ToggleLever%d" % [index, index]) as MeshInstance3D
	var tip := panel.to_local(lever.to_global(Vector3(0, 0.1, 0)))
	var base := panel.get_node("ToggleBase%d" % index) as MeshInstance3D
	var lamp := panel.get_node("StatusLamp%d" % index) as MeshInstance3D
	var material := lamp.get_active_material(0) as StandardMaterial3D
	var yellow := material.emission.r > 0.9 and material.emission.g > 0.5 and material.emission.b < 0.15
	var green := material.emission.g > material.emission.r * 2.0 and material.emission.g > material.emission.b * 2.0
	return tip.y > base.position.y and yellow if panel.lever_up[index] else tip.y < base.position.y and green


func _lever_point(index: int) -> Vector2:
	return main.main_camera.unproject_position(panel.lever_areas[index].global_position)


func _all_disabled() -> bool:
	if panel.interaction_enabled or panel.focus_area.input_ray_pickable:
		return false
	for area in panel.lever_areas:
		if area.input_ray_pickable or area.collision_layer != 0:
			return false
	return true


func _turn_to(side: int) -> void:
	for attempt in range(4):
		if main._active_side == side:
			return
		main._request_turn(-1)
		await _settle(0.4)
	check(main._active_side == side, "normal cardinal turns reach the cabinet wall")


func _face_door(door: HospitalDoor) -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	for attempt in range(4):
		var target := door.doorway_area.global_position
		if not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20).has_point(main.main_camera.unproject_position(target)):
			return
		main._request_turn(-1)
		await _settle(0.4)
	check(false, "normal cardinal turns reveal the physical doorway")


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click_at(point: Vector2) -> void:
	_move_pointer(point)
	await _settle(0.04)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _profile_files(directory: String = "res://test-user/saves") -> Dictionary:
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
	check(viewport.get_texture().get_image().save_png("res://basement-pump-%s.png" % stage) == OK, "rendered evidence: " + stage)


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("BASEMENT_PUMP_CONTROL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
