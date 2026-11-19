extends Node3D
## Opens the authored grave row and reveals a real descending stair shaft.

signal enter_requested
signal opening_changed(active: bool)
const PICK_LAYER := 1 << 25
const STAIRS := preload("res://scenes/props/GraveSecretStairs.tscn")
const OUTLINE := preload("res://assets/shader/inventory_outline.gdshader")

@export var slide_duration := 2.8
@export var reward_hold_duration := 3.9
@export var slide_distance := 2.6
@export_range(0.0, 8.0, 0.1) var wobble_degrees := 2.8
var camera: Camera3D
var context_available: Callable
var graves: Array[Node3D] = []
var is_open := false
var is_opening := false
var interaction_enabled := false
var stairs: Node3D
var pick_area: Area3D
var floor_meshes: Array[MeshInstance3D] = []
var open_amount := 0.0
var _original_grave_positions: Array[Vector3] = []
var _original_grave_rotations: Array[Vector3] = []
var _grave_visuals: Array[Array] = []
var _original_transparencies: Dictionary = {}
var _grave_directions: Array[float] = []
var _outline: ShaderMaterial
var _hovered := false
var _slide: Tween


func _ready() -> void:
	stairs = STAIRS.instantiate()
	stairs.name = "SecretStairs"
	add_child(stairs)
	stairs.hide()
	pick_area = Area3D.new()
	pick_area.name = "StairPickArea"
	pick_area.collision_mask = 0
	pick_area.monitoring = false
	pick_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 1.4, 4.8)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	pick_area.add_child(collider)
	pick_area.position = Vector3(0, -1.1, -2.4)
	add_child(pick_area)
	pick_area.input_event.connect(_on_pick_input)
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_color", Color(1, 0.85, 0, 1))
	_outline.set_shader_parameter("world_space_size", true)
	_outline.set_shader_parameter("outline_size", 0.015)
	set_interaction_enabled(false)


func configure(puzzle: Node3D) -> void:
	graves.assign(puzzle.graves)
	# The two smaller local Z positions are the two screen-left graves from
	# the authored grave-row camera. Keep the existing geometry and inscriptions.
	var sorted := graves.duplicate()
	sorted.sort_custom(func(a: Node3D, b: Node3D): return a.position.z < b.position.z)
	for grave in graves:
		_original_grave_positions.append(grave.position)
		_original_grave_rotations.append(grave.rotation)
		var visuals: Array[GeometryInstance3D] = []
		_collect_visuals(grave, visuals)
		_grave_visuals.append(visuals)
		for visual in visuals:
			_original_transparencies[visual] = visual.transparency
		_grave_directions.append(-1.0 if sorted.find(grave) < 2 else 1.0)
	var room := get_parent() as Node3D
	var candidates: Array[Node] = [room.get_node("Earth")]
	candidates.append_array(room.get_node("Terrain").get_children())
	candidates.append_array(room.get_node("Paths").get_children())
	var hole := room.global_transform.affine_inverse() * global_transform * AABB(Vector3(-1.3, -0.6, -6.4), Vector3(2.6, 0.9, 6.4))
	for candidate in candidates:
		if not candidate is MeshInstance3D or candidate.mesh == null:
			continue
		var mesh := candidate as MeshInstance3D
		var bounds := room.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		if not bounds.intersects(hole):
			continue
		floor_meshes.append(mesh)
		mesh.set_instance_shader_parameter("grave_opening_origin", to_global(Vector3(0, 0, -3.2)))
		mesh.set_instance_shader_parameter("grave_opening_right", global_basis.x.normalized())
		mesh.set_instance_shader_parameter("grave_opening_forward", -global_basis.z.normalized())
		mesh.set_instance_shader_parameter("grave_opening_half_size", Vector2(1.30 * global_basis.x.length(), 3.20 * global_basis.z.length()))
		mesh.set_instance_shader_parameter("grave_opening_amount", 0.0)
	puzzle.puzzle_solved.connect(_on_puzzle_solved)
	CollectionManager.collection_changed.connect(_on_collection_changed)
	if CollectionManager.has_discovered_card(CollectionManager.GRAVE_REWARD_CARD_ID):
		_open_immediately()


func _on_puzzle_solved(_instance: Dictionary) -> void:
	if is_open or is_opening:
		return
	is_opening = true
	opening_changed.emit(true)
	# Keep the existing reward reveal readable, then let the player see the
	# whole row move with the camera still facing the newly revealed opening.
	await get_tree().create_timer(reward_hold_duration, false).timeout
	if not is_inside_tree():
		return
	if not CollectionManager.has_discovered_card(CollectionManager.GRAVE_REWARD_CARD_ID):
		is_opening = false
		opening_changed.emit(false)
		return
	stairs.show()
	_slide = create_tween()
	_slide.tween_method(_animate_graves, 0.0, 1.0, slide_duration)
	await _slide.finished
	_slide = null
	_finish_open()


func _open_immediately() -> void:
	stairs.show()
	_animate_graves(1.0)
	_finish_open()


func _collect_visuals(node: Node, visuals: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		visuals.append(node)
	for child in node.get_children():
		_collect_visuals(child, visuals)


func _animate_graves(progress: float) -> void:
	var travel := smoothstep(0.0, 1.0, progress)
	var shake := sin(PI * progress) if progress < 1.0 else 0.0
	var fade := smoothstep(0.60, 0.98, progress)
	for index in range(graves.size()):
		var wave := TAU * 6.5 * progress + float(index) * 1.7
		var tremor := Vector3(sin(wave * 1.7) * 0.025, absf(sin(wave)) * 0.018, 0.0) * shake
		graves[index].position = _original_grave_positions[index] + tremor + Vector3(0, 0, slide_distance * _grave_directions[index] * travel)
		graves[index].rotation = _original_grave_rotations[index] + Vector3(sin(wave) * 0.55, sin(wave * 0.73) * 0.25, cos(wave) * 0.95) * deg_to_rad(wobble_degrees) * shake
		# Finish fading before hiding the root: stone, soil and inscriptions
		# all disappear together instead of popping out at the final frame.
		for visual: GeometryInstance3D in _grave_visuals[index]:
			visual.transparency = lerpf(float(_original_transparencies[visual]), 1.0, fade)
	_set_open_amount(travel)


func _finish_open() -> void:
	is_open = true
	is_opening = false
	for grave in graves:
		grave.hide()
	opening_changed.emit(false)
	set_interaction_enabled(interaction_enabled)


func _on_collection_changed(_ids: Array[String]) -> void:
	_sync_discovery.call_deferred()


func _sync_discovery() -> void:
	if not is_open and not is_opening and CollectionManager.has_discovered_card(CollectionManager.GRAVE_REWARD_CARD_ID):
		_open_immediately()


func _set_open_amount(value: float) -> void:
	open_amount = value
	for mesh in floor_meshes:
		mesh.set_instance_shader_parameter("grave_opening_amount", value)


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not is_instance_valid(pick_area):
		return
	var available := enabled and is_open and not is_opening
	pick_area.input_ray_pickable = available
	pick_area.collision_layer = PICK_LAYER if available else 0
	pick_area.set_meta("keep_input_ray_pickable_disabled", not available)
	if not available:
		_set_hovered(false)


func _can_interact() -> bool:
	return (interaction_enabled and is_open and not is_opening and not get_tree().paused
		and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call())))


func _process(_delta: float) -> void:
	var hit := false
	if _can_interact():
		var pointer := get_viewport().get_mouse_position()
		if get_viewport().get_visible_rect().has_point(pointer):
			var origin := camera.project_ray_origin(pointer)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, PICK_LAYER)
			query.collide_with_areas = true
			query.collide_with_bodies = false
			hit = get_world_3d().direct_space_state.intersect_ray(query).get("collider") == pick_area
	_set_hovered(hit)


func _set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	if is_instance_valid(stairs):
		for node in stairs.get_children():
			if node is MeshInstance3D and str(node.name).begins_with("OpeningRim"):
				node.material_overlay = _outline if value else null


func _on_pick_input(pick_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if pick_camera != camera or not _can_interact() or not pick_area.input_ray_pickable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		enter_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_set_hovered(false)


func _exit_tree() -> void:
	for mesh in floor_meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter("grave_opening_amount", 0.0)
