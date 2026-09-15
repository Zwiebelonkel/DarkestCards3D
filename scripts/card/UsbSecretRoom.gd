extends Node3D

## Normalize the supplied USB asset without editing its imported geometry or
## shared materials. The rest of the vault is authored in the scene.
@export var rotation_speed_degrees := 12.0

@onready var _display: Node3D = $USBDisplay


func _ready() -> void:
	var model: Node3D = $USBDisplay/USBModel
	var bounds := AABB()
	var found := false
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := model.global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_bounds: AABB = relative * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	if not found:
		return
	var longest_side := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var normalization := 1.72 / maxf(longest_side, 0.001)
	model.scale = Vector3.ONE * normalization
	model.position = -(model.basis * bounds.get_center())


func _process(delta: float) -> void:
	# Rotate the centered display, keeping its position and the vault fixed.
	_display.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
