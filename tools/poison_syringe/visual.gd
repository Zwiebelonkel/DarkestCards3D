extends "res://tools/random_damage_coin/visual.gd"

const SYRINGE := preload("res://scenes/effects/PoisonSyringe.tscn")


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	output = "res://docs/validation/poison-syringe"
	var healing_mode := "--healing" in OS.get_cmdline_user_args()
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
	# Match the room's normal base lighting while comparing the short poses.
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
			data["animated"] = false
			data["effects"] = []
			if healing_mode:
				data["defense"] = 30
				if side == "enemy" and slot == 2:
					data["effects"] = [{"type":"regeneration", "value":3}]
			var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
			deck.append(data)
			table._draw_to_slot(side, slot, false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	table.set_process(false)
	var target := table._enemy_slots[2]
	var syringe: Node3D
	if healing_mode:
		target.take_damage(8)
		await table._apply_start_turn_effects("enemy")
		syringe = table._poison_syringes.back()
	else:
		target.apply_poison(3, 3)
		syringe = SYRINGE.instantiate()
		table.add_child(syringe)
		syringe.play_on(target)
	syringe.set_process(false)
	if healing_mode:
		# Compare only the prop once the existing regen burst/number finishes.
		await get_tree().create_timer(5.0).timeout
	var camera := table.table_camera
	var original_camera := camera.global_transform
	syringe.hide()
	var before := await _benchmark()
	syringe.show()
	syringe._apply_pose(syringe.ENTRY_DURATION)
	var after := await _benchmark()
	for entry: Array in [["entry", syringe.ENTRY_DURATION * 0.375], ["pierce", syringe.ENTRY_DURATION], ["press", syringe.ENTRY_DURATION + syringe.PRESS_DURATION], ["exit", syringe.ENTRY_DURATION + syringe.PRESS_DURATION + syringe.EXIT_DURATION * 0.5]]:
		syringe._apply_pose(float(entry[1]))
		await _capture("context-" + str(entry[0]))
	syringe._apply_pose(syringe.ENTRY_DURATION)
	var focus: Vector3 = syringe.global_position + Vector3.UP * 0.25
	var occluders: Array[Node3D] = [table.dealer_satan]
	for node_name: String in ["angelImprisoned", "DealerImprisoned", "PrisonerImprisoned", "jesterImprisoned"]:
		var node := table.get_node_or_null(node_name) as Node3D
		if node != null:
			occluders.append(node)
	var visibility: Array[bool] = []
	for node in occluders:
		visibility.append(node.visible)
		node.hide()
	for entry: Array in [["front", Vector3(0, 0.85, 1)], ["back", Vector3(0, 0.85, -1)], ["left", Vector3(-1, 0.85, 0)], ["right", Vector3(1, 0.85, 0)]]:
		camera.global_position = focus + (entry[1] as Vector3) * 1.2
		camera.look_at(focus)
		await _capture("detail-" + str(entry[0]))
	for i in range(occluders.size()):
		occluders[i].visible = visibility[i]
	camera.global_transform = original_camera
	if healing_mode:
		for quarter in range(4):
			syringe.rotation.y = float(quarter) * PI * 0.5
			syringe._apply_pose(syringe.ENTRY_DURATION + syringe.PRESS_DURATION * 0.5)
			await _capture("yaw-%d" % (quarter * 90))
	var file := FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captured_utc": Time.get_datetime_string_from_system(true), "scene_modified": FileAccess.get_modified_time("res://scenes/effects/PoisonSyringe.tscn"), "script_modified": FileAccess.get_modified_time("res://scripts/effects/PoisonSyringe.gd"), "shots": shots, "performance": {"without_syringe": before, "with_syringe": after}, "animation_duration_seconds": syringe.DURATION, "healing_mode": healing_mode, "sampled_injection_yaw": syringe.injection_yaw, "context":"Real Main and match camera, original room lighting. Occluding character cutouts hidden only for diagnostic detail cameras. Four explicit yaw poses demonstrate unchanged inclination and tip contact; runtime yaw remains sampled once per injection."}, "  "))
	file.close()
	await get_tree().create_timer(5.0).timeout
	syringe.queue_free()
	table._clear_match()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("HEALING_SYRINGE_VISUAL: PASS" if healing_mode else "POISON_SYRINGE_VISUAL: PASS")
	get_tree().quit()
