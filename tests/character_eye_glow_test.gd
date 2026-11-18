extends Node

const ANIMATION := preload("res://scripts/SpriteAnim.gd")
const ACTORS := [
	["res://scenes/table/GameTable.tscn", "dealer/SatanMotionRoot/satan", "satan", "satan", "satanHover"],
	["res://scenes/ui/CollectionScreen.tscn", "angel", "angel", "angel", "angelHover"],
	["res://scenes/rooms/BlackMarket.tscn", "Kiosk/Dealer", "baclmarketDealer", "blackmarketDealer", "dealerHover"],
	["res://scenes/rooms/Graveyard.tscn", "jester", "jester", "jester", "jesterHover"],
	["res://scenes/rooms/Graveyard.tscn", "Crypt/Prisoner", "prisoner", "prisoner", "prisonerHover"],
]

var failures := 0
var checks := 0
var actors: Array[Sprite3D] = []


func _ready() -> void:
	GameCurrency.set_process(false)
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	for entry: Array in ACTORS:
		var scene := (load(entry[0]) as PackedScene).instantiate()
		var source := scene.get_node(entry[1]) as Sprite3D
		check(source.material_override is StandardMaterial3D, entry[3] + " has authored material")
		var actor := source.duplicate() as Sprite3D
		# A character-only fixture cannot run interactions or change player saves.
		for child in actor.get_children():
			child.free()
		add_child(actor)
		actor.set_process(false)
		actors.append(actor)
		check(actor.material_override != source.material_override, "Independent material: " + entry[3])
		var material := actor.material_override as StandardMaterial3D
		check(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Mask restricts emission: " + entry[3])
		for sheet: String in [entry[3], entry[4]]:
			actor.texture = load("res://assets/characters/" + entry[2] + "/" + sheet + ".png")
			check(material.albedo_texture == actor.texture, "Albedo follows " + sheet)
			check(material.emission_texture == ANIMATION.EYE_EMISSION_MAPS[sheet], "Emission follows " + sheet)
			check(material.emission_enabled, "Emission enabled for " + sheet)
			check(material.emission_texture.get_size() == actor.texture.get_size(), "Atlas dimensions: " + sheet)
		actor.texture = load("res://assets/characters/" + entry[2] + "/" + entry[3] + ".png")
		scene.free()
	var satan := actors[0]
	for sheet: String in ["satanLaught", "satanDeath"]:
		satan.play_sheet(load("res://assets/characters/satan/" + sheet + ".png"), 2, 0.0)
		check(satan.material_override.emission_texture == ANIMATION.EYE_EMISSION_MAPS[sheet], "Cinematic sheet: " + sheet)
	satan.texture = load("res://assets/characters/cat/cat.png")
	check(not satan.material_override.emission_enabled, "Unknown sheet never emits its whole silhouette")
	satan.texture = load("res://assets/characters/satan/satan.png")
	satan.hframes = 25
	satan.frame = 0
	check(satan.material_override.emission_enabled, "Direct texture restoration re-enables eyes")
	for sheet: String in ANIMATION.EYE_EMISSION_MAPS:
		var mask := (ANIMATION.EYE_EMISSION_MAPS[sheet] as Texture2D).get_image()
		check(mask.get_height() == 64 and mask.get_width() % 64 == 0, "Saved eye map round trip: " + sheet)
		for frame_index in range(mask.get_width() / 64):
			check(mask.get_pixel(frame_index * 64 + 31, 48).r == 0.0, "Body excluded: " + sheet)
	check(_mask_pixel("angel", 31, 9).r > 0.5, "Gold halo emits")
	check(_mask_pixel("prisoner", 31, 33).r > 0.5, "Prisoner mouth emits")
	check(_mask_pixel("prisonerHover", 28, 14).r > 0.5, "White sword emits")
	check(_mask_pixel("satanLaught", 31, 40).r > 0.5, "Laughing mouth emits")
	check(_mask_pixel("satan", 21 * 64 + 26, 25).r == 0.0, "Blink has no ghost eye")
	check(_mask_pixel("satan", 26, 22).r > 0.5, "Open red eye emits")
	check(_mask_pixel("angel", 26, 22).b > 0.5, "Cyan eye emits")
	check(_mask_pixel("prisonerHover", 27, 22).r > 0.5, "White hover eye emits")
	if DisplayServer.get_name() != "headless":
		await _render_review()
	for actor in actors:
		actor.queue_free()
	await get_tree().process_frame
	print("CHARACTER_EYE_GLOW_TESTS: ", "PASS" if failures == 0 else "FAIL", " (", checks, " checks)")
	get_tree().quit(0 if failures == 0 else 1)


func _mask_pixel(sheet: String, x: int, y: int) -> Color:
	return (ANIMATION.EYE_EMISSION_MAPS[sheet] as Texture2D).get_image().get_pixel(x, y)


func _render_review() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.15
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_bloom = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.position = Vector3(0, 0.0, 8)
	viewport.add_child(camera)
	for index in actors.size():
		var actor := actors[index]
		actor.reparent(viewport)
		actor.transform = Transform3D.IDENTITY
		actor.position.x = (index - 2) * 2.0
		actor.pixel_size = 0.03
		actor.frame = 0
	var directory := "res://docs/validation/character-eyes"
	DirAccess.make_dir_recursive_absolute(directory)
	for enabled: bool in [false, true]:
		for actor in actors:
			actor.material_override.emission_enabled = enabled
		await _capture(viewport, directory + ("/after.png" if enabled else "/before.png"))
		if enabled:
			var rendered := viewport.get_texture().get_image()
			for actor in actors:
				var pixel := Vector2i(camera.unproject_position(actor.position + Vector3(0, -0.5, 0)))
				var body := rendered.get_pixelv(pixel)
				check(maxf(body.r, maxf(body.g, body.b)) < 0.1, "Rendered body stays dark: " + actor.name)
	environment.ambient_light_energy = 0.0
	await _capture(viewport, directory + "/dark.png")
	for actor in actors:
		actor.queue_free()
	actors.clear()
	world.queue_free()
	await get_tree().process_frame
	await _render_contexts(viewport, camera, directory)
	viewport.queue_free()
	await get_tree().process_frame


func _render_contexts(viewport: SubViewport, camera: Camera3D, directory: String) -> void:
	viewport.size = Vector2i(1280, 720)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 65.0
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	# Keep authored geometry, lighting and actor animations while preventing
	# startup, gameplay, audio and save logic in this visual-only fixture.
	_strip_gameplay(main)
	viewport.add_child(main)
	var original_camera := main.get_node("CameraPivot/CameraTilt/Camera3D") as Camera3D
	camera.global_transform = original_camera.global_transform
	camera.make_current()
	await _capture(viewport, directory + "/table-context.png")
	var paths := ["ScenePivot/GameTable/dealer/SatanMotionRoot/satan", "ScenePivot/Collection/angel", "BlackMarketRoom/Kiosk/Dealer", "GraveyardRoom/jester", "GraveyardRoom/Crypt/Prisoner"]
	for index in paths.size():
		var actor := main.get_node(paths[index]) as Sprite3D
		var ancestor: Node = actor
		while ancestor != main:
			if ancestor is Node3D:
				ancestor.show()
			ancestor = ancestor.get_parent()
		actor.set_process(false)
		actor.frame = 0
		# Collection faces the opposite wall of the hub.
		camera.global_position = actor.global_position + Vector3(0, 0.1, -4.5 if index == 1 else 4.5)
		camera.look_at(actor.global_position)
		await _capture(viewport, directory + "/context-" + str(ACTORS[index][3]) + ".png")
	main.queue_free()
	await get_tree().process_frame


func _strip_gameplay(node: Node) -> void:
	if node.get_script() != ANIMATION:
		node.set_script(null)
	if node is CanvasLayer:
		node.visible = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.autoplay = false
	for child in node.get_children():
		_strip_gameplay(child)


func _capture(viewport: SubViewport, path: String) -> void:
	for index in range(5):
		await RenderingServer.frame_post_draw
	var capture := viewport.get_texture().get_image()
	check(capture.save_png(path) == OK, "Saved review " + path)
	var report_path := "res://docs/validation/character-eyes/review_report.json"
	var report: Dictionary = {}
	if FileAccess.file_exists(report_path):
		report = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var luminance := 0.0
	for y in range(0, capture.get_height(), 8):
		for x in range(0, capture.get_width(), 8):
			var pixel := capture.get_pixel(x, y)
			luminance += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
	report[path.get_file()] = {
		"captured_at_utc": Time.get_datetime_string_from_system(true),
		"resolution": str(capture.get_size()),
		"mean_sampled_luminance": luminance / (ceilf(capture.get_width() / 8.0) * ceilf(capture.get_height() / 8.0)),
		"satan_material_modified": FileAccess.get_modified_time("res://assets/characters/satan/eye_glow.tres"),
		"fixture": "authored scene geometry and lighting; gameplay scripts disabled" if path.get_file().begins_with("context-") or path.get_file().begins_with("table-") else "isolated character row",
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
