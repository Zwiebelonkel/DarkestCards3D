extends Node3D
class_name UpgradeWallCollection

signal detail_open_changed(open: bool)

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const DETAIL_ROTATION := preload("res://scripts/card/CardDetailRotation.gd")
const CARD_GROUPS := {
	"upgrade_group_clicker": ["clicker", "clicker_upgrade", "golden_clicker", "auto_clicker"],
	"upgrade_group_starting_hand": ["starting_hand_1", "starting_hand_2", "starting_hand_3", "starting_hand_4", "starting_hand_5"],
	"upgrade_group_soulcoins": ["soulcoin_boost_1", "soulcoin_boost_2", "soulcoin_boost_3", "soulcoin_boost_4"],
	"upgrade_group_xp": ["xp_boost_1", "xp_boost_2", "xp_boost_3", "xp_boost_4"],
	"upgrade_group_fusion": ["fusion_upgrade_1", "fusion_upgrade_2"],
	"upgrade_group_trade": ["lucky_coin", "dealer_license"],
	"upgrade_group_access": ["slot_room_key", "black_market_access", "graveyard_key", "basement_key"],
	"upgrade_group_story": [],
	"upgrade_group_other": [],
}
const CARD_SIZE := Vector2(0.792, 1.14)
const CARD_SCALE := 0.88
const COLUMNS := 4
const VISIBLE_ROWS := 2
const ROW_SPACING := 1.50
const AMOUNT_OFFSET := 0.65
const SCROLL_TOP := 1.15
const SCROLL_BOTTOM := -1.5
const SCROLL_X := 2.65

enum DetailPhase { CLOSED, OPENING, OPEN, CLOSING }

@export var camera: Camera3D
@export_range(0, 3, 1) var view_side := 3
@export_range(0.1, 1.5, 0.01) var detail_flight_duration := 0.42

var _interaction_enabled := false
var _refresh_pending := false
var _cards: Dictionary = {}
var _amount_labels: Dictionary = {}
var _base_positions: Dictionary = {}
var _card_rows: Dictionary = {}
var _rows: Array[Dictionary] = []
var _group_labels: Array[Label3D] = []
var _scroll_row := 0
var _row_count := 0
var _scroll_track: MeshInstance3D
var _scroll_thumb: MeshInstance3D
var _scroll_dragging := false
var _scroll_drag_offset := 0.0
var _hovered_id := ""
var _cards_root: Node3D
var _empty_label: Label3D
var _summary_label: Label3D
var _detail_card: Card3D
var _detail_id := ""
var _detail_layer: CanvasLayer
var _detail_controls: Control
var _detail_caption: Label
var _detail_phase := DetailPhase.CLOSED
var _detail_progress := 0.0
var _detail_start_transform := Transform3D.IDENTITY
var _detail_rotation := DETAIL_ROTATION.new()
var focus_area: Area3D


func _ready() -> void:
	get_window().focus_exited.connect(_detail_rotation.stop)
	_build_wall()
	_build_detail_controls()
	CollectionManager.collection_changed.connect(_queue_refresh)
	Localization.locale_changed.connect(_queue_refresh)
	refresh_collection()


func _process(delta: float) -> void:
	if _refresh_pending:
		refresh_collection()
	if not _can_interact():
		_scroll_dragging = false
	if is_detail_open():
		if not is_instance_valid(_detail_card) or not is_visible_in_tree() or not is_instance_valid(camera) or get_viewport().get_camera_3d() != camera:
			close_detail(true)
		else:
			_update_detail_transform(delta)
		return
	var hovered := _card_at(get_viewport().get_mouse_position()) if _can_interact() else ""
	_hovered_id = hovered
	for card_id: String in _cards:
		var card: Card3D = _cards[card_id]
		if not card.visible:
			continue
		var active := card_id == hovered
		var target: Vector3 = _base_positions[card_id] + (Vector3(0, 0.03, 0.13) if active else Vector3.ZERO)
		card.position = card.position.lerp(target, minf(delta * 14.0, 1.0))
		card.scale = card.scale.lerp(Vector3.ONE * CARD_SCALE * (1.045 if active else 1.0), minf(delta * 14.0, 1.0))


func _input(event: InputEvent) -> void:
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_scroll_dragging = false
	if not is_detail_open() or get_tree().paused:
		return
	if event.is_action_pressed("ui_cancel"):
		close_detail()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_detail_rotation.stop()


func _can_rotate_detail() -> bool:
	return _detail_phase == DetailPhase.OPEN and is_instance_valid(_detail_card) and is_visible_in_tree() and not get_tree().paused and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact():
		return
	if _scroll_dragging and event is InputEventMouseMotion:
		var drag_hit: Variant = _wall_point_at(event.position)
		if drag_hit != null:
			_scroll_to_pointer(drag_hit.y)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	var wall_hit: Variant = _wall_point_at(button.position)
	if wall_hit != null and absf(wall_hit.x) <= 2.9 and absf(wall_hit.y) <= 1.9:
		if _row_count > VISIBLE_ROWS and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_scroll_row(_scroll_row + (1 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))
			get_viewport().set_input_as_handled()
			return
		if _scroll_track.visible and button.button_index == MOUSE_BUTTON_LEFT and absf(wall_hit.x - SCROLL_X) <= 0.18 and wall_hit.y >= SCROLL_BOTTOM and wall_hit.y <= SCROLL_TOP:
			_scroll_dragging = true
			_scroll_drag_offset = wall_hit.y - _scroll_thumb.position.y if absf(wall_hit.y - _scroll_thumb.position.y) <= _scroll_thumb.scale.y * 0.5 else 0.0
			_scroll_to_pointer(wall_hit.y)
			get_viewport().set_input_as_handled()
			return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	var card_id := _card_at(button.position)
	if card_id != "":
		open_detail(card_id)
		get_viewport().set_input_as_handled()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if is_instance_valid(focus_area):
		focus_area.input_ray_pickable = enabled
	if not enabled:
		_hovered_id = ""
		_scroll_dragging = false


func is_detail_open() -> bool:
	return _detail_phase != DetailPhase.CLOSED


func close_detail(immediate: bool = false) -> void:
	_detail_rotation.stop()
	if not is_detail_open():
		return
	if immediate or not is_instance_valid(_detail_card):
		_finish_detail_close()
		return
	if _detail_phase == DetailPhase.CLOSING:
		return
	# Start from the visible pose, including an interrupted outward flight.
	_detail_start_transform = _detail_card.global_transform
	_detail_progress = 0.0
	_detail_phase = DetailPhase.CLOSING
	_detail_caption.hide()


func _finish_detail_close() -> void:
	_detail_rotation.reset()
	if is_instance_valid(_detail_card) and _base_positions.has(_detail_id):
		_detail_card.global_transform = _wall_card_transform(_detail_id)
	_detail_card = null
	_detail_id = ""
	_detail_phase = DetailPhase.CLOSED
	_detail_progress = 0.0
	if is_instance_valid(_detail_controls):
		_detail_controls.hide()
	detail_open_changed.emit(false)


func open_detail(card_id: String) -> void:
	if not _can_interact() or not _cards.has(card_id):
		return
	if not _cards[card_id].visible:
		return
	var data := CollectionManager.get_display_card(card_id)
	if not CardData.is_upgrade_collection_card(data) or CollectionManager.get_amount(card_id) <= 0:
		return
	_detail_id = card_id
	_detail_rotation.reset()
	# Move the mounted card itself so its place on the wall stays empty.
	_detail_card = _cards[card_id]
	_detail_start_transform = _detail_card.global_transform
	_detail_progress = 0.0
	_detail_phase = DetailPhase.OPENING
	_update_detail_caption()
	_detail_caption.hide()
	_detail_controls.show()
	_hovered_id = ""
	_scroll_dragging = false
	detail_open_changed.emit(true)


func refresh_collection() -> void:
	_refresh_pending = false
	if not is_instance_valid(_cards_root):
		return
	var ids: Array[String] = []
	for value: Variant in CollectionManager.get_owned_cards():
		var card_id := str(value)
		if CollectionManager.get_amount(card_id) > 0 and CardData.is_upgrade_collection_card(CardDatabase.get_card(card_id)):
			ids.append(card_id)
	if is_detail_open() and not ids.has(_detail_id):
		close_detail(true)
	var anchor_id := ""
	if _scroll_row < _rows.size() and not _rows[_scroll_row]["ids"].is_empty():
		anchor_id = str(_rows[_scroll_row]["ids"][0])
	for child in _cards_root.get_children():
		if child != _detail_card:
			child.queue_free()
	_cards.clear()
	_amount_labels.clear()
	_base_positions.clear()
	_card_rows.clear()
	_group_labels.clear()
	_build_group_rows(ids)
	_row_count = _rows.size()
	if _card_rows.has(anchor_id):
		_scroll_row = int(_card_rows[anchor_id])
	_scroll_row = clampi(_scroll_row, 0, maxi(_row_count - VISIBLE_ROWS, 0))
	if is_detail_open():
		# Newly acquired cards can move the inspected card into another row.
		var detail_row: int = _card_rows[_detail_id]
		_scroll_row = clampi(_scroll_row, maxi(detail_row - VISIBLE_ROWS + 1, 0), detail_row)
	for card_id: String in _card_rows:
		var card: Card3D
		if is_detail_open() and card_id == _detail_id:
			card = _detail_card
		else:
			card = _create_card(CollectionManager.get_display_card(card_id), _cards_root)
		card.name = "Upgrade_" + card_id
		var row: int = _card_rows[card_id]
		var row_ids: Array = _rows[row]["ids"]
		var in_row := row_ids.size()
		var position_in_row := row_ids.find(card_id)
		var wall_position := Vector3((position_in_row - (in_row - 1) * 0.5) * 1.28, _row_y(row), 0.12)
		if card != _detail_card:
			card.position = wall_position
			card.scale = Vector3.ONE * CARD_SCALE
		_cards[card_id] = card
		_base_positions[card_id] = wall_position
		card.visible = card == _detail_card or _row_is_visible(row)
		var amount := _label("× %d" % CollectionManager.get_amount(card_id), Vector3(wall_position.x, wall_position.y - AMOUNT_OFFSET, 0.14), 23, 0.0042)
		amount.visible = _row_is_visible(row)
		_cards_root.add_child(amount)
		_amount_labels[card_id] = amount
	for row in range(_rows.size()):
		var caption := Localization.text(str(_rows[row]["group"]))
		if int(_rows[row]["parts"]) > 1:
			caption += " · %d/%d" % [int(_rows[row]["part"]), int(_rows[row]["parts"])]
		var heading := _label(caption, Vector3(-2.35, _row_y(row) + 0.74, 0.14), 25, 0.0044)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.modulate = Color(0.92, 0.80, 0.58)
		heading.visible = _row_is_visible(row)
		_cards_root.add_child(heading)
		_group_labels.append(heading)
	_empty_label.visible = ids.is_empty()
	_summary_label.text = "NOCH KEINE UPGRADES GEFUNDEN" if ids.is_empty() else Localization.format_text("%d UPGRADES", [ids.size()])
	_update_scrollbar()
	if is_detail_open():
		_detail_card.setup(CollectionManager.get_display_card(_detail_id))
		_detail_card.description_label.skip()
		_disable_card_input(_detail_card)
		_update_detail_caption()


func _build_group_rows(ids: Array[String]) -> void:
	_rows.clear()
	var remaining := ids.duplicate()
	for group: String in CARD_GROUPS:
		var members: Array[String] = []
		if group == "upgrade_group_story":
			for card_id: String in remaining.duplicate():
				if CardData.is_story_card(CardDatabase.get_card(card_id)):
					members.append(card_id)
					remaining.erase(card_id)
		elif group == "upgrade_group_other":
			members.assign(remaining)
			members.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		else:
			for card_id: String in CARD_GROUPS[group]:
				if remaining.has(card_id):
					members.append(card_id)
					remaining.erase(card_id)
		var parts := ceili(members.size() / float(COLUMNS))
		for part in range(parts):
			var row_ids := members.slice(part * COLUMNS, (part + 1) * COLUMNS)
			for card_id: String in row_ids:
				_card_rows[card_id] = _rows.size()
			_rows.append({"group": group, "ids": row_ids, "part": part + 1, "parts": parts})


func _queue_refresh(card_ids: Array = []) -> void:
	# Acquisitions can emit several times in a pack or cheat. Rebuild once,
	# outside CollectionManager's signal and any physics input callback.
	if card_ids.is_empty():
		_refresh_pending = true
	for card_id: String in card_ids:
		if CardData.is_upgrade_collection_card(CardDatabase.get_card(card_id)):
			_refresh_pending = true
			break


func _can_interact() -> bool:
	return _interaction_enabled and not is_detail_open() and not get_tree().paused and is_visible_in_tree() and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera


func _row_y(row: int) -> float:
	return 0.58 - (row - _scroll_row) * ROW_SPACING


func _row_is_visible(row: int) -> bool:
	return row >= _scroll_row and row < _scroll_row + VISIBLE_ROWS


func _set_scroll_row(row: int) -> void:
	if not _can_interact():
		return
	var next_row := clampi(row, 0, maxi(_row_count - VISIBLE_ROWS, 0))
	if next_row == _scroll_row:
		return
	_scroll_row = next_row
	_hovered_id = ""
	# Scroll in whole rows so card faces and quantity labels stay inside the frame.
	for card_id: String in _cards:
		var card: Card3D = _cards[card_id]
		var card_row: int = _card_rows[card_id]
		var wall_position: Vector3 = _base_positions[card_id]
		wall_position.y = _row_y(card_row)
		_base_positions[card_id] = wall_position
		card.position = wall_position
		card.scale = Vector3.ONE * CARD_SCALE
		card.visible = _row_is_visible(card_row)
		var amount: Label3D = _amount_labels[card_id]
		amount.position.y = wall_position.y - AMOUNT_OFFSET
		amount.visible = card.visible
	for index in range(_group_labels.size()):
		_group_labels[index].position.y = _row_y(index) + 0.74
		_group_labels[index].visible = _row_is_visible(index)
	_update_scrollbar()


func _update_scrollbar() -> void:
	_scroll_track.visible = _row_count > VISIBLE_ROWS
	_scroll_thumb.visible = _scroll_track.visible
	if not _scroll_track.visible:
		_scroll_dragging = false
		return
	var track_height := SCROLL_TOP - SCROLL_BOTTOM
	var thumb_height := maxf(0.22, track_height * VISIBLE_ROWS / _row_count)
	_scroll_thumb.scale.y = thumb_height
	var progress := float(_scroll_row) / (_row_count - VISIBLE_ROWS)
	_scroll_thumb.position.y = SCROLL_TOP - thumb_height * 0.5 - progress * (track_height - thumb_height)


func _scroll_to_pointer(local_y: float) -> void:
	var thumb_height := _scroll_thumb.scale.y
	var travel := SCROLL_TOP - SCROLL_BOTTOM - thumb_height
	if travel <= 0.0:
		return
	var progress := (SCROLL_TOP - thumb_height * 0.5 - (local_y - _scroll_drag_offset)) / travel
	_set_scroll_row(roundi(clampf(progress, 0.0, 1.0) * (_row_count - VISIBLE_ROWS)))


func _wall_point_at(mouse_position: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var normal := global_basis.z.normalized()
	if normal.dot(ray_direction) >= -0.001:
		return null
	var hit: Variant = Plane(normal, to_global(Vector3(0, 0, 0.14))).intersects_ray(ray_origin, ray_direction)
	return to_local(hit) if hit != null else null


func _card_at(mouse_position: Vector2) -> String:
	if not _can_interact():
		return ""
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var nearest := INF
	var selected := ""
	for card_id: String in _cards:
		var card: Card3D = _cards[card_id]
		if not card.is_visible_in_tree() or camera.is_position_behind(card.global_position):
			continue
		var normal := card.global_basis.z.normalized()
		# Only the visible front can be selected, never through the wall.
		if normal.dot(ray_direction) >= -0.001:
			continue
		var hit: Variant = Plane(normal, card.global_position).intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var local: Vector3 = card.to_local(hit)
		if absf(local.x) > CARD_SIZE.x * 0.5 or absf(local.y) > CARD_SIZE.y * 0.5:
			continue
		var distance: float = ray_origin.distance_squared_to(hit)
		if distance < nearest:
			nearest = distance
			selected = card_id
	return selected


func _create_card(data: Dictionary, parent: Node3D = null) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	(parent if parent != null else self).add_child(card)
	card.setup(data)
	card.description_label.skip()
	_disable_card_input(card)
	return card


func _disable_card_input(node: Node) -> void:
	if node is CollisionObject3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)


func _wall_card_transform(card_id: String) -> Transform3D:
	return _cards_root.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * CARD_SCALE), _base_positions[card_id])


func _update_detail_transform(delta: float) -> void:
	if _detail_phase == DetailPhase.OPEN:
		_detail_card.global_transform = _detail_target_transform()
		_detail_rotation.apply(_detail_card, camera)
		return
	_detail_progress = minf(_detail_progress + delta / detail_flight_duration, 1.0)
	var target := _wall_card_transform(_detail_id) if _detail_phase == DetailPhase.CLOSING else _detail_target_transform()
	_detail_card.global_transform = _detail_start_transform.interpolate_with(target, smoothstep(0.0, 1.0, _detail_progress))
	if _detail_progress >= 1.0:
		if _detail_phase == DetailPhase.CLOSING:
			_finish_detail_close()
		else:
			_detail_phase = DetailPhase.OPEN
			_detail_caption.show()


func _detail_target_transform() -> Transform3D:
	# Camera-relative placement stays upright even though the wall is rotated.
	# Projected dimensions keep the full card above the ownership caption.
	var depth := 1.8
	var viewport_size := get_viewport().get_visible_rect().size
	var top := camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.08), depth)
	var bottom := camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.82), depth)
	var left := camera.project_position(Vector2(viewport_size.x * 0.08, viewport_size.y * 0.45), depth)
	var right := camera.project_position(Vector2(viewport_size.x * 0.92, viewport_size.y * 0.45), depth)
	var card_scale := minf(top.distance_to(bottom) / CARD_SIZE.y, left.distance_to(right) / CARD_SIZE.x)
	return Transform3D(camera.global_basis.orthonormalized().scaled(Vector3.ONE * card_scale), (top + bottom) * 0.5)


func _update_detail_caption() -> void:
	var amount := CollectionManager.get_amount(_detail_id)
	_detail_caption.text = Localization.format_text("IM BESITZ: %d", [amount])


func _build_wall() -> void:
	# The shared shop camera controller checks this whole panel, including
	# gaps between cards. Its geometric polling needs no physics collision.
	focus_area = Area3D.new()
	focus_area.name = "FocusArea"
	focus_area.collision_layer = 0
	focus_area.collision_mask = 0
	focus_area.input_ray_pickable = _interaction_enabled
	add_child(focus_area)
	var focus_shape := CollisionShape3D.new()
	focus_shape.name = "CollisionShape3D"
	var focus_box := BoxShape3D.new()
	focus_box.size = Vector3(5.96, 3.97, 0.35)
	focus_shape.shape = focus_box
	focus_shape.position.z = 0.10
	focus_area.add_child(focus_shape)
	_add_box("Backing", Vector3(5.8, 3.8, 0.08), Vector3(0, 0, -0.035), Color(0.055, 0.042, 0.039))
	var border := Color(0.29, 0.25, 0.21)
	_add_box("TopRail", Vector3(5.96, 0.085, 0.12), Vector3(0, 1.94, 0), border)
	_add_box("BottomRail", Vector3(5.96, 0.085, 0.12), Vector3(0, -1.94, 0), border)
	_add_box("LeftRail", Vector3(0.085, 3.8, 0.12), Vector3(-2.94, 0, 0), border)
	_add_box("RightRail", Vector3(0.085, 3.8, 0.12), Vector3(2.94, 0, 0), border)
	_scroll_track = _add_box("ScrollTrack", Vector3(0.06, SCROLL_TOP - SCROLL_BOTTOM, 0.025), Vector3(SCROLL_X, (SCROLL_TOP + SCROLL_BOTTOM) * 0.5, 0.10), border)
	_scroll_thumb = _add_box("ScrollThumb", Vector3(0.16, 1.0, 0.04), Vector3(SCROLL_X, 0, 0.14), Color(0.85, 0.72, 0.48))
	add_child(_label("UPGRADES", Vector3(0, 1.66, 0.065), 38, 0.006))
	_summary_label = _label("", Vector3(0, -1.73, 0.065), 23, 0.0046)
	add_child(_summary_label)
	_empty_label = _label("FINDE UPGRADE-KARTEN IN PACKS.\nDEINE FREISCHALTUNGEN HÄNGEN HIER.", Vector3(0, 0, 0.065), 26, 0.005)
	add_child(_empty_label)
	_cards_root = Node3D.new()
	_cards_root.name = "Cards"
	add_child(_cards_root)
	var light := SpotLight3D.new()
	light.name = "CollectionLight"
	light.position = Vector3(0, 0.7, 3.4)
	light.light_color = Color(1.0, 0.89, 0.75)
	light.light_energy = 3.0
	light.light_specular = 0.0
	light.spot_range = 6.0
	light.spot_angle = 53.0
	light.shadow_enabled = false
	add_child(light)


func _add_box(node_name: String, dimensions: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = node_name
	box.position = local_position
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	mesh.material = material
	box.mesh = mesh
	add_child(box)
	return box


func _label(value: String, local_position: Vector3, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = local_position
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 3
	label.modulate = Color(0.94, 0.91, 0.85)
	return label


func _build_detail_controls() -> void:
	_detail_layer = CanvasLayer.new()
	_detail_layer.name = "UpgradeDetailLayer"
	_detail_layer.layer = 15
	add_child(_detail_layer)
	_detail_controls = Control.new()
	_detail_controls.name = "UpgradeDetailControls"
	_detail_layer.add_child(_detail_controls)
	_detail_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_controls.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_controls.gui_input.connect(_on_detail_background_input)
	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_controls.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -250
	panel.offset_top = -62
	panel.offset_right = 250
	panel.offset_bottom = -20
	panel.add_theme_constant_override("separation", 12)
	_detail_caption = Label.new()
	_detail_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_caption.add_theme_font_override("font", FONT)
	_detail_caption.add_theme_font_size_override("font_size", 17)
	_detail_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_detail_caption)
	_detail_controls.hide()


func _on_detail_background_input(event: InputEvent) -> void:
	if _can_rotate_detail() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _detail_rotation.begin(_detail_card, camera, event.position):
			_detail_controls.accept_event()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		close_detail()
		_detail_controls.accept_event()
