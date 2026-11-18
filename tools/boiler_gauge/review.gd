extends "res://tests/basement_boiler_test.gd"
## Isolated saves; honest gameplay framing and matched before/after render costs.

var output := "res://docs/validation/boiler-gauges"
var shots: Array[Dictionary] = []


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	CollectionManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	CollectionManager.add_card("basement_key")
	CollectionManager.use_access_key("basement_key")
	GameCurrency._basement_cat_choice = "shot"
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	viewport.add_child(main)
	focus = main.screen_camera_focus
	boilers = main.basement_boilers
	for node in main.find_children("*", "Node3D", true, false):
		if node is StreetLanternFlicker:
			node.flicker_enabled = false
			if is_instance_valid(node.light) and not node.is_shot_out:
				node.light.light_energy = node.base_energy
	await _settle(0.6)
	var door: HospitalDoor
	for area in main.progression_areas:
		if area.room_index == 3:
			door = area.door
	await _face_door(door)
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	check(await _wait_until(func(): return main._active_room == 3 and not main._room_transition_active), "review arrives in basement")
	await _turn_to(boilers[0].view_side)
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)
	await _capture("context")
	var context_cost := await _benchmark()
	await _hover_boiler(boilers[0])
	await _capture("focused")
	var focused_cost := await _benchmark()
	main.set_process(false)
	focus.set_process(false)
	var boiler := boilers[0]
	var center := boiler.to_global(Vector3(0.98, 1.75, 0.12))
	main.main_camera.global_position = center + boiler.global_basis.x.normalized() * 1.18
	main.main_camera.look_at(center)
	main.main_camera.fov = 40
	for value: float in [0.0, 2.8, 6.0]:
		boiler.pressure = value
		boiler._update_gauge()
		await _wait_until(func(): return not boiler.digits.is_rolling())
		await _capture("detail-%.1f" % value)
	# A frame sequence shows real motion through a carry and the reverse carry.
	var frames := output.path_join("roll-frames")
	DirAccess.make_dir_recursive_absolute(frames)
	boiler.pressure = 2.8
	boiler._update_gauge()
	boiler.digits.set_pressure(2.8, true)
	var frames_saved := true
	for frame in range(90):
		if frame >= 10 and frame < 50:
			boiler.pressure = 2.8 + float(frame - 10) * 0.01
			boiler._update_gauge()
		elif frame >= 50:
			boiler.pressure = 3.2 - float(frame - 50) * 0.01
			boiler._update_gauge()
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		frames_saved = picture.save_png(frames.path_join("%03d.png" % frame)) == OK and frames_saved
	check(frames_saved, "counter forward and reverse animation frames")
	boiler.digits.set_pressure(2.95, true)
	await _capture("detail-carry")
	if ResourceLoader.exists("res://scenes/props/BoilerGauge.tscn"):
		var isolated := load("res://scenes/props/BoilerGauge.tscn").instantiate() as Node3D
		viewport.add_child(isolated)
		isolated.position = Vector3(200, 0, 0)
		for offset: Vector3 in [Vector3(0.3, 0.7, 1), Vector3(-0.6, 0.4, -0.8), Vector3(-0.8, -0.2, 0.4)]:
			var light := OmniLight3D.new()
			light.position = isolated.position + offset
			light.light_energy = 0.7
			viewport.add_child(light)
		for entry: Array in [["front", Vector3(0, 0, 1)], ["back", Vector3(0, 0, -1)], ["left", Vector3(-1, 0, 0)], ["right", Vector3(1, 0, 0)], ["bezel", Vector3(0.6, 0.25, 1)]]:
			main.main_camera.global_position = isolated.position + (entry[1] as Vector3) * 0.95
			main.main_camera.look_at(isolated.position)
			await _capture("isolated-" + str(entry[0]))
	var report := {"captured_utc": Time.get_datetime_string_from_system(true), "scene_modified": FileAccess.get_modified_time("res://scenes/rooms/Basement.tscn"), "shots": shots, "performance": {"context": context_cost, "focused": focused_cost}}
	FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	main.queue_free()
	await _settle(0.2)
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("BOILER_GAUGE_REVIEW: PASS")
	get_tree().quit(0 if failures == 0 else 1)


func _capture(stage: String) -> void:
	await _settle(0.12)
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture.save_png(output.path_join(stage + ".png")) == OK, "capture " + stage)
	var luminance := 0.0
	var samples := 0
	for y in range(0, picture.get_height(), 16):
		for x in range(0, picture.get_width(), 16):
			var c := picture.get_pixel(x, y)
			luminance += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			samples += 1
	shots.append({"name": stage, "width": picture.get_width(), "height": picture.get_height(), "mean_luminance": luminance / samples, "camera": str(main.main_camera.global_transform), "fov": main.main_camera.fov})


func _benchmark() -> Dictionary:
	for frame in range(15):
		await get_tree().process_frame
	var times: Array[float] = []
	for frame in range(60):
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	var total := 0.0
	for time in times:
		total += time
	times.sort()
	return {"frames": times.size(), "average_ms": total / times.size(), "p95_ms": times[56], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
