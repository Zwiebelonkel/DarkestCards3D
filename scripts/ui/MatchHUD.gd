extends Control
class_name MatchHUD

enum VoiceActivity { SILENT, SPEAKING, LOUD }

# Compatibility aliases keep MatchHUD's existing constants available while the
# implementation lives in the reusable portrait component.
const FRAME_SIZE := SatanVoicePortrait.FRAME_SIZE
const BASE_FRAME_COUNT := SatanVoicePortrait.BASE_FRAME_COUNT
const BASE_FPS := SatanVoicePortrait.BASE_FPS
const LOUD_FRAME_COUNT := SatanVoicePortrait.LOUD_FRAME_COUNT
const LOUD_FPS := SatanVoicePortrait.LOUD_FPS
const SHAKE_ATTACK_TAU_SECONDS := SatanVoicePortrait.SHAKE_ATTACK_TAU_SECONDS
const SHAKE_RELEASE_TAU_SECONDS := SatanVoicePortrait.SHAKE_RELEASE_TAU_SECONDS
const SHAKE_LEVEL_DEAD_ZONE := SatanVoicePortrait.SHAKE_LEVEL_DEAD_ZONE
const SHAKE_LEVEL_FULL := SatanVoicePortrait.SHAKE_LEVEL_FULL
const SHAKE_MIN_FREQUENCY_HZ := SatanVoicePortrait.SHAKE_MIN_FREQUENCY_HZ
const SHAKE_MAX_FREQUENCY_HZ := SatanVoicePortrait.SHAKE_MAX_FREQUENCY_HZ
const SHAKE_MAX_TRANSLATION_PIXELS := SatanVoicePortrait.SHAKE_MAX_TRANSLATION_PIXELS
const SHAKE_MAX_ROTATION_RADIANS := SatanVoicePortrait.SHAKE_MAX_ROTATION_RADIANS

@export var satan_idle_texture: Texture2D
@export var satan_speaking_texture: Texture2D
@export var satan_loud_texture: Texture2D
@export var idle_panel_style: StyleBox
@export var speaking_panel_style: StyleBox
@export var loud_panel_style: StyleBox

@onready var voice_panel: PanelContainer = %OpponentVoiceIndicator
@onready var satan_portrait: SatanVoicePortrait = %SatanVoicePortrait
# Preserve the former public node references for callers that inspect the HUD.
@onready var satan_shake_root: Control = satan_portrait.satan_shake_root
@onready var portrait: TextureRect = satan_portrait.portrait
@onready var voice_state_label: Label = %VoiceStateLabel

var _voice_activity := VoiceActivity.SILENT
var _chat_enabled := false
var _remote_voice_level := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if satan_portrait != null and is_instance_valid(satan_portrait):
		satan_portrait.configure_textures(
			satan_idle_texture,
			satan_speaking_texture,
			satan_loud_texture
		)
		satan_portrait.set_activity(_voice_activity)
		satan_portrait.set_voice_level(_remote_voice_level)
	_set_mouse_filter_ignore(self)
	_apply_voice_visuals()
	_reset_portrait_shake()


func show_for_match(should_show: bool) -> void:
	visible = should_show
	if not should_show:
		set_remote_voice_activity(VoiceActivity.SILENT)
		_reset_portrait_shake()


func set_voice_chat_enabled(enabled: bool) -> void:
	if _chat_enabled == enabled:
		if not enabled:
			_reset_portrait_shake()
		return
	_chat_enabled = enabled
	if not _chat_enabled:
		_voice_activity = VoiceActivity.SILENT
		_reset_portrait_shake()
	if satan_portrait != null and is_instance_valid(satan_portrait):
		satan_portrait.set_activity(_voice_activity)
	_apply_voice_visuals()


func set_remote_voice_activity(activity: int) -> void:
	activity = clampi(activity, VoiceActivity.SILENT, VoiceActivity.LOUD)
	if not _chat_enabled:
		activity = VoiceActivity.SILENT
	if _voice_activity == activity:
		return
	_voice_activity = activity
	if _voice_activity == VoiceActivity.SILENT:
		_remote_voice_level = 0.0
	if satan_portrait != null and is_instance_valid(satan_portrait):
		satan_portrait.set_activity(_voice_activity)
		satan_portrait.set_voice_level(_remote_voice_level)
	_apply_voice_visuals()


func get_voice_activity() -> int:
	return _voice_activity


func set_remote_voice_level(level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	if (
		not visible
		or not _chat_enabled
		or _voice_activity == VoiceActivity.SILENT
	):
		level = 0.0
	_remote_voice_level = level
	if satan_portrait != null and is_instance_valid(satan_portrait):
		satan_portrait.set_voice_level(_remote_voice_level)


func get_remote_voice_level() -> float:
	return _remote_voice_level


func _reset_portrait_shake() -> void:
	_remote_voice_level = 0.0
	if satan_portrait != null and is_instance_valid(satan_portrait):
		satan_portrait.reset_shake()


func _apply_voice_visuals() -> void:
	if voice_panel == null or voice_state_label == null or satan_portrait == null:
		return
	if not _chat_enabled:
		voice_state_label.text = "VOICE AUS"
		voice_state_label.add_theme_color_override("font_color", Color(0.46, 0.43, 0.45, 1.0))
		voice_panel.add_theme_stylebox_override("panel", idle_panel_style)
		satan_portrait.modulate = Color(0.48, 0.45, 0.47, 1.0)
		return

	satan_portrait.modulate = Color.WHITE
	match _voice_activity:
		VoiceActivity.LOUD:
			voice_state_label.text = "LAUT!"
			voice_state_label.add_theme_color_override("font_color", Color(1.0, 0.24, 0.2, 1.0))
			voice_panel.add_theme_stylebox_override("panel", loud_panel_style)
		VoiceActivity.SPEAKING:
			voice_state_label.text = "SPRICHT"
			voice_state_label.add_theme_color_override("font_color", Color(1.0, 0.52, 0.4, 1.0))
			voice_panel.add_theme_stylebox_override("panel", speaking_panel_style)
		_:
			voice_state_label.text = "STILL"
			voice_state_label.add_theme_color_override("font_color", Color(0.64, 0.59, 0.61, 1.0))
			voice_panel.add_theme_stylebox_override("panel", idle_panel_style)


func _set_mouse_filter_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_ignore(child)
