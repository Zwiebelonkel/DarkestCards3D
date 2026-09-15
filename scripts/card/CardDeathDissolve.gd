extends RefCounted

## Private, per-card materials driven only by the table's existing death tween.
const DISSOLVE_SHADER := preload("res://assets/shader/dissolve.gdshader")

var _materials: Array[ShaderMaterial] = []
var _progress: float = 0.0
var _card_inverse: Transform3D
var _bounds: AABB


func begin(card: Node3D, body: MeshInstance3D, artwork: MeshInstance3D, icons: Array[Sprite3D]) -> void:
	_card_inverse = card.global_transform.affine_inverse()
	_bounds = AABB(Vector3(-0.4, -0.6, 0.0), Vector3(0.8, 1.2, 0.01))
	if body != null and body.mesh != null:
		_bounds = (_card_inverse * body.global_transform) * body.get_aabb()
	_replace_mesh(body)
	_replace_mesh(artwork)
	for icon in icons:
		if icon == null or not icon.visible or icon.texture == null:
			continue
		var material := _new_material(icon)
		_set_texture(material, icon.texture, icon.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		material.set_shader_parameter("base_color", icon.modulate)
		material.set_shader_parameter("unshaded_mode", true)
		# Sprite3D already generates its current frame/region/flip UVs.
		icon.material_override = material
		icon.material_overlay = null
		_materials.append(material)


func set_progress(value: float) -> void:
	# A repeated start or an interrupted callback cannot revive discarded pixels.
	_progress = maxf(_progress, clampf(value, 0.0, 1.0))
	for material in _materials:
		material.set_shader_parameter("dissolve_progress", _progress)


func get_progress() -> float:
	return _progress


func _replace_mesh(mesh: MeshInstance3D) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var originals: Array[Material] = []
	for surface in range(mesh.mesh.get_surface_count()):
		originals.append(mesh.get_active_material(surface))
	mesh.material_override = null
	mesh.material_overlay = null
	for surface in range(originals.size()):
		var material := _new_material(mesh)
		var source := originals[surface] as BaseMaterial3D
		if source != null:
			material.set_shader_parameter("base_color", source.albedo_color)
			_set_texture(material, source.albedo_texture, source.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
			material.set_shader_parameter("texture_uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
			material.set_shader_parameter("texture_uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
			material.set_shader_parameter("roughness_amount", source.roughness)
			material.set_shader_parameter("metallic_amount", source.metallic)
			material.set_shader_parameter("specular_amount", source.metallic_specular)
			material.set_shader_parameter("unshaded_mode", source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		# No shared resource or next-pass chain is changed: shine/holo passes
		# are replaced together with this dying instance's base surface.
		mesh.set_surface_override_material(surface, material)
		_materials.append(material)


func _new_material(target: GeometryInstance3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("use_local_space", true)
	material.set_shader_parameter("local_space_planar", true)
	material.set_shader_parameter("local_space_transform", _card_inverse * target.global_transform)
	material.set_shader_parameter("dissolve_min_y", _bounds.position.y)
	material.set_shader_parameter("dissolve_height", maxf(_bounds.size.y, 0.01))
	material.set_shader_parameter("dissolve_progress", 0.0)
	return material


func _set_texture(material: ShaderMaterial, texture: Texture2D, nearest: bool) -> void:
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_texture_nearest", texture)
	material.set_shader_parameter("use_nearest_texture", nearest)
