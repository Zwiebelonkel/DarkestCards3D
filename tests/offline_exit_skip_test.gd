extends Node
## Run only in an isolated project with user:// remapped to res://test-user/.

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var table: GameTable
var finishes := 0
var shots := 0
var reveals := 0
var exit_returns := 0
var balance_after_result: Dictionary = {}
var music_before := -8.25
var master_before := -4.25
var filter_before := 7800.0
var master_bus := -1
var lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	print(("PASS: " if condition else "FAIL: ") + message)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use an isolated project to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	SettingsManager.set_fullscreen(false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	add_child(viewport)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	viewport.add_child(main)
	table = main.get_node("ScenePivot/GameTable") as GameTable
	await _settle(0.7)
	main.set_process(false)
	main.level_progress.set_process(false)
	main.wakeup_blur_duration = 4.0
	master_bus = AudioServer.get_bus_index("Master")
	lowpass = table._get_or_create_lowpass()
	table.loss_exit_finished.connect(func(): finishes += 1)
	table.loss_shot_fired.connect(func(): shots += 1)
	table.loss_reveal_started.connect(func(_duration: float): reveals += 1)
	check(table.has_method("try_skip_offline_exit"), "GameTable exposes the offline cinematic input handler")
	if not table.has_method("try_skip_offline_exit"):
		_finish()
		return
	check(not table.try_skip_offline_exit(_key(KEY_SPACE)), "ordinary menu input cannot skip a nonexistent cinematic")
	await _check_early_win_and_input_filter()
	await _check_turn_key_is_consumed()
	await _check_stage("win gun raise", true, func(): return table.player_gun_mount.visible, _mouse())
	await _check_stage("win Satan absent", true, func(): return not table.dealer_satan.visible, _pad())
	await _check_stage("win Satan return", true, func(): return reveals > 0, _key(KEY_SPACE))
	await _check_stage("loss gun raise", false, func(): return not table.dealer_gun.global_transform.is_equal_approx(table.pistol_start_marker.global_transform), _mouse())
	await _check_stage("loss hearing hold", false, func(): return table._hearing_recovery_active, _pad(), 1.0)
	await _check_stage("loss hearing fade", false, func(): return table._hearing_recovery_active and AudioServer.get_bus_volume_db(master_bus) > -79.0, _key(KEY_SPACE), 3.2)
	await _check_stage("loss wakeup reveal", false, func(): return reveals > 0, _mouse())
	await _check_new_match_during_retired_wait()
	await _check_online_guard(false)
	await _check_online_guard(true)
	main.queue_free()
	await _settle(0.1)
	_finish()


func _configure_timings() -> void:
	table.match_camera_duration = 0.03
	table.loss_player_view_return_duration = 0.06
	table.loss_camera_approach_duration = 0.08
	table.win_gun_raise_duration = 0.16
	table.win_gun_lower_duration = 0.08
	table.pistol_raise_duration = 0.16
	table.pistol_aim_pause = 0.1
	table.win_satan_knockback_duration = 0.14
	table.win_satan_absent_duration = 0.3
	table.win_satan_return_duration = 0.3
	table.win_satan_return_hold = 0.1
	table.loss_camera_return_duration = 0.06
	table.loss_reveal_duration = 0.6


func _begin_result(win: bool, online: bool = false) -> void:
	_configure_timings()
	table._show_main_menu()
	await _settle(0.06)
	table._online_mode = online
	table._online_is_host = false
	table._online_is_spectator = false
	table._reset_online_sync_tracking()
	table._table_state = GameTable.TableState.PLAYING
	table._game_over = false
	table._match_reward_granted = false
	table._last_match_outcome = GameTable.MatchOutcome.NONE
	var surviving_card: Dictionary = CardDatabase.get_combat_cards()[0].duplicate(true)
	if win:
		table._player_deck.append(surviving_card)
	else:
		table._enemy_deck.append(surviving_card)
	check(table._check_game_over(), "the actual match result settles before the exit cinematic")
	balance_after_result = _balance()
	main.music.volume_db = music_before
	AudioServer.set_bus_volume_db(master_bus, master_before)
	lowpass.cutoff_hz = filter_before
	AudioServer.set_bus_effect_enabled(master_bus, 0, false)
	finishes = 0
	shots = 0
	reveals = 0
	exit_returns = 0


func _start_exit() -> void:
	await table._on_exit_button_pressed()
	exit_returns += 1


func _check_early_win_and_input_filter() -> void:
	await _begin_result(true)
	table.loss_camera_approach_duration = 1.0
	_start_exit()
	await get_tree().process_frame
	check(table._loss_exit_running and main._loss_cinematic_active and main.pause_menu._cinematic_locked, "offline win owns the camera and locks pause while running")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(5, 3)
	var released_key := _key(KEY_SPACE)
	released_key.pressed = false
	var echo_key := _key(KEY_SPACE)
	echo_key.echo = true
	var released_mouse := _mouse()
	released_mouse.pressed = false
	var released_pad := _pad()
	released_pad.pressed = false
	var stick := InputEventJoypadMotion.new()
	stick.axis_value = 1.0
	for ignored in [motion, released_key, echo_key, released_mouse, released_pad, stick]:
		check(not table.try_skip_offline_exit(ignored) and table._loss_exit_running, "%s does not accidentally skip" % ignored.as_text())
	viewport.push_input(_key(KEY_ESCAPE), true)
	await get_tree().process_frame
	_check_restored("Escape skips early win")
	check(not main.pause_menu._is_open and not get_tree().paused, "the Escape used to skip cannot also open pause")
	check(not main._is_journal_active(), "the skip returns to gameplay without opening another overlay")
	check(not table.try_skip_offline_exit(_mouse()), "a repeated skip request cannot complete the same sequence twice")
	await _settle(0.35)
	_check_restored("early win stays finished after its old camera wait")
	check(shots == 0 and reveals == 0, "skipping before the shot prevents all later shot and reveal signals")


func _check_stage(label: String, win: bool, predicate: Callable, event: InputEvent, stale_wait: float = 0.45) -> void:
	await _begin_result(win)
	_start_exit()
	var reached := await _wait_until(predicate)
	check(reached and table._loss_exit_running, label + " is reached before natural completion")
	if not reached or not table._loss_exit_running:
		return
	var previous_shots := shots
	var previous_reveals := reveals
	check(table.try_skip_offline_exit(event), label + " accepts a single pressed input")
	await get_tree().process_frame
	_check_restored(label)
	await _settle(stale_wait)
	_check_restored(label + " after retired waits")
	check(shots == previous_shots and reveals == previous_reveals, label + " emits no deferred shot or reveal after skipping")
	check(exit_returns == 1, label + " releases the original exit caller exactly once")


func _check_turn_key_is_consumed() -> void:
	main.set_process(true)
	await _begin_result(true)
	_start_exit()
	await get_tree().process_frame
	var previous_side := main._active_side
	Input.action_press(main.input_action_right)
	viewport.push_input(_key(KEY_D), true)
	await get_tree().process_frame
	main._read_input()
	check(not table._loss_exit_running and main._pending_direction == 0 and main._phase == MainScene.Phase.IDLE, "D skips without polling the same press as a room turn")
	Input.action_release(main.input_action_right)
	await _settle(0.2)
	check(main._active_side == previous_side and main._phase == MainScene.Phase.IDLE, "the turn key used to skip leaves the active camera side unchanged")
	main.set_process(false)
	_check_restored("turn-key skip with active Main processing")


func _check_new_match_during_retired_wait() -> void:
	await _begin_result(false)
	_start_exit()
	check(await _wait_until(func(): return table._hearing_recovery_active), "loss enters the hearing delay before immediate next-match regression")
	check(table.try_skip_offline_exit(_key(KEY_SPACE)), "loss hearing delay can be skipped before starting another match")
	await get_tree().process_frame
	# Model the next result immediately; any continuation from the old hearing
	# delay must neither silence this match nor reset its menu or gun animation.
	await _begin_result(true)
	table.loss_camera_approach_duration = 1.2
	_start_exit()
	await _settle(0.95)
	check(table._loss_exit_running and main._loss_cinematic_active, "a retired loss cannot end the next match's cinematic")
	check(not table._hearing_recovery_active and is_equal_approx(AudioServer.get_bus_volume_db(master_bus), master_before), "the old hearing timer cannot change the next match's audio")
	check(finishes == 0 and exit_returns == 0, "old exit waits cannot issue completion for the next match")
	check(table.try_skip_offline_exit(_pad()), "the next cinematic remains independently skippable")
	await get_tree().process_frame
	_check_restored("second consecutive cinematic")


func _check_online_guard(disconnected: bool) -> void:
	await _begin_result(true, true)
	if disconnected:
		NetworkManager.current_lobby_id = 0
		NetworkManager._connected_peer_ids.clear()
		_start_exit()
	else:
		# The online protocol also calls the same presentation function directly.
		table._play_win_exit_sequence(false)
	await get_tree().process_frame
	check(table._loss_exit_running, "online%s cinematic starts" % (" disconnected fallback" if disconnected else ""))
	check(not table.try_skip_offline_exit(_mouse()) and not table.try_skip_offline_exit(_key(KEY_SPACE)) and not table.try_skip_offline_exit(_pad()), "online%s results reject local skip input" % (" disconnected fallback" if disconnected else ""))
	check(table._loss_exit_running and finishes == 0, "online skip attempts cannot finish the shared result")
	check(await _wait_until(func(): return not table._loss_exit_running, 6000), "online%s presentation still finishes normally" % (" disconnected fallback" if disconnected else ""))
	await _settle(0.12)
	check(finishes == 1 and shots == 1 and reveals == 1, "online completion still plays the complete result exactly once")
	check(_balance() == balance_after_result, "online input does not award the result twice")
	table._online_mode = false


func _check_restored(label: String) -> void:
	check(not table._loss_exit_running and not main._loss_cinematic_active and finishes == 1, label + ": cinematic finishes exactly once by the next frame")
	check(table._table_state == GameTable.TableState.MENU and table.mode_buttons.visible and not table.end_buttons.visible, label + ": normal mode menu is restored")
	check(table.table_camera.global_transform.is_equal_approx(table._camera_base_transform) and is_equal_approx(table.table_camera.fov, table._camera_base_fov), label + ": player camera position, orientation and field of view are restored")
	check(not table.player_gun_mount.visible and not table.player_muzzle_flash.visible and not table.flash_sprite.visible and table.dealer_gun.global_transform.is_equal_approx(table.pistol_start_marker.global_transform), label + ": both gun presentations and flashes reset")
	check(table.dealer_satan.visible and table.satan_motion_root.transform.is_equal_approx(table._satan_motion_base_transform) and table.dealer_satan.modulate.is_equal_approx(table._satan_base_modulate) and not table._satan_is_dying and not table._satan_is_laughing, label + ": Satan is restored to his normal visible pose")
	check(table._black_rect == null or not table._black_rect.visible, label + ": no black overlay blocks the screen")
	check(not table._hearing_recovery_active and is_equal_approx(AudioServer.get_bus_volume_db(master_bus), master_before) and is_equal_approx(lowpass.cutoff_hz, filter_before) and not AudioServer.is_bus_effect_enabled(master_bus, 0), label + ": original hearing volume, filter frequency and enabled state return")
	check(is_equal_approx(main.music.volume_db, music_before) and not main._loss_music_restore_pending, label + ": background music returns to its original volume")
	check(is_equal_approx(float(main._wakeup_blur_material.get_shader_parameter("blur_strength")), MainScene.WAKEUP_BLUR_END), label + ": wakeup blur cannot linger after the skip")
	check(not main.pause_menu._cinematic_locked and table.satan_hover_area.input_ray_pickable, label + ": pause and scene interactions are available again")
	check(_balance() == balance_after_result, label + ": settled coins, level and XP remain unchanged")


func _balance() -> Dictionary:
	return {"coins": GameCurrency.coins, "level": GameCurrency.level, "xp": GameCurrency.xp}


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _mouse() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(640, 360)
	event.pressed = true
	return event


func _pad() -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	return event


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 9000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _finish() -> void:
	print("OFFLINE_EXIT_SKIP_TESTS: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
