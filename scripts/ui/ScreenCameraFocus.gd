extends Node
class_name ScreenCameraFocus

@export var camera: Camera3D
@export_range(1.0, 120.0, 0.5) var focus_fov := 49.0
@export_range(0.5, 10.0, 0.05) var focus_screen_distance := 2.9
@export_range(0.0, 10.0, 0.05) var max_focus_travel := 3.5
@export_range(0.01, 2.0, 0.01) var focus_duration := 0.30
@export_range(0.01, 2.0, 0.01) var return_duration := 0.30
@export_range(0.0, 0.5, 0.01) var hover_exit_grace := 0.08
@export_range(0.0, 4.0, 0.1) var pointer_motion_epsilon := 0.5

var _screens: Dictionary = {}
var _screen_rooms: Dictionary = {}
var _active_room := -1
var _hovered_screen: Area3D = null
var _focused_screen: Area3D = null
var _active_side := -1
var _interaction_allowed := false
var _is_focused := false
var _camera_tween: Tween = null

var _base_position := Vector3.ZERO
var _base_fov := 75.0
var _base_basis := Basis.IDENTITY
var _owns_orientation := false
var _focus_position := Vector3.ZERO
var _initialized := false
var _pointer_miss_time := 0.0
var _pointer_moved_since_hit := false
var _last_pointer_position := Vector2.ZERO
var _has_pointer_position := false
var _hover_suspended := false


func _ready() -> void:
	if camera == null:
		push_error("ScreenCameraFocus: Main-Kamera fehlt.")
		set_process(false)
		return

	_base_position = camera.position
	_base_fov = camera.fov
	_base_basis = camera.basis
	_focus_position = _base_position
	_initialized = true


func _process(delta: float) -> void:
	if not _initialized or camera == null or not is_instance_valid(camera):
		return

	# Godot aktualisiert Area3D.mouse_entered nur bei einem neuen Mausereignis.
	# Nach einer Seitendrehung kann der Zeiger deshalb bereits auf dem neuen
	# Bildschirm stehen, ohne dass ein Signal ausgelöst wird. Die registrierten
	# Screen-Flächen werden zusätzlich direkt unter dem aktuellen Kamerastrahl
	# geprüft, damit auch eine vollkommen stillstehende Maus erkannt wird.
	_update_pointer_hover(delta)


func register_screen(screen_area: Area3D, side_index: int, room_index: int = -1) -> void:
	if screen_area == null:
		return

	_screens[screen_area] = side_index
	_screen_rooms[screen_area] = room_index

	var entered_callback := Callable(self, "_on_screen_mouse_entered").bind(screen_area)
	if not screen_area.mouse_entered.is_connected(entered_callback):
		screen_area.mouse_entered.connect(entered_callback)

	var exited_callback := Callable(self, "_on_screen_mouse_exited").bind(screen_area)
	if not screen_area.mouse_exited.is_connected(exited_callback):
		screen_area.mouse_exited.connect(exited_callback)


func set_context(active_side: int, interaction_allowed: bool, room_index: int = -1) -> void:
	var context_changed := _active_side != active_side or _interaction_allowed != interaction_allowed or (room_index >= 0 and _active_room != room_index)
	if room_index >= 0:
		_active_room = room_index
	_active_side = active_side
	_interaction_allowed = interaction_allowed

	if not interaction_allowed:
		_hovered_screen = null
		_reset_pointer_tracking()

	if context_changed:
		_refresh_focus_target()


func set_hover_suspended(suspended: bool) -> void:
	# Keep the current framing while a camera-relative card detail covers the
	# wall. Room, pause and turn context changes still release the camera.
	_hover_suspended = suspended


func restore_immediately() -> void:
	if not _initialized or camera == null or not is_instance_valid(camera):
		return

	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null

	_hovered_screen = null
	_focused_screen = null
	_is_focused = false
	_reset_pointer_tracking()
	camera.position = _base_position
	camera.fov = _base_fov
	if _owns_orientation:
		camera.basis = _base_basis
		_owns_orientation = false


func release_camera() -> void:
	# Hand the current pose to a match/menu transition without leaving a
	# competing focus tween alive. The new camera owner handles restoration.
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null
	_hovered_screen = null
	_focused_screen = null
	_is_focused = false
	_owns_orientation = false
	_reset_pointer_tracking()


func is_focused() -> bool:
	return _is_focused


func suspend_for_cinematic() -> Dictionary:
	var resume := {"screen": _focused_screen, "returning": not _is_focused and _camera_tween != null and _camera_tween.is_running()}
	set_context(_active_side, false)
	release_camera()
	return resume


func resume_after_cinematic(resume: Dictionary) -> void:
	var screen := resume.get("screen") as Area3D
	if is_instance_valid(screen) and _interaction_allowed and _is_screen_available_for_active_side(screen):
		focus_screen(screen)
	elif resume.get("returning", false):
		_tween_camera(false)


func _on_screen_mouse_entered(screen_area: Area3D) -> void:
	if not _interaction_allowed or _hover_suspended:
		return
	if not _is_screen_available_for_active_side(screen_area):
		return
	if _hovered_screen != null and _hovered_screen != screen_area and _has_pointer_position:
		if camera.get_viewport().get_mouse_position().distance_to(_last_pointer_position) <= pointer_motion_epsilon:
			return
	focus_screen(screen_area)


func focus_screen(screen_area: Area3D) -> void:
	if not _interaction_allowed or not _is_screen_available_for_active_side(screen_area):
		return

	_hovered_screen = screen_area
	_focus_position = _calculate_focus_position(screen_area)
	_pointer_miss_time = 0.0
	_pointer_moved_since_hit = false
	_refresh_focus_target()


func _on_screen_mouse_exited(screen_area: Area3D) -> void:
	if _hovered_screen != screen_area:
		return

	# Nicht unmittelbar zurückfahren: Der Kameratween selbst kann Godots
	# Mouse-Exit auslösen, obwohl die Maus nicht bewegt wurde. Das Polling
	# entscheidet mit einer kleinen Hysterese, ob der Zeiger wirklich fort ist.
	_pointer_miss_time = 0.0


func _update_pointer_hover(delta: float) -> void:
	if not _interaction_allowed:
		return

	var viewport := camera.get_viewport()
	if viewport == null:
		return
	_update_pointer_hover_at(viewport.get_mouse_position(), delta)


func _update_pointer_hover_at(pointer_position: Vector2, delta: float) -> void:
	if _hover_suspended:
		return
	var pointer_moved := false
	if _has_pointer_position:
		pointer_moved = pointer_position.distance_to(_last_pointer_position) > pointer_motion_epsilon
	else:
		_has_pointer_position = true
		_last_pointer_position = pointer_position

	var pointed_screen := _find_screen_under_pointer(pointer_position)
	if pointed_screen != null:
		# Moving between camera targets may bring another prop under a
		# still pointer. Only an actual pointer move should switch that target.
		if _hovered_screen != null and _hovered_screen != pointed_screen and not pointer_moved:
			return
		_last_pointer_position = pointer_position
		_pointer_miss_time = 0.0
		_pointer_moved_since_hit = false
		if _hovered_screen != pointed_screen:
			_hovered_screen = pointed_screen
			_focus_position = _calculate_focus_position(pointed_screen)
			_refresh_focus_target()
		return

	if _hovered_screen == null:
		_last_pointer_position = pointer_position
		_pointer_miss_time = 0.0
		_pointer_moved_since_hit = false
		return

	if pointer_moved:
		_pointer_moved_since_hit = true

	# Eine reine Kamera-/FOV-Bewegung darf den Hover nicht aufheben. Sonst
	# pendelt die Kamera an den Bildschirmrändern zwischen Fokus und Basis.
	if not _pointer_moved_since_hit:
		return

	_pointer_miss_time += delta
	if _pointer_miss_time < hover_exit_grace:
		return

	_hovered_screen = null
	_pointer_miss_time = 0.0
	_pointer_moved_since_hit = false
	_refresh_focus_target()


func _find_screen_under_pointer(pointer_position: Vector2) -> Area3D:
	var viewport_rect := camera.get_viewport().get_visible_rect()
	if not viewport_rect.has_point(pointer_position):
		return null

	var ray_origin := camera.project_ray_origin(pointer_position)
	var ray_end := ray_origin + camera.project_ray_normal(pointer_position) * camera.far

	for screen_variant in _screens.keys():
		var screen_area := screen_variant as Area3D
		if not _is_screen_available_for_active_side(screen_area):
			continue
		if _ray_intersects_screen_area(screen_area, ray_origin, ray_end):
			return screen_area

	return null


func _is_screen_available_for_active_side(screen_area: Area3D) -> bool:
	if screen_area == null or not is_instance_valid(screen_area):
		return false
	if not _screens.has(screen_area):
		return false
	if int(_screens[screen_area]) != _active_side:
		return false
	var room_index := int(_screen_rooms.get(screen_area, -1))
	if room_index >= 0 and room_index != _active_room:
		return false
	if not screen_area.input_ray_pickable:
		return false
	return screen_area.is_visible_in_tree()


func _ray_intersects_screen_area(screen_area: Area3D, ray_origin: Vector3, ray_end: Vector3) -> bool:
	for child in screen_area.get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or collision_shape.disabled:
			continue

		var box_shape := collision_shape.shape as BoxShape3D
		if box_shape == null:
			continue

		var local_origin := collision_shape.to_local(ray_origin)
		var local_end := collision_shape.to_local(ray_end)
		var half_size := box_shape.size * 0.5
		var bounds := AABB(-half_size, box_shape.size)
		if bounds.intersects_segment(local_origin, local_end) != null:
			return true

	return false


func _reset_pointer_tracking() -> void:
	_pointer_miss_time = 0.0
	_pointer_moved_since_hit = false
	_has_pointer_position = false


func _refresh_focus_target() -> void:
	if not _initialized:
		return

	var should_focus := _can_focus_hovered_screen()
	var next_screen: Area3D = _hovered_screen if should_focus else null
	if should_focus == _is_focused and next_screen == _focused_screen:
		return

	_is_focused = should_focus
	_focused_screen = next_screen
	_tween_camera(should_focus)


func _can_focus_hovered_screen() -> bool:
	if not _interaction_allowed or _hovered_screen == null:
		return false
	return _is_screen_available_for_active_side(_hovered_screen)


func _calculate_focus_position(screen_area: Area3D) -> Vector3:
	var camera_parent := camera.get_parent() as Node3D
	if camera_parent == null or screen_area == null:
		return _base_position
	var marker := screen_area.get_meta("focus_camera_marker") as Node3D if screen_area.has_meta("focus_camera_marker") else null
	if is_instance_valid(marker):
		return camera_parent.to_local(marker.global_position)

	# Work in the camera parent's coordinate space so the target remains
	# compatible with the existing side rotation and mouse-tilt hierarchy.
	var screen_position := camera_parent.to_local(screen_area.global_position)
	var forward := -camera.transform.basis.z.normalized()
	var to_screen := screen_position - _base_position
	var current_distance := to_screen.dot(forward)
	# Wide physical stations need room for the whole work surface, while the
	# shop screens keep their existing close reading distance.
	var target_distance := maxf(float(screen_area.get_meta("focus_distance", focus_screen_distance)), 0.5)
	if current_distance <= target_distance:
		return _base_position

	# Move onto the screen's center axis. Both machines then reach the same
	# readable distance and remain fully framed despite their different room
	# positions. Main only enables this after its initial camera tween settles.
	var travel := current_distance - target_distance
	if max_focus_travel > 0.0:
		travel = minf(travel, max_focus_travel)
	var centering_offset := to_screen - forward * current_distance
	var desired_offset := forward * travel + centering_offset

	return _base_position + desired_offset


func _tween_camera(focus: bool) -> void:
	if camera == null or not is_instance_valid(camera):
		return

	if _camera_tween != null:
		_camera_tween.kill()

	var target_position := _focus_position if focus else _base_position
	var target_fov := minf(focus_fov, _base_fov) if focus else _base_fov
	if focus and is_instance_valid(_focused_screen):
		target_fov = minf(float(_focused_screen.get_meta("focus_fov", focus_fov)), _base_fov)
	var duration := focus_duration if focus else return_duration

	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.set_ease(Tween.EASE_OUT if focus else Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "position", target_position, duration)
	_camera_tween.tween_property(camera, "fov", target_fov, duration)
	var marker := _focused_screen.get_meta("focus_camera_marker") as Node3D if focus and is_instance_valid(_focused_screen) and _focused_screen.has_meta("focus_camera_marker") else null
	if is_instance_valid(marker):
		var target_basis := (camera.get_parent() as Node3D).global_basis.inverse() * marker.global_basis
		_camera_tween.tween_property(camera, "quaternion", target_basis.orthonormalized().get_rotation_quaternion(), duration)
		_owns_orientation = true
	elif _owns_orientation:
		_camera_tween.tween_property(camera, "quaternion", _base_basis.get_rotation_quaternion(), duration)
	_camera_tween.finished.connect(func():
		_camera_tween = null
		if not focus:
			_owns_orientation = false
	)


func _exit_tree() -> void:
	restore_immediately()
