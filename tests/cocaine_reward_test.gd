extends "res://tests/weed_reward_test.gd"

var capture_diagnostics: Dictionary = {}


func capture(label: String, target: SubViewport = null) -> void:
	if not render:
		return
	if target == null:
		target = viewport
	await RenderingServer.frame_post_draw
	var path := "res://test-user/cocaine/" + label + ".png"
	var snapshot := target.get_texture().get_image()
	check(snapshot.save_png(path) == OK, "capture " + label)
	var luminance_sum := 0.0
	var nonblack := 0
	var samples := 0
	for y in range(0, snapshot.get_height(), 16):
		for x in range(0, snapshot.get_width(), 16):
			var pixel := snapshot.get_pixel(x, y)
			var luminance := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			luminance_sum += luminance
			nonblack += int(luminance > 0.01)
			samples += 1
	capture_diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true),
		"camera_pose": str(target.get_camera_3d().global_transform),
		"mean_luminance": luminance_sum / samples, "nonblack_ratio": float(nonblack) / samples}
	captures.append(path)


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute("res://test-user/cocaine")
	GameCurrency.reset_progression()
	CollectionManager.collection = {"cards": {}, "instances": []}
	GameCurrency.set_process(false)
	_test_transactions()
	GameCurrency.level = 50
	GameCurrency.story_completed_level = 18
	GameCurrency.weed_consumed = true
	GameCurrency.weed_reward_unlocked = true
	GameCurrency.save()
	GameCurrency.award_match("win")
	check(not GameCurrency.cocaine_reward_unlocked, "player level fifty and an ordinary victory cannot unlock cocaine")
	GameCurrency.award_story_win(19)
	check(not GameCurrency.cocaine_reward_unlocked and GameCurrency.get_story_package_kind() == "weed", "story nineteen still selects the weed reward")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	make_main()
	await settle(0.4)
	var hint := main.get_node("EmptyRoom/hint2") as Sprite3D
	var authored_room := (load("res://scenes/rooms/EmptyHospitalRoom.tscn") as PackedScene).instantiate()
	var authored_hint := authored_room.get_node("hint2") as Sprite3D
	var hint_pose := authored_hint.transform
	var hint_pixel_size := authored_hint.pixel_size
	authored_room.free()
	check(hint.transform.is_equal_approx(hint_pose) and is_equal_approx(hint.pixel_size, hint_pixel_size)
		and not main.has_node("Hint2") and hint.global_position.distance_to(main.get_node("Hint1").global_position) > 10.0,
		"configure retains the existing hospital Hint2 placement and size with no copy next to Hint1")
	check(not weed._models["cocaine"].visible and not main.get_node("EmptyRoom/hint2").visible, "there is no cocaine package or hint before story twenty")
	table._table_state = GameTable.TableState.PLAYING
	table._local_mode = "story"
	table._story_level = 20
	table._last_match_outcome = GameTable.MatchOutcome.WIN
	table._match_reward_granted = false
	table._grant_match_rewards()
	await settle(0.1)
	check(GameCurrency.cocaine_reward_unlocked and GameCurrency.story_completed_level == 20 and not weed.dropping,
		"a saved story-twenty victory queues cocaine until the match exits")
	table._table_state = GameTable.TableState.MENU
	await settle(0.15)
	check(weed.package_kind == "cocaine" and weed.dropping and not weed._models["weed"].visible,
		"the supplied cocaine model falls instead of the weed model")
	check(not weed.area.input_ray_pickable, "a falling cocaine package cannot be clicked")
	await settle(0.45)
	await capture("drop")
	check(await wait_landed(), "the cocaine bag lands and settles")
	var bag_bounds: AABB = weed.mesh.global_transform * weed.mesh.get_aabb()
	var tabletop: MeshInstance3D = table.get_node("table/Cube")
	var top := (tabletop.global_transform * tabletop.get_aabb()).end.y
	check(bag_bounds.position.y >= top and bag_bounds.position.y - top < 0.008,
		"the cocaine mesh rests on the real tabletop without penetration")
	await capture("landed")
	await move_pointer(pointer())
	check(weed.hovered and weed.mesh.material_overlay == weed._outline, "the cocaine bag receives the same yellow hover outline")
	await capture("hover")
	click_signal(MOUSE_BUTTON_RIGHT)
	click_signal(MOUSE_BUTTON_LEFT, false)
	check(not weed.active and not GameCurrency.cocaine_consumed, "right clicks and releases cannot consume cocaine")
	var base_pitch: float = main.music.pitch_scale
	var master := AudioServer.get_bus_index("Master")
	var effects_before := AudioServer.get_bus_effect_count(master)
	await click_real()
	check(weed.active and GameCurrency.cocaine_consumed and not weed.model.visible, "a real picked click saves consumption and removes the package")
	check(main.get_node("EmptyRoom/hint2").visible and not main.get_node("Hint1").visible,
		"only Hint2 is shown during cocaine")
	check(weed._effect_material.shader.resource_path.ends_with("cocaine.gdshader")
		and weed._effect_material.shader != weed.WEED_SHADER, "cocaine uses its own sharp cyan/magenta filter")
	check(weed.effect_duration == 60.0 and weed.fade_in_duration == 5.0 and weed.fade_out_duration == 5.0,
		"the shared sixty-second lifetime retains five-second fades")
	await settle(0.7)
	check(main.music.pitch_scale > base_pitch and main.music.pitch_scale < base_pitch * 1.35,
		"music tempo and pitch gradually increase during fade-in")
	await capture("fade-in")
	weed._process(5.0)
	check(is_equal_approx(main.music.pitch_scale, base_pitch * 1.35) and is_zero_approx(main.music._mix),
		"the original synchronized arrangement plays 35 percent faster and higher at full effect")
	check(weed._high_cut == null and AudioServer.get_bus_effect_count(master) == effects_before,
		"the cocaine sound stays clear and preserves every existing audio bus effect")
	var material := hint.material_override as StandardMaterial3D
	check(hint.hframes == 4 and material.emission_enabled and material.emission_texture != null,
		"Hint2 animates its four authored frames with an emissive map")
	check(hint.transform.is_equal_approx(hint_pose) and is_equal_approx(hint.pixel_size, hint_pixel_size),
		"activating cocaine changes Hint2 visibility without moving or resizing the hospital hint")
	await capture("active")
	var active_cost := await sample_cost()
	await _capture_hospital_hint()
	var elapsed: float = weed._effect_elapsed
	click_signal()
	check(weed._effect_elapsed >= elapsed, "repeated clicks never restart an active cocaine effect")
	main.pause_menu.open()
	await settle()
	var remaining: float = weed.remaining
	await settle(0.15)
	check(is_equal_approx(weed.remaining, remaining), "Pause freezes the cocaine countdown")
	main.pause_menu.close()
	weed._process(weed.remaining - 2.5)
	check(main.music.pitch_scale > base_pitch and main.music.pitch_scale < base_pitch * 1.35
		and hint.modulate.a > 0.0 and hint.modulate.a < 1.0,
		"the final five seconds smoothly return music speed, filter and Hint2 to normal")
	await capture("fade-out")
	weed._process(weed.remaining + 0.1)
	check(not weed.active and not weed.overlay.visible and not hint.visible
		and is_equal_approx(main.music.pitch_scale, base_pitch), "expiry hides the cocaine effect and restores the exact authored music pitch")
	check(hint.transform.is_equal_approx(hint_pose) and is_equal_approx(hint.pixel_size, hint_pixel_size),
		"expiry leaves the original hospital Hint2 pose and size intact")
	check(not main.get_node("Hint1").visible and AudioServer.get_bus_effect_count(master) == effects_before,
		"expiry cannot accidentally reveal Hint1 or change audio effects")
	var baseline := await sample_cost()
	GameCurrency.load_currency()
	check(GameCurrency.cocaine_consumed and GameCurrency.weed_consumed, "both reward histories survive a save reload independently")
	main.queue_free()
	await settle()
	# An old unclaimed weed reward cannot fall after cocaine was consumed.
	GameCurrency.weed_consumed = false
	GameCurrency.save()
	make_main()
	await settle(0.3)
	check(weed.package_kind == "cocaine" and not weed.dropping and not weed.model.visible,
		"re-entering after cocaine consumption never falls back to an unclaimed weed reward")
	check(is_equal_approx(main.music.pitch_scale, base_pitch), "scene re-entry restores normal music and does not resume the trip")
	main.pause_menu.open()
	main.pause_menu._open_settings()
	var settings := main.pause_menu.settings_menu
	settings.cheats_toggle.button_pressed = true
	await settle(0.15)
	(settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer).ensure_control_visible(settings.cheat_weed_button)
	await settle(0.1)
	check(settings.cheat_weed_button.text == Localization.text("Kokain-Paket fallen lassen"), "the shared admin button identifies cocaine after story twenty")
	await capture("admin-menu")
	settings.cheat_weed_button.pressed.emit()
	settings.close()
	main.pause_menu.close()
	check(await wait_landed() and weed.package_kind == "cocaine", "the admin drop uses cocaine at this story milestone even after prior consumption")
	await move_pointer(pointer())
	await click_real()
	check(weed.active and main.get_node("EmptyRoom/hint2").visible, "the repeated admin cocaine pickup uses the real effect and Hint2")
	main.queue_free()
	await settle()
	make_main()
	check(is_equal_approx(main.music.pitch_scale, base_pitch), "leaving during a cocaine trip does not leak its speed into a new scene")
	main.queue_free()
	await settle()
	# Check replacement of a still-unclaimed earlier package in the same scene.
	GameCurrency.reset_progression()
	GameCurrency.story_completed_level = 19
	GameCurrency.weed_reward_unlocked = true
	GameCurrency.weed_package_pending = true
	GameCurrency.save()
	make_main()
	check(await wait_landed() and weed.package_kind == "weed", "an unconsumed story-seven reward still uses weed before story twenty")
	GameCurrency.award_story_win(20)
	await settle(0.15)
	check(weed.package_kind == "cocaine" and weed.dropping and not weed._models["weed"].visible,
		"winning story twenty replaces an unclaimed weed bag instead of leaving two packages")
	check(await wait_landed(), "the replacement cocaine package also settles normally")
	main.queue_free()
	await settle()
	if render:
		await capture_cardinals("cocaine")
	material = null
	var report := {"checks": checks, "failures": failures, "captures": captures,
		"active": active_cost, "baseline": baseline, "audio_driver": AudioServer.get_driver_name(),
		"capture_diagnostics": capture_diagnostics,
		"main_scene_modified_unix": FileAccess.get_modified_time("res://scenes/main/Main.tscn"),
		"hospital_scene_modified_unix": FileAccess.get_modified_time("res://scenes/rooms/EmptyHospitalRoom.tscn")}
	var file := FileAccess.open("res://test-user/cocaine/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COCAINE_REWARD_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _capture_hospital_hint() -> void:
	if not render:
		return
	# Review the existing hint from the real hospital turning anchor and lens.
	# Move only the test camera, never the sprite or its parent room.
	var previous := main.camera_pivot.global_transform
	main.set_process(false)
	main.camera_pivot.global_transform = main.room_camera_anchor.global_transform
	main.camera_pivot.rotate_y(PI)
	await settle(0.1)
	await capture("hint2-hospital")
	main.camera_pivot.global_transform = previous
	main.set_process(true)


func _test_transactions() -> void:
	var wallet := RejectingWallet.new()
	add_child(wallet)
	wallet.story_completed_level = 19
	wallet.weed_consumed = true
	var before := wallet.get_coin_cents()
	check(wallet.award_story_win(20).is_empty() and not wallet.cocaine_reward_unlocked
		and wallet.story_completed_level == 19 and wallet.get_coin_cents() == before,
		"a failed story-twenty save rolls back both the victory and cocaine eligibility")
	wallet.story_completed_level = 20
	wallet.cocaine_reward_unlocked = true
	check(not wallet.consume_story_package("cocaine") and not wallet.cocaine_consumed and wallet.weed_consumed,
		"a failed cocaine consumption save preserves both exact prior histories")
	wallet.free()
	var legacy := ConfigFile.new()
	legacy.set_value("story", "completed_level", 20)
	legacy.save("res://test-user/legacy-cocaine.cfg")
	wallet = RejectingWallet.new()
	wallet.save_path = "res://test-user/legacy-cocaine.cfg"
	add_child(wallet)
	wallet.load_currency()
	check(wallet.cocaine_reward_unlocked and not wallet.cocaine_consumed and wallet.get_story_package_kind() == "cocaine",
		"older saves that already completed story twenty receive an unclaimed cocaine reward")
	wallet.set_training_session(self, true)
	check(not wallet.consume_story_package("cocaine", true), "training cannot activate cocaine even through the admin path")
	wallet.free()
