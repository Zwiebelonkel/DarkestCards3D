extends Node3D
class_name BasementBoiler
## Turning a valve changes this boiler's wheel and gauge for the basement puzzle.

signal dragging_changed(dragging: bool)

const WHEEL_LAYER := 1 << 18
const MAX_PRESSURE := 6.0
const PRESSURE_PER_RADIAN := MAX_PRESSURE / (TAU * 2.0)
const WHEEL_RADIUS := 0.29
const PRESSURE_COUNTER := preload("res://scripts/rooms/BoilerPressureCounter.gd")

@export var view_side := 2

var camera: Camera3D
var context_available: Callable
var interaction_enabled := false
var pressure := 2.8
var focus_area: Area3D
var wheel_area: Area3D
var _dragging := false
var _last_drag_angle := 0.0
var _has_drag_angle := false
var _valve_angle := 0.0
var _wheel_parts: Array[Node3D] = []
var _wheel_bases: Array[Basis] = []

@onready var wheel: MeshInstance3D = $RedValveWheel
@onready var needle: MeshInstance3D = $PressureGauge/GaugeNeedle
@onready var digits: PRESSURE_COUNTER = $PressureGauge/PressureDigits


func _ready() -> void:
	for part_name: String in ["RedValveWheel", "WheelSpokeA", "WheelSpokeB"]:
		var part := get_node(part_name) as Node3D
		_wheel_parts.append(part)
		_wheel_bases.append(part.basis)
	focus_area = _create_area("FocusArea", Vector3(0.45, 1.25, 0), Vector3(1.85, 2.55, 2.0))
	focus_area.set_meta("focus_distance", 4.8)
	wheel_area = _create_area("WheelArea", wheel.position, Vector3(0.18, WHEEL_RADIUS * 2.0, WHEEL_RADIUS * 2.0))
	set_interaction_enabled(false)
	visibility_changed.connect(_on_visibility_changed)
	_update_gauge()


func _create_area(area_name: String, center: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	return area


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	for area: Area3D in [focus_area, wheel_area]:
		if is_instance_valid(area):
			area.input_ray_pickable = enabled
			area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if is_instance_valid(wheel_area):
		wheel_area.collision_layer = WHEEL_LAYER if enabled else 0
	if not enabled:
		_end_drag()


func is_dragging() -> bool:
	return _dragging


func _can_interact() -> bool:
	return (
		interaction_enabled and is_inside_tree() and is_visible_in_tree()
		and not get_tree().paused and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call()))
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact() or _dragging:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _pointer_hits_wheel(event.position):
			return
		_dragging = true
		_has_drag_angle = false
		_update_drag(event.position)
		dragging_changed.emit(true)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if not _can_interact():
		_end_drag()
		return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_drag(event.position)
		else:
			_end_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.is_action_pressed("ui_cancel"):
		_end_drag()
		get_viewport().set_input_as_handled()


func _pointer_hits_wheel(pointer: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var point := _wheel_plane_point(pointer)
	if not point.is_finite() or point.length() > WHEEL_RADIUS:
		return false
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, WHEEL_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == wheel_area


func _wheel_plane_point(pointer: Vector2) -> Vector2:
	var origin := to_local(camera.project_ray_origin(pointer))
	var direction := global_basis.inverse() * camera.project_ray_normal(pointer)
	if absf(direction.x) < 0.00001 or origin.x <= wheel.position.x:
		return Vector2.INF
	var distance := (wheel.position.x - origin.x) / direction.x
	if distance < 0.0:
		return Vector2.INF
	var point := origin + direction * distance - wheel.position
	return Vector2(point.y, point.z)


func _update_drag(pointer: Vector2) -> void:
	var point := _wheel_plane_point(pointer)
	if not point.is_finite() or point.length() < 0.04:
		_has_drag_angle = false
		return
	var angle := point.angle()
	if _has_drag_angle:
		var delta := wrapf(angle - _last_drag_angle, -PI, PI)
		var previous_pressure := pressure
		# Viewed from the front, +Y toward +Z travels counterclockwise.
		pressure = clampf(pressure - delta * PRESSURE_PER_RADIAN, 0.0, MAX_PRESSURE)
		_valve_angle -= (pressure - previous_pressure) / PRESSURE_PER_RADIAN
		_update_gauge()
	_last_drag_angle = angle
	_has_drag_angle = true


func _update_gauge() -> void:
	var wheel_rotation := Basis(Vector3.RIGHT, _valve_angle)
	for index in range(_wheel_parts.size()):
		_wheel_parts[index].basis = wheel_rotation * _wheel_bases[index]
	# The shared dial covers 270 degrees clockwise, from lower left to lower right.
	needle.rotation.z = deg_to_rad(135.0 - pressure * 45.0)
	digits.set_pressure(pressure)


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_has_drag_angle = false
	# Settle on exactly the number the player just saw, including when a
	# release arrives through pause, focus loss or a change of view.
	var displayed_pressure := ("%.1f" % pressure).to_float()
	_valve_angle -= (displayed_pressure - pressure) / PRESSURE_PER_RADIAN
	pressure = displayed_pressure
	_update_gauge()
	dragging_changed.emit(false)


func _process(_delta: float) -> void:
	if _dragging and not _can_interact():
		_end_drag()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_end_drag()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag()
