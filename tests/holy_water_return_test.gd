extends "res://tests/prisoner_dialogue_test.gd"

var reward_card_id := "holy_water"
var dialogue_node_name := "SatanHolyWaterDialogue"
var seen_flag := "holy_water_return_dialogue_seen"
var outside_area_id := "graveyard"
var outside_room := 2
var expected_return_side := 0
var success_marker := "HOLY_WATER_RETURN_TESTS"


func _claim_return_dialogue() -> bool:
	if reward_card_id == "crucifix":
		return CollectionManager.claim_crucifix_return_dialogue()
	return CollectionManager.claim_holy_water_return_dialogue()


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	CollectionManager.clear_profile_state()
	GameCurrency.reset_progression()
	GameCurrency.set_process(false)
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	GameCurrency._basement_cat_choice = "shot"
	check(not _claim_return_dialogue(), "no scene without the story item")
	CollectionManager.add_card(outside_area_id + "_key")
	CollectionManager.use_access_key(outside_area_id + "_key")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0
	main.room_travel_duration = 0.15
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	viewport.add_child(main)
	await _settle(0.4)
	for step in range(2):
		main._request_turn(1)
		await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(main._active_side == 2, "fixture leaves the hub while facing the collection")
	var entrance: HospitalDoor
	for area in main.progression_areas:
		if area.area_id == outside_area_id:
			entrance = area.door
	main._on_room_door_activated(entrance)
	await _wait_until(func(): return main._active_room == outside_room and not main._room_transition_active)
	CollectionManager.add_card(reward_card_id)
	check(not bool(CollectionManager.collection.metadata.get(seen_flag, false)), "acquisition outside does not start the scene")
	var cards_before := CollectionManager.get_owned_cards().duplicate(true)
	var coins_before := GameCurrency.get_coin_cents()
	var saved_pose: Transform3D = main._hub_return_pivot_transform
	var saved_fov: float = main.main_camera.fov
	main._on_room_door_activated(main.connected_rooms[outside_room].get_node("ReturnDoor"))
	saved_pose = main._hub_return_pivot_transform
	check(await _wait_until(func(): return main.has_node(dialogue_node_name)), "real return opens Satan dialogue after the swing")
	var conversation = main.get_node_or_null(dialogue_node_name)
	if conversation == null:
		get_tree().quit(1)
		return
	check(main._room_transition_active and not main._can_travel_between_rooms() and not main._can_turn(false), "movement stays locked throughout the conversation")
	check(is_equal_approx(main.main_camera.fov, saved_fov * 0.88), "camera zooms in slightly")
	check(main.music.stream_paused, "music is paused during the sequence")
	var table: GameTable = main.scene_pivot.get_node("GameTable")
	var target := table.dealer_satan.global_position + Vector3.UP * table.dealer_satan.pixel_size * 6.0 * table.dealer_satan.global_basis.get_scale().y
	check((-main.main_camera.global_basis.z).dot((target - main.main_camera.global_position).normalized()) > 0.999, "camera points at Satan")
	var original_eye: Vector3 = (saved_pose * main._hub_camera_base_transform).origin
	var moved := original_eye.distance_to(main.main_camera.global_position)
	check(moved > 0.01 and moved <= 0.451 and main.main_camera.global_position.distance_to(target) < original_eye.distance_to(target), "camera approaches Satan's face only a small distance")
	conversation._advance_dialog_text(100.0)
	await _settle(0.35)
	await _capture(reward_card_id + "-return")
	var sentences: Array[String] = conversation._get_story_sentences()
	check(sentences.size() == 4, "the return conversation has four sentences")
	if reward_card_id == "crucifix":
		check(sentences != conversation.SENTENCES, "the Crucifix uses its own dialogue instead of the Holy Water lines")
		check("Auge" not in " ".join(sentences) and "Kreuz" in " ".join(sentences), "the dialogue talks about the cross without mentioning the eye")
	for index in range(4):
		check(table._satan_is_laughing == (index == 3), "Satan laughs only in the fourth dialogue part")
		check(conversation._message == sentences[index], "ordered sentence %d" % (index + 1))
		for locale in Localization.SUPPORTED_LOCALES:
			Localization.set_locale(locale)
			check(conversation._body_label.text == Localization.text(sentences[index]), "live language refresh %s part %d" % [locale, index + 1])
			if locale != "de":
				check(conversation._body_label.text != sentences[index], "translated %s part %d" % [locale, index + 1])
		conversation._advance_dialog_text(100.0)
		conversation.continue_dialog()
	check(await _wait_until(func(): return not main._room_transition_active), "slow return completes and releases movement")
	check(main.camera_pivot.global_position.is_equal_approx(saved_pose.origin) and is_equal_approx(main.main_camera.fov, saved_fov), "normal hub position and lens restored")
	var look := -main.main_camera.global_basis.z
	var inward := main.camera_pivot.global_position - entrance.global_position
	var expected_heading := main._hub_settle_origin_y + deg_to_rad(main.rotation_step_degrees) * expected_return_side
	var expected_look := (main.camera_pivot.get_parent() as Node3D).global_basis * -Basis(Vector3.UP, expected_heading).z
	look.y = 0
	inward.y = 0
	check(look.normalized().dot(expected_look.normalized()) > 0.999 and look.normalized().dot(inward.normalized()) > 0.85 and main._active_side == expected_return_side,
		"the item sequence ends facing away from the arrival door (side %d, expected %d; look %s, inward %s)" % [main._active_side, expected_return_side, look, inward])
	check(posmod(main._settle_step_index, MainScene.SIDE_COUNT) == expected_return_side, "the turn state agrees with the inward-facing view")
	var return_pose := main.camera_pivot.global_transform
	await _settle(0.35)
	check(main.camera_pivot.global_transform.is_equal_approx(return_pose), "idle frames preserve the arrival direction")
	Localization.set_locale("de")
	await _capture(reward_card_id + "-" + outside_area_id + "-return-facing")
	check(not main.music.stream_paused and main.music.playing, "music resumes after the return swing")
	check(not table._satan_is_laughing, "Satan stops laughing after the dialogue")
	check(CollectionManager.get_owned_cards() == cards_before and GameCurrency.get_coin_cents() == coins_before, "the return sequence preserves the item, other cards and money")
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(main._active_side == posmod(expected_return_side + 1, MainScene.SIDE_COUNT), "the next normal turn starts from the arrival side")
	main._request_turn(1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(main._active_side == expected_return_side and main.camera_pivot.global_transform.is_equal_approx(return_pose),
		"turning back restores the arrival direction without a jump")
	CollectionManager.reload_profile()
	check(not _claim_return_dialogue(), "saved one-time flag survives reload")
	main._on_room_door_activated(entrance)
	await _wait_until(func(): return main._active_room == outside_room and not main._room_transition_active)
	main._on_room_door_activated(main.connected_rooms[outside_room].get_node("ReturnDoor"))
	await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active)
	check(not main.has_node(dialogue_node_name), "second return does not replay")
	check(main._active_side == expected_return_side and main.camera_pivot.global_transform.is_equal_approx(return_pose),
		"a return without an item conversation also ends facing away from the door")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	print("%s: %d checks, %d failures" % [success_marker, checks, failures])
	get_tree().quit(1 if failures else 0)
