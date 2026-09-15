extends RefCounted
class_name PackFoil

## Flexible, length-preserving peel of the imported top. Progress belongs to
## the interaction controller; this helper only adds spring response to lift.
const FOIL_SHADER := preload("res://assets/shader/pack_foil.gdshader")
const WIDTH_SEGMENTS := 96
const EPSILON := 0.000001

var _top: MeshInstance3D
var _source_mesh: Mesh
var _source_override: Material
var _source_surface_overrides: Array[Material] = []
var _mesh: ArrayMesh
var _materials: Array[ShaderMaterial] = []
var _bounds := AABB()
var _metric_scale := Vector3.ONE
var _center := Vector3.ZERO
var _width := 1.0
var _progress := 0.0
var _lift := 0.0
var _lift_velocity := 0.0
var _ripple := 0.0
var _phase := 0.0


func configure(top: MeshInstance3D) -> bool:
	_restore_source()
	if top == null or top.mesh == null:
		return false
	_top = top
	_source_mesh = top.mesh
	_source_override = top.material_override
	_source_surface_overrides.clear()
	for surface in range(_source_mesh.get_surface_count()):
		_source_surface_overrides.append(top.get_surface_override_material(surface))
	_bounds = _source_mesh.get_aabb()
	if _bounds.size.x <= EPSILON:
		return false
	_metric_scale = top.transform.basis.get_scale().abs().max(Vector3.ONE * 0.0001)
	_width = _bounds.size.x * _metric_scale.x
	_center = _bounds.get_center() * _metric_scale
	_mesh = ArrayMesh.new()
	_materials.clear()
	for surface in range(_source_mesh.get_surface_count()):
		if _source_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			_restore_source()
			return false
		var arrays := _subdivide_surface(_source_mesh.surface_get_arrays(surface))
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var original: Material = top.get_surface_override_material(surface)
		if original == null or original is ShaderMaterial:
			original = _source_mesh.surface_get_material(surface)
		var material := _make_material(original)
		_mesh.surface_set_material(surface, material)
		_materials.append(material)
		if _source_mesh is ArrayMesh:
			_mesh.surface_set_name(surface, (_source_mesh as ArrayMesh).surface_get_name(surface))
	# GPU bending extends far beyond the very thin original local Z bounds.
	var margin := Vector3.ONE * (_width * 1.15) / _metric_scale
	_mesh.custom_aabb = AABB(_bounds.position - margin, _bounds.size + margin * 2.0)
	top.mesh = _mesh
	top.material_override = null
	for surface in range(_mesh.get_surface_count()):
		top.set_surface_override_material(surface, null)
	reset()
	return true


func update_foil(progress: float, lift: float, velocity: float, delta: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	var target_lift := clampf(lift, 0.0, 1.0)
	var elapsed := clampf(delta, 0.0, 0.05)
	var steps := maxi(1, int(ceil(elapsed / 0.008)))
	var step := elapsed / steps
	for _index in range(steps):
		_lift_velocity += ((target_lift - _lift) * 210.0 - _lift_velocity * 24.0) * step
		_lift += _lift_velocity * step
	_lift = clampf(_lift, -0.04, 1.08)
	_ripple = lerpf(_ripple, minf(absf(velocity), 8.0) * 0.11, 1.0 - exp(-elapsed * 12.0))
	_phase += elapsed * (11.0 + minf(absf(velocity), 5.0) * 2.0)
	_sync_uniforms()


func settle(delta: float) -> void:
	update_foil(_progress, 0.0, 0.0, delta)


func reset() -> void:
	_progress = 0.0
	_lift = 0.0
	_lift_velocity = 0.0
	_ripple = 0.0
	_phase = 0.0
	_sync_uniforms()


func get_local_bounds() -> AABB:
	return _bounds


func get_deformed_bounds() -> AABB:
	var first := get_deformed_position(_bounds.position)
	var result := AABB(first, Vector3.ZERO)
	for sample_index in range(33):
		var x := _bounds.position.x + _bounds.size.x * float(sample_index) / 32.0
		for y in [_bounds.position.y, _bounds.end.y]:
			for z in [_bounds.position.z, _bounds.end.z]:
				result = result.expand(get_deformed_position(Vector3(x, y, z)))
	var margin := Vector3.ONE * (_width * 0.003) / _metric_scale
	return AABB(result.position - margin, result.size + margin * 2.0)


func get_grip_local_position() -> Vector3:
	return get_deformed_position(Vector3(_bounds.position.x, _bounds.get_center().y, _bounds.get_center().z))


func get_tear_local_position() -> Vector3:
	return Vector3(_bounds.position.x + _bounds.size.x * _progress, _bounds.get_center().y, _bounds.get_center().z)


func get_deformed_position(original_local: Vector3) -> Vector3:
	var point := original_local * _metric_scale
	var boundary := (_bounds.position.x + _bounds.size.x * _progress) * _metric_scale.x
	var distance := boundary - point.x
	if _progress <= 0.0 or distance <= 0.0:
		return original_local
	var arc := _arc_at(distance)
	var direction := Vector3(0.0, 0.52 + _lift * 0.33, 0.78 - _lift * 0.2).normalized()
	var axis := Vector3.RIGHT.cross(direction)
	var offset := Vector3(0, point.y - _center.y, point.z - _center.z)
	var rotated := offset.rotated(axis, -arc.z)
	var displaced := Vector3(boundary + arc.x, _center.y, _center.z) + direction * arc.y + rotated
	var weight := smoothstep(0.0, maxf(0.0001, minf(_width * 0.025, _width * _progress * 0.25)), distance)
	var wave := sin(point.x * 57.0 + point.y * 34.0 + _phase) * 0.6 + sin(point.x * 103.0 - point.y * 49.0 - _phase * 0.7) * 0.4
	displaced += axis * wave * _width * (0.00022 + _ripple * 0.0005) * weight * clampf(_progress * 8.0, 0, 1)
	return displaced / _metric_scale


func _arc_at(distance: float) -> Vector3:
	var free_length := _width * _progress
	var bend_length := minf(free_length, _width * 0.14 + free_length * 0.18)
	var angle := minf(0.7 + clampf(_lift, 0.0, 1.05) * 2.0, free_length / maxf(0.001, _bounds.size.y * _metric_scale.y * 0.68))
	var curve := angle / maxf(bend_length, 0.0001)
	var bent_distance := minf(distance, bend_length)
	var theta := bent_distance * curve
	var x := -sin(theta) / maxf(curve, 0.0001)
	var up := (1.0 - cos(theta)) / maxf(curve, 0.0001)
	var curl_start := maxf(bend_length, free_length * 0.78)
	var straight := maxf(0.0, minf(distance, curl_start) - bend_length)
	x -= cos(angle) * straight
	up += sin(angle) * straight
	if distance > curl_start:
		var curl_angle := 0.2 + clampf(_lift, 0.0, 1.0) * 0.32 + _ripple * 0.08
		var curl_curve := curl_angle / maxf(free_length - curl_start, 0.0001)
		theta = angle + (distance - curl_start) * curl_curve
		x -= (sin(theta) - sin(angle)) / curl_curve
		up += (cos(angle) - cos(theta)) / curl_curve
	elif distance > bend_length:
		theta = angle
	return Vector3(x, up, theta)


func _sync_uniforms() -> void:
	for material in _materials:
		material.set_shader_parameter("peel_progress", _progress)
		material.set_shader_parameter("peel_lift", _lift)
		material.set_shader_parameter("ripple_energy", _ripple)
		material.set_shader_parameter("ripple_phase", _phase)


func _make_material(original: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOIL_SHADER
	material.set_shader_parameter("metric_scale", _metric_scale)
	material.set_shader_parameter("source_min_x", _bounds.position.x)
	material.set_shader_parameter("source_width", _bounds.size.x)
	material.set_shader_parameter("cross_center", _center)
	material.set_shader_parameter("band_height", _bounds.size.y * _metric_scale.y)
	if original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("has_albedo_texture", source.albedo_texture != null)
		material.set_shader_parameter("albedo_tint", source.albedo_color)
		material.set_shader_parameter("metallic_value", source.metallic)
		material.set_shader_parameter("roughness_value", source.roughness)
	return material


func _restore_source() -> void:
	if is_instance_valid(_top) and _top.mesh == _mesh and _source_mesh != null:
		_top.mesh = _source_mesh
		_top.material_override = _source_override
		for surface in range(_source_surface_overrides.size()):
			_top.set_surface_override_material(surface, _source_surface_overrides[surface])
	_top = null
	_source_mesh = null
	_source_override = null
	_source_surface_overrides.clear()
	_mesh = null
	_materials.clear()


func _subdivide_surface(source: Array) -> Array:
	var positions: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var vertices: Array[Dictionary] = []
	for index in range(positions.size()):
		vertices.append({"p": positions[index], "n": normals[index] if normals.size() > index else Vector3.FORWARD, "uv": uvs[index] if uvs.size() > index else Vector2.ZERO})
	var out_positions := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var element_count := indices.size() if not indices.is_empty() else positions.size()
	var step := _bounds.size.x / WIDTH_SEGMENTS
	for triangle in range(0, element_count, 3):
		var polygon: Array[Dictionary] = []
		for corner in range(3):
			polygon.append(vertices[indices[triangle + corner] if not indices.is_empty() else triangle + corner])
		var low: float = minf(polygon[0].p.x, minf(polygon[1].p.x, polygon[2].p.x))
		var high: float = maxf(polygon[0].p.x, maxf(polygon[1].p.x, polygon[2].p.x))
		var first := maxi(1, int(floor((low - _bounds.position.x) / step)) + 1)
		var last := mini(WIDTH_SEGMENTS - 1, int(ceil((high - _bounds.position.x) / step)) - 1)
		for division in range(first, last + 1):
			var plane := _bounds.position.x + division * step
			var left := _clip_polygon(polygon, plane, true)
			_append_polygon(left, out_positions, out_normals, out_uvs)
			polygon = _clip_polygon(polygon, plane, false)
		_append_polygon(polygon, out_positions, out_normals, out_uvs)
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = out_positions
	result[Mesh.ARRAY_NORMAL] = out_normals
	result[Mesh.ARRAY_TEX_UV] = out_uvs
	return result


func _clip_polygon(polygon: Array[Dictionary], plane: float, left: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if polygon.is_empty():
		return result
	var previous: Dictionary = polygon.back()
	var previous_inside: bool = previous.p.x <= plane if left else previous.p.x >= plane
	for current in polygon:
		var inside: bool = current.p.x <= plane if left else current.p.x >= plane
		if inside != previous_inside:
			var t: float = clampf((plane - previous.p.x) / (current.p.x - previous.p.x), 0.0, 1.0)
			var point: Vector3 = previous.p.lerp(current.p, t)
			point.x = plane
			result.append({"p": point, "n": previous.n.lerp(current.n, t).normalized(), "uv": previous.uv.lerp(current.uv, t)})
		if inside:
			result.append(current)
		previous = current
		previous_inside = inside
	return result


func _append_polygon(polygon: Array[Dictionary], positions: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> void:
	for index in range(1, polygon.size() - 1):
		if (polygon[index].p - polygon[0].p).cross(polygon[index + 1].p - polygon[0].p).length_squared() <= 0.000000000001:
			continue
		for vertex in [polygon[0], polygon[index], polygon[index + 1]]:
			positions.append(vertex.p)
			normals.append(vertex.n)
			uvs.append(vertex.uv)
