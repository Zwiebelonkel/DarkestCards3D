extends Control
class_name EventHandUI

## The hand is private presentation only. GameTable validates and resolves plays.
signal event_selected(uid: String)
signal selection_cancelled

const CARD_SIZE := Vector2(198.0, 314.0)
const PEEK_HEIGHT := 48.0
const CARD_GAP := 10.0
const TITLE_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

var _hand: Array[Dictionary] = []
var _cards: Array[EventHandCard] = []
var _playable := false
var _selected_uid := ""
var _status := ""
var _hovered_uid := ""
var _page := 0
var _page_size := 6
var _hand_scale := 1.0
var _status_label: Label
var _previous_button: Button
var _next_button: Button
var _played_events_root: Control
var _played_event_tweens: Array[Tween] = []
var _built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_status_label = Label.new()
	_status_label.name = "EventHandStatus"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color("c7bacd"))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.025, 0.95))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_status_label)
	_previous_button = _make_page_button("‹", -1)
	_next_button = _make_page_button("›", 1)
	# Public reveals also appear to spectators, whose private hand is hidden.
	_played_events_root = Control.new()
	_played_events_root.name = "PlayedEventCards"
	_played_events_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_played_events_root.clip_contents = true
	_played_events_root.z_index = 10
	get_parent().add_child(_played_events_root)
	_played_events_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_built = true
	resized.connect(_layout_hand)
	Localization.locale_changed.connect(_on_locale_changed)
	_rebuild_cards()
	_layout_hand()


func configure(
	hand: Array[Dictionary],
	playable: bool,
	selected_uid: String = "",
	status: String = "",
	visible_for_player: bool = true
) -> void:
	var changed := _hand != hand
	if not changed and _playable == playable and _selected_uid == selected_uid and _status == status and visible == visible_for_player:
		return
	if changed:
		_hand = hand.duplicate(true)
	_playable = playable
	_selected_uid = selected_uid
	_status = status
	visible = visible_for_player
	if not visible:
		_hovered_uid = ""
	if not _built:
		return
	if changed:
		_rebuild_cards()
	for card in _cards:
		var was_hovered := card.uid == _hovered_uid
		card.set_hand_state(_playable, _selected_uid)
		if was_hovered:
			_hovered_uid = card.uid
	_layout_hand()


func play_event(event: Dictionary, from_opponent: bool = false) -> void:
	if not _built or not is_instance_valid(_played_events_root):
		return
	var card := EventHandCard.new()
	card.data = event.duplicate(true)
	card.size = CARD_SIZE
	card.z_index = 5
	_played_events_root.add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_state(false, true)
	card.set_action_caption("GEGNER SPIELT" if from_opponent else "EVENT AUSGESPIELT")
	var reveal_scale := _hand_scale * 0.95
	card.scale = Vector2.ONE * reveal_scale
	card.pivot_offset = CARD_SIZE * 0.5
	card.position = Vector2(
		(size.x - CARD_SIZE.x) * 0.5,
		-CARD_SIZE.y - 20.0 if from_opponent else size.y - PEEK_HEIGHT
	)
	card.rotation_degrees = 5.0 if from_opponent else -5.0
	var landing := Vector2((size.x - CARD_SIZE.x) * 0.5, maxf(20.0, size.y * 0.42 - CARD_SIZE.y * 0.5))
	var animation := _played_events_root.create_tween()
	for index in range(_played_event_tweens.size() - 1, -1, -1):
		if not _played_event_tweens[index].is_valid():
			_played_event_tweens.remove_at(index)
	_played_event_tweens.append(animation)
	animation.set_parallel(true)
	animation.tween_property(card, "position", landing, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(card, "rotation_degrees", 0.0, 0.24)
	animation.set_parallel(false)
	animation.tween_interval(0.38)
	animation.tween_property(card, "modulate:a", 0.0, 0.2)
	animation.tween_callback(card.queue_free)


func clear_played_events() -> void:
	for animation in _played_event_tweens:
		if animation.is_valid():
			animation.kill()
	_played_event_tweens.clear()
	if is_instance_valid(_played_events_root):
		for card in _played_events_root.get_children():
			card.hide()
			card.queue_free()


func _exit_tree() -> void:
	clear_played_events()
	if is_instance_valid(_played_events_root) and not _played_events_root.is_queued_for_deletion():
		_played_events_root.queue_free()


func _make_page_button(caption: String, direction: int) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 27)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17101f")
	style.border_color = Color("60516e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(_change_page.bind(direction))
	button.tooltip_text = "Weitere Event-Karten"
	add_child(button)
	return button


func _rebuild_cards() -> void:
	var hovered_identity: Dictionary = {}
	var previous_order: Array[Dictionary] = []
	for card in _cards:
		previous_order.append(_event_identity(card.data))
		if card.uid == _hovered_uid:
			hovered_identity = _event_identity(card.data)
		remove_child(card)
		card.queue_free()
	_cards.clear()
	_hovered_uid = ""
	var identities: Array[Dictionary] = []
	for data in _hand:
		var identity := _event_identity(data)
		var stack_index := identities.find(identity)
		if stack_index >= 0:
			_cards[stack_index].instances.append(data)
			continue
		var card := EventHandCard.new()
		card.data = data
		card.instances.append(data)
		card.size = CARD_SIZE
		card.activated.connect(_on_card_activated)
		card.cancelled.connect(_cancel_selection)
		identities.append(identity)
		_cards.append(card)
	# Playing the first physical copy must not move its remaining stack sideways.
	var ordered_cards: Array[EventHandCard] = []
	for identity in previous_order:
		var index := identities.find(identity)
		if index >= 0:
			ordered_cards.append(_cards[index])
	for card in _cards:
		if not ordered_cards.has(card):
			ordered_cards.append(card)
	_cards = ordered_cards
	for card in _cards:
		card.set_hand_state(_playable, _selected_uid)
		add_child(card)
		if _event_identity(card.data) == hovered_identity:
			_hovered_uid = card.uid


func _event_identity(data: Dictionary) -> Dictionary:
	# Physical copies differ only by UID. All other fields must match, including
	# the exact effect/multiplier; similar-looking event variants stay separate.
	var identity := data.duplicate()
	identity.erase("uid")
	return identity


func _layout_hand() -> void:
	if not _built:
		return
	_hand_scale = clampf(minf(size.x / 1100.0, size.y / 690.0), 0.72, 1.2)
	var card_width := CARD_SIZE.x * _hand_scale
	var available_width := maxf(size.x - 116.0, card_width)
	_page_size = maxi(1, int(floor(available_width / (card_width + CARD_GAP))))
	var page_count := maxi(1, int(ceil(float(_cards.size()) / float(_page_size))))
	_page = clampi(_page, 0, page_count - 1)
	# Keep a selected target card on screen when resizing or receiving a snapshot.
	for index in range(_cards.size()):
		if _cards[index].uid == _selected_uid:
			_page = index / _page_size
	var first := _page * _page_size
	var shown := mini(_page_size, _cards.size() - first)
	var row_width := shown * card_width + maxi(0, shown - 1) * CARD_GAP
	var start_x := (size.x - row_width) * 0.5
	for index in range(_cards.size()):
		var card := _cards[index]
		card.visible = index >= first and index < first + shown
		card.scale = Vector2.ONE * _hand_scale
		card.position.x = start_x + (index - first) * (card_width + CARD_GAP)
		if not card.has_meta("positioned"):
			card.position.y = size.y - PEEK_HEIGHT * _hand_scale
			card.set_meta("positioned", true)
	_previous_button.visible = page_count > 1
	_next_button.visible = page_count > 1
	_previous_button.disabled = _page == 0
	_next_button.disabled = _page == page_count - 1
	_previous_button.position = Vector2(maxf(6.0, start_x - 48.0), size.y - 44.0)
	_next_button.position = Vector2(minf(size.x - 44.0, start_x + row_width + 8.0), size.y - 44.0)
	_previous_button.size = Vector2(38.0, 36.0)
	_next_button.size = Vector2(38.0, 36.0)
	_refresh_status()


func _process(delta: float) -> void:
	if not _built or not is_visible_in_tree():
		return
	_update_hover(get_local_mouse_position())
	_animate_hand(delta)


func _animate_hand(delta: float) -> void:
	var expanded := false
	var speed := 1.0 - exp(-delta * 19.0)
	for card in _cards:
		if not card.visible:
			continue
		# Target selection must leave every board card reachable once the pointer
		# returns to the table. Its outline and title remain in the bottom strip.
		var raised := card.uid == _hovered_uid
		expanded = expanded or raised
		# The raised card still reaches the bottom edge: the pointer remains over
		# the card after it rises, so hovering never oscillates open and closed.
		var target_y := size.y - (CARD_SIZE.y - 4.0 if raised else PEEK_HEIGHT) * _hand_scale
		card.position.y = lerpf(card.position.y, target_y, speed)
		card.set_hovered(card.uid == _hovered_uid)
		card.z_index = 2 if raised else 0
	var label_y := size.y - ((CARD_SIZE.y + 29.0) if expanded else (PEEK_HEIGHT + 31.0)) * _hand_scale
	_status_label.position = Vector2(18.0, label_y)
	_status_label.size = Vector2(maxf(0.0, size.x - 36.0), 29.0 * _hand_scale)


func _update_hover(pointer: Vector2) -> void:
	var hovered := ""
	# Each distinct event stack has its own reachable header and exposed edges.
	for card in _cards:
		if not card.visible:
			continue
		var stack_peek := card.stack_peek_height() * _hand_scale
		var bottom_strip := Rect2(
			Vector2(card.position.x, size.y - PEEK_HEIGHT * _hand_scale - stack_peek),
			Vector2(CARD_SIZE.x * _hand_scale, PEEK_HEIGHT * _hand_scale + stack_peek)
		)
		if bottom_strip.has_point(pointer):
			hovered = card.uid
			break
	if hovered.is_empty():
		for card in _cards:
			var stack_peek := card.stack_peek_height() * _hand_scale
			var card_rect := Rect2(card.position - Vector2(0, stack_peek), CARD_SIZE * _hand_scale + Vector2(0, stack_peek))
			if card.visible and card_rect.has_point(pointer):
				hovered = card.uid
				break
	_hovered_uid = hovered


func _refresh_status() -> void:
	var caption := Localization.format_text("EVENT-HAND · %d", [_hand.size()])
	if _cards.size() > _page_size:
		caption += " · %d/%d" % [_page + 1, int(ceil(float(_cards.size()) / float(_page_size)))]
	if not _status.is_empty():
		caption += "   —   " + Localization.text(_status)
	elif _hand.is_empty():
		caption += "   —   " + Localization.text("Nur durch Karteneffekte erhältlich")
	elif not _selected_uid.is_empty():
		caption += "   —   " + Localization.text("Ziel auf dem Tisch wählen · Esc: Abbrechen")
	elif _playable:
		caption += "   —   " + Localization.text("Ansehen: Hover · Ausspielen: Klick · Danach angreifen")
	else:
		caption += "   —   " + Localization.text("Ausspielbar im eigenen Zug vor dem Angriff")
	_status_label.text = caption
	_status_label.visible = not _hand.is_empty() or not _status.is_empty()


func _on_locale_changed() -> void:
	if _built and is_inside_tree() and not is_queued_for_deletion():
		# Text only: preserve paging, pointer state and all card/reveal motion.
		_refresh_status()


func _change_page(direction: int) -> void:
	if not _selected_uid.is_empty():
		_cancel_selection()
	_page += direction
	_hovered_uid = ""
	_layout_hand()


func _on_card_activated(uid: String) -> void:
	if not _playable:
		return
	if uid == _selected_uid:
		_cancel_selection()
	else:
		event_selected.emit(uid)


func _cancel_selection() -> void:
	if not _selected_uid.is_empty():
		selection_cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _selected_uid.is_empty():
		return
	var cancel := event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton:
		cancel = cancel or (event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	if cancel:
		_cancel_selection()
		get_viewport().set_input_as_handled()


class EventHandCard extends Control:
	signal activated(uid: String)
	signal cancelled

	const STACK_OFFSET := 7.0
	const MAX_STACK_LAYERS := 2

	var uid := ""
	var data: Dictionary = {}
	var instances: Array[Dictionary] = []
	var _playable := false
	var _selected := false
	var _hovered := false
	var _accent := Color("ad96c7")
	var _body_style: StyleBoxFlat
	var _stack_style: StyleBoxFlat
	var _action_label: Label
	var _title_label: Label
	var _rarity_label: Label
	var _description_label: Label
	var _action_caption := ""


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		var rarity := str(data.get("rarity", "common"))
		match rarity:
			"uncommon": _accent = Color("90c6ba")
			"rare": _accent = Color("bca0ed")
			"epic": _accent = Color("e19eca")
			"legendary", "mythic", "god": _accent = Color("e1bb6c")
		_body_style = StyleBoxFlat.new()
		_body_style.bg_color = Color("17101e")
		_body_style.border_color = _accent.darkened(0.32)
		_body_style.set_border_width_all(2)
		_body_style.set_corner_radius_all(7)
		_body_style.shadow_color = Color(0.0, 0.0, 0.0, 0.68)
		_body_style.shadow_size = 12
		_body_style.shadow_offset = Vector2(0, 2)
		_stack_style = _body_style.duplicate() as StyleBoxFlat
		_stack_style.shadow_size = 0
		_stack_style.bg_color = Color("211729")
		_title_label = _add_label("", Vector2(10, 9), Vector2(178, 29), 21, _accent, true)
		if instances.size() > 1:
			_title_label.size.x = 136
			_add_label("×%d" % instances.size(), Vector2(151, 10), Vector2(37, 27), 15, _accent)
		_rarity_label = _add_label("", Vector2(12, 111), Vector2(174, 18), 10, _accent.darkened(0.12))
		_description_label = _add_label("", Vector2(16, 132), Vector2(166, 130), 13, Color("eee5e9"))
		_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_description_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_description_label.size = Vector2(166, 130)
		_action_label = _add_label("", Vector2(10, 273), Vector2(178, 28), 11, _accent)
		Localization.locale_changed.connect(_refresh_localized_text)
		_refresh_localized_text()


	func _refresh_localized_text() -> void:
		if not is_inside_tree() or is_queued_for_deletion():
			return
		_title_label.text = Localization.text(str(data.get("name", "Event"))).to_upper()
		_rarity_label.text = Localization.rarity_name(str(data.get("rarity", "common")), true)
		_description_label.text = Localization.text(str(data.get("description", "")))
		_fit_single_line(_title_label, 21, 15)
		_fit_single_line(_rarity_label, 10, 9)
		for description_size in [13, 12, 11]:
			_description_label.add_theme_font_size_override("font_size", description_size)
			var text_size := _description_label.get_theme_font("font").get_multiline_string_size(_description_label.text, HORIZONTAL_ALIGNMENT_CENTER, 166, description_size)
			if text_size.y <= 122:
				break
		_refresh_action()


	func _fit_single_line(label: Label, starting_size: int, minimum_size: int) -> void:
		for font_size in range(starting_size, minimum_size - 1, -1):
			label.add_theme_font_size_override("font_size", font_size)
			if label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x <= label.size.x:
				break


	func set_action_caption(source: String) -> void:
		# Public reveal captions persist independently of hand playability.
		_action_caption = source
		_refresh_action()


	func _add_label(text: String, origin: Vector2, dimensions: Vector2, font_size: int, color: Color, title: bool = false) -> Label:
		var label := Label.new()
		label.text = text
		label.position = origin
		label.size = dimensions
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		if title:
			label.add_theme_font_override("font", EventHandUI.TITLE_FONT)
		add_child(label)
		return label


	func set_state(playable: bool, selected: bool) -> void:
		_playable = playable
		_selected = selected
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if playable else Control.CURSOR_ARROW
		_refresh_action()
		queue_redraw()


	func set_hand_state(playable: bool, selected_uid: String) -> void:
		# Keep the actual selected copy addressable across snapshots and rebuilds.
		data = instances[0]
		for instance in instances:
			if str(instance.get("uid", "")) == selected_uid:
				data = instance
				break
		uid = str(data.get("uid", ""))
		set_state(playable, uid == selected_uid)


	func stack_peek_height() -> float:
		return mini(MAX_STACK_LAYERS, maxi(0, instances.size() - 1)) * STACK_OFFSET


	func set_hovered(hovered: bool) -> void:
		if _hovered == hovered:
			return
		_hovered = hovered
		queue_redraw()


	func _refresh_action() -> void:
		if _action_label == null:
			return
		var source := _action_caption
		if source.is_empty():
			if not _playable:
				source = "VOR DEINEM ANGRIFF SPIELEN"
			elif str(data.get("target", "none")) == "none":
				source = "KLICK → DIREKT SPIELEN"
			elif _selected:
				source = "ZIEL WÄHLEN · KLICK: ABBRUCH"
			elif str(data.get("target", "none")) == "ally":
				source = "KLICK → EIGENE KARTE WÄHLEN"
			elif str(data.get("target", "none")) == "enemy":
				source = "KLICK → GEGNERKARTE WÄHLEN"
			else:
				source = "KLICK → AUSSPIELEN"
		_action_label.text = Localization.text(source)
		_fit_single_line(_action_label, 11, 9)


	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _playable:
				activated.emit(uid)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			cancelled.emit()


	func _draw() -> void:
		if _body_style == null:
			return
		var ink := _accent if _playable or _hovered else _accent.darkened(0.25)
		_body_style.border_color = ink if _hovered or _selected else ink.darkened(0.4)
		_body_style.bg_color = Color("25192e") if _selected else Color("17101e")
		_stack_style.border_color = ink.darkened(0.4)
		var layers := mini(MAX_STACK_LAYERS, maxi(0, instances.size() - 1))
		for layer in range(layers, 0, -1):
			draw_style_box(_stack_style, Rect2(Vector2(0, -layer * STACK_OFFSET), size))
		draw_style_box(_body_style, Rect2(Vector2.ZERO, size))
		draw_line(Vector2(14, 44), Vector2(184, 44), Color(ink, 0.4), 1.0)
		draw_line(Vector2(14, 263), Vector2(184, 263), Color(ink, 0.3), 1.0)
		var center := Vector2(99, 80)
		draw_arc(center, 25, 0, TAU, 48, Color(ink, 0.2), 1.0, true)
		draw_arc(center, 30, -PI * 0.42, PI * 0.42, 24, Color(ink, 0.48), 1.0, true)
		draw_arc(center, 30, PI * 0.58, PI * 1.42, 24, Color(ink, 0.48), 1.0, true)
		var event_id := str(data.get("id", ""))
		if event_id.begins_with("switch"):
			_draw_arrow(center + Vector2(-15, -7), center + Vector2(15, -7), ink)
			_draw_arrow(center + Vector2(15, 7), center + Vector2(-15, 7), ink)
		elif event_id.begins_with("block"):
			var shield := PackedVector2Array([center + Vector2(-15, -15), center + Vector2(15, -15), center + Vector2(12, 8), center + Vector2(0, 18), center + Vector2(-12, 8), center + Vector2(-15, -15)])
			draw_polyline(shield, ink, 2.0, true)
			draw_line(center + Vector2(-8, 1), center + Vector2(8, 1), ink, 3.0, true)
		elif event_id.begins_with("steal") or event_id.begins_with("steel"):
			draw_rect(Rect2(center + Vector2(-16, -17), Vector2(19, 28)), Color(ink, 0.35), false, 2.0)
			draw_rect(Rect2(center + Vector2(-2, -10), Vector2(19, 28)), ink, false, 2.0)
			_draw_arrow(center + Vector2(-9, 5), center + Vector2(11, 5), ink)
		elif event_id == "rearrange_event":
			_draw_arrow(center + Vector2(-18, -9), center + Vector2(18, -9), ink)
			_draw_arrow(center + Vector2(18, 9), center + Vector2(-18, 9), ink)
		elif event_id == "heal_event":
			draw_line(center + Vector2(-17, 0), center + Vector2(17, 0), ink, 9.0, true)
			draw_line(center + Vector2(0, -17), center + Vector2(0, 17), ink, 9.0, true)
		elif event_id == "piss_event":
			var arc := PackedVector2Array([
				center + Vector2(-21, -9), center + Vector2(-15, -18),
				center + Vector2(-7, -21), center + Vector2(2, -19),
				center + Vector2(10, -11), center + Vector2(16, 3),
			])
			draw_polyline(arc, ink, 3.0, true)
			draw_circle(center + Vector2(18, 9), 2.5, ink, true, -1.0, true)
			draw_arc(center + Vector2(12, 17), 12, 0.0, PI, 20, ink, 2.0, true)
			draw_line(center + Vector2(-2, 17), center + Vector2(26, 17), Color(ink, 0.5), 2.0, true)
		else:
			_draw_arrow(center + Vector2(0, 17), center + Vector2(0, -17), ink)
			draw_line(center + Vector2(-12, 8), center + Vector2(-12, -5), ink, 2.0, true)
			draw_line(center + Vector2(12, 8), center + Vector2(12, -5), ink, 2.0, true)
		if _selected:
			draw_circle(Vector2(183, 45 if instances.size() > 1 else 17), 4.0, ink)


	func _draw_arrow(start: Vector2, end: Vector2, ink: Color) -> void:
		var direction := (end - start).normalized()
		var side := Vector2(-direction.y, direction.x)
		draw_line(start, end, ink, 2.2, true)
		draw_polyline(PackedVector2Array([end - direction * 7 + side * 6, end, end - direction * 7 - side * 6]), ink, 2.2, true)
