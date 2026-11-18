extends RigidBody3D
## Each peer owns its cosmetic bodies. No RPCs, snapshots or gameplay RNG.

const PICK_LAYER := 1 << 10
const TABLE_LAYER := 1 << 11
const BODY_LAYER := 1 << 12
const HALF_HEIGHT := 0.06
const DROP_HEIGHT := 0.58
const DROP_SPEED := 4.5
const SETTLE_DURATION := 0.30
const HOLD_DURATION := 1.8
const DISSOLVE_DURATION := 2.0
const MAX_LIFETIME := 5.5
const DISSOLVE_SHADER := preload("res://assets/shader/dissolve.gdshader")

var landed := false
var kicked := false
var _elapsed := 0.0
var _landed_at := -1.0
var _settle_elapsed := 0.0
var _rest_height := 0.0
var _materials: Array[ShaderMaterial] = []
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_prepare_materials()
	body_entered.connect(_on_body_entered)


func drop_on(card_position: Vector3) -> void:
	# A short, fast fall triggers its blood burst at contact, without
	# delaying damage, deaths, multi-strikes or the next turn.
	global_position = card_position + Vector3.UP * (DROP_HEIGHT + HALF_HEIGHT)
	_rest_height = card_position.y + HALF_HEIGHT + 0.002
	global_rotation = Vector3(0.0, _random.randf_range(-0.28, 0.28), 0.0)
	linear_velocity = Vector3.DOWN * DROP_SPEED
	angular_velocity = Vector3.ZERO
	sleeping = false


func _on_body_entered(_body: Node) -> void:
	if landed:
		return
	landed = true
	_landed_at = _elapsed
	# Keep the first contact centered, then let the real rigid body bounce
	# and settle with a small peer-local tumble.
	angular_velocity = Vector3(_random.randf_range(-0.8, 0.8), _random.randf_range(-1.0, 1.0), _random.randf_range(-0.8, 0.8))


func _physics_process(delta: float) -> void:
	if not landed or kicked or freeze:
		return
	_settle_elapsed += delta
	if _settle_elapsed < SETTLE_DURATION:
		return
	# Thin boxes can keep rocking on the physics solver's contact margin.
	# Retire that simulation after the small bounce, with a flat resting pose.
	# Clicking explicitly unfreezes the body before applying its impulse.
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_rotation = Vector3(0.0, global_rotation.y, 0.0)
	global_position.y = _rest_height


func _process(delta: float) -> void:
	_elapsed += delta
	if _landed_at >= 0.0:
		var progress := (_elapsed - _landed_at - HOLD_DURATION) / DISSOLVE_DURATION
		set_dissolve_progress(progress)
		if progress >= 1.0:
			queue_free()
	if _elapsed >= MAX_LIFETIME:
		queue_free()


func set_dissolve_progress(value: float) -> void:
	for material in _materials:
		material.set_shader_parameter("dissolve_progress", clampf(value, 0.0, 1.0))
	if value >= 0.85:
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if kicked or not is_visible_in_tree() or get_tree().paused:
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return
	var origin := camera.project_ray_origin(event.position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(event.position) * camera.far, PICK_LAYER)
	# Cards are Areas; this early body-only ray consumes a brick click before
	# physics picking can also select the card underneath it. GUI runs first.
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") != self:
		return
	get_viewport().set_input_as_handled()
	kick(camera)


func kick(camera: Camera3D) -> void:
	if kicked or not is_instance_valid(camera):
		return
	kicked = true
	var direction := global_position - camera.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	freeze = false
	sleeping = false
	apply_central_impulse((direction.normalized() * 5.5 + Vector3.UP * 3.5) * mass)
	apply_torque_impulse(Vector3(_random.randf_range(-0.12, 0.12), 0.08, 0.16))
	# A click never restarts the lifetime or changes another peer's brick.
	if _landed_at < 0.0:
		_landed_at = _elapsed


func _prepare_materials() -> void:
	for node: Node in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = DISSOLVE_SHADER
			if source != null:
				material.set_shader_parameter("base_color", source.albedo_color)
				material.set_shader_parameter("albedo_texture", source.albedo_texture)
				material.set_shader_parameter("roughness_amount", source.roughness)
				material.set_shader_parameter("metallic_amount", source.metallic)
				material.set_shader_parameter("specular_amount", source.metallic_specular)
			material.set_shader_parameter("use_local_space", true)
			# Sweep along the long side so the breakup is readable from the
			# overhead match camera and follows the brick when it is kicked.
			var face_space := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
			material.set_shader_parameter("local_space_transform", face_space * global_transform.affine_inverse() * mesh.global_transform)
			material.set_shader_parameter("dissolve_min_y", -0.25)
			material.set_shader_parameter("dissolve_height", 0.5)
			material.set_shader_parameter("noise_scale", 32.0)
			material.set_shader_parameter("emission_intensity", 0.0)
			material.set_shader_parameter("dissolve_progress", 0.0)
			mesh.set_surface_override_material(surface, material)
			_materials.append(material)
