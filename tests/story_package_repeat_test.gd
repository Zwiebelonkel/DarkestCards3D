extends "res://tests/weed_reward_test.gd"


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	GameCurrency.reset_progression()
	CollectionManager.collection = {"cards": {}, "instances": []}
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	make_main()
	await settle(0.4)
	GameCurrency.story_completed_level = 6
	GameCurrency.award_story_win(7)
	check(await wait_landed(), "story seven drops the initial package")
	await move_pointer(pointer())
	await click_real()
	weed.clear_effect()
	await settle()
	check(GameCurrency.weed_consumed and not GameCurrency.is_story_package_available("weed"), "use history survives while the pending package is consumed")
	GameCurrency.award_match("loss")
	GameCurrency.award_match("draw")
	await settle()
	check(not weed.model.visible, "losses and draws cannot respawn the package")
	GameCurrency.award_match("win")
	check(await wait_landed(), "a normal victory respawns weed after consumption")
	GameCurrency.load_currency()
	check(GameCurrency.weed_package_pending and GameCurrency.weed_consumed, "pending repeat and prior trip are saved independently")
	GameCurrency.award_story_win(1)
	await settle(0.1)
	check(weed.dropping, "another story victory drops an already staged package anew")
	check(await wait_landed(), "the repeated drop settles")
	var reward := CollectionManager.claim_pump_puzzle_reward([true, false, false, true, false])
	check(not reward.is_empty(), "the pump puzzle can still be solved after repeated victories")
	await settle()
	check(not weed.model.visible and not weed.area.input_ray_pickable, "solving the pump puzzle removes a staged weed package")
	GameCurrency.award_match("win")
	GameCurrency.award_story_win(8)
	await settle(0.2)
	check(not GameCurrency.is_story_package_available("weed") and not weed.model.visible, "normal and story victories cannot drop weed after puzzle completion")
	GameCurrency.load_currency()
	check(not GameCurrency.is_story_package_available("weed"), "the solved gate survives currency reload")
	var wallet := RejectingWallet.new()
	add_child(wallet)
	wallet.story_completed_level = 7
	wallet.weed_reward_unlocked = true
	check(wallet.award_match("win").is_empty() and not wallet.weed_package_pending, "failed victory persistence cannot queue a repeat")
	wallet.free()
	main.queue_free()
	await settle()
	print("STORY_PACKAGE_REPEAT: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
