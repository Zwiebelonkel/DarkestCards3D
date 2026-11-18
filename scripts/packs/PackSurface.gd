extends RefCounted
class_name PackSurface

## Shared immutable heightmaps; per-instance materials never alter the GLBs.
const SURFACE_SHADER := preload("res://assets/shader/pack_surface.gdshader")
const HEIGHTMAPS := {
	"basic": preload("res://assets/cards/pack/surfaces/basic_height.res"),
	"ultra": preload("res://assets/cards/pack/surfaces/ultra_height.res"),
	"god": preload("res://assets/cards/pack/surfaces/god_height.res"),
}
const PROFILES := {
	"basic": {"relief": 0.00035, "tint": 0.018, "roughness": 0.025, "gloss": 0.33, "metallic": 0.25},
	"ultra": {"relief": 0.0006, "tint": 0.025, "roughness": 0.035, "gloss": 0.32, "metallic": 0.32},
	"god": {"relief": 0.0008, "tint": 0.028, "roughness": 0.04, "gloss": 0.31, "metallic": 0.42},
}


static func apply_to_pack(pack: Node3D, pack_id: String, include_top: bool = true) -> void:
	for node_name: String in ["base", "top"]:
		if node_name == "top" and not include_top:
			continue
		var instance := pack.get_node_or_null(node_name) as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var source := instance.get_active_material(surface)
			if source is ShaderMaterial and source.shader == SURFACE_SHADER:
				configure_material(source, null, pack_id)
				continue
			var material := ShaderMaterial.new()
			material.shader = SURFACE_SHADER
			configure_material(material, source, pack_id)
			material.set_shader_parameter("metric_scale", instance.scale.abs())
			material.set_shader_parameter("surface_origin", instance.position)
			instance.set_surface_override_material(surface, material)


static func configure_material(material: ShaderMaterial, original: Material, pack_id: String) -> void:
	var profile: Dictionary = PROFILES.get(pack_id, PROFILES["basic"])
	material.set_shader_parameter("surface_heightmap", HEIGHTMAPS.get(pack_id, HEIGHTMAPS["basic"]))
	material.set_shader_parameter("surface_relief", profile["relief"])
	material.set_shader_parameter("surface_tint_strength", profile["tint"])
	material.set_shader_parameter("surface_roughness_strength", profile["roughness"])
	if original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("has_albedo_texture", source.albedo_texture != null)
		material.set_shader_parameter("albedo_tint", source.albedo_color)
	# Printed metallic backing under a smooth dielectric plastic laminate.
	material.set_shader_parameter("metallic_value", profile["metallic"])
	material.set_shader_parameter("roughness_value", profile["gloss"])
