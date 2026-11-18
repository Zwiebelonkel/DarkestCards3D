extends Node

const SURFACE := preload("res://scripts/packs/PackSurface.gd")
const FOIL := preload("res://scripts/packs/PackFoil.gd")
const IDS := ["basic", "ultra", "god"]
var checks := 0
var failures := 0
var models: Array[Node3D] = []
var foils: Array[RefCounted] = []
var view: SubViewport
var camera: Camera3D
var output := "res://pack-surface-review"
var relief_multiplier := 1.0
var baseline_shader: Shader
var report := {"captures": [], "materials": [], "performance": {}}


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run this fixture in an isolated project with redirected saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		if argument.begins_with("--relief="):
			relief_multiplier = argument.trim_prefix("--relief=").to_float()
		if argument.begins_with("--baseline-foil="):
			baseline_shader = Shader.new()
			baseline_shader.code = FileAccess.get_file_as_string(argument.trim_prefix("--baseline-foil="))
	DirAccess.make_dir_recursive_absolute(output)
	report["captured_at_utc"] = Time.get_datetime_string_from_system(true)
	report["shader_modified"] = FileAccess.get_modified_time("res://assets/shader/pack_surface.gdshader")
	report["framing"] = "1500x900, 34 degree camera, equal pack scales and fixed lighting before/after"
	_setup_view()
	for index in range(IDS.size()):
		var pack_id: String = IDS[index]
		var model := (PackDefinition.PACK_TYPES[pack_id]["scene"] as PackedScene).instantiate() as Node3D
		model.position = Vector3((index - 1) * 1.85, 0.0, 0.0)
		model.scale = Vector3.ONE * 0.46
		view.add_child(model)
		models.append(model)
		# Compare the same already-subdivided peel geometry. The optional shader
		# comes from the pre-change revision; otherwise disable the new finish.
		var top := model.get_node("top") as MeshInstance3D
		var original := top.get_active_material(0) as BaseMaterial3D
		var baseline_foil := FOIL.new()
		baseline_foil.configure(top, pack_id)
		for surface in range(top.mesh.get_surface_count()):
			var material := top.get_active_material(surface) as ShaderMaterial
			if baseline_shader != null:
				material.shader = baseline_shader
			material.set_shader_parameter("metallic_value", original.metallic)
			material.set_shader_parameter("roughness_value", original.roughness)
			material.set_shader_parameter("surface_relief", 0.0)
			material.set_shader_parameter("surface_tint_strength", 0.0)
			material.set_shader_parameter("surface_roughness_strength", 0.0)
			material.set_shader_parameter("laminate_clearcoat", 0.0)
		foils.append(baseline_foil)
		var map: Texture2D = SURFACE.HEIGHTMAPS[pack_id]
		var image := map.get_image()
		check(image.get_size() == Vector2i(512, 512) and image.has_mipmaps(), pack_id + " has a baked mipmapped heightmap")
		check(image.get_format() == Image.FORMAT_L8, pack_id + " height data is linear grayscale")
		var minimum := 1.0
		var maximum := 0.0
		for y in range(0, 512, 8):
			for x in range(0, 512, 8):
				minimum = minf(minimum, image.get_pixel(x, y).r)
				maximum = maxf(maximum, image.get_pixel(x, y).r)
		check(maximum - minimum > 0.25, pack_id + " heightmap contains usable relief")
	await _capture("00-before-front")
	await _measure("before")
	for index in range(models.size()):
		var model := models[index]
		var pack_id: String = IDS[index]
		SURFACE.apply_to_pack(model, pack_id, false)
		var foil: RefCounted = foils[index]
		check(foil.configure(model.get_node("top"), pack_id), pack_id + " peel configures with its surface variant")
		for node_name: String in ["base", "top"]:
			var mesh := model.get_node(node_name) as MeshInstance3D
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as ShaderMaterial
				material.set_shader_parameter("surface_relief", float(material.get_shader_parameter("surface_relief")) * relief_multiplier)
				check(material != null and material.get_shader_parameter("surface_heightmap") == SURFACE.HEIGHTMAPS[pack_id], pack_id + " " + node_name + " uses the matching heightmap")
				check(float(material.get_shader_parameter("roughness_value")) <= 0.35, pack_id + " " + node_name + " has glossy printed backing")
				check(material.get_shader_parameter("albedo_texture") != null, pack_id + " " + node_name + " keeps the printed artwork")
				report["materials"].append({"pack": pack_id, "mesh": node_name, "surface": surface, "roughness": material.get_shader_parameter("roughness_value"), "heightmap": material.get_shader_parameter("surface_heightmap").resource_path})
		var untouched := (PackDefinition.PACK_TYPES[pack_id]["scene"] as PackedScene).instantiate() as Node3D
		check(untouched.get_node("base").get_active_material(0) is StandardMaterial3D, pack_id + " leaves shared imported materials untouched")
		untouched.free()
	await _capture("01-after-front")
	await _measure("after")
	for model in models:
		model.rotation_degrees.y = 180.0
	await _capture("02-after-back")
	for model in models:
		model.rotation_degrees.y = -32.0
	await _capture("03-after-grazing")
	for index in range(foils.size()):
		for step in range(30):
			foils[index].update_foil(0.7, 0.6, 0.5, 1.0 / 60.0)
	await _capture("04-after-partial-peel")
	# Direct preview integration, including the back/top surfaces in the shop.
	var ui := (load("res://scenes/PackShopUI.tscn") as PackedScene).instantiate() as PackShopUI
	get_tree().root.size = Vector2i(1500, 900)
	add_child(ui)
	ui.set_packs(PackDefinition.PACK_TYPES)
	await get_tree().process_frame
	for pack_id: String in IDS:
		var preview: PackPreviewViewport = ui.pack_previews[pack_id]
		preview.set_process(false)
		preview.pack_model.rotation_degrees.y = -16.0
		check(preview.pack_model.get_node("base").get_active_material(0).get_shader_parameter("surface_heightmap") == SURFACE.HEIGHTMAPS[pack_id], pack_id + " shop preview applies its matching finish")
		await preview._force_viewport_refresh()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output + "/05-shop.png") == OK, "shop capture saved")
	ui.queue_free()
	var unknown := (PackDefinition.PACK_TYPES["basic"]["scene"] as PackedScene).instantiate() as Node3D
	view.add_child(unknown)
	unknown.hide()
	SURFACE.apply_to_pack(unknown, "unknown")
	var first_material: Material = unknown.get_node("base").get_active_material(0)
	SURFACE.apply_to_pack(unknown, "unknown")
	check(first_material == unknown.get_node("base").get_active_material(0), "reapplying the same finish does not allocate new materials")
	check(first_material.get_shader_parameter("surface_heightmap") == SURFACE.HEIGHTMAPS["basic"], "unknown pack IDs safely fall back to Basic")
	SURFACE.apply_to_pack(unknown, "god")
	check(first_material == unknown.get_node("base").get_active_material(0) and first_material.get_shader_parameter("surface_heightmap") == SURFACE.HEIGHTMAPS["god"], "changing finish on an existing model updates its map without replacing materials")
	await get_tree().process_frame
	unknown.queue_free()
	view.queue_free()
	foils.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(output + "/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PACK_SURFACE_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _setup_view() -> void:
	view = SubViewport.new()
	view.size = Vector2i(1500, 900)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.029, 0.038)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	view.add_child(world)
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 0.2, 6.8)
	camera.fov = 34.0
	view.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-28, -24, 0)
	light.light_energy = 1.8
	view.add_child(light)
	var softbox := OmniLight3D.new()
	softbox.position = Vector3(-1.8, 2.8, 3.7)
	softbox.light_energy = 4.0
	softbox.light_size = 1.0
	softbox.omni_range = 12.0
	view.add_child(softbox)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3.0, -1.2, 2.5)
	fill.light_energy = 1.2
	fill.light_color = Color(0.6, 0.73, 1.0)
	fill.light_size = 0.6
	fill.omni_range = 10.0
	view.add_child(fill)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in range(8):
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image.save_png(output + "/" + label + ".png") == OK, label + " capture saved")
	var luminance := 0.0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			luminance += image.get_pixel(x, y).get_luminance()
	report["captures"].append({"label": label, "resolution": str(image.get_size()), "mean_luminance": luminance / (125.0 * 75.0), "camera": str(camera.global_transform), "timestamp_utc": Time.get_datetime_string_from_system(true)})


func _measure(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var frames: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(48):
		await RenderingServer.frame_post_draw
		var current := Time.get_ticks_usec()
		frames.append((current - previous) / 1000.0)
		previous = current
	frames.sort()
	var total := 0.0
	for value in frames:
		total += value
	report["performance"][label] = {"average_frame_ms": total / frames.size(), "p95_frame_ms": frames[int(frames.size() * 0.95)], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "rendered_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
