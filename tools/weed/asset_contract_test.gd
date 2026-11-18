extends Node
## Godot-native structural and budget audit.
## Pass --target=res://path/asset.tscn [--manifest=res://path/asset.asset.json]
##      [--report=C:/out/asset_audit.json]


func _ready() -> void:
	var options := parse_arguments()
	var target_path: String = options.get("target", "")
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		_fail("Pass an existing --target=res://... scene")
		return
	var packed := load(target_path) as PackedScene
	var target := packed.instantiate() as Node3D if packed != null else null
	if target == null:
		_fail("Target is not an instantiable Node3D scene")
		return
	add_child(target)
	await get_tree().process_frame

	var metrics := scene_metrics(target)
	var manifest_path: String = options.get("manifest", target_path.trim_suffix(".tscn") + ".asset.json")
	var manifest := load_manifest(manifest_path)
	var failures: Array[String] = []
	if metrics["mesh_instances"] + metrics["multimesh_instances"] <= 0:
		failures.append("scene has no visible MeshInstance3D or MultiMeshInstance3D")
	if metrics["multimesh_invalid_buffers"] > 0:
		failures.append("%d MultiMesh resources have incomplete transform buffers" % metrics["multimesh_invalid_buffers"])
	if metrics["multimesh_missing_custom_aabb"] > 0:
		failures.append("%d populated MultiMesh resources have no authored custom_aabb" % metrics["multimesh_missing_custom_aabb"])
	var bounds_position: Array = metrics["bounds"]["position"]
	var bounds_size: Array = metrics["bounds"]["size"]
	if bounds_size[0] <= 0.0 or bounds_size[1] <= 0.0 or bounds_size[2] <= 0.0:
		failures.append("visible bounds are empty")

	if not manifest.is_empty():
		if String(manifest.get("scene", target_path)) != target_path:
			failures.append("manifest scene does not match target")
		var collision: Dictionary = manifest.get("collision", {})
		if collision.get("required", false) and metrics["collision_shapes"] <= 0:
			failures.append("manifest requires collision but no CollisionShape3D exists")
		if manifest.get("origin", "") == "ground_center" and absf(float(bounds_position[1])) > 0.15:
			failures.append("ground origin is %.3fm from the visible base" % float(bounds_position[1]))
		_compare_dimensions(manifest, bounds_size, failures)
		var budgets: Dictionary = manifest.get("budgets", {})
		for key in ["nodes", "mesh_instances", "multimesh_instances",
				"multimesh_elements", "multimesh_invalid_buffers",
				"multimesh_missing_custom_aabb", "collision_shapes",
				"concave_collision_shapes", "collision_triangles", "surfaces", "triangles",
				"unique_materials", "lights", "particles", "nonuniform_scales"]:
			if budgets.has(key) and int(metrics[key]) > int(budgets[key]):
				failures.append("%s exceeds budget: %d > %d" % [key, metrics[key], budgets[key]])

	var report := {
		"target": target_path,
		"manifest": manifest_path if not manifest.is_empty() else "",
		"passed": failures.is_empty(),
		"failures": failures,
		"metrics": metrics,
	}
	var report_path: String = options.get("report", "")
	if not report_path.is_empty():
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			failures.append("could not write report: %s" % error_string(FileAccess.get_open_error()))
			report["passed"] = false
			report["failures"] = failures
		else:
			file.store_string(JSON.stringify(report, "  "))

	print("asset audit: %s" % JSON.stringify(report))
	print("asset_contract_test %s" % ("PASSED" if failures.is_empty() else "FAILED"))
	target.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func parse_arguments() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target="):
			options["target"] = argument.trim_prefix("--target=")
		elif argument.begins_with("--manifest="):
			options["manifest"] = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--report="):
			options["report"] = argument.trim_prefix("--report=")
	return options


func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _compare_dimensions(manifest: Dictionary, bounds_size: Array,
		failures: Array[String]) -> void:
	var footprint: Array = manifest.get("footprint_m", [])
	if footprint.size() == 2:
		_compare_measure("footprint width", float(footprint[0]), float(bounds_size[0]), failures)
		_compare_measure("footprint depth", float(footprint[1]), float(bounds_size[2]), failures)
	var expected_height := float(manifest.get("height_m", 0.0))
	if expected_height > 0.0:
		_compare_measure("height", expected_height, float(bounds_size[1]), failures)


func _compare_measure(label: String, expected: float, actual: float,
		failures: Array[String]) -> void:
	var tolerance := maxf(0.10, expected * 0.10)
	if absf(expected - actual) > tolerance:
		failures.append("%s differs from manifest: %.3f vs %.3f" % [label, actual, expected])


func scene_metrics(root: Node3D) -> Dictionary:
	var metrics := {
		"nodes": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"multimesh_elements": 0,
		"multimesh_buffer_floats": 0,
		"multimesh_invalid_buffers": 0,
		"multimesh_missing_custom_aabb": 0,
		"collision_shapes": 0,
		"concave_collision_shapes": 0,
		"collision_triangles": 0,
		"surfaces": 0,
		"triangles": 0,
		"unique_materials": 0,
		"lights": 0,
		"particles": 0,
		"nonuniform_scales": 0,
	}
	var materials := {}
	accumulate_metrics(root, metrics, materials)
	metrics["unique_materials"] = materials.size()
	var bounds := merged_bounds(root)
	metrics["bounds"] = {
		"position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"size": [bounds.size.x, bounds.size.y, bounds.size.z],
	}
	return metrics


func accumulate_metrics(node: Node, metrics: Dictionary, materials: Dictionary) -> void:
	metrics["nodes"] += 1
	if node is Node3D:
		var node_scale := (node as Node3D).transform.basis.get_scale().abs()
		if not is_equal_approx(node_scale.x, node_scale.y) or not is_equal_approx(node_scale.y, node_scale.z):
			metrics["nonuniform_scales"] += 1
	if node is CollisionShape3D:
		metrics["collision_shapes"] += 1
		var collision_shape := (node as CollisionShape3D).shape
		if collision_shape is ConcavePolygonShape3D:
			var concave := collision_shape as ConcavePolygonShape3D
			metrics["concave_collision_shapes"] += 1
			metrics["collision_triangles"] += concave.get_faces().size() / 3
	if node is Light3D:
		metrics["lights"] += 1
	if node is GPUParticles3D or node is CPUParticles3D:
		metrics["particles"] += 1
	if node is MeshInstance3D:
		metrics["mesh_instances"] += 1
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			metrics["surfaces"] += mesh.get_surface_count()
			for surface in mesh.get_surface_count():
				var material := mesh_instance.material_override
				if material == null:
					material = mesh.surface_get_material(surface)
				if material != null:
					materials[material.get_instance_id()] = true
			metrics["triangles"] += mesh.get_faces().size() / 3
	if node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if multimesh != null and multimesh.mesh != null:
			metrics["multimesh_instances"] += 1
			metrics["multimesh_elements"] += multimesh.instance_count
			var buffer_size := multimesh.get_buffer().size()
			metrics["multimesh_buffer_floats"] += buffer_size
			var stride := 12 + (4 if multimesh.use_colors else 0) \
				+ (4 if multimesh.use_custom_data else 0)
			if multimesh.instance_count > 0 and buffer_size < multimesh.instance_count * stride:
				metrics["multimesh_invalid_buffers"] += 1
			var authored_bounds := multimesh.custom_aabb
			if multimesh.instance_count > 0 and (authored_bounds.size.x <= 0.0 \
					or authored_bounds.size.y <= 0.0 or authored_bounds.size.z <= 0.0):
				metrics["multimesh_missing_custom_aabb"] += 1
			metrics["surfaces"] += multimesh.mesh.get_surface_count()
			metrics["triangles"] += multimesh.mesh.get_faces().size() / 3 \
				* multimesh.instance_count
			for surface in multimesh.mesh.get_surface_count():
				var material := (node as MultiMeshInstance3D).material_override
				if material == null:
					material = multimesh.mesh.surface_get_material(surface)
				if material != null:
					materials[material.get_instance_id()] = true
	for child in node.get_children():
		accumulate_metrics(child, metrics, materials)


func merged_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := relative * mesh_instance.get_aabb()
		bounds = transformed if not has_bounds else bounds.merge(transformed)
		has_bounds = true
	for found in root.find_children("*", "MultiMeshInstance3D", true, false):
		var multimesh_instance := found as MultiMeshInstance3D
		if multimesh_instance.multimesh == null or multimesh_instance.multimesh.mesh == null:
			continue
		var relative := root.global_transform.affine_inverse() * multimesh_instance.global_transform
		var transformed := relative * multimesh_instance.get_aabb()
		bounds = transformed if not has_bounds else bounds.merge(transformed)
		has_bounds = true
	return bounds


func _fail(message: String) -> void:
	push_error(message)
	print("asset_contract_test FAILED")
	get_tree().quit(1)
