extends Node3D
class_name AngelDialogue

signal modal_changed(opened: bool)

const CONTENT := preload("res://scripts/rooms/AngelDialogueContent.gd")
const LAUGH_AUDIO_SCRIPT := preload("res://scripts/SatanLaughAudio.gd")
const DIALOGUE_STYLE := preload("res://scripts/ui/DialogueStyle.gd")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const CLICK_LAYER := 1 << 16
const TYPEWRITER_CPS := 32.0
const PANEL_SWIPE_DURATION := 0.24
const PANEL_EDGE_MARGIN := 24.0

var camera: Camera3D
var actor: Sprite3D
var context_available: Callable
var interaction_enabled := false
var dialog_name := "Angel"
var voice_pitch_offset := 0.0
var npc_area: Area3D
var _open := false
var _message := ""
var _typing_characters := 0.0
var _last_sentence_index := -1
var _text_finished := false
var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _modal_root: Control
var _panel: PanelContainer
var _title_label: Label
var _body_label: RichTextLabel
var _laugh_audio: AudioStreamPlayer3D
var _panel_swipe_tween: Tween
var _panel_slide_offset_y := 0.0
var _closing := false


func _ready() -> void:
	# This controller must stop the voice and dismiss its modal on pause even
	# while the collection and the existing animated sprite are paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_create_click_area()
	_create_audio()
	_create_modal()
	Localization.locale_changed.connect(_on_locale_changed)
	_update_click_area()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not enabled:
		close_dialog()
	_update_click_area()


func is_dialog_open() -> bool:
	return _open


func is_busy() -> bool:
	return _open


func _context_is_valid() -> bool:
	return (
		interaction_enabled and is_inside_tree() and not get_tree().paused
		and is_visible_in_tree() and is_instance_valid(actor) and actor.is_visible_in_tree()
		and is_instance_valid(camera) and camera.is_current()
		and (not context_available.is_valid() or bool(context_available.call()))
	)


func _can_open() -> bool:
	return not _open and not _closing and _context_is_valid()


func open_dialog() -> bool:
	var sentences := _get_sentences()
	if not _can_open() or sentences.is_empty():
		return false
	var count := sentences.size()
	var next_index := _rng.randi_range(0, count - (2 if _last_sentence_index >= 0 and count > 1 else 1))
	if count > 1 and _last_sentence_index >= 0 and next_index >= _last_sentence_index:
		next_index += 1
	_last_sentence_index = next_index
	_message = sentences[next_index]
	_open = true
	_closing = false
	_text_finished = false
	_typing_characters = 0.0
	_refresh_body_text()
	_body_label.visible_characters = 0
	_refresh_labels()
	_layer.show()
	_layout_modal()
	_start_panel_swipe_in()
	_update_click_area()
	_sync_dialog_audio()
	modal_changed.emit(true)
	return true


func _get_sentences() -> Array[String]:
	return CONTENT.SENTENCES


func _get_dialog_title() -> String:
	return "Der Engel"


func _uses_laughing_text() -> bool:
	return false


func _refresh_body_text() -> void:
	DIALOGUE_STYLE.set_body(_body_label, Localization.text(_message), _uses_laughing_text())


func close_dialog() -> void:
	if not _open or _closing:
		return
	_closing = true
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(false)
	_update_click_area()
	_start_panel_swipe_out()


func continue_dialog() -> void:
	if not _open or _closing:
		return
	if _is_typing():
		_typing_characters = float(_body_label.get_total_character_count())
		_body_label.visible_characters = -1
		_finish_sentence()
	else:
		close_dialog()


func _is_typing() -> bool:
	return _open and not _closing and not _text_finished and _body_label.visible_characters >= 0 and _body_label.visible_characters < _body_label.get_total_character_count()


func _advance_dialog_text(delta: float) -> void:
	if not _is_typing():
		return
	var total := _body_label.get_total_character_count()
	_typing_characters = minf(_typing_characters + maxf(delta, 0.0) * TYPEWRITER_CPS, float(total))
	_body_label.visible_characters = int(_typing_characters)
	if not _is_typing():
		_body_label.visible_characters = -1
		_finish_sentence()
	_sync_dialog_audio()


func _finish_sentence() -> void:
	_laugh_audio.set_laughing(false)
	if _text_finished or not _open:
		return
	_text_finished = true


func _sync_dialog_audio() -> void:
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(_open and _context_is_valid() and _is_typing())


func _process(delta: float) -> void:
	_update_click_area()
	_update_pointer_hover()
	if not _open:
		return
	if _closing:
		_layout_modal()
		return
	if not _context_is_valid():
		close_dialog()
		return
	_layout_modal()
	_advance_dialog_text(delta)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey:
		if event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel")):
			close_dialog()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# The entire dialog responds identically, including text and empty space.
		# Consume before GUI or physics picking can reuse a revealing/closing click.
		get_viewport().set_input_as_handled()
		if not _closing and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			continue_dialog()


func _on_npc_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pointer_hits_area(event.position) and open_dialog():
			get_viewport().set_input_as_handled()


func _pointer_hits_area(pointer: Vector2) -> bool:
	if not _can_open() or not is_instance_valid(npc_area):
		return false
	if not npc_area.input_ray_pickable or not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# The angel stands behind the cards. Only the nearest world target may
	# receive the click, including foreground collection cards and buttons.
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == npc_area


func _update_pointer_hover() -> void:
	if is_instance_valid(actor) and actor.has_method("set_hovered"):
		actor.call("set_hovered", _pointer_hits_area(get_viewport().get_mouse_position()))


func _create_click_area() -> void:
	npc_area = Area3D.new()
	npc_area.name = dialog_name + "ClickArea"
	npc_area.collision_layer = 0
	npc_area.collision_mask = 0
	npc_area.monitoring = false
	npc_area.monitorable = false
	npc_area.input_ray_pickable = false
	var shape := BoxShape3D.new()
	if is_instance_valid(actor) and actor.texture != null:
		shape.size = Vector3(actor.texture.get_width() * actor.pixel_size / maxi(actor.hframes, 1), actor.texture.get_height() * actor.pixel_size / maxi(actor.vframes, 1), 0.25)
	else:
		shape.size = Vector3(3.5, 3.5, 0.25)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	npc_area.add_child(collision)
	add_child(npc_area)
	npc_area.input_event.connect(_on_npc_input)


func _update_click_area() -> void:
	if not is_instance_valid(npc_area):
		return
	var enabled := not _open and _context_is_valid()
	npc_area.collision_layer = CLICK_LAYER if enabled else 0
	npc_area.input_ray_pickable = enabled
	npc_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled and is_instance_valid(actor) and actor.has_method("set_hovered"):
		actor.call("set_hovered", false)
	if is_instance_valid(actor) and is_instance_valid(camera) and is_inside_tree():
		# Match the sprite's billboard solely with its invisible hit box. The
		# authored angel position, scale, animation, and camera stay untouched.
		npc_area.global_transform = Transform3D(camera.global_basis.orthonormalized().scaled(actor.global_basis.get_scale()), actor.global_position)
		if is_instance_valid(_laugh_audio):
			_laugh_audio.global_position = actor.global_position


func _create_audio() -> void:
	_laugh_audio = LAUGH_AUDIO_SCRIPT.new()
	_laugh_audio.name = dialog_name + "Voice"
	_laugh_audio.pitch_offset_semitones = voice_pitch_offset
	add_child(_laugh_audio)


func _create_modal() -> void:
	_layer = CanvasLayer.new()
	_layer.name = dialog_name + "Dialog"
	_layer.layer = 50
	add_child(_layer)
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_modal_root)
	_panel = PanelContainer.new()
	_panel.name = "DialogPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.04, 0.97)
	style.border_color = Color(0.65, 0.65, 0.45)
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
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_override("font", FONT)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", DIALOGUE_STYLE.speaker_color(dialog_name))
	column.add_child(_title_label)
	_body_label = RichTextLabel.new()
	# Translate explicitly below so Godot cannot change the character count
	# before the locale handler preserves the current typewriter progress.
	_body_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body_label.bbcode_enabled = false
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size.y = 52
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.add_theme_font_override("normal_font", FONT)
	_body_label.add_theme_font_size_override("normal_font_size", 21)
	_body_label.add_theme_color_override("default_color", Color(0.86, 0.88, 0.81))
	column.add_child(_body_label)
	_refresh_labels()
	_layer.hide()


func _refresh_labels() -> void:
	_title_label.text = Localization.text(_get_dialog_title())
	_title_label.add_theme_color_override("font_color", DIALOGUE_STYLE.speaker_color(dialog_name))


func _layout_modal() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(760.0, maxf(1.0, viewport_size.x - PANEL_EDGE_MARGIN * 2.0))
	_panel.size.x = width
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = _panel_rest_position(viewport_size) + Vector2(0, _panel_slide_offset_y)


func _panel_rest_position(viewport_size: Vector2) -> Vector2:
	return Vector2(
		(viewport_size.x - _panel.size.x) * 0.5,
		maxf(16.0, viewport_size.y - _panel.size.y - PANEL_EDGE_MARGIN)
	)


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
	_panel_swipe_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_panel_swipe_tween.tween_method(_set_panel_slide_offset, _panel_slide_offset_y, 0.0, PANEL_SWIPE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_swipe_tween.tween_callback(_finish_panel_swipe_in)


func _finish_panel_swipe_in() -> void:
	if not _closing:
		_panel_swipe_tween = null


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
	if not _closing:
		return
	_panel_swipe_tween = null
	_panel_slide_offset_y = 0.0
	_closing = false
	_open = false
	if is_instance_valid(_layer):
		_layer.hide()
	_update_click_area()
	modal_changed.emit(false)


func _on_locale_changed() -> void:
	if not _open or _closing:
		_refresh_labels()
		return
	var was_typing := _is_typing()
	var previous_total := maxi(_body_label.get_total_character_count(), 1)
	var fraction := clampf(_typing_characters / float(previous_total), 0.0, 1.0)
	_refresh_body_text()
	_typing_characters = fraction * _body_label.get_total_character_count()
	_body_label.visible_characters = int(_typing_characters) if was_typing else -1
	_refresh_labels()
	_layout_modal()
	_sync_dialog_audio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		close_dialog()


func _exit_tree() -> void:
	# The parent scene may already be tearing down its other UI controllers.
	# Stop silently instead of publishing a navigation update during removal.
	_open = false
	_closing = false
	_cancel_panel_swipe()
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(false)
	if is_instance_valid(_layer):
		_layer.hide()
