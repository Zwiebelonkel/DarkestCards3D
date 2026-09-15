extends Node3D
## Local light shimmer follows the shader without consuming gameplay randomness.

@onready var fire_light: OmniLight3D = $FireLight
var _time := 0.0
var _base_energy := 1.0


func _ready() -> void:
	_base_energy = fire_light.light_energy


func _process(delta: float) -> void:
	_time += delta
	var shimmer := sin(_time * 7.3) * 0.08 + sin(_time * 12.7 + 0.9) * 0.045 + sin(_time * 3.1) * 0.035
	fire_light.light_energy = _base_energy * (1.0 + shimmer)
