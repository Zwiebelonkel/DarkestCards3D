extends Node3D
## Open journal, with its reading surfaces in XY and their fronts facing +Z.
## Page faces finish at z=0.075; place printed content at z >= 0.10.
## Printable rectangles: centres (+/-1.65, 0), each 2.85 by 3.8 units.

const PAGE_SURFACE_Z := 0.075
const PRINT_SURFACE_Z := 0.10
const HINGE_Z := 0.084

var _open_amount := 1.0
var _right_leaf: Node3D
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _box_mesh: BoxMesh
var _rivet_mesh: CylinderMesh


func _ready() -> void:
	_make_materials()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_rivet_mesh = CylinderMesh.new()
	_rivet_mesh.top_radius = 0.5
	_rivet_mesh.bottom_radius = 0.5
	_rivet_mesh.height = 1.0
	_rivet_mesh.radial_segments = 8
	_right_leaf = Node3D.new()
	_right_leaf.name = "OpeningLeaf"
	_right_leaf.position.z = HINGE_Z
	add_child(_right_leaf)
	_build_half(self, -1.0)
	_build_half(_right_leaf, 1.0)
	_build_spine()
	_build_bookmark()
	_commit_batches()
	set_open_amount(_open_amount)


func set_open_amount(value: float) -> void:
	_open_amount = clampf(value, 0.0, 1.0)
	if is_instance_valid(_right_leaf):
		_right_leaf.rotation.y = PI * (1.0 - _open_amount)


func get_open_amount() -> float:
	return _open_amount


func _make_materials() -> void:
	_materials["leather"] = _material(Color("341a1c"), 0.86, 0.0)
	_materials["leather_edge"] = _material(Color("221316"), 0.94, 0.0)
	_materials["leather_raised"] = _material(Color("49272a"), 0.8, 0.0)
	_materials["brass"] = _material(Color("97794b"), 0.72, 0.55)
	_materials["brass_dark"] = _material(Color("604a31"), 0.83, 0.45)
	_materials["paper"] = _material(Color("d6c39b"), 0.95, 0.0)
	_materials["paper_edge"] = _material(Color("b8a47e"), 1.0, 0.0)
	_materials["paper_light"] = _material(Color("cfbd98"), 1.0, 0.0)
	_materials["gutter"] = _material(Color("978360"), 1.0, 0.0)
	_materials["thread"] = _material(Color("b19a75"), 1.0, 0.0)
	_materials["ribbon"] = _material(Color("723b38"), 1.0, 0.0)
	# Printed pages retain their contrast under the different room lights.
	for key in ["paper", "paper_edge", "paper_light", "gutter", "thread"]:
		(_materials[key] as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _material(tint: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = roughness
	result.metallic = metallic
	return result


func _build_half(parent: Node3D, side: float) -> void:
	# Thick leather boards, with a dark cut edge under the folded leather lip.
	_box(parent, Vector3(3.41, 4.63, 0.075), Vector3(side * 1.775, 0.0, -0.109), "leather_edge")
	_box(parent, Vector3(3.38, 4.57, 0.022), Vector3(side * 1.775, 0.0, -0.064), "leather")
	_box(parent, Vector3(3.32, 4.53, 0.007), Vector3(side * 1.775, 0.0, -0.147), "leather")
	# Four separately coloured page layers reveal a bound block at the edges.
	for layer in range(4):
		var inset := 0.008 * (layer % 2)
		var tint := "paper_light" if layer % 2 == 0 else "paper_edge"
		_box(parent, Vector3(3.20 - inset, 4.28 - inset, 0.027), Vector3(side * 1.695, 0.0, -0.031 + layer * 0.028), tint)
	_box(parent, Vector3(3.22, 4.30, 0.012), Vector3(side * 1.695, 0.0, PAGE_SURFACE_Z - 0.006), "paper")
	# Thin uneven fore-edge strokes read as stacked sheets at oblique angles.
	for edge in range(5):
		var z := -0.039 + edge * 0.023
		_box(parent, Vector3(0.008, 4.20, 0.005), Vector3(side * 3.303, 0.0, z), "paper_light")
		for end in [-1.0, 1.0]:
			_box(parent, Vector3(3.12, 0.008, 0.005), Vector3(side * 1.70, end * 2.153, z), "paper_light")
	# Recessed inner margins suggest the shallow valley of a sewn binding.
	_box(parent, Vector3(0.055, 4.26, 0.010), Vector3(side * 0.115, 0.0, 0.058), "gutter")
	_box(parent, Vector3(0.035, 4.26, 0.008), Vector3(side * 0.160, 0.0, 0.070), "paper_edge")
	# Blind-embossed rules stay in the margins outside the printable area.
	for end in [-1.0, 1.0]:
		_box(parent, Vector3(2.81, 0.010, 0.003), Vector3(side * 1.69, end * 2.008, 0.077), "paper_edge")
		_box(parent, Vector3(0.075, 0.075, 0.003), Vector3(side * 1.69, end * 2.008, 0.078), "paper_edge", Vector3(0.0, 0.0, PI / 4.0))
	# Brass corner shoes wrap the edge but never overlap printed text.
	for end in [-1.0, 1.0]:
		_box(parent, Vector3(0.30, 0.10, 0.025), Vector3(side * 3.327, end * 2.265, -0.038), "brass_dark")
		_box(parent, Vector3(0.10, 0.31, 0.025), Vector3(side * 3.427, end * 2.160, -0.038), "brass")
		_box(parent, Vector3(0.23, 0.025, 0.008), Vector3(side * 3.292, end * 2.268, -0.022), "brass")
		_rivet(parent, Vector3(side * 3.427, end * 2.239, -0.019), 0.045)
	_build_cover_embossing(parent, side)


func _build_cover_embossing(parent: Node3D, side: float) -> void:
	# The outside face is on -Z while open, becoming the visible front cover
	# as the right leaf folds over. Relief is shallow enough to keep the book thin.
	var center_x := side * 1.775
	for end in [-1.0, 1.0]:
		_box(parent, Vector3(0.29, 0.08, 0.006), Vector3(side * 3.33, end * 2.267, -0.153), "brass_dark")
		_box(parent, Vector3(0.08, 0.29, 0.006), Vector3(side * 3.435, end * 2.162, -0.153), "brass")
	for edge_x in [-1.41, 1.41]:
		_box(parent, Vector3(0.022, 4.08, 0.006), Vector3(center_x + edge_x, 0.0, -0.152), "brass_dark")
	for edge_y in [-2.04, 2.04]:
		_box(parent, Vector3(2.84, 0.022, 0.006), Vector3(center_x, edge_y, -0.152), "brass_dark")
	for edge_x in [-1.29, 1.29]:
		_box(parent, Vector3(0.036, 3.78, 0.004), Vector3(center_x + edge_x, 0.0, -0.152), "leather_raised")
	for edge_y in [-1.89, 1.89]:
		_box(parent, Vector3(2.60, 0.036, 0.004), Vector3(center_x, edge_y, -0.152), "leather_raised")
	# An inset geometric seal gives the closed cover an identifiable centre.
	_box(parent, Vector3(0.81, 0.81, 0.004), Vector3(center_x, 0.0, -0.1515), "brass_dark", Vector3(0.0, 0.0, PI / 4.0))
	_box(parent, Vector3(0.72, 0.72, 0.004), Vector3(center_x, 0.0, -0.155), "leather_edge", Vector3(0.0, 0.0, PI / 4.0))
	# A small quill embossed in the seal marks this as a writing journal.
	_box(parent, Vector3(0.025, 0.63, 0.004), Vector3(center_x, -0.01, -0.158), "brass", Vector3(0.0, 0.0, -0.42))
	for barb in range(3):
		var y := 0.005 + barb * 0.09
		var x := center_x + 0.02 + barb * 0.04
		_box(parent, Vector3(0.19 - barb * 0.035, 0.036, 0.004), Vector3(x - 0.054, y + 0.037, -0.158), "brass", Vector3(0.0, 0.0, -0.55))
		_box(parent, Vector3(0.17 - barb * 0.032, 0.036, 0.004), Vector3(x + 0.054, y - 0.015, -0.158), "brass", Vector3(0.0, 0.0, 0.46))
	for end in [-1.0, 1.0]:
		_box(parent, Vector3(0.105, 0.105, 0.004), Vector3(center_x, end * 1.58, -0.153), "brass_dark", Vector3(0.0, 0.0, PI / 4.0))


func _build_spine() -> void:
	_box(self, Vector3(0.17, 4.67, 0.16), Vector3(0.0, 0.0, -0.069), "leather_edge")
	_box(self, Vector3(0.10, 4.40, 0.038), Vector3(0.0, 0.0, 0.025), "leather")
	for y in [-1.94, -1.02, 0.0, 1.02, 1.94]:
		_box(self, Vector3(0.16, 0.11, 0.016), Vector3(0.0, y, 0.047), "leather_raised")
		for side in [-1.0, 1.0]:
			_box(self, Vector3(0.077, 0.014, 0.008), Vector3(side * 0.045, y, 0.060), "thread", Vector3(0.0, 0.0, side * 0.34))
	for end in [-1.0, 1.0]:
		for stitch in range(5):
			_box(self, Vector3(0.014, 0.073, 0.014), Vector3(-0.056 + stitch * 0.028, end * 2.205, 0.041), "thread" if stitch % 2 == 0 else "ribbon")


func _build_bookmark() -> void:
	var vertices := PackedVector3Array([
		Vector3(-0.105, 0.18, 0.0), Vector3(0.105, 0.18, 0.0),
		Vector3(0.105, -0.21, 0.0), Vector3(0.0, -0.14, 0.0),
		Vector3(-0.105, -0.21, 0.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 1, 2, 3, 0, 3, 4])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bookmark := MeshInstance3D.new()
	bookmark.name = "ClothBookmark"
	bookmark.mesh = mesh
	bookmark.position = Vector3(-0.44, -2.15, 0.084)
	var material := (_materials["ribbon"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bookmark.material_override = material
	add_child(bookmark)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.010, 0.30, 0.003), Vector3(-0.44 + side * 0.071, -2.115, 0.087), "brass_dark")


func _box(parent: Node3D, size: Vector3, at: Vector3, material: String, angles := Vector3.ZERO) -> void:
	_piece(parent, _box_mesh, material, size, at, angles)


func _rivet(parent: Node3D, at: Vector3, diameter: float) -> void:
	_piece(parent, _rivet_mesh, "brass", Vector3(diameter, 0.013, diameter), at, Vector3(PI / 2.0, 0.0, 0.0))


func _piece(parent: Node3D, mesh: Mesh, material: String, size: Vector3, at: Vector3, angles := Vector3.ZERO) -> void:
	var key := str(parent.get_instance_id()) + "_" + material + "_" + str(mesh.get_instance_id())
	if not _batches.has(key):
		_batches[key] = {"parent": parent, "mesh": mesh, "material": material, "transforms": []}
	var local_at := at - parent.position if parent == _right_leaf else at
	_batches[key]["transforms"].append(Transform3D(Basis.from_euler(angles) * Basis.from_scale(size), local_at))


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
		instance.name = "Book_" + str(batch["material"]) + "_" + str((batch["parent"] as Node3D).get_child_count())
		instance.multimesh = multimesh
		instance.material_override = _materials[batch["material"]]
		(batch["parent"] as Node3D).add_child(instance)
	_batches.clear()
