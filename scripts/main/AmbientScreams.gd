extends Node3D
## Local, spatial horror ambience. Owned by Main, so it stops on scene exit.

const SCREAMS: Array[AudioStream] = [
	preload("res://assets/sounds/SFX/screams/scream1.mp3"),
	preload("res://assets/sounds/SFX/screams/scream2.mp3"),
	preload("res://assets/sounds/SFX/screams/scream3.mp3"),
]
const MIN_INTERVAL := 300.0
const MAX_INTERVAL := 600.0
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 12.0
const MIN_PITCH := 0.8
const MAX_PITCH := 1.2

# Keep ambience independent of card, pack and slot outcome randomness.
var _rng := RandomNumberGenerator.new()
var _timer: Timer
var _player: AudioStreamPlayer3D


func _ready() -> void:
	_rng.randomize()
	_player = AudioStreamPlayer3D.new()
	_player.name = "ScreamAudio"
	_player.bus = &"SFX"
	_player.volume_db = -8.0
	_player.unit_size = 8.0
	_player.max_distance = 40.0
	add_child(_player)
	_timer = Timer.new()
	_timer.name = "ScreamTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	_schedule_next()


func _schedule_next() -> void:
	_timer.start(_rng.randf_range(MIN_INTERVAL, MAX_INTERVAL))


func _on_timeout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(MIN_DISTANCE, MAX_DISTANCE)
		# Place the emitter in world space; turning or walking never drags it along.
		_player.global_position = camera.global_position + Vector3(
			cos(angle) * distance, _rng.randf_range(-1.0, 2.0), sin(angle) * distance
		)
		_player.stream = SCREAMS[_rng.randi_range(0, SCREAMS.size() - 1)]
		_player.pitch_scale = _rng.randf_range(MIN_PITCH, MAX_PITCH)
		_player.play()
	_schedule_next()
