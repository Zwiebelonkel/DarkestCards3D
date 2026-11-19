extends "res://tests/cocaine_reward_test.gd"

var heard: Array[int] = []
var audio_events: Array[Dictionary] = []


func capture(label: String, target: SubViewport = null) -> void:
	if not render:
		return
	if target == null:
		target = viewport
	await RenderingServer.frame_post_draw
	var snapshot := target.get_texture().get_image()
	var path := "res://test-user/mdma/" + label + ".png"
	check(snapshot.save_png(path) == OK, "capture " + label)
	captures.append(path)
	var luminance_sum := 0.0
	var samples := 0
	for y in range(0, snapshot.get_height(), 16):
		for x in range(0, snapshot.get_width(), 16):
			var color := snapshot.get_pixel(x, y)
			luminance_sum += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			samples += 1
	capture_diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true),
		"camera": str(target.get_camera_3d().global_transform), "mean_luminance": luminance_sum / samples}


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute("res://test-user/mdma")
	GameCurrency.set_process(false)
	GameCurrency.reset_progression()
	CollectionManager.collection = {"cards": {}, "instances": []}
	_test_mdma_transactions()
	GameCurrency.level = 50
	GameCurrency.story_completed_level = 24
	GameCurrency.cocaine_reward_unlocked = true
	GameCurrency.cocaine_package_pending = true
	GameCurrency.save()
	GameCurrency.award_match("win")
	check(not GameCurrency.mdma_reward_unlocked and GameCurrency.get_story_package_kind() == "cocaine",
		"player level fifty and ordinary wins before story 25 do not unlock MDMA")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	make_main()
	check(await wait_landed() and weed.package_kind == "cocaine", "an unclaimed cocaine bag remains available at story 24")
	table._table_state = GameTable.TableState.PLAYING
	table._local_mode = "story"
	table._story_level = 25
	table._last_match_outcome = GameTable.MatchOutcome.WIN
	table._match_reward_granted = false
	table._grant_match_rewards()
	await settle()
	check(GameCurrency.mdma_reward_unlocked and GameCurrency.mdma_package_pending and not weed.dropping,
		"the real story-25 result saves MDMA and waits for the idle hub")
	table._table_state = GameTable.TableState.MENU
	await settle(0.15)
	check(weed.package_kind == "mdma" and weed.dropping and not weed._models["cocaine"].visible
		and not weed._models["weed"].visible and not weed.area.input_ray_pickable,
		"MDMA replaces the previous bag and cannot be clicked during its fall")
	await settle(0.55)
	await capture("drop")
	check(await wait_landed(), "MDMA lands normally")
	var bounds: AABB = weed.mesh.global_transform * weed.mesh.get_aabb()
	var table_mesh := table.get_node("table/Cube") as MeshInstance3D
	var top := (table_mesh.global_transform * table_mesh.get_aabb()).end.y
	check(bounds.position.y >= top and bounds.position.y - top < 0.008, "the supplied MDMA mesh rests on the tabletop")
	await capture("landed")
	await move_pointer(pointer())
	check(weed.hovered and weed.mesh.material_overlay == weed._outline, "MDMA uses the real yellow mouse-hover outline")
	await capture("hover")
	click_signal(MOUSE_BUTTON_RIGHT)
	click_signal(MOUSE_BUTTON_LEFT, false)
	check(not weed.active, "right clicks and releases cannot activate MDMA")
	main.pause_menu.open()
	await settle()
	click_signal()
	check(not weed.active and not weed.area.input_ray_pickable, "pause prevents MDMA pickup")
	main.pause_menu.close()
	var master := AudioServer.get_bus_index("Master")
	var hearing := table._get_or_create_lowpass()
	var sentinel := AudioEffectEQ10.new()
	AudioServer.add_bus_effect(master, sentinel)
	var effects_before := AudioServer.get_bus_effect_count(master)
	var base_pitch: float = main.music.pitch_scale
	var audio: Node3D = weed.mdma_audio
	audio.clue_started.connect(func(index: int, direction: Vector3):
		heard.append(index)
		audio_events.append({"index": index, "direction": str(direction), "seconds": weed._effect_elapsed})
		check(not (audio._voice.playing and audio._separator.playing), "clue recordings never overlap")
		if index < 4:
			check(audio._voice.position.is_equal_approx(direction * 2.0), "voice source matches its listener-relative direction")
	)
	await move_pointer(pointer())
	await click_real()
	check(weed.active and GameCurrency.mdma_consumed and not GameCurrency.mdma_package_pending
		and not weed.model.visible and weed.overlay.visible, "a real picked click saves consumption and starts the overlay")
	check(weed._effect_material.shader.resource_path == "res://assets/shader/mdma.gdshader"
		and not main.get_node("Hint1").visible and not main.get_node("EmptyRoom/hint2").visible,
		"MDMA has its own shader and exclusively uses the spoken hint")
	check(audio.active and audio._crackle.playing and audio._voice is AudioStreamPlayer3D and heard.is_empty(),
		"subtle crackle begins while the positional hint waits for fade-in")
	check(AudioServer.get_bus_effect_count(master) == effects_before + 1
		and AudioServer.get_bus_effect(master, 0) == hearing, "MDMA adds one owned lo-fi filter after the hearing filter")
	await settle(0.7)
	await capture("fade-in")
	await settle(4.5)
	check(heard == [0], "Pablo starts first after the five-second visual fade-in")
	check(is_equal_approx(audio._distortion.drive, 0.1) and is_equal_approx(main.music.pitch_scale, base_pitch * 0.85)
		and is_zero_approx(main.music._mix), "full MDMA adds gentle lo-fi and slows/lowers the original music to 85 percent")
	await capture("active")
	var active_cost := await sample_cost()
	weed.overlay.hide()
	var baseline := await sample_cost()
	weed.overlay.show()
	var pose := main.main_camera.transform
	main.main_camera.rotate_y(0.5)
	audio._process(0.0)
	check(audio.global_transform.is_equal_approx(main.main_camera.global_transform.orthonormalized()),
		"turning the listener preserves the four directions around the player")
	main.main_camera.transform = pose
	main.pause_menu.open()
	await settle()
	var elapsed: float = weed._effect_elapsed
	var position: float = audio._voice.get_playback_position()
	var count := heard.size()
	await settle(0.4)
	check(is_equal_approx(weed._effect_elapsed, elapsed) and heard.size() == count
		and absf(audio._voice.get_playback_position() - position) < 0.08,
		"pause freezes the visual countdown and current voice recording")
	main.pause_menu.close()
	var deadline := Time.get_ticks_msec() + 20000
	while heard.size() < 7 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(heard.slice(0, 7) == [0, 1, 2, 3, 4, 0, 1], "actual playback finishes Pablo, Trinity, Stuart, Hannah, separator, then repeats")
	GameCurrency.load_currency()
	check(GameCurrency.mdma_consumed and not GameCurrency.is_story_package_available("mdma"), "reload preserves the consumed package and separate use history")
	weed._process(weed.effect_duration - weed._effect_elapsed - 2.5)
	check(float(weed._effect_material.get_shader_parameter("effect_mix")) < 1.0 and audio._distortion.drive < 0.1,
		"sound and visual strength share the fade-out")
	await capture("fade-out")
	weed._process(3.0)
	check(not weed.active and not audio.active and not audio._voice.playing and not audio._separator.playing
		and not audio._crackle.playing and audio._delay.is_stopped() and not weed.overlay.visible,
		"expiry stops the visual, every recording, the crackle and future loop callbacks")
	check(AudioServer.get_bus_effect_count(master) == effects_before
		and AudioServer.get_bus_effect(master, effects_before - 1) == sentinel,
		"expiry removes only the MDMA filter and preserves unrelated effects")
	check(is_equal_approx(main.music.pitch_scale, base_pitch) and not main.music._mdma_pitch_active,
		"expiry restores the exact music speed and pitch")
	await capture("expired")
	GameCurrency.award_match("loss")
	GameCurrency.award_match("draw")
	await settle()
	check(not weed.model.visible, "losses and draws cannot queue another MDMA package")
	GameCurrency.award_match("win")
	check(await wait_landed() and weed.package_kind == "mdma", "later victories drop MDMA again after consumption")
	main.pause_menu.settings_menu._refresh_package_button()
	check(main.pause_menu.settings_menu.cheat_weed_button.text == Localization.text("MDMA-Paket fallen lassen"),
		"the shared cheat button identifies MDMA from story 25 onward")
	await move_pointer(pointer())
	await click_real()
	check(audio.active, "repeat pickup starts the audio clue anew")
	GameCurrency.request_admin_weed_drop()
	await settle()
	check(not audio.active and audio._delay.is_stopped() and weed.dropping,
		"an admin replacement cancels the active trip and queued voice callbacks")
	check(await wait_landed() and weed._admin_package and weed.package_kind == "mdma",
		"the admin path drops the selected MDMA model without advancing story progress")
	await move_pointer(pointer())
	await click_real()
	check(audio.active and audio.clue_index == -1, "the admin pickup restarts the hint from Pablo after the fade-in")
	main.queue_free()
	await settle()
	check(AudioServer.get_bus_effect_count(master) == effects_before, "leaving the scene during MDMA restores the audio bus")
	AudioServer.remove_bus_effect(master, effects_before - 1)
	if render:
		await capture_cardinals("mdma")
	var report := {"checks": checks, "failures": failures, "captures": captures, "diagnostics": capture_diagnostics,
		"audio_events": audio_events, "active": active_cost, "baseline": baseline,
		"audio_driver": AudioServer.get_driver_name(), "scene_modified_unix": FileAccess.get_modified_time("res://scenes/props/WeedPickup.tscn")}
	var file := FileAccess.open("res://test-user/mdma/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MDMA_REWARD_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_mdma_transactions() -> void:
	var wallet := RejectingWallet.new()
	add_child(wallet)
	wallet.story_completed_level = 24
	var coins_before := wallet.get_coin_cents()
	check(wallet.award_story_win(25).is_empty() and not wallet.mdma_reward_unlocked and not wallet.mdma_package_pending
		and wallet.story_completed_level == 24 and wallet.get_coin_cents() == coins_before,
		"failed story-25 persistence rolls back progress, package and currency")
	wallet.story_completed_level = 25
	wallet.mdma_reward_unlocked = true
	wallet.mdma_package_pending = true
	check(not wallet.consume_story_package("mdma") and not wallet.mdma_consumed and wallet.mdma_package_pending,
		"failed pickup persistence leaves MDMA available for retry")
	wallet.set_training_session(self, true)
	check(not wallet.consume_story_package("mdma", true), "training blocks MDMA including the admin path")
	wallet.set_training_session(self, false)
	wallet.free()
	var legacy := ConfigFile.new()
	legacy.set_value("story", "completed_level", 25)
	legacy.save("res://test-user/legacy-mdma.cfg")
	wallet = RejectingWallet.new()
	wallet.save_path = "res://test-user/legacy-mdma.cfg"
	add_child(wallet)
	wallet.load_currency()
	check(wallet.mdma_reward_unlocked and wallet.mdma_package_pending and not wallet.mdma_consumed
		and wallet.get_story_package_kind() == "mdma", "older saves past story 25 receive the pending MDMA reward")
	wallet.clear_profile_state()
	check(not wallet.mdma_reward_unlocked and not wallet.mdma_consumed and not wallet.mdma_package_pending,
		"profile reset clears all MDMA state")
	wallet.free()
