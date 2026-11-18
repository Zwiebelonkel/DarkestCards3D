extends Node3D
class_name BasementPumpControl
## Five independent levers; the weed hint unlocks the one-time key puzzle.

const LEVER_LAYER := 1 << 20
const LEVER_COUNT := 5
const SWITCH_ANGLE := PI * 0.31
const INTERFACE_SOUNDS := preload("res://scripts/ui/InterfaceSounds.gd")
const REWARD_REVEAL := preload("res://scripts/ui/SecretCardReveal.gd")

@export var view_side := 1
@export var lever_up: Array[bool] = [false, false, true, false, false]

var camera: Camera3D
var context_available: Callable
var interaction_enabled := false
var focus_area: Area3D
var lever_areas: Array[Area3D] = []
var _pivots: Array[Node3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _lever_tweens: Array[Tween] = []


func _ready() -> void:
	lever_up.resize(LEVER_COUNT)
	focus_area = _create_area("FocusArea", $ControlDoor.position, Vector3(2.65, 2.0, 0.5))
	var marker := Marker3D.new()
	marker.name = "FocusCamera"
	marker.position = $ControlDoor.position + Vector3(0, 0, 2.85)
	add_child(marker)
	focus_area.set_meta("focus_camera_marker", marker)
	focus_area.set_meta("focus_fov", 49.0)
	# A worn metal handle stays readable against the dark cabinet door.
	var handle_material := StandardMaterial3D.new()
	handle_material.albedo_color = Color(0.42, 0.45, 0.4)
	handle_material.metallic = 0.6
	handle_material.roughness = 0.4
	handle_material.emission_enabled = true
	handle_material.emission = Color(0.12, 0.13, 0.1)
	handle_material.emission_energy_multiplier = 0.6
	for index in range(LEVER_COUNT):
		var lever := get_node("ToggleLever%d" % index) as MeshInstance3D
		var base := get_node("ToggleBase%d" % index) as MeshInstance3D
		var lamp := get_node("StatusLamp%d" % index) as MeshInstance3D
		var pivot := Node3D.new()
		pivot.name = "LeverPivot%d" % index
		pivot.position = base.position + Vector3(0, 0, 0.05)
		add_child(pivot)
		lever.reparent(pivot, false)
		lever.position = Vector3(0, 0, 0.12)
		lever.rotation = Vector3(PI * 0.5, 0, 0)
		lever.material_override = handle_material
		_pivots.append(pivot)
		_lamps.append(lamp.get_active_material(0).duplicate() as StandardMaterial3D)
		lamp.material_override = _lamps[index]
		_lever_tweens.append(null)
		lever_areas.append(_create_area("LeverArea%d" % index, base.position + Vector3(0, 0, 0.15), Vector3(0.36, 0.68, 0.6)))
		_update_switch(index, false)
	set_interaction_enabled(false)


func _create_area(area_name: String, center: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	return area


func set_interaction_enabled(enabled: bool) -> void:
	var newly_enabled := enabled and not interaction_enabled
	interaction_enabled = enabled
	focus_area.input_ray_pickable = enabled
	focus_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	for area in lever_areas:
		area.input_ray_pickable = enabled
		area.collision_layer = LEVER_LAYER if enabled else 0
		area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if newly_enabled:
		_try_claim_reward()


func _can_interact() -> bool:
	return (
		interaction_enabled and is_inside_tree() and is_visible_in_tree()
		and not get_tree().paused and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call()))
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact() or not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not get_viewport().get_visible_rect().has_point(event.position):
		return
	var origin := camera.project_ray_origin(event.position)
	var direction := camera.project_ray_normal(event.position)
	# The cabinet is operated from its front, never through its back wall.
	if direction.dot(global_basis.z.normalized()) >= 0.0:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far, LEVER_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var collider: Object = get_world_3d().direct_space_state.intersect_ray(query).get("collider")
	var index := lever_areas.find(collider)
	if index < 0:
		return
	lever_up[index] = not lever_up[index]
	_update_switch(index, true)
	INTERFACE_SOUNDS.play_click(self)
	get_viewport().set_input_as_handled()
	_try_claim_reward()


func _try_claim_reward() -> void:
	if not _can_interact():
		return
	var instance := CollectionManager.claim_pump_puzzle_reward(lever_up)
	if not instance.is_empty():
		_show_reward.call_deferred(instance)


func _show_reward(instance: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(camera):
		return
	var card := REWARD_REVEAL.play(self, instance, camera, focus_area.global_position)
	if card != null:
		card.name = "PumpPuzzleRewardReveal"


func _update_switch(index: int, animate: bool) -> void:
	var material := _lamps[index]
	material.albedo_color = Color(1.0, 0.78, 0.12) if lever_up[index] else Color(0.29, 0.58, 0.19)
	material.emission = Color(1.0, 0.68, 0.04) if lever_up[index] else Color(0.34, 0.82, 0.13)
	material.emission_enabled = true
	material.emission_energy_multiplier = 2.0
	if _lever_tweens[index] != null:
		_lever_tweens[index].kill()
	var angle := -SWITCH_ANGLE if lever_up[index] else SWITCH_ANGLE
	if animate:
		_lever_tweens[index] = create_tween()
		_lever_tweens[index].tween_property(_pivots[index], "rotation:x", angle, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_pivots[index].rotation.x = angle
