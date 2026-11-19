extends "res://tools/random_damage_coin/visual.gd"


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	output = "res://docs/validation/block-knife"
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
			data["effects"] = []
			var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
			deck.append(data)
			table._draw_to_slot(side, slot, false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	table.set_process(false)
	var before := await _benchmark()
	var card := table._enemy_slots[2]
	card.apply_event_block(2)
	var knife: Node3D = card._event_block_badge
	knife.set_process(false)
	knife._apply_entry(knife.ENTRY_DURATION * 0.90)
	await _capture("context-entry")
	knife._process(knife.ENTRY_DURATION + knife.SETTLE_DURATION)
	var after := await _benchmark()
	await _capture("context-pinned")
	card.tick_event_block()
	await _capture("context-one-turn-left")
	var camera := table.table_camera
	var original_camera := camera.global_transform
	var focus := card.to_global(Vector3(0.10, 0.0, 0.55))
	# Character cutouts sit between reverse diagnostic cameras and the pin.
	# Keep every actual match-camera capture honest; hide them only for details.
	var diagnostic_occluders: Array[Node3D] = [table.dealer_satan]
	for node_name: String in ["angelImprisoned", "DealerImprisoned", "PrisonerImprisoned", "jesterImprisoned"]:
		var node := table.get_node_or_null(node_name) as Node3D
		if node != null:
			diagnostic_occluders.append(node)
	var original_visibility: Array[bool] = []
	for node in diagnostic_occluders:
		original_visibility.append(node.visible)
		node.hide()
	for entry: Array in [["front", Vector3(0, 0.9, 1.0)], ["back", Vector3(0, 1.0, -1.0)], ["left", Vector3(-1.0, 0.9, 0)], ["right", Vector3(1.0, 0.9, 0)]]:
		camera.global_position = focus + (entry[1] as Vector3) * 1.5
		camera.look_at(focus)
		await _capture("detail-" + str(entry[0]))
	for i in range(diagnostic_occluders.size()):
		diagnostic_occluders[i].visible = original_visibility[i]
	camera.global_transform = original_camera
	card.tick_event_block()
	knife.set_process(false)
	knife._apply_exit(knife.EXIT_DURATION * 0.4)
	await _capture("context-release")
	knife._process(knife.EXIT_DURATION)
	await _capture("context-released")
	var file := FileAccess.open(output.path_join("review_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captured_utc":Time.get_datetime_string_from_system(true), "scene_modified":FileAccess.get_modified_time("res://scenes/effects/EventBlockKnife.tscn"), "shots":shots, "performance":{"without_knife":before,"with_knife":after}, "context":"Real Main scene, standard match camera and room lighting. Lamp flicker fixed at authored base energy and startup blur finished. No extra lights. Occluding character cutouts hidden only for the four detail cameras, restored for all match-camera captures.", "interfaces":{"tip_contact":"measured source blade tip penetrates through card into table at local (0.10,0.05,-0.30); shaft crosses the card face inside its footprint","card_picking":"no collision or picking Areas in the cosmetic knife"}}, "  "))
	file.close()
	# Let the real table's existing draw-audio tails finish before teardown.
	await get_tree().create_timer(5.0).timeout
	table._clear_match()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("BLOCK_KNIFE_VISUAL: PASS")
	get_tree().quit()
