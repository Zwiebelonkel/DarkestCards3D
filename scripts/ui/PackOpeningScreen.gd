extends Node3D
class_name PackOpeningScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")

@export var card_count := 5

@export_group("Pack Opening")
@export var pack_body_open_position := Vector3(0, -0.18, 0)
@export var pack_top_fly_position := Vector3(0, 3.5, -2.6)
@export var pack_top_fly_rotation := Vector3(-180, 35, 90)

@export_group("Pack Top Drag")
@export var drag_open_distance: float = 260.0
@export var drag_top_max_offset := Vector3(1.65, 0.0, 0.0)
@export var drag_top_rotation := Vector3(0.0, 0.0, -28.0)
@export var drag_release_snap_time: float = 0.18
@export var base_shake_strength: float = 0.045
@export var base_shake_rotation_strength: float = 4.0

@export_group("Cards In Pack")
@export var stack_base_position := Vector3(0, 0.62, -0.55)
@export var stack_position_offset := Vector3(0, 0.025, -0.018)
@export var stack_face_down_rotation := Vector3(-8, 180, 0)
@export var stack_card_scale := 0.82

@export_group("Reveal")
@export var shoot_height_offset := 0.45
@export var revealed_stack_position := Vector3(1.0, 0.62, -0.55)
@export var revealed_stack_offset := Vector3(0.015, 0.02, -0.01)
@export var revealed_scale := 0.72
@export var revealed_rotation := Vector3(-8, 0, 0)
@export var revealed_hover_offset := Vector3(-0.25, 0, 0)
@export var revealed_hover_rotation_offset := Vector3(0, -25, 0)
@export var revealed_hover_duration := 0.18

@onready var pack: Node3D = $pack
@onready var pack_mesh: MeshInstance3D = $pack/base
@onready var pack_top: MeshInstance3D = $pack/top
@onready var pack_top_area: Area3D = $pack/top/PackTopArea
@onready var cards_root: Node3D = $Cards
@onready var info_label: Label3D = $InfoLabel

var _hovering_pack := false
var _opened := false
var _dragging_pack_top := false
var _drag_start_mouse_pos := Vector2.ZERO
var _drag_progress := 0.0
var _pack_top_start_position := Vector3.ZERO
var _pack_top_start_rotation := Vector3.ZERO
var _pack_start_position := Vector3.ZERO
var _pack_start_rotation := Vector3.ZERO

var _card_stack: Array[Card3D] = []
var _revealed_cards: Array[Card3D] = []
var _revealed_rest_positions: Dictionary = {}
var _top_revealed_card: Card3D = null


func _ready() -> void:
	randomize()
	print("PackTopArea gefunden: ", pack_top_area)
	print("PackTopArea pickable: ", pack_top_area.input_ray_pickable)
	print("PackTopArea shapes: ", pack_top_area.get_child_count())

	if pack_top_area:
		pack_top_area.input_ray_pickable = true
		pack_top_area.monitoring = true
		pack_top_area.monitorable = true

		pack_top_area.mouse_entered.connect(func(): _hovering_pack = true)
		pack_top_area.mouse_exited.connect(func(): _hovering_pack = false)
		pack_top_area.input_event.connect(_on_pack_top_input)

	info_label.text = "PackTop ziehen"


func _process(delta: float) -> void:
	if _opened:
		return

	if _dragging_pack_top:
		_apply_base_shake(_drag_progress)
		return

	pack.rotation.y += sin(Time.get_ticks_msec() * 0.002) * delta * 0.45
	pack.rotation.x = sin(Time.get_ticks_msec() * 0.0015) * 0.08


func _input(event: InputEvent) -> void:
	if _opened:
		return

	if not _dragging_pack_top:
		return

	if event is InputEventMouseMotion:
		var drag_delta: Vector2 = event.position - _drag_start_mouse_pos

		# Maus nach links ziehen = Pack aufreißen
		var amount: float = clamp(drag_delta.x / drag_open_distance, 0.0, 1.0)
		_drag_progress = amount

		pack_top.position = _pack_top_start_position + drag_top_max_offset * amount
		pack_top.rotation_degrees = _pack_top_start_rotation + drag_top_rotation * amount

		_apply_base_shake(amount)

		info_label.text = "Loslassen zum Öffnen" if amount >= 1.0 else "Nach links ziehen..."

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_pack_top = false

		if _drag_progress >= 1.0:
			_open_pack_from_drag()
		else:
			_reset_pack_top_drag()
			
			
func _on_pack_top_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if _opened:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging_pack_top = true
		print("Dragging")
		_drag_start_mouse_pos = event.position
		_drag_progress = 0.0
		_pack_start_position = pack.position
		_pack_start_rotation = pack.rotation_degrees
		_pack_top_start_position = pack_top.position
		_pack_top_start_rotation = pack_top.rotation_degrees
		info_label.text = "Pack nach links aufreißen..."


func _reset_pack_top_drag() -> void:
	var tween := create_tween().set_parallel(true)

	tween.tween_property(pack_top, "position", _pack_top_start_position, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pack_top, "rotation_degrees", _pack_top_start_rotation, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.tween_property(pack, "position", _pack_start_position, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pack, "rotation_degrees", _pack_start_rotation, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_drag_progress = 0.0
	info_label.text = "Pack nach links aufreißen"


func _open_pack_from_drag() -> void:
	_opened = true
	_hovering_pack = false
	_dragging_pack_top = false
	info_label.text = "Pack wird geöffnet..."

	if pack_top_area:
		pack_top_area.monitoring = false

	var top_tween := create_tween().set_parallel(true)
	top_tween.tween_property(pack_top, "position", pack_top_fly_position, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_top, "rotation_degrees", pack_top_fly_rotation, 0.45)
	top_tween.tween_property(pack_top, "scale", Vector3.ZERO, 0.35)

	var body_tween := create_tween().set_parallel(true)
	body_tween.tween_property(pack, "position", pack_body_open_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	body_tween.tween_property(pack, "rotation_degrees", Vector3.ZERO, 0.25)

	await get_tree().create_timer(0.45).timeout

	pack_top.visible = false
	_spawn_cards_inside_pack()


func _spawn_cards_inside_pack() -> void:
	_clear_old_cards()

	var cards := CardDatabase.get_all_cards()
	if cards.is_empty():
		info_label.text = "Keine Karten gefunden"
		return

	cards.shuffle()

	for i in range(card_count):
		var data: Dictionary = CardDatabase.get_random_card_weighted()

		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.setup(data)

		card.position = Vector3(0, 0.15, -1.1)
		card.rotation_degrees = stack_face_down_rotation
		card.scale = Vector3.ONE * 0.01

		_card_stack.append(card)

		var final_pos := _get_stack_position(i)

		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", final_pos, 0.35 + i * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", stack_face_down_rotation, 0.35 + i * 0.05)
		tween.tween_property(card, "scale", Vector3.ONE * stack_card_scale, 0.25 + i * 0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.7).timeout

	_connect_top_card()
	info_label.text = "Oberste Karte anklicken"


func _get_stack_position(index: int) -> Vector3:
	return stack_base_position + stack_position_offset * index


func _get_revealed_position(index: int) -> Vector3:
	return revealed_stack_position + revealed_stack_offset * index


func _get_top_card() -> Card3D:
	if _card_stack.is_empty():
		return null

	return _card_stack[0]


func _connect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and not top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.connect(_on_top_card_input)


func _disconnect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.disconnect(_on_top_card_input)


func _on_top_card_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var top_card := _get_top_card()
	if top_card == null:
		return

	_reveal_top_card(top_card)


func _reveal_top_card(card: Card3D) -> void:
	_disconnect_top_card()

	var card_id := str(card.card_data.get("id", ""))
	var card_name := str(card.card_data.get("name", card_id))

	if card_id != "":
		CollectionManager.add_card(card_id)

	info_label.text = card_name + " gezogen"

	_card_stack.erase(card)
	_revealed_cards.append(card)

	var reveal_index := _revealed_cards.size() - 1
	var final_pos := _get_revealed_position(reveal_index)

	if _card_stack.is_empty():
		info_label.text = "Pack vollständig geöffnet"
	else:
		_realign_stack_in_pack()
		_connect_top_card()
		info_label.text = "Nächste Karte anklicken"

	var previous_top_card := _top_revealed_card
	if is_instance_valid(previous_top_card):
		_connect_revealed_hover(previous_top_card)

	_top_revealed_card = card

	_animate_revealed_card(card, final_pos)


func _animate_revealed_card(card: Card3D, final_pos: Vector3) -> void:
	var lift_position := card.position + Vector3(0, shoot_height_offset, 0)

	var shoot_tween := create_tween().set_parallel(true)
	shoot_tween.tween_property(card, "position", lift_position, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	shoot_tween.tween_property(card, "scale", Vector3.ONE * 1.05, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await shoot_tween.finished

	if not is_instance_valid(card):
		return

	var flip_tween := create_tween().set_parallel(true)
	flip_tween.tween_property(card, "rotation_degrees", revealed_rotation, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "position", final_pos, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "scale", Vector3.ONE * revealed_scale, 0.32)

	await flip_tween.finished

	if not is_instance_valid(card):
		return

	card.position = final_pos
	card.rotation_degrees = revealed_rotation

	_revealed_rest_positions[card] = final_pos


func _connect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if not card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.connect(_on_revealed_card_hover_start.bind(card))

	if not card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.connect(_on_revealed_card_hover_end.bind(card))


func _disconnect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.disconnect(_on_revealed_card_hover_start)

	if card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.disconnect(_on_revealed_card_hover_end)


func _on_revealed_card_hover_start(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	if card == _top_revealed_card:
		return

	var rest_pos: Vector3 = _revealed_rest_positions[card]
	var hover_pos := rest_pos + revealed_hover_offset
	var hover_rot := revealed_rotation + revealed_hover_rotation_offset

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", hover_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rot, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_revealed_card_hover_end(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	var rest_pos: Vector3 = _revealed_rest_positions[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", rest_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", revealed_rotation, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _realign_stack_in_pack() -> void:
	for i in range(_card_stack.size()):
		var card := _card_stack[i]
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", _get_stack_position(i), 0.18)
		tween.tween_property(card, "rotation_degrees", stack_face_down_rotation, 0.18)


func _clear_old_cards() -> void:
	for card in _card_stack:
		if is_instance_valid(card):
			card.queue_free()

	for card in _revealed_cards:
		if is_instance_valid(card):
			card.queue_free()

	_card_stack.clear()
	_revealed_cards.clear()
	_revealed_rest_positions.clear()
	_top_revealed_card = null
	
	
func _apply_base_shake(amount: float) -> void:
	var t := Time.get_ticks_msec() * 0.05

	var shake_power := amount * amount

	var shake_x := sin(t * 1.7) * base_shake_strength * shake_power
	var shake_y := cos(t * 2.1) * base_shake_strength * 0.45 * shake_power
	var shake_z := sin(t * 2.8) * base_shake_strength * 0.35 * shake_power

	pack.position = _pack_start_position + Vector3(shake_x, shake_y, shake_z)

	pack.rotation_degrees = _pack_start_rotation + Vector3(
		sin(t * 2.4) * base_shake_rotation_strength * shake_power,
		cos(t * 1.8) * base_shake_rotation_strength * 0.6 * shake_power,
		sin(t * 2.9) * base_shake_rotation_strength * 0.8 * shake_power
	)
