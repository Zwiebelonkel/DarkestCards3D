extends Node3D
class_name CollectionScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

const RARITY_ORDER := [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
	"mythic",
	"exotic",
]

const RARITY_NAMES := {
	"common": "COMMON",
	"uncommon": "UNCOMMON",
	"rare": "RARE",
	"epic": "EPIC",
	"legendary": "LEGENDARY",
	"mythic": "MYTHIC",
	"exotic": "EXOTIC",
}
@onready var card_hover_sfx: AudioStreamPlayer = $CardHoverSFX
@onready var fly_sfx: AudioStreamPlayer = $CardRemoveSFX


@export_group("Layout")
@export var card_spacing_x := 0.95
@export var row_spacing_z := 1.25
@export var row_start_x := -2.0
@export var row_label_x := -3.2
@export var row_label_y := 0.1
@export var row_scroll_step := 0.45
@export var row_scroll_duration := 0.15
@export var row_visible_width := 4.2

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

@export_group("Detail Mouse Tilt")
@export var detail_mouse_tilt_strength := 50.0
@export var detail_mouse_tilt_smooth := 10.0

@export_group("Deck Button")
@export var deck_button_scene: PackedScene
@export var deck_button_offset_right := 0.95
@export var deck_button_offset_up := -0.25
@export var deck_button_offset_forward := 0.0
@export var deck_button_scale := 0.45
@export var deck_button_rotation := Vector3(-27.78, 0, 0)
@export var add_button_slide_offset := Vector3(1.4, 0, 0)
@export var add_button_slide_duration := 0.22

var _deck_button_base_pos := Vector3.ZERO
var _deck_button_tween: Tween = null

@export_group("Deck Overview Button")
@export var deck_overview_button_scene: PackedScene
@export var deck_overview_button_position := Vector3(3.6, 0.4, 1.2)
@export var deck_overview_button_rotation := Vector3(-27.78, 0, 0)
@export var deck_overview_button_scale := 0.55
@export var deck_overview_label := "DECK ANSEHEN"

@export_group("Deck Fan View")
@export var deck_fan_offset_from_camera := Vector3(0, -0.35, -2.4)
@export var deck_fan_card_scale := 0.62
@export var deck_fan_radius := 3.6
@export var deck_fan_max_angle_degrees := 64.0
@export var deck_fan_base_tilt := Vector3(-55, 0, 0)
@export var deck_fan_rise_height := 1.2
@export var deck_fan_duration := 0.4
@export var deck_fan_stagger := 0.02
@export var deck_fan_card_angle_spacing := 8.5
@export var deck_fan_min_x_spacing := 0.42
@export var deck_fan_reflow_duration := 0.22
@export var deck_fan_depth_spacing := 0.035

@export_group("Deck Fan Drag Remove")
@export var fan_drag_remove_distance := 0.75
@export var fan_drag_pull_strength := 0.65
@export var fan_drag_max_pull := 1.15
@export var fan_drag_scale := 1.08



var _dragged_fan_card: Card3D = null
var _dragged_fan_card_id := ""
var _drag_start_pos := Vector3.ZERO

@export var camera: Camera3D
@onready var cards_root: Node3D = $Cards
@onready var empty_label: Label3D = $EmptyLabel


var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_scales: Dictionary = {}
var _card_rarities: Dictionary = {}
var _row_cards: Dictionary = {}
var _row_scroll_offsets: Dictionary = {}
var _hovered_rarity: String = ""

var _detail_card: Card3D = null
var _detail_tween_running := false
var _detail_switch_tween: Tween = null
var _detail_card_id := ""
@onready var _deck_button: Table3DButton = $AddToDeckButton
@onready var _deck_overview_button: Table3DButton = $ShowDeckButton
var _deck_fan_open := false
var _deck_fan_tween_running := false
var _deck_fan_cards: Array[Card3D] = []
var _deck_fan_base_transforms: Dictionary = {}


func _ready() -> void:
	if not CardUpgradeManager.upgrades_changed.is_connected(_on_card_upgrades_changed):
		CardUpgradeManager.upgrades_changed.connect(_on_card_upgrades_changed)
	_build_collection()
	_setup_deck_overview_button()
	_deck_button_base_pos = _deck_button.position
	_deck_button.visible = false


func _process(delta: float) -> void:
	if _dragged_fan_card != null:
		_update_dragged_fan_card()
		return
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
	_card_rarities.clear()
	_row_cards.clear()
	_row_scroll_offsets.clear()
	_hovered_rarity = ""
	_detail_card = null

	for rarity in RARITY_ORDER:
		_row_cards[rarity] = []
		_row_scroll_offsets[rarity] = 0.0

	var owned := CollectionManager.get_owned_cards()
	empty_label.visible = owned.is_empty()

	if owned.is_empty():
		return

	for card_id in owned.keys():
		var available_amount := _get_available_amount(card_id)

		var data := CardDatabase.get_card(card_id)
		if data.is_empty():
			continue

		var rarity := str(data.get("rarity", "common")).to_lower()
		if not _row_cards.has(rarity):
			rarity = "common"

		_row_cards[rarity].append({
			"id": card_id,
			"data": data,
			"amount": _get_available_amount(card_id),
		})

	var global_index := 0

	for row_index in range(RARITY_ORDER.size()):
		var rarity: String = RARITY_ORDER[row_index]
		_add_rarity_label(rarity, row_index)

		var cards: Array = _row_cards[rarity]

		for i in range(cards.size()):
			var entry: Dictionary = cards[i]
			var card := CARD_SCENE.instantiate() as Card3D
			cards_root.add_child(card)
			var upgraded_data := CardUpgradeManager.apply_upgrades(str(entry["id"]), entry["data"])
			card.setup(upgraded_data)

			var target_pos := _row_card_position(rarity, i)
			var target_rot := Vector3(-18, 0, 0)

			_base_positions[card] = target_pos
			_base_rotations[card] = target_rot
			_base_scales[card] = card.scale
			_card_rarities[card] = rarity

			_add_amount_label(card, int(entry["amount"]))
			_spawn_card(card, target_pos, target_rot, global_index)

			cards[i] = card
			global_index += 1

		_row_cards[rarity] = cards


func _add_rarity_label(rarity: String, row_index: int) -> void:
	var label := Label3D.new()
	label.name = "RarityLabel_" + rarity
	label.text = str(RARITY_NAMES.get(rarity, rarity.to_upper()))
	label.font = VCR_FONT
	label.font_size = 26
	label.outline_size = 6
	label.pixel_size = 0.008
	label.position = Vector3(row_label_x, row_label_y, -row_index * row_spacing_z)
	label.rotation_degrees = Vector3(-18, 0, 0)
	cards_root.add_child(label)


func _row_card_position(rarity: String, index: int) -> Vector3:
	var row_index := RARITY_ORDER.find(rarity)
	if row_index < 0:
		row_index = 0

	var scroll_offset: float = _row_scroll_offsets.get(rarity, 0.0)

	return Vector3(
		row_start_x + index * card_spacing_x + scroll_offset,
		0.0,
		-row_index * row_spacing_z
	)


func _add_amount_label(card: Card3D, amount: int) -> void:
	var label := Label3D.new()
	label.font = VCR_FONT
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


func _on_card_hovered(card: Card3D) -> void:
	if _detail_card != null:
		return
	if _deck_fan_open:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	_hovered_rarity = str(_card_rarities.get(card, ""))

	var base_pos: Vector3 = _base_positions[card]
	var base_scale: Vector3 = _base_scales[card]
	
	_play_card_hover_sfx()

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos + hover_lift, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rotation, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale * hover_scale, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_card_unhovered(card: Card3D) -> void:
	if _detail_card != null:
		return
	if _deck_fan_open:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	if _hovered_rarity == str(_card_rarities.get(card, "")):
		_hovered_rarity = ""

	var base_pos: Vector3 = _base_positions[card]
	var base_rot: Vector3 = _base_rotations[card]
	var base_scale: Vector3 = _base_scales[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", base_pos, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", base_rot, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _scroll_row(rarity: String, direction: int) -> void:
	if rarity == "":
		return
	if not _row_cards.has(rarity):
		return

	var cards: Array = _row_cards[rarity]
	if cards.is_empty():
		return

	var min_offset :float= min(0.0, row_visible_width - float(cards.size()) * card_spacing_x)
	var current_offset: float = _row_scroll_offsets.get(rarity, 0.0)

	current_offset += float(direction) * row_scroll_step
	current_offset = clamp(current_offset, min_offset, 0.0)

	_row_scroll_offsets[rarity] = current_offset

	for i in range(cards.size()):
		var card: Card3D = cards[i]
		if not is_instance_valid(card):
			continue

		var new_pos := _row_card_position(rarity, i)
		_base_positions[card] = new_pos

		if card == _detail_card:
			continue

		var tween := create_tween()
		tween.tween_property(card, "position", new_pos, row_scroll_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_card_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, card: Card3D) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	if _deck_fan_open:
		return

	if _detail_tween_running:
		return

	# Während der Deck-Button sichtbar ist, schwebt er direkt neben/vor der
	# Detailkarte. Godots Area3D-Picking ruft input_event auf ALLEN getroffenen
	# Areas auf (nicht nur der vordersten) – ein Klick, der eigentlich den
	# Button treffen soll, kann also ZUSÄTZLICH die Karten-Area3D der Detail-
	# karte selbst treffen. Ohne diese Sperre würde das hier _close_detail_card()
	# auslösen, noch bevor/während der Button-Klick verarbeitet wird, wodurch
	# der Button sofort wieder verschwindet, bevor er reagieren kann.
	if _deck_button != null and is_instance_valid(_deck_button) and card == _detail_card:
		return

	get_viewport().set_input_as_handled()

	if _detail_card == card:
		_close_detail_card()
	elif _detail_card == null:
		_open_detail_card(card)
	else:
		_close_detail_card()
		_open_detail_card(card)


func _open_detail_card(card: Card3D) -> void:
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	_detail_card = card
	_detail_tween_running = true

	var base_scale: Vector3 = _base_scales[card]
	var target_pos := camera.global_transform * detail_offset_from_camera
	var target_scale := base_scale * detail_scale

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "global_position", target_pos, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", detail_rotation, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", target_scale, detail_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_detail_card_id = str(card.card_data.get("id", card.card_data.get("card_id", "")))
	_show_deck_button(card)

	await tween.finished
	_detail_tween_running = false


func _close_detail_card() -> void:
	_hide_deck_button()
	_detail_card_id = ""
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
	# ---------------------------------------------------------
	# Karte aus dem Deck ziehen
	# ---------------------------------------------------------
	if _dragged_fan_card != null:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_release_drag_fan_card()

		get_viewport().set_input_as_handled()
		return


	# ---------------------------------------------------------
	# Deck-Fan geöffnet
	# ---------------------------------------------------------
	if _deck_fan_open:
		if event is InputEventMouseButton:
			# Scroll ignorieren
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				return

			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return

			# Nur Linksklick behandeln
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

				# Klick auf irgendein 3D-Objekt?
				# Dann NICHT schließen.
				if _mouse_hits_interactive_3d():
					return

				# Wirklich daneben geklickt
				_close_deck_fan()
				return

		return
		
	if _detail_card != null:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_show_next_detail_card(-1)
				get_viewport().set_input_as_handled()
				return

			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_show_next_detail_card(1)
				get_viewport().set_input_as_handled()
				return


	# ---------------------------------------------------------
	# Collection scrollen
	# ---------------------------------------------------------
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_row(_hovered_rarity, 1)
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_row(_hovered_rarity, -1)
			return


	# ---------------------------------------------------------
	# Detailkarte
	# ---------------------------------------------------------
	if _detail_card == null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

			if _mouse_hits_interactive_3d():
				return

			_close_detail_card()

# ---------------------------------------------------------------------------
# Deck-Button (im Detail-View, "ADD TO DECK")
# ---------------------------------------------------------------------------

func _show_deck_button(_card: Card3D) -> void:
	if _detail_card_id == "":
		return

	if not _deck_button.pressed.is_connected(_on_add_to_deck_pressed):
		_deck_button.pressed.connect(_on_add_to_deck_pressed)

	if _deck_button_tween:
		_deck_button_tween.kill()

	_deck_button.visible = true
	_deck_button.position = _deck_button_base_pos + add_button_slide_offset
	_deck_button.scale = Vector3.ONE * 0.01

	_update_deck_button_state()

	_deck_button_tween = create_tween().set_parallel(true)
	_deck_button_tween.tween_property(_deck_button, "position", _deck_button_base_pos, add_button_slide_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	_deck_button_tween.tween_property(_deck_button, "scale", Vector3.ONE, add_button_slide_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

func _update_deck_button_state() -> void:
	if _deck_button == null:
		return

	if DeckManager.is_full():
		_deck_button.label_text = "DECK FULL"
		_deck_button.set_disabled(true)
		return

	if not DeckManager.can_add_card(_detail_card_id):
		_deck_button.label_text = "MAX OWNED"
		_deck_button.set_disabled(true)
		return

	var amount_in_deck := DeckManager.get_card_count(_detail_card_id)
	_deck_button.label_text = "ADD TO DECK " + str(amount_in_deck) + "/" + str(CollectionManager.get_amount(_detail_card_id))
	_deck_button.set_disabled(false)


func _on_add_to_deck_pressed() -> void:
	get_viewport().set_input_as_handled()

	if _detail_card_id == "":
		return

	var added := DeckManager.add_card(_detail_card_id)

	if added:
		empty_label.text = "Deck: %d / %d" % [DeckManager.battle_deck.size(), DeckManager.MAX_DECK_SIZE]
		_refresh_collection_amount_labels()
		_update_deck_button_state()
	else:
		empty_label.text = "Karte konnte nicht hinzugefügt werden"

	_update_deck_button_state()


# ---------------------------------------------------------------------------
# Deck-Übersicht-Button (fest in der Szene, öffnet den Fan-View)
# ---------------------------------------------------------------------------

func _setup_deck_overview_button() -> void:
	_deck_overview_button.visible = true
	_deck_overview_button.label_text = deck_overview_label

	if not _deck_overview_button.pressed.is_connected(_on_deck_overview_pressed):
		_deck_overview_button.pressed.connect(_on_deck_overview_pressed)
		
func _on_deck_overview_pressed() -> void:
	# Selbes Prinzip wie beim ADD-TO-DECK-Button: Klick sofort als verarbeitet
	# markieren, damit er nicht in _unhandled_input weiterläuft und den
	# Fan-View, der gerade erst geöffnet wird, im selben Frame wieder schließt.
	get_viewport().set_input_as_handled()

	if _deck_fan_tween_running:
		return

	if _deck_fan_open:
		_close_deck_fan()
	else:
		_open_deck_fan()


func _open_deck_fan() -> void:
	if _detail_card != null:
		_close_detail_card()

	var deck_ids: Array[String] = DeckManager.get_deck_cards()
	if deck_ids.is_empty():
		empty_label.text = "Dein Deck ist leer"
		return

	_deck_fan_open = true
	_deck_fan_tween_running = true
	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()

	var count: int = deck_ids.size()

	for i: int in range(count):
		var card_id: String = deck_ids[i]
		var data: Dictionary = CardDatabase.get_card(card_id)

		if data.is_empty():
			continue

		var card: Card3D = CARD_SCENE.instantiate() as Card3D
		add_child(card)
		var upgraded_data := CardUpgradeManager.apply_upgrades(card_id, data)
		card.setup(upgraded_data)

		var fan_transform: Dictionary = _calculate_fan_transform(i, count)

		var target_pos: Vector3 = fan_transform["position"]
		var target_rot: Vector3 = fan_transform["rotation"]
		var target_scale: Vector3 = fan_transform["scale"]

		card.global_position = target_pos + Vector3(0, -deck_fan_rise_height, 0)
		card.rotation_degrees = target_rot
		card.scale = target_scale * 0.01

		_deck_fan_base_transforms[card] = fan_transform
		_deck_fan_cards.append(card)

		var delay: float = float(i) * deck_fan_stagger

		var tween: Tween = create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(
			card,
			"global_position",
			target_pos,
			deck_fan_duration
		).set_delay(delay).set_trans(Tween.TRANS_BACK)

		tween.tween_property(
			card,
			"scale",
			target_scale,
			deck_fan_duration
		).set_delay(delay).set_trans(Tween.TRANS_BACK)

		_connect_fan_card_input(card, card_id)

	var last_delay: float = 0.0
	if count > 0:
		last_delay = float(count - 1) * deck_fan_stagger

	await get_tree().create_timer(last_delay + deck_fan_duration).timeout
	_deck_fan_tween_running = false

func _connect_fan_card_input(card: Card3D, card_id: String) -> void:
	if not card.area:
		return

	card.area.input_event.connect(_on_fan_card_input.bind(card, card_id))


func _on_fan_card_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int,
	card: Card3D,
	card_id: String
) -> void:
	if _deck_fan_tween_running:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag_fan_card(card, card_id)
			else:
				_release_drag_fan_card()

		get_viewport().set_input_as_handled()


func _remove_card_from_fan(card: Card3D, card_id: String) -> void:
	DeckManager.remove_card(card_id)

	_deck_fan_cards.erase(card)
	_deck_fan_base_transforms.erase(card)
	_play_fly_sfx()

	if is_instance_valid(card):
		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(card, "global_position", card.global_position + Vector3(0, -deck_fan_rise_height, 0), 0.22).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card, "scale", card.scale * 0.01, 0.22).set_trans(Tween.TRANS_CUBIC)
		tween.finished.connect(func():
			if is_instance_valid(card):
				card.queue_free()
		)

	empty_label.text = "Deck: %d / %d" % [
		DeckManager.battle_deck.size(),
		DeckManager.MAX_DECK_SIZE
	]

	_refresh_collection_amount_labels()

	if _deck_fan_cards.is_empty():
		_deck_fan_open = false
		return

	_reflow_deck_fan()

func _close_deck_fan() -> void:
	if not _deck_fan_open:
		return

	_deck_fan_open = false
	_deck_fan_tween_running = true

	var cards_to_close := _deck_fan_cards.duplicate()
	_deck_fan_cards.clear()

	for card in cards_to_close:
		if not is_instance_valid(card):
			continue

		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(card, "position", card.position + Vector3(0, -deck_fan_rise_height, 0), 0.22).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card, "scale", card.scale * 0.01, 0.22).set_trans(Tween.TRANS_CUBIC)
		tween.finished.connect(func():
			if is_instance_valid(card):
				card.queue_free()
		)

	_deck_fan_base_transforms.clear()

	await get_tree().create_timer(0.24).timeout
	_deck_fan_tween_running = false
	
func _mouse_hits_interactive_3d() -> bool:
	if camera == null:
		return false

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 100.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return false

	var collider :Object = result.get("collider")

	if collider == null:
		return false

	if collider is Area3D:
		return true

	return false


func _get_available_amount(card_id: String) -> int:
	return max(
		CollectionManager.get_amount(card_id) - DeckManager.get_card_count(card_id),
		0
	)
	
func _start_drag_fan_card(card: Card3D, card_id: String) -> void:
	if not is_instance_valid(card):
		return

	_dragged_fan_card = card
	_dragged_fan_card_id = card_id
	_drag_start_pos = card.global_position

	if _deck_fan_base_transforms.has(card):
		var base: Dictionary = _deck_fan_base_transforms[card]
		_drag_start_pos = base["position"]


func _update_dragged_fan_card() -> void:
	if not is_instance_valid(_dragged_fan_card):
		_dragged_fan_card = null
		_dragged_fan_card_id = ""
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)

	var plane := Plane(camera.global_basis.z, _drag_start_pos)
	var hit: Variant = plane.intersects_ray(from, dir)

	if hit == null:
		return

	var hit_pos: Vector3 = hit as Vector3
	var pull_vec: Vector3 = hit_pos - _drag_start_pos

	var pull_distance: float = min(pull_vec.length() * fan_drag_pull_strength, fan_drag_max_pull)

	if pull_vec.length() > 0.001:
		pull_vec = pull_vec.normalized() * pull_distance
	else:
		pull_vec = Vector3.ZERO

	var base: Dictionary = _deck_fan_base_transforms.get(_dragged_fan_card, {})
	var base_rot: Vector3 = base.get("rotation", _dragged_fan_card.rotation_degrees)
	var base_scale: Vector3 = base.get("scale", Vector3.ONE * deck_fan_card_scale)

	_dragged_fan_card.global_position = _drag_start_pos + pull_vec
	_dragged_fan_card.rotation_degrees = base_rot
	_dragged_fan_card.scale = base_scale * fan_drag_scale

func _release_drag_fan_card() -> void:
	if _dragged_fan_card == null:
		return

	var card: Card3D = _dragged_fan_card
	var card_id: String = _dragged_fan_card_id

	_dragged_fan_card = null
	_dragged_fan_card_id = ""

	if not is_instance_valid(card):
		return

	var distance: float = card.global_position.distance_to(_drag_start_pos)

	if distance >= fan_drag_remove_distance:
		_remove_card_from_fan(card, card_id)
	else:
		_snap_fan_card_back(card)

func _snap_fan_card_back(card: Card3D) -> void:
	if not is_instance_valid(card):
		return
	if not _deck_fan_base_transforms.has(card):
		return

	var base: Dictionary = _deck_fan_base_transforms[card]
	var base_pos: Vector3 = base["position"]
	var base_rot: Vector3 = base["rotation"]
	var base_scale: Vector3 = base["scale"]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "global_position", base_pos, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", base_rot, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	
func _refresh_collection_amount_labels() -> void:
	for card in _base_positions.keys():
		if not is_instance_valid(card):
			continue

		var card_id: String = str(card.card_data.get("id", card.card_data.get("card_id", "")))
		var amount: int = _get_available_amount(card_id)

		var label := card.get_node_or_null("AmountLabel") as Label3D
		if label:
			label.text = "x" + str(amount)

			if amount <= 0:
				label.modulate = Color(1.0, 0.3, 0.3) # Rot
			else:
				label.modulate = Color.WHITE

		card.set_disabled(amount <= 0)


func _calculate_fan_transform(index: int, count: int) -> Dictionary:
	var center_pos: Vector3 = camera.global_transform * deck_fan_offset_from_camera

	var angle_span: float = 0.0
	if count > 1:
		angle_span = min(deck_fan_max_angle_degrees, float(count - 1) * deck_fan_card_angle_spacing)

	var angle_step: float = 0.0 if count <= 1 else angle_span / float(count - 1)
	var start_angle: float = -angle_span * 0.5

	var angle_deg: float = start_angle + angle_step * index
	var angle_rad: float = deg_to_rad(angle_deg)

	var arc_offset := Vector3(
		sin(angle_rad) * deck_fan_radius,
		cos(angle_rad) * deck_fan_radius - deck_fan_radius,
		0.0
	)

	var spread_x: float = (float(index) - float(count - 1) * 0.5) * deck_fan_min_x_spacing

	var center_index: float = float(count - 1) * 0.5
	var distance_from_center: float = abs(float(index) - center_index)
	var depth_offset: float = distance_from_center * deck_fan_depth_spacing
	var local_target_pos: Vector3 = center_pos \
		+ camera.global_basis.x * (arc_offset.x + spread_x) \
		+ camera.global_basis.y * arc_offset.y \
		- camera.global_basis.z * depth_offset

	var target_rot: Vector3 = deck_fan_base_tilt + Vector3(0, 0, -angle_deg)

	return {
		"position": local_target_pos,
		"rotation": target_rot,
		"scale": Vector3.ONE * deck_fan_card_scale,
	}
	
func _reflow_deck_fan() -> void:
	var valid_cards: Array[Card3D] = []

	for card in _deck_fan_cards:
		if card != null and is_instance_valid(card):
			valid_cards.append(card)

	_deck_fan_cards = valid_cards

	var count: int = _deck_fan_cards.size()

	for i in range(count):
		var card: Card3D = _deck_fan_cards[i]

		if card == _dragged_fan_card:
			continue

		var fan_transform: Dictionary = _calculate_fan_transform(i, count)

		_deck_fan_base_transforms[card] = fan_transform

		var target_pos: Vector3 = fan_transform["position"]
		var target_rot: Vector3 = fan_transform["rotation"]
		var target_scale: Vector3 = fan_transform["scale"]

		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "global_position", target_pos, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", target_rot, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", target_scale, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func refresh_collection() -> void:
	_build_collection()

func _hide_deck_button() -> void:
	if _deck_button == null:
		return

	if _deck_button_tween:
		_deck_button_tween.kill()

	_deck_button_tween = create_tween().set_parallel(true)
	_deck_button_tween.tween_property(_deck_button, "position", _deck_button_base_pos + add_button_slide_offset, 0.16)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN)

	_deck_button_tween.tween_property(_deck_button, "scale", Vector3.ONE * 0.01, 0.16)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN)

	_deck_button_tween.finished.connect(func():
		if _deck_button != null:
			_deck_button.visible = false
			_deck_button.position = _deck_button_base_pos
			_deck_button.scale = Vector3.ONE
	)
	
func _show_next_detail_card(direction: int) -> void:
	if _detail_card == null:
		return
	_play_card_hover_sfx()
	# Falls gerade eine Karte vom letzten Wechsel noch "im Flug" zurück nach
	# Hause ist (ihr Rückflug-Tween läuft noch), lassen wir den einfach
	# weiterlaufen – er gehört nicht zum _detail_switch_tween und wird hier
	# nicht gekillt. Nur den Wechsel-Tween (alte->Detail raus, neue->Detail
	# rein) killen wir, falls er noch läuft.
	if _detail_switch_tween:
		_detail_switch_tween.kill()
		_detail_switch_tween = null

	_detail_tween_running = false

	var all_cards: Array[Card3D] = []

	for rarity in RARITY_ORDER:
		if not _row_cards.has(rarity):
			continue

		for card in _row_cards[rarity]:
			if card != null and is_instance_valid(card):
				all_cards.append(card)

	if all_cards.size() <= 1:
		return

	var current_index := all_cards.find(_detail_card)
	if current_index == -1:
		return

	var next_index := current_index + direction

	if next_index < 0:
		next_index = all_cards.size() - 1
	elif next_index >= all_cards.size():
		next_index = 0

	var old_card := _detail_card
	var new_card := all_cards[next_index]

	if old_card == new_card:
		return

	_hide_deck_button()

	_detail_tween_running = true
	_detail_card = new_card
	_detail_card_id = str(new_card.card_data.get("id", new_card.card_data.get("card_id", "")))

	var detail_pos := camera.global_transform * detail_offset_from_camera

	var old_base_pos: Vector3 = _base_positions[old_card]
	var old_base_rot: Vector3 = _base_rotations[old_card]
	var old_base_scale: Vector3 = _base_scales[old_card]

	var new_base_scale: Vector3 = _base_scales[new_card]
	var new_detail_scale := new_base_scale * detail_scale

	var move_dir := -float(direction)
	var side_offset := camera.global_basis.x * 1.7 * move_dir

	new_card.global_position = detail_pos - side_offset
	new_card.rotation_degrees = detail_rotation
	new_card.scale = new_detail_scale * 0.85

	# ------------------------------------------------------------------
	# Alte Karte: eigener, unabhängiger Tween direkt zurück zur Basis-
	# Position. Läuft komplett losgelöst vom restlichen Wechsel-Tween,
	# damit ein erneutes Scrollen ihn nicht killt und die Karte mitten
	# in der Luft hängen bleibt.
	# ------------------------------------------------------------------
	var return_tween := create_tween().set_parallel(true)
	return_tween.tween_property(old_card, "global_position", old_card.get_parent().to_global(old_base_pos), detail_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	return_tween.tween_property(old_card, "rotation_degrees", old_base_rot, detail_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	return_tween.tween_property(old_card, "scale", old_base_scale, detail_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

	# ------------------------------------------------------------------
	# Neue Karte: fliegt von der Seite in die Detailposition.
	# ------------------------------------------------------------------
	_detail_switch_tween = create_tween().set_parallel(true)
	var tween := _detail_switch_tween

	tween.tween_property(new_card, "global_position", detail_pos, detail_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(new_card, "rotation_degrees", detail_rotation, detail_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(new_card, "scale", new_detail_scale, detail_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	tween.finished.connect(func():
		_detail_tween_running = false
		_detail_switch_tween = null
		_show_deck_button(new_card)
		)
		
func _play_card_hover_sfx() -> void:
	if card_hover_sfx == null:
		return
	
	if card_hover_sfx.playing:
		card_hover_sfx.stop()
	
	card_hover_sfx.play()
	
func _play_fly_sfx() -> void:
	if fly_sfx == null:
		return
	
	if fly_sfx.playing:
		fly_sfx.stop()
	
	fly_sfx.play()
	
func _on_card_upgrades_changed(card_id: String) -> void:
	call_deferred("_refresh_upgraded_card_everywhere", card_id)

func _refresh_upgraded_card_everywhere(card_id: String) -> void:
	var base_data := CardDatabase.get_card(card_id)
	if base_data.is_empty():
		return

	var upgraded_data := CardUpgradeManager.apply_upgrades(card_id, base_data)

	# Normale Collection-Karten aktualisieren
	for card in _base_positions.keys():
		if card == null or not is_instance_valid(card):
			continue

		var id := str(card.card_data.get("id", card.card_data.get("card_id", "")))
		if id != card_id:
			continue

		card.setup(upgraded_data)

	# Detailkarte aktualisieren, falls genau diese offen ist
	if _detail_card != null and is_instance_valid(_detail_card):
		var detail_id := str(_detail_card.card_data.get("id", _detail_card.card_data.get("card_id", "")))
		if detail_id == card_id:
			_detail_card.setup(upgraded_data)

	# Deck-Fan-Karten aktualisieren, falls der Fan offen ist
	for fan_card in _deck_fan_cards:
		if fan_card == null or not is_instance_valid(fan_card):
			continue

		var fan_id := str(fan_card.card_data.get("id", fan_card.card_data.get("card_id", "")))
		if fan_id != card_id:
			continue

		fan_card.setup(upgraded_data)

	_refresh_collection_amount_labels()

	if _deck_button != null and is_instance_valid(_deck_button):
		_update_deck_button_state()
