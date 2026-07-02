extends Node3D
class_name BloodBurst3D

@export var auto_free_time: float = 1.05

@onready var particles: GPUParticles3D = $Particles



func _ready() -> void:

	particles.restart()
	particles.emitting = true

	await get_tree().create_timer(auto_free_time).timeout
	queue_free()
