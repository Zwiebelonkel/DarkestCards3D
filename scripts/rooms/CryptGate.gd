extends Node3D
## The fixed hit box stays in the doorway while the complete grille sways.

signal activated
signal return_requested

const BEACON_SCENE := preload("res://scenes/props/TravelBeacon.tscn")

@export_range(0.0, 10.0, 0.1) var hover_angle_degrees := 3.0
@export_range(0.05, 1.0, 0.01) var hover_duration := 0.24

var camera: Camera3D
var context_available: Callable
var return_available: Callable
var interaction_enabled := false
var gate_area: Area3D
var hinge: Node3D
var _shape: CollisionShape3D
var _hovered := false
var _hinge_tween: Tween
var return_beacon: Node3D
var _return_shape: CollisionShape3D
var _beacon_visual: Node3D
var _beacon_time := 0.0


func _ready() -> void:
	hinge = Node3D.new()
	hinge.name = "GateHinge"
	hinge.position = Vector3(-1.03, 1.62, -17.7)
	add_child(hinge)
	for child in get_parent().get_children():
		if str(child.name).begins_with("DoorBar_") or str(child.name).begins_with("DoorRail_"):
			var part := child as Node3D
			var original := part.transform
			part.reparent(hinge, false)
			part.transform = hinge.transform.affine_inverse() * original
	gate_area = Area3D.new()
	gate_area.name = "GateArea"
	gate_area.position = Vector3(0, 1.62, -17.7)
	gate_area.collision_layer = 0
	gate_area.collision_mask = 0
	gate_area.monitoring = false
	gate_area.monitorable = false
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.12, 2.52, 0.3)
	_shape.shape = box
	gate_area.add_child(_shape)
	add_child(gate_area)
	return_beacon = BEACON_SCENE.instantiate() as Node3D
	return_beacon.position = Vector3(0, 0.115, -6.0)
	add_child(return_beacon)
	_return_shape = return_beacon.get_node("HoverArea/CollisionShape3D") as CollisionShape3D
	_beacon_visual = return_beacon.get_node("Visual") as Node3D
	set_interaction_enabled(false)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_set_hovered(false)
	)


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if is_instance_valid(gate_area):
		gate_area.input_ray_pickable = enabled
		gate_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled:
		_set_hovered(false)


func _can_interact() -> bool:
	return (
		interaction_enabled and is_visible_in_tree() and not get_tree().paused
		and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call()))
	)


func _process(delta: float) -> void:
	_set_hovered(_can_interact() and _pointer_hits_gate(get_viewport().get_mouse_position()))
	refresh_return_beacon()
	if _beacon_visual.visible:
		_beacon_time += delta
		_beacon_visual.get_node("Glyph").position.y = 0.7 + sin(_beacon_time * 2.8) * 0.05


func _can_return() -> bool:
	return (
		is_visible_in_tree() and not get_tree().paused
		and is_instance_valid(camera) and camera.is_current()
		and return_available.is_valid() and bool(return_available.call())
	)


func refresh_return_beacon() -> void:
	_beacon_visual.visible = _can_return() and _pointer_hits_shape(get_viewport().get_mouse_position(), _return_shape)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _can_return() and _pointer_hits_shape(event.position, _return_shape):
		get_viewport().set_input_as_handled()
		return_requested.emit()
	elif _can_interact() and _pointer_hits_gate(event.position):
		get_viewport().set_input_as_handled()
		activated.emit()


func _pointer_hits_gate(pointer: Vector2) -> bool:
	return _pointer_hits_shape(pointer, _shape)


func _pointer_hits_shape(pointer: Vector2, collision: CollisionShape3D) -> bool:
	if not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var origin := camera.project_ray_origin(pointer)
	var end := origin + camera.project_ray_normal(pointer) * camera.far
	var box := collision.shape as BoxShape3D
	return AABB(-box.size * 0.5, box.size).intersects_segment(collision.to_local(origin), collision.to_local(end)) != null


func _set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	if _hinge_tween != null:
		_hinge_tween.kill()
	_hinge_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hinge_tween.tween_property(hinge, "rotation:y", deg_to_rad(hover_angle_degrees) if value else 0.0, hover_duration)


func get_approach_camera_pose() -> Transform3D:
	var eye := to_global(Vector3(0, 2.3, -14.7))
	var direction := gate_area.global_position - eye
	return Transform3D(Basis.looking_at(direction, Vector3.UP), eye)
