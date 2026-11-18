extends Node3D

signal started
signal halfway_clicked
signal recovery_started
signal cancelled
signal finished

const SCARE_SOUND := preload("res://assets/sounds/SFX/jumpscare.mp3")
const GRAB_SOUND := preload("res://assets/sounds/SFX/grab.mp3")
const LAUGH_SHEET := preload("res://assets/characters/satan/satanLaught.png")
const SCARE_LAYER := 1 << 19
const ACTOR_PROPERTIES := [
	"texture", "hframes", "vframes", "frame", "TOTAL_FRAMES", "fps", "loop",
	"_frame_timer", "layers", "shaded", "no_depth_test", "render_priority", "modulate",
]

@export var clicks_required := 4
@export var click_window_seconds := 1.5
@export var duration := 1.05
@export var cooldown_seconds := 8.0
@export var strobe_hz := 10.0
@export var click_push_distance := 0.12
@export var click_push_seconds := 0.035
@export var click_return_seconds := 0.1
@export var wakeup_floor_hold := 0.8
@export var get_up_duration := 3.2
@export var floor_eye_height := 0.25

var camera: Camera3D
var actor: Sprite3D
var context_available: Callable
var active := false
var _click_times: Array[int] = []
var _start_queued := false
var _cooldown_until := 0
var _elapsed := 0.0
var _camera_transform := Transform3D.IDENTITY
var _camera_global_transform := Transform3D.IDENTITY
var _camera_mask := 0
var _camera_environment: Environment
var _actor_transform := Transform3D.IDENTITY
var _actor_state := {}
var _actor_processing := false
var _canvas_visibility := {}
var _light: OmniLight3D
var _sound: AudioStreamPlayer
var _grab_sound: AudioStreamPlayer
var _random := RandomNumberGenerator.new()
var _click_recoil: Tween
var _click_recoil_active := false
var _click_rest_position := Vector3.ZERO
var _floor_y := 0.0
var _recovering := false
var _recovery_elapsed := 0.0
var _floor_camera_transform := Transform3D.IDENTITY
var _scare_presentation_active := false


func configure(scene_camera: Camera3D, satan: Sprite3D, area: Area3D, available: Callable, floor_y: float) -> void:
	camera = scene_camera
	actor = satan
	context_available = available
	_floor_y = floor_y
	area.input_event.connect(_on_satan_input)
	_random.randomize()
	_sound = AudioStreamPlayer.new()
	_sound.name = "JumpscareSound"
	_sound.stream = SCARE_SOUND
	_sound.bus = &"SFX"
	add_child(_sound)
	_grab_sound = AudioStreamPlayer.new()
	_grab_sound.name = "SatanGrabSound"
	_grab_sound.stream = GRAB_SOUND
	_grab_sound.bus = &"SFX"
	_grab_sound.max_polyphony = 4
	add_child(_grab_sound)


func _on_satan_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if active or _start_queued:
		return
	if not context_available.is_valid() or not context_available.call():
		_click_times.clear()
		return
	_grab_sound.play()
	_play_click_recoil()
	if Time.get_ticks_msec() < _cooldown_until:
		return
	var now := Time.get_ticks_msec()
	while not _click_times.is_empty() and now - _click_times[0] > int(click_window_seconds * 1000):
		_click_times.pop_front()
	_click_times.append(now)
	if _click_times.size() == maxi(1, ceili(float(clicks_required) * 0.5)):
		halfway_clicked.emit()
	if _click_times.size() >= clicks_required:
		_start_queued = true
		_start.call_deferred()


func _play_click_recoil() -> void:
	if not _click_recoil_active:
		_click_rest_position = actor.position
	if _click_recoil != null and _click_recoil.is_valid():
		_click_recoil.kill()
	_click_recoil_active = true
	var away := (actor.global_position - camera.global_position).normalized()
	var offset := (actor.get_parent() as Node3D).global_basis.inverse() * away * click_push_distance
	_click_recoil = create_tween()
	_click_recoil.tween_property(actor, "position", _click_rest_position + offset, click_push_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_click_recoil.tween_property(actor, "position", _click_rest_position, click_return_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_click_recoil.finished.connect(func() -> void:
		_click_recoil_active = false
		_click_recoil = null
	)


func _stop_click_recoil() -> void:
	if _click_recoil != null and _click_recoil.is_valid():
		_click_recoil.kill()
	_click_recoil = null
	if _click_recoil_active and is_instance_valid(actor):
		actor.position = _click_rest_position
	_click_recoil_active = false


func _start() -> void:
	_start_queued = false
	_click_times.clear()
	if active or not context_available.is_valid() or not context_available.call():
		return
	_stop_click_recoil()
	active = true
	# Main first suspends input and other camera owners. Record that stable pose.
	started.emit()
	_camera_transform = camera.transform
	_camera_global_transform = camera.global_transform
	_camera_mask = camera.cull_mask
	_camera_environment = camera.environment
	_actor_transform = actor.transform
	_actor_processing = actor.is_processing()
	for property: String in ACTOR_PROPERTIES:
		_actor_state[property] = actor.get(property)
	_scare_presentation_active = true
	_recovering = false
	_recovery_elapsed = 0.0
	_capture_canvases(get_parent())
	var darkness := Environment.new()
	darkness.background_mode = Environment.BG_COLOR
	darkness.background_color = Color.BLACK
	darkness.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	camera.environment = darkness
	camera.cull_mask = SCARE_LAYER
	actor.layers = SCARE_LAYER
	actor.shaded = true
	actor.no_depth_test = true
	actor.render_priority = 127
	actor.modulate = Color.WHITE
	actor.play_sheet(LAUGH_SHEET, 2, 20.0)
	_light = OmniLight3D.new()
	_light.name = "JumpscareStrobe"
	_light.layers = SCARE_LAYER
	_light.light_cull_mask = SCARE_LAYER
	_light.light_energy = 5.0
	_light.omni_range = 4.0
	add_child(_light)
	_light.global_transform = _camera_global_transform
	_elapsed = 0.0
	_update_presentation()
	_sound.play()


func _process(delta: float) -> void:
	if not active:
		if context_available.is_valid() and not context_available.call():
			_click_times.clear()
			_stop_click_recoil()
		return
	if not is_instance_valid(camera) or not is_instance_valid(actor):
		cancel()
		return
	if _recovering:
		_update_recovery(delta)
		return
	_elapsed += delta
	if _elapsed >= duration:
		_start_recovery()
		return
	_update_presentation()


func _start_recovery() -> void:
	# Return Satan and the room immediately, but retain Main's input/camera lock
	# and hide the HUD until the player has finished getting up.
	_restore_scare_presentation()
	_recovering = true
	_recovery_elapsed = 0.0
	var forward := -_camera_global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	_floor_camera_transform = Transform3D(
		Basis.looking_at(forward.normalized(), Vector3.UP)
			* Basis(Vector3.RIGHT, deg_to_rad(86.0))
			* Basis(Vector3.BACK, deg_to_rad(-6.0)),
		Vector3(_camera_global_transform.origin.x, _floor_y + floor_eye_height, _camera_global_transform.origin.z))
	camera.global_transform = _floor_camera_transform
	recovery_started.emit()


func _update_recovery(delta: float) -> void:
	_recovery_elapsed += delta
	var progress := clampf((_recovery_elapsed - wakeup_floor_hold) / maxf(get_up_duration, 0.01), 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	camera.global_transform = _floor_camera_transform.interpolate_with(_camera_global_transform, eased)
	if progress >= 1.0:
		_finish(false)


func _update_presentation() -> void:
	var strength := 1.0 - 0.35 * clampf(_elapsed / maxf(duration, 0.01), 0.0, 1.0)
	var camera_jitter := Vector3(_noise(), _noise(), _noise()) * 0.025 * strength
	var camera_rotation := Vector3(_noise(), _noise(), _noise()) * 0.035 * strength
	camera.transform = _camera_transform * Transform3D(Basis.from_euler(camera_rotation), camera_jitter)
	var depth := 0.65
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var screen_height := camera.project_position(Vector2(viewport_size.x * 0.5, 0), depth).distance_to(
		camera.project_position(Vector2(viewport_size.x * 0.5, viewport_size.y), depth))
	var scale_factor := screen_height * 2.3 / (64.0 * actor.pixel_size)
	var jitter := Vector3(_noise() * 0.045, _noise() * 0.035, _noise() * 0.012) * strength
	actor.global_transform = _camera_global_transform * Transform3D(
		Basis.from_euler(Vector3(0, 0, _noise() * 0.075)).scaled(Vector3.ONE * scale_factor),
		Vector3(0, 0, -depth) + jitter)
	_light.visible = int(_elapsed * strobe_hz * 2.0) % 2 == 0


func _noise() -> float:
	# Cosmetic shakes never consume card rolls or other gameplay randomness.
	return _random.randf_range(-1.0, 1.0)


func _capture_canvases(node: Node) -> void:
	if node.get_viewport() != camera.get_viewport():
		return
	# Keep the lens and screen shaders rendering over the entire sequence.
	if node is CanvasLayer and not node.is_in_group(&"screen_overlay_effects"):
		_canvas_visibility[node] = node.visible
		node.hide()
	for child in node.get_children():
		_capture_canvases(child)


func cancel(stop_sound: bool = true) -> void:
	if active:
		cancelled.emit()
	_finish(stop_sound)


func _finish(stop_sound: bool) -> void:
	_click_times.clear()
	_start_queued = false
	_stop_click_recoil()
	if not active:
		return
	_restore_presentation()
	if stop_sound:
		_sound.stop()
	_cooldown_until = Time.get_ticks_msec() + int(cooldown_seconds * 1000)
	finished.emit()


func _restore_presentation() -> void:
	if not active:
		return
	_restore_scare_presentation()
	active = false
	_recovering = false
	if is_instance_valid(camera):
		camera.transform = _camera_transform
	for canvas: CanvasLayer in _canvas_visibility:
		if is_instance_valid(canvas):
			canvas.visible = _canvas_visibility[canvas]
	_canvas_visibility.clear()


func _restore_scare_presentation() -> void:
	if not _scare_presentation_active:
		return
	_scare_presentation_active = false
	if is_instance_valid(camera):
		camera.cull_mask = _camera_mask
		camera.environment = _camera_environment
	if is_instance_valid(actor):
		for property: String in ACTOR_PROPERTIES:
			actor.set(property, _actor_state[property])
		actor.transform = _actor_transform
		actor.set_process(_actor_processing)
	if is_instance_valid(_light):
		_light.hide()
		_light.queue_free()
	_light = null


func _exit_tree() -> void:
	_stop_click_recoil()
	_restore_presentation()
