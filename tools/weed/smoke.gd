extends Node

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	print("WEED_SMOKE: PASS audio=", AudioServer.get_driver_name(), " display=", DisplayServer.get_name())
	get_tree().quit()
