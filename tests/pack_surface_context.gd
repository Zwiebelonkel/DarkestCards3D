extends Node

## Honest hub camera, authored lighting and post effects; no fixture lights.
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run this capture in an isolated project.")
		get_tree().quit(1)
		return
	var output := "res://pack-surface-context"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	GameCurrency.level = 10
	GameCurrency.coins = 1000.0
	get_tree().root.size = Vector2i(1500, 900)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	if not main._request_turn(-1):
		push_error("Could not turn toward the pack shop.")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.4).timeout
	var screen: PackOpeningScreen = main.get_node("ScenePivot/PackShopMachine/PackOpeningScreen")
	if not screen.buy_pack("ultra", PackDefinition.PACK_TYPES["ultra"]):
		push_error("Context purchase failed.")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.0).timeout
	for frame in range(8):
		await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png(output + "/06-hub-context.png") != OK:
		get_tree().quit(1)
		return
	var file := FileAccess.open(output + "/context_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"captured_at_utc": Time.get_datetime_string_from_system(true), "main_scene_modified": FileAccess.get_modified_time("res://scenes/main/Main.tscn"), "pack": "ultra", "camera": str(main.main_camera.global_transform), "fov": main.main_camera.fov, "fixture": "real Main; turn left and buy Ultra; authored lighting and post effects; isolated saves"}, "\t"))
	file.close()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PACK_SURFACE_CONTEXT: PASS")
	get_tree().quit()
