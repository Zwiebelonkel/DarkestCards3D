extends Node

var failures := 0
var output := "res://docs/validation/event-switch"


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match fixture for visual validation.")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	AudioServer.set_bus_mute(0, true)
	get_tree().root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	for side: String in ["player", "enemy"]:
		var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
		for index in range(13):
			var data := CardDatabase.get_card("corpse").duplicate(true)
			data["instance_id"] = "switch-visual-%s-%d" % [side, index]
			data["animated"] = false
			data["effects"] = []
			deck.append(data)
		for slot in range(5):
			table._draw_to_slot(side, slot, false)
		table._rebuild_stack_visual(side)
	table._initialize_event_deck()
	var event: Dictionary = {}
	for candidate in table._event_deck:
		if candidate["id"] == "switch":
			event = candidate
			break
	table._event_deck.erase(event)
	table._player_event_hand.append(event)
	table._refresh_event_hand()
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.85).timeout
	await _capture("01-before")
	check(table._try_play_event("player", event["uid"]), "Switch plays in the real match scene")
	var tween := table._event_switch_tween
	tween.pause()
	var near := table._get_stack_top_position("player")
	var far := table._get_stack_top_position("enemy")
	var flying := table._event_switch_cards.duplicate()
	for step in range(1, 5):
		tween.custom_step(table.SWITCH_EXCHANGE_DURATION * 0.249)
		check(flying[0].is_stack_decoration and flying[1].is_stack_decoration and not flying[0].area.input_ray_pickable, "Flying Switch cards stay face-down and cannot intercept table clicks")
		if step == 2:
			check(flying[0].global_position.distance_to(flying[1].global_position) > 1.0, "The two passing cards have distinct visible lanes")
			for card: Card3D in flying:
				var screen := table.table_camera.unproject_position(card.global_position)
				check(Rect2(35, 35, 1210, 650).has_point(screen), "The flying card stays in view of the original match camera")
		await _capture("0%d-flight" % (step + 1))
	check(flying[0].global_position.distance_to(far) < 0.03 and flying[1].global_position.distance_to(near) < 0.03, "Each card finishes on the opposite pile at its original scale")
	tween.custom_step(0.02)
	await get_tree().process_frame
	check(table._event_switch_cards.is_empty() and table._player_stack_visuals.size() == 8 and table._enemy_stack_visuals.size() == 8, "Landing cleans up the effect and preserves both eight-card piles")
	await _capture("06-landed")
	table._play_switch_exchange()
	var cancelled := table._event_switch_cards.duplicate()
	table._clear_match()
	await get_tree().process_frame
	check(table._event_switch_cards.is_empty() and table._event_switch_tween == null and not is_instance_valid(cancelled[0]) and not is_instance_valid(cancelled[1]), "Leaving mid-flight removes both temporary cards and stops their tween")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("EVENT_SWITCH_VISUAL_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
