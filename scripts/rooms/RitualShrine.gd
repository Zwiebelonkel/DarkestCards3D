extends Node3D
## Three manually dragged story cards unlock the physical shotgun reward.

signal busy_changed
signal shotgun_collected
const CARD := preload("res://scenes/table/Card3D.tscn")
const OUTLINE := preload("res://assets/shader/inventory_outline.gdshader")
const UI_AUDIO := preload("res://scripts/ui/InterfaceSounds.gd")
const PICK_LAYER := 1 << 26
const HAND_SCALE := 0.60

@export var drop_height := 3.4
@export var drop_duration := 0.9
var camera: Camera3D
var focus_controller: ScreenCameraFocus
var interaction_enabled := false
var available_cards: Dictionary = {}
var seated_cards: Dictionary = {}
var dragging_id := ""
var dropping := false
var snapping := false
var collecting := false
var _refresh_pending := false
var _drag_plane := Plane()
var _drag_offset := Vector3.ZERO
var _card_homes: Dictionary = {}
var _gun_hovered := false
var _outline: ShaderMaterial
var _gun_rest := Transform3D.IDENTITY
var _animation: Tween
var _hover_socket := -1
var _save_failed := false

@onready var focus_area: Area3D = $FocusArea
@onready var shotgun: Node3D = $Shotgun
@onready var shotgun_area: Area3D = $ShotgunPickArea
@onready var sockets: Node3D = $Sockets
@onready var hand: Node3D = $AvailableCards
@onready var status: Label3D = $Status


func _ready() -> void:
	_gun_rest = shotgun.transform
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_color", Color(1, 0.85, 0, 1))
	_outline.set_shader_parameter("world_space_size", true)
	_outline.set_shader_parameter("outline_size", 0.018)
	focus_area.set_meta("focus_camera_marker", $FocusCamera)
	focus_area.set_meta("focus_fov", 49.0)
	CollectionManager.collection_changed.connect(_queue_refresh)
	Localization.locale_changed.connect(_update_status)
	_refresh_from_save()
	set_interaction_enabled(false)


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not is_node_ready():
		return
	focus_area.input_ray_pickable = enabled
	focus_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	shotgun_area.input_ray_pickable = enabled and shotgun.visible and not is_busy()
	shotgun_area.set_meta("keep_input_ray_pickable_disabled", not shotgun_area.input_ray_pickable)
	if not enabled:
		_cancel_drag()
		_set_gun_hover(false)
		_set_socket_hover(-1)
		hand.hide()


func is_busy() -> bool:
	return not dragging_id.is_empty() or snapping or dropping or collecting


func _focused() -> bool:
	return focus_controller != null and focus_controller._focused_screen == focus_area


func _can_interact() -> bool:
	return (interaction_enabled and is_visible_in_tree() and not get_tree().paused
		and is_instance_valid(camera) and camera.is_current() and _focused()
		and focus_controller._camera_tween == null)


func _process(_delta: float) -> void:
	if _refresh_pending and not is_busy():
		_refresh_from_save()
	var can_interact := _can_interact()
	($FocusArea/HandHoverShape as CollisionShape3D).disabled = not _focused()
	hand.visible = interaction_enabled and _focused() and not get_tree().paused
	for card_id: String in available_cards:
		var card: Card3D = available_cards[card_id]
		if card_id != dragging_id and card.get_parent() == hand and is_instance_valid(camera):
			card.global_basis = camera.global_basis.orthonormalized().scaled(Vector3.ONE * HAND_SCALE)
	if not can_interact:
		_cancel_drag()
		_set_gun_hover(false)
		return
	var pointer := get_viewport().get_mouse_position()
	if not dragging_id.is_empty():
		var hit: Variant = _drag_plane.intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
		if hit != null:
			(available_cards[dragging_id] as Card3D).global_position = hit + _drag_offset
		_set_socket_hover(_socket_at(pointer))
	_set_gun_hover(not is_busy() and shotgun.visible and is_finite(_area_distance(shotgun_area, pointer)))


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not _can_interact():
		return
	if not event.pressed and not dragging_id.is_empty():
		var card_id := dragging_id
		var target := _socket_at(event.position)
		dragging_id = ""
		_set_socket_hover(-1)
		if target >= 0:
			_place_card(card_id, target)
		else:
			_return_card(card_id)
		busy_changed.emit()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed or is_busy():
		return
	var card_id := _card_at(event.position)
	if not card_id.is_empty():
		dragging_id = card_id
		var card: Card3D = available_cards[card_id]
		_drag_plane = Plane(camera.global_basis.z.normalized(), card.global_position)
		var hit: Variant = _drag_plane.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		_drag_offset = card.global_position - hit if hit != null else Vector3.ZERO
		busy_changed.emit()
		get_viewport().set_input_as_handled()
	elif shotgun.visible and is_finite(_area_distance(shotgun_area, event.position)):
		_collect_shotgun()
		get_viewport().set_input_as_handled()


func _place_card(card_id: String, index: int) -> void:
	if not CollectionManager.place_vault_ritual_card(card_id, index):
		_save_failed = true
		_return_card(card_id)
		_update_status()
		return
	_save_failed = false
	snapping = true
	busy_changed.emit()
	var card: Card3D = available_cards[card_id]
	card.reparent(self, true)
	var target := (sockets.get_child(index).get_node("CardAnchor") as Marker3D).global_transform
	_animation = create_tween()
	_animation.tween_property(card, "global_transform", target, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _animation.finished
	_animation = null
	available_cards.erase(card_id)
	_card_homes.erase(card_id)
	seated_cards[index] = card
	snapping = false
	UI_AUDIO.play_click(self)
	_refresh_from_save(true)
	busy_changed.emit()


func _return_card(card_id: String) -> void:
	if available_cards.has(card_id):
		(available_cards[card_id] as Card3D).position = _card_homes[card_id]


func _cancel_drag() -> void:
	if dragging_id.is_empty():
		return
	_return_card(dragging_id)
	dragging_id = ""
	_set_socket_hover(-1)
	busy_changed.emit()


func _refresh_from_save(animate_reward: bool = false) -> void:
	_refresh_pending = false
	var state := CollectionManager.get_vault_ritual_state()
	for index: int in seated_cards.keys():
		if str(state.slots[index]) != str((seated_cards[index] as Card3D).card_data.get("id", "")):
			(seated_cards[index] as Card3D).queue_free()
			seated_cards.erase(index)
	for card_id: String in available_cards.keys():
		if state.slots.has(card_id) or CollectionManager.get_amount(card_id) <= 0:
			(available_cards[card_id] as Card3D).queue_free()
			available_cards.erase(card_id)
			_card_homes.erase(card_id)
	for index in range(3):
		var card_id := str(state.slots[index])
		if not card_id.is_empty() and not seated_cards.has(index):
			var card := _make_card(card_id, self)
			card.global_transform = (sockets.get_child(index).get_node("CardAnchor") as Marker3D).global_transform
			seated_cards[index] = card
	for index in range(CollectionManager.RITUAL_CARD_IDS.size()):
		var card_id: String = CollectionManager.RITUAL_CARD_IDS[index]
		if not state.slots.has(card_id) and CollectionManager.get_amount(card_id) > 0 and not available_cards.has(card_id):
			var card := _make_card(card_id, hand)
			card.position = Vector3((index - 1) * 1.15, 0, 0)
			card.scale = Vector3.ONE * HAND_SCALE
			available_cards[card_id] = card
			_card_homes[card_id] = card.position
	if state.completed and not state.shotgun_collected:
		if animate_reward:
			_drop_shotgun()
		elif not dropping:
			shotgun.transform = _gun_rest
			shotgun.show()
	elif not dropping and not collecting:
		shotgun.hide()
	_update_status()
	set_interaction_enabled(interaction_enabled)


func _make_card(card_id: String, parent: Node3D) -> Card3D:
	var card := CARD.instantiate() as Card3D
	card.name = "RitualCard_" + card_id
	parent.add_child(card)
	card.setup(CollectionManager.get_display_card(card_id))
	card.description_label.skip()
	_disable_card_input(card)
	return card


func _disable_card_input(node: Node) -> void:
	if node is Area3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)


func _drop_shotgun() -> void:
	if dropping or collecting:
		return
	dropping = true
	_set_gun_hover(false)
	shotgun.show()
	shotgun.transform = _gun_rest
	shotgun.position.y += drop_height
	busy_changed.emit()
	_animation = create_tween()
	_animation.tween_property(shotgun, "position:y", _gun_rest.origin.y, drop_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_animation.tween_property(shotgun, "position:y", _gun_rest.origin.y + 0.16, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(shotgun, "position:y", _gun_rest.origin.y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _animation.finished
	_animation = null
	dropping = false
	UI_AUDIO.play_click(self)
	busy_changed.emit()
	_update_status()
	set_interaction_enabled(interaction_enabled)


func _collect_shotgun() -> void:
	if not CollectionManager.claim_vault_ritual_shotgun():
		_save_failed = true
		_update_status()
		return
	_save_failed = false
	collecting = true
	_set_gun_hover(false)
	busy_changed.emit()
	_animation = create_tween().set_parallel(true)
	_animation.tween_property(shotgun, "global_position", camera.global_position - camera.global_basis.z * 0.7, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_animation.tween_property(shotgun, "scale", Vector3.ONE * 0.03, 0.38)
	await _animation.finished
	_animation = null
	shotgun.hide()
	collecting = false
	UI_AUDIO.play_click(self)
	shotgun_collected.emit()
	busy_changed.emit()
	_refresh_from_save()


func _area_distance(area: Area3D, point: Vector2) -> float:
	var collider := area.get_child(0) as CollisionShape3D
	var box := collider.shape as BoxShape3D
	var origin := camera.project_ray_origin(point)
	var end := origin + camera.project_ray_normal(point) * camera.far
	var hit: Variant = AABB(-box.size * 0.5, box.size).intersects_segment(collider.to_local(origin), collider.to_local(end))
	return origin.distance_to(collider.to_global(hit)) if hit != null else INF


func _socket_at(point: Vector2) -> int:
	var state := CollectionManager.get_vault_ritual_state()
	var nearest := INF
	var result := -1
	for index in range(3):
		if not str(state.slots[index]).is_empty():
			continue
		var distance := _area_distance(sockets.get_child(index).get_node("PickArea"), point)
		if distance < nearest:
			nearest = distance
			result = index
	return result


func _card_at(point: Vector2) -> String:
	var origin := camera.project_ray_origin(point)
	var end := origin + camera.project_ray_normal(point) * camera.far
	var nearest := INF
	var result := ""
	for card_id: String in available_cards:
		var card: Card3D = available_cards[card_id]
		var hit: Variant = AABB(Vector3(-0.44, -0.65, -0.12), Vector3(0.88, 1.3, 0.24)).intersects_segment(card.to_local(origin), card.to_local(end))
		if hit != null:
			var distance := origin.distance_to(card.to_global(hit))
			if distance < nearest:
				nearest = distance
				result = card_id
	return result


func _set_socket_hover(index: int) -> void:
	if _hover_socket == index:
		return
	_hover_socket = index
	for socket_index in range(3):
		var socket := sockets.get_child(socket_index)
		for node in socket.get_children():
			if node is MeshInstance3D and str(node.name).begins_with("Rim"):
				node.material_overlay = _outline if index == socket_index else null


func _set_gun_hover(value: bool) -> void:
	if _gun_hovered == value:
		return
	_gun_hovered = value
	for node in shotgun.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _outline if value else null


func _queue_refresh(_changed: Array = []) -> void:
	_refresh_pending = true


func _update_status() -> void:
	var state := CollectionManager.get_vault_ritual_state()
	var message := "Ziehe deine drei Story-Karten in die freien Sockel."
	if _save_failed:
		message = "Speichern fehlgeschlagen. Bitte erneut versuchen."
	elif state.shotgun_collected:
		message = "Shotgun eingesammelt."
	elif state.completed:
		message = "Die Shotgun gehört dir. Klicke sie an." if not dropping else "Das Ritual ist vollendet."
	status.text = Localization.text(message)
	Localization.fit_text_3d(status, 4.2, 0.12)
