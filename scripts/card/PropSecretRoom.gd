extends Node3D

## Fit an imported prop onto its pedestal without changing its shared meshes or
## materials. Bounds include the model's authored rotation and import transform.
@export var display_height := 1.42
@export var rotation_speed_degrees := 12.0

@onready var _display: Node3D = $PropDisplay


func _ready() -> void:
	var normalization_root: Node3D = $PropDisplay/ModelNormalizer
	var bounds := AABB()
	var found := false
	for child in normalization_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := normalization_root.global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_bounds: AABB = relative * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	if not found:
		return
	var normalization := display_height / maxf(bounds.size.y, 0.001)
	normalization_root.scale = Vector3.ONE * normalization
	var floor_center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	normalization_root.position = -floor_center * normalization


func _process(delta: float) -> void:
	# The normalized model turns on its own vertical axis above the pedestal.
	_display.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
