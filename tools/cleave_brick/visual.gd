extends "res://tools/random_damage_coin/visual.gd"


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	output = "res://docs/validation/cleave-brick"
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
			data["animated"] = false
			data["defense"] = 100
			data["attack"] = 8 if side == "player" else 0
			data["effects"] = [{"type":"cleave", "side_damage":0.5}] if side == "player" and slot == 2 else []
			var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
			deck.append(data)
			table._draw_to_slot(side, slot, false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	var camera := table.table_camera
	var original_camera := camera.global_transform
	var attacker := table._player_slots[2]
	var target := table._enemy_slots[2]
	table._resolve_attack_target_hit(attacker, target, 8, {})
	table._apply_cleave(attacker, 2, "player")
	var bricks := table._cleave_bricks.duplicate()
	for brick in bricks:
		brick.set_process(false)
	for i in range(3):
		await get_tree().physics_frame
	await _capture("context-drop")
	await get_tree().create_timer(0.6).timeout
	for brick in bricks:
		brick.freeze = true
	await _capture("context-landed")
	var center: RigidBody3D = bricks[0]
	var focus := center.global_position
	for entry: Array in [["front", Vector3(0, 0.4, 0.9)], ["back", Vector3(0, 0.4, -0.9)], ["left", Vector3(-0.9, 0.4, 0)], ["right", Vector3(0.9, 0.4, 0)]]:
		camera.global_position = focus + (entry[1] as Vector3)
		camera.look_at(focus)
		await _capture("detail-" + str(entry[0]))
	camera.global_transform = original_camera
	for brick in bricks:
		brick.set_dissolve_progress(0.52)
	await _capture("context-dissolve")
	for brick in bricks:
		brick.set_dissolve_progress(0.0)
	center.freeze = false
	center.kick(camera)
	await get_tree().create_timer(0.13).timeout
	center.freeze = true
	await _capture("context-kick")
	# Compare only the props once the original hit particles/numbers finish.
	await get_tree().create_timer(5.2).timeout
	for brick in bricks:
		brick.hide()
	var before := await _benchmark()
	for brick in bricks:
		brick.show()
	var after := await _benchmark()
	var file := FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"captured_utc": Time.get_datetime_string_from_system(true),
		"scene_modified": FileAccess.get_modified_time("res://scenes/effects/CleaveBrick.tscn"),
		"shots": shots,
		"performance": {"without_bricks": before, "with_three_bricks": after},
		"context": "Real Main scene, normal match camera/lighting; startup blur finished, lamp flicker held at authored base energy. Actual target-hit and Cleave presentation paths; no extra lights.",
		"junctions": {"construction": "not applicable: original single mesh", "table_contact": "physics tested against card-plane collider"},
	}, "  "))
	file.close()
	table._clear_match()
	main.queue_free()
	bricks.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	print("CLEAVE_BRICK_VISUAL: PASS")
	get_tree().quit()
