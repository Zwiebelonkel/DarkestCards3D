extends Node3D

var checks := 0
var failures := 0
var main: MainScene
var table: GameTable
var viewport: SubViewport


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func wait_until(predicate: Callable, timeout_ms: int = 7000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://" + file_name + ".png")


func imprisoned(npc: String) -> bool:
	var paths := {"angel": "angelImprisoned", "dealer": "DealerImprisoned", "jester": "jesterImprisoned", "prisoner": "PrisonerImprisoned"}
	return table.get_node(paths[npc]).visible


func story_win(level: int) -> void:
	table._table_state = GameTable.TableState.GAME_OVER
	table._local_mode = "story"
	table._story_level = level
	table._last_match_outcome = GameTable.MatchOutcome.WIN
	table._match_reward_granted = false
	table._grant_match_rewards()


func finish_story_exit() -> void:
	table._on_exit_button_pressed()
	await wait_until(func(): return table._loss_exit_running)
	var skip := InputEventKey.new()
	skip.keycode = KEY_SPACE
	skip.pressed = true
	table.try_skip_offline_exit(skip)
	await wait_until(func(): return not table._loss_exit_running)
	await settle(0.08)


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/") or not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use an isolated project with redirected saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.reset_progression()
	GameCurrency.greeting_completed = true
	GameCurrency.save()
	Localization.set_locale("de")
	CollectionManager.add_card_instance(CardData.create_instance("corpse"))
	CollectionManager.add_card_instance(CardData.create_instance("toilet_paper"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	await settle()
	var machine := main.scene_pivot.get_node("UpgradeMachine") as UpgradeMachine
	var angel := main.scene_pivot.get_node("Collection/angel") as Sprite3D
	var dealer := main.get_node("BlackMarketRoom/Kiosk/Dealer") as Sprite3D
	var jester := main.get_node("GraveyardRoom/jester") as Sprite3D
	var prisoner := main.get_node("GraveyardRoom/Crypt/Prisoner") as Sprite3D
	check(imprisoned("angel") and not imprisoned("dealer") and not imprisoned("jester") and not imprisoned("prisoner"), "fresh profile shows only imprisoned Angel")
	check(not angel.visible and not dealer.visible and not jester.visible and not prisoner.visible, "all normal NPC locations start empty")
	check(not machine.is_operational() and not machine.ui.visible and machine.upgrade_viewport.gui_disable_input, "upgrade machine UI and input are locked")
	var material := machine.screen_mesh.get_surface_override_material(0) as StandardMaterial3D
	check(material.albedo_texture == null and material.albedo_color == Color.BLACK and not material.emission_enabled, "locked monitor is plain black")
	machine.selected_card_id = "corpse"
	var coins := GameCurrency.coins
	machine._upgrade_attack()
	machine._upgrade_health()
	machine._roll_effect()
	check(GameCurrency.coins == coins and CardUpgradeManager.get_attack_bonus("corpse") == 0, "direct upgrade callbacks cannot spend or upgrade while locked")
	check(not main._jester_context_is_safe() and not main._dealer_context_is_safe() and not main._prisoner_context_is_safe(), "NPC contexts stay locked")
	check(not CollectionManager.offer_jester_card("chick", "missing").get("ok", false), "Jester offering backend is locked")
	check(CollectionManager.exchange_prisoner_toilet_paper().is_empty() and CollectionManager.get_amount("toilet_paper") == 1, "locked Prisoner cannot consume a trade item")
	check(not main.black_market_board._content.visible and main.black_market_board._title.text == "GESCHLOSSEN", "Dealer shop shows its closed sign")
	await capture("npc-rescue-first-round")
	main._settle_step_index = 3
	main._active_side = 3
	main._snap_camera_pivot_to_cardinal_target()
	await settle()
	await capture("npc-rescue-machine-locked")
	main._settle_step_index = 0
	main._active_side = 0
	main._snap_camera_pivot_to_cardinal_target()
	GameCurrency.set_training_session(self, true)
	check(GameCurrency.award_story_win(1).is_empty() and not GameCurrency.is_npc_rescued("angel"), "training cannot rescue NPCs")
	GameCurrency.set_training_session(self, false)
	GameCurrency.award_match("win", "normal")
	check(not GameCurrency.is_npc_rescued("angel"), "ordinary wins do not advance Story rescues")
	# Opt in because the deliberately failed write emits an expected error.
	if OS.get_cmdline_user_args().has("--failed-save"):
		var save_path := GameCurrency._save_path_override
		GameCurrency._save_path_override = "res://test-user/missing-directory/currency.cfg"
		check(GameCurrency.award_story_win(1).is_empty() and not GameCurrency.is_npc_rescued("angel") and not GameCurrency.angel_rescue_intro_pending, "failed Story save rolls rescue state back")
		GameCurrency._save_path_override = save_path
	story_win(1)
	check(table._match_reward_granted and imprisoned("angel") and not angel.visible, "first Story result keeps Angel imprisoned until the shot")
	check(machine.is_operational() and machine.ui.visible and not machine.upgrade_viewport.gui_disable_input, "Angel rescue enables machine immediately")
	await settle()
	check(not main._npc_rescue_intro_active and GameCurrency.angel_rescue_intro_pending, "Angel camera waits for the first station visit")
	# Exercise the real skipped victory exit as well as the one-time dialog.
	table._on_exit_button_pressed()
	check(await wait_until(func(): return table._loss_exit_running), "victory cinematic starts")
	if not OS.get_cmdline_user_args().has("--full-victory"):
		var skip := InputEventKey.new()
		skip.keycode = KEY_SPACE
		skip.pressed = true
		check(table.try_skip_offline_exit(skip), "victory skip is accepted")
	check(await wait_until(func(): return not table._loss_exit_running, 30000), "victory exit finishes")
	await settle()
	check(not main._npc_rescue_intro_active and GameCurrency.angel_rescue_intro_pending, "returning to the table does not trigger the Angel greeting")
	for step in range(2):
		main._request_turn(-1)
		await wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	check(await wait_until(func(): return main.get_node_or_null("NPCRescueDialogue") != null), "first collection visit opens Angel greeting")
	var dialogue := main.get_node_or_null("NPCRescueDialogue") as AngelDialogue
	if dialogue != null:
		check(main._active_side == 2 and not main._can_turn(false) and not main._can_travel_between_rooms(), "Angel introduction faces collection and locks movement")
		check(dialogue._message.contains("Du hast mich befreit") and dialogue._message.contains("Upgrade-Maschine freigeschaltet"), "rescue dialog gives upgrade instructions")
		dialogue.continue_dialog()
		await settle(0.7)
		await capture("npc-rescue-angel-dialog")
		dialogue.continue_dialog()
	check(await wait_until(func(): return not main._npc_rescue_intro_active), "closing Angel dialog returns the camera and restores control")
	check(not GameCurrency.angel_rescue_intro_pending and main._active_side == 2, "introduction completes once and keeps a normal collection view")
	GameCurrency.load_currency()
	check(GameCurrency.is_npc_rescued("angel") and not GameCurrency.angel_rescue_intro_pending, "Angel rescue and completed introduction survive reload")
	CollectionManager.add_card_instance(CardData.create_instance("black_market_access"))
	CollectionManager.add_card_instance(CardData.create_instance("graveyard_key"))
	check(not imprisoned("dealer") and not imprisoned("jester"), "finding keys alone does not spawn prisoners")
	check(CollectionManager.use_access_key("graveyard_key"), "Graveyard key activates")
	check(not imprisoned("jester") and not imprisoned("prisoner") and not jester.visible and not prisoner.visible and GameCurrency.get_imprisoned_npc_ids().has("jester"), "Graveyard activation queues Jester without an immediate appearance")
	check(CollectionManager.use_access_key("black_market_access"), "Black Market key activates")
	check(not imprisoned("dealer") and not dealer.visible and GameCurrency.get_imprisoned_npc_ids().has("dealer"), "Black Market activation queues Dealer without an immediate appearance")
	var offer := CollectionManager.get_black_market_offers()
	check(not CollectionManager.purchase_black_market_offer(str(offer["day"]), str(offer["offers"][0]["offer_id"])).get("ok", false), "activated key alone cannot bypass Dealer purchase lock")
	GameCurrency.award_match("loss", "normal")
	check(GameCurrency.get_imprisoned_npc_ids().has("dealer") and GameCurrency.get_imprisoned_npc_ids().has("jester"), "loss leaves prisoners waiting")
	GameCurrency.load_currency()
	CollectionManager.load_collection()
	main._refresh_npc_rescue_state()
	check(not imprisoned("dealer") and not imprisoned("jester"), "reloading does not reveal prisoners while facing collection")
	for step in range(2):
		main._request_turn(-1)
		await wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	await wait_until(func(): return imprisoned("dealer") and imprisoned("jester"))
	story_win(2)
	await finish_story_exit()
	check(dealer.visible and jester.visible and not imprisoned("dealer") and not imprisoned("jester"), "next Story victory frees Dealer and Jester")
	check(GameCurrency.get_imprisoned_npc_ids().has("prisoner") and not prisoner.visible and not GameCurrency.is_npc_rescued("prisoner"), "Jester victory queues Prisoner without freeing him")
	check(main.black_market_board._content.visible, "freed Dealer opens shop offers")
	GameCurrency.coins = 10000.0
	offer = CollectionManager.get_black_market_offers()
	check(CollectionManager.purchase_black_market_offer(str(offer["day"]), str(offer["offers"][0]["offer_id"])).get("ok", false), "freed Dealer permits a real purchase")
	var sacrifice := CollectionManager.add_card_instance(CardData.create_instance("chick"))
	check(CollectionManager.offer_jester_card("chick", str(sacrifice.get("instance_id", ""))).get("ok", false), "freed Jester permits a real sacrifice")
	main._active_room = 4
	main._active_side = main.black_market_board.view_side
	check(main._dealer_context_is_safe(), "freed Dealer can be approached")
	main._active_room = 2
	main._active_side = main.graveyard_jester.view_side
	check(main._jester_context_is_safe(), "freed Jester can be approached")
	main._active_room = 0
	main._active_side = 0
	story_win(3)
	await finish_story_exit()
	check(prisoner.visible and not imprisoned("prisoner") and GameCurrency.is_npc_rescued("prisoner"), "following Story victory frees Prisoner")
	check(not GameCurrency.angel_rescue_intro_pending, "later Story wins do not repeat Angel introduction")
	main._active_room = 2
	main._crypt_gate_close = true
	check(main._prisoner_context_is_safe(), "freed Prisoner can be approached")
	check(not CollectionManager.exchange_prisoner_toilet_paper().is_empty(), "freed Prisoner permits the real item exchange")
	main._active_room = 0
	main._crypt_gate_close = false
	GameCurrency.load_currency()
	check(GameCurrency.get_imprisoned_npc_ids().is_empty() and GameCurrency.RESCUE_NPC_IDS.all(func(id): return GameCurrency.is_npc_rescued(id)), "all four rescues persist")
	main.queue_free()
	await settle()
	check(SaveSlots.select_slot(2) == OK and not GameCurrency.is_npc_rescued("angel") and not GameCurrency.is_npc_rescued("prisoner"), "another save slot starts without inherited rescues")
	check(SaveSlots.select_slot(1) == OK and GameCurrency.RESCUE_NPC_IDS.all(func(id): return GameCurrency.is_npc_rescued(id)), "returning to the original slot restores all rescued NPCs")
	GameCurrency.reset_progression()
	check(not GameCurrency.is_npc_rescued("angel") and not GameCurrency.angel_rescue_intro_pending, "fresh/reset profile discards previous rescue progress")
	print("NPC_RESCUE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
