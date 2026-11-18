extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS: " if condition else "FAIL: ") + message)


func settle(seconds: float = 0.05) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _new_main(hide_lens: bool = false) -> MainScene:
	var scene := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	scene.greeting_enabled = true
	scene.mouse_tilt_strength = 0.0
	if hide_lens:
		scene.get_node("CameraPivot/CameraTilt/Camera3D/CanvasLayer").hide()
	viewport.add_child(scene)
	return scene


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event, true)


func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://greeting-" + label + ".png")


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match feature runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	PlaytimeManager.encounter_completed = true
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.save()
	Localization.set_locale("de")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = _new_main()
	var greeting = main._greeting
	check(main._greeting_active and is_instance_valid(greeting), "fresh slot starts its greeting before the first frame")
	if not is_instance_valid(greeting):
		_finish()
		return
	var pose: Transform3D = greeting._camera_pose
	var mask: int = greeting._camera_mask
	var intro_environment := main.main_camera.environment
	var scene_environment := main.main_camera.get_world_3d().environment
	check(intro_environment != scene_environment and intro_environment.glow_enabled == scene_environment.glow_enabled and is_equal_approx(intro_environment.glow_intensity, scene_environment.glow_intensity), "intro preserves the scene's eye glow in its own dark environment")
	var lights: Dictionary = greeting._light_visibility.duplicate()
	var canvases: Dictionary = greeting._canvas_visibility.duplicate()
	var lens := main.main_camera.get_node("CanvasLayer") as CanvasLayer
	var screen := main.main_camera.get_node("CanvasLayer2") as CanvasLayer
	var lens_material := main.dirty_lens.material
	var screen_rect := screen.get_node("ColorRect") as ColorRect
	var screen_material := screen_rect.material
	check(lens.visible and screen.visible and main.dirty_lens.is_visible_in_tree() and screen_rect.is_visible_in_tree(), "intro keeps both camera overlay passes visible from its first frame")
	check(not canvases.has(lens) and not canvases.has(screen), "intro hides HUD layers without taking ownership of camera filters")
	check(lights.size() > 0 and lights.keys().all(func(light): return not light.visible) and not main.music.playing, "every scene light and the music stay off during the greeting")
	check(main.main_camera.cull_mask == greeting.EYES_LAYER and main.main_camera.environment.background_color == Color.BLACK, "only Satan's eyes render against true darkness")
	check(main.main_camera.global_position.distance_to((main.scene_pivot.get_node("GameTable") as GameTable).dealer_satan.global_position) < 0.8, "camera starts right in front of Satan's eyes")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "intro blocks navigation, travel and journal")
	check(not main.level_progress._enabled and not main._access_key_context_is_safe() and main.pause_menu._cinematic_locked, "progress, keys and pause remain locked")
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	check(table._journal_input_blocked and not table.satan_hover_area.input_ray_pickable, "table and Satan hover are blocked")
	var opening_pose := main.main_camera.global_transform
	await settle(0.08)
	await _capture("eyes")
	_key(KEY_J)
	_key(KEY_D)
	_key(KEY_ESCAPE)
	main._read_input()
	check(not main.journal.is_active() and not main.pause_menu.visible and main._pending_direction == 0, "gameplay keys cannot interrupt the intro")
	await settle(0.7)
	check(greeting._body.text == "Hallo, Abschaum." and greeting._body.visible_characters >= 0, "offline greeting uses Abschaum with typewriter text")
	check(greeting._voice._laughing and greeting._voice.pitch_offset_semitones == DealerDialogue.VOICE_PITCH_OFFSET, "voice uses exactly the dealer's deep pitch")
	await _capture("hello")
	check(lens.visible and screen.visible and main.dirty_lens.material == lens_material and screen_rect.material == screen_material, "lens and screen effects keep rendering throughout the intro dialogue")
	await settle(0.5)
	check(not main.main_camera.global_transform.is_equal_approx(opening_pose) and not main.main_camera.global_transform.is_equal_approx(pose), "camera moves gradually toward the player's original pose")
	# Even rapidly reading through all lines cannot release controls in mid-flight.
	for index in range(greeting.SENTENCES.size()):
		if greeting._body.visible_characters >= 0:
			_key(KEY_SPACE)
		check(not greeting._voice._laughing and not greeting._voice.playing and not main.music.playing, "line %d ends silently while music stays stopped" % index)
		_key(KEY_SPACE)
	check(greeting._dialog_finished and main._greeting_active and not GameCurrency.greeting_completed, "finishing text early waits for the camera and does not save prematurely")
	await greeting.finished
	check(not main._greeting_active and GameCurrency.greeting_completed, "both completed tracks release the greeting and persist completion")
	check(main.main_camera.global_transform.is_equal_approx(pose) and main.main_camera.cull_mask == mask and main.main_camera.environment == null, "camera pose, render mask and environment are restored exactly")
	var scare := main.get_node_or_null("GreetingScare") as AudioStreamPlayer
	check(lights.keys().all(func(light): return light.visible == lights[light]) and main.music.playing and is_instance_valid(scare) and scare.playing and scare.stream.resource_path.ends_with("scare.mp3"), "lights, music and scare.mp3 start together")
	check(canvases.keys().all(func(canvas): return canvas.visible == canvases[canvas]), "HUD layers restore their previous visibility")
	check(lens.visible and screen.visible and main.dirty_lens.material == lens_material and screen_rect.material == screen_material, "intro completion leaves overlay visibility and materials unchanged")
	await settle()
	check(is_instance_valid(scare) and scare.playing, "the reveal sound survives disposal of the greeting node")
	check(main._can_turn() and not main.pause_menu._cinematic_locked and not table._journal_input_blocked, "player input becomes available after the final reveal")
	await _capture("lights-on")
	GameCurrency.reload_profile()
	check(GameCurrency.greeting_completed, "completion survives profile reload")
	main.queue_free()
	await settle()
	main = _new_main()
	check(not main._greeting_active and main.music.playing and not main.has_node("GreetingScare"), "returning to the same slot starts normal music without replaying the greeting or scare")
	main.queue_free()
	await settle()
	check(SaveSlots.select_slot(2) == OK and not GameCurrency.greeting_completed, "a second save slot has its own unseen greeting")
	check(SaveSlots.select_slot(1) == OK and GameCurrency.greeting_completed, "switching back preserves the first slot's completion")
	GameCurrency.clear_profile_state()
	NetworkManager.test_persona_name = "Luca [b]42%[/b]"
	main = _new_main(true)
	check(not main.main_camera.get_node("CanvasLayer").visible and main.main_camera.get_node("CanvasLayer2").visible, "an intentionally disabled lens stays disabled while the active screen filter stays visible")
	check(main._greeting_active, "a reset or fresh profile starts its own greeting")
	greeting = main._greeting
	greeting._hold_remaining = 0.0
	await settle()
	check(greeting._body.text == "Hallo, Luca [b]42%[/b]." and not greeting._body.bbcode_enabled, "Steam name is inserted literally without markup or format interpretation")
	NetworkManager.test_persona_name = ""
	main.queue_free()
	await settle()
	check(not GameCurrency.greeting_completed, "destroying an unfinished greeting never marks it complete")
	# Natural timing also finishes without any input, using short test timings.
	main = _new_main()
	greeting = main._greeting
	greeting.characters_per_second = 10000.0
	greeting.sentence_hold = 0.01
	greeting._camera_tween.set_speed_scale(20.0)
	greeting._hold_remaining = 0.01
	await greeting.finished
	check(GameCurrency.greeting_completed and not main._greeting_active, "all sentences advance and finish automatically")
	main.queue_free()
	await settle()
	GameCurrency.clear_profile_state()
	NetworkManager.current_lobby_id = 123
	main = _new_main()
	check(not main._greeting_active and not GameCurrency.greeting_completed, "online entry bypasses the intro without consuming it")
	main.queue_free()
	await settle()
	NetworkManager.current_lobby_id = 0
	main = _new_main()
	check(main._greeting_active, "offline entry still greets after bypassing for a lobby")
	NetworkManager.current_lobby_id = 123
	NetworkManager.lobby_state_changed.emit()
	check(not main._greeting_active and not GameCurrency.greeting_completed and not main.pause_menu._cinematic_locked and main.music.playing and not main.has_node("GreetingScare"), "an incoming Steam lobby restores music without playing the scare or marking the intro seen")
	main.queue_free()
	await settle()
	NetworkManager.current_lobby_id = 0
	# Legacy saves without an intro key must not greet established players again.
	var cfg := ConfigFile.new()
	cfg.load(GameCurrency.save_path)
	cfg.erase_section("intro")
	cfg.save(GameCurrency.save_path)
	GameCurrency.reload_profile()
	check(GameCurrency.greeting_completed, "pre-existing saves migrate as already greeted")
	GameCurrency.clear_profile_state()
	var original_path := GameCurrency.save_path
	GameCurrency.save_path = "res://test-user/missing-folder/currency.cfg"
	check(not GameCurrency.complete_greeting() and not GameCurrency.greeting_completed, "failed persistence rolls back the greeting flag")
	GameCurrency.save_path = original_path
	_finish()


func _finish() -> void:
	print("SATAN_GREETING_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
