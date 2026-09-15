extends Node

const ENVIRONMENT_LAYER := 1 << 12
const CRATE_LAYER := 1 << 11

var checks := 0
var failures := 0
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var template: Node3D
var throws := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	print(("PASS: " if condition else "FAIL: ") + message)


func _settle(seconds: float = 0.05) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 3, 7)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	# Duplicate the actual compound crate, including its authored mesh parts.
	# A known thin wall makes reflection and CCD failures reproducible.
	template = (load("res://scenes/rooms/Basement.tscn") as PackedScene).instantiate() as Node3D
	_add_box(Vector3(0, -0.25, 0), Vector3(30, 0.5, 30))
	_add_box(Vector3(3, 3, 0), Vector3(0.08, 6, 20))
	var holder := Node3D.new()
	holder.name = "ScaledCrateParent"
	holder.transform = Transform3D(Basis.from_euler(Vector3(0, 0.3, 0)) * Basis.from_scale(Vector3.ONE * 1.25), Vector3(-0.5, 0, -0.5))
	world.add_child(holder)
	var crate := _add_crate(holder, Vector3(0, 2, 0))
	var untouched := _add_crate(holder, Vector3(-4, 1.5, 5))
	var untouched_pose := untouched.global_transform
	var untouched_materials := _materials(untouched)
	await _settle()
	check(not crate._launched and crate.get_rigid_body() == null and not crate._pick_area.input_ray_pickable, "unthrown crates remain authored decorations until an enabled click")
	crate.set_interaction_enabled(true)
	var original_parent := crate.get_parent()
	var original_scale := crate.global_basis.get_scale()
	var original_position := crate.global_position
	# A cosmetic click must not consume the game's battle/reward RNG.
	seed(831072)
	var expected_random := randi()
	seed(831072)
	_click_area(crate)
	check(randi() == expected_random, "throwing a crate leaves the global battle RNG untouched")
	await _wait_body(crate)
	var body := crate.get_rigid_body()
	check(body != null, "the actual Area3D input creates a live RigidBody3D")
	if body == null:
		_finish()
		return
	check(body.collision_layer == CRATE_LAYER and (body.collision_mask & ENVIRONMENT_LAYER) != 0 and body.continuous_cd and not body.input_ray_pickable, "thrown bodies collide with the room and enable continuous collision detection without becoming mouse targets")
	check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE) and crate.global_basis.get_scale().is_equal_approx(original_scale) and crate.global_position.distance_to(original_position) < 0.5, "rigid-body adoption preserves the scaled authored crate without scaling its physics body or teleporting it")
	check(not crate._pick_area.input_ray_pickable and crate._pick_area.collision_layer == 0 and throws == 1, "launch emits once and removes its former click collider")
	_click_area(crate)
	crate.set_interaction_enabled(false)
	crate.set_interaction_enabled(true)
	check(crate.get_rigid_body() == body and throws == 1 and not crate._pick_area.input_ray_pickable, "duplicate input and room gating cannot create a second body or reset a thrown crate")
	body.gravity_scale = 0.0
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3(12, 0, 0)
	var impact := await _observe_wall_impact(body, 0.8)
	check(impact.reflected and impact.max_x < 3.04, "a normal throw strikes the thin wall and rebounds into the room")
	body.gravity_scale = 1.0
	# A second throw crosses more than the complete wall thickness per tick.
	var fast_crate := _add_crate(world, Vector3(0, 2, 3))
	fast_crate.set_interaction_enabled(true)
	_click_area(fast_crate)
	await _wait_body(fast_crate)
	var fast_body := fast_crate.get_rigid_body()
	if fast_body != null:
		fast_body.gravity_scale = 0.0
		fast_body.angular_velocity = Vector3.ZERO
		fast_body.linear_velocity = Vector3(120, 0, 0)
		var fast_impact := await _observe_wall_impact(fast_body, 0.35)
		check(fast_impact.reflected and fast_impact.max_x < 3.04, "a high-speed throw cannot tunnel through an eight-centimeter wall")
		fast_body.linear_velocity = Vector3.ZERO
		fast_body.gravity_scale = 1.0
	else:
		check(false, "the high-speed throw creates its physical body")
	var minimum_bottom := INF
	var landed := false
	var floor_deadline := Time.get_ticks_msec() + 1700
	while Time.get_ticks_msec() < floor_deadline and is_instance_valid(body):
		await get_tree().physics_frame
		await get_tree().process_frame
		var bounds := _world_bounds(crate)
		minimum_bottom = minf(minimum_bottom, bounds.position.y)
		landed = landed or (bounds.position.y < 0.12 and absf(body.linear_velocity.y) < 0.25)
	check(landed and minimum_bottom > -0.08, "the complete crate lands on the floor without falling or tunneling below it")
	check(crate.is_visible_in_tree() and not crate.is_dissolving() and is_zero_approx(crate.get_dissolve_progress()), "crate geometry remains visible for several seconds after the impact")
	check(untouched.global_transform.is_equal_approx(untouched_pose) and untouched.get_rigid_body() == null and not untouched._launched, "the neighboring unthrown crate retains its authored pose and static state")
	await _wait_dissolve(crate)
	check(crate.is_dissolving() and crate.get_dissolve_progress() > 0.0 and crate.get_dissolve_progress() < 1.0 and crate.is_visible_in_tree(), "cleanup begins with a gradual visible dissolve rather than an immediate hide")
	var progress := crate.get_dissolve_progress()
	var paused_pose := body.global_transform
	get_tree().paused = true
	await get_tree().create_timer(0.3, true).timeout
	check(is_equal_approx(crate.get_dissolve_progress(), progress) and body.global_transform.is_equal_approx(paused_pose), "Pause freezes the physics body and dissolve together")
	get_tree().paused = false
	await _settle(crate.dissolve_duration * 0.25)
	check(crate.get_dissolve_progress() > progress and crate.get_dissolve_progress() < 1.0, "dissolve resumes smoothly when Pause closes")
	_check_dissolve_materials(crate, untouched, untouched_materials)
	var body_reference: WeakRef = weakref(body)
	await _settle(crate.dissolve_duration + 0.2)
	check(not crate.is_visible_in_tree() and not crate.is_physics_processing() and crate.get_rigid_body() == null and body_reference.get_ref() == null, "finished dissolve hides every mesh and frees the rigid-body resources")
	check(crate.get_parent() == original_parent and crate._launched and not crate._pick_area.input_ray_pickable, "cleanup keeps the spent crate node valid under its original parent without enabling another throw")
	check(untouched.global_transform.is_equal_approx(untouched_pose) and _materials(untouched) == untouched_materials, "dissolve never mutates shared materials or transforms on an untouched crate")
	template.free()
	world.queue_free()
	await _settle()
	_finish()


func _add_box(position: Vector3, size: Vector3) -> void:
	var static_body := StaticBody3D.new()
	static_body.collision_layer = ENVIRONMENT_LAYER
	static_body.collision_mask = 0
	world.add_child(static_body)
	static_body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	static_body.add_child(collision)


func _add_crate(parent: Node3D, position: Vector3) -> BasementCrate:
	var crate := template.get_node("Storage/FloorCrate").duplicate() as BasementCrate
	crate.name = "Crate%d" % parent.get_child_count()
	crate.transform = Transform3D.IDENTITY
	parent.add_child(crate)
	crate.global_position = position
	crate.thrown.connect(func(_crate: BasementCrate): throws += 1)
	return crate


func _click_area(crate: BasementCrate) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	crate._pick_area.input_event.emit(camera, event, crate.to_global(crate._center_local), Vector3.UP, 0)


func _wait_body(crate: BasementCrate) -> void:
	for _frame in range(12):
		if crate.get_rigid_body() != null:
			return
		await get_tree().physics_frame
		await get_tree().process_frame


func _observe_wall_impact(body: RigidBody3D, seconds: float) -> Dictionary:
	var max_x := body.global_position.x
	var reflected := false
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and not reflected:
		await get_tree().physics_frame
		await get_tree().process_frame
		max_x = maxf(max_x, body.global_position.x)
		reflected = body.linear_velocity.x < -0.05
	return {"reflected": reflected, "max_x": max_x}


func _wait_dissolve(crate: BasementCrate) -> void:
	var deadline := Time.get_ticks_msec() + int((crate.dissolve_delay + 1.0) * 1000.0)
	while (not crate.is_dissolving() or crate.get_dissolve_progress() <= 0.0) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		await get_tree().process_frame


func _meshes(crate: BasementCrate) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in crate.find_children("*", "MeshInstance3D", true, false):
		if node.mesh != null:
			result.append(node as MeshInstance3D)
	return result


func _materials(crate: BasementCrate) -> Array[Material]:
	var result: Array[Material] = []
	for mesh in _meshes(crate):
		for surface in range(mesh.mesh.get_surface_count()):
			result.append(mesh.get_active_material(surface))
	return result


func _world_bounds(crate: BasementCrate) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in _meshes(crate):
		var part_bounds := mesh.global_transform * mesh.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	return bounds


func _check_dissolve_materials(crate: BasementCrate, untouched: BasementCrate, original: Array[Material]) -> void:
	var materials := _materials(crate)
	var all_shader_materials := not materials.is_empty()
	var all_progress_matches := true
	var all_base_colors_preserved := true
	for index in range(materials.size()):
		var material := materials[index]
		all_shader_materials = all_shader_materials and material is ShaderMaterial and not original.has(material)
		if material is ShaderMaterial:
			all_progress_matches = all_progress_matches and is_equal_approx(float(material.get_shader_parameter("dissolve_progress")), crate.get_dissolve_progress())
			if original[index] is BaseMaterial3D:
				all_base_colors_preserved = all_base_colors_preserved and material.get_shader_parameter("base_color") == (original[index] as BaseMaterial3D).albedo_color
		else:
			all_progress_matches = false
	check(all_shader_materials and materials.size() == original.size(), "dissolve covers every authored wood, corner and metal-band surface with private materials")
	check(all_progress_matches and all_base_colors_preserved, "all component surfaces dissolve together while retaining their authored colors")
	check(_materials(untouched) == original, "starting the dissolve leaves the neighboring crate's shared materials intact")


func _finish() -> void:
	print("BASEMENT_CRATE_PHYSICS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
