extends Node3D
## Local viewer concealment only. Numeric labels are emptied by Card3D.

const PUDDLE_SHADER := preload("res://assets/shader/card_stat_puddle.gdshader")
const PUDDLE_SIZE := Vector2(0.25, 0.145)


func configure(attack_position: Vector3, health_position: Vector3, variant: int) -> void:
	var quad := QuadMesh.new()
	quad.size = PUDDLE_SIZE
	var material := ShaderMaterial.new()
	material.shader = PUDDLE_SHADER
	material.render_priority = 85
	var positions: Array[Vector3] = [attack_position, health_position]
	for i in range(positions.size()):
		var puddle := MeshInstance3D.new()
		puddle.name = "AttackPuddle" if i == 0 else "HealthPuddle"
		puddle.mesh = quad
		puddle.material_override = material
		puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puddle.position = Vector3(positions[i].x, positions[i].y - 0.004, 0.045)
		add_child(puddle)
		# Stable per-card shapes; no random draws, timers or gameplay state.
		puddle.set_instance_shader_parameter("blot_seed", float(absi(variant % 997)) * 0.127 + float(i) * 3.71)
