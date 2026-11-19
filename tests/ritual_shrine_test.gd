extends "res://tests/grave_vault_test.gd"

class RitualCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save

var shrine: Node3D

func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://test-user/ritual")
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	GameCurrency.set_process(false)
	_test_ritual_backend()
	CollectionManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	CollectionManager.add_card("graveyard_key")
	CollectionManager.use_access_key("graveyard_key")
	for card_id: String in CollectionManager.RITUAL_CARD_IDS:
		CollectionManager.add_card(card_id)
	GameCurrency._basement_cat_choice = "shot"
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	await _arrive_at_ritual()
	check(shrine.scene_file_path == "res://scenes/props/RitualShrine.tscn" and hall.scene_file_path == "res://scenes/rooms/UndergroundVault.tscn", "shrine and underground hall remain independent saved scenes")
	check(shrine.seated_cards.is_empty() and not shrine.shotgun.visible, "ownership alone never seats cards or drops the shotgun")
	check(viewport.get_visible_rect().has_point(main.main_camera.unproject_position(shrine.focus_area.global_position)), "the ritual shrine is directly in front of the arriving player")
	await _capture("approach")
	var before := await _sample_cost()
	await _hover_shrine()
	check(main.screen_camera_focus._focused_screen == shrine.focus_area and main.screen_camera_focus._camera_tween == null, "real shrine hover swings the shared camera to its authored focus marker")
	check(shrine.available_cards.size() == 3 and shrine.hand.visible, "the focused shrine presents the three owned story cards for manual dragging")
	await _capture("three-empty-sockets")
	_move_pointer(main.main_camera.unproject_position((shrine.available_cards["holy_water"] as Node3D).global_position))
	await _settle(0.35)
	check(main.screen_camera_focus._focused_screen == shrine.focus_area and shrine.hand.visible, "hovering the available card hand keeps the altar camera steady before dragging")
	await _begin_card("holy_water")
	check(shrine.dragging_id == "holy_water" and not main._can_turn() and not main._can_travel_between_rooms(), "real mouse press grabs a story card and locks turns and room exits")
	_move_pointer(Vector2(1230, 40))
	await _settle()
	_send_button(Vector2(1230, 40), false)
	await _settle()
	check(not shrine.is_busy() and shrine.seated_cards.is_empty(), "releasing outside the shrine returns the card without recording a socket")
	await _hover_shrine()
	await _begin_card("holy_water")
	main.pause_menu.open()
	await _settle(0.12)
	check(shrine.dragging_id.is_empty() and shrine.seated_cards.is_empty() and not shrine._gun_hovered, "Pause cancels a held card without placing it or leaving a hover outline")
	_send_button(Vector2(1230, 40), false)
	main.pause_menu.close()
	await _settle(0.3)
	await _hover_shrine()
	await _drag_to("holy_water", 1)
	check(str(CollectionManager.get_vault_ritual_state().slots[1]) == "holy_water" and shrine.seated_cards.size() == 1, "a manually released card snaps into the selected free socket")
	check(not shrine.shotgun.visible, "one occupied socket cannot spawn the shotgun")
	await _capture("first-card-seated")
	await _drag_to("crucifix", 1)
	check(shrine.seated_cards.size() == 1 and shrine.available_cards.has("crucifix"), "dropping on an occupied socket returns the new card without replacing the seated one")
	await _drag_to("crucifix", 0)
	check(shrine.seated_cards.size() == 2 and not shrine.shotgun.visible, "two sockets still leave the reward locked")
	await _capture("two-cards-seated")
	await _drag_to("silver_bullet", 2, false)
	check(await _wait_until(func(): return shrine.dropping), "only the third manually seated card starts the shotgun drop")
	check(shrine.shotgun.position.y > shrine._gun_rest.origin.y and not main._can_turn() and not shrine._gun_hovered, "the shotgun falls from above while repeat input is blocked")
	await _settle(shrine.drop_duration * 0.87)
	await _capture("shotgun-falling")
	check(await _wait_until(func(): return not shrine.is_busy()), "the falling shotgun lands and settles onto the shrine")
	check(shrine.seated_cards.size() == 3 and shrine.available_cards.is_empty() and shrine.shotgun.visible, "all cards remain snapped in while the landed reward is available")
	await _capture("shotgun-landed")
	main.queue_free()
	await _settle()
	CollectionManager.reload_profile()
	await _arrive_at_ritual()
	check(shrine.seated_cards.size() == 3 and shrine.shotgun.visible and not shrine.dropping, "reloading a completed ritual restores the uncollected shotgun without replaying its fall")
	await _hover_shrine()
	var gun_point := main.main_camera.unproject_position(shrine.shotgun_area.global_position)
	_move_pointer(gun_point)
	await _settle()
	check(shrine._gun_hovered, "the actual shotgun gains a yellow outline under the mouse")
	await _capture("shotgun-hover")
	main.pause_menu.open()
	await _settle()
	await _click_at(gun_point)
	check(not CollectionManager.get_vault_ritual_state().shotgun_collected and not shrine._gun_hovered, "Pause blocks shotgun collection and removes its outline")
	main.pause_menu.close()
	await _settle(0.3)
	await _hover_shrine()
	gun_point = main.main_camera.unproject_position(shrine.shotgun_area.global_position)
	await _click_at(gun_point)
	check(await _wait_until(func(): return not shrine.collecting), "a real click finishes collecting the shotgun")
	check(CollectionManager.get_vault_ritual_state().shotgun_collected and not shrine.shotgun.visible, "shotgun ownership is saved before the world reward disappears")
	check(CollectionManager.get_amount("holy_water") == 1 and CollectionManager.get_amount("crucifix") == 1 and CollectionManager.get_amount("silver_bullet") == 1, "placing story cards preserves their unique collection mementos")
	await _capture("shotgun-collected")
	var after := await _sample_cost()
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	check(not main.screen_camera_focus.is_focused() and main.main_camera.position.is_equal_approx(main.screen_camera_focus._base_position), "leaving the shrine restores the normal room camera")
	await _turn_to(2)
	await _click_at(main.main_camera.unproject_position(hall.exit_area.global_position))
	check(await _wait_until(func(): return main._active_room == 2 and not main._room_transition_active), "the completed shrine does not obstruct the normal return stair")
	main.queue_free()
	await _settle()
	CollectionManager.reload_profile()
	await _arrive_at_ritual()
	check(shrine.seated_cards.size() == 3 and not shrine.shotgun.visible and CollectionManager.get_vault_ritual_state().shotgun_collected, "reloading collected progress never respawns or duplicates the shotgun")
	main.queue_free()
	await _settle()
	CollectionManager.clear_profile_state()
	await _capture_shrine_views()
	var report := {"checks": checks, "failures": failures, "captures": captures, "diagnostics": diagnostics, "before": before, "after": after, "audio_driver": AudioServer.get_driver_name(), "scene_modified_unix": FileAccess.get_modified_time("res://scenes/props/RitualShrine.tscn")}
	var file := FileAccess.open("res://test-user/ritual/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RITUAL_SHRINE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _arrive_at_ritual() -> void:
	_make_vault_main()
	_move_pointer(Vector2(10, 10))
	await _settle(0.3)
	await _travel_to(2)
	main._enter_underground_vault()
	check(await _wait_until(func(): return main._active_room == 5 and not main._room_transition_active), "fixture reaches the vault with the real shared camera journey")
	shrine = hall.get_node("RitualShrine")
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)

func _hover_shrine() -> void:
	_move_pointer(Vector2(10, 10))
	await _settle(0.4)
	_move_pointer(main.main_camera.unproject_position(shrine.focus_area.global_position))
	await _settle(0.6)

func _begin_card(card_id: String) -> void:
	var card: Node3D = shrine.available_cards.get(card_id)
	if card == null:
		check(false, "missing available ritual card " + card_id)
		return
	var point := main.main_camera.unproject_position(card.global_position)
	_move_pointer(point)
	await _settle(0.04)
	_send_button(point, true)
	await _settle(0.06)

func _drag_to(card_id: String, index: int, wait_for_finish: bool = true) -> void:
	await _begin_card(card_id)
	var anchor := shrine.sockets.get_child(index).get_node("CardAnchor") as Marker3D
	var point := main.main_camera.unproject_position(anchor.global_position)
	_move_pointer(point)
	await _settle(0.1)
	_send_button(point, false)
	await _settle(0.04)
	if wait_for_finish:
		await _wait_until(func(): return not shrine.is_busy())

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var snapshot := viewport.get_texture().get_image()
	var path := "res://test-user/ritual/" + label + ".png"
	check(snapshot.save_png(path) == OK, "capture " + label)
	captures.append(path)
	diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true), "camera": str(main.main_camera.global_transform)}

func _capture_shrine_views() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var display := SubViewport.new()
	display.size = Vector2i(1000, 750)
	display.own_world_3d = true
	display.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(display)
	var prop := (load("res://scenes/props/RitualShrine.tscn") as PackedScene).instantiate() as Node3D
	display.add_child(prop)
	var camera := Camera3D.new()
	camera.fov = 50
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0.018, 0.023, 0.021)
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.ambient_light_color = Color(0.68, 0.72, 0.66)
	camera.environment.ambient_light_energy = 0.7
	display.add_child(camera)
	var light := OmniLight3D.new()
	light.position = Vector3(2, 5, 3)
	light.omni_range = 14
	light.light_energy = 3
	display.add_child(light)
	var views := {
		"asset-front": [Vector3(0, 3, 8), Vector3(0, 1, 0)],
		"asset-back": [Vector3(0, 3, -8), Vector3(0, 1, 0)],
		"asset-left": [Vector3(-8, 3, 0), Vector3(0, 1, 0)],
		"asset-right": [Vector3(8, 3, 0), Vector3(0, 1, 0)],
		"asset-three-quarter": [Vector3(5, 4.5, 6), Vector3(0, 1, 0)],
		"socket-closeup": [Vector3(1.8, 2.8, 2.5), Vector3(0, 1.25, 0)],
		"support-closeup": [Vector3(-3, 1.25, 3), Vector3(0, 0.7, 0)],
		"shotgun-closeup": [Vector3(2.6, 3.6, 3.6), Vector3(0, 1.4, -1.08)],
	}
	for label: String in views:
		prop.shotgun.visible = label == "shotgun-closeup"
		camera.position = views[label][0]
		camera.look_at(views[label][1])
		await _settle(0.08)
		await RenderingServer.frame_post_draw
		var snapshot := display.get_texture().get_image()
		var path := "res://test-user/ritual/" + label + ".png"
		check(snapshot.save_png(path) == OK, "capture " + label)
		captures.append(path)
		diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true), "camera": str(camera.global_transform)}
	display.queue_free()
	await _settle()

func _test_ritual_backend() -> void:
	var manager := RitualCollection.new()
	add_child(manager)
	check(not manager.claim_vault_ritual_shotgun(), "an empty ritual cannot grant a shotgun")
	check(not manager.place_vault_ritual_card("holy_water", 0), "unowned cards cannot be placed")
	for card_id: String in CollectionManager.RITUAL_CARD_IDS:
		manager.add_card(card_id)
	check(not manager.place_vault_ritual_card("chick", 0) and not manager.place_vault_ritual_card("holy_water", 3), "non-story cards and invalid sockets are rejected")
	GameCurrency.set_training_session(self, true)
	check(not manager.place_vault_ritual_card("holy_water", 0), "training cannot save ritual progress")
	GameCurrency.set_training_session(self, false)
	manager.reject_save = true
	var previous := manager.collection.duplicate(true)
	check(not manager.place_vault_ritual_card("holy_water", 1) and manager.collection == previous, "a failed placement save leaves all progress and cards unchanged")
	manager.reject_save = false
	check(manager.place_vault_ritual_card("holy_water", 1), "a retry can save the first card into any free socket")
	check(not manager.place_vault_ritual_card("holy_water", 2) and not manager.place_vault_ritual_card("crucifix", 1), "duplicates and overwriting an occupied socket are rejected")
	check(manager.place_vault_ritual_card("crucifix", 0) and not manager.claim_vault_ritual_shotgun(), "two distinct cards cannot unlock the shotgun")
	check(manager.place_vault_ritual_card("silver_bullet", 2) and manager.get_vault_ritual_state().completed, "three distinct story cards complete the ritual")
	manager.reject_save = true
	previous = manager.collection.duplicate(true)
	check(not manager.claim_vault_ritual_shotgun() and manager.collection == previous, "a failed pickup save keeps the pending shotgun available")
	manager.reject_save = false
	check(manager.claim_vault_ritual_shotgun() and not manager.claim_vault_ritual_shotgun(), "shotgun collection is durable and can only happen once")
	manager.clear_profile_state()
	check(not manager.get_vault_ritual_state().completed and not manager.get_vault_ritual_state().shotgun_collected, "a fresh profile inherits neither sockets nor shotgun ownership")
	manager.free()
