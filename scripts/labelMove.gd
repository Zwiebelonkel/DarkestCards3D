extends Label3D

@export var horizontal_distance := 0.15
@export var vertical_distance := 0.05
@export var speed := 1.0

var start_position: Vector3

func _ready() -> void:
	start_position = position

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 * speed

	position.x = start_position.x + sin(t) * horizontal_distance
	position.y = start_position.y + cos(t * 0.7) * vertical_distance
