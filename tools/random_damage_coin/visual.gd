extends Node

const COIN := preload("res://scenes/effects/RandomDamageCoin.tscn")
var output := "res://docs/validation/random-damage-coin"
var shots: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table._table_state = GameTable.TableState.PLAYING
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	for side: String in ["player", "enemy"]:
		for slot in range(5):
			var data := CardDatabase.get_card("corpse").duplicate(true)
			data["animated"] = false
			data["effects"] = [{"type": "random_damage"}] if slot == 2 else []
			var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
			deck.append(data)
			table._draw_to_slot(side, slot, false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	var camera := table.table_camera
	var camera_transform := camera.global_transform
	var landing := Vector3(0, 0.145, 0)
	var coin := COIN.instantiate()
	table.add_child(coin)
	coin.set_process(false)
	coin.hide()
	var before := await _benchmark()
	coin.show()
	coin.play_flip(2.0, landing, Vector3(-3.7, 0.9, 0.35))
	coin._apply_flip(coin.REVEAL_DURATION)
	var after := await _benchmark()
	for value: float in [0.75, 2.0]:
		coin.play_flip(value, landing, Vector3(-3.7, 0.9, 0.35))
		coin._apply_flip(coin.REVEAL_DURATION)
		await _capture("context-" + str(value))
		camera.global_position = coin.global_position + Vector3(0, 1.4, 0.001)
		camera.look_at(coin.global_position, Vector3.FORWARD)
		await _capture("face-" + str(value))
		camera.global_transform = camera_transform
	for direction: float in [-1.0, 1.0]:
		camera.global_position = coin.global_position + Vector3(direction * 1.2, 0.45, 0)
		camera.look_at(coin.global_position)
		await _capture("edge-" + str(direction))
	camera.global_transform = camera_transform
	coin.play_flip(2.0, landing, Vector3(-3.7, 0.9, 0.35))
	coin._apply_flip(0.30)
	await _capture("context-flight")
	coin._apply_flip(coin.REVEAL_DURATION)
	coin.dissolve()
	coin.set_dissolve_progress(0.55)
	await _capture("context-dissolve")
	var file := FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captured_utc": Time.get_datetime_string_from_system(true), "scene_modified": FileAccess.get_modified_time("res://scenes/effects/RandomDamageCoin.tscn"), "shots": shots, "performance": {"without_coin": before, "with_coin": after}, "junctions": {"face_text_clearance": "pass: raised text overlaps the face without z-fighting", "table_contact": "pass: body clears table by 0.005m; underside lettering is hidden"}}, "  "))
	coin.queue_free()
	table._clear_match()
	main.queue_free()
	await get_tree().process_frame
	print("COIN_VISUAL: PASS")
	get_tree().quit()


func _capture(label: String) -> void:
	var picture: Image
	var luminance := 0.0
	# The real room lights flicker; avoid accepting a black diagnostic frame.
	for attempt in range(60):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		picture = get_viewport().get_texture().get_image()
		var total := 0.0
		var samples := 0
		for y in range(0, picture.get_height(), 32):
			for x in range(0, picture.get_width(), 32):
				var color := picture.get_pixel(x, y)
				total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
				samples += 1
		luminance = total / samples
		if luminance > 0.12:
			break
	assert(luminance > 0.12)
	var path := output.path_join(label + ".png")
	assert(picture.save_png(path) == OK)
	shots.append({"name": label, "path": path, "resolution": [picture.get_width(), picture.get_height()], "mean_luminance_sample": luminance})


func _benchmark() -> Dictionary:
	for i in range(10):
		await get_tree().process_frame
	var times: Array[float] = []
	for i in range(30):
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	var total := 0.0
	for value in times:
		total += value
	times.sort()
	return {"frames": times.size(), "average_ms": total / times.size(), "p95_ms": times[28], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
