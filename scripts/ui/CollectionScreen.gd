extends Node3D
class_name CollectionScreen

signal slot_room_key_requested
signal angel_dialog_changed(opened: bool)

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const NEW_CARD_LABEL := preload("res://scripts/card/NewCardLabel.gd")
const EFFECT_OVERVIEW_SCENE := preload("res://scenes/CardEffectOverview.tscn")
const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const COLLECTION_CARD_WIDTH := 0.792
const COLLECTION_CARD_TILT := -18.0
const STARTING_HAND_VIEW := preload("res://scripts/ui/StartingHandSlots.gd")
const ANGEL_DIALOG_SCRIPT := preload("res://scripts/rooms/AngelDialogue.gd")
const DETAIL_ROTATION := preload("res://scripts/card/CardDetailRotation.gd")

const RARITY_ORDER := [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
	"mythic",
	"exotic",
	"secret",
]

const RARITY_NAMES := {
	"common": "COMMON",
	"uncommon": "UNCOMMON",
	"rare": "RARE",
	"epic": "EPIC",
	"legendary": "LEGENDARY",
	"mythic": "MYTHIC",
	"exotic": "EXOTIC",
	"secret": "SECRET",
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
@export_range(0.0, 0.3, 0.01) var row_stack_spread := 0.12
@export_range(0.01, 0.4, 0.01) var row_stack_depth := 0.18

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
var _deck_button_scene_transform := Transform3D.IDENTITY
var _deck_button_tween: Tween = null

@export_group("Deck Overview Button")
@export var deck_overview_button_scene: PackedScene
@export var deck_overview_button_position := Vector3(3.6, 0.4, 1.2)
@export var deck_overview_button_rotation := Vector3(-27.78, 0, 0)
@export var deck_overview_button_scale := 0.55
@export var deck_overview_label := "DECK ANSEHEN"

@export_group("Deck Fan View")
@export var deck_fan_offset_from_camera := Vector3(0, 0.47, -2.8)
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
var _drag_pointer_offset := Vector3.ZERO
var _starting_hand_view: StartingHandSlots
var _deck_input_suspended := false
var _collection_refresh_pending := false
var _slot_room_key_request_pending := false
var angel_dialog: ANGEL_DIALOG_SCRIPT
var _angel_context_enabled := true
var angel_presence_available: Callable

@export var camera: Camera3D
@onready var cards_root: Node3D = $Cards
@onready var empty_label: Label3D = $EmptyLabel
@onready var clear_deck_button: Table3DButton = $ClearDeckButton
@onready var random_deck_button: Table3DButton = $RandomDeckButton


var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_scales: Dictionary = {}
var _card_rarities: Dictionary = {}
var _row_cards: Dictionary = {}
var _row_scroll_offsets: Dictionary = {}
var _hovered_rarity: String = ""
var _hovered_cards: Dictionary = {}
var _card_hover_tweens: Dictionary = {}
var _effect_overview: CardEffectOverviewUI = null
var _effect_overview_layer: CanvasLayer = null

var _detail_card: Card3D = null
var _detail_tween_running := false
var _detail_switch_tween: Tween = null
var _detail_card_id := ""
var _detail_rotation := DETAIL_ROTATION.new()
var _view_close_requested := false
@onready var _deck_button: Table3DButton = $AddToDeckButton
@onready var _deck_overview_button: Table3DButton = $ShowDeckButton
var _deck_fan_open := false
var _deck_fan_tween_running := false
var _deck_fan_cards: Array[Card3D] = []
var _deck_fan_base_transforms: Dictionary = {}
var _deck_reflow_tweens: Dictionary = {}


func _ready() -> void:
	add_to_group("collection_screens")
	get_window().focus_exited.connect(_detail_rotation.stop)
	if not CardUpgradeManager.upgrades_changed.is_connected(_on_card_upgrades_changed):
		CardUpgradeManager.upgrades_changed.connect(_on_card_upgrades_changed)
	if not CollectionManager.collection_changed.is_connected(_on_collection_changed):
		CollectionManager.collection_changed.connect(_on_collection_changed)

	_build_collection()
	_setup_deck_overview_button()
	_setup_deck_management_buttons()

	_deck_button_base_pos = _deck_button.position
	_deck_button_scene_transform = _deck_button.transform
	_deck_button.visible = false

	clear_deck_button.visible = false
	random_deck_button.visible = false
	_setup_angel_dialog()
	GameCurrency.npc_rescue_changed.connect(_sync_angel_context)
	visibility_changed.connect(_sync_angel_context)


func _setup_angel_dialog() -> void:
	var actor := get_node_or_null("angel") as Sprite3D
	if actor == null:
		return
	angel_dialog = ANGEL_DIALOG_SCRIPT.new()
	angel_dialog.name = "AngelDialogue"
	angel_dialog.actor = actor
	angel_dialog.camera = camera
	angel_dialog.context_available = _angel_context_available
	add_child(angel_dialog)
	angel_dialog.modal_changed.connect(_on_angel_modal_changed)
	_sync_angel_context()


func is_angel_dialog_open() -> bool:
	return is_instance_valid(angel_dialog) and angel_dialog.is_dialog_open()


func set_angel_context_enabled(enabled: bool) -> void:
	_angel_context_enabled = enabled
	_sync_angel_context()


func _angel_context_available() -> bool:
	# The dialog's own input lock is separate from external suspension: an
	# already open conversation must not invalidate its own collection context.
	return (
		GameCurrency.is_npc_rescued("angel") and _angel_context_enabled and is_inside_tree() and is_visible_in_tree()
		and not get_tree().paused and not _deck_input_suspended
		and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera
		and _detail_card == null and not _detail_tween_running
		and not _deck_fan_open and not _deck_fan_tween_running
		and _dragged_fan_card == null and not _slot_room_key_request_pending
	)


func _sync_angel_context() -> void:
	if not is_instance_valid(angel_dialog):
		return
	angel_dialog.camera = camera
	angel_dialog.actor.visible = GameCurrency.is_npc_rescued("angel") and (not angel_presence_available.is_valid() or bool(angel_presence_available.call()))
	angel_dialog.set_interaction_enabled(_angel_context_available())


func _on_angel_modal_changed(opened: bool) -> void:
	if opened:
		_detail_rotation.stop()
		_reset_collection_hover()
		_hide_effect_overview()
	angel_dialog_changed.emit(opened)


func _process(delta: float) -> void:
	_sync_angel_context()
	if not _can_rotate_detail():
		_detail_rotation.stop()
	if is_angel_dialog_open():
		return
	_finish_requested_view_close()
	if _collection_refresh_pending and _can_refresh_collection():
		refresh_collection()
	if _dragged_fan_card != null:
		_update_dragged_fan_card()
		return
	if _detail_card == null:
		return
	if _detail_tween_running:
		return
	if not is_instance_valid(_detail_card):
		return
	if not _can_rotate_detail():
		return
	if _detail_rotation.has_rotated:
		_detail_rotation.apply(_detail_card, camera)
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
	_detail_rotation.reset()
	_reset_collection_hover()
	for child in cards_root.get_children():
		if child is Label3D:
			# Free the stable label name before rebuilding in the same frame.
			child.name = "RetiredLabel_" + str(child.get_instance_id())
			child.hide()
		child.queue_free()

	_base_positions.clear()
	_base_rotations.clear()
	_base_scales.clear()
	_card_rarities.clear()
	_row_cards.clear()
	_row_scroll_offsets.clear()
	_hovered_cards.clear()
	_hovered_rarity = ""
	_detail_card = null

	for rarity in RARITY_ORDER:
		_row_cards[rarity] = []
		_row_scroll_offsets[rarity] = 0.0

	var owned := CollectionManager.get_owned_cards()
	var display_cards := CollectionManager.get_display_cards(owned.keys())
	empty_label.text = "Noch keine Karten in der Sammlung"
	empty_label.visible = true

	for card_id in owned.keys():
		var data: Dictionary = display_cards.get(card_id, {})
		if data.is_empty() or CardData.is_upgrade_collection_card(data):
			continue
		empty_label.visible = false

		var rarity := str(data.get("rarity", "common")).to_lower()
		if not _row_cards.has(rarity):
			rarity = "common"

		_row_cards[rarity].append({
			"id": card_id,
			"data": data,
			"amount": _get_available_amount(card_id),
		})

	if empty_label.visible:
		if _has_received_secret():
			_add_rarity_label("secret", RARITY_ORDER.find("secret"))
		return

	var global_index := 0

	for row_index in range(RARITY_ORDER.size()):
		var rarity: String = RARITY_ORDER[row_index]
		if rarity != "secret" or _has_received_secret():
			_add_rarity_label(rarity, row_index)

		var cards: Array = _row_cards[rarity]

		for i in range(cards.size()):
			var entry: Dictionary = cards[i]
			var card := _create_collection_card(str(entry["id"]), rarity, i, entry["data"])
			var target_pos: Vector3 = _base_positions[card]
			var target_rot: Vector3 = _base_rotations[card]
			_spawn_card(card, target_pos, target_rot, global_index)

			cards[i] = card
			global_index += 1

		_row_cards[rarity] = cards


func _create_collection_card(card_id: String, rarity: String, index: int, data: Dictionary = {}) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	cards_root.add_child(card)
	card.setup(CardUpgradeManager.apply_upgrades(card_id, CollectionManager.get_display_card(card_id) if data.is_empty() else data))
	_refresh_new_card_label(card, card_id)
	card.position = _row_card_position(rarity, index)
	card.rotation_degrees = Vector3(COLLECTION_CARD_TILT, 0, 0)
	_base_positions[card] = card.position
	_base_rotations[card] = card.rotation_degrees
	_base_scales[card] = card.scale
	_card_rarities[card] = rarity
	_add_amount_label(card, _get_available_amount(card_id))
	return card


func _refresh_new_card_label(card: Card3D, card_id: String) -> void:
	var label := card.get_node_or_null("NewLabel") as Sprite3D
	if label != null and (label.is_queued_for_deletion() or not CollectionManager.is_card_new(card_id)):
		card.remove_child(label)
		label.queue_free()
		label = null
	if label == null and CollectionManager.is_card_new(card_id):
		var new_label := NEW_CARD_LABEL.new()
		new_label.name = "NewLabel"
		card.add_child(new_label)
		new_label.watch_collection_card(card_id)


func _has_received_secret() -> bool:
	for card_id: String in CollectionManager.get_discovered_card_ids():
		if CardDatabase.get_card(card_id).get("rarity") == "secret":
			return true
	return false


func _refresh_secret_cards() -> void:
	# A grant can arrive during physics picking or while another card is in
	# detail. Append immediately after input without rebuilding that active view.
	if _has_received_secret() and cards_root.get_node_or_null("RarityLabel_secret") == null:
		_add_rarity_label("secret", RARITY_ORDER.find("secret"))
	var existing := {}
	for card: Card3D in _row_cards.get("secret", []):
		if is_instance_valid(card):
			existing[str(card.card_data.get("id", ""))] = card
	var secret_ids: Array[String] = []
	for card_id: String in CollectionManager.get_owned_cards():
		if CardDatabase.get_card(card_id).get("rarity") == "secret":
			secret_ids.append(card_id)
	var display_cards := CollectionManager.get_display_cards(secret_ids)
	for card_id: String in display_cards:
		var data: Dictionary = display_cards[card_id]
		if data.get("rarity") != "secret" or CardData.is_upgrade_collection_card(data):
			continue
		if existing.has(card_id):
			var card := existing[card_id] as Card3D
			var updated := CardUpgradeManager.apply_upgrades(card_id, data)
			if card.card_data != updated:
				card.setup(updated)
			_refresh_new_card_label(card, card_id)
			continue
		var cards: Array = _row_cards["secret"]
		var card := _create_collection_card(card_id, "secret", cards.size(), data)
		cards.append(card)
		_connect_card_input(card)
		_update_collection_amount_visibility(card)
		empty_label.visible = _deck_fan_open
	for card_id: String in existing:
		if CollectionManager.get_amount(card_id) == 0:
			_collection_refresh_pending = true
	_refresh_collection_amount_labels()
	_update_deck_button_state()


func _add_rarity_label(rarity: String, row_index: int) -> void:
	var label := Label3D.new()
	label.name = "RarityLabel_" + rarity
	label.text = str(RARITY_NAMES.get(rarity, rarity.to_upper()))
	label.font = VCR_FONT
	label.font_size = 26
	label.outline_size = 6
	label.pixel_size = 0.008
	# Keep the existing label placement where it fits, with a clear gutter
	# before the fixed left edge of the card stack even for long rarity names.
	var text_width := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var label_right := minf(row_label_x + text_width * 0.5, row_start_x - COLLECTION_CARD_WIDTH * 0.5 - 0.18)
	label.position = Vector3(label_right, row_label_y, -row_index * row_spacing_z)
	label.rotation_degrees = Vector3(COLLECTION_CARD_TILT, 0, 0)
	cards_root.add_child(label)


func _row_card_position(rarity: String, index: int) -> Vector3:
	var row_index := RARITY_ORDER.find(rarity)
	if row_index < 0:
		row_index = 0

	var scroll_offset: float = _row_scroll_offsets.get(rarity, 0.0)
	var spacing := maxf(card_spacing_x, 0.01)
	var cards_passed := maxf(-scroll_offset / spacing, 0.0)
	# A bounded fan keeps even very long rows beside their rarity label.
	# Fractional progress makes cards enter and leave the pile continuously.
	var layer_step := minf(0.03, row_stack_depth / maxf(cards_passed, 1.0))
	var spread_step := minf(0.02, row_stack_spread / maxf(cards_passed, 1.0))
	var natural_x := row_start_x + index * spacing + scroll_offset
	var layer := minf(float(index), cards_passed)
	var stacked_x := row_start_x + layer * spread_step
	# Incoming cards stay in front of the pile while sliding onto its top.
	var depth := minf(layer * layer_step, row_stack_depth)
	var front := Vector3(0.0, -sin(deg_to_rad(COLLECTION_CARD_TILT)), cos(deg_to_rad(COLLECTION_CARD_TILT)))
	return Vector3(maxf(natural_x, stacked_x), 0.0, -row_index * row_spacing_z) + front * depth


func _row_min_scroll_offset(rarity: String) -> float:
	var count: int = _row_cards.get(rarity, []).size()
	# Include the final card's width, rather than an extra empty spacing cell.
	return minf(0.0, row_visible_width - (maxi(count - 1, 0) * maxf(card_spacing_x, 0.01) + COLLECTION_CARD_WIDTH))


func _is_card_buried_in_row(card: Card3D) -> bool:
	var rarity := str(_card_rarities.get(card, ""))
	var cards: Array = _row_cards.get(rarity, [])
	var index := cards.find(card)
	if index < 0:
		return false
	var offset: float = _row_scroll_offsets.get(rarity, 0.0)
	var top_index := mini(int(floor(maxf(-offset, 0.0) / maxf(card_spacing_x, 0.01))), cards.size() - 1)
	return index < top_index


func _update_collection_amount_visibility(card: Card3D, force_visible: bool = false) -> void:
	var label := card.get_node_or_null("AmountLabel") as Label3D
	if label != null:
		label.visible = force_visible or card == _detail_card or _hovered_cards.has(card) or not _is_card_buried_in_row(card)


func _get_scroll_rarity_at(mouse_position: Vector2) -> String:
	if camera == null or not is_visible_in_tree() or _detail_card != null or _detail_tween_running or _deck_fan_open or _deck_fan_tween_running:
		return ""
	if get_viewport().get_camera_3d() != camera:
		return ""
	var hit_card := _collection_card_under_mouse(mouse_position)
	if hit_card != null and _card_rarities.has(hit_card):
		return str(_card_rarities[hit_card])

	# Keep the row scrollable in its gaps and next to the pile, even when a
	# moving card's Area3D has just sent mouse_exited under a still pointer.
	var nearest_rarity := ""
	var nearest_distance := INF
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(COLLECTION_CARD_TILT))
	for rarity: String in RARITY_ORDER:
		if _row_cards.get(rarity, []).is_empty():
			continue
		var row_is_interactive := false
		for card: Card3D in _row_cards[rarity]:
			if is_instance_valid(card) and card.is_visible_in_tree() and card.area.input_ray_pickable:
				row_is_interactive = true
				break
		if not row_is_interactive:
			continue
		var row_z := -float(RARITY_ORDER.find(rarity)) * row_spacing_z
		var row_center := Vector3(row_start_x + (row_visible_width - COLLECTION_CARD_WIDTH) * 0.5, 0, row_z)
		var left := row_start_x - COLLECTION_CARD_WIDTH * 0.5 - 0.18
		var right := row_start_x + row_visible_width - COLLECTION_CARD_WIDTH * 0.5
		var corners := PackedVector2Array()
		for corner: Vector2 in [Vector2(left, -0.65), Vector2(right, -0.65), Vector2(right, 0.73), Vector2(left, 0.73)]:
			var local_corner := Vector3(corner.x, 0, row_z) + tilt * Vector3(0, corner.y, 0)
			corners.append(camera.unproject_position(cards_root.to_global(local_corner)))
		if Geometry2D.is_point_in_polygon(mouse_position, corners):
			var center_on_screen := camera.unproject_position(cards_root.to_global(row_center))
			var distance := absf(mouse_position.y - center_on_screen.y)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_rarity = rarity
	return nearest_rarity


func _add_amount_label(card: Card3D, amount: int) -> void:
	var label := Label3D.new()
	label.font = VCR_FONT
	label.name = "AmountLabel"
	label.text = "x" + str(amount)
	label.position = Vector3(0.36, 0.665, 0.1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.pixel_size = 0.005
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
	_card_hover_tweens[card] = tween
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", target_pos, spawn_duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card, "scale", base_scale, spawn_duration).set_delay(delay).set_trans(Tween.TRANS_BACK)

	tween.finished.connect(func() -> void:
		if is_instance_valid(card):
			_connect_card_input(card)
	)


func _connect_card_input(card: Card3D) -> void:
	if not card.area:
		return

	var hover_started := _on_card_hovered.bind(card)
	var hover_ended := _on_card_unhovered.bind(card)
	var input_received := _on_card_input.bind(card)
	if not card.area.mouse_entered.is_connected(hover_started):
		card.area.mouse_entered.connect(hover_started)
	if not card.area.mouse_exited.is_connected(hover_ended):
		card.area.mouse_exited.connect(hover_ended)
	if not card.area.input_event.is_connected(input_received):
		card.area.input_event.connect(input_received)
	if not card.card_hovered.is_connected(_on_effect_card_hovered):
		card.card_hovered.connect(_on_effect_card_hovered)
	if not card.card_unhovered.is_connected(_on_effect_card_unhovered):
		card.card_unhovered.connect(_on_effect_card_unhovered)


func _ensure_effect_overview() -> void:
	if _effect_overview != null and is_instance_valid(_effect_overview):
		return
	if _effect_overview_layer == null or not is_instance_valid(_effect_overview_layer):
		_effect_overview_layer = CanvasLayer.new()
		_effect_overview_layer.name = "EffectOverviewLayer"
		add_child(_effect_overview_layer)
	_effect_overview = EFFECT_OVERVIEW_SCENE.instantiate() as CardEffectOverviewUI
	_effect_overview_layer.add_child(_effect_overview)


func _on_effect_card_hovered(card: Card3D) -> void:
	if is_angel_dialog_open():
		return
	if _deck_fan_open and not _deck_fan_cards.has(card):
		return
	if _detail_card != null and card != _detail_card:
		return
	if _detail_card == null and not _deck_fan_open:
		var front_card := _collection_card_under_mouse(get_viewport().get_mouse_position())
		if front_card != null and front_card != card:
			return
	if CardData.get_active_effects(card.card_data).is_empty():
		return
	_ensure_effect_overview()
	if _effect_overview != null:
		_effect_overview.show_for_card(card)


func _on_effect_card_unhovered(card: Card3D) -> void:
	if _effect_overview != null:
		_effect_overview.hide_overview(card)


func _hide_effect_overview() -> void:
	if _effect_overview != null:
		_effect_overview.hide_overview()


func _on_card_hovered(card: Card3D) -> void:
	if is_angel_dialog_open() or _slot_room_key_request_pending or _deck_input_suspended or not is_visible_in_tree() or get_tree().paused:
		return
	if not is_instance_valid(camera) or get_viewport().get_camera_3d() != camera:
		return
	if _detail_card != null or _detail_tween_running:
		return
	if _deck_fan_open or _deck_fan_tween_running:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return
	if not card.is_visible_in_tree() or card.area == null or not card.area.input_ray_pickable:
		return
	var front_card := _collection_card_under_mouse(get_viewport().get_mouse_position())
	if front_card != null and front_card != card:
		return
	for previous_card: Variant in _hovered_cards.keys():
		if previous_card != card:
			_on_card_unhovered(previous_card)

	_hovered_rarity = str(_card_rarities.get(card, ""))
	if _hovered_cards.has(card):
		return
	_hovered_cards[card] = true
	CollectionManager.mark_card_seen(str(card.card_data.get("id", "")))
	_play_card_hover_sfx()
	_animate_collection_hover(card, true)


func _on_card_unhovered(card: Card3D) -> void:
	# A detail/fan transition can move the area out from under the pointer.
	# Always release its hover state, even while collection animation is suspended.
	_hovered_cards.erase(card)
	if _hovered_rarity == str(_card_rarities.get(card, "")):
		_hovered_rarity = ""
		for hovered_card: Variant in _hovered_cards:
			_hovered_rarity = str(_card_rarities.get(hovered_card, ""))
	if _detail_card != null or _detail_tween_running or _deck_fan_open or _deck_fan_tween_running:
		return
	if not is_instance_valid(card) or not _base_positions.has(card):
		return
	_animate_collection_hover(card, false)


func _animate_collection_hover(card: Card3D, hovered: bool, duration: float = -1.0) -> void:
	# Scrolling can finish a row's entrance early; these idempotent connections
	# keep a cancelled entrance tween from leaving its cards unresponsive.
	_connect_card_input(card)
	var previous: Tween = _card_hover_tweens.get(card)
	if previous != null and previous.is_valid():
		previous.kill()

	var base_pos: Vector3 = _base_positions[card]
	var base_rot: Vector3 = _base_rotations[card]
	var base_scale: Vector3 = _base_scales[card]
	var move_duration := hover_duration if duration < 0.0 else duration
	_update_collection_amount_visibility(card, hovered)
	var tween := create_tween().set_parallel(true)
	_card_hover_tweens[card] = tween
	tween.tween_property(card, "position", base_pos + hover_lift if hovered else base_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rotation if hovered else base_rot, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale * hover_scale if hovered else base_scale, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _reset_collection_hover(preserve_card: Card3D = null) -> void:
	for card: Variant in _card_hover_tweens.keys():
		var tween: Tween = _card_hover_tweens[card]
		if tween != null and tween.is_valid():
			tween.kill()
		if is_instance_valid(card) and card != preserve_card and _base_positions.has(card):
			card.position = _base_positions[card]
			card.rotation_degrees = _base_rotations[card]
			card.scale = _base_scales[card]
			_connect_card_input(card)
	_card_hover_tweens.clear()
	_hovered_cards.clear()
	_hovered_rarity = ""
	for card: Variant in _base_positions:
		if is_instance_valid(card):
			_update_collection_amount_visibility(card, card == preserve_card)


func _restore_collection_hover_under_mouse() -> void:
	for card: Variant in _base_positions:
		if is_instance_valid(card):
			_update_collection_amount_visibility(card)
	if camera == null or _detail_card != null or _deck_fan_open:
		return
	var card := _collection_card_under_mouse(get_viewport().get_mouse_position())
	if card != null and _base_positions.has(card):
		_on_card_hovered(card)


func _scroll_row(rarity: String, direction: int) -> void:
	if is_angel_dialog_open():
		return
	if rarity == "":
		return
	if not _row_cards.has(rarity):
		return

	var cards: Array = _row_cards[rarity]
	if cards.is_empty():
		return

	var min_offset := _row_min_scroll_offset(rarity)
	var current_offset: float = _row_scroll_offsets.get(rarity, 0.0)

	current_offset += float(direction) * row_scroll_step
	current_offset = clamp(current_offset, min_offset, 0.0)
	if is_equal_approx(current_offset, float(_row_scroll_offsets.get(rarity, 0.0))):
		return

	_row_scroll_offsets[rarity] = current_offset

	for i in range(cards.size()):
		var card: Card3D = cards[i]
		if not is_instance_valid(card):
			continue

		var new_pos := _row_card_position(rarity, i)
		_base_positions[card] = new_pos

		if card == _detail_card:
			continue

		# Scroll and hover share a tween, so rapid wheel input or a late
		# mouse-exit cannot pull a card back toward an obsolete row position.
		_animate_collection_hover(card, _hovered_cards.has(card), row_scroll_duration)


func _on_card_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, card: Card3D) -> void:
	if is_angel_dialog_open() or _slot_room_key_request_pending or _deck_input_suspended or not is_visible_in_tree() or get_tree().paused:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var front_card := _collection_card_under_mouse(event.position)
	if front_card != null and front_card != card:
		return

	if _deck_fan_open:
		return

	if _detail_tween_running:
		return
	# Pressing the open card starts rotation in _unhandled_input. A delayed
	# physics-picking callback must never turn that press into a close action.
	if card == _detail_card:
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
		await _close_detail_card()
		_open_detail_card(card)


func _open_detail_card(card: Card3D) -> void:
	if is_angel_dialog_open() or _slot_room_key_request_pending:
		return
	_hide_effect_overview()
	if not is_instance_valid(card) or not _base_positions.has(card):
		return

	_reset_collection_hover(card)
	_detail_rotation.reset()
	_detail_card = card
	_detail_tween_running = true
	_play_card_unique_sfx(card)

	var base_scale: Vector3 = _base_scales[card]
	var target_pos := camera.global_transform * detail_offset_from_camera
	var target_scale := _detail_target_scale(card, base_scale)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "global_position", target_pos, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", detail_rotation, detail_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", target_scale, detail_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_detail_card_id = str(card.card_data.get("id", card.card_data.get("card_id", "")))
	CollectionManager.mark_card_seen(_detail_card_id)
	_show_deck_button(card)

	await tween.finished
	_detail_tween_running = false


func _detail_target_scale(card: Card3D, base_scale: Vector3) -> Vector3:
	var target_scale := base_scale * detail_scale
	if str(card.card_data.get("id", "")) != CollectionManager.SLOT_ROOM_KEY_ID:
		return target_scale
	# Fit the whole key card in the standalone camera's narrower lens as well
	# as the hub, leaving room for its action without changing normal cards.
	var viewport_size := get_viewport().get_visible_rect().size
	var depth := absf(detail_offset_from_camera.z)
	var top := camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.09), depth)
	var bottom := camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.91), depth)
	var parent_scale := (card.get_parent() as Node3D).global_basis.get_scale()
	var height := 1.3 * target_scale.y * parent_scale.y
	return target_scale * minf(1.0, top.distance_to(bottom) / maxf(height, 0.001))


func _close_detail_card() -> void:
	_detail_rotation.reset()
	if _detail_switch_tween != null and _detail_switch_tween.is_valid():
		_detail_switch_tween.kill()
	_detail_switch_tween = null
	_hide_deck_button()
	_detail_card_id = ""
	var card := _detail_card
	_reset_collection_hover(card)
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
	_restore_collection_hover_under_mouse()


func _input(event: InputEvent) -> void:
	# Claim Escape before GUI/menu navigation or Pause can receive it. Keep
	# claiming it during return flights, and queue a close during entry flights.
	if event.is_action_pressed("ui_cancel", true) and _has_open_collection_view() and is_visible_in_tree() and not get_tree().paused and not _deck_input_suspended and not is_angel_dialog_open() and not _slot_room_key_request_pending and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera:
		get_viewport().set_input_as_handled()
		_request_view_close()
		return
	if _detail_rotation.dragging:
		if not _can_rotate_detail():
			_detail_rotation.stop()
		elif event is InputEventMouseMotion:
			_detail_rotation.drag(_detail_card, camera, event)
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_detail_rotation.stop()
			get_viewport().set_input_as_handled()
			return
	if is_angel_dialog_open():
		return
	# If a GUI consumes the release, cancel after dispatch instead of leaving a
	# card attached to the pointer. Normal drops finish in _unhandled_input first.
	if _dragged_fan_card != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_cancel_deck_drag.call_deferred()


func _has_open_collection_view() -> bool:
	return is_instance_valid(_detail_card) or _detail_tween_running or _deck_fan_open or _deck_fan_tween_running


func _request_view_close() -> void:
	_detail_rotation.stop()
	_cancel_deck_drag()
	_view_close_requested = true
	_finish_requested_view_close()


func _finish_requested_view_close() -> void:
	if not _view_close_requested or _detail_tween_running or _deck_fan_tween_running:
		return
	_view_close_requested = false
	if is_instance_valid(_detail_card):
		_close_detail_card()
	elif _deck_fan_open:
		_close_deck_fan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_detail_rotation.stop()
		_cancel_deck_drag()
		if is_instance_valid(angel_dialog):
			angel_dialog.close_dialog()


func _cancel_deck_drag() -> void:
	var card := _dragged_fan_card
	_dragged_fan_card = null
	_dragged_fan_card_id = ""
	if not is_instance_valid(card):
		return
	_stop_deck_reflow(card)
	var base: Dictionary = _deck_fan_base_transforms.get(card, {})
	if not base.is_empty():
		card.global_position = base["position"]
		card.rotation_degrees = base["rotation"]
		card.scale = base["scale"]
	_refresh_starting_hand_slots()


func suspend_deck_input(suspended: bool) -> void:
	_deck_input_suspended = suspended
	if suspended:
		_detail_rotation.stop()
		_cancel_deck_drag()
	_sync_angel_context()


func _unhandled_input(event: InputEvent) -> void:
	if is_angel_dialog_open() or not is_visible_in_tree() or get_tree().paused or _deck_input_suspended or _slot_room_key_request_pending:
		return
	if _can_rotate_detail() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Respect the real front-most collider, including Add to Deck, before
		# claiming a press; GUI controls have already had their input opportunity.
		if _collection_card_under_mouse(event.position) == _detail_card and _detail_rotation.begin(_detail_card, camera, event.position):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if _try_remove_hovered_deck_card(event):
			return

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
				var card := _collection_card_under_mouse(event.position)
				if card != null and not _deck_fan_tween_running:
					_start_drag_fan_card(card, str(card.card_data.get("id", "")))
					get_viewport().set_input_as_handled()
					return
				if is_instance_valid(_starting_hand_view) and _starting_hand_view.contains_pointer(event.position):
					get_viewport().set_input_as_handled()
					return

				# Klick auf irgendein 3D-Objekt?
				# Dann NICHT schließen.
				if _mouse_hits_interactive_3d(event.position):
					return

				# Wirklich daneben geklickt
				get_viewport().set_input_as_handled()
				_request_view_close()
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
			var rarity := _get_scroll_rarity_at(event.position)
			_scroll_row(rarity, 1)
			if not rarity.is_empty():
				get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var rarity := _get_scroll_rarity_at(event.position)
			_scroll_row(rarity, -1)
			if not rarity.is_empty():
				get_viewport().set_input_as_handled()
			return


	# ---------------------------------------------------------
	# Detailkarte
	# ---------------------------------------------------------
	if _detail_card == null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

			if _mouse_hits_interactive_3d(event.position):
				return

			get_viewport().set_input_as_handled()
			_request_view_close()


func _can_rotate_detail() -> bool:
	return is_instance_valid(_detail_card) and not _detail_tween_running and not is_angel_dialog_open() and not _slot_room_key_request_pending and not _deck_input_suspended and is_visible_in_tree() and not get_tree().paused and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera


func _collection_card_under_mouse(mouse_position: Vector2) -> Card3D:
	if is_angel_dialog_open() or not is_visible_in_tree() or not is_instance_valid(camera):
		return null
	if get_viewport().get_camera_3d() != camera:
		return null
	var from := camera.project_ray_origin(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(mouse_position) * 100.0
	)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var area := hit.get("collider") as Area3D
	if area == null or not area.input_ray_pickable or not area.is_visible_in_tree():
		return null
	var card := area.get_parent() as Card3D
	if card == null:
		return null
	if _deck_fan_open:
		return card if _deck_fan_cards.has(card) else null
	return card if _base_positions.has(card) else null


func _try_remove_hovered_deck_card(event: InputEventMouseButton) -> bool:
	if is_angel_dialog_open() or get_tree().paused or _detail_card != null or _detail_tween_running:
		return false
	if _deck_fan_tween_running or _dragged_fan_card != null:
		return false
	var card := _collection_card_under_mouse(event.position)
	if card == null:
		return false
	# Handle the closest card before physics picking dispatches to overlapping Areas.
	get_viewport().set_input_as_handled()
	if not event.pressed:
		return true
	var card_id := str(card.card_data.get("id", ""))
	if not CardData.is_combat_card(card.card_data) or DeckManager.get_card_count(card_id) == 0:
		return true
	if _deck_fan_open:
		var starting_slot := DeckManager.get_starting_deck_indices().find(int(card.get_meta("deck_index", -1)))
		if starting_slot >= 0:
			DeckManager.remove_starting_card(starting_slot)
			_reflow_deck_fan()
			_play_fly_sfx()
		else:
			_remove_card_from_fan(card, card_id)
	elif DeckManager.remove_card(card_id):
		_refresh_collection_amount_labels()
		_play_fly_sfx()
		empty_label.text = Localization.format_text("Deck: %d / %d", [DeckManager.battle_deck.size(), DeckManager.MAX_DECK_SIZE])
	return true

# ---------------------------------------------------------------------------
# Deck-Button (im Detail-View, "ADD TO DECK")
# ---------------------------------------------------------------------------

func _show_deck_button(card: Card3D) -> void:
	if _detail_card_id == "":
		return
	if _detail_card_id != CollectionManager.SLOT_ROOM_KEY_ID and not CardData.is_combat_card(card.card_data):
		_hide_deck_button()
		return

	if not _deck_button.pressed.is_connected(_on_add_to_deck_pressed):
		_deck_button.pressed.connect(_on_add_to_deck_pressed)

	if _deck_button_tween:
		_deck_button_tween.kill()

	_deck_button.transform = _deck_button_scene_transform
	_deck_button_base_pos = _deck_button_scene_transform.origin
	var target_scale := Vector3.ONE
	if _detail_card_id == CollectionManager.SLOT_ROOM_KEY_ID:
		# The standalone collection and the hub use different cameras. Keep
		# this key action on screen rather than at the scene's fixed deck button.
		var pointer := get_viewport().get_visible_rect().size * Vector2(0.875, 0.72)
		var world_position := camera.project_position(pointer, absf(detail_offset_from_camera.z) + 1.8)
		_deck_button_base_pos = to_local(world_position)
		target_scale = Vector3.ONE * 0.38 / global_basis.get_scale()

	_deck_button.visible = true
	_deck_button.position = _deck_button_base_pos + add_button_slide_offset
	_deck_button.scale = Vector3.ONE * 0.01

	_update_deck_button_state()

	_deck_button_tween = create_tween().set_parallel(true)
	_deck_button_tween.tween_property(_deck_button, "position", _deck_button_base_pos, add_button_slide_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	_deck_button_tween.tween_property(_deck_button, "scale", target_scale, add_button_slide_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

func _update_deck_button_state() -> void:
	if _deck_button == null or _detail_card_id == "":
		return
	if _detail_card_id == CollectionManager.SLOT_ROOM_KEY_ID:
		_set_detail_button_state("Zur Tür", _slot_room_key_request_pending or CollectionManager.get_amount(_detail_card_id) <= 0)
		return
	if not CardData.is_combat_card(CardDatabase.get_card(_detail_card_id)):
		_set_detail_button_state("SONDERKARTE", true)
		return

	if DeckManager.is_full():
		_set_detail_button_state("DECK FULL", true)
		return

	if not DeckManager.can_add_card(_detail_card_id):
		_set_detail_button_state("MAX OWNED", true)
		return

	var amount_in_deck := DeckManager.get_card_count(_detail_card_id)
	_set_detail_button_state(Localization.format_text("ADD TO DECK %d/%d", [amount_in_deck, CollectionManager.get_amount(_detail_card_id)]), false)


func _set_detail_button_state(text: String, disabled: bool) -> void:
	_deck_button.label_text = text
	_deck_button.label.text = text
	_deck_button.set_disabled(disabled)


func _on_add_to_deck_pressed() -> void:
	get_viewport().set_input_as_handled()

	if is_angel_dialog_open() or _slot_room_key_request_pending or _detail_tween_running or _deck_fan_tween_running or _deck_input_suspended or not is_visible_in_tree() or get_tree().paused:
		return
	if _detail_card_id == "":
		return
	if _detail_card_id == CollectionManager.SLOT_ROOM_KEY_ID:
		_request_slot_room_key()
		return
	if not CardData.is_combat_card(CardDatabase.get_card(_detail_card_id)):
		return

	var added := DeckManager.add_card(_detail_card_id)

	if added:
		empty_label.text = Localization.format_text("Deck: %d / %d", [DeckManager.battle_deck.size(), DeckManager.MAX_DECK_SIZE])
		_refresh_collection_amount_labels()
		_update_deck_button_state()
	else:
		empty_label.text = "Karte konnte nicht hinzugefügt werden"

	_update_deck_button_state()


func _request_slot_room_key() -> void:
	if is_angel_dialog_open() or _slot_room_key_request_pending or CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) <= 0:
		return
	_slot_room_key_request_pending = true
	_update_deck_button_state()
	await _close_detail_card()
	if CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) <= 0:
		finish_slot_room_key_request()
		return
	if slot_room_key_requested.get_connections().is_empty():
		# The main menu also opens this collection as a standalone scene. Carry
		# only the focus request into the hub; Main still owns the door reveal.
		CollectionManager.set_meta("slot_room_key_focus_requested", true)
		var scene_error := get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
		if scene_error != OK:
			CollectionManager.remove_meta("slot_room_key_focus_requested")
			finish_slot_room_key_request()
			push_warning("Die Tür konnte nicht geöffnet werden: Raum konnte nicht geladen werden.")
		return
	slot_room_key_requested.emit()


func finish_slot_room_key_request() -> void:
	_slot_room_key_request_pending = false
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

	if is_angel_dialog_open() or _slot_room_key_request_pending or _deck_input_suspended or not is_visible_in_tree() or get_tree().paused:
		return
	if _deck_fan_tween_running:
		return

	if _deck_fan_open:
		_close_deck_fan()
	else:
		_open_deck_fan()


func _open_deck_fan() -> void:
	if is_angel_dialog_open():
		return
	_hide_effect_overview()

	if _deck_fan_tween_running:
		return

	if _detail_card != null:
		await _close_detail_card()
	_reset_collection_hover()

	var deck_ids: Array[String] = DeckManager.get_deck_cards()

	_deck_fan_open = true
	_deck_fan_tween_running = false
	cards_root.visible = false

	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()

	_set_deck_management_buttons_visible(true)
	_show_starting_hand_slots()

	if deck_ids.is_empty():
		empty_label.text = "Dein Deck ist leer"
		empty_label.visible = true
		return

	empty_label.text = Localization.format_text("Deck: %d / %d", [
		deck_ids.size(),
		DeckManager.MAX_DECK_SIZE
	])
	empty_label.visible = true

	_deck_fan_tween_running = true

	var count: int = deck_ids.size()
	var deck_data := DeckManager.get_deck_card_data()
	var selected := DeckManager.get_starting_deck_indices()
	var assigned_count := selected.size() - selected.count(-1)
	var fan_index := 0

	for i: int in range(count):
		var card_id: String = deck_ids[i]
		var data: Dictionary = deck_data[i]

		if data.is_empty():
			continue

		var card: Card3D = CARD_SCENE.instantiate() as Card3D
		add_child(card)

		card.setup(data)
		card.set_meta("deck_index", i)

		var starting_slot := selected.find(i)
		var fan_transform: Dictionary = _starting_card_transform(starting_slot) if starting_slot >= 0 else _calculate_fan_transform(fan_index, count - assigned_count)
		if starting_slot < 0:
			fan_index += 1

		var target_pos: Vector3 = fan_transform["position"]
		var target_rot: Vector3 = fan_transform["rotation"]
		var target_scale: Vector3 = fan_transform["scale"]

		card.global_position = target_pos + Vector3(
			0,
			-deck_fan_rise_height,
			0
		)

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

	var last_delay := 0.0

	if count > 0:
		last_delay = float(count - 1) * deck_fan_stagger

	await get_tree().create_timer(
		last_delay + deck_fan_duration
	).timeout

	_deck_fan_tween_running = false

func _connect_fan_card_input(card: Card3D, card_id: String) -> void:
	if not card.area:
		return

	var input_received := _on_fan_card_input.bind(card, card_id)
	if not card.area.input_event.is_connected(input_received):
		card.area.input_event.connect(input_received)
	if not card.card_hovered.is_connected(_on_effect_card_hovered):
		card.card_hovered.connect(_on_effect_card_hovered)
	if not card.card_unhovered.is_connected(_on_effect_card_unhovered):
		card.card_unhovered.connect(_on_effect_card_unhovered)


func _on_fan_card_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int,
	card: Card3D,
	card_id: String
) -> void:
	if is_angel_dialog_open() or not _deck_fan_open or _deck_fan_tween_running or get_tree().paused or _deck_input_suspended:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag_fan_card(card, card_id)
			else:
				_release_drag_fan_card()

		get_viewport().set_input_as_handled()


func _remove_card_from_fan(card: Card3D, card_id: String) -> void:
	if card_id == "":
		return
	if _effect_overview != null:
		_effect_overview.hide_overview(card)

	var deck_index := int(card.get_meta("deck_index", -1))
	if not DeckManager.remove_card_at(deck_index):
		return

	_deck_fan_cards.erase(card)
	_deck_fan_base_transforms.erase(card)
	_stop_deck_reflow(card)
	for remaining in _deck_fan_cards:
		var previous := int(remaining.get_meta("deck_index", -1))
		if previous > deck_index:
			remaining.set_meta("deck_index", previous - 1)
	_refresh_fan_instance_finishes()
	_refresh_starting_hand_slots()

	_play_fly_sfx()

	if is_instance_valid(card):
		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_IN)

		tween.tween_property(
			card,
			"global_position",
			card.global_position + Vector3(
				0,
				-deck_fan_rise_height,
				0
			),
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.tween_property(
			card,
			"scale",
			card.scale * 0.01,
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.finished.connect(
			func() -> void:
				if is_instance_valid(card):
					card.queue_free()
		)

	_refresh_collection_amount_labels()

	empty_label.text = Localization.format_text("Deck: %d / %d", [
		DeckManager.battle_deck.size(),
		DeckManager.MAX_DECK_SIZE
	])

	empty_label.visible = true

	if _deck_button != null and is_instance_valid(_deck_button):
		_update_deck_button_state()

	if _deck_fan_cards.is_empty():
		empty_label.text = "Dein Deck ist leer"

		# Der Fan bleibt logisch geöffnet.
		_deck_fan_open = true
		_set_deck_management_buttons_visible(true)
		return

	_reflow_deck_fan()

func _close_deck_fan() -> void:
	if not _deck_fan_open:
		return

	if _deck_fan_tween_running:
		return
	_hide_effect_overview()

	_deck_fan_open = false
	_deck_fan_tween_running = true
	cards_root.visible = true

	_set_deck_management_buttons_visible(false)
	_hide_starting_hand_slots()

	if _dragged_fan_card != null:
		_dragged_fan_card = null
		_dragged_fan_card_id = ""

	var cards_to_close: Array[Card3D] = _deck_fan_cards.duplicate()

	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()

	for card: Card3D in cards_to_close:
		if card == null or not is_instance_valid(card):
			continue
		_stop_deck_reflow(card)

		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_IN)

		tween.tween_property(
			card,
			"global_position",
			card.global_position + Vector3(
				0,
				-deck_fan_rise_height,
				0
			),
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.tween_property(
			card,
			"scale",
			card.scale * 0.01,
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.finished.connect(
			func() -> void:
				if is_instance_valid(card):
					card.queue_free()
		)

	await get_tree().create_timer(0.24).timeout

	_deck_fan_tween_running = false

	empty_label.text = Localization.format_text("Deck: %d / %d", [
		DeckManager.battle_deck.size(),
		DeckManager.MAX_DECK_SIZE
	])
	_restore_collection_hover_under_mouse()
	
func _mouse_hits_interactive_3d(mouse_pos: Vector2) -> bool:
	if camera == null:
		return false

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
		return (collider as Area3D).input_ray_pickable and (collider as Area3D).is_visible_in_tree()

	return false


func _get_available_amount(card_id: String) -> int:
	return max(
		CollectionManager.get_amount(card_id) - DeckManager.get_card_count(card_id),
		0
	)
	
func _start_drag_fan_card(card: Card3D, card_id: String) -> void:
	if is_angel_dialog_open() or not is_instance_valid(card) or _dragged_fan_card != null or _deck_fan_tween_running or _deck_input_suspended:
		return
	_hide_effect_overview()
	_stop_deck_reflow(card)

	_dragged_fan_card = card
	_dragged_fan_card_id = card_id
	_drag_start_pos = card.global_position

	if _deck_fan_base_transforms.has(card):
		var base: Dictionary = _deck_fan_base_transforms[card]
		_drag_start_pos = base["position"]
	var plane := Plane(camera.global_basis.z, _drag_start_pos)
	var mouse_pos := get_viewport().get_mouse_position()
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos))
	_drag_pointer_offset = _drag_start_pos - (hit as Vector3) if hit != null else Vector3.ZERO


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

	var base: Dictionary = _deck_fan_base_transforms.get(_dragged_fan_card, {})
	var base_rot: Vector3 = base.get("rotation", _dragged_fan_card.rotation_degrees)
	var base_scale: Vector3 = base.get("scale", Vector3.ONE * deck_fan_card_scale)

	_dragged_fan_card.global_position = hit_pos + _drag_pointer_offset + camera.global_basis.z * 0.025
	_dragged_fan_card.rotation_degrees = base_rot
	_dragged_fan_card.scale = base_scale * fan_drag_scale
	if is_instance_valid(_starting_hand_view):
		_starting_hand_view.highlight_drop(mouse_pos, int(_dragged_fan_card.get_meta("deck_index", -1)))

func _release_drag_fan_card() -> void:
	if _dragged_fan_card == null:
		return

	var card: Card3D = _dragged_fan_card
	var card_id: String = _dragged_fan_card_id

	_dragged_fan_card = null
	_dragged_fan_card_id = ""

	if not is_instance_valid(card):
		return
	_refresh_starting_hand_slots()
	var deck_index := int(card.get_meta("deck_index", -1))
	var starting_slot := DeckManager.get_starting_deck_indices().find(deck_index)
	var pointer := get_viewport().get_mouse_position()
	if is_instance_valid(_starting_hand_view) and _starting_hand_view.contains_pointer(pointer):
		var target := _starting_hand_view.slot_at(pointer)
		if target >= 0 and target < CollectionManager.get_starting_hand_slot_count():
			if DeckManager.assign_starting_card(deck_index, target):
				_play_fly_sfx()
				_reflow_deck_fan()
				return
		_snap_fan_card_back(card)
		return

	var distance: float = card.global_position.distance_to(_drag_start_pos)
	if starting_slot >= 0:
		if distance >= 0.2:
			DeckManager.remove_starting_card(starting_slot)
			_play_fly_sfx()
			_reflow_deck_fan()
		else:
			_snap_fan_card_back(card)
		return

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
	_stop_deck_reflow(card)
	_deck_reflow_tweens[card] = tween
	tween.tween_property(card, "global_position", base_pos, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", base_rot, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	
func _refresh_fan_instance_finishes() -> void:
	var deck_data := DeckManager.get_deck_card_data()
	for card: Card3D in _deck_fan_cards:
		if not is_instance_valid(card):
			continue
		var index := int(card.get_meta("deck_index", -1))
		if index < 0 or index >= deck_data.size():
			continue
		var data: Dictionary = deck_data[index]
		if str(data.get("instance_id", "")) != str(card.card_data.get("instance_id", "")):
			card.setup(data)


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
	var offset := deck_fan_offset_from_camera
	var center_pos: Vector3 = camera.global_transform * offset

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
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var edge := camera.project_position(Vector2(viewport_size.x * 0.94, viewport_size.y * 0.5), absf(offset.z))
	var available_half_width := absf((edge - center_pos).dot(camera.global_basis.x)) - 0.4
	var natural_half_width := sin(deg_to_rad(angle_span * 0.5)) * deck_fan_radius + float(count - 1) * 0.5 * deck_fan_min_x_spacing
	var width_scale := minf(1.0, available_half_width / maxf(natural_half_width, 0.001))

	# Anchor the depth stack to one card. A fractional center puts the two
	# middle cards of an even fan on the same plane, so their faces z-fight.
	var front_card_index: int = maxi(0, floori(float(count - 1) * 0.5))
	var distance_from_center: float = abs(float(index - front_card_index))
	var depth_offset: float = distance_from_center * deck_fan_depth_spacing
	var local_target_pos: Vector3 = center_pos \
		+ camera.global_basis.x * (arc_offset.x + spread_x) * maxf(width_scale, 0.1) \
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
	var selected := DeckManager.get_starting_deck_indices()
	var assigned_count := selected.size() - selected.count(-1)
	var fan_index := 0
	_refresh_starting_hand_slots()

	for i in range(count):
		var card: Card3D = _deck_fan_cards[i]

		if card == _dragged_fan_card:
			continue

		var starting_slot := selected.find(int(card.get_meta("deck_index", -1)))
		var fan_transform: Dictionary = _starting_card_transform(starting_slot) if starting_slot >= 0 else _calculate_fan_transform(fan_index, count - assigned_count)
		if starting_slot < 0:
			fan_index += 1

		_deck_fan_base_transforms[card] = fan_transform

		var target_pos: Vector3 = fan_transform["position"]
		var target_rot: Vector3 = fan_transform["rotation"]
		var target_scale: Vector3 = fan_transform["scale"]

		var tween := create_tween().set_parallel(true)
		_stop_deck_reflow(card)
		_deck_reflow_tweens[card] = tween
		tween.tween_property(card, "global_position", target_pos, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", target_rot, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", target_scale, deck_fan_reflow_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func refresh_collection() -> void:
	if not _can_refresh_collection():
		_collection_refresh_pending = true
		return
	_collection_refresh_pending = false
	_sync_collection_cards()
	if _deck_fan_open:
		_refresh_starting_hand_slots()


func _sync_collection_cards() -> void:
	var owned := CollectionManager.get_owned_cards()
	var display_cards := CollectionManager.get_display_cards(owned.keys())
	var existing := {}
	for card: Card3D in _base_positions.keys():
		if is_instance_valid(card):
			existing[str(card.card_data.get("id", ""))] = card
	var next_rows := {}
	for rarity: String in RARITY_ORDER:
		next_rows[rarity] = []
	for card_id: String in display_cards:
		var data: Dictionary = display_cards[card_id]
		if int(owned.get(card_id, 0)) <= 0 or CardData.is_upgrade_collection_card(data):
			continue
		var rarity := str(data.get("rarity", "common")).to_lower()
		if not next_rows.has(rarity):
			rarity = "common"
		var card := existing.get(card_id) as Card3D
		if card == null:
			card = _create_collection_card(card_id, rarity, next_rows[rarity].size(), data)
			_connect_card_input(card)
		else:
			existing.erase(card_id)
			var updated := CardUpgradeManager.apply_upgrades(card_id, data)
			if card.card_data != updated:
				card.setup(updated)
			_refresh_new_card_label(card, card_id)
		_card_rarities[card] = rarity
		next_rows[rarity].append(card)
	for card: Card3D in existing.values():
		var tween := _card_hover_tweens.get(card) as Tween
		if tween != null and tween.is_valid():
			tween.kill()
		_card_hover_tweens.erase(card)
		_hovered_cards.erase(card)
		_base_positions.erase(card)
		_base_rotations.erase(card)
		_base_scales.erase(card)
		_card_rarities.erase(card)
		card.hide()
		card.area.input_ray_pickable = false
		card.queue_free()
	_row_cards = next_rows
	var has_cards := not _base_positions.is_empty()
	var secret_unlocked := _has_received_secret()
	for rarity: String in RARITY_ORDER:
		var label := cards_root.get_node_or_null("RarityLabel_" + rarity) as Label3D
		var show_label := secret_unlocked if rarity == "secret" else has_cards
		if label == null and show_label:
			_add_rarity_label(rarity, RARITY_ORDER.find(rarity))
		elif label != null and not show_label:
			cards_root.remove_child(label)
			label.queue_free()
		_row_scroll_offsets[rarity] = clampf(float(_row_scroll_offsets.get(rarity, 0.0)), _row_min_scroll_offset(rarity), 0.0)
		var cards: Array = _row_cards[rarity]
		for index in range(cards.size()):
			var card: Card3D = cards[index]
			var position_in_row := _row_card_position(rarity, index)
			if not (_base_positions[card] as Vector3).is_equal_approx(position_in_row):
				_base_positions[card] = position_in_row
				_animate_collection_hover(card, _hovered_cards.has(card), row_scroll_duration)
			_update_collection_amount_visibility(card)
	if not _deck_fan_open:
		empty_label.text = "Noch keine Karten in der Sammlung"
		empty_label.visible = not has_cards
	_refresh_collection_amount_labels()
	_update_deck_button_state()


func _can_refresh_collection() -> bool:
	return not is_angel_dialog_open() and _detail_card == null and not _detail_tween_running and not _deck_fan_tween_running and _dragged_fan_card == null and not _slot_room_key_request_pending


func _on_collection_changed(card_ids: Array[String]) -> void:
	_collection_refresh_pending = true
	for card_id: String in card_ids:
		if CardDatabase.get_card(card_id).get("rarity") == "secret":
			_refresh_secret_cards.call_deferred()
			break


func _stop_deck_reflow(card: Card3D) -> void:
	var previous := _deck_reflow_tweens.get(card) as Tween
	if previous != null:
		previous.kill()
	_deck_reflow_tweens.erase(card)


func refresh_starting_hand_unlocks() -> void:
	_refresh_starting_hand_slots()
	# Cheats can run from paused settings while a detail card is open.
	# Rebuild the collection once that view has safely returned.
	_collection_refresh_pending = true


func _show_starting_hand_slots() -> void:
	_hide_starting_hand_slots()
	_starting_hand_view = STARTING_HAND_VIEW.new() as StartingHandSlots
	_starting_hand_view.name = "StartingHandSlots"
	add_child(_starting_hand_view)
	_starting_hand_view.setup(camera)


func _hide_starting_hand_slots() -> void:
	if is_instance_valid(_starting_hand_view):
		_starting_hand_view.hide()
		_starting_hand_view.queue_free()
	_starting_hand_view = null


func _refresh_starting_hand_slots() -> void:
	if is_instance_valid(_starting_hand_view):
		_starting_hand_view.refresh()


func _starting_card_transform(slot: int) -> Dictionary:
	var local_basis := global_basis.inverse() * _starting_hand_view.global_basis
	return {
		"position": _starting_hand_view.card_position(slot),
		"rotation": local_basis.orthonormalized().get_euler() * (180.0 / PI),
		"scale": Vector3.ONE * 0.53 / global_basis.get_scale(),
	}

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
			_deck_button.transform = _deck_button_scene_transform
			_deck_button_base_pos = _deck_button_scene_transform.origin
	)
	
func _show_next_detail_card(direction: int) -> void:
	if is_angel_dialog_open() or _detail_card == null or _slot_room_key_request_pending:
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

	_detail_rotation.reset()
	_hide_deck_button()

	_detail_tween_running = true
	_detail_card = new_card
	_detail_card_id = str(new_card.card_data.get("id", new_card.card_data.get("card_id", "")))
	CollectionManager.mark_card_seen(_detail_card_id)
	_play_card_unique_sfx(new_card)

	var detail_pos := camera.global_transform * detail_offset_from_camera

	var old_base_pos: Vector3 = _base_positions[old_card]
	var old_base_rot: Vector3 = _base_rotations[old_card]
	var old_base_scale: Vector3 = _base_scales[old_card]

	var new_base_scale: Vector3 = _base_scales[new_card]
	var new_detail_scale := _detail_target_scale(new_card, new_base_scale)

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

		card.setup(CardData.with_instance_metadata(upgraded_data, card.card_data))

	# Detailkarte aktualisieren, falls genau diese offen ist
	if _detail_card != null and is_instance_valid(_detail_card):
		var detail_id := str(_detail_card.card_data.get("id", _detail_card.card_data.get("card_id", "")))
		if detail_id == card_id:
			_detail_card.setup(CardData.with_instance_metadata(upgraded_data, _detail_card.card_data))

	# Deck-Fan-Karten aktualisieren, falls der Fan offen ist
	var deck_data := DeckManager.get_deck_card_data()
	for fan_card in _deck_fan_cards:
		if fan_card == null or not is_instance_valid(fan_card):
			continue

		var fan_id := str(fan_card.card_data.get("id", fan_card.card_data.get("card_id", "")))
		if fan_id != card_id:
			continue

		var index := int(fan_card.get_meta("deck_index", -1))
		if index >= 0 and index < deck_data.size():
			fan_card.setup(deck_data[index])

	_refresh_collection_amount_labels()

	if _deck_button != null and is_instance_valid(_deck_button):
		_update_deck_button_state()
		
func _play_card_unique_sfx(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		return

	var card_id := str(card.card_data.get("id", card.card_data.get("card_id", "")))
	if card_id == "":
		return

	var sound_path := "res://assets/sounds/SFX/cards/" + card_id + ".ogg"

	if not ResourceLoader.exists(sound_path):
		return

	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = load(sound_path)
	add_child(player)

	player.play()
	player.finished.connect(player.queue_free)

func _setup_deck_management_buttons() -> void:
	if clear_deck_button != null:
		clear_deck_button.label_text = "CLEAR DECK"

		if not clear_deck_button.pressed.is_connected(_on_clear_deck_pressed):
			clear_deck_button.pressed.connect(_on_clear_deck_pressed)

	if random_deck_button != null:
		random_deck_button.label_text = "RANDOM DECK"

		if not random_deck_button.pressed.is_connected(_on_random_deck_pressed):
			random_deck_button.pressed.connect(_on_random_deck_pressed)

	_set_deck_management_buttons_visible(false)

func _set_deck_management_buttons_visible(value: bool) -> void:
	if clear_deck_button != null and is_instance_valid(clear_deck_button):
		clear_deck_button.visible = value

	if random_deck_button != null and is_instance_valid(random_deck_button):
		random_deck_button.visible = value

func _on_clear_deck_pressed() -> void:
	get_viewport().set_input_as_handled()
	if is_angel_dialog_open():
		return

	if not _deck_fan_open:
		return

	if _deck_fan_tween_running:
		return
	_hide_effect_overview()

	_deck_fan_tween_running = true

	if _dragged_fan_card != null:
		_dragged_fan_card = null
		_dragged_fan_card_id = ""

	var deck_cards: Array[String] = DeckManager.get_deck_cards()

	for card_id: String in deck_cards:
		DeckManager.remove_card(card_id)

	var visible_cards: Array[Card3D] = _deck_fan_cards.duplicate()

	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()

	for card: Card3D in visible_cards:
		if card == null or not is_instance_valid(card):
			continue
		_stop_deck_reflow(card)

		var tween := create_tween().set_parallel(true)
		tween.set_ease(Tween.EASE_IN)

		tween.tween_property(
			card,
			"global_position",
			card.global_position + Vector3(
				0,
				-deck_fan_rise_height,
				0
			),
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.tween_property(
			card,
			"scale",
			card.scale * 0.01,
			0.22
		).set_trans(Tween.TRANS_CUBIC)

		tween.finished.connect(
			func() -> void:
				if is_instance_valid(card):
					card.queue_free()
		)

	_play_fly_sfx()

	await get_tree().create_timer(0.24).timeout
	_refresh_starting_hand_slots()

	_deck_fan_tween_running = false
	_deck_fan_open = true

	_set_deck_management_buttons_visible(true)
	_refresh_collection_amount_labels()

	empty_label.text = "Dein Deck ist leer"
	empty_label.visible = true

	if _deck_button != null and is_instance_valid(_deck_button):
		_update_deck_button_state()

func _on_random_deck_pressed() -> void:
	get_viewport().set_input_as_handled()
	if is_angel_dialog_open():
		return

	if not _deck_fan_open:
		return

	if _deck_fan_tween_running:
		return
	_hide_effect_overview()

	_deck_fan_tween_running = true

	if _dragged_fan_card != null:
		_dragged_fan_card = null
		_dragged_fan_card_id = ""

	# ---------------------------------------------------------
	# Aktuelles Deck leeren
	# ---------------------------------------------------------
	var current_deck: Array[String] = DeckManager.get_deck_cards()

	for card_id: String in current_deck:
		DeckManager.remove_card(card_id)

	# ---------------------------------------------------------
	# Aktuell sichtbare Fan-Karten entfernen
	# ---------------------------------------------------------
	for card: Card3D in _deck_fan_cards:
		if card != null and is_instance_valid(card):
			_stop_deck_reflow(card)
			card.queue_free()

	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()

	# ---------------------------------------------------------
	# Pool aus allen tatsächlich besessenen Karten erstellen
	_refresh_starting_hand_slots()
	# ---------------------------------------------------------
	var random_pool: Array[String] = []
	var owned_cards: Dictionary = CollectionManager.get_owned_cards()

	for card_id_variant: Variant in owned_cards.keys():
		var card_id := str(card_id_variant)
		var owned_amount := int(
			owned_cards.get(card_id_variant, 0)
		)

		if card_id == "":
			continue

		if owned_amount <= 0:
			continue

		var data: Dictionary = CardDatabase.get_card(card_id)

		if not CardData.is_combat_card(data):
			continue

		# Jede besessene Kopie kommt einmal in den Pool.
		for copy_index: int in range(owned_amount):
			random_pool.append(card_id)

	random_pool.shuffle()

	# ---------------------------------------------------------
	# Deck bis zur Maximalgröße füllen
	# ---------------------------------------------------------
	for card_id: String in random_pool:
		if DeckManager.is_full():
			break

		if not DeckManager.can_add_card(card_id):
			continue

		DeckManager.add_card(card_id)

	_refresh_collection_amount_labels()

	_deck_fan_tween_running = false
	_deck_fan_open = true

	_set_deck_management_buttons_visible(true)

	var new_deck: Array[String] = DeckManager.get_deck_cards()

	if new_deck.is_empty():
		empty_label.text = "Keine Karten für Random Deck verfügbar"
		empty_label.visible = true
		return

	empty_label.text = Localization.format_text("Deck: %d / %d", [
		new_deck.size(),
		DeckManager.MAX_DECK_SIZE
	])

	empty_label.visible = true

	if _deck_button != null and is_instance_valid(_deck_button):
		_update_deck_button_state()

	# Fan mit dem neu erzeugten Deck wieder aufbauen.
	await _rebuild_open_deck_fan()

func _rebuild_open_deck_fan() -> void:
	if not _deck_fan_open or _deck_fan_tween_running:
		return
	for card: Card3D in _deck_fan_cards:
		_stop_deck_reflow(card)
		if is_instance_valid(card):
			card.hide()
			card.queue_free()
	_deck_fan_cards.clear()
	_deck_fan_base_transforms.clear()
	await _open_deck_fan()
