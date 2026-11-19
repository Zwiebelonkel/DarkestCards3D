extends Node3D
## Listener-relative positional clue, owned lo-fi filter and quiet vinyl crackle.

signal clue_started(index: int, direction: Vector3)

const CLIPS := [
	preload("res://assets/sounds/SFX/names/pablo.res"),
	preload("res://assets/sounds/SFX/names/trinity.res"),
	preload("res://assets/sounds/SFX/names/steward.res"),
	preload("res://assets/sounds/SFX/names/hannah.res"),
	preload("res://assets/sounds/SFX/names/seperator.res"),
]
const DIRECTIONS := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.ZERO]
const CLIP_GAP := 0.35

var active := false
var clue_index := -1
var _camera: Camera3D
var _voice: AudioStreamPlayer3D
var _separator: AudioStreamPlayer
var _crackle: AudioStreamPlayer
var _delay: Timer
var _distortion: AudioEffectDistortion


func _ready() -> void:
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = &"SFX"
	_voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_voice.panning_strength = 1.5
	add_child(_voice)
	_separator = AudioStreamPlayer.new()
	_separator.bus = &"SFX"
	add_child(_separator)
	_crackle = AudioStreamPlayer.new()
	_crackle.bus = &"SFX"
	_crackle.stream = _make_crackle()
	add_child(_crackle)
	_delay = Timer.new()
	_delay.one_shot = true
	add_child(_delay)
	_delay.timeout.connect(_play_next)
	_voice.finished.connect(_queue_next)
	_separator.finished.connect(_queue_next)
	set_process(false)


func start(camera: Camera3D, initial_delay: float) -> void:
	stop()
	_camera = camera
	active = true
	clue_index = -1
	_distortion = AudioEffectDistortion.new()
	_distortion.resource_name = "MdmaLoFi"
	_distortion.mode = AudioEffectDistortion.MODE_LOFI
	_distortion.keep_hf_hz = 16000.0
	_distortion.drive = 0.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _distortion)
	set_strength(0.0)
	_crackle.play()
	set_process(true)
	_process(0.0)
	_delay.start(maxf(initial_delay, 0.01))


func _process(_delta: float) -> void:
	if is_instance_valid(_camera):
		# Keep the sources at ear height, around the current listener, even while
		# walking/turning; the authored table transform must not skew the panning.
		global_transform = _camera.global_transform.orthonormalized()


func set_strength(strength: float) -> void:
	var weight := clampf(strength, 0.0, 1.0)
	if _distortion != null:
		_distortion.drive = 0.10 * weight
	if is_instance_valid(_crackle):
		_crackle.volume_db = linear_to_db(maxf(weight * 0.025, 0.0001))
	if is_instance_valid(_voice):
		_voice.volume_db = linear_to_db(maxf(weight, 0.0001))
		_separator.volume_db = _voice.volume_db


func _play_next() -> void:
	if not active:
		return
	clue_index = (clue_index + 1) % CLIPS.size()
	var direction: Vector3 = DIRECTIONS[clue_index]
	if clue_index == CLIPS.size() - 1:
		_separator.stream = CLIPS[clue_index]
		_separator.play()
	else:
		_voice.position = direction * 2.0
		_voice.stream = CLIPS[clue_index]
		_voice.play()
	clue_started.emit(clue_index, direction)


func _queue_next() -> void:
	if active:
		_delay.start(CLIP_GAP)


func stop() -> void:
	active = false
	set_process(false)
	if is_instance_valid(_delay):
		_delay.stop()
		_voice.stop()
		_separator.stop()
		_crackle.stop()
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and _distortion != null:
		for index in range(AudioServer.get_bus_effect_count(master) - 1, -1, -1):
			if AudioServer.get_bus_effect(master, index) == _distortion:
				AudioServer.remove_bus_effect(master, index)
	_distortion = null
	_camera = null


func _make_crackle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2507
	var data := PackedByteArray()
	const SAMPLE_RATE := 22050
	data.resize(SAMPLE_RATE * 2 * 2)
	var impulse := 0.0
	for index in range(SAMPLE_RATE * 2):
		if rng.randf() < 0.0018:
			impulse = rng.randf_range(-0.85, 0.85)
		impulse *= 0.56
		var sample := clampf(impulse + rng.randf_range(-0.025, 0.025), -1.0, 1.0)
		data.encode_s16(index * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = SAMPLE_RATE * 2
	return stream


func _exit_tree() -> void:
	stop()
