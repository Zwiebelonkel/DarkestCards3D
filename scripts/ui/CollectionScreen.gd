extends Node3D
class_name CollectionScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const CARD_SPACING := Vector3(0.95, 0.0, 1.25)
const COLUMNS := 5

@onready var cards_root: Node3D = $Cards
@onready var empty_label: Label3D = $EmptyLabel

var _base_positions: Dictionary = {}

func _ready() -> void:
	_build_collection()

func _build_collection() -> void:
	for child in cards_root.get_children():
		child.queue_free()
	_base_positions.clear()

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
		card.position = _grid_position(index)
		card.rotation_degrees = Vector3(-18, 0, 0)
		_base_positions[card] = card.position
		_add_amount_label(card, amount)

		if card.area:
			card.area.mouse_entered.connect(_on_card_hovered.bind(card))
			card.area.mouse_exited.connect(_on_card_unhovered.bind(card))

		index += 1

func _grid_position(index: int) -> Vector3:
	var column := index % COLUMNS
	var row := index / COLUMNS
	return Vector3((column - (COLUMNS - 1) * 0.5) * CARD_SPACING.x, 0.0, -row * CARD_SPACING.z)

func _add_amount_label(card: Card3D, amount: int) -> void:
	var label := Label3D.new()
	label.name = "AmountLabel"
	label.text = "x" + str(amount)
	label.position = Vector3(0.32, -0.52, -0.04)
	label.pixel_size = 0.25
	label.font_size = 28
	label.outline_size = 7
	card.add_child(label)

func _on_card_hovered(card: Card3D) -> void:
	var base_pos: Vector3 = _base_positions.get(card, card.position)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos + Vector3(0, 0.35, 0.38), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", Vector3(-8, 0, 0), 0.15)

func _on_card_unhovered(card: Card3D) -> void:
	var base_pos: Vector3 = _base_positions.get(card, card.position)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", Vector3(-18, 0, 0), 0.15)
