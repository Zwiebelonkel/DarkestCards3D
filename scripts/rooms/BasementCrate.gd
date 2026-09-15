extends LocalTableProp
class_name BasementCrate
## Main enables these local decorations only while the basement accepts input.

signal thrown(crate: BasementCrate)

const FLYING_COLLISION_LAYER := 1 << 11
const ENVIRONMENT_COLLISION_LAYER := 1 << 12
const DISSOLVE_SHADER := preload("res://assets/shader/dissolve.gdshader")
const CRATE_THROW_SOUND := preload("res://assets/sounds/SFX/crateThrow.mp3")

@export var interaction_enabled := false
@export_range(0.0, 15.0, 0.1) var dissolve_delay := 4.0
@export_range(0.1, 5.0, 0.1) var dissolve_duration := 1.2

var _rigid_body: RigidBody3D
var _original_parent: Node
var _dissolve_materials: Array[ShaderMaterial] = []
var _dissolve_started := false
var _dissolve_progress := 0.0


func _ready() -> void:
	add_to_group("basement_crates")
	if throw_sound == null:
		throw_sound = CRATE_THROW_SOUND
	super._ready()
	_sync_pick_visibility()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	_sync_pick_visibility()


func get_rigid_body() -> RigidBody3D:
	return _rigid_body if is_instance_valid(_rigid_body) else null


func get_dissolve_progress() -> float:
	return _dissolve_progress


func is_dissolving() -> bool:
	return _dissolve_started and _dissolve_progress < 1.0


func _sync_pick_visibility() -> void:
	if not is_instance_valid(_pick_area):
		return
	var enabled := interaction_enabled and not _launched and is_visible_in_tree()
	_pick_area.input_ray_pickable = enabled
	_pick_area.collision_layer = PICK_COLLISION_LAYER if enabled else 0
	_pick_area.set_meta("keep_input_ray_pickable_disabled", not enabled)


func _on_input_event(camera: Node, event: InputEvent, hit_position: Vector3, normal: Vector3, shape_index: int) -> void:
	if not interaction_enabled:
		return
	super._on_input_event(camera, event, hit_position, normal, shape_index)


func _launch(camera: Camera3D) -> void:
	if not interaction_enabled or _launched or not is_visible_in_tree() or get_tree().paused:
		return
	if not is_instance_valid(camera) or camera != get_viewport().get_camera_3d():
		return
	super._launch(camera)
	if _launched:
		_original_parent = get_parent()
		# Picking is delivered during physics queries. Add/reparent the body
		# after those queries finish, while keeping the once-only award timely.
		_start_physical_flight.call_deferred()
		thrown.emit(self)


func _start_physical_flight() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(_original_parent):
		return
	var body_basis := _flight_start.basis.orthonormalized()
	if body_basis.determinant() < 0.0:
		body_basis.z = -body_basis.z
	var body_pose := Transform3D(body_basis, _flight_center)
	var bounds := _mesh_bounds(body_pose.affine_inverse())
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(bounds.size.x, 0.01), maxf(bounds.size.y, 0.01), maxf(bounds.size.z, 0.01))
	shape.margin = 0.002
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = bounds.get_center()
	_rigid_body = RigidBody3D.new()
	_rigid_body.name = str(name) + "FlightBody"
	_rigid_body.top_level = true
	_rigid_body.transform = body_pose
	_rigid_body.collision_layer = FLYING_COLLISION_LAYER
	_rigid_body.collision_mask = ENVIRONMENT_COLLISION_LAYER | FLYING_COLLISION_LAYER
	_rigid_body.input_ray_pickable = false
	_rigid_body.continuous_cd = true
	_rigid_body.mass = 3.0
	_rigid_body.gravity_scale = gravity / maxf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)), 0.001)
	_rigid_body.linear_damp = 0.12
	_rigid_body.angular_damp = 0.8
	var physical_material := PhysicsMaterial.new()
	physical_material.friction = 0.8
	physical_material.bounce = 0.18
	_rigid_body.physics_material_override = physical_material
	_rigid_body.add_child(collision)
	_original_parent.add_child(_rigid_body)
	# Preserve the complete authored pose/scale in the visual child. The
	# physics body and its baked box have no inherited non-uniform scale.
	reparent(_rigid_body, true)
	_rigid_body.linear_velocity = _velocity
	_rigid_body.angular_velocity = _spin_axis * _spin_speed
	_sync_pick_visibility()


func _physics_process(delta: float) -> void:
	# The rigid body owns motion. The base prop's analytic arc and timed hide
	# must never run for basement crates, including after they hit a surface.
	if not _launched:
		return
	_flight_time += delta
	if not is_instance_valid(_rigid_body) or _flight_time < dissolve_delay:
		return
	if not _dissolve_started:
		_begin_dissolve()
	_dissolve_progress = clampf((_flight_time - dissolve_delay) / maxf(dissolve_duration, 0.001), 0.0, 1.0)
	for material in _dissolve_materials:
		material.set_shader_parameter("dissolve_progress", _dissolve_progress)
	if _dissolve_progress >= 1.0:
		set_physics_process(false)
		_finish_flight.call_deferred()


func _mesh_bounds(to_space: Transform3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	var bounds := AABB()
	var found := false
	for mesh in meshes:
		var mesh_bounds: AABB = to_space * mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	return bounds


func _begin_dissolve() -> void:
	_dissolve_started = true
	var world_bounds := _mesh_bounds(Transform3D.IDENTITY)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	for mesh in meshes:
		# A node override takes priority over surface overrides. Capture the
		# actual visible materials first, then install independent replacements.
		var source_materials: Array[Material] = []
		for surface in range(mesh.mesh.get_surface_count()):
			source_materials.append(mesh.get_active_material(surface))
		mesh.material_override = null
		for surface in range(source_materials.size()):
			var material := ShaderMaterial.new()
			material.shader = DISSOLVE_SHADER
			var source := source_materials[surface] as BaseMaterial3D
			if source != null:
				material.set_shader_parameter("base_color", source.albedo_color)
				material.set_shader_parameter("albedo_texture", source.albedo_texture)
				material.set_shader_parameter("texture_uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
				material.set_shader_parameter("texture_uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
				material.set_shader_parameter("roughness_amount", source.roughness)
				material.set_shader_parameter("metallic_amount", source.metallic)
				material.set_shader_parameter("specular_amount", source.metallic_specular)
			# All planks and metal straps share one world-space sweep; their
			# separate origins/UVs cannot restart the effect on each component.
			material.set_shader_parameter("dissolve_min_y", world_bounds.position.y)
			material.set_shader_parameter("dissolve_height", maxf(world_bounds.size.y, 0.01))
			material.set_shader_parameter("dissolve_progress", 0.0)
			mesh.set_surface_override_material(surface, material)
			_dissolve_materials.append(material)


func _finish_flight() -> void:
	hide()
	_sync_pick_visibility()
	if is_instance_valid(_rigid_body):
		var finished_body := _rigid_body
		if is_instance_valid(_original_parent) and not _original_parent.is_queued_for_deletion():
			# Discovery/Main retain crate references after the body is gone.
			reparent(_original_parent, true)
		_rigid_body = null
		finished_body.queue_free()
