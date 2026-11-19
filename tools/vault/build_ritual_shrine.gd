extends Node
const SURFACE := preload("res://assets/shader/basement_surface.gdshader")
var stone: ShaderMaterial
var dark: ShaderMaterial
var brass: StandardMaterial3D
var glow: StandardMaterial3D
var box := BoxMesh.new()

func _ready() -> void:
	stone = _stone(Color(0.28, 0.30, 0.27))
	dark = _stone(Color(0.055, 0.065, 0.055))
	brass = StandardMaterial3D.new()
	brass.albedo_color = Color(0.48, 0.32, 0.10)
	brass.metallic = 0.72
	brass.roughness = 0.65
	glow = StandardMaterial3D.new()
	glow.albedo_color = Color(0.75, 0.48, 0.13)
	glow.emission_enabled = true
	glow.emission = Color(0.9, 0.35, 0.045)
	glow.emission_energy_multiplier = 0.8
	var shrine := _build()
	_owners(shrine, shrine)
	var packed := PackedScene.new()
	if packed.pack(shrine) != OK or ResourceSaver.save(packed, "res://scenes/props/RitualShrine.tscn") != OK:
		get_tree().quit(1)
		return
	shrine.free()
	var saved := load("res://scenes/props/RitualShrine.tscn") as PackedScene
	var hall := (load("res://scenes/rooms/UndergroundVault.tscn") as PackedScene).instantiate() as Node3D
	if hall.has_node("RitualShrine"):
		var old := hall.get_node("RitualShrine")
		hall.remove_child(old)
		old.free()
	var instance := saved.instantiate() as Node3D
	instance.name = "RitualShrine"
	instance.position = Vector3(0, 0, 13.0)
	hall.add_child(instance)
	instance.owner = hall
	packed = PackedScene.new()
	var success := packed.pack(hall) == OK and ResourceSaver.save(packed, "res://scenes/rooms/UndergroundVault.tscn") == OK
	hall.free()
	if success:
		print("RITUAL_SHRINE_BUILD: PASS")
	get_tree().quit(0 if success else 1)

func _stone(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("mortar_color", Color(0.065, 0.075, 0.06))
	material.set_shader_parameter("masonry", false)
	material.set_shader_parameter("roughness_amount", 0.92)
	return material

func _box(parent: Node3D, label: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = box
	mesh.position = position
	mesh.scale = size
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _area(parent: Node3D, label: String, position: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = label
	area.position = position
	area.collision_layer = 1 << 26
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	parent.add_child(area)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	area.add_child(collider)
	return area

func _build() -> Node3D:
	var root := Node3D.new()
	root.name = "RitualShrine"
	root.set_script(load("res://scripts/rooms/RitualShrine.gd"))
	_box(root, "BuriedFoot", Vector3(0, 0.07, 0), Vector3(5.1, 0.18, 3.0), dark)
	_box(root, "LowerStep", Vector3(0, 0.23, 0), Vector3(4.9, 0.22, 2.8), stone)
	_box(root, "AltarBody", Vector3(0, 0.68, -0.15), Vector3(4.45, 0.82, 2.3), stone)
	_box(root, "ShadowBand", Vector3(0, 1.025, -0.15), Vector3(4.65, 0.12, 2.5), dark)
	_box(root, "AltarTop", Vector3(0, 1.15, -0.15), Vector3(4.95, 0.18, 2.9), stone)
	_box(root, "FrontInlay", Vector3(0, 0.73, 1.015), Vector3(3.8, 0.065, 0.04), brass)
	for x in [-1.7, -0.85, 0.0, 0.85, 1.7]:
		var rune := _box(root, "RitualRune", Vector3(x, 0.73, 1.045), Vector3(0.12, 0.25, 0.045), brass)
		rune.rotation_degrees.z = 45
	var sockets := Node3D.new()
	sockets.name = "Sockets"
	root.add_child(sockets)
	for index in range(3):
		var socket := Node3D.new()
		socket.name = "Socket%d" % index
		socket.position = Vector3((index - 1) * 1.35, 0, 0.05)
		sockets.add_child(socket)
		_box(socket, "Recess", Vector3(0, 1.252, 0), Vector3(1.05, 0.025, 1.50), dark)
		for side in [-1.0, 1.0]:
			_box(socket, "RimSide", Vector3(side * 0.55, 1.275, 0), Vector3(0.065, 0.06, 1.57), brass)
			_box(socket, "RimEnd", Vector3(0, 1.275, side * 0.78), Vector3(1.16, 0.06, 0.065), brass)
		var anchor := Marker3D.new()
		anchor.name = "CardAnchor"
		anchor.position = Vector3(0, 1.31, 0)
		anchor.rotation.x = -PI * 0.5
		anchor.scale = Vector3.ONE * 0.88
		socket.add_child(anchor)
		_area(socket, "PickArea", Vector3(0, 1.32, 0), Vector3(1.12, 0.24, 1.56))
	for side in [-1.0, 1.0]:
		_box(root, "RearPillar", Vector3(side * 2.12, 1.53, -1.24), Vector3(0.36, 0.60, 0.42), stone)
		_box(root, "EmberCup", Vector3(side * 2.12, 1.88, -1.24), Vector3(0.31, 0.13, 0.32), brass)
		_box(root, "Embers", Vector3(side * 2.12, 1.955, -1.24), Vector3(0.23, 0.035, 0.24), glow)
	var focus_area := _area(root, "FocusArea", Vector3(0, 1.0, 0), Vector3(5.15, 1.8, 3.0))
	# Extend the hover surface to the hand only after the altar is focused.
	var hand_hover := CollisionShape3D.new()
	hand_hover.name = "HandHoverShape"
	var hand_box := BoxShape3D.new()
	hand_box.size = Vector3(4.0, 1.35, 0.9)
	hand_hover.shape = hand_box
	hand_hover.position = Vector3(0, 0, 1.9)
	hand_hover.disabled = true
	focus_area.add_child(hand_hover)
	var focus := Marker3D.new()
	focus.name = "FocusCamera"
	focus.position = Vector3(0, 3.5, 3.7)
	focus.basis = Basis.looking_at(Vector3(0, 1.0, 0.3) - focus.position)
	root.add_child(focus)
	var hand := Node3D.new()
	hand.name = "AvailableCards"
	hand.position = Vector3(0, 1.0, 1.9)
	root.add_child(hand)
	var status := Label3D.new()
	status.name = "Status"
	status.position = Vector3(0, 1.1, 1.325)
	status.font = load("res://fonts/VCR_OSD_MONO_1.001.ttf")
	status.font_size = 30
	status.pixel_size = 0.0038
	status.modulate = Color(0.95, 0.78, 0.40)
	root.add_child(status)
	var reward := Node3D.new()
	reward.name = "Shotgun"
	reward.position = Vector3(0, 1.245, -1.08)
	reward.visible = false
	root.add_child(reward)
	var model := (load("res://assets/environments/props/shotgun/shotgun.tscn") as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.basis = (Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.5)).scaled(Vector3.ONE * 2.7)
	reward.add_child(model)
	var bounds := _bounds(model, Transform3D.IDENTITY)
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	_area(root, "ShotgunPickArea", reward.position + Vector3(0, bounds.size.y * 0.5, 0), bounds.size + Vector3(0.18, 0.20, 0.18))
	return root

func _bounds(node: Node3D, parent_pose: Transform3D) -> AABB:
	var pose := parent_pose * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh != null:
		bounds = pose * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, pose)
			if child_bounds.size.length() > 0:
				bounds = child_bounds if bounds.size.length() == 0 else bounds.merge(child_bounds)
	return bounds

func _owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if not child is Node3D or child.scene_file_path.is_empty():
			_owners(child, root)
