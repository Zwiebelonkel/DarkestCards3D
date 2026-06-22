extends Node3D
class_name PackOpeningScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const CARD_COUNT := 5

@onready var pack_mesh: MeshInstance3D = $Pack/PackMesh
@onready var pack_top: MeshInstance3D = $Pack/PackTop
@onready var pack_top_area: Area3D = $Pack/PackTop/PackTopArea
@onready var cards_root: Node3D = $Cards
@onready var info_label: Label3D = $InfoLabel

var _hovering_pack := false
var _opened := false
var _revealed_cards: Array[Card3D] = []
var _top_card: Card3D

func _ready() -> void:
	if pack_top_area:
		pack_top_area.mouse_entered.connect(func(): _hovering_pack = true)
		pack_top_area.mouse_exited.connect(func(): _hovering_pack = false)
		pack_top_area.input_event.connect(_on_pack_top_input)

	info_label.text = "PackTop anklicken/abziehen"

func _process(delta: float) -> void:
	if _opened or _hovering_pack:
		return

	$Pack.rotation.y += sin(Time.get_ticks_msec() * 0.002) * delta * 0.45
	$Pack.rotation.x = sin(Time.get_ticks_msec() * 0.0015) * 0.08

func _on_pack_top_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _opened:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_pack()

func _open_pack() -> void:
	_opened = true
	_hovering_pack = false
	info_label.text = "Wähle die oberste Karte"

	var top_tween := create_tween().set_parallel(true)
	top_tween.tween_property(pack_top, "position", Vector3(0, 1.15, -0.85), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_top, "rotation_degrees", Vector3(-70, 0, 15), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_mesh, "scale", Vector3(1.08, 0.9, 1.08), 0.25)

	await get_tree().create_timer(0.22).timeout
	_spawn_random_cards()

func _spawn_random_cards() -> void:
	var cards := CardDatabase.get_all_cards()
	cards.shuffle()

	for i in CARD_COUNT:
		var data: Dictionary = cards[i % cards.size()] if not cards.is_empty() else {}
		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.setup(data)
		card.position = Vector3(0, 0.05, 0)
		card.rotation_degrees = Vector3(-80, 0, randf_range(-8.0, 8.0))
		card.scale = Vector3.ONE * 0.01
		_revealed_cards.append(card)

		var final_pos := Vector3((i - 2) * 0.82, 1.05 + i * 0.08, -1.45 - abs(i - 2) * 0.12)
		var final_rot := Vector3(-18, 0, (i - 2) * -4.0)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", final_pos, 0.55 + i * 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", final_rot, 0.55 + i * 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector3.ONE, 0.35 + i * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_top_card = _revealed_cards[_revealed_cards.size() - 1] if not _revealed_cards.is_empty() else null
	if _top_card and _top_card.area:
		_top_card.area.input_event.connect(_on_top_card_input)

func _on_top_card_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _top_card:
		var card_id := str(_top_card.card_data.get("id", ""))
		if card_id != "":
			CollectionManager.add_card(card_id)
			info_label.text = str(_top_card.card_data.get("name", card_id)) + " zur Sammlung hinzugefügt"
			var tween := create_tween().set_parallel(true)
			tween.tween_property(_top_card, "position", Vector3(0, 2.2, -2.4), 0.35)
			tween.tween_property(_top_card, "scale", Vector3.ONE * 1.25, 0.2)
			_top_card.area.input_event.disconnect(_on_top_card_input)
