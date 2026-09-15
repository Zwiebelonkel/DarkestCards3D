extends Node3D
class_name LocalTableProp
## Cosmetic table clutter. Its transform never participates in match snapshots or RPCs.

const PICK_COLLISION_LAYER := 1 << 10
const THROW_MOTION := preload("res://scripts/table/TableThrowMotion.gd")
const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const PROP_SECRET_MODELS := {
	"res://assets/environments/props/usb/scene.gltf": "usb_stick",
	"res://assets/environments/props/cigarettes/cigs.glb": "cigarettes",
	"res://assets/environments/props/beer/energy.glb": "moewenmilch",
}
# Cross-section of the imported blade just above the visible tabletop.
const KNIFE_BLADE_CONTACT := Vector3(0.052175, -0.005438, -1.567834)
const KNIFE_CARD_OFFSET := Vector3(-0.102035, 0.002868, 0.0009955)

@export_range(1.0, 12.0, 0.1) var throw_speed := THROW_MOTION.THROW_SPEED
@export_range(0.5, 8.0, 0.1) var upward_speed := THROW_MOTION.UPWARD_SPEED
@export_range(1.0, 25.0, 0.1) var gravity := THROW_MOTION.GRAVITY
@export_range(0.5, 5.0, 0.1) var flight_duration := THROW_MOTION.FLIGHT_DURATION
@export var throw_sound: AudioStream

var _pick_area: Area3D
var _center_local := Vector3.ZERO
var _flight_center := Vector3.ZERO
var _flight_start := Transform3D.IDENTITY
var _velocity := Vector3.ZERO
var _spin_axis := Vector3.RIGHT
var _spin_speed := 0.0
var _flight_time := 0.0
var _launched := false
var _knife_card: Card3D
# A separate RNG prevents cosmetic clicks from changing battle/deck randomness.
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	set_physics_process(false)
	_create_pick_area()
	if _is_knife():
		CollectionManager.collection_changed.connect(_sync_knife_card)
		_sync_knife_card()
	visibility_changed.connect(_sync_pick_visibility)
	_sync_pick_visibility()


func _create_pick_area() -> void:
	_pick_area = Area3D.new()
	_pick_area.name = "LocalPropPickArea"
	_pick_area.collision_layer = PICK_COLLISION_LAYER
	_pick_area.collision_mask = 0
	_pick_area.monitoring = false
	_pick_area.monitorable = false
	add_child(_pick_area)
	_pick_area.input_event.connect(_on_input_event)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	var bounds := AABB()
	var has_bounds := false
	var to_prop := global_transform.affine_inverse()
	for mesh_instance in meshes:
		# Mesh surfaces provide tight picking, including the slender knife and USB.
		# A large box around the entire decoration group would overlap the cards.
		var mesh_transform := to_prop * mesh_instance.global_transform
		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = mesh_transform
		_pick_area.add_child(collision)
		var mesh_bounds := mesh_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	if has_bounds:
		_center_local = bounds.get_center()


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			meshes.append(mesh_instance)
	for child in node.get_children():
		_collect_meshes(child, meshes)


func _sync_pick_visibility() -> void:
	if _pick_area == null:
		return
	# Hidden duplicate decorations must never absorb a click on a visible object.
	_pick_area.collision_layer = PICK_COLLISION_LAYER if is_visible_in_tree() and not _launched else 0
	if _launched:
		_pick_area.input_ray_pickable = false


func _on_input_event(camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if _launched or not is_visible_in_tree() or get_tree().paused:
		return
	if not _pick_area.input_ray_pickable or camera != get_viewport().get_camera_3d():
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Physics picking runs after GUI/unhandled input, so menus consume their clicks.
	get_viewport().set_input_as_handled()
	_launch(camera as Camera3D)


func _launch(camera: Camera3D) -> void:
	if _launched or not is_instance_valid(camera):
		return
	_launched = true
	_pick_area.set_meta("keep_input_ray_pickable_disabled", true)
	_pick_area.input_ray_pickable = false
	_pick_area.set_deferred("collision_layer", 0)
	_flight_start = global_transform
	_flight_center = global_transform * _center_local
	var direction := _flight_center - camera.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = -camera.global_basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	direction = direction.normalized().rotated(Vector3.UP, _random.randf_range(-0.2, 0.2))
	_velocity = direction * throw_speed + Vector3.UP * upward_speed
	_spin_axis = Vector3.UP.cross(direction).normalized()
	_spin_speed = _random.randf_range(THROW_MOTION.MIN_SPIN_SPEED, THROW_MOTION.MAX_SPIN_SPEED)
	set_physics_process(true)
	_play_throw_sound()
	_award_knife_key()
	_award_prop_secret(camera)


func _play_throw_sound() -> void:
	if throw_sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "ThrowSound"
	player.stream = throw_sound
	player.bus = &"SFX"
	player.volume_db = -6.0
	# The scene owns this one-shot: hiding clutter or reparenting a flying
	# basement crate must not interrupt the sound halfway through.
	var sound_parent: Node = get_tree().current_scene
	if sound_parent == null:
		sound_parent = get_tree().root
	sound_parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _is_knife() -> bool:
	return name.to_lower() == "knife" or scene_file_path.ends_with("/knife/knife.glb")


func _award_prop_secret(camera: Camera3D) -> void:
	var card_id := str(PROP_SECRET_MODELS.get(scene_file_path, ""))
	if card_id.is_empty():
		return
	var instance := CollectionManager.discover_prop_secret(card_id, _random)
	if not instance.is_empty():
		# Picking runs inside a physics query; create the reveal afterwards.
		_show_prop_discovery.call_deferred(instance, camera, _flight_center)


func _show_prop_discovery(instance: Dictionary, camera: Camera3D, origin: Vector3) -> void:
	if not is_instance_valid(camera) or not is_inside_tree():
		return
	var card := CARD_SCENE.instantiate() as Card3D
	card.name = "DiscoveredUsbSecret" if instance.get("card_id") == "usb_stick" else "DiscoveredPropSecret"
	card.top_level = true
	get_parent().add_child(card)
	card.setup(CardData.merge_card_and_instance(CardDatabase.get_card(str(instance["card_id"])), instance))
	card.description_label.skip()
	_disable_card_picking(card)
	var facing := camera.global_basis.orthonormalized()
	var destination := camera.global_position - facing.z * 1.6 - facing.y * 0.08
	card.global_transform = Transform3D(facing.scaled(Vector3.ONE * 0.15), origin)
	var reveal := card.create_tween()
	reveal.tween_property(card, "global_transform", Transform3D(facing, destination), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# A gentle turn makes the room's depth visible at the moment of discovery.
	for angle in [-18.0, 18.0, 0.0]:
		var pose := Transform3D(facing * Basis(Vector3.UP, deg_to_rad(angle)), destination)
		reveal.tween_property(card, "global_transform", pose, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(card, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	reveal.tween_callback(card.queue_free)


func _knife_key_found() -> bool:
	return CollectionManager.has_discovered_card(CollectionManager.SLOT_ROOM_KEY_ID) or CollectionManager.is_slot_room_unlocked()


func _sync_knife_card(_card_ids: Array[String] = []) -> void:
	if _knife_key_found():
		if is_instance_valid(_knife_card):
			_knife_card.hide()
			_knife_card.queue_free()
			_knife_card = null
	elif not _launched and not is_instance_valid(_knife_card):
		_attach_knife_card()


func _attach_knife_card() -> void:
	if not _is_knife() or _knife_key_found():
		return
	# Build after the knife's picking mesh so this visual neither steals card
	# clicks nor changes the existing flight pivot. It stays pinned only until
	# the key is discovered, including on other already-instantiated knives.
	_knife_card = CARD_SCENE.instantiate() as Card3D
	_knife_card.name = "PinnedKeyCard"
	_knife_card.is_stack_decoration = true
	add_child(_knife_card)
	_knife_card.setup(CardDatabase.get_card(CollectionManager.SLOT_ROOM_KEY_ID))
	_knife_card.process_mode = Node.PROCESS_MODE_DISABLED
	_knife_card.description_label.skip()
	_knife_card.card_outline.hide()
	_knife_card.rarity_mesh.hide()
	_disable_card_picking(_knife_card)
	var body := _knife_card.card_model.get_node("Cube") as MeshInstance3D
	for surface in range(body.mesh.get_surface_count()):
		var material := body.get_active_material(surface).duplicate() as Material
		material.next_pass = null
		body.set_surface_override_material(surface, material)
	# Match the game's normal face-down orientation, lying flat in the
	# decoration parent's space rather than inheriting the slanted knife pose.
	var body_in_card := _knife_card.card_model.transform * body.transform
	var printed_bounds: AABB = body_in_card * body.get_aabb()
	var paper_scale := Vector3(0.35, 0.35, 0.005 / maxf(printed_bounds.size.z, 0.001))
	var card_basis := Basis.from_euler(Vector3(PI * 0.5, PI, 0.0)) * Basis.from_scale(paper_scale)
	var center := transform * KNIFE_BLADE_CONTACT + KNIFE_CARD_OFFSET
	var card_bounds: AABB = Transform3D(card_basis, Vector3.ZERO) * body_in_card * body.get_aabb()
	center.y -= card_bounds.end.y
	_knife_card.transform = transform.affine_inverse() * Transform3D(card_basis, center)


func _disable_card_picking(node: Node) -> void:
	if node is Area3D:
		var area := node as Area3D
		area.input_ray_pickable = false
		area.collision_layer = 0
		area.collision_mask = 0
		area.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_picking(child)


func _award_knife_key() -> void:
	# Both the hub and match table use the same imported knife. A renamed
	# instance still qualifies by its model path, while other clutter does not.
	if not _is_knife():
		return
	var card_id := CollectionManager.SLOT_ROOM_KEY_ID
	if _knife_key_found():
		return
	# Use this prop's RNG, including identity/Holo, so a cosmetic table throw
	# cannot consume the shared battle/deck random sequence. No reveal or sound.
	CollectionManager.add_card_instance({
		"instance_id": "%s_%s_%d" % [card_id, Time.get_unix_time_from_system(), _random.randi()],
		"card_id": card_id,
		"level": 1,
		"effects": [],
		"is_holo": CardData.roll_holo(_random.randi_range(0, CardData.HOLO_ROLL_SIDES - 1)),
	})


func _physics_process(delta: float) -> void:
	_flight_time += delta
	# Rotate around the visible object, even when the imported model's origin is offset.
	global_transform = THROW_MOTION.transform_at(
		_flight_start, _center_local, _velocity, _spin_axis, _spin_speed, gravity, _flight_time
	)
	if _flight_time >= flight_duration:
		hide()
		set_physics_process(false)
