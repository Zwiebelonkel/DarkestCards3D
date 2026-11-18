extends Node3D
## Local first-person interaction for the two authored jackpot-room beds.

const OUTLINE_SHADER := preload("res://assets/shader/inventory_outline.gdshader")
const PICK_LAYER := 1 << 21
enum State { IDLE, FACING, WALKING, TURNING, SITTING, SEATED, RISING, RETURNING }

@export var face_duration := 0.24
@export var turn_duration := 0.55
@export var sit_duration := 0.42
@export var seated_eye_height := 1.95
@export_range(0.2, 1.0, 0.05) var return_duration_scale := 0.55

var beds: Array[Node3D] = []
var areas: Array[Area3D] = []
var bounds: Array[AABB] = []
var state := State.IDLE
var selected_bed := -1
var hovered_bed := -1
var _main: Node
var _camera: Camera3D
var _motion: Tween
var _outline: ShaderMaterial
var _mesh_groups: Array = []
var _original_overlays: Dictionary = {}
var _return_requested := false
var _return_pivot := Transform3D.IDENTITY
var _return_tilt := Transform3D.IDENTITY
var _return_camera := Transform3D.IDENTITY
var _return_eye := Transform3D.IDENTITY
var _return_fov := 58.0
var _camera_to_pivot := Transform3D.IDENTITY
var _lane := Vector3.ZERO
var _corner := Vector3.ZERO
var _approach := Transform3D.IDENTITY
var _seat := Transform3D.IDENTITY


func configure(main: Node, room: Node3D) -> void:
	_main = main
	_camera = main.main_camera
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE_SHADER
	_outline.set_shader_parameter("outline_color", Color(1.0, 0.85, 0.0, 1.0))
	_outline.set_shader_parameter("outline_size", 0.015)
	for bed_name: String in ["bed", "bed2"]:
		var bed := room.get_node_or_null(bed_name) as Node3D
		if bed != null:
			_add_bed(bed)


func _add_bed(bed: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	var area := Area3D.new()
	area.name = "BedSeatArea"
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	bed.add_child(area)
	var bed_bounds := AABB()
	var first := true
	for child in bed.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		meshes.append(mesh)
		_original_overlays[mesh] = mesh.material_overlay
		var local := bed.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds := local * mesh.get_aabb()
		bed_bounds = mesh_bounds if first else bed_bounds.merge(mesh_bounds)
		first = false
		# Tight mesh picking avoids a large invisible box across the bed rails.
		var shape := mesh.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = local
		area.add_child(collision)
	beds.append(bed)
	areas.append(area)
	bounds.append(bed_bounds)
	_mesh_groups.append(meshes)


func is_busy() -> bool:
	return state != State.IDLE


func can_start() -> bool:
	return not is_busy() and is_instance_valid(_camera) and _camera.is_current() and _main._active_room == 1 and _main._can_travel_between_rooms() and not _main.secret_wall_input.is_busy() and not _main.access_key_tray.is_expanded()


func _process(_delta: float) -> void:
	if is_busy() and (_main._active_room != 1 or not _camera.is_current()):
		cancel()
	var enabled := can_start()
	_update_pickability(enabled)
	_set_hovered(_bed_at(get_viewport().get_mouse_position()) if enabled else -1)


func _update_pickability(enabled: bool) -> void:
	for area in areas:
		area.input_ray_pickable = enabled
		area.collision_layer = PICK_LAYER if enabled else 0
		area.set_meta("keep_input_ray_pickable_disabled", not enabled)


func _bed_at(pointer: Vector2) -> int:
	if not get_viewport().get_visible_rect().has_point(pointer):
		return -1
	var origin := _camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(pointer) * _camera.far)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var area := hit.get("collider") as Area3D
	return areas.find(area) if area != null else -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_hovered(-1)
		for area in areas:
			area.input_ray_pickable = false
			area.collision_layer = 0


func _set_hovered(index: int) -> void:
	if index == hovered_bed:
		return
	for meshes: Array in _mesh_groups:
		for mesh: MeshInstance3D in meshes:
			mesh.material_overlay = _original_overlays[mesh]
	hovered_bed = index
	if index >= 0:
		for mesh: MeshInstance3D in _mesh_groups[index]:
			mesh.material_overlay = _outline


func _unhandled_input(event: InputEvent) -> void:
	if can_start() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _bed_at(event.position)
		if index >= 0:
			get_viewport().set_input_as_handled()
			sit_on_bed(index)


func handle_input(event: InputEvent) -> bool:
	if not is_busy():
		return false
	if event.is_action_pressed("ui_cancel"):
		_return_requested = true
		if state == State.SEATED:
			_begin_return()
	return event is InputEventKey or event is InputEventMouse or event is InputEventJoypadButton


func sit_on_bed(index: int) -> bool:
	if not can_start() or index < 0 or index >= beds.size():
		return false
	_return_pivot = _main.camera_pivot.global_transform
	_return_tilt = _main.camera_tilt.transform
	_main.screen_camera_focus.restore_immediately()
	_main._claim_shared_camera_for_hub_rotation(false)
	_return_camera = _camera.transform
	_return_fov = _camera.fov
	_return_eye = _camera.global_transform
	_main.camera_tilt.rotation = Vector3.ZERO
	_camera.transform = _main._hub_camera_base_transform
	_camera_to_pivot = (_main.camera_pivot.global_transform.affine_inverse() * _camera.global_transform).affine_inverse()
	_main.camera_pivot.global_transform = _return_eye * _camera_to_pivot
	selected_bed = index
	_return_requested = false
	state = State.FACING
	_set_hovered(-1)
	_update_pickability(false)
	_main._pending_direction = 0
	_main.pause_menu.set_cinematic_locked(true)
	_refresh_context()
	_build_seat_poses(index)
	var face := Transform3D(_look_toward_bed(_return_eye.origin), _return_eye.origin)
	_animate_to(face, face_duration, _walk_to_bed)
	return true


func _build_seat_poses(index: int) -> void:
	var bed := beds[index]
	var bed_bounds := bounds[index]
	var foot := bed_bounds.end.z
	var local_origin := bed.to_local(_return_eye.origin)
	# Choose the long side nearest the room center, avoiding the head/foot
	# boards. Reach it through the clear lane in front of both foot ends.
	var side := -1.0 if local_origin.x < bed_bounds.get_center().x else 1.0
	var edge := bed_bounds.position.x if side < 0.0 else bed_bounds.end.x
	var z := bed_bounds.get_center().z
	var approach_point := bed.to_global(Vector3(edge + side * 1.25, 0.0, z))
	approach_point.y = _return_eye.origin.y
	_lane = bed.to_global(Vector3(local_origin.x, 0.0, foot + 1.25))
	_lane.y = _return_eye.origin.y
	_corner = bed.to_global(Vector3(edge + side * 1.25, 0.0, foot + 1.25))
	_corner.y = _return_eye.origin.y
	var outward := bed.global_basis.x.normalized() * side
	outward.y = 0.0
	outward = outward.normalized()
	_approach = Transform3D(Basis.looking_at(-outward, Vector3.UP), approach_point)
	var seat_point := bed.to_global(Vector3(edge - side * 0.5, seated_eye_height, z))
	_seat = Transform3D(Basis.looking_at(outward, Vector3.UP), seat_point)
	if beds.size() == 2:
		var other := 1 - index
		var target := beds[other].to_global(bounds[other].get_center())
		_seat.basis = Basis.looking_at(target - seat_point, Vector3.UP)


func _look_toward_bed(origin: Vector3) -> Basis:
	var direction := beds[selected_bed].global_position - origin
	direction.y = 0.0
	return Basis.looking_at(direction.normalized(), Vector3.UP)


func _animate_to(target: Transform3D, duration: float, finished: Callable) -> void:
	var start := _camera.global_transform
	_motion = create_tween()
	_motion.tween_method(_apply_eye_pose.bind(start, target), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_callback(finished)


func _apply_eye_pose(weight: float, start: Transform3D, target: Transform3D) -> void:
	_main.camera_pivot.global_transform = start.interpolate_with(target, weight) * _camera_to_pivot


func _walk_route(poses: Array[Transform3D], finished: Callable, duration_scale: float = 1.0) -> void:
	var duration: float = maxf(_main.room_travel_duration * duration_scale, 0.05)
	var distance := 0.0
	for index in range(1, poses.size()):
		distance += poses[index - 1].origin.distance_to(poses[index].origin)
	_main._start_walking_sequence(duration)
	_motion = create_tween()
	_main._room_travel_tween = _motion
	for index in range(1, poses.size()):
		var length := poses[index - 1].origin.distance_to(poses[index].origin)
		var leg_duration := maxf(duration * length / maxf(distance, 0.001), 0.01)
		_motion.tween_method(_apply_walk_pose.bind(poses[index - 1] * _camera_to_pivot, poses[index] * _camera_to_pivot), 0.0, 1.0, leg_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_callback(_finish_walk.bind(finished))


func _apply_walk_pose(weight: float, start: Transform3D, target: Transform3D) -> void:
	if state == State.RETURNING:
		var pivot_to_camera := _camera_to_pivot.affine_inverse()
		var pose := (start * pivot_to_camera).interpolate_with(target * pivot_to_camera, weight) * _camera_to_pivot
		_main._apply_room_travel_pose(1.0, pose, pose)
		# A faster return uses a quieter lens motion, without changing room walks.
		_camera.transform = _main._walking_camera_base_transform.interpolate_with(_camera.transform, 0.35)
	else:
		_main._apply_room_travel_pose(weight, start, target)


func _finish_walk(finished: Callable) -> void:
	_main._stop_walking_sequence()
	_main._room_travel_tween = null
	finished.call()


func _walk_to_bed() -> void:
	state = State.WALKING
	var poses: Array[Transform3D] = [_camera.global_transform, Transform3D(_look_toward_bed(_lane), _lane), Transform3D(_look_toward_bed(_corner), _corner), _approach]
	_walk_route(poses, _turn_at_bed)


func _turn_at_bed() -> void:
	state = State.TURNING
	var turned := Basis(Vector3.UP, PI) * _approach.basis
	_animate_to(Transform3D(turned, _approach.origin), turn_duration, _sit_down)


func _sit_down() -> void:
	state = State.SITTING
	_animate_to(_seat, sit_duration, _seated)


func _seated() -> void:
	state = State.SEATED
	_motion = null
	if _return_requested:
		_begin_return()


func _begin_return() -> void:
	# Finish at the room's forge view, including the logical A/D turning grid.
	var forge_side: int = _main.fusion_workbench.view_side
	var target_y: float = _main._settle_origin_y + deg_to_rad(_main.rotation_step_degrees) * forge_side
	_return_pivot.basis = Basis.from_euler(Vector3(_main._base_x_rotation, target_y, 0.0))
	_return_tilt = Transform3D.IDENTITY
	_return_eye = _return_pivot * _return_tilt * _return_camera
	state = State.RISING
	var standing := _camera.global_transform
	# Rise and step off the mattress in one motion, keeping the seated heading.
	standing.origin = _approach.origin
	_animate_to(standing, sit_duration * 0.65, _walk_back)


func _walk_back() -> void:
	state = State.RETURNING
	# The aisle between the beds gives a direct clear return. One continuous
	# interpolation restores the original view instead of turning at corners.
	var poses: Array[Transform3D] = [_camera.global_transform, _return_eye]
	_walk_route(poses, _finish_return, return_duration_scale)


func _finish_return() -> void:
	_motion = null
	_restore_camera()
	_main._settle_step_index = roundi((_return_pivot.basis.get_euler().y - _main._settle_origin_y) / deg_to_rad(_main.rotation_step_degrees))
	_main._settle_target_y = _main._settle_origin_y + deg_to_rad(_main.rotation_step_degrees) * _main._settle_step_index
	_main._active_side = posmod(_main._settle_step_index, _main.SIDE_COUNT)
	_main._visual_pivot_rotation = _main.camera_pivot.rotation
	state = State.IDLE
	selected_bed = -1
	_return_requested = false
	_main.pause_menu.set_cinematic_locked(false)
	_refresh_context()
	_update_pickability(can_start())


func _restore_camera() -> void:
	_main.camera_pivot.global_transform = _return_pivot
	_main.camera_tilt.transform = _return_tilt
	_camera.transform = _return_camera
	_camera.fov = _return_fov


func _refresh_context() -> void:
	_main._update_room_door_interaction()
	_main._update_screen_camera_focus_context()
	_main._update_labels()
	_main.turn_arrows.refresh()


func cancel() -> void:
	if not is_busy():
		return
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if is_instance_valid(_camera):
		if _main._walking_steps_active:
			_main._stop_walking_sequence()
		_main._room_travel_tween = null
		_finish_return()


func _exit_tree() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_set_hovered(-1)
