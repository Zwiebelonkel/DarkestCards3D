extends Node
## Bake the shared instrument once; static detailing never runs in gameplay.

const OUTPUT := "res://scenes/props/BoilerGauge.tscn"
var batches: Dictionary = {}
var materials: Dictionary = {}


func _ready() -> void:
	materials["iron"] = _material(Color(0.075, 0.085, 0.083), 0.6, 0.65)
	materials["brass"] = _material(Color(0.48, 0.32, 0.135), 0.7, 0.4)
	materials["ivory"] = _material(Color(0.76, 0.72, 0.57), 0.0, 0.74)
	materials["ink"] = _material(Color(0.035, 0.043, 0.038), 0.0, 0.85)
	materials["red"] = _material(Color(0.72, 0.075, 0.035), 0.25, 0.42)
	materials["ivory"].emission_enabled = true
	materials["ivory"].emission = Color(0.76, 0.72, 0.57)
	materials["ivory"].emission_energy_multiplier = 0.12
	for key: String in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = surface
	var root := Node3D.new()
	root.name = "BoilerGauge"
	add_child(root)
	# Rear mount enters the vessel; stepped rolled bezel overlaps the dial edge.
	_cylinder(0.14, 0.06, Vector3(0, 0, -0.01), "iron")
	_cylinder(0.217, 0.082, Vector3(0, 0, 0.025), "brass")
	_cylinder(0.202, 0.006, Vector3(0, 0, 0.068), "iron")
	_cylinder(0.193, 0.006, Vector3(0, 0, 0.073), "ivory")
	_torus(0.204, 0.22, Vector3(0, 0, 0.066), "brass")
	_torus(0.190, 0.199, Vector3(0, 0, 0.078), "brass")
	# Sixty divisions, half-unit marks and full-unit numbers share one ink surface.
	for index in range(61):
		var angle := deg_to_rad(-135.0 + float(index) * 4.5)
		var major := index % 10 == 0
		var half := index % 5 == 0
		var length := 0.022 if major else (0.015 if half else 0.008)
		var width := 0.0034 if major else 0.0016
		var radial := Vector2(sin(angle), cos(angle))
		_box(Vector3(width, length, 0.0009), Vector3(radial.x * (0.181 - length * 0.5), radial.y * (0.181 - length * 0.5), 0.077), -angle, "ink")
		if major:
			_text(str(index / 10), Vector2(radial.x, radial.y) * 0.139, 0.033)
	# A restrained high-pressure band follows the same calibrated sweep.
	for index in range(16):
		var angle := deg_to_rad(67.5 + (float(index) + 0.5) * 4.21875)
		var radial := Vector2(sin(angle), cos(angle))
		_box(Vector3(0.0123, 0.004, 0.0008), Vector3(radial.x * 0.186, radial.y * 0.186, 0.0775), -angle, "red")
	_text("bar", Vector2(0, 0.064), 0.021)
	_text("0 - 6", Vector2(0, -0.111), 0.013)
	# A recessed mechanical counter window keeps tenths easy to read for the puzzle.
	_box(Vector3(0.104, 0.041, 0.003), Vector3(0, -0.072, 0.078), 0, "brass")
	_box(Vector3(0.094, 0.032, 0.003), Vector3(0, -0.072, 0.080), 0, "iron")
	# Slotted screws are placed outside the calibrated arc, at the lower bezel.
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * 0.075, -0.193, 0.076)
		_cylinder(0.0075, 0.004, center, "iron", 16)
		_box(Vector3(0.010, 0.0015, 0.001), center + Vector3(0, 0, 0.0025), side * 0.35, "brass")
	# The center cap is fixed; the tapered pointer rotates underneath it.
	_cylinder(0.021, 0.012, Vector3(0, 0, 0.091), "iron", 32)
	_cylinder(0.013, 0.004, Vector3(0, 0, 0.099), "brass", 32)
	var static_mesh := ArrayMesh.new()
	for key: String in batches:
		var surface: SurfaceTool = batches[key]
		surface.set_material(materials[key])
		surface.commit(static_mesh)
	var body := MeshInstance3D.new()
	body.name = "HousingAndScale"
	body.mesh = static_mesh
	root.add_child(body)
	body.owner = root
	var needle := MeshInstance3D.new()
	needle.name = "GaugeNeedle"
	needle.mesh = _needle_mesh()
	needle.position.z = 0.084
	needle.rotation.z = deg_to_rad(9.0) # 2.8 bar, same calibration as the controller.
	var pointer_material := materials["red"].duplicate() as StandardMaterial3D
	pointer_material.emission_enabled = true
	pointer_material.emission = Color(0.72, 0.075, 0.035)
	pointer_material.emission_energy_multiplier = 0.22
	needle.material_override = pointer_material
	needle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(needle)
	needle.owner = root
	var digit_strip := await _bake_digit_strip()
	var digits := Node3D.new()
	digits.name = "PressureDigits"
	digits.set_script(load("res://scripts/rooms/BoilerPressureCounter.gd"))
	digits.position = Vector3(0, -0.072, 0.083)
	var drum_material := ShaderMaterial.new()
	drum_material.shader = load("res://scripts/rooms/boiler_counter.gdshader")
	drum_material.set_shader_parameter("digit_strip", digit_strip)
	for entry: Array in [["Units", -0.022, 2.0], ["Tenths", 0.022, 8.0]]:
		var drum := MeshInstance3D.new()
		drum.name = str(entry[0])
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.029, 0.028)
		drum.mesh = mesh
		drum.position.x = float(entry[1])
		drum.material_override = drum_material
		drum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drum.set_instance_shader_parameter("roll_steps", float(entry[2]))
		digits.add_child(drum)
	var decimal := Label3D.new()
	decimal.name = "DecimalPoint"
	decimal.position = Vector3(0, -0.0015, 0.0005)
	decimal.font = load("res://fonts/VCR_OSD_MONO_1.001.ttf")
	decimal.font_size = 40
	decimal.pixel_size = 0.00054
	decimal.text = "."
	decimal.modulate = Color(0.84, 0.78, 0.59)
	decimal.outline_size = 0
	digits.add_child(decimal)
	root.add_child(digits)
	digits.owner = root
	for child in digits.get_children():
		child.owner = root
	var packed := PackedScene.new()
	if packed.pack(root) != OK or ResourceSaver.save(packed, OUTPUT) != OK:
		push_error("Gauge scene could not be saved")
		get_tree().quit(1)
		return
	var saved := ResourceLoader.load(OUTPUT, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var round_trip := saved.instantiate()
	if round_trip.get_node_or_null("GaugeNeedle") == null or round_trip.get_node_or_null("PressureDigits") == null:
		push_error("Gauge round trip lost its interaction nodes")
		get_tree().quit(1)
		return
	round_trip.free()
	root.queue_free()
	await get_tree().process_frame
	print("BOILER_GAUGE_BUILD: PASS")
	get_tree().quit()


func _bake_digit_strip() -> Texture2D:
	# Baked once into the scene: no viewports or font rendering in the live counter.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 1280)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	for number in range(10):
		var label := Label.new()
		label.position = Vector2(0, number * 128)
		label.size = Vector2(96, 128)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", load("res://fonts/VCR_OSD_MONO_1.001.ttf"))
		label.add_theme_font_size_override("font_size", 96)
		label.text = str(number)
		viewport.add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	viewport.queue_free()
	return texture


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _append(mesh: Mesh, pose: Transform3D, key: String) -> void:
	(batches[key] as SurfaceTool).append_from(mesh, 0, pose)


func _cylinder(radius: float, depth: float, center: Vector3, key: String, segments: int = 64) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = segments
	mesh.rings = 1
	_append(mesh, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), center), key)


func _torus(inner: float, outer: float, center: Vector3, key: String) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 64
	mesh.ring_segments = 8
	_append(mesh, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), center), key)


func _box(size: Vector3, center: Vector3, angle: float, key: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh, Transform3D(Basis(Vector3.BACK, angle), center), key)


func _text(value: String, center: Vector2, height: float) -> void:
	var mesh := TextMesh.new()
	mesh.font = ThemeDB.fallback_font
	mesh.font_size = 64
	mesh.pixel_size = height / 64.0
	mesh.depth = 0
	mesh.text = value
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_append(mesh, Transform3D(Basis.IDENTITY, Vector3(center.x, center.y, 0.0779)), "ink")


func _needle_mesh() -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Raised pointer, fine point, broad base and an integrated counterweight.
	var outline: Array[Vector2] = [Vector2(0, 0.160), Vector2(-0.007, 0.034), Vector2(-0.006, -0.022), Vector2(-0.014, -0.039), Vector2(0, -0.050), Vector2(0.014, -0.039), Vector2(0.006, -0.022), Vector2(0.007, 0.034)]
	for index in range(outline.size()):
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		for point: Vector3 in [Vector3(0, 0, 0.0035), Vector3(b.x, b.y, 0.0015), Vector3(a.x, a.y, 0.0015)]:
			mesh.add_vertex(point)
		for point: Vector3 in [Vector3(a.x, a.y, 0), Vector3(a.x, a.y, 0.0015), Vector3(b.x, b.y, 0.0015), Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0.0015), Vector3(b.x, b.y, 0)]:
			mesh.add_vertex(point)
	mesh.generate_normals()
	return mesh.commit()
