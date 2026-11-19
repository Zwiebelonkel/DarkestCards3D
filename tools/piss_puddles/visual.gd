extends "res://tools/random_damage_coin/visual.gd"


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	output = "res://docs/validation/piss-puddles"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	for node in main.find_children("*", "Node3D", true, false):
		if node is StreetLanternFlicker:
			node.flicker_enabled = false
			if is_instance_valid(node.light) and not node.is_shot_out:
				node.light.light_energy = node.base_energy
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table._table_state = GameTable.TableState.PLAYING
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	for side: String in ["player", "enemy"]:
		for slot in range(5):
			var data := CardDatabase.get_card("corpse").duplicate(true)
			data["instance_id"] = "puddle-%s-%d" % [side, slot]
			data["animated"] = false
			data["attack"] = 12 + slot
			data["defense"] = 80 + slot
			data["effects"] = []
			var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
			deck.append(data)
			table._draw_to_slot(side, slot, false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	table.set_process(false)
	await _capture("normal-values")
	var before := await _benchmark()
	table._piss_hidden_turns["player"] = 2
	table._refresh_piss_visibility()
	await _capture("covered-values")
	var after := await _benchmark()
	var card := table._player_slots[2]
	var camera := table.table_camera
	var original_camera := camera.global_transform
	var focus := card.to_global(Vector3(0, -0.38, 0.045))
	camera.global_position = focus + Vector3(0, 0.65, 0.42)
	camera.look_at(focus)
	await _capture("covered-detail")
	card.take_damage(17)
	card.heal(5)
	await _capture("covered-after-hp-change")
	table._piss_hidden_turns["player"] = 0
	table._refresh_piss_visibility()
	await _capture("restored-detail")
	camera.global_transform = original_camera
	await _capture("restored-values")
	var file := FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captured_utc":Time.get_datetime_string_from_system(true),"script_modified":FileAccess.get_modified_time("res://scripts/card/CardStatPuddles.gd"),"shader_modified":FileAccess.get_modified_time("res://assets/shader/card_stat_puddle.gdshader"),"shots":shots,"performance":{"normal_labels":before,"yellow_puddles":after},"context":"Real Main, ordinary match camera and lighting. Lamp flicker fixed to authored energy and startup blur finished. The production viewer-concealment path covers both rows; HP changes under the puddles remain concealed."}, "  "))
	file.close()
	await get_tree().create_timer(5.0).timeout
	table._clear_match()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PISS_PUDDLE_VISUAL: PASS")
	get_tree().quit()
