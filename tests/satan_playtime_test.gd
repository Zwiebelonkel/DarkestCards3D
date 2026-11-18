extends Node

var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS: " if condition else "FAIL: ") + message)


func settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	viewport.push_input(event, true)


func _new_main() -> MainScene:
	var scene := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.greeting_enabled = false
	scene.mouse_tilt_strength = 0.0
	scene.wakeup_blur_duration = 0.01
	scene.room_travel_duration = 0.1
	viewport.add_child(scene)
	return scene


func _run() -> void:
	if not PlaytimeManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run only with isolated saves.")
		get_tree().quit(1)
		return
	Localization.set_locale("de")
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(PlaytimeManager.SAVE_PATH + suffix)
	PlaytimeManager.elapsed_seconds = minf(42.0, PlaytimeManager.LIMIT_SECONDS * 0.1)
	PlaytimeManager.encounter_completed = false
	check(PlaytimeManager.LIMIT_SECONDS > 0.0, "the configured timer threshold is positive, including short test settings")
	check(PlaytimeManager.flush() == OK, "global checkpoint saves successfully")
	var checkpoint := PlaytimeManager.elapsed_seconds
	var reloaded = load("res://scripts/autoload/PlaytimeManager.gd").new()
	add_child(reloaded)
	check(absf(reloaded.elapsed_seconds - checkpoint) < 0.001 and not reloaded.encounter_completed, "a new manager resumes saved time without adding closed-game time")
	reloaded.queue_free()
	await settle()
	var before_pause := PlaytimeManager.elapsed_seconds
	var before_pause_ticks := Time.get_ticks_usec()
	get_tree().paused = true
	while Time.get_ticks_usec() - before_pause_ticks < 120000:
		await get_tree().process_frame
	await get_tree().process_frame
	check(PlaytimeManager.elapsed_seconds > before_pause + 0.05, "global time keeps advancing during pause menus")
	get_tree().paused = false
	check(SaveSlots.select_slot(2) == OK and PlaytimeManager.elapsed_seconds >= before_pause, "switching save slots never resets the global timer")
	GameCurrency.set_process(false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = _new_main()
	var lens := main.main_camera.get_node("CanvasLayer") as CanvasLayer
	var screen := main.main_camera.get_node("CanvasLayer2") as CanvasLayer
	var lens_material := main.dirty_lens.material
	var screen_rect := screen.get_node("ColorRect") as ColorRect
	var screen_material := screen_rect.material
	await settle(0.15)
	check(not is_instance_valid(main._playtime_encounter), "no encounter before expiry")
	main._active_room = 3
	PlaytimeManager.elapsed_seconds = PlaytimeManager.LIMIT_SECONDS
	await settle()
	check(PlaytimeManager.is_encounter_pending() and not is_instance_valid(main._playtime_encounter), "expiry in another room stays pending")
	main._active_room = 0
	main._room_transition_active = true
	await settle()
	check(not is_instance_valid(main._playtime_encounter), "a return camera move finishes before the encounter")
	main._room_transition_active = false
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	table._table_state = GameTable.TableState.PLAYING
	await settle()
	check(not is_instance_valid(main._playtime_encounter), "an ongoing match is never interrupted")
	table._table_state = GameTable.TableState.MENU
	NetworkManager.current_lobby_id = 123
	await settle()
	check(not is_instance_valid(main._playtime_encounter), "an online lobby defers the global pause")
	NetworkManager.current_lobby_id = 0
	NetworkManager.test_persona_name = "Luca [b]42%[/b]"
	# Exercise a non-Satan hub side and preserve its orientation on return.
	main._active_side = 1
	main.camera_pivot.rotation.y = PI * 0.5
	await settle()
	var encounter = main._playtime_encounter
	check(is_instance_valid(encounter) and encounter.active, "returning to the hub starts the pending encounter even on another side")
	if not is_instance_valid(encounter):
		_finish()
		return
	var saved_pose: Transform3D = encounter._saved_pose
	var saved_fov: float = encounter._saved_fov
	check(get_tree().paused and not viewport.physics_object_picking and main.pause_menu._cinematic_locked, "world, picking and pause navigation are locked")
	check(lens.visible and screen.visible and main.dirty_lens.is_visible_in_tree() and screen_rect.is_visible_in_tree(), "camera overlays remain visible during the paused approach")
	check(not encounter._canvas_visibility.has(lens) and not encounter._canvas_visibility.has(screen), "the encounter hides HUD layers without capturing camera filters")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal() and table._journal_input_blocked, "all hub interaction contexts are locked")
	check(table._satan_is_laughing and encounter._laugh_audio._laughing and encounter._laugh_audio.playing, "Satan laughs visibly and audibly during the camera swing")
	check(is_equal_approx(float(table.dealer_satan.get("fps")), GameTable.SATAN_STREAM_LAUGH_FPS) and is_equal_approx(encounter._laugh_audio.pitch_offset_semitones, table._satan_laugh_audio.pitch_offset_semitones + GameTable.SATAN_STREAM_LAUGH_PITCH_OFFSET), "money laughter matches the stream's fast animation and audio pitch")
	var frame := table.dealer_satan.frame
	var animation_advanced := false
	_key(KEY_J)
	_key(KEY_D)
	_key(KEY_ESCAPE)
	for index in range(16):
		await get_tree().process_frame
		animation_advanced = animation_advanced or table.dealer_satan.frame != frame
	check(not main.journal.is_active() and not main.pause_menu.visible and encounter._stage == "approach", "gameplay and dismissal keys cannot interrupt the swing")
	check(animation_advanced and not main.main_camera.global_transform.is_equal_approx(saved_pose), "laugh animation and camera continue while the world is paused")
	encounter._camera_tween.set_speed_scale(30.0)
	await settle(0.2)
	check(encounter._stage == "dialog" and encounter._body_label.text == "Luca [b]42%[/b], Danke für dein Geld, du wirst es nie wiedersehen, fick dich.", "dialogue contains the literal Steam name and exact requested line")
	check(not encounter._body_label.bbcode_enabled, "Steam names cannot inject rich-text markup")
	check(lens.visible and screen.visible and main.dirty_lens.material == lens_material and screen_rect.material == screen_material, "the laughing dialogue preserves active camera overlays and their materials")
	_key(KEY_SPACE)
	await settle()
	check(encounter._text_finished and encounter._laugh_audio._laughing and encounter._laugh_audio.is_processing() and encounter._laugh_audio.can_process() and table._satan_is_laughing, "laughter continues after the complete text is visible")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://test-user/satan-playtime-dialog.png")
	encounter._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(encounter._stage == "dialog" and not PlaytimeManager.encounter_completed, "switching away cannot silently complete the unread encounter")
	_key(KEY_SPACE)
	check(encounter._stage == "return" and encounter._laugh_audio._laughing, "laughter continues throughout the return swing")
	check(lens.visible and screen.visible, "camera overlays remain visible during the return swing")
	encounter._camera_tween.set_speed_scale(30.0)
	await settle(0.2)
	check(not get_tree().paused and not is_instance_valid(main._playtime_encounter) and PlaytimeManager.encounter_completed, "completion unpauses gameplay and records the one-time encounter")
	check(viewport.physics_object_picking and not main.pause_menu._cinematic_locked and not table._journal_input_blocked and not table._satan_is_laughing, "picking, pause, table input and Satan's idle state are restored")
	check(main.main_camera.global_transform.is_equal_approx(saved_pose) and is_equal_approx(main.main_camera.fov, saved_fov), "camera returns exactly to its previous pose and field of view")
	check(lens.visible and screen.visible and main.dirty_lens.material == lens_material and screen_rect.material == screen_material, "camera overlays remain unchanged after the encounter")
	reloaded = load("res://scripts/autoload/PlaytimeManager.gd").new()
	add_child(reloaded)
	check(reloaded.encounter_completed and not reloaded.is_encounter_pending(), "completion survives a new manager and cannot replay after restart")
	reloaded.queue_free()
	main.queue_free()
	await settle()
	main = _new_main()
	await settle()
	check(not is_instance_valid(main._playtime_encounter), "a new hub visit never replays a completed encounter")
	# Interrupted encounters must release the global pause and remain pending.
	main.main_camera.get_node("CanvasLayer").hide()
	PlaytimeManager.encounter_completed = false
	await settle()
	encounter = main._playtime_encounter
	check(is_instance_valid(encounter), "an uncompleted encounter can start again")
	check(not main.main_camera.get_node("CanvasLayer").visible and main.main_camera.get_node("CanvasLayer2").visible, "a hidden lens is preserved without hiding the other camera effect")
	if is_instance_valid(encounter):
		encounter._camera_tween.set_speed_scale(40.0)
		await settle(0.2)
		check(encounter._body_label.text == "Luca [b]42%[/b], Danke für dein Geld, du wirst es nie wiedersehen, fick dich.", "repeat setup preserves the player name")
		main.queue_free()
		await settle()
		check(not get_tree().paused and PlaytimeManager.is_encounter_pending() and viewport.physics_object_picking, "scene teardown restores the pause and leaves an interrupted encounter pending")
	NetworkManager.test_persona_name = ""
	main = _new_main()
	await settle()
	encounter = main._playtime_encounter
	if is_instance_valid(encounter):
		encounter._camera_tween.set_speed_scale(40.0)
		await settle(0.2)
		check(encounter._body_label.text.begins_with("Abschaum, Danke"), "offline mode uses the established name fallback")
		NetworkManager.current_lobby_id = 456
		NetworkManager.lobby_state_changed.emit()
		check(not get_tree().paused and PlaytimeManager.is_encounter_pending(), "an incoming lobby cancels safely without consuming the encounter")
	NetworkManager.current_lobby_id = 0
	main.queue_free()
	await settle()
	PlaytimeManager.complete_encounter()
	check(PlaytimeManager.reset_timer() == OK and PlaytimeManager.elapsed_seconds < 1.0 and not PlaytimeManager.encounter_completed and not PlaytimeManager.is_encounter_pending(), "reset clears elapsed time, completion and pending expiry")
	reloaded = load("res://scripts/autoload/PlaytimeManager.gd").new()
	add_child(reloaded)
	check(reloaded.elapsed_seconds < 1.0 and not reloaded.encounter_completed and not reloaded.is_encounter_pending(), "reset survives reload despite an old completed backup")
	reloaded.queue_free()
	await settle()
	var expiry_count := [0]
	PlaytimeManager.expired.connect(func(): expiry_count[0] += 1)
	PlaytimeManager.elapsed_seconds = PlaytimeManager.LIMIT_SECONDS
	await settle()
	check(expiry_count[0] == 1 and PlaytimeManager.is_encounter_pending(), "reset rearms the expiry signal for the next timer run")
	main = _new_main()
	await settle()
	check(is_instance_valid(main._playtime_encounter), "the Satan encounter can trigger again after a reset")
	check(PlaytimeManager.reset_timer() == OK and not get_tree().paused and not is_instance_valid(main._playtime_encounter), "reset during an active encounter cancels it and restores controls")
	main.queue_free()
	await settle()
	_finish()


func _finish() -> void:
	print("SATAN_PLAYTIME_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
