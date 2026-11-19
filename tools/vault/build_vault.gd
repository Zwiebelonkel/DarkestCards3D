extends Node
## Deterministic, saved architecture. No runtime geometry generation.

const SURFACE := preload("res://assets/shader/basement_surface.gdshader")
var stone: ShaderMaterial
var pale: ShaderMaterial
var floor_material: ShaderMaterial
var dark: ShaderMaterial
var bronze: StandardMaterial3D
var glow: StandardMaterial3D
var unit_box := BoxMesh.new()


func _ready() -> void:
	stone = _stone(Color(0.27, 0.31, 0.29), true)
	pale = _stone(Color(0.40, 0.42, 0.37), false)
	floor_material = _stone(Color(0.20, 0.24, 0.23), false)
	dark = _stone(Color(0.09, 0.12, 0.115), true)
	bronze = StandardMaterial3D.new()
	bronze.albedo_color = Color(0.18, 0.14, 0.08)
	bronze.metallic = 0.65
	bronze.roughness = 0.72
	glow = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.56, 0.16)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.35, 0.055)
	glow.emission_energy_multiplier = 2.0
	if not _save(_build_stairs(), "res://scenes/props/GraveSecretStairs.tscn"):
		get_tree().quit(1)
		return
	if not _save(_build_hall(), "res://scenes/rooms/UndergroundVault.tscn"):
		get_tree().quit(1)
		return
	print("GRAVE_VAULT_BUILD: PASS")
	get_tree().quit()


func _stone(color: Color, masonry: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("mortar_color", Color(0.10, 0.12, 0.11))
	material.set_shader_parameter("masonry", masonry)
	return material


func _box(parent: Node3D, label: String, position: Vector3, size: Vector3, material: Material, collision: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = unit_box
	mesh.position = position
	mesh.scale = size
	mesh.material_override = material
	parent.add_child(mesh)
	if collision:
		_body_box(parent, label + "Body", position, size)
	return mesh


func _body_box(parent: Node3D, label: String, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body


func _multi(parent: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * 12)
	var bounds := AABB()
	for index in range(transforms.size()):
		var pose := transforms[index]
		var values := [pose.basis.x.x, pose.basis.y.x, pose.basis.z.x, pose.origin.x,
			pose.basis.x.y, pose.basis.y.y, pose.basis.z.y, pose.origin.y,
			pose.basis.x.z, pose.basis.y.z, pose.basis.z.z, pose.origin.z]
		for component in range(12):
			buffer[index * 12 + component] = values[component]
		var part := transforms[index] * mesh.get_aabb()
		bounds = part if index == 0 else bounds.merge(part)
	multi.buffer = buffer
	multi.custom_aabb = bounds.grow(0.03)
	instance.multimesh = multi
	instance.material_override = material
	parent.add_child(instance)


func _pose(position: Vector3, size: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(size), position)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var points: Array = [a, b, c, a, c, d] if (b - a).cross(c - a).dot(normal) > 0.0 else [a, c, b, a, d, c]
	for point in points:
		surface.set_normal(normal)
		surface.add_vertex(point)


func _arch(inner: float, outer: float, spring: float, depth: float, segments: int = 24) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var a := PI * index / segments
		var b := PI * (index + 1) / segments
		var da := Vector3(cos(a), sin(a), 0)
		var db := Vector3(cos(b), sin(b), 0)
		var offset := Vector3(0, spring, 0)
		var front := Vector3(0, 0, depth * 0.5)
		_quad(surface, offset + da * inner - front, offset + db * inner - front,
			offset + db * inner + front, offset + da * inner + front, -(da + db).normalized())
		_quad(surface, offset + da * outer + front, offset + db * outer + front,
			offset + db * outer - front, offset + da * outer - front, (da + db).normalized())
		for side in [-1.0, 1.0]:
			var z: Vector3 = front * side
			_quad(surface, offset + da * inner + z, offset + db * inner + z,
				offset + db * outer + z, offset + da * outer + z, Vector3(0, 0, side))
	surface.index()
	return surface.commit()


func _mesh(parent: Node3D, label: String, geometry: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = geometry
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _marker(parent: Node3D, label: String, position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = label
	marker.position = position
	parent.add_child(marker)
	return marker


func _build_stairs() -> Node3D:
	var root := Node3D.new()
	root.name = "GraveSecretStairs"
	var steps: Array[Transform3D] = []
	for index in range(64):
		steps.append(_pose(Vector3(0, -0.14 * (index + 1) - 0.11, -0.20 * index - 0.10), Vector3(2.4, 0.22, 0.215)))
	_multi(root, "StoneSteps", unit_box, steps, pale)
	# Continuous ramp under the visual treads, with no transverse threshold collider.
	var ramp := _body_box(root, "StairRamp", Vector3(0, -4.64, -6.4), Vector3(2.4, 0.24, sqrt(12.8 * 12.8 + 8.96 * 8.96)))
	ramp.rotation.x = -atan(0.14 / 0.20)
	for side in [-1.0, 1.0]:
		_mesh(root, "ShaftWall" + str(side), _shaft_wall(side), Vector3.ZERO, stone)
		var rim := _box(root, "OpeningRim" + str(side), Vector3(side * 1.39, 0.045, -3.2), Vector3(0.24, 0.19, 6.6), pale)
		rim.add_to_group("vault_entry_outline", true)
	_box(root, "TopThreshold", Vector3(0, -0.03, 0.13), Vector3(3.0, 0.20, 0.30), pale)
	_box(root, "BottomLanding", Vector3(0, -9.10, -13.10), Vector3(2.8, 0.28, 0.75), pale, true)
	# The covered lower shaft meets the underground hall below the graveyard soil.
	var cover := _box(root, "LowerShaftRoof", Vector3(0, -3.42, -8.6), Vector3(3.3, 0.30, 10.1), stone)
	cover.rotation.x = -atan(0.14 / 0.20)
	var arch := _arch(1.23, 1.40, 1.45, 0.24, 12)
	for index in range(4):
		var distance := 5.4 + index * 2.1
		_mesh(root, "ShaftArch%d" % index, arch, Vector3(0, -distance * 0.7, -distance), pale)
	for index in range(2):
		var z := -1.4 - index * 6.2
		_box(root, "LampBracket%d" % index, Vector3(-1.19, z * 0.7 + 1.1, z), Vector3(0.18, 0.36, 0.26), bronze)
		_box(root, "LampGlow%d" % index, Vector3(-1.09, z * 0.7 + 1.1, z), Vector3(0.09, 0.23, 0.17), glow)
		var light := OmniLight3D.new()
		light.name = "ShaftLamp%d" % index
		light.position = Vector3(-0.8, z * 0.7 + 1.1, z)
		light.light_color = Color(1.0, 0.60, 0.25)
		light.light_energy = 2.0
		light.omni_range = 5.0
		root.add_child(light)
	_marker(root, "TopRoute", Vector3(0, 1.05, 0.30))
	_marker(root, "MiddleRoute", Vector3(0, -3.43, -6.4))
	_marker(root, "BottomRoute", Vector3(0, -7.91, -13.15))
	_marker(root, "BottomFloor", Vector3(0, -8.96, -13.45))
	return root


func _shaft_wall(side: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(32):
		var a := index * 0.42
		var b := (index + 1) * 0.42
		var top_a := minf(0.12, -a * 0.7 + 2.5)
		var top_b := minf(0.12, -b * 0.7 + 2.5)
		var low_a := -a * 0.7 - 0.4
		var low_b := -b * 0.7 - 0.4
		for face in [-1.0, 1.0]:
			var x: float = side * 1.4 + face * 0.18
			_quad(surface, Vector3(x, low_a, -a), Vector3(x, low_b, -b), Vector3(x, top_b, -b), Vector3(x, top_a, -a), Vector3(face, 0, 0))
		_quad(surface, Vector3(side * 1.4 - 0.18, top_a, -a), Vector3(side * 1.4 + 0.18, top_a, -a), Vector3(side * 1.4 + 0.18, top_b, -b), Vector3(side * 1.4 - 0.18, top_b, -b), Vector3.UP)
	surface.index()
	return surface.commit()


func _build_hall() -> Node3D:
	var root := Node3D.new()
	root.name = "UndergroundVault"
	root.set_script(load("res://scripts/rooms/UndergroundVault.gd"))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.014, 0.022, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.57, 0.56)
	environment.ambient_light_energy = 0.50
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	root.set("room_environment", environment)
	_box(root, "Foundation", Vector3(0, -0.25, 0), Vector3(32, 0.5, 63), floor_material, true)
	_box(root, "CentralAisle", Vector3(0, 0.015, 0), Vector3(8.2, 0.03, 61), pale)
	for side in [-1.0, 1.0]:
		_box(root, "PerimeterWall" + str(side), Vector3(side * 15.75, 2.2, 0), Vector3(0.5, 4.6, 63), stone, true)
		_box(root, "AisleCeiling" + str(side), Vector3(side * 12.35, 4.18, 0), Vector3(6.9, 0.30, 63), stone)
		_box(root, "SouthWall" + str(side), Vector3(side * 9.2, 2.15, 31.25), Vector3(13.6, 4.5, 0.5), stone, true)
		_box(root, "PortalJamb" + str(side), Vector3(side * 2.48, 2.15, 31.02), Vector3(0.34, 4.5, 0.7), pale)
	_box(root, "PortalLintel", Vector3(0, 4.48, 31.02), Vector3(5.3, 0.36, 0.7), pale)
	_box(root, "NorthWall", Vector3(0, 2.15, -31.25), Vector3(32, 4.5, 0.5), stone, true)
	_mesh(root, "BarrelVault", _arch(9.0, 9.36, 4.20, 63.0), Vector3.ZERO, stone)
	# Filled semicircular end walls overlap the roof shell instead of leaving sky gaps.
	var end := SurfaceTool.new()
	end.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(24):
		for side in [-1.0, 1.0]:
			var points: Array[Vector3] = [Vector3(0, 4.12, side * 0.12), Vector3(cos(PI * index / 24.0) * 9.12, 4.2 + sin(PI * index / 24.0) * 9.12, side * 0.12), Vector3(cos(PI * (index + 1) / 24.0) * 9.12, 4.2 + sin(PI * (index + 1) / 24.0) * 9.12, side * 0.12)]
			if side < 0:
				points.reverse()
			for point in points:
				end.set_normal(Vector3(0, 0, side))
				end.add_vertex(point)
	var end_mesh := end.commit()
	_mesh(root, "SouthRoofEnd", end_mesh, Vector3(0, 0, 31.20), stone)
	var north_end := _mesh(root, "NorthRoofEnd", end_mesh, Vector3(0, 0, -31.20), stone)
	north_end.rotation.y = PI
	var shafts: Array[Transform3D] = []
	var bases: Array[Transform3D] = []
	var capitals: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var coffins: Array[Transform3D] = []
	var lids: Array[Transform3D] = []
	var column := CylinderMesh.new()
	column.top_radius = 0.62
	column.bottom_radius = 0.72
	column.height = 3.55
	column.radial_segments = 10
	column.rings = 1
	var rib := _arch(8.77, 9.17, 4.18, 0.48)
	for bay in range(9):
		var z := -27.0 + bay * 6.75
		_mesh(root, "VaultRib%d" % bay, rib, Vector3(0, 0, z), pale)
		for side in [-1.0, 1.0]:
			shafts.append(_pose(Vector3(side * 9.0, 2.075, z)))
			bases.append(_pose(Vector3(side * 9.0, 0.20, z), Vector3(1.7, 0.40, 1.7)))
			capitals.append(_pose(Vector3(side * 9.0, 4.02, z), Vector3(1.75, 0.48, 1.75)))
			lamps.append(_pose(Vector3(side * 8.15, 2.6, z), Vector3(0.13, 0.44, 0.22)))
			if bay > 0 and bay < 8:
				coffins.append(_pose(Vector3(side * 12.5, 0.45, z), Vector3(1.6, 0.90, 3.0)))
				lids.append(_pose(Vector3(side * 12.5, 0.98, z), Vector3(1.80, 0.24, 3.16)))
	_multi(root, "Columns", column, shafts, stone)
	_multi(root, "ColumnBases", unit_box, bases, pale)
	_multi(root, "ColumnCapitals", unit_box, capitals, pale)
	_multi(root, "WarmNaveLamps", unit_box, lamps, glow)
	_multi(root, "SideSarcophagi", unit_box, coffins, stone)
	_multi(root, "SarcophagusLids", unit_box, lids, pale)
	_box(root, "FarDaisLower", Vector3(0, 0.12, -26), Vector3(6.0, 0.24, 5.0), pale)
	_box(root, "FarDaisUpper", Vector3(0, 0.30, -26.4), Vector3(4.8, 0.24, 3.8), pale)
	_box(root, "EmptyStonePlinth", Vector3(0, 0.90, -26.4), Vector3(2.8, 1.0, 1.6), stone)
	for index in range(4):
		var light := OmniLight3D.new()
		light.name = "HallFill%d" % index
		light.position = Vector3(-5 if index % 2 == 0 else 5, 4.5, -19 if index < 2 else 19)
		light.light_color = Color(0.50, 0.68, 0.70) if index < 2 else Color(1.0, 0.66, 0.34)
		light.light_energy = 5.0
		light.omni_range = 32
		light.omni_attenuation = 0.8
		root.add_child(light)
	for index in range(2):
		var light := SpotLight3D.new()
		light.name = "VaultKey%d" % index
		light.position = Vector3(0, 11, -16 if index == 0 else 16)
		light.rotation_degrees.x = -90
		light.light_color = Color(0.68, 0.77, 0.75)
		light.light_energy = 3.5
		light.spot_range = 32
		light.spot_angle = 78
		light.shadow_enabled = true
		root.add_child(light)
	_marker(root, "EntranceFloor", Vector3(0, 0, 31.5))
	_marker(root, "CameraAnchor", Vector3(0, 0, 18))
	var exit_area := Area3D.new()
	exit_area.name = "ExitArea"
	exit_area.position = Vector3(0, 1.7, 30.6)
	exit_area.collision_layer = 0
	exit_area.collision_mask = 0
	exit_area.input_ray_pickable = false
	exit_area.monitoring = false
	exit_area.monitorable = false
	root.add_child(exit_area)
	var exit_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.65, 3.8, 1.0)
	exit_shape.shape = box
	exit_area.add_child(exit_shape)
	if ResourceLoader.exists("res://scenes/props/RitualShrine.tscn"):
		var shrine := (load("res://scenes/props/RitualShrine.tscn") as PackedScene).instantiate() as Node3D
		shrine.name = "RitualShrine"
		shrine.position = Vector3(0, 0, 13)
		root.add_child(shrine)
	return root


func _save(root: Node3D, path: String) -> bool:
	_assign_owner(root, root)
	var packed := PackedScene.new()
	var valid := packed.pack(root) == OK and ResourceSaver.save(packed, path) == OK
	root.free()
	if not valid:
		push_error("Cannot save " + path)
		return false
	var reloaded: Node3D = (load(path) as PackedScene).instantiate()
	valid = reloaded != null and reloaded.get_child_count() > 0
	if reloaded != null:
		for node in reloaded.find_children("*", "MultiMeshInstance3D", true, false):
			var multi := (node as MultiMeshInstance3D).multimesh
			valid = valid and multi != null and multi.buffer.size() == multi.instance_count * 12 and multi.custom_aabb.size.length() > 0
	if reloaded != null:
		reloaded.free()
	return valid


func _assign_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		if not child is Node3D or child.scene_file_path.is_empty():
			_assign_owner(child, owner_root)
