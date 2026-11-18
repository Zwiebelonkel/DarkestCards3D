extends Node3D

const MAIN_SCENE := preload("res://scenes/main/Main.tscn")
const LENS_PATH := NodePath("CameraPivot/CameraTilt/Camera3D/CanvasLayer/DirtyLensRect")
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _blur(main: MainScene) -> float:
	return float(main.dirty_lens.material.get_shader_parameter("blur_strength"))


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/") or not DeckManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	var config := ConfigFile.new()
	config.set_value("settings", "fullscreen", false)
	config.set_value("settings", "frame_limit", 144)
	config.save(SettingsManager.CONFIG_PATH)
	var settings := preload("res://scripts/autoload/SettingsManager.gd").new()
	check(settings.fullscreen and settings.DEFAULT_FULLSCREEN, "fresh settings start fullscreen by default")
	add_child(settings)
	check(not settings.fullscreen and settings.frame_limit == 144, "ordinary startup preserves saved windowed mode and other preferences")
	settings.reset_to_defaults(false)
	config.load(SettingsManager.CONFIG_PATH)
	check(settings.fullscreen and config.get_value("settings", "fullscreen") == false, "nonpersistent reset uses fullscreen without changing the saved preference")
	settings.reset_to_defaults()
	config.load(SettingsManager.CONFIG_PATH)
	check(config.get_value("settings", "fullscreen") == true, "normal reset persists fullscreen as the default")
	settings.fullscreen = false
	settings.load_settings()
	check(settings.fullscreen, "saved fullscreen default survives reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.CONFIG_PATH))
	settings.queue_free()
	var fresh := preload("res://scripts/autoload/SettingsManager.gd").new()
	add_child(fresh)
	check(fresh.fullscreen, "a profile without a settings file boots fullscreen")
	fresh.queue_free()
	SettingsManager.fullscreen = false
	SettingsManager.apply_settings()

	var main := MAIN_SCENE.instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	var shared_lens := (main.get_node(LENS_PATH) as ColorRect).material as ShaderMaterial
	check(is_equal_approx(float(shared_lens.get_shader_parameter("blur_strength")), 0.265), "the saved scene retains its normal lens blur")
	add_child(main)
	check(_blur(main) == 5.0 and main.wakeup_blur_duration > 0.0, "Main initializes exact blur 5 before its first rendered frame")
	check(main.dirty_lens.material != shared_lens, "startup animation uses an instance-local material")
	check(not main.blood_overlay.active, "ordinary startup blur does not trigger the blood border")
	if DisplayServer.get_name() != "headless":
		await _capture("start")
	await get_tree().create_timer(main.wakeup_blur_duration * 0.5).timeout
	var midpoint := _blur(main)
	check(midpoint > 1.8 and midpoint < 3.4, "blur eases gradually through an intermediate value halfway through waking")
	get_tree().paused = true
	await get_tree().create_timer(0.2, true).timeout
	check(is_equal_approx(_blur(main), midpoint), "offline pause holds the wake animation at its current blur")
	get_tree().paused = false
	await main._wakeup_blur_tween.finished
	check(is_equal_approx(_blur(main), 0.265), "wake animation finishes at exact requested normal blur")
	check(is_equal_approx(float(shared_lens.get_shader_parameter("blur_strength")), 0.265), "finishing never mutates the shared material")
	if DisplayServer.get_name() != "headless":
		await _capture("settled")
	await _check_death_wakeup(main)
	var second := MAIN_SCENE.instantiate() as MainScene
	add_child(second)
	check(_blur(second) == 5.0 and is_equal_approx(_blur(main), 0.265), "a fresh scene entry restarts at 5 without changing an existing instance")
	check(second.dirty_lens.material != main.dirty_lens.material, "simultaneous scene instances keep independent lens materials")
	var pending_tween := second._wakeup_blur_tween
	second.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not pending_tween.is_valid(), "leaving during wake safely kills the bound tween")
	print("STARTUP_SETTINGS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_death_wakeup(main: MainScene) -> void:
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	var local_material := main.dirty_lens.material
	# Run the real death/blackout/reveal path, shortening only the lead-in camera
	# and gun movement. Hearing recovery, reveal and wake blur keep their timing.
	table.loss_player_view_return_duration = 0.01
	table.loss_camera_approach_duration = 0.01
	table.loss_camera_return_duration = 0.01
	table.pistol_raise_duration = 0.01
	table.pistol_aim_pause = 0.01
	table._play_loss_exit_sequence()
	await table.player_wakeup_started
	var started_at := Time.get_ticks_msec()
	var death_wakeup_duration := maxf(main.wakeup_blur_duration * 0.5, 0.01)
	check(_blur(main) == 5.0, "actual death reveal resets blur to 5 synchronously")
	check(table._black_rect.visible and table._black_rect.modulate.a == 1.0, "death blur is primed before the black screen starts revealing the room")
	check(main.blood_overlay.active and main.blood_overlay.blood_rect.visible,
		"actual death wake starts the blood border with the reveal")
	check(main.dirty_lens.material == local_material, "death wake reuses the isolated lens material")
	await get_tree().create_timer(death_wakeup_duration * 0.5).timeout
	check(_blur(main) > 1.8 and _blur(main) < 3.4, "death blur reaches its halfway value midway through its configured duration")
	if DisplayServer.get_name() != "headless":
		await _capture("death-midpoint")
	await main._wakeup_blur_tween.finished
	var elapsed := (Time.get_ticks_msec() - started_at) / 1000.0
	check(elapsed >= death_wakeup_duration - 0.15 and elapsed < death_wakeup_duration + 0.35 and is_equal_approx(_blur(main), 0.265), "death wake reaches exact normal blur after half the configured startup duration")
	# The lens and the blackout have independent authored durations. A shorter
	# lens tween does not mean the entire loss presentation has already ended.
	var cinematic_deadline := Time.get_ticks_msec() + int((table.loss_reveal_duration + 1.0) * 1000.0)
	while table._loss_exit_running and Time.get_ticks_msec() < cinematic_deadline:
		await get_tree().process_frame
	check(not table._loss_exit_running and not table._black_rect.visible, "loss cinematic completes normally after its own reveal duration")
	var settled_tween := main._wakeup_blur_tween
	main.blood_overlay.clear()
	table.loss_reveal_started.emit(0.1)
	check(main._wakeup_blur_tween == settled_tween and is_equal_approx(_blur(main), 0.265), "shared win/music reveal does not trigger a player death blur")
	check(not main.blood_overlay.active, "shared win/music reveal does not trigger a blood border")
	# A second wake can interrupt either the startup or another death tween.
	main._start_wakeup_blur()
	var interrupted_tween := main._wakeup_blur_tween
	table.player_wakeup_started.emit()
	check(not interrupted_tween.is_running() and _blur(main) == 5.0, "death wake cancels an ongoing startup blur before restarting")
	await get_tree().create_timer(0.15).timeout
	interrupted_tween = main._wakeup_blur_tween
	table.player_wakeup_started.emit()
	check(not interrupted_tween.is_running() and _blur(main) == 5.0, "repeated death wake replaces the previous tween without overlap")
	check(main.dirty_lens.material == local_material, "repeated death wake retains the same instance-local lens")
	await main._wakeup_blur_tween.finished
	check(is_equal_approx(_blur(main), 0.265), "repeated death wake settles back to the exact normal value")


func _capture(stage: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://wakeup-%s.png" % stage) == OK, "wakeup %s render saved" % stage)
