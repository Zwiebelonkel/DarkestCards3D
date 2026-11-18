extends Node3D

## Scripted motion: the combat roll owns the face; physics never rerolls it.
const FLIGHT_DURATION := 0.42
const SETTLE_DURATION := 0.12
const RESULT_HOLD_DURATION := 0.16
const REVEAL_DURATION := FLIGHT_DURATION + SETTLE_DURATION + RESULT_HOLD_DURATION
const DISSOLVE_DURATION := 1.15
const DISSOLVE_SHADER := preload("res://assets/shader/dissolve.gdshader")

var result_revealed := false
var multiplier := 1.0
var _elapsed := 0.0
var _playing := false
var _dissolving := false
var _dissolve_elapsed := 0.0
var _landing_position := Vector3.ZERO
var _entry_offset := Vector3.ZERO
var _face_angle := 0.0
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_prepare_materials()


func play_flip(value: float, landing_position: Vector3, entry_offset: Vector3) -> void:
	multiplier = value
	_landing_position = landing_position
	_entry_offset = entry_offset
	# The imported model has red 0.75 on +Y and green 2 on -Y.
	_face_angle = PI if value > 1.0 else 0.0
	_elapsed = 0.0
	_playing = true
	result_revealed = false
	_apply_flip(0.0)
	$Sound.play()


func _process(delta: float) -> void:
	if _playing and not result_revealed:
		_elapsed += delta
		_apply_flip(_elapsed)
		result_revealed = _elapsed >= REVEAL_DURATION
	if _dissolving:
		_dissolve_elapsed += delta
		set_dissolve_progress(_dissolve_elapsed / DISSOLVE_DURATION)
		if _dissolve_elapsed >= DISSOLVE_DURATION:
			queue_free()


func _apply_flip(elapsed: float) -> void:
	if elapsed < FLIGHT_DURATION:
		var t := clampf(elapsed / FLIGHT_DURATION, 0.0, 1.0)
		position = _landing_position + _entry_offset * (1.0 - t)
		position.y += sin(t * PI) * 0.9
		rotation = Vector3(_face_angle + TAU * 3.0 * (1.0 - t), 0.0, sin(t * TAU) * 0.22)
	else:
		var t := clampf((elapsed - FLIGHT_DURATION) / SETTLE_DURATION, 0.0, 1.0)
		var wobble := sin(t * TAU * 1.5) * (1.0 - t) * 0.16
		position = _landing_position + Vector3.UP * absf(wobble) * 0.18
		rotation = Vector3(_face_angle + wobble, 0.0, wobble * 0.5)


func dissolve() -> void:
	if _dissolving:
		return
	_dissolving = true


func _prepare_materials() -> void:
	# Replace only this instance's surfaces and retain the authored colors.
	for node: Node in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = DISSOLVE_SHADER
			material.set_shader_parameter("unshaded_mode", false)
			material.set_shader_parameter("emission_intensity", 0.0)
			if source != null:
				material.set_shader_parameter("base_color", source.albedo_color)
				material.set_shader_parameter("albedo_texture", source.albedo_texture)
				material.set_shader_parameter("roughness_amount", source.roughness)
				material.set_shader_parameter("metallic_amount", source.metallic)
				material.set_shader_parameter("specular_amount", source.metallic_specular)
			if mesh.name == &"coin":
				material.set_shader_parameter("base_color", Color(0.12, 0.1296, 0.144, 1.0))
				material.set_shader_parameter("metallic_amount", 1.0)
				material.set_shader_parameter("roughness_amount", 0.55)
			else:
				# Painted numbers react to the room lighting without emitting light.
				material.set_shader_parameter("metallic_amount", 0.0)
				material.set_shader_parameter("roughness_amount", 0.75)
				material.set_shader_parameter("specular_amount", 0.15)
			# Sweep across the face, not through the thin coin's thickness.
			var mesh_to_coin := global_transform.affine_inverse() * mesh.global_transform
			var face_space := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
			material.set_shader_parameter("use_local_space", true)
			material.set_shader_parameter("local_space_transform", face_space * mesh_to_coin)
			material.set_shader_parameter("dissolve_min_y", -0.36)
			material.set_shader_parameter("dissolve_height", 0.72)
			material.set_shader_parameter("noise_scale", 18.0)
			mesh.set_surface_override_material(surface, material)
			_materials.append(material)


func set_dissolve_progress(value: float) -> void:
	for material in _materials:
		material.set_shader_parameter("dissolve_progress", clampf(value, 0.0, 1.0))
