extends Node3D
class_name CollectionScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const CARD_SPACING := Vector3(0.95, 0.0, 1.25)
const COLUMNS := 5

@export_group("Eingangs-Animation")
@export var spawn_rise_height := 0.6
@export var spawn_duration := 0.4
@export var spawn_stagger := 0.04

@export_group("Hover")
@export var hover_lift := Vector3(0, 0.35, 0.38)
@export var hover_rotation := Vector3(-8, 0, 0)
@export var hover_scale := 1.08
@export var hover_duration := 0.15

@export_group("Detailansicht")
@export var detail_offset_from_camera := Vector3(0, 0, -1.6)
@export var detail_rotation := Vector3(0, 0, 0)
@export var detail_scale := 2.2
@export var detail_duration := 0.32

@onready var camera: Camera3D = $Camera3D
@onready var cards_root: Node3D = $Cards
@onready var empty_label: Label3D = $EmptyLabel

@export_group("Detail Mouse Tilt")
@export var detail_mouse_tilt_strength := 50.0
@export var detail_mouse_tilt_smooth := 10.0

var _detail_target_rotation := Vector3.ZERO

var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_scales: Dictionary = {}

var _detail_card: Card3D = null
var _detail_tween_running := false


func _ready() -> void:
	_build_collection()
	
func _process(delta: float) -> void:
	if _detail_card == null:
		return

	if _detail_tween_running:
		return

	if not is_instance_valid(_detail_card):
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size

	var centered := Vector2(
		(mouse_pos.x / viewport_size.x) * 2.0 - 1.0,
		(mouse_pos.y / viewport_size.y) * 2.0 - 1.0
	)

	var target_rot := detail_rotation + Vector3(
		centered.y * detail_mouse_tilt_strength,
		centered.x * detail_mouse_tilt_strength,
		0.0
	)

	_detail_card.rotation_degrees = _detail_card.rotation_degrees.lerp(
		target_rot,
		delta * detail_mouse_tilt_smooth
	)


func _build_collection() -> void:
	for child in cards_root.get_children():
		child.queue_free()

	_base_positions.clear()
	_base_rotations.clear()
	_base_scales.clear()
	_detail_card = null

	var owned := CollectionManager.get_owned_cards()
	empty_label.visible = owned.is_empty()

	if owned.is_empty():
		return

	var index := 0
	for card_id in owned.keys():
		var amount := CollectionManager.get_amount(card_id)
		var data := CardDatabase.get_card(card_id)
		if data.is_empty():
			continue

		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.setup(data)

		var target_pos := _grid_position(index)
		var target_rot := Vector3(-18, 0, 0)

		_base_positions[card] = target_pos
		_base_rotations[card] = target_rot
		_base_scales[card] = card.scale

		_add_amount_label(card, amount)
		_spawn_card(card, target_pos, target_rot, index)

		index += 1


func _grid_position(index: int) -> Vector3:
	var column := index % COLUMNS
	var row := index / COLUMNS
	return Vector3((column - (COLUMNS - 1) * 0.5) * CARD_SPACING.x, 0.0, -row * CARD_SPACING.z)


func _add_amount_label(card: Card3D, amount: int) -> void:
	var label := Label3D.new()
	var font := load("res://fonts/VCR_OSD_MONO_1.001.ttf") as FontFile
	label.font = font
	label.name = "AmountLabel"
	label.text = "x" + str(amount)
	label.position = Vector3(0.28, -0.48, 0.1)
	label.pixel_size = 0.008
	label.font_size = 24
	label.outline_size = 5
	card.add_child(label)

func _spawn_card(card: Card3D, target_pos: Vector3, target_rot: Vector3, index: int) -> void:
	var base_scale: Vector3 = _base_scales[card]

	card.position = target_pos + Vector3(0, -spawn_rise_height, 0)
	card.rotation_degrees = target_rot
	card.scale = base_scale * 0.01

	var delay := index * spawn_stagger

	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", target_pos, spawn_duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card, "scale", base_scale, spawn_duration).set_delay(delay).set_trans(Tween.TRANS_BACK)

	await tween.finished

	if not is_instance_valid(card):
		return

	_connect_card_input(card)


func _connect_card_input(card: Card3D) -> void:
	if not card.area:
		return

	if not card.area.mouse_entered.is_connected(_on_card_hovered):
		card.area.mouse_entered.connect(_on_card_hovered.bind(card))
	if not card.area.mouse_exited.is_connected(_on_card_unhovered):
		card.area.mouse_exited.connect(_on_card_unhovered.bind(card))
	if not card.area.input_event.is_connected(_on_card_input):
		card.area.input_event.connect(_on_card_input.bind(card))


# --- Hover ------------------------------------------------------------

func _on_card_hovered(card: Card3D) -> void:
	# Waehrend eine Detailansicht offen ist, reagiert keine Karte (auch
	# nicht die Detailkarte selbst) auf Hover.
	if _detail_card != null:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	var base_pos: Vector3 = _base_positions[card]
	var base_scale: Vector3 = _base_scales[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos + hover_lift, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rotation, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale * hover_scale, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_card_unhovered(card: Card3D) -> void:
	if _detail_card != null:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	var base_pos: Vector3 = _base_positions[card]
	var base_rot: Vector3 = _base_rotations[card]
	var base_scale: Vector3 = _base_scales[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", base_rot, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Detailansicht -----------------------------------------------------

func _on_card_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, card: Card3D) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	if _detail_tween_running:
		return

	if _detail_card == card:
		_close_detail_card()
	elif _detail_card == null:
		_open_detail_card(card)
	else:
		# Eine andere Karte ist bereits in der Detailansicht offen —
		# erst diese schliessen, dann die neue oeffnen.
		_close_detail_card()
		_open_detail_card(card)


func _open_detail_card(card: Card3D) -> void:
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	_detail_card = card
	_detail_target_rotation = detail_rotation
	_detail_tween_running = true

	var base_scale: Vector3 = _base_scales[card]
	var target_pos := camera.global_transform * detail_offset_from_camera
	var target_scale := base_scale * detail_scale

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "global_position", target_pos, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", detail_rotation, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", target_scale, detail_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished
	_detail_tween_running = false


func _close_detail_card() -> void:
	var card := _detail_card
	if not is_instance_valid(card) or not _base_positions.has(card):
		_detail_card = null
		return

	_detail_card = null
	_detail_tween_running = true

	var base_pos: Vector3 = _base_positions[card]
	var base_rot: Vector3 = _base_rotations[card]
	var base_scale: Vector3 = _base_scales[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "global_position", card.get_parent().to_global(base_pos), detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", base_rot, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await tween.finished
	_detail_tween_running = false


func _unhandled_input(event: InputEvent) -> void:
	if _detail_card == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_detail_card()
