extends Node3D
## First-visit presentation. Main owns the gameplay lock; this node owns only
## the camera, darkness, dialog and voice, restoring all of them on exit.
signal finished

const VOICE := preload("res://scripts/SatanLaughAudio.gd")
const DIALOGUE_STYLE := preload("res://scripts/ui/DialogueStyle.gd")
const LIGHTS_ON_SOUND := preload("res://assets/sounds/SFX/scare.mp3")
const VOICE_PITCH_OFFSET := -16.0
const EYES_LAYER := 1 << 19
const SENTENCES: Array[String] = [
	"Hallo, %s.",
	"Ich weiß auch nicht, wie du hier gelandet bist. Aber nun ist es so.",
	"Wieso kaufst du dir nicht ein Paket links von dir? Oder mehrere?",
	"Und baust dir dein Deck in der Collection.",
	"Wenn du das gemacht hast, komm wieder zu mir. Ich zeig dir, wie das läuft.",
]

@export_range(0.1, 30.0, 0.1) var camera_duration := 12.0
@export_range(1.0, 200.0, 1.0) var characters_per_second := 32.0
@export_range(0.0, 5.0, 0.1) var sentence_hold := 1.8
@export_range(0.0, 3.0, 0.1) var opening_hold := 0.65

var camera: Camera3D
var actor: Sprite3D
var active := false
var _camera_pose: Transform3D
var _camera_mask: int
var _camera_environment: Environment
var _actor_layers: int
var _light_visibility: Dictionary = {}
var _canvas_visibility: Dictionary = {}
var _camera_tween: Tween
var _camera_finished := false
var _dialog_finished := false
var _voice: AudioStreamPlayer3D
var _layer: CanvasLayer
var _panel: PanelContainer
var _body: RichTextLabel
var _hint: Label
var _sentence_index := -1
var _characters := 0.0
var _hold_remaining := 0.0
var _player_name := ""
var _presentation_captured := false


func start(scene: Node3D, scene_camera: Camera3D, satan: Sprite3D) -> void:
	if active:
		return
	camera = scene_camera
	actor = satan
	active = true
	_player_name = NetworkManager.get_local_persona_name()
	_camera_pose = camera.global_transform
	_camera_mask = camera.cull_mask
	_camera_environment = camera.environment
	_actor_layers = actor.layers
	_capture_darkness(scene)
	_presentation_captured = true
	# Emissive signs, screens and unshaded props must also disappear in the
	# blackout. Render only Satan's existing animated eyes until lights return.
	actor.layers = EYES_LAYER
	camera.cull_mask = EYES_LAYER
	# Preserve the scene's glow so the emissive eyes also bloom in the intro.
	var source_environment := _camera_environment
	if source_environment == null:
		source_environment = camera.get_world_3d().environment
	var darkness := source_environment.duplicate() as Environment if source_environment != null else Environment.new()
	darkness.background_mode = Environment.BG_COLOR
	darkness.background_color = Color.BLACK
	darkness.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	darkness.sky = null
	camera.environment = darkness
	var eyes := actor.global_position + Vector3.UP * actor.pixel_size * 6.0 * actor.global_basis.get_scale().y
	camera.global_position = eyes + Vector3(0, 0, 0.55)
	camera.look_at(eyes, Vector3.UP)
	global_position = actor.global_position
	_create_dialog()
	_voice = VOICE.new()
	_voice.pitch_offset_semitones = VOICE_PITCH_OFFSET
	add_child(_voice)
	_hold_remaining = opening_hold
	_camera_tween = create_tween()
	_camera_tween.tween_interval(opening_hold)
	_camera_tween.tween_property(camera, "global_transform", _camera_pose, camera_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_callback(func():
		_camera_finished = true
		_try_finish()
	)


func _capture_darkness(node: Node) -> void:
	if node == self or node.get_viewport() != camera.get_viewport():
		return
	if node is Light3D:
		_light_visibility[node] = node.visible
		node.hide()
	# Hide interface layers without removing the persistent lens/screen passes.
	if node is CanvasLayer and not node.is_in_group(&"screen_overlay_effects"):
		_canvas_visibility[node] = node.visible
		node.hide()
	for child in node.get_children():
		_capture_darkness(child)


func _create_dialog() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.04, 0.97)
	style.border_color = Color(0.48, 0.56, 0.43)
	style.set_border_width_all(2)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "Satan"
	title.add_theme_font_override("font", Localization.FONT)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", DIALOGUE_STYLE.SATAN)
	column.add_child(title)
	_body = RichTextLabel.new()
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size.y = 56
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_override("normal_font", Localization.FONT)
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_color_override("default_color", Color(0.82, 0.86, 0.79))
	column.add_child(_body)
	_hint = Label.new()
	_hint.text = Localization.text("Klick / Leertaste: weiter")
	_hint.add_theme_font_override("font", Localization.FONT)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.modulate = Color(0.62, 0.66, 0.59)
	column.add_child(_hint)
	_layer.hide()


func _layout_dialog() -> void:
	var size := get_viewport().get_visible_rect().size
	_panel.size.x = minf(760.0, maxf(1.0, size.x - 48.0))
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, maxf(16.0, size.y - _panel.size.y - 24.0))


func _show_sentence() -> void:
	_sentence_index += 1
	if _sentence_index >= SENTENCES.size():
		_dialog_finished = true
		_hint.hide()
		_try_finish()
		return
	_body.text = Localization.format_text(SENTENCES[0], [_player_name if not _player_name.is_empty() else Localization.text("Abschaum")]) if _sentence_index == 0 else Localization.text(SENTENCES[_sentence_index])
	_body.visible_characters = 0
	_characters = 0.0
	_hold_remaining = sentence_hold
	_layer.show()
	_layout_dialog()
	_voice.set_laughing(true)


func _finish_sentence() -> void:
	_body.visible_characters = -1
	_voice.set_laughing(false)
	_hold_remaining = sentence_hold


func _process(delta: float) -> void:
	if not active:
		return
	_layout_dialog()
	if _dialog_finished:
		return
	if _sentence_index < 0:
		_hold_remaining -= delta
		if _hold_remaining <= 0.0:
			_show_sentence()
	elif _body.visible_characters >= 0:
		_characters += delta * characters_per_second
		_body.visible_characters = int(_characters)
		if _characters >= _body.get_total_character_count():
			_finish_sentence()
	else:
		_hold_remaining -= delta
		if _hold_remaining <= 0.0:
			_show_sentence()


func _input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()
	if _sentence_index < 0 or _dialog_finished:
		return
	var advance: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	advance = advance or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER])
	advance = advance or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
	if advance:
		if _body.visible_characters >= 0:
			_finish_sentence()
		else:
			_show_sentence()


func _try_finish() -> void:
	if not active or not _dialog_finished or not _camera_finished:
		return
	active = false
	GameCurrency.complete_greeting()
	_restore_presentation()
	# Keep the reveal sound alive after this temporary greeting node is freed.
	var scare := AudioStreamPlayer.new()
	scare.name = "GreetingScare"
	scare.stream = LIGHTS_ON_SOUND
	scare.bus = &"SFX"
	get_parent().add_child(scare)
	scare.finished.connect(scare.queue_free)
	scare.play()
	finished.emit()
	queue_free()


func cancel() -> void:
	if not active:
		return
	active = false
	_restore_presentation()
	finished.emit()
	queue_free()


func _restore_presentation() -> void:
	if _camera_tween != null:
		_camera_tween.kill()
	if is_instance_valid(_voice):
		_voice.set_laughing(false)
	if is_instance_valid(_layer):
		_layer.hide()
	if not _presentation_captured:
		return
	_presentation_captured = false
	if is_instance_valid(camera):
		camera.cull_mask = _camera_mask
		camera.environment = _camera_environment
		if camera.is_inside_tree():
			camera.global_transform = _camera_pose
	if is_instance_valid(actor):
		actor.layers = _actor_layers
	for light: Light3D in _light_visibility:
		if is_instance_valid(light):
			light.visible = _light_visibility[light]
	for canvas: CanvasLayer in _canvas_visibility:
		if is_instance_valid(canvas):
			canvas.visible = _canvas_visibility[canvas]


func _exit_tree() -> void:
	# An interrupted intro must replay on the next visit, never mark it seen.
	_restore_presentation()
