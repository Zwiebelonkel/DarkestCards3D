extends Node3D

@export var amplitude: float = 0.08      # Höhe der Bewegung (Meter)
@export var speed: float = 1.5           # Geschwindigkeit
@export var random_offset := true        # Startphase zufällig

var _start_position: Vector3
var _time := 0.0

func _ready() -> void:
	_start_position = global_position

	if random_offset:
		_time = randf() * TAU

func _process(delta: float) -> void:
	_time += delta * speed

	global_position = _start_position + Vector3(
		0.0,
		sin(_time) * amplitude,
		0.0
	)
