extends Node3D
class_name BasementDiscovery
## The cemetery key is a local, saved discovery, like the key pinned by the knife.

signal card_discovered(card_id: String)

const KEY_CARD_ID := "graveyard_key"
const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const CRATE_WORLD_LAYER := 1 << 12

var _crates: Array[BasementCrate] = []
var _secret_crate: BasementCrate
var _hidden_card: Card3D
var _discovered := false
var _interaction_enabled := false
var _reveal_tween: Tween
var _random := RandomNumberGenerator.new()
var _crate_environment: StaticBody3D


func _ready() -> void:
	_random.randomize()
	_create_crate_environment()
	for node in $Storage.find_children("*", "Node3D", true, false):
		if node is BasementCrate:
			var crate := node as BasementCrate
			_crates.append(crate)
			crate.thrown.connect(_on_crate_thrown)
	_secret_crate = $Storage/FloorCrate as BasementCrate
	_discovered = _already_found()
	_create_hidden_card()
	CollectionManager.collection_changed.connect(_on_collection_changed)
	set_interaction_enabled(false)


func _create_crate_environment() -> void:
	# Bake the actual room geometry into unscaled physics space. This keeps
	# impacts aligned with the imported hospital's floor, walls and doorway.
	_crate_environment = StaticBody3D.new()
	_crate_environment.name = "CrateWorldCollision"
	_crate_environment.top_level = true
	_crate_environment.collision_layer = CRATE_WORLD_LAYER
	_crate_environment.collision_mask = 0
	_crate_environment.input_ray_pickable = false
	_crate_environment.set_meta("keep_input_ray_pickable_disabled", true)
	add_child(_crate_environment)
	_crate_environment.global_transform = Transform3D(Basis.IDENTITY, global_position)
	var faces := PackedVector3Array()
	_collect_environment_faces($Shell, faces)
	# Shelves catch the rebounding crates instead of letting the wood pass
	# through their metal supports. The crates themselves remain independent.
	_collect_environment_faces($Storage/Rack0, faces)
	_collect_environment_faces($Storage/Rack1, faces)
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "RoomAndShelves"
	collision.shape = shape
	_crate_environment.add_child(collision)


func _collect_environment_faces(node: Node, faces: PackedVector3Array) -> void:
	if node is BasementCrate:
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree():
			var to_physics := _crate_environment.global_transform.affine_inverse() * mesh_instance.global_transform
			for vertex in mesh_instance.mesh.get_faces():
				faces.append(to_physics * vertex)
	for child in node.get_children():
		_collect_environment_faces(child, faces)


func get_crates() -> Array[BasementCrate]:
	return _crates.duplicate()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	for crate in _crates:
		crate.set_interaction_enabled(enabled)


func _already_found() -> bool:
	# Older saves may already own the formerly drawable key. Keep that access
	# and do not turn the new hiding place into a second copy.
	return CollectionManager.get_amount(KEY_CARD_ID) > 0 or CollectionManager.has_area_access("graveyard")


func _create_hidden_card() -> void:
	_hidden_card = CARD_SCENE.instantiate() as Card3D
	_hidden_card.name = "HiddenGraveyardKey"
	_hidden_card.is_stack_decoration = true
	add_child(_hidden_card)
	_hidden_card.setup(CardDatabase.get_card(KEY_CARD_ID))
	_hidden_card.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_card_input()
	_hidden_card.card_outline.hide()
	_hidden_card.rarity_mesh.hide()
	_hidden_card.description_label.skip()
	# Keep the actual paper on the floor, as a sibling of the thrown crate.
	# Its face and aura must not shine through the wood before discovery.
	var body := _hidden_card.card_model.get_node("Cube") as MeshInstance3D
	for surface in range(body.mesh.get_surface_count()):
		var material := body.get_active_material(surface)
		if material != null:
			var matte := material.duplicate() as Material
			matte.next_pass = null
			body.set_surface_override_material(surface, matte)
	var printed_bounds := (_hidden_card.card_model.transform * body.transform) * body.get_aabb()
	var paper_scale := Vector3(0.7, 0.7, 0.008 / maxf(printed_bounds.size.z, 0.001))
	var paper_basis := Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)) * Basis.from_scale(paper_scale)
	var flattened_bounds: AABB = Transform3D(paper_basis, Vector3.ZERO) * printed_bounds
	var floor_point := ($Storage as Node3D).to_global(Vector3(_secret_crate.position.x, 0.012, _secret_crate.position.z))
	var origin := floor_point - Vector3(flattened_bounds.get_center().x, flattened_bounds.position.y, flattened_bounds.get_center().z)
	_hidden_card.global_transform = Transform3D(paper_basis, origin)
	_hidden_card.visible = not _discovered


func _disable_card_input() -> void:
	for child in _hidden_card.find_children("*", "Area3D", true, false):
		var area := child as Area3D
		area.input_ray_pickable = false
		area.collision_layer = 0
		area.collision_mask = 0
		area.set_meta("keep_input_ray_pickable_disabled", true)


func _on_crate_thrown(crate: BasementCrate) -> void:
	if crate != _secret_crate or _discovered or not _interaction_enabled or get_tree().paused:
		return
	if _already_found() or not CollectionManager.can_obtain_card(KEY_CARD_ID):
		_discovered = true
		_hidden_card.hide()
		return
	_discovered = true
	# Cosmetic exploration never advances the global battle/reward RNG.
	var stored := CollectionManager.add_card_instance({
		"instance_id": "%s_%s_%d" % [KEY_CARD_ID, Time.get_unix_time_from_system(), _random.randi()],
		"card_id": KEY_CARD_ID,
		"level": 1,
		"effects": [],
		"is_holo": CardData.roll_holo(_random.randi_range(0, CardData.HOLO_ROLL_SIDES - 1)),
	})
	if stored.is_empty():
		_discovered = false
		return
	_show_discovery(stored)
	card_discovered.emit(KEY_CARD_ID)


func _show_discovery(instance: Dictionary) -> void:
	var data := CardDatabase.get_card(KEY_CARD_ID).duplicate(true)
	data.merge(instance, true)
	_hidden_card.is_stack_decoration = false
	_hidden_card.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden_card.setup(data)
	_hidden_card.description_label.skip()
	_hidden_card.card_outline.hide()
	_disable_card_input()
	_hidden_card.show()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var start := _hidden_card.global_transform
	var towards_camera := (camera.global_position - start.origin).normalized()
	var destination := start.origin + Vector3.UP * 1.2 + towards_camera * 1.3
	var face_camera := Basis.looking_at(camera.global_position - destination, Vector3.UP, true)
	var revealed := Transform3D(face_camera * Basis.from_scale(start.basis.get_scale()), destination)
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(0.18)
	_reveal_tween.tween_property(_hidden_card, "global_transform", revealed, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_interval(2.5)
	var collected := Transform3D(revealed.basis.scaled(Vector3.ONE * 0.01), destination + Vector3.UP * 0.35)
	_reveal_tween.tween_property(_hidden_card, "global_transform", collected, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_reveal_tween.tween_callback(_hidden_card.hide)


func _on_collection_changed(card_ids: Array[String]) -> void:
	# Also retire the secret if an existing save is loaded while Main is open.
	if not _discovered and card_ids.has(KEY_CARD_ID) and _already_found():
		_discovered = true
		_hidden_card.hide()
