extends Node3D
class_name BloodBurst3D

@export var auto_free_time: float = 1.05
@export var base_amount: int = 90
@export var velocity_min: float = 1.4
@export var velocity_max: float = 3.8

var _intensity: float = 1.0

@onready var particles: GPUParticles3D = $Particles


func set_intensity(value: float) -> void:
	_intensity = clamp(value, 0.25, 2.5)

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

	particles.amount = max(1, int(base_amount * _intensity))

	var process := particles.process_material as ParticleProcessMaterial
	if process != null:
		process.initial_velocity_min = velocity_min * _intensity
		process.initial_velocity_max = velocity_max * _intensity
