extends Node3D
class_name ParticleBurst3D

@export var auto_free_time: float = 1.5

@onready var particles: GPUParticles3D = $Particles

func _ready() -> void:
	if particles == null:
		queue_free()
		return

	particles.restart()
	particles.emitting = true

	await get_tree().create_timer(auto_free_time).timeout
	queue_free()
