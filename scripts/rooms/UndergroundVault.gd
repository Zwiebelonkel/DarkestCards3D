extends Node3D
## Initial secret hall: the existing shared camera turns here and can return upstairs.

signal exit_requested
const OUTLINE := preload("res://assets/shader/inventory_outline.gdshader")
const EXIT_LAYER := 1 << 24

@export var room_environment: Environment
var camera: Camera3D
var context_available: Callable
var interaction_enabled := false
var _hovered := false
var _outline: ShaderMaterial

@onready var exit_area: Area3D = $ExitArea


func _ready() -> void:
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_color", Color(1, 0.85, 0, 1))
	_outline.set_shader_parameter("world_space_size", true)
	_outline.set_shader_parameter("outline_size", 0.045)
	exit_area.input_event.connect(_on_exit_input)
	set_interaction_enabled(false)


func inherit_fog(source: Environment) -> void:
	if source == null or room_environment == null:
		return
	# Keep the current atmosphere when changing the hall's lighting. Work on
	# an instance copy so neither the shared hall asset nor the source changes.
	var environment := room_environment.duplicate() as Environment
	for property in source.get_property_list():
		var property_name := String(property.name)
		if property_name.begins_with("fog_") or property_name.begins_with("volumetric_fog_"):
			environment.set(property.name, source.get(property.name))
	room_environment = environment


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not is_node_ready():
		return
	exit_area.input_ray_pickable = enabled
	exit_area.collision_layer = EXIT_LAYER if enabled else 0
	exit_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled:
		_set_hovered(false)


func _can_interact() -> bool:
	return (interaction_enabled and not get_tree().paused and is_visible_in_tree()
		and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call())))


func _process(_delta: float) -> void:
	var hit := false
	if _can_interact():
		var pointer := get_viewport().get_mouse_position()
		if get_viewport().get_visible_rect().has_point(pointer):
			var origin := camera.project_ray_origin(pointer)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, EXIT_LAYER)
			query.collide_with_areas = true
			query.collide_with_bodies = false
			hit = get_world_3d().direct_space_state.intersect_ray(query).get("collider") == exit_area
	_set_hovered(hit)


func _set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	for node in get_children():
		var mesh := node as MeshInstance3D
		if mesh != null and (str(mesh.name).begins_with("PortalJamb") or mesh.name == "PortalLintel"):
			mesh.material_overlay = _outline if value else null


func _on_exit_input(pick_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if pick_camera != camera or not _can_interact():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		exit_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_set_hovered(false)
