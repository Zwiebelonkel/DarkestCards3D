extends Node3D
class_name GraveyardJester
## Presentation only: the collection manager commits each exact-copy offering
## and its reward before the optional dissolve animation starts.

signal modal_changed(opened: bool)

enum Mode { NONE, DIALOG, CANDIDATE, OFFERING, RECEIVED }

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const LAUGH_AUDIO_SCRIPT := preload("res://scripts/SatanLaughAudio.gd")
const DIALOGUE_STYLE := preload("res://scripts/ui/DialogueStyle.gd")
const SENTENCE_END_SOUND := preload("res://assets/sounds/SFX/sentenceEnd.mp3")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const GRAVES := {"chick": "Burials/Grave_27", "harald": "Burials/Grave_28"}
const DIALOGUE := "Ich wurde hier draußen zurückgelassen.\nMein Auge wurde mir genommen.\nAlles wurde mir genommen.\nWürdest du bitte ein Opfer hierlassen?"
const CLICK_LAYER := 1 << 15
const LAUGH_PITCH_OFFSET := 6.0
const IDLE_BOB_HEIGHT := 0.06
const IDLE_BOB_PERIOD := 2.8
const PANEL_SWIPE_DURATION := 0.24
const PANEL_EDGE_MARGIN := 24.0

@export var camera: Camera3D
@export var view_side := 1
@export_range(0.05, 2.0) var offering_duration := 0.7

var interaction_enabled := false
var focus_area: Area3D
var npc_area: Area3D
var grave_areas: Dictionary = {}
var _mode := Mode.NONE
var _candidate: Dictionary = {}
var _body_label: RichTextLabel
var _title_label: Label
var _choice_buttons: BoxContainer
var _sacrifice_button: Button
var _decline_button: Button
var _preview_card: Card3D
var _preview_entry_progress := 1.0
var _layer: CanvasLayer
var _panel: PanelContainer
var _modal_root: Control
var _offering_tween: Tween
var _selected_card_id := ""
var _message := ""
var _reward_data: Dictionary = {}
var _typing_characters := 0.0
var _laugh_audio: AudioStreamPlayer3D
var _sentence_end_audio: AudioStreamPlayer3D
var _actor: Node3D
var _actor_base_y := 0.0
var _idle_bob_phase := 0.0
var _seen_slot := 0
var _dialogue_sentences := PackedStringArray()
var _dialogue_sentence_index := -1
var _dialogue_waiting_for_continue := false
var _panel_swipe_tween: Tween
var _panel_slide_offset_y := 0.0
var _is_closing := false


func _ready() -> void:
	_seen_slot = SaveSlots.active_slot
	focus_area = _create_area(self, "JesterFocusArea", Vector3(-4.8, 1.4, -6.0), Vector3(3.4, 3.8, 3.0))
	(focus_area.get_child(0) as CollisionShape3D).position.y = 0.5
	focus_area.set_meta("focus_distance", 6.5)
	# This box is read directly by ScreenCameraFocus, never by physics picking.
	focus_area.collision_layer = 0
	_actor = get_node_or_null("jester") as Node3D
	var actor_position := _actor.position if _actor != null else Vector3(-5.65704, 2.06642, -5.99858)
	_actor_base_y = actor_position.y
	_laugh_audio = LAUGH_AUDIO_SCRIPT.new()
	_laugh_audio.name = "LaughSound"
	_laugh_audio.pitch_offset_semitones = LAUGH_PITCH_OFFSET
	if _actor != null:
		_actor.add_child(_laugh_audio)
	else:
		add_child(_laugh_audio)
		_laugh_audio.position = actor_position
	_sentence_end_audio = AudioStreamPlayer3D.new()
	_sentence_end_audio.name = "SentenceEndSound"
	_sentence_end_audio.stream = SENTENCE_END_SOUND
	_sentence_end_audio.bus = &"SFX"
	_sentence_end_audio.volume_db = -8.0
	_sentence_end_audio.unit_size = 5.0
	_sentence_end_audio.max_distance = 20.0
	_sentence_end_audio.position = _laugh_audio.position
	_laugh_audio.add_sibling(_sentence_end_audio)
	_sentence_end_audio.finished.connect(_sync_dialog_audio)
	npc_area = _create_area(self, "JesterClickArea", actor_position, Vector3(0.7, 3.3, 1.9))
	npc_area.input_event.connect(_on_npc_input)
	for card_id: String in GRAVES:
		var grave := get_node_or_null(GRAVES[card_id]) as Node3D
		if grave == null:
			continue
		var area := _create_area(grave, "OfferingArea", Vector3(0, 0.85, 0), Vector3(1.2, 1.7, 2.2))
		area.input_event.connect(_on_grave_input.bind(card_id))
		grave_areas[card_id] = area
	_create_modal()
	CollectionManager.collection_changed.connect(refresh_state)
	Localization.locale_changed.connect(_on_locale_changed)
	refresh_state()
	set_interaction_enabled(false)


func _create_area(parent: Node3D, area_name: String, center: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	parent.add_child(area)
	return area


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not enabled:
		close_dialog()
		_set_actor_hovered(false)
	if not is_instance_valid(focus_area):
		return
	focus_area.input_ray_pickable = enabled
	focus_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	for area: Area3D in _click_areas():
		area.input_ray_pickable = enabled
		area.collision_layer = CLICK_LAYER if enabled else 0
		area.set_meta("keep_input_ray_pickable_disabled", not enabled)


func _click_areas() -> Array[Area3D]:
	var areas: Array[Area3D] = []
	if is_instance_valid(npc_area):
		areas.append(npc_area)
	for area: Area3D in grave_areas.values():
		areas.append(area)
	return areas


func is_busy() -> bool:
	return _mode != Mode.NONE or _is_closing


func is_dialog_open() -> bool:
	return is_busy()


func _can_open() -> bool:
	return interaction_enabled and not is_busy() and not get_tree().paused and is_visible_in_tree() and is_instance_valid(camera) and camera.is_current()


func _set_mode(value: Mode) -> void:
	var was_busy := is_busy()
	_mode = value
	if is_busy():
		_set_actor_hovered(false)
	if _mode != Mode.DIALOG and is_instance_valid(_sentence_end_audio):
		_sentence_end_audio.stop()
	_sync_dialog_audio()
	if is_instance_valid(_layer):
		_layer.visible = is_busy()
	_refresh_choice_buttons()
	if was_busy != is_busy():
		modal_changed.emit(is_busy())


func open_dialog() -> bool:
	if not _can_open():
		return false
	_dialogue_sentences = _get_localized_dialogue_sentences()
	if _dialogue_sentences.is_empty():
		return false
	_dialogue_sentence_index = 0
	_dialogue_waiting_for_continue = false
	_set_mode(Mode.DIALOG)
	_show_dialogue_sentence()
	_start_panel_swipe_in()
	return true


func _get_localized_dialogue_sentences() -> PackedStringArray:
	var dialogue_key := "Dein Opfer ist nicht vergessen." if CollectionManager.get_jester_offering_state()["completed"] else DIALOGUE
	return Localization.text(dialogue_key).split("\n", false)


func _show_dialogue_sentence() -> void:
	if _dialogue_sentence_index < 0 or _dialogue_sentence_index >= _dialogue_sentences.size():
		return
	# Replace the previous line instead of accumulating it in the panel.
	_body_label.text = ""
	_body_label.visible_characters = 0
	_message = _dialogue_sentences[_dialogue_sentence_index]
	_dialogue_waiting_for_continue = false
	_typing_characters = 0.0
	_refresh_modal_text()
	_body_label.visible_characters = 0
	_sync_dialog_audio()


func _advance_to_next_dialogue_sentence() -> void:
	if _dialogue_sentence_index + 1 >= _dialogue_sentences.size():
		close_dialog()
		return
	_dialogue_sentence_index += 1
	_show_dialogue_sentence()


func open_grave(card_id: String) -> bool:
	if not _can_open() or not GRAVES.has(card_id):
		return false
	_selected_card_id = card_id
	_candidate = CollectionManager.get_jester_offering_candidate(card_id)
	if _candidate.get("ok", false):
		_message = "Dieses Holo-Exemplar wird dauerhaft geopfert." if CardData.is_holo(_candidate["instance"]) else "Dieses Exemplar wird dauerhaft geopfert."
	else:
		_message = str(_candidate.get("reason", ""))
	_set_mode(Mode.CANDIDATE)
	if _candidate.get("ok", false):
		_create_preview(_candidate["card_data"])
	_refresh_modal_text()
	_start_panel_swipe_in()
	return true


func _confirm_offering() -> void:
	if _mode != Mode.CANDIDATE or not interaction_enabled or get_tree().paused or not _candidate.get("ok", false) or _preview_entry_progress < 1.0:
		return
	var instance: Dictionary = _candidate.get("instance", {})
	var instance_id := str(instance.get("instance_id", ""))
	# Freeze the reviewed identity before calling the guarded, atomic backend.
	_set_mode(Mode.OFFERING)
	var result := CollectionManager.offer_jester_card(_selected_card_id, instance_id)
	if not result.get("ok", false):
		_candidate = {}
		_message = str(result.get("reason", ""))
		_clear_preview()
		_set_mode(Mode.CANDIDATE)
		_refresh_modal_text()
		return
	_candidate = {}
	_message = "Opfer angenommen."
	_refresh_modal_text()
	if not is_instance_valid(_preview_card):
		_finish_offering(result)
		return
	var grave := get_node(GRAVES[_selected_card_id]) as Node3D
	var destination := grave.to_global(Vector3(0, 0.65, -0.6))
	_preview_card.begin_death_dissolve()
	_offering_tween = create_tween().set_parallel(true)
	_offering_tween.tween_property(_preview_card, "global_position", destination, offering_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_offering_tween.tween_property(_preview_card, "scale", _preview_card.scale * 0.25, offering_duration)
	_offering_tween.tween_method(_preview_card.set_death_dissolve_progress, 0.0, 1.0, offering_duration)
	_offering_tween.chain().tween_callback(_finish_offering.bind(result))


func _finish_offering(result: Dictionary) -> void:
	if _mode != Mode.OFFERING or not interaction_enabled:
		return
	_offering_tween = null
	_clear_preview()
	_reward_data = result.get("reward_card_data", {}).duplicate(true)
	_set_mode(Mode.RECEIVED)
	if not _reward_data.is_empty():
		_create_preview(_reward_data)
	_refresh_modal_text()


func close_dialog() -> void:
	if not is_busy() or _is_closing:
		return
	_is_closing = true
	if _offering_tween != null and _offering_tween.is_valid():
		_offering_tween.kill()
	_offering_tween = null
	_clear_preview()
	_candidate = {}
	_reward_data = {}
	_selected_card_id = ""
	_message = ""
	_dialogue_sentences = PackedStringArray()
	_dialogue_sentence_index = -1
	_dialogue_waiting_for_continue = false
	_set_mode(Mode.NONE)
	_start_panel_swipe_out()


func refresh_state(_ids: Array[String] = []) -> void:
	if _seen_slot != SaveSlots.active_slot:
		close_dialog()
		_seen_slot = SaveSlots.active_slot
	var state := CollectionManager.get_jester_offering_state()
	for card_id: String in GRAVES:
		var inscription := get_node_or_null(str(GRAVES[card_id]) + "/Inscription") as Label3D
		if inscription != null:
			inscription.text = _card_name(card_id)
			if state["offered"].has(card_id):
				inscription.text += "\n" + Localization.text("Geopfert")


func _card_name(card_id: String) -> String:
	return Localization.text(str(CardDatabase.get_card(card_id).get("name", card_id)))


func _on_locale_changed() -> void:
	refresh_state()
	if _mode != Mode.DIALOG:
		if is_busy() and not _is_closing:
			_refresh_modal_text()
		return
	var was_typing := _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count()
	var previous_total := maxi(_body_label.get_total_character_count(), 1)
	var reveal_fraction := clampf(_typing_characters / float(previous_total), 0.0, 1.0)
	_dialogue_sentences = _get_localized_dialogue_sentences()
	_dialogue_sentence_index = clampi(_dialogue_sentence_index, 0, _dialogue_sentences.size() - 1)
	if _dialogue_sentences.is_empty() or _dialogue_sentence_index < 0:
		close_dialog()
		return
	_message = _dialogue_sentences[_dialogue_sentence_index]
	_refresh_modal_text()
	if was_typing:
		_typing_characters = reveal_fraction * _body_label.get_total_character_count()
		_body_label.visible_characters = int(_typing_characters)
	else:
		_body_label.visible_characters = -1
	_layout_modal()
	_sync_dialog_audio()


func _on_npc_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _pointer_hits_area(event.position, npc_area) and open_dialog():
			get_viewport().set_input_as_handled()


func _on_grave_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int, card_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _pointer_hits_area(event.position, grave_areas.get(card_id)) and open_grave(card_id):
			get_viewport().set_input_as_handled()


func _pointer_hits_area(pointer: Vector2, area: Area3D) -> bool:
	if not _can_open() or not is_instance_valid(area):
		return false
	if not area.input_ray_pickable or not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, CLICK_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Picking can emit for overlapping boxes. Only the frontmost station
	# target may react, independently of the engine's callback order.
	return hit.get("collider") == area


func _set_actor_hovered(hovered: bool) -> void:
	if is_instance_valid(_actor) and _actor.has_method("set_hovered"):
		_actor.call("set_hovered", hovered)


func _update_pointer_hover() -> void:
	_set_actor_hovered(_pointer_hits_area(get_viewport().get_mouse_position(), npc_area))


func _input(event: InputEvent) -> void:
	if not is_busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel")):
		close_dialog()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	# The full-screen modal GUI consumes background clicks. Only its two real
	# buttons decide an offering; GUI dispatch needs both press and release.
	if _mode == Mode.CANDIDATE and not _is_closing:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
	# Handle before GUI and physics dispatch. A click that closes a modal must
	# never open the grave or NPC behind it, or repeat an offering transaction.
	get_viewport().set_input_as_handled()
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	match _mode:
		Mode.DIALOG:
			if _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count():
				_typing_characters = float(_body_label.get_total_character_count())
				_body_label.visible_characters = -1
				_dialogue_waiting_for_continue = true
				_play_sentence_end()
			else:
				_advance_to_next_dialogue_sentence()
		Mode.OFFERING, Mode.RECEIVED:
			close_dialog()


func _on_sacrifice_pressed() -> void:
	get_viewport().set_input_as_handled()
	if not _is_closing:
		_confirm_offering()


func _on_decline_pressed() -> void:
	get_viewport().set_input_as_handled()
	if _mode == Mode.CANDIDATE and not _is_closing:
		close_dialog()


func _sync_dialog_audio() -> void:
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(_mode == Mode.DIALOG and not _dialogue_waiting_for_continue and _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count() and not _sentence_end_audio.playing)


func _play_sentence_end() -> void:
	_laugh_audio.set_laughing(false)
	if not _sentence_end_audio.playing:
		_sentence_end_audio.play()


func _advance_dialog_text(delta: float) -> void:
	if _dialogue_waiting_for_continue or _sentence_end_audio.playing:
		return
	var dialogue := _body_label.get_parsed_text()
	_typing_characters = minf(_typing_characters + delta * 32.0, dialogue.length())
	_body_label.visible_characters = int(_typing_characters)
	if _typing_characters >= dialogue.length():
		_body_label.visible_characters = -1
		_dialogue_waiting_for_continue = true
		_play_sentence_end()
	_sync_dialog_audio()


func _process(delta: float) -> void:
	_update_pointer_hover()
	if is_instance_valid(_actor) and _actor.is_visible_in_tree():
		_idle_bob_phase = fmod(_idle_bob_phase + delta * TAU / IDLE_BOB_PERIOD, TAU)
		# Move the sprite around its authored height; keep camera focus and picking steady.
		_actor.position.y = _actor_base_y + sin(_idle_bob_phase) * IDLE_BOB_HEIGHT
	if not is_busy():
		return
	if not is_instance_valid(camera) or not camera.is_current() or not is_visible_in_tree():
		close_dialog()
		return
	_layout_modal()
	if _mode == Mode.DIALOG and _body_label.visible_characters >= 0:
		_advance_dialog_text(delta)
	if _mode in [Mode.CANDIDATE, Mode.RECEIVED]:
		_position_preview()


func _create_preview(data: Dictionary) -> void:
	_clear_preview()
	_preview_entry_progress = 0.0 if _mode == Mode.CANDIDATE else 1.0
	_preview_card = CARD_SCENE.instantiate() as Card3D
	add_child(_preview_card)
	_preview_card.setup(data)
	_preview_card.description_label.skip()
	_disable_card_input(_preview_card)
	_position_preview()


func _disable_card_input(node: Node) -> void:
	if node is CollisionObject3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)


func _position_preview() -> void:
	if not is_instance_valid(_preview_card) or not is_instance_valid(camera):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	# Match the dialog's slide-in while keeping the whole starting card below
	# the viewport. The camera-plane path preserves the authored size and pose.
	var screen_y := lerpf(viewport_size.y * 1.5, viewport_size.y * 0.31, _preview_entry_progress)
	var origin := camera.project_position(Vector2(viewport_size.x * 0.5, screen_y), 2.5)
	_preview_card.global_transform = Transform3D(camera.global_basis.orthonormalized().scaled(Vector3.ONE * 0.85), origin)


func _set_preview_entry_progress(progress: float) -> void:
	_preview_entry_progress = clampf(progress, 0.0, 1.0)
	_position_preview()


func _clear_preview() -> void:
	if is_instance_valid(_preview_card):
		_preview_card.hide()
		_preview_card.queue_free()
	_preview_card = null
	_preview_entry_progress = 1.0


func _create_modal() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "JesterDialog"
	_layer.layer = 50
	add_child(_layer)
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_modal_root)
	_panel = PanelContainer.new()
	_panel.name = "DialogPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.04, 0.97)
	style.border_color = Color(0.48, 0.56, 0.43, 1)
	style.set_border_width_all(2)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	_modal_root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	_title_label = Label.new()
	_title_label.add_theme_font_override("font", FONT)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", DIALOGUE_STYLE.JESTER)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title_label)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = false
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size.y = 52
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.add_theme_font_override("normal_font", FONT)
	_body_label.add_theme_font_size_override("normal_font_size", 21)
	_body_label.add_theme_color_override("default_color", Color(0.82, 0.86, 0.79))
	column.add_child(_body_label)
	_choice_buttons = BoxContainer.new()
	_choice_buttons.name = "OfferingChoices"
	_choice_buttons.add_theme_constant_override("separation", 14)
	column.add_child(_choice_buttons)
	_sacrifice_button = _create_choice_button("SacrificeButton", true)
	_decline_button = _create_choice_button("DeclineButton", false)
	_sacrifice_button.pressed.connect(_on_sacrifice_pressed)
	_decline_button.pressed.connect(_on_decline_pressed)
	_refresh_choice_buttons()
	_layer.hide()


func _create_choice_button(button_name: String, sacrifice: bool) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color(0.92, 0.94, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.44, 0.4))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.19, 0.24, 0.14) if sacrifice else Color(0.055, 0.075, 0.075)
	normal.border_color = Color(0.58, 0.66, 0.4) if sacrifice else Color(0.36, 0.43, 0.36)
	normal.set_border_width_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.13)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.24)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.04, 0.05, 0.045)
	disabled.border_color = Color(0.19, 0.23, 0.19)
	button.add_theme_stylebox_override("disabled", disabled)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(0.88, 0.91, 0.74)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	_choice_buttons.add_child(button)
	return button


func _refresh_choice_buttons() -> void:
	if not is_instance_valid(_choice_buttons):
		return
	var choosing := _mode == Mode.CANDIDATE and not _is_closing
	# Preserve the outgoing panel's shape during its existing swipe animation.
	_choice_buttons.visible = choosing or (_is_closing and _choice_buttons.visible)
	_sacrifice_button.text = Localization.text("Opfern")
	_decline_button.text = Localization.text("Nicht opfern")
	_sacrifice_button.disabled = not choosing or not _candidate.get("ok", false) or not interaction_enabled or get_tree().paused or _preview_entry_progress < 1.0
	_decline_button.disabled = not choosing


func _refresh_modal_text() -> void:
	_sentence_end_audio.stop()
	_title_label.text = Localization.text("Der Narr")
	_body_label.text = Localization.text(_message)
	_body_label.visible_characters = -1
	if _mode == Mode.CANDIDATE:
		_title_label.text = Localization.format_text("Opfer für %s", [_card_name(_selected_card_id)])
	elif _mode == Mode.RECEIVED and not _reward_data.is_empty():
		_title_label.text = Localization.format_text("Erhalten: %s", [Localization.text(str(_reward_data.get("name", "")))])
		_body_label.text = Localization.text("Dein Opfer ist nicht vergessen.")
	_refresh_choice_buttons()
	_sync_dialog_audio()
	_layout_modal()


func _layout_modal() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := maxf(280.0, minf(760.0, viewport_size.x - PANEL_EDGE_MARGIN * 2.0))
	_choice_buttons.vertical = width < 520.0
	_panel.size.x = width
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = _panel_rest_position(viewport_size) + Vector2(0, _panel_slide_offset_y)


func _panel_rest_position(viewport_size: Vector2) -> Vector2:
	return Vector2((viewport_size.x - _panel.size.x) * 0.5, viewport_size.y - _panel.size.y - PANEL_EDGE_MARGIN)


func _panel_swipe_distance() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	return maxf(PANEL_EDGE_MARGIN * 2.0, viewport_size.y - _panel_rest_position(viewport_size).y + PANEL_EDGE_MARGIN)


func _set_panel_slide_offset(offset_y: float) -> void:
	_panel_slide_offset_y = offset_y
	if is_instance_valid(_panel):
		_layout_modal()


func _cancel_panel_swipe() -> void:
	if _panel_swipe_tween != null and _panel_swipe_tween.is_valid():
		_panel_swipe_tween.kill()
	_panel_swipe_tween = null


func _start_panel_swipe_in() -> void:
	if not is_instance_valid(_panel):
		return
	_cancel_panel_swipe()
	_set_panel_slide_offset(_panel_swipe_distance())
	_panel_swipe_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_panel_swipe_tween.tween_method(_set_panel_slide_offset, _panel_slide_offset_y, 0.0, PANEL_SWIPE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _mode == Mode.CANDIDATE and is_instance_valid(_preview_card):
		_panel_swipe_tween.tween_method(_set_preview_entry_progress, 0.0, 1.0, PANEL_SWIPE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_swipe_tween.chain().tween_callback(_finish_panel_swipe_in)


func _finish_panel_swipe_in() -> void:
	if not _is_closing:
		_panel_swipe_tween = null
		_refresh_choice_buttons()


func _start_panel_swipe_out() -> void:
	if not is_instance_valid(_panel) or not is_inside_tree():
		_finish_close()
		return
	_cancel_panel_swipe()
	_layout_modal()
	_panel_swipe_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_panel_swipe_tween.tween_method(_set_panel_slide_offset, _panel_slide_offset_y, _panel_swipe_distance(), PANEL_SWIPE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_swipe_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	if not _is_closing:
		return
	_panel_swipe_tween = null
	_panel_slide_offset_y = 0.0
	_is_closing = false
	if is_instance_valid(_layer):
		_layer.hide()
	modal_changed.emit(false)


func _exit_tree() -> void:
	if _offering_tween != null and _offering_tween.is_valid():
		_offering_tween.kill()
	_cancel_panel_swipe()
	_is_closing = false
