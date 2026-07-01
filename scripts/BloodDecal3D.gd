extends Node3D
class_name BloodDecal3D

@export var normal_scale := Vector3(0.34, 0.34, 0.34)
@export var kill_scale := Vector3(0.78, 0.78, 0.78)

@export var fade_delay: float = 0.45
@export var fade_duration: float = 1.45
@export var start_alpha: float = 0.78

@onready var decal_mesh: MeshInstance3D = $DecalMesh

var _is_kill := false
var _material: ShaderMaterial


func setup(is_kill: bool = false) -> void:
	_is_kill = is_kill


func _ready() -> void:
	scale = kill_scale if _is_kill else normal_scale

	_material = decal_mesh.material_override as ShaderMaterial
	if _material != null:
		# Damit mehrere Decals nicht alle exakt gleich aussehen.
		_material = _material.duplicate() as ShaderMaterial
		decal_mesh.material_override = _material

		_material.set_shader_parameter("alpha", start_alpha)
		_material.set_shader_parameter("seed", randf() * 100.0)

	var tween := create_tween()
	tween.tween_interval(fade_delay)
	tween.tween_method(_set_alpha, start_alpha, 0.0, fade_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	tween.finished.connect(func():
		queue_free()
	)


func _set_alpha(value: float) -> void:
	if _material == null:
		return

	_material.set_shader_parameter("alpha", value)
