extends AudioStreamPlayer
## Both arrangements share one playback clock; only their mix changes.

const CURSED_THEME := preload("res://assets/sounds/theme4cursed.mp3")
const TRANSITION_DURATION := 0.3
const SILENT_DB := -80.0
const COCAINE_SPEED := 1.35
const MDMA_SPEED := 0.85

var _layers: AudioStreamSynchronized
var _mix := 0.0
var _cursed := false
var _transition: Tween
var _cocaine_pitch_active := false
var _cocaine_base_pitch := 1.0
var _mdma_pitch_active := false
var _mdma_base_pitch := 1.0


func _ready() -> void:
	var normal := stream.duplicate() as AudioStreamMP3
	var cursed := CURSED_THEME.duplicate() as AudioStreamMP3
	# The MP3 files differ by ~52 ms. Give both the same loop endpoint so
	# encoder padding cannot accumulate into drift during long hub sessions.
	# Leave audio for Godot's short loop-boundary fade before the MP3 EOF.
	var loop_duration := minf(normal.get_length(), cursed.get_length()) - 0.02
	for layer in [normal, cursed]:
		layer.loop = true
		layer.loop_offset = 0.0
		layer.beat_count = 1
		layer.bpm = 60.0 / loop_duration
	_layers = AudioStreamSynchronized.new()
	_layers.stream_count = 2
	_layers.set_sync_stream(0, normal)
	_layers.set_sync_stream(1, cursed)
	stream = _layers
	_apply_mix(0.0)


func set_weed_effect_active(enabled: bool) -> void:
	if _cursed == enabled:
		return
	_cursed = enabled
	if _transition != null:
		_transition.kill()
	_transition = create_tween()
	_transition.tween_method(_apply_mix, _mix, 1.0 if enabled else 0.0, TRANSITION_DURATION)


func _apply_mix(weight: float) -> void:
	_mix = clampf(weight, 0.0, 1.0)
	# Fade amplitudes so the transition does not dip to silence midway.
	_layers.set_sync_stream_volume(0, maxf(linear_to_db(1.0 - _mix), SILENT_DB))
	_layers.set_sync_stream_volume(1, maxf(linear_to_db(_mix), SILENT_DB))


func set_cocaine_effect_strength(strength: float) -> void:
	var weight := clampf(strength, 0.0, 1.0)
	if weight > 0.0 and not _cocaine_pitch_active:
		_cocaine_base_pitch = pitch_scale
		_cocaine_pitch_active = true
	if _cocaine_pitch_active:
		# Playback speed raises tempo and pitch together without restarting either
		# synchronized arrangement. Restore the authored pitch exactly at zero.
		pitch_scale = _cocaine_base_pitch * lerpf(1.0, COCAINE_SPEED, weight)
		if weight <= 0.0:
			_cocaine_pitch_active = false


func set_mdma_effect_strength(strength: float) -> void:
	var weight := clampf(strength, 0.0, 1.0)
	if weight > 0.0 and not _mdma_pitch_active:
		_mdma_base_pitch = pitch_scale
		_mdma_pitch_active = true
	if _mdma_pitch_active:
		pitch_scale = _mdma_base_pitch * lerpf(1.0, MDMA_SPEED, weight)
		if weight <= 0.0:
			_mdma_pitch_active = false
