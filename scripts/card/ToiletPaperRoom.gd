extends Node3D

@onready var display: Node3D = $Display

func _ready() -> void:
	var model: Node3D = $Display/Model
	var bounds := AABB()
	var found := false
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local := model.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = local * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if found:
		var factor := 1.45 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		model.scale = Vector3.ONE * factor
		model.position = -bounds.get_center() * factor

func follow_card_pointer(target: Vector3, delta: float) -> void:
	var direction := (target - display.position).normalized()
	var desired := Basis.looking_at(direction, Vector3.UP, true).get_rotation_quaternion()
	display.quaternion = display.quaternion.slerp(desired, 1.0 - exp(-10.0 * delta))
