extends Node


func _ready() -> void:
	GameCurrency.set_process(false)
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var menu := (load("res://scenes/main/MainMenu.tscn") as PackedScene).instantiate()
	menu.get_node("Music").autoplay = false
	# Freeze only the fixture's random neon startup for comparable captures.
	for path: String in ["Neon/darkest", "Neon/cards2"]:
		var neon := menu.get_node(path)
		neon.startup_flicker = false
		neon.random_failures = false
		neon.flicker_enabled = false
	viewport.add_child(menu)
	var satan := menu.get_node("ScenePivot/GameTable/dealer/SatanMotionRoot/satan") as Sprite3D
	satan.set_process(false)
	satan.frame = 0
	var material := satan.material_override as StandardMaterial3D
	if material == null or not material.emission_enabled or material.emission_operator != BaseMaterial3D.EMISSION_OP_MULTIPLY:
		push_error("Main-menu Satan must use masked emission")
		get_tree().quit(1)
		return
	if material.emission_texture.get_image().get_pixel(31, 48).r > 0.0:
		push_error("Black body must not emit")
		get_tree().quit(1)
		return
	if material.emission_energy_multiplier < 6.0:
		push_error("Menu emission must remain visible through the menu filters")
		get_tree().quit(1)
		return
	var idle := satan.texture
	satan.play_sheet(load("res://assets/characters/satan/satanLaught.png"), 2, 0.0)
	if material.emission_texture != satan.EYE_EMISSION_MAPS["satanLaught"]:
		push_error("Menu material must follow animation-sheet changes")
		get_tree().quit(1)
		return
	satan.play_sheet(idle, 25, 0.0)
	print("MENU_EMISSION_ENERGY ", material.emission_energy_multiplier)
	if DisplayServer.get_name() != "headless":
		for index in range(12):
			await RenderingServer.frame_post_draw
		var directory := "res://docs/validation/character-eyes"
		DirAccess.make_dir_recursive_absolute(directory)
		var label := "main-menu"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--label="):
				label = argument.trim_prefix("--label=")
		var capture := viewport.get_texture().get_image()
		if capture.save_png(directory + "/" + label + ".png") != OK:
			get_tree().quit(1)
			return
		var report := {
			"captured_at_utc": Time.get_datetime_string_from_system(true),
			"scene_modified": FileAccess.get_modified_time("res://scenes/main/MainMenu.tscn"),
			"resolution": str(capture.get_size()),
			"emission_energy": material.emission_energy_multiplier,
			"black_body_emission": 0.0,
			"fixture": "actual MainMenu; neon flicker frozen and music disabled for capture",
		}
		var report_file := FileAccess.open(directory + "/main-menu-review.json", FileAccess.WRITE)
		report_file.store_string(JSON.stringify(report, "\t"))
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("MAIN_MENU_EMISSION_TESTS: PASS")
	get_tree().quit()
