extends "res://tests/npc_rescue_test.gd"

const DIALOGUE := preload("res://scripts/main/NPCRescueDialogue.gd")


func _spawn_main() -> void:
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.room_travel_duration = 0.12
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-80, -80)
	viewport.push_input(motion, true)
	await settle()


func _turn_to(side: int) -> void:
	while main._active_side != side:
		check(main._request_turn(-1), "station turn is accepted")
		await wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	await settle(0.03)


func _enter(area_id: String) -> void:
	for area in main.progression_areas:
		if area.area_id == area_id:
			main._on_room_door_activated(area.door)
			break
	check(await wait_until(func(): return not main._room_transition_active or main._npc_rescue_intro_active), "door travel reaches station room")


func _finish_intro(npc_id: String, actor: Sprite3D, normal_camera: Transform3D) -> void:
	check(await wait_until(func(): return main._npc_rescue_intro_active), npc_id + " starts automatically at its station")
	check(main._npc_rescue_intro_id == npc_id, "the greeting belongs to " + npc_id)
	var rig := main.camera_pivot.global_transform
	var tilt := main.camera_tilt.transform
	var side := main._active_side
	var room := main._active_room
	var actor_pose := actor.transform
	check(GameCurrency.is_npc_rescue_intro_pending(npc_id), "introduction stays pending during approach")
	check(not main._can_turn(false) and not main._can_travel_between_rooms() and not main._can_open_journal(), "approach blocks navigation and journal")
	check(not main.level_progress._enabled and not main.access_key_tray._enabled, "progress and key controls are suspended")
	check(await wait_until(func(): return main.get_node_or_null("NPCRescueDialogue") != null), "dialog waits for the face approach")
	var dialogue := main.get_node_or_null("NPCRescueDialogue") as AngelDialogue
	if dialogue == null:
		return
	check(dialogue.get("npc_id") == npc_id and dialogue._message == DIALOGUE.GREETINGS[npc_id], "NPC-specific scripted greeting is selected")
	check(is_equal_approx(dialogue.voice_pitch_offset, DIALOGUE.VOICE_PITCHES[npc_id]), "greeting keeps the NPC's usual voice")
	check(main.main_camera.fov <= 44.01, "camera narrows its lens for the face")
	var face := main._npc_rescue_face_position(actor)
	var projected := main.main_camera.unproject_position(face)
	check(projected.distance_to(Vector2(viewport.size) * 0.5) < 45.0, "the face is centered in the camera")
	check(main.camera_pivot.global_transform.is_equal_approx(rig) and main.camera_tilt.transform.is_equal_approx(tilt), "camera move leaves room/turn rig untouched")
	if npc_id != "jester":
		check(actor.transform.is_equal_approx(actor_pose), "face approach preserves authored sprite pose")
	else:
		check(actor.transform.basis.is_equal_approx(actor_pose.basis), "Jester keeps his authored orientation and scale")
	check(not main._try_start_npc_rescue_intro(), "another introduction cannot overlap")
	if npc_id == "jester":
		var word_sound := dialogue.get_node("SentenceEndSound") as AudioStreamPlayer3D
		dialogue._advance_dialog_text(0.4)
		check(word_sound.playing and dialogue._is_typing(), "Jester cue plays at completed words while the welcome is still typing")
		word_sound.stop()
		dialogue._advance_dialog_text(0.25)
		check(word_sound.playing and dialogue._is_typing(), "the next completed word triggers the Jester cue again")
	dialogue.continue_dialog()
	if npc_id == "jester":
		var ending := dialogue.get_node("SentenceEndSound") as AudioStreamPlayer3D
		check(ending.playing and ending.stream == main.graveyard_jester._sentence_end_audio.stream, "Jester welcome plays the iconic sentence-end sample after revealing text")
		check(ending.bus == &"SFX" and is_equal_approx(ending.volume_db, main.graveyard_jester._sentence_end_audio.volume_db) and not dialogue._laugh_audio.playing, "welcome ending matches station audio settings and replaces the voice")
	else:
		check(dialogue.get_node_or_null("SentenceEndSound") == null, "other NPC welcomes do not gain the Jester sound")
	await settle(0.28)
	await capture("npc-intro-" + npc_id)
	dialogue.continue_dialog()
	if npc_id == "jester":
		check(not (dialogue.get_node("SentenceEndSound") as AudioStreamPlayer3D).playing, "closing the welcome stops the sentence-end sound")
	check(await wait_until(func(): return main.get_node_or_null("NPCRescueDialogue") == null), "dialog closes before camera returns")
	check(main._npc_rescue_intro_active and GameCurrency.is_npc_rescue_intro_pending(npc_id), "return flight stays locked and completion is not saved early")
	check(await wait_until(func(): return not main._npc_rescue_intro_active), "camera returns and releases navigation")
	check(main.main_camera.transform.is_equal_approx(normal_camera) and is_equal_approx(main.main_camera.fov, main._hub_camera_base_fov), "exact station lens and FOV are restored")
	check(main.camera_pivot.global_transform.is_equal_approx(rig) and main._active_side == side and main._active_room == room, "return keeps the station and cardinal heading")
	check(not GameCurrency.is_npc_rescue_intro_pending(npc_id), "completed greeting is saved for " + npc_id)
	GameCurrency.load_currency()
	check(not GameCurrency.is_npc_rescue_intro_pending(npc_id), "completed greeting stays completed after reload")
	await settle(0.1)
	check(not main._npc_rescue_intro_active, "staying at the station never repeats the greeting")


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/") or not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use isolated saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	SaveSlots.select_slot(1)
	SaveSlots.reset_slot(1)
	SaveSlots.reset_slot(2)
	GameCurrency.greeting_completed = true
	GameCurrency.save()
	Localization.set_locale("de")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	await _spawn_main()
	check(not main._npc_rescue_intro_active and not GameCurrency.is_npc_rescue_intro_pending("angel"), "unfreed NPCs have no station introduction")
	GameCurrency.award_story_win(1)
	await settle()
	check(GameCurrency.is_npc_rescue_intro_pending("angel") and not main._npc_rescue_intro_active, "Angel waits for collection instead of playing at the table")
	# Pending greetings survive reloading before the first station visit.
	GameCurrency.load_currency()
	check(GameCurrency.is_npc_rescue_intro_pending("angel"), "unvisited Angel greeting survives reload")
	await _turn_to(2)
	await _finish_intro("angel", main.get_node("ScenePivot/Collection/angel"), main._hub_camera_base_transform)
	await _turn_to(3)
	await _turn_to(2)
	check(not main._npc_rescue_intro_active, "returning to collection does not repeat the Angel greeting")
	for key_id in ["graveyard_key", "black_market_access"]:
		CollectionManager.add_card_instance(CardData.create_instance(key_id))
		CollectionManager.use_access_key(key_id)
	GameCurrency.award_story_win(2)
	check(GameCurrency.is_npc_rescue_intro_pending("dealer") and GameCurrency.is_npc_rescue_intro_pending("jester") and not GameCurrency.is_npc_rescue_intro_pending("prisoner"), "each newly freed NPC receives an independent pending greeting")
	await _enter("black_market")
	await _finish_intro("dealer", main.get_node("BlackMarketRoom/Kiosk/Dealer"), main._hub_camera_base_transform)
	main._on_room_door_activated(main.get_node("BlackMarketRoom/ReturnDoor"))
	await wait_until(func(): return not main._room_transition_active)
	await _enter("graveyard")
	check(not main._npc_rescue_intro_active and GameCurrency.is_npc_rescue_intro_pending("jester"), "graveyard entrance alone is not the Jester station")
	await _turn_to(main.graveyard_jester.view_side)
	await _finish_intro("jester", main.get_node("GraveyardRoom/jester"), main._hub_camera_base_transform)
	main._on_room_door_activated(main.get_node("GraveyardRoom/ReturnDoor"))
	await wait_until(func(): return not main._room_transition_active)
	GameCurrency.award_story_win(3)
	check(GameCurrency.is_npc_rescue_intro_pending("prisoner"), "Prisoner greeting is queued only after his own rescue")
	await _enter("graveyard")
	check(not main._npc_rescue_intro_active, "distant crypt view does not start the Prisoner greeting")
	main._travel_to_crypt_gate(true)
	await wait_until(func(): return main._crypt_gate_close and (not main._room_transition_active or main._npc_rescue_intro_active))
	await _finish_intro("prisoner", main.get_node("GraveyardRoom/Crypt/Prisoner"), main._crypt_camera_base_transform)
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		for message: String in DIALOGUE.GREETINGS.values():
			check(not Localization.text(message).is_empty() and (locale == "de" or Localization.text(message) != message), "greeting is translated in " + locale)
	Localization.set_locale("de")
	GameCurrency.award_story_win(1)
	check(GameCurrency.RESCUE_NPC_IDS.all(func(id): return not GameCurrency.is_npc_rescue_intro_pending(id)), "replaying a Story win never queues completed greetings")
	main.queue_free()
	await settle()
	SaveSlots.select_slot(2)
	GameCurrency.award_story_win(1)
	await _spawn_main()
	await _turn_to(2)
	check(await wait_until(func(): return main._npc_rescue_intro_active), "fresh slot gets its own Angel introduction")
	main.queue_free()
	await settle()
	GameCurrency.load_currency()
	check(GameCurrency.is_npc_rescue_intro_pending("angel"), "interrupting the approach preserves the pending greeting")
	SaveSlots.select_slot(1)
	check(GameCurrency.RESCUE_NPC_IDS.all(func(id): return not GameCurrency.is_npc_rescue_intro_pending(id)), "original save slot retains all four completed greetings")
	viewport.queue_free()
	viewport = null
	await settle(0.3)
	print("NPC_RESCUE_INTRO_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
