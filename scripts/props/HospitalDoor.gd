extends Node3D
class_name HospitalDoor
## Floor-centered doorway. The imported frame stays fixed while its leaf turns.

signal activated(door: HospitalDoor)

const OPEN_SOUND := preload("res://assets/sounds/SFX/doorOpen.mp3")
const FRAME_SIZE := Vector3(1.9384625, 3.2884156, 0.2481034)
const OPENING_SIZE := Vector2(1.6574795, 3.1579228)
const LEAF_LEFT := -0.7787599564
const LEAF_RIGHT := 0.8787195086
const LEAF_TOP := 2.501715
const LEAF_FRONT := -0.155999
const FRAME_FRONT := -1.14835465
const LEAF_BACK := 0.85164529

@export_range(-120.0, 120.0, 1.0) var hover_open_degrees := -25.0
@export_range(-160.0, 160.0, 1.0) var travel_open_degrees := -100.0
@export_range(0.05, 2.0, 0.01) var hover_duration := 0.32
@export_range(0.05, 2.0, 0.01) var travel_duration := 0.45
@export var interaction_enabled := true
@export var locked := false
## Empty preserves the existing manually controlled slot-room door.
@export var area_id := ""

var _hovered := false
var _travel_open := false
var _return_passage_open := false
var _target_angle := 0.0
var _hinge_tween: Tween
var _open_audio: AudioStreamPlayer3D

@onready var hinge: Node3D = $Hinge
@onready var doorway_area: Area3D = $DoorwayArea
@onready var _doorway_shape: CollisionShape3D = $DoorwayArea/CollisionShape3D


func _ready() -> void:
	_split_imported_door()
	_open_audio = AudioStreamPlayer3D.new()
	_open_audio.name = "DoorOpenSound"
	_open_audio.stream = OPEN_SOUND
	_open_audio.bus = &"SFX"
	_open_audio.volume_db = -6.0
	_open_audio.unit_size = 4.0
	_open_audio.max_distance = 20.0
	_open_audio.attenuation_filter_cutoff_hz = 20500.0
	_open_audio.attenuation_filter_db = 0.0
	_open_audio.position = Vector3(0, 1.5, 0)
	add_child(_open_audio)
	doorway_area.mouse_entered.connect(_on_mouse_entered)
	doorway_area.mouse_exited.connect(_on_mouse_exited)
	doorway_area.input_event.connect(_on_input_event)
	visibility_changed.connect(_sync_pickability)
	if not area_id.is_empty():
		CollectionManager.collection_changed.connect(refresh_area_access)
		refresh_area_access()
	_sync_pickability()
	_update_pose()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not enabled:
		_hovered = false
	if is_node_ready():
		_sync_pickability()
		_update_pose()


func refresh_area_access(_card_ids: Array[String] = []) -> void:
	if not area_id.is_empty():
		set_locked(not CollectionManager.has_area_access(area_id))


func set_travel_open(open: bool) -> void:
	_travel_open = open
	if is_node_ready():
		_update_pose()


func set_return_passage_open(open: bool) -> void:
	# Main may open a locked entrance from inside during a return flight.
	# This changes the leaf only; access checks and picking stay locked.
	_return_passage_open = open
	if is_node_ready():
		_update_pose()


func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	if locked:
		_hovered = false
		_travel_open = false
	if is_node_ready():
		_sync_pickability()
		_update_pose()


func _sync_pickability() -> void:
	var enabled := interaction_enabled and not locked and is_visible_in_tree()
	doorway_area.input_ray_pickable = enabled
	doorway_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled:
		_hovered = false
		_update_pose()


func _process(_delta: float) -> void:
	# Also detect a stationary pointer after an A/D turn or camera transition.
	# The fixed doorway box never follows the swinging leaf.
	if not interaction_enabled or not doorway_area.input_ray_pickable or not is_visible_in_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var pointer := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(pointer)
	var end := origin + camera.project_ray_normal(pointer) * camera.far
	var box := _doorway_shape.shape as BoxShape3D
	var hit := get_viewport().get_visible_rect().has_point(pointer) and AABB(-box.size * 0.5, box.size).intersects_segment(_doorway_shape.to_local(origin), _doorway_shape.to_local(end)) != null
	_set_hovered(hit)


func _on_mouse_entered() -> void:
	if interaction_enabled and not locked and doorway_area.input_ray_pickable and is_visible_in_tree() and not get_tree().paused:
		_set_hovered(true)


func _on_mouse_exited() -> void:
	_set_hovered(false)


func _set_hovered(value: bool) -> void:
	# Physics signals and stationary-pointer polling share one rising edge.
	if _hovered == value:
		return
	_hovered = value
	if _hovered:
		_open_audio.play()
	_update_pose()


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	refresh_area_access()
	if locked or not interaction_enabled or not doorway_area.input_ray_pickable or not is_visible_in_tree() or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not area_id.is_empty() and not CollectionManager.unlock_area(area_id):
			return
		get_viewport().set_input_as_handled()
		activated.emit(self)


func _update_pose() -> void:
	var degrees := travel_open_degrees if _travel_open or _return_passage_open else (hover_open_degrees if _hovered and interaction_enabled else 0.0)
	if locked and not _return_passage_open:
		degrees = 0.0
	var angle := deg_to_rad(degrees)
	if is_equal_approx(angle, _target_angle):
		return
	_target_angle = angle
	if _hinge_tween != null:
		_hinge_tween.kill()
	_hinge_tween = create_tween()
	_hinge_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hinge_tween.tween_property(hinge, "rotation:y", angle, travel_duration if _travel_open or _return_passage_open else hover_duration)


func _split_imported_door() -> void:
	var source := $Model/hospitalDoor/Door as MeshInstance3D
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var frame_surface := SurfaceTool.new()
	var leaf_surface := SurfaceTool.new()
	for surface in [frame_surface, leaf_surface]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(source.get_active_material(0))
	for triangle in range(0, indices.size(), 3):
		var in_opening := true
		var on_leaf := true
		for corner in range(3):
			var vertex := vertices[indices[triangle + corner]]
			in_opening = in_opening and vertex.x >= LEAF_LEFT - 0.0001 and vertex.x <= LEAF_RIGHT + 0.0001 and vertex.y <= LEAF_TOP + 0.0001
			on_leaf = on_leaf and vertex.z >= LEAF_FRONT - 0.0001
		var target := leaf_surface if in_opening and on_leaf else frame_surface
		for corner in range(3):
			var index := indices[triangle + corner]
			target.set_normal(normals[index])
			target.set_uv(uvs[index])
			target.add_vertex(vertices[index])
		if in_opening and not on_leaf:
			# The source shares its recessed frame sides with the closed leaf.
			# Keep the recess fixed and add matching top/side faces to the leaf
			# so its thin edges remain solid when viewed while open.
			for corner in range(3):
				var index := indices[triangle + corner]
				var vertex := vertices[index]
				vertex.z = remap(vertex.z, FRAME_FRONT, LEAF_FRONT, LEAF_BACK, LEAF_FRONT)
				leaf_surface.set_normal(normals[index] * Vector3(-1, -1, 1))
				leaf_surface.set_uv(uvs[index])
				leaf_surface.add_vertex(vertex)
	var model_transform := global_transform.affine_inverse() * source.global_transform
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = frame_surface.commit()
	frame.transform = model_transform
	add_child(frame)
	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	leaf.mesh = leaf_surface.commit()
	leaf.transform = hinge.transform.affine_inverse() * model_transform
	hinge.add_child(leaf)
	source.hide()


func _exit_tree() -> void:
	if _hinge_tween != null:
		_hinge_tween.kill()
