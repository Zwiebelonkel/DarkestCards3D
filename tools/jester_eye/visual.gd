extends Node3D

func _ready() -> void:
	assert(load("res://scripts/ui/AccessKeyTray.gd") != null)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 5)
	add_child(camera)
	camera.current = true
	var preview = load("res://scripts/ui/JesterEyePreview.gd").new()
	preview.pixel_size = 0.008
	add_child(preview)
	var room = load("res://scenes/cards/JesterEyeSecretRoom.tscn").instantiate()
	add_child(room)
	room.position = Vector3(3, 0, 0)
	for i in range(12):
		preview.follow_pointer(get_viewport().get_visible_rect().size * 0.5, camera, 0.1)
		await get_tree().process_frame
	assert(preview.eye.basis.z.z > 0.99)
	preview.follow_pointer(Vector2(1800, 100), camera, 1.0)
	assert(preview.eye.basis.z.x > 0.0 and preview.eye.basis.z.y > 0.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/jester_eye/preview.png")
	print("JESTER_EYE_OK")
	get_tree().quit()
