extends Node3D
## Static workshop geometry. Origin is the floor and the working side faces +Z.
## Repeated pieces are instanced in material batches to keep the prop inexpensive.

var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _box_mesh: BoxMesh
var _cylinder_mesh: CylinderMesh
var _cone_mesh: CylinderMesh
var _ember_light: OmniLight3D
var _rim_light: OmniLight3D
var _forge_strength := 0.0
var _forging := false
var _elapsed := 0.0


func _ready() -> void:
	_make_materials()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_cylinder_mesh = CylinderMesh.new()
	_cylinder_mesh.top_radius = 0.5
	_cylinder_mesh.bottom_radius = 0.5
	_cylinder_mesh.height = 1.0
	_cylinder_mesh.radial_segments = 8
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.0
	_cone_mesh.bottom_radius = 0.5
	_cone_mesh.height = 1.0
	_cone_mesh.radial_segments = 6
	_build_structure()
	_build_firebox()
	_build_tools()
	_commit_batches()
	_build_lights()


func set_forging(active: bool) -> void:
	_forging = active


func _process(delta: float) -> void:
	if not is_instance_valid(_ember_light) or not is_visible_in_tree():
		return
	_elapsed += delta
	_forge_strength = move_toward(_forge_strength, 1.0 if _forging else 0.0, delta * 2.4)
	var flicker := 1.0 + sin(_elapsed * 4.3) * 0.035 + sin(_elapsed * 7.7) * 0.022
	_ember_light.light_energy = (1.25 + _forge_strength * 2.2) * flicker
	_rim_light.light_energy = 0.55 + _forge_strength * 0.4
	var ember_material: StandardMaterial3D = _materials["ember"]
	ember_material.emission_energy_multiplier = (2.5 + _forge_strength * 3.5) * flicker


func _make_materials() -> void:
	_materials["oak"] = _material(Color("30231a"), 0.98, 0.0)
	_materials["oak_light"] = _material(Color("3b2b1e"), 0.98, 0.0)
	_materials["oak_dark"] = _material(Color("211b17"), 1.0, 0.0)
	_materials["iron"] = _material(Color("1d2123"), 0.8, 0.68)
	_materials["steel"] = _material(Color("515658"), 0.63, 0.8)
	_materials["brass"] = _material(Color("81603a"), 0.77, 0.6)
	_materials["coal"] = _material(Color("15100e"), 1.0, 0.0)
	var ember := _material(Color("bc3f0d"), 1.0, 0.0)
	ember.emission_enabled = true
	ember.emission = Color("ff6a13")
	ember.emission_energy_multiplier = 2.5
	_materials["ember"] = ember


func _material(tint: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = roughness
	result.metallic = metallic
	return result


func _build_structure() -> void:
	# Broad individual oak boards catch the room lighting with dark seams.
	for i in range(8):
		var grain := "oak_light" if i % 3 == 0 else "oak"
		_box(Vector3(0.837, 0.20, 2.42), Vector3(-2.975 + i * 0.85, 1.45, 0.73), grain)
	_box(Vector3(6.86, 0.16, 0.10), Vector3(0.0, 1.46, 1.98), "steel")
	_box(Vector3(6.86, 0.25, 0.12), Vector3(0.0, 1.27, 1.88), "iron")
	_box(Vector3(6.8, 0.22, 0.15), Vector3(0.0, 1.28, -0.39), "iron")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.11, 0.25, 2.5), Vector3(side * 3.42, 1.42, 0.73), "iron")
		for depth in [-0.2, 1.63]:
			_box(Vector3(0.34, 1.29, 0.34), Vector3(side * 2.97, 0.665, depth), "oak_dark")
			_box(Vector3(0.39, 0.18, 0.39), Vector3(side * 2.97, 0.14, depth), "iron")
			_box(Vector3(0.38, 0.23, 0.38), Vector3(side * 2.97, 1.17, depth), "iron")
		_box(Vector3(0.22, 0.2, 2.11), Vector3(side * 2.97, 0.36, 0.73), "oak")
		# Short diagonal knees make the table feel able to carry a heavy anvil.
		_box(Vector3(0.20, 0.60, 0.18), Vector3(side * 2.70, 1.01, 1.65), "iron", Vector3(0.0, 0.0, -side * 0.7))
	_box(Vector3(5.95, 0.20, 0.22), Vector3(0.0, 0.35, 0.0), "oak_dark")
	_box(Vector3(6.15, 0.12, 1.55), Vector3(0.0, 0.38, 0.69), "oak_dark")

	# Recessed backboard leaves the complete inventory and title areas usable.
	for i in range(12):
		var grain := "oak_dark" if i % 3 == 0 else "oak"
		_box(Vector3(0.533, 3.1, 0.16), Vector3(-2.97 + i * 0.54, 3.23, -0.30), grain)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.22, 3.37, 0.27), Vector3(side * 3.30, 3.245, -0.23), "iron")
		_box(Vector3(0.045, 3.20, 0.035), Vector3(side * 3.22, 3.24, -0.075), "brass")
		for bolt_y in [1.75, 2.45, 3.35, 4.15, 4.78]:
			_rivet(Vector3(side * 3.30, bolt_y, -0.075), 0.08)
	for rail_y in [1.67, 4.87]:
		_box(Vector3(6.81, 0.17, 0.25), Vector3(0.0, rail_y, -0.23), "iron")
		_box(Vector3(6.42, 0.027, 0.035), Vector3(0.0, rail_y, -0.082), "brass")
		for bolt_x in [-2.82, -1.62, 0.0, 1.62, 2.82]:
			_rivet(Vector3(bolt_x, rail_y, -0.075), 0.07)
	for bolt_x in [-3.2, -2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4, 3.2]:
		_rivet(Vector3(bolt_x, 1.26, 1.95), 0.063)
	# Worn steel reinforcing straps across the worktop, outside the inputs.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.16, 0.016, 2.2), Vector3(side * 2.79, 1.558, 0.73), "steel")


func _build_firebox() -> void:
	# The furnace lives under the bench; no flame crosses the displayed cards.
	_box(Vector3(3.16, 0.66, 1.21), Vector3(0.0, 0.79, 0.70), "iron")
	_box(Vector3(2.76, 0.43, 0.065), Vector3(0.0, 0.78, 1.32), "coal")
	_box(Vector3(2.61, 0.21, 0.038), Vector3(0.0, 0.69, 1.36), "ember")
	for i in range(18):
		var x := -1.23 + i * 0.145
		var height := 0.1 + float(i % 3) * 0.028
		_box(Vector3(0.17, height, 0.13), Vector3(x, 0.65 + float(i % 2) * 0.055, 1.39), "coal", Vector3(0.0, 0.17 * i, float(i % 4) * 0.16))
	for i in range(12):
		_box(Vector3(0.047, 0.50, 0.07), Vector3(-1.30 + i * 0.237, 0.80, 1.47), "iron")
	for edge_y in [0.535, 1.065]:
		_box(Vector3(2.92, 0.068, 0.10), Vector3(0.0, edge_y, 1.47), "steel")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.09, 0.59, 0.10), Vector3(side * 1.49, 0.80, 1.47), "steel")
		_rivet(Vector3(side * 1.49, 0.58, 1.535), 0.06)
		_rivet(Vector3(side * 1.49, 1.00, 1.535), 0.06)
	# A pair of warm vent slits on the front apron echo the glowing furnace.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.44, 0.032, 0.015), Vector3(side * 2.37, 1.27, 1.95), "brass")


func _build_tools() -> void:
	# Small anvil at the outer left corner, clear of all five offering slots.
	var anvil := Vector3(-2.94, 1.56, 0.17)
	_box(Vector3(0.57, 0.08, 0.65), anvil + Vector3(0.0, 0.04, 0.0), "steel")
	_box(Vector3(0.40, 0.12, 0.46), anvil + Vector3(0.0, 0.13, 0.0), "iron")
	_box(Vector3(0.24, 0.22, 0.29), anvil + Vector3(0.0, 0.28, 0.0), "iron")
	_box(Vector3(0.42, 0.13, 0.56), anvil + Vector3(0.0, 0.425, 0.0), "steel")
	_box(Vector3(0.44, 0.022, 0.59), anvil + Vector3(0.0, 0.502, 0.0), "steel")
	_piece(_cone_mesh, "steel", Vector3(0.27, 0.32, 0.21), anvil + Vector3(0.0, 0.427, 0.40), Vector3(PI / 2.0, 0.0, 0.0))
	# A square hardy hole reads as a dark inset without extra CSG geometry.
	_box(Vector3(0.087, 0.009, 0.08), anvil + Vector3(0.10, 0.517, -0.17), "coal")

	# Heavy forging hammer rests on the right-hand edge of the tabletop.
	var hammer := Vector3(3.02, 1.60, 0.22)
	_piece(_cylinder_mesh, "oak_light", Vector3(0.071, 0.83, 0.071), hammer + Vector3(0.0, 0.005, 0.22), Vector3(PI / 2.0, 0.0, 0.0))
	_box(Vector3(0.44, 0.21, 0.20), hammer + Vector3(0.0, 0.07, -0.18), "iron", Vector3(0.0, 0.06, 0.0))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.065, 0.22, 0.22), hammer + Vector3(side * 0.215, 0.07, -0.18), "steel")
	for i in range(4):
		_piece(_cylinder_mesh, "oak_dark", Vector3(0.079, 0.035, 0.079), hammer + Vector3(0.0, 0.006, 0.38 + i * 0.06), Vector3(PI / 2.0, 0.0, 0.0))
	# Spare steel ingots on the lower shelf beside the furnace.
	for i in range(3):
		_box(Vector3(0.57, 0.12, 0.20), Vector3(2.12, 0.51 + i * 0.11, 0.63), "steel", Vector3(0.0, -0.09 + i * 0.08, 0.0))
	_box(Vector3(0.47, 0.11, 0.19), Vector3(-2.16, 0.51, 0.75), "iron", Vector3(0.0, -0.25, 0.0))


func _build_lights() -> void:
	_ember_light = OmniLight3D.new()
	_ember_light.name = "EmberLight"
	_ember_light.position = Vector3(0.0, 0.90, 1.68)
	_ember_light.light_color = Color("ff9b46")
	_ember_light.light_energy = 1.25
	_ember_light.omni_range = 4.3
	_ember_light.omni_attenuation = 1.8
	_ember_light.shadow_enabled = false
	add_child(_ember_light)
	_rim_light = OmniLight3D.new()
	_rim_light.name = "WorkbenchWarmLight"
	_rim_light.position = Vector3(0.0, 3.60, 1.35)
	_rim_light.light_color = Color("ffd09a")
	_rim_light.light_energy = 0.55
	_rim_light.omni_range = 4.4
	_rim_light.omni_attenuation = 1.5
	_rim_light.shadow_enabled = false
	add_child(_rim_light)


func _box(size: Vector3, at: Vector3, material: String, angles := Vector3.ZERO) -> void:
	_piece(_box_mesh, material, size, at, angles)


func _rivet(at: Vector3, diameter: float) -> void:
	_piece(_cylinder_mesh, "steel", Vector3(diameter, 0.032, diameter), at, Vector3(PI / 2.0, 0.0, 0.0))


func _piece(mesh: Mesh, material: String, size: Vector3, at: Vector3, angles := Vector3.ZERO) -> void:
	var key := material + "_" + str(mesh.get_instance_id())
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": material, "transforms": []}
	var pose := Transform3D(Basis.from_euler(angles) * Basis.from_scale(size), at)
	_batches[key]["transforms"].append(pose)


func _commit_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var transforms: Array = batch["transforms"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = batch["mesh"]
		multimesh.instance_count = transforms.size()
		for i in range(transforms.size()):
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Forge_" + str(batch["material"]) + "_" + str(get_child_count())
		instance.multimesh = multimesh
		instance.material_override = _materials[batch["material"]]
		if batch["material"] == "ember":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	_batches.clear()
