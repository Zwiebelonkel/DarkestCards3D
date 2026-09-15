extends Control
class_name SatanVoicePortrait

enum VoiceActivity { SILENT, SPEAKING, LOUD }

const FRAME_SIZE := Vector2(64.0, 64.0)
const BASE_FRAME_COUNT := 25
const BASE_FPS := 15.0
const LOUD_FRAME_COUNT := 2
const LOUD_FPS := 20.0
const SHAKE_ATTACK_TAU_SECONDS := 0.045
const SHAKE_RELEASE_TAU_SECONDS := 0.14
const SHAKE_LEVEL_DEAD_ZONE := 0.06
const SHAKE_LEVEL_FULL := 0.95
const SHAKE_MIN_FREQUENCY_HZ := 3.0
const SHAKE_MAX_FREQUENCY_HZ := 9.0
const SHAKE_MAX_TRANSLATION_PIXELS := 5.0
const SHAKE_MAX_ROTATION_RADIANS := 0.039269908

@export var satan_idle_texture: Texture2D
@export var satan_speaking_texture: Texture2D
@export var satan_loud_texture: Texture2D

@onready var satan_shake_root: Control = %SatanShakeRoot
@onready var portrait: TextureRect = %SatanPortrait

var _voice_activity := VoiceActivity.SILENT
var _base_animation_seconds := 0.0
var _loud_animation_seconds := 0.0
var _current_frame := -1
var _current_texture: Texture2D = null
# AtlasTexture is mutable, so every portrait instance must own its own resource.
var _portrait_atlas := AtlasTexture.new()
var _voice_level := 0.0
var _smoothed_shake_level := 0.0
var _shake_phase := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_mouse_filter_ignore(self)
	_refresh_portrait_frame()
	reset_shake()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_base_animation_seconds = fmod(
		_base_animation_seconds + delta,
		float(BASE_FRAME_COUNT) / BASE_FPS
	)
	if _voice_activity == VoiceActivity.LOUD:
		_loud_animation_seconds = fmod(
			_loud_animation_seconds + delta,
			float(LOUD_FRAME_COUNT) / LOUD_FPS
		)
	_refresh_portrait_frame()
	_update_shake(delta)


func configure_textures(
	idle_texture: Texture2D,
	speaking_texture: Texture2D,
	loud_texture: Texture2D
) -> void:
	satan_idle_texture = idle_texture
	satan_speaking_texture = speaking_texture
	satan_loud_texture = loud_texture
	_current_texture = null
	_current_frame = -1
	_refresh_portrait_frame()


func set_activity(activity: int) -> void:
	activity = clampi(activity, VoiceActivity.SILENT, VoiceActivity.LOUD)
	if _voice_activity == activity:
		return
	var was_loud := _voice_activity == VoiceActivity.LOUD
	_voice_activity = activity
	if _voice_activity == VoiceActivity.SILENT:
		_voice_level = 0.0
	if _voice_activity == VoiceActivity.LOUD and not was_loud:
		_loud_animation_seconds = 0.0
	_current_frame = -1
	_refresh_portrait_frame()


func set_voice_activity(activity: int) -> void:
	set_activity(activity)


func get_voice_activity() -> int:
	return _voice_activity


func set_voice_level(level: float) -> void:
	_voice_level = clampf(level, 0.0, 1.0)


func get_voice_level() -> float:
	return _voice_level


func reset_shake() -> void:
	_voice_level = 0.0
	_smoothed_shake_level = 0.0
	_shake_phase = 0.0
	_apply_shake_transform(Vector2.ZERO, 0.0)


func _update_shake(delta: float) -> void:
	if satan_shake_root == null or not is_instance_valid(satan_shake_root):
		return

	var tau := (
		SHAKE_ATTACK_TAU_SECONDS
		if _voice_level > _smoothed_shake_level
		else SHAKE_RELEASE_TAU_SECONDS
	)
	var blend := 1.0 - exp(-maxf(delta, 0.0) / maxf(tau, 0.001))
	_smoothed_shake_level = clampf(
		lerpf(_smoothed_shake_level, _voice_level, blend),
		0.0,
		1.0
	)

	if _voice_level <= 0.0 and _smoothed_shake_level < 0.002:
		_smoothed_shake_level = 0.0
		_shake_phase = 0.0
		_apply_shake_transform(Vector2.ZERO, 0.0)
		return

	var normalized_strength := clampf(
		inverse_lerp(
			SHAKE_LEVEL_DEAD_ZONE,
			SHAKE_LEVEL_FULL,
			_smoothed_shake_level
		),
		0.0,
		1.0
	)
	var strength := (
		normalized_strength
		* normalized_strength
		* (3.0 - 2.0 * normalized_strength)
	)
	if strength <= 0.0:
		_apply_shake_transform(Vector2.ZERO, 0.0)
		return

	var frequency_hz := lerpf(
		SHAKE_MIN_FREQUENCY_HZ,
		SHAKE_MAX_FREQUENCY_HZ,
		strength
	)
	_shake_phase = fmod(_shake_phase + TAU * frequency_hz * delta, TAU)
	var horizontal_wave := (
		0.72 * sin(_shake_phase)
		+ 0.28 * sin(2.0 * _shake_phase + 1.1)
	)
	var vertical_wave := (
		0.70 * sin(_shake_phase + 2.05)
		+ 0.30 * sin(2.0 * _shake_phase + 0.35)
	)
	var rotation_wave := (
		0.78 * sin(_shake_phase + 0.55)
		+ 0.22 * sin(2.0 * _shake_phase + 2.2)
	)
	var max_axis_offset := SHAKE_MAX_TRANSLATION_PIXELS / sqrt(2.0)
	_apply_shake_transform(
		Vector2(horizontal_wave, vertical_wave) * max_axis_offset * strength,
		rotation_wave * SHAKE_MAX_ROTATION_RADIANS * strength
	)


func _apply_shake_transform(offset: Vector2, angle: float) -> void:
	if satan_shake_root == null or not is_instance_valid(satan_shake_root):
		return
	satan_shake_root.pivot_offset = satan_shake_root.size * 0.5
	satan_shake_root.position = offset
	satan_shake_root.rotation = angle


func _refresh_portrait_frame() -> void:
	if portrait == null:
		return
	var target_texture := satan_idle_texture
	var target_frame := floori(_base_animation_seconds * BASE_FPS) % BASE_FRAME_COUNT
	if _voice_activity == VoiceActivity.LOUD:
		target_texture = satan_loud_texture
		target_frame = floori(_loud_animation_seconds * LOUD_FPS) % LOUD_FRAME_COUNT
	elif _voice_activity == VoiceActivity.SPEAKING:
		target_texture = satan_speaking_texture

	if target_texture == null:
		return
	if _current_texture == target_texture and _current_frame == target_frame:
		return
	_current_texture = target_texture
	_current_frame = target_frame
	_portrait_atlas.atlas = target_texture
	_portrait_atlas.region = Rect2(
		Vector2(float(target_frame) * FRAME_SIZE.x, 0.0),
		FRAME_SIZE
	)
	portrait.texture = _portrait_atlas


func _set_mouse_filter_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_ignore(child)
