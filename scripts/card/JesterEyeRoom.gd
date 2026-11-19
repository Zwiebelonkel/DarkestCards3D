extends Node3D

@onready var eye: Node3D = $Eye

func follow_card_pointer(target: Vector3, delta: float) -> void:
	var direction := (target - eye.position).normalized()
	var desired := Basis.looking_at(direction, Vector3.UP, true).get_rotation_quaternion()
	eye.quaternion = eye.quaternion.slerp(desired, 1.0 - exp(-10.0 * delta))
