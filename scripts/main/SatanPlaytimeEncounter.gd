extends "res://scripts/rooms/AngelDialogue.gd"
## Owns the temporary global pause and camera. The inherited modal provides
## the game's existing typography, typewriter and panel transitions.
signal finished

@export var approach_duration := 2.8
@export var return_duration := 1.6

var active := false
var _stage := "approach"
var _table: GameTable
var _saved_pose: Transform3D
var _saved_fov := 75.0
var _saved_pause := false
var _saved_actor_mode: ProcessMode
var _saved_picking := false
var _canvas_visibility: Dictionary = {}
var _camera_tween: Tween
var _captured := false
var _persona_name := ""


func _ready() -> void:
	dialog_name = "Satan"
	voice_pitch_offset = GameTable.SATAN_STREAM_LAUGH_PITCH_OFFSET
	super._ready()


func start(table: GameTable) -> void:
	_table = table
	_persona_name = NetworkManager.get_local_persona_name()
	if _persona_name.is_empty():
		_persona_name = Localization.text("Abschaum")
	_saved_pose = camera.global_transform
	_saved_fov = camera.fov
	_saved_pause = get_tree().paused
	_saved_actor_mode = actor.process_mode
	_saved_picking = get_viewport().physics_object_picking
	_capture_canvases(get_parent())
	_captured = true
	active = true
	get_viewport().physics_object_picking = false
	get_tree().paused = true
	actor.process_mode = Node.PROCESS_MODE_ALWAYS
	_table._set_satan_hovered(false)
	_table._set_satan_laughing(true)
	actor.set("fps", GameTable.SATAN_STREAM_LAUGH_FPS)
	_laugh_audio.global_position = actor.global_position
	_sync_dialog_audio()
	# A fullscreen input shield is present during both camera moves as well.
	_layer.show()
	_panel.hide()
	var target := actor.global_position + Vector3.UP * actor.pixel_size * 6.0 * actor.global_basis.get_scale().y
	var eye := camera.global_position
	var direction := (target - eye).normalized()
	var focused_pose := Transform3D(Basis.looking_at(direction, Vector3.UP), eye + direction * minf(0.45, eye.distance_to(target) * 0.08))
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(camera, "global_transform", focused_pose, approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "fov", _saved_fov * 0.88, approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.chain().tween_callback(_show_message)


func _capture_canvases(node: Node) -> void:
	if node == self or node.get_viewport() != camera.get_viewport():
		return
	# Cinematic input locks must not remove the game's camera effects.
	if node is CanvasLayer and not node.is_in_group(&"screen_overlay_effects"):
		_canvas_visibility[node] = node.visible
		node.hide()
	for child in node.get_children():
		_capture_canvases(child)


func _show_message() -> void:
	_stage = "dialog"
	_panel.show()
	interaction_enabled = true
	open_dialog()


func _get_dialog_title() -> String:
	return "Satan"


func _get_sentences() -> Array[String]:
	return ["%s, Danke für dein Geld, du wirst es nie wiedersehen, fick dich." % _persona_name]


func _uses_laughing_text() -> bool:
	return true


func _context_is_valid() -> bool:
	return active and is_instance_valid(camera) and is_instance_valid(actor) and camera.is_current()


func _update_click_area() -> void:
	pass


func _update_pointer_hover() -> void:
	pass


func _sync_dialog_audio() -> void:
	if is_instance_valid(_laugh_audio):
		_laugh_audio.set_laughing(active)


func _finish_sentence() -> void:
	_text_finished = true
	_sync_dialog_audio()


func _input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()
	if _stage != "dialog":
		return
	var advance: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	advance = advance or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE])
	advance = advance or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
	if advance:
		continue_dialog()


func close_dialog() -> void:
	if not active or _stage != "dialog":
		return
	_stage = "return"
	_open = false
	_panel.hide()
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(camera, "global_transform", _saved_pose, return_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "fov", _saved_fov, return_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.chain().tween_callback(func():
		PlaytimeManager.complete_encounter()
		_end()
	)


func cancel() -> void:
	if active:
		_end()


func _end() -> void:
	active = false
	_restore()
	finished.emit()
	queue_free()


func _restore() -> void:
	if _camera_tween != null:
		_camera_tween.kill()
	_sync_dialog_audio()
	if not _captured:
		return
	_captured = false
	if is_instance_valid(camera) and camera.is_inside_tree():
		camera.global_transform = _saved_pose
		camera.fov = _saved_fov
	if is_instance_valid(_table):
		_table._set_satan_laughing(false)
	if is_instance_valid(actor):
		actor.process_mode = _saved_actor_mode
	for canvas: CanvasLayer in _canvas_visibility:
		if is_instance_valid(canvas):
			canvas.visible = _canvas_visibility[canvas]
	get_viewport().physics_object_picking = _saved_picking
	get_tree().paused = _saved_pause
	_layer.hide()


func _exit_tree() -> void:
	# Closing the game or changing scenes mid-line keeps the encounter pending.
	active = false
	_restore()
	super._exit_tree()


func _notification(_what: int) -> void:
	# Focus changes must not dismiss or complete the player's unread line.
	pass
