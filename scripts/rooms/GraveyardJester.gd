extends Node3D
class_name GraveyardJester
## Presentation only: the collection manager commits each exact-copy offering
## and its reward before the optional dissolve animation starts.

signal modal_changed(opened: bool)

enum Mode { NONE, DIALOG, CANDIDATE, OFFERING, RECEIVED }

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const LAUGH_AUDIO_SCRIPT := preload("res://scripts/SatanLaughAudio.gd")
const SENTENCE_END_SOUND := preload("res://assets/sounds/SFX/sentenceEnd.mp3")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const GRAVES := {"chick": "Burials/Grave_27", "harald": "Burials/Grave_28"}
const DIALOGUE := "Ich wurde hier draußen zurückgelassen.\nMein Auge wurde mir genommen.\nAlles wurde mir genommen.\nWürdest du bitte ein Opfer hierlassen?"
const CLICK_LAYER := 1 << 15
const LAUGH_PITCH_OFFSET := 6.0
const IDLE_BOB_HEIGHT := 0.06
const IDLE_BOB_PERIOD := 2.8

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
var _preview_card: Card3D
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
	return _mode != Mode.NONE


func is_dialog_open() -> bool:
	return is_busy()


func _can_open() -> bool:
	return interaction_enabled and not is_busy() and not get_tree().paused and is_visible_in_tree() and is_instance_valid(camera) and camera.is_current()


func _set_mode(value: Mode) -> void:
	var was_busy := is_busy()
	_mode = value
	if _mode != Mode.DIALOG and is_instance_valid(_sentence_end_audio):
		_sentence_end_audio.stop()
	_sync_dialog_audio()
	if is_instance_valid(_layer):
		_layer.visible = is_busy()
	if was_busy != is_busy():
		modal_changed.emit(is_busy())


func open_dialog() -> bool:
	if not _can_open():
		return false
	_message = "Dein Opfer ist nicht vergessen." if CollectionManager.get_jester_offering_state()["completed"] else DIALOGUE
	_set_mode(Mode.DIALOG)
	_refresh_modal_text()
	_typing_characters = 0.0
	_body_label.visible_characters = 0
	_sync_dialog_audio()
	return true


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
	return true


func _confirm_offering() -> void:
	if _mode != Mode.CANDIDATE or not interaction_enabled or get_tree().paused or not _candidate.get("ok", false):
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
	if _offering_tween != null and _offering_tween.is_valid():
		_offering_tween.kill()
	_offering_tween = null
	_clear_preview()
	_candidate = {}
	_reward_data = {}
	_selected_card_id = ""
	_message = ""
	_set_mode(Mode.NONE)


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
	if is_busy():
		_refresh_modal_text()


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
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, CLICK_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Picking can emit for overlapping boxes. Only the frontmost station
	# target may react, independently of the engine's callback order.
	return hit.get("collider") == area


func _input(event: InputEvent) -> void:
	if not is_busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel")):
		close_dialog()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	# Handle before GUI and physics dispatch. A click that closes a modal must
	# never open the grave or NPC behind it, or repeat an offering transaction.
	get_viewport().set_input_as_handled()
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	match _mode:
		Mode.DIALOG:
			if _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count():
				_body_label.visible_characters = -1
				_play_sentence_end()
			else:
				close_dialog()
		Mode.CANDIDATE:
			if _candidate.get("ok", false) and _panel.get_global_rect().has_point(event.position):
				_confirm_offering()
			else:
				close_dialog()
		Mode.OFFERING, Mode.RECEIVED:
			close_dialog()


func _sync_dialog_audio() -> void:
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(_mode == Mode.DIALOG and _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count() and not _sentence_end_audio.playing)


func _play_sentence_end() -> void:
	_laugh_audio.set_laughing(false)
	if not _sentence_end_audio.playing:
		_sentence_end_audio.play()


func _advance_dialog_text(delta: float) -> void:
	if _sentence_end_audio.playing:
		return
	var dialogue := _body_label.get_parsed_text()
	var previous_count := _body_label.visible_characters
	_typing_characters = minf(_typing_characters + delta * 32.0, dialogue.length())
	var next_count := int(_typing_characters)
	for index in range(previous_count, next_count):
		if dialogue[index] in [".", "!", "?", "…"] and (index + 1 == dialogue.length() or dialogue[index + 1].strip_edges().is_empty()):
			# Stop at the first sentence even when a slow frame reveals many characters.
			next_count = index + 1
			_typing_characters = float(next_count)
			_play_sentence_end()
			break
	_body_label.visible_characters = next_count
	_sync_dialog_audio()


func _process(delta: float) -> void:
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
	var origin := camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y * 0.31), 2.5)
	_preview_card.global_transform = Transform3D(camera.global_basis.orthonormalized().scaled(Vector3.ONE * 0.85), origin)


func _clear_preview() -> void:
	if is_instance_valid(_preview_card):
		_preview_card.hide()
		_preview_card.queue_free()
	_preview_card = null


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
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.81))
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
	_layer.hide()


func _refresh_modal_text() -> void:
	_sentence_end_audio.stop()
	_title_label.text = Localization.text("Der Narr")
	_body_label.text = Localization.text(_message)
	_body_label.visible_characters = -1
	if _mode == Mode.CANDIDATE:
		_title_label.text = Localization.format_text("Opfer für %s", [_card_name(_selected_card_id)])
		if _candidate.get("ok", false):
			_body_label.text += "\n\n" + Localization.text("Ins Textfeld klicken: opfern · Daneben klicken: abbrechen.")
	elif _mode == Mode.RECEIVED and not _reward_data.is_empty():
		_title_label.text = Localization.format_text("Erhalten: %s", [Localization.text(str(_reward_data.get("name", "")))])
		_body_label.text = Localization.text("Dein Opfer ist nicht vergessen.")
	_sync_dialog_audio()
	_layout_modal()


func _layout_modal() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := maxf(280.0, minf(760.0, viewport_size.x - 48.0))
	_panel.size.x = width
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = Vector2((viewport_size.x - width) * 0.5, viewport_size.y - _panel.size.y - 24.0)


func _exit_tree() -> void:
	if _offering_tween != null and _offering_tween.is_valid():
		_offering_tween.kill()
