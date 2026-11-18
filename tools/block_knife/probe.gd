extends Node3D

func _ready() -> void:
	var model := (load("res://assets/environments/props/knife/knife.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var bounds := AABB()
	var first := true
	var tip := Vector3(0, 0, INF)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
		var box := local * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface in range(mesh.mesh.get_surface_count()):
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := local * vertex
				if point.z < tip.z:
					tip = point
	print(JSON.stringify({"bounds":str(bounds), "tip":str(tip)}))
	model.queue_free()
	await get_tree().process_frame
	print("BLOCK_KNIFE_PROBE: PASS")
	get_tree().quit()
