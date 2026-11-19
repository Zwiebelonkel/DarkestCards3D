extends Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3)
	add_child(camera)
	camera.current = true
	var aperture := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.8, 1.7)
	aperture.mesh = quad
	add_child(aperture)
	var diorama = load("res://scripts/card/CardDiorama.gd").new()
	add_child(diorama)
	diorama.configure(aperture, load("res://scenes/cards/JesterEyeSecretRoom.tscn"))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = diorama.get_texture()
	aperture.material_override = material
	for i in range(16):
		await get_tree().process_frame
	var room = diorama._room
	room.follow_card_pointer(Vector3(2, 1, 0), 1.0)
	assert(room.eye.basis.z.x > 0 and room.eye.basis.z.y > 0)
	room.follow_card_pointer(Vector3(-2, -1, 0), 1.0)
	assert(room.eye.basis.z.x < 0 and room.eye.basis.z.y < 0)
	room.follow_card_pointer(Vector3.ZERO, 1.0)
	assert(room.eye.basis.z.normalized().z > 0.99)
	diorama.set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/jester_eye/dark_room.png")
	print("JESTER_DARK_ROOM_OK")
	get_tree().quit()
