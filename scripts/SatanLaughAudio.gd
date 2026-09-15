extends AudioStreamPlayer3D

const VOICE_SOUND := preload("res://assets/sounds/SFX/satanVoice.mp3")
const PITCH_STEPS := [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0]

@export_range(-24.0, 24.0, 0.5) var pitch_offset_semitones := 0.0

var _laughing := false
var _syllable_remaining := 0.0
var _last_pitch_index := -1
# Sound variation must not consume the card/slot outcome RNG.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	stream = VOICE_SOUND
	bus = &"SFX"
	volume_db = -8.0
	unit_size = 5.0
	max_distance = 20.0
	set_process(false)


func set_laughing(active: bool) -> void:
	if _laughing == active:
		return
	_laughing = active
	_syllable_remaining = 0.0
	set_process(active)
	if active and _source_is_visible():
		_play_syllable()
	else:
		stop()


func _process(delta: float) -> void:
	if not _source_is_visible():
		stop()
		_syllable_remaining = 0.0
		return
	_syllable_remaining -= delta
	if _syllable_remaining <= 0.0:
		_play_syllable()


func _source_is_visible() -> bool:
	var source := get_parent() as Node3D
	return source != null and source.is_visible_in_tree()


func _play_syllable() -> void:
	# Pick a different pitch every time, keeping the short sample intact.
	var pitch_index := _rng.randi_range(0, PITCH_STEPS.size() - (1 if _last_pitch_index < 0 else 2))
	if _last_pitch_index >= 0 and pitch_index >= _last_pitch_index:
		pitch_index += 1
	_last_pitch_index = pitch_index
	pitch_scale = pow(2.0, (PITCH_STEPS[pitch_index] + pitch_offset_semitones) / 12.0)
	play()
	_syllable_remaining = stream.get_length() / pitch_scale + _rng.randf_range(0.0, 0.012)
