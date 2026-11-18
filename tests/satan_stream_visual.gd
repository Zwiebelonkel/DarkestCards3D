extends Node

var viewport: SubViewport
var main: MainScene


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	AudioServer.set_bus_mute(0, true)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	viewport.add_child(main)
	await get_tree().create_timer(0.6).timeout
	main.set_process(false)
	var camera := main.main_camera
	var original_pose := camera.global_transform
	var idle := await _sample_frames()
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	for index in range(ceili(float(main._satan_jumpscare.clicks_required) * 0.5)):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		table.satan_hover_area.input_event.emit(camera, event, Vector3.ZERO, Vector3.ZERO, 0)
	var stream = main._satan_stream
	if not stream.active:
		push_error("The half-click effect did not start")
		get_tree().quit(1)
		return
	var running := await _sample_frames()
	await get_tree().create_timer(0.8).timeout
	stream.set_process(false)
	await _capture("context")
	var focus: Vector3 = stream.trajectory_position(stream.flight_seconds * 0.5)
	var poses := {
		"front": Vector3(0, 2.1, 3.0),
		"back": Vector3(0, 3.3, -5.85),
		"left": Vector3(-5.2, 2.1, -2.5),
		"right": Vector3(5.2, 2.1, -2.5),
	}
	for label in poses:
		camera.global_position = poses[label]
		camera.look_at(focus)
		await _capture(label)
	camera.global_transform = original_pose
	stream.stop_pissing(true)
	var report := {
		"recorded_at": Time.get_datetime_string_from_system(true),
		"source": str(stream.source_position), "target": str(stream.target_position),
		"flight_seconds": stream.flight_seconds, "particle_capacity": stream.particles.amount,
		"source_node": str(stream.get_path()), "source_scene_modified": FileAccess.get_modified_time("res://scenes/effects/Piss.tscn"),
		"idle_sample": idle, "stream_sample": running,
		"views": ["context", "front", "back", "left", "right"],
	}
	var file := FileAccess.open("res://satan-stream-review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("SATAN_STREAM_VISUAL_TESTS: PASS")
	get_tree().quit()


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://satan-stream-" + label + ".png")


func _sample_frames() -> Dictionary:
	var times: Array[float] = []
	var draws := 0.0
	for index in range(20):
		await get_tree().process_frame
		times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	var total := 0.0
	for value in times:
		total += value
	return {"average_process_ms": total / times.size(), "p95_process_ms": times[18], "average_draw_calls": draws / times.size()}
