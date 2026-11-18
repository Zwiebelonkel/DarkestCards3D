extends "res://tests/npc_rescue_intro_test.gd"

const PRESENTATION := preload("res://scripts/main/ImprisonedNPCPresentation.gd")
var win_shots := 0


func _ready_for(npc_id: String) -> bool:
	return main.imprisoned_npcs.states[npc_id] == PRESENTATION.State.PRESENT


func _key(card_id: String) -> void:
	main._on_access_key_requested(card_id)
	check(await wait_until(func(): return not main._room_transition_active), card_id + " completes its actual door-key animation")


func _start_exit() -> void:
	table._on_exit_button_pressed()
	check(await wait_until(func(): return table._loss_exit_running), "actual victory exit starts")


func _skip() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	check(table.try_skip_offline_exit(event), "victory skip is accepted")
	check(await wait_until(func(): return not table._loss_exit_running), "skipped exit completes")
	await settle(0.04)


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use isolated saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	SaveSlots.select_slot(1)
	SaveSlots.reset_slot(1)
	GameCurrency.greeting_completed = true
	GameCurrency.save()
	Localization.set_locale("de")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.05
	main.settle_duration = 0.04
	main.door_key_look_duration = 0.12
	main.imprisoned_reveal_duration = 0.9
	main.imprisoned_departure_duration = 0.9
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	table.loss_player_view_return_duration = 0.12
	table.loss_camera_approach_duration = 0.22
	table.win_gun_raise_duration = 0.22
	table.pistol_aim_pause = 0.12
	table.win_gun_lower_duration = 0.12
	table.win_satan_knockback_duration = 0.16
	table.win_satan_absent_duration = 1.15
	table.win_satan_return_duration = 0.22
	table.win_satan_return_hold = 0.12
	table.win_shot_fired.connect(func(): win_shots += 1)
	var presentation := main.imprisoned_npcs
	var angel := presentation.actors["angel"] as Sprite3D
	var dealer := presentation.actors["dealer"] as Sprite3D
	var jester := presentation.actors["jester"] as Sprite3D
	var prisoner := presentation.actors["prisoner"] as Sprite3D
	check(not angel.visible and not dealer.visible and not jester.visible and not prisoner.visible, "all four table copies start hidden before the first facing update")
	await settle(0.23)
	check(presentation.states["angel"] == PRESENTATION.State.ENTERING and angel.visible and angel.transparency > 0.0 and angel.transparency < 1.0, "first Angel rises with partial opacity")
	check(angel.position.y < (presentation.origins["angel"] as Vector3).y, "arrival begins below the authored position")
	await capture("prisoners-angel-arriving")
	check(await wait_until(func(): return _ready_for("angel")), "Angel arrival settles")
	check(angel.position.is_equal_approx(presentation.origins["angel"]) and angel.transparency == 0.0, "arrival restores the exact authored position and full opacity")
	var original_basis := angel.basis
	await _turn_to(2)
	for card_id in ["graveyard_key", "black_market_access"]:
		CollectionManager.add_card_instance(CardData.create_instance(card_id))
	check(not dealer.visible and not jester.visible, "finding keys does not reveal anyone")
	await _key("graveyard_key")
	check(not jester.visible and not prisoner.visible, "Graveyard key only queues Jester while looking at the door")
	await _key("black_market_access")
	check(not dealer.visible and not jester.visible, "both newly queued prisoners stay hidden at the key doors")
	for repeat in range(3):
		main._refresh_npc_rescue_state()
	await settle(0.2)
	check(not dealer.visible and not jester.visible, "collection refreshes cannot bypass the delayed entrance")
	await _turn_to(2)
	await _turn_to(0)
	check(await wait_until(func(): return presentation.states["dealer"] == PRESENTATION.State.ENTERING), "turning back toward Satan triggers the queued entrances")
	await settle(0.3)
	check(dealer.transparency > 0.0 and dealer.transparency < 1.0 and jester.transparency > 0.0 and jester.transparency < 1.0, "Dealer and Jester fade in gradually")
	check(dealer.position.y < (presentation.origins["dealer"] as Vector3).y and jester.position.y < (presentation.origins["jester"] as Vector3).y, "both prisoners rise from below")
	await capture("prisoners-keys-arriving")
	check(await wait_until(func(): return _ready_for("dealer") and _ready_for("jester")), "key prisoners finish their entrance")
	check(angel.basis.is_equal_approx(original_basis), "animations preserve authored orientation and scale")
	var normal_angel := main.get_node("ScenePivot/Collection/angel") as Sprite3D
	var normal_dealer := main.get_node("BlackMarketRoom/Kiosk/Dealer") as Sprite3D
	var normal_jester := main.get_node("GraveyardRoom/jester") as Sprite3D
	var normal_prisoner := main.get_node("GraveyardRoom/Crypt/Prisoner") as Sprite3D
	story_win(1)
	check(GameCurrency.is_npc_rescued("angel") and GameCurrency.is_npc_rescued("dealer") and GameCurrency.is_npc_rescued("jester"), "Story victory durably commits the rescues")
	check(angel.visible and dealer.visible and jester.visible and angel.transparency == 0.0 and dealer.transparency == 0.0, "winning does not remove or fade the prisoners")
	await settle(0.18)
	check(not normal_angel.visible and not normal_dealer.visible and not normal_jester.visible, "normal locations wait until the rescue departure")
	check(not prisoner.visible, "successor Prisoner does not pop in at the victory result")
	await _start_exit()
	check(win_shots == 0 and angel.visible and dealer.visible and jester.visible, "all rescued prisoners stay through the pre-shot victory sequence")
	await capture("prisoners-before-shot")
	check(await wait_until(func(): return win_shots == 1), "the actual Satan shot emits the departure cue")
	check(presentation.states["angel"] == PRESENTATION.State.DEPARTING and angel.visible and dealer.visible and jester.visible, "shot starts departures without instantly hiding anyone")
	await settle(0.3)
	check(angel.position.x < (presentation.origins["angel"] as Vector3).x and jester.position.x < (presentation.origins["jester"] as Vector3).x, "left-side Angel and Jester leave to the left")
	check(dealer.position.x > (presentation.origins["dealer"] as Vector3).x, "right-side Dealer leaves to the right")
	check(angel.transparency > 0.0 and angel.transparency < 1.0 and dealer.transparency > 0.0 and dealer.transparency < 1.0, "departure combines sideways movement and a gradual fade")
	await capture("prisoners-leaving-after-shot")
	check(await wait_until(func(): return presentation.held_for_shot.is_empty()), "side departures complete")
	check(not angel.visible and not dealer.visible and not jester.visible, "departed table copies stay hidden")
	check(normal_angel.visible and normal_dealer.visible and normal_jester.visible, "rescued NPCs appear at their normal stations after departure")
	check(not prisoner.visible and main._loss_cinematic_active, "successor waits until the victory camera is finished")
	check(await wait_until(func(): return not table._loss_exit_running), "full unskipped victory finishes")
	check(await wait_until(func(): return presentation.states["prisoner"] == PRESENTATION.State.ENTERING), "Prisoner then makes his own shadow entrance")
	await capture("prisoners-successor-arriving")
	check(await wait_until(func(): return _ready_for("prisoner")), "Prisoner arrival settles")
	check(not normal_prisoner.visible and not GameCurrency.is_npc_rescued("prisoner"), "Jester's victory does not release the Prisoner too")
	table.loss_shot_fired.emit()
	await settle(0.06)
	check(_ready_for("prisoner") and prisoner.visible, "a loss-shot cue cannot dismiss a waiting Prisoner")
	story_win(2)
	check(prisoner.visible and not normal_prisoner.visible, "Prisoner also stays at his own victory result")
	await _start_exit()
	await _skip()
	check(win_shots == 1 and not prisoner.visible and normal_prisoner.visible and presentation.held_for_shot.is_empty(), "skip before the shot finalizes rescue without ghosts or extra shots")
	# Reset while this same Main is loaded, then skip a departure in flight.
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	GameCurrency.reset_progression()
	check(await wait_until(func(): return _ready_for("angel")), "profile reset restarts only the fresh Angel entrance")
	check(not dealer.visible and not jester.visible and not prisoner.visible, "reset clears previous keys and departing actors")
	story_win(1)
	await _start_exit()
	check(await wait_until(func(): return win_shots == 2), "second real victory reaches its shot")
	check(presentation.states["angel"] == PRESENTATION.State.DEPARTING, "second departure is in flight before skip")
	await _skip()
	check(not angel.visible and normal_angel.visible and presentation.held_for_shot.is_empty() and presentation._tweens.is_empty(), "skip during departure cleans up every actor tween")
	GameCurrency.load_currency()
	check(not angel.visible and normal_angel.visible and GameCurrency.is_npc_rescued("angel"), "saved rescue reload cannot resurrect the table copy")
	main.queue_free()
	await settle()
	viewport.queue_free()
	await settle(0.2)
	print("NPC_PRISONER_ANIMATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
