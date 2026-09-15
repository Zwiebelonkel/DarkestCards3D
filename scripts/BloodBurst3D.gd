extends Node3D
class_name BloodBurst3D

@export var auto_free_time: float = 1.05

@onready var particles: GPUParticles3D = $Particles

var _intensity := 1.0


func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.1, 2.0)
	if is_node_ready():
		_apply_intensity()

func _ready() -> void:
	_apply_intensity()
	particles.restart()
	particles.emitting = true

	await get_tree().create_timer(auto_free_time).timeout
	queue_free()


func _apply_intensity() -> void:
	if particles == null:
		return
	particles.amount = maxi(int(round(1000.0 * _intensity)), 180)
	particles.speed_scale = lerpf(0.85, 1.2, clampf((_intensity - 0.1) / 1.9, 0.0, 1.0))
