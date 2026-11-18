extends Node

const MENU_PATH := "res://scenes/main/MainMenu.tscn"
const LOADING_PATH := "res://scenes/main/LoadingScreen.tscn"
const MAIN_PATH := "res://scenes/main/Main.tscn"

var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _wait_for_scene(path: String, timeout: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		if is_instance_valid(current) and current.scene_file_path == path:
			return true
		await get_tree().process_frame
	return false


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	# Keep this coordinator alive while exercising actual SceneTree changes.
	get_tree().current_scene = null
	var error := get_tree().change_scene_to_file(MENU_PATH)
	check(error == OK and await _wait_for_scene(MENU_PATH), "the real main menu opens")
	if failures > 0:
		_finish()
		return
	var menu := get_tree().current_scene as MainMenu
	menu.selected_slot = 2
	menu._play_selected()
	menu._play_selected()
	check(await _wait_for_scene(LOADING_PATH), "Play enters the standalone loading scene even after a double click")
	if failures > 0:
		_finish()
		return
	check(SaveSlots.active_slot == 2, "the selected save slot is committed before background loading")
	var loading := get_tree().current_scene as Control
	check(not bool(loading.get("_request_started")), "Main is not requested before the loading screen can draw")
	check((loading.get_node("Black") as ColorRect).color == Color.BLACK, "the standalone scene covers the viewport in black")
	var bar := loading.get_node("Center/Content/LoadingBar") as ProgressBar
	var portrait := loading.get_node("Center/Content/Satan") as TextureRect
	check(not bar.show_percentage and bar.value == 0.0 and not loading.find_children("*", "Label", true, false).size(), "the screen contains only Satan and an empty minimalist bar")
	var atlas := portrait.texture as AtlasTexture
	var starting_region := atlas.region
	var changed_frames := 0
	var maximum_progress := 0.0
	var last_progress := 0.0
	var completed := false
	var captured := false
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(loading) and Time.get_ticks_msec() < deadline:
		if atlas.region != starting_region:
			changed_frames += 1
			starting_region = atlas.region
		if bar.value < last_progress:
			check(false, "loading progress never moves backwards")
		last_progress = bar.value
		maximum_progress = maxf(maximum_progress, bar.value)
		if not completed and bar.value == 1.0:
			completed = true
			check(loading.get("_loaded_scene") is PackedScene, "the bar reaches 100 percent only after Main is fully loaded")
		if not captured and float(loading.get("_elapsed")) >= 0.2 and DisplayServer.get_name() != "headless":
			captured = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://loading-screen-preview.png")
		await get_tree().process_frame
	check(changed_frames >= 2, "Satan's existing laugh sheet continues animating while loading")
	check(maximum_progress == 1.0 and completed, "the completed bar is displayed before the scene switch")
	check(await _wait_for_scene(MAIN_PATH), "the deferred handoff enters the real Main scene")
	check(not get_tree().paused and SaveSlots.active_slot == 2, "entering Main preserves the selected profile and resumes normal processing")
	# Returning and entering again exercises the cached-resource request path.
	get_tree().change_scene_to_file(MENU_PATH)
	check(await _wait_for_scene(MENU_PATH), "returning from Main restores the menu")
	menu = get_tree().current_scene as MainMenu
	menu._change_scene(MAIN_PATH)
	check(await _wait_for_scene(LOADING_PATH), "the menu's direct/online entry path also uses the loader")
	check(await _wait_for_scene(MAIN_PATH), "a repeated load reaches Main without getting stuck or duplicating the transition")
	get_tree().current_scene.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	print("LOADING_SCREEN_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
