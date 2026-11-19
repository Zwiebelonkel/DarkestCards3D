extends Node3D
## Four clicks form one complete attempt; the backend validates the saved MDMA gate.

signal attempt_reset
signal puzzle_solved(instance: Dictionary)

const PICK_LAYER := 1 << 23
const GRAVE_NODES := ["Grave_Pablo", "Grave_Trinity", "Grave_Steward", "Grave_Hannah"]
const VOICES := [
	preload("res://assets/sounds/SFX/names/pablo.res"),
	preload("res://assets/sounds/SFX/names/trinity.res"),
	preload("res://assets/sounds/SFX/names/steward.res"),
	preload("res://assets/sounds/SFX/names/hannah.res"),
]
const SEPARATOR := preload("res://assets/sounds/SFX/names/seperator.res")
const OUTLINE := preload("res://assets/shader/inventory_outline.gdshader")
const REVEAL := preload("res://scripts/ui/SecretCardReveal.gd")

@export_range(0.1, 1.0, 0.01) var click_voice_pitch := 0.28

var camera: Camera3D
var context_available: Callable
var interaction_enabled := false
var attempt: Array[String] = []
var graves: Array[Node3D] = []
var areas: Array[Area3D] = []
var hovered := -1
var resetting := false
var _meshes: Array[Array] = []
var _original_overlays: Dictionary = {}
var _outline: ShaderMaterial
var _voice: AudioStreamPlayer
var _separator: AudioStreamPlayer


func _ready() -> void:
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_color", Color(1, 0.85, 0, 1))
	_outline.set_shader_parameter("world_space_size", true)
	_outline.set_shader_parameter("outline_size", 0.018)
	for index in range(GRAVE_NODES.size()):
		var grave := get_parent().get_node("Burials/" + GRAVE_NODES[index]) as Node3D
		graves.append(grave)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(grave, meshes)
		_meshes.append(meshes)
		var area := Area3D.new()
		area.name = "NamePuzzlePickArea"
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		grave.add_child(area)
		for mesh in meshes:
			_original_overlays[mesh] = mesh.material_overlay
			var bounds := mesh.get_aabb()
			var shape := BoxShape3D.new()
			shape.size = bounds.size.max(Vector3.ONE * 0.01)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			area.add_child(collision)
			collision.transform = grave.global_transform.affine_inverse() * mesh.global_transform * Transform3D(Basis.IDENTITY, bounds.get_center())
		area.input_event.connect(_on_pick_input.bind(index))
		areas.append(area)
	_voice = AudioStreamPlayer.new()
	_voice.name = "GraveNameVoice"
	_voice.bus = &"SFX"
	_voice.pitch_scale = click_voice_pitch
	add_child(_voice)
	_separator = AudioStreamPlayer.new()
	_separator.name = "GraveAttemptSeparator"
	_separator.bus = &"SFX"
	_separator.stream = SEPARATOR
	add_child(_separator)
	_voice.finished.connect(_on_name_finished)
	_separator.finished.connect(_on_separator_finished)
	set_interaction_enabled(false)


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	for area in areas:
		area.input_ray_pickable = enabled and not resetting
		area.collision_layer = PICK_LAYER if enabled else 0
		area.set_meta("keep_input_ray_pickable_disabled", not area.input_ray_pickable)
	if not enabled:
		_set_hovered(-1)


func _can_interact() -> bool:
	return (interaction_enabled and not resetting and not get_tree().paused
		and is_visible_in_tree() and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call())))


func _process(_delta: float) -> void:
	var index := -1
	if _can_interact():
		var pointer := get_viewport().get_mouse_position()
		if get_viewport().get_visible_rect().has_point(pointer):
			var origin := camera.project_ray_origin(pointer)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, PICK_LAYER)
			query.collide_with_areas = true
			query.collide_with_bodies = false
			index = areas.find(get_world_3d().direct_space_state.intersect_ray(query).get("collider"))
	_set_hovered(index)


func _set_hovered(index: int) -> void:
	if index == hovered:
		return
	if hovered >= 0:
		for mesh: MeshInstance3D in _meshes[hovered]:
			mesh.material_overlay = _original_overlays[mesh]
	hovered = index
	if hovered >= 0:
		for mesh: MeshInstance3D in _meshes[hovered]:
			mesh.material_overlay = _outline


func _on_pick_input(pick_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int, index: int) -> void:
	if pick_camera != camera or not _can_interact() or not areas[index].input_ray_pickable:
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	_voice.stream = VOICES[index]
	_voice.pitch_scale = click_voice_pitch
	_voice.play()
	if not GameCurrency.mdma_consumed or GameCurrency.is_training_session() or CollectionManager.has_discovered_card(CollectionManager.GRAVE_REWARD_CARD_ID):
		attempt.clear()
		return
	attempt.append(CollectionManager.GRAVE_SOLUTION[index])
	if attempt.size() < 4:
		return
	var reward := CollectionManager.claim_grave_puzzle_reward(attempt)
	attempt.clear()
	if reward.is_empty():
		resetting = true
		set_interaction_enabled(interaction_enabled)
		_set_hovered(-1)
		return
	puzzle_solved.emit(reward)
	var card := REVEAL.play(self, reward, camera, graves[index].global_position + Vector3.UP, true)
	if card != null:
		card.name = "GravePuzzleRewardReveal"


func _on_name_finished() -> void:
	if resetting:
		_separator.play()


func _on_separator_finished() -> void:
	resetting = false
	set_interaction_enabled(interaction_enabled)
	attempt_reset.emit()


func cancel_attempt() -> void:
	attempt.clear()
	resetting = false
	_voice.stop()
	_separator.stop()
	_set_hovered(-1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_hovered(-1)
