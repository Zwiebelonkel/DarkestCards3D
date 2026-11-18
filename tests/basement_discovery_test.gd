extends Node

const KEY_ID := "graveyard_key"

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var basement: BasementDiscovery
var discoveries: Array[String] = []
var throw_events: Array[BasementCrate] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	print(("PASS: " if condition else "FAIL: ") + message)


func _settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	# This suite exercises crate discovery after the separate cat encounter.
	if GameCurrency.get_basement_cat_choice().is_empty():
		GameCurrency.resolve_basement_cat_choice("spared")
	SettingsManager.set_fullscreen(false)
	Localization.set_locale("en")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	CollectionManager.add_card("basement_key")
	check(CollectionManager.use_access_key("basement_key"), "discovery fixture explicitly activates basement access")
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	await _spawn_main()
	if basement == null:
		check(false, "Main instantiates the basement discovery controller")
		_finish()
		return
	var crates := basement.get_crates()
	var secret := basement._secret_crate
	check(crates.size() == 14 and crates.has(secret), "all fourteen basement crates use the shared throw mechanic")
	if secret == null:
		main.queue_free()
		_finish()
		return
	check(secret == basement.get_node("Storage/FloorCrate"), "the floor crate covers the single authored discovery")
	var all_crates_valid := true
	for crate in crates:
		all_crates_valid = all_crates_valid and crate is LocalTableProp and crate.is_in_group("basement_crates") and crate._pick_area != null and crate._pick_area.get_child_count() > 0
		crate.thrown.connect(func(thrown_crate: BasementCrate): throw_events.append(thrown_crate))
	check(all_crates_valid, "each crate has mesh-shaped physics picking and the basement group")
	_check_real_room_collisions(secret)
	check(_all_picking_disabled(), "all basement crate ray layers and hitboxes are inactive in the hub")
	_send_area_event(secret)
	check(not secret._launched and CollectionManager.get_amount(KEY_ID) == 0, "even a queued crate input cannot reveal a card while outside the basement")
	var card := basement._hidden_card
	check(card != null and card.card_data.get("id") == KEY_ID, "the secret is represented by a real graveyard-key Card3D")
	if card != null:
		check(not secret.is_ancestor_of(card) and not card.area.input_ray_pickable and card.area.collision_layer == 0, "the floor card stays independent of the thrown crate and cannot intercept clicks")
		var paper := card.card_model.get_node("Cube") as MeshInstance3D
		var paper_bounds := paper.global_transform * paper.get_aabb()
		check(paper_bounds.size.y < 0.025 and minf(paper_bounds.size.x, paper_bounds.size.z) > 0.15 and paper_bounds.get_center().y < secret.to_global(secret._center_local).y, "the actual card lies paper-thin on the floor beneath the crate")
	check(not CollectionManager.has_area_access("graveyard"), "looking at the unopened secret does not unlock the graveyard")
	await _enter_basement()
	check(main._active_room == 3 and _unthrown_picking_enabled(), "entering the basement enables its unthrown crates through Main")
	await _check_input_gates(secret)
	var ordinary := await _find_normal_crate()
	check(ordinary != null, "a normal crate is reachable by the real camera and physics ray")
	if ordinary != null:
		var start_pose := ordinary.global_transform
		await _click_at(_crate_pointer(ordinary))
		await _settle(0.15)
		check(ordinary._launched and ordinary.global_position.distance_to(start_pose.origin) > 0.1, "actual mouse input throws the ordinary crate with visible motion")
		check(CollectionManager.get_amount(KEY_ID) == 0 and discoveries.is_empty(), "throwing an ordinary crate gives no secret reward")
		check(not ordinary._pick_area.input_ray_pickable and ordinary._pick_area.collision_layer == 0, "a flying crate immediately stops absorbing later clicks")
	await _face_crate(secret)
	check(_ray_hits_crate(secret), "the secret floor crate is reachable from a normal cardinal camera view")
	await _capture("covered")
	var floor_card_position := basement._hidden_card.global_position
	await _click_at(_crate_pointer(secret))
	check(secret._launched and CollectionManager.get_amount(KEY_ID) == 1, "clicking the secret crate automatically awards one graveyard key")
	check(discoveries == [KEY_ID] and CollectionManager.get_instances_for_card(KEY_ID).size() == 1, "the discovery emits once and creates exactly one saved card instance")
	check(not CollectionManager.has_area_access("graveyard") and not CollectionManager.is_access_key_used(KEY_ID) and CollectionManager.get_unused_access_key_ids().has(KEY_ID) and DeckManager.battle_deck.is_empty(), "the found key remains unused until activated in the hub and never enters the battle deck")
	check(is_instance_valid(basement._hidden_card) and basement._hidden_card.is_visible_in_tree(), "the revealed physical card remains visible briefly without another pickup click")
	await _settle(0.95)
	check(basement._hidden_card.global_position.distance_to(floor_card_position) > 0.5 and not basement._hidden_card.area.input_ray_pickable and basement._hidden_card.area.collision_layer == 0, "the discovered card rises from the floor without becoming a second interactive pickup")
	await _capture("revealed")
	_send_area_event(secret)
	_send_area_event(secret)
	check(throw_events.count(secret) == 1 and discoveries == [KEY_ID] and CollectionManager.get_amount(KEY_ID) == 1, "duplicate click delivery neither rethrows the secret crate nor duplicates its reward")
	check(secret.is_visible_in_tree() and not secret.is_dissolving(), "the thrown crate remains present before its delayed dissolve")
	await _settle(secret.dissolve_delay + secret.dissolve_duration + 0.2)
	check(not secret.is_visible_in_tree() and not secret.is_physics_processing() and secret.get_rigid_body() == null, "the delayed dissolve removes the physical body and leaves the thrown crate hidden")
	await _leave_basement()
	check(main._active_room == 0 and _all_picking_disabled(), "leaving the basement disables every remaining crate ray layer")
	await _enter_basement()
	check(secret._launched and not secret.is_visible_in_tree() and not secret._pick_area.input_ray_pickable, "reentering the same room does not restore an already thrown crate")
	_send_area_event(secret)
	check(CollectionManager.get_amount(KEY_ID) == 1 and discoveries == [KEY_ID], "room reentry does not award another discovery")
	await _check_loaded_ownership()
	main.queue_free()
	await _settle()
	_finish()


func _spawn_main() -> void:
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	main.room_travel_duration = 0.7
	viewport.add_child(main)
	basement = main.get_node("BasementRoom") as BasementDiscovery
	if basement != null:
		basement.card_discovered.connect(func(card_id: String): discoveries.append(card_id))
	_move_pointer(Vector2(5, 700))
	await _settle(0.6)


func _check_real_room_collisions(secret: BasementCrate) -> void:
	var environment := basement._crate_environment
	check(is_instance_valid(environment) and environment.collision_layer == 1 << 12 and not environment.input_ray_pickable, "the actual basement shell supplies a dedicated non-pickable collision body")
	var center := secret.to_global(secret._center_local)
	var down := PhysicsRayQueryParameters3D.create(center + Vector3.UP, center + Vector3.DOWN * 8.0, 1 << 12)
	var floor_hit := basement.get_world_3d().direct_space_state.intersect_ray(down)
	check(floor_hit.get("collider") == environment and absf(float(floor_hit.get("position", Vector3.INF).y) - (basement.get_node("Storage") as Node3D).global_position.y) < 0.15, "the floor beneath the secret crate collides at the visible basement floor height")
	var eye := basement.global_position + Vector3.UP * 0.5
	var horizontal := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.RIGHT * 30.0, 1 << 12)
	var wall_hit := basement.get_world_3d().direct_space_state.intersect_ray(horizontal)
	check(wall_hit.get("collider") == environment and (wall_hit.get("normal", Vector3.ZERO) as Vector3).x < -0.8, "the real eastern wall blocks outgoing crate movement")


func _check_input_gates(secret: BasementCrate) -> void:
	main.pause_menu.open()
	await _settle()
	check(get_tree().paused and _all_picking_disabled(), "Pause disables the basement's picking layers as well as its input")
	_send_area_event(secret)
	check(not secret._launched and CollectionManager.get_amount(KEY_ID) == 0, "paused crate input cannot throw or award the hidden card")
	main.pause_menu.close()
	await _settle()
	check(_unthrown_picking_enabled(), "closing Pause restores the remaining crate interactions")
	# The existing pack-opening modal also blocks other world interactions.
	main._pack_opening_blocks_screen_focus = true
	await _settle()
	check(_all_picking_disabled(), "an active modal removes all basement crate ray targets")
	_send_area_event(secret)
	check(not secret._launched and discoveries.is_empty(), "modal-blocked crate input cannot reveal the secret")
	main._pack_opening_blocks_screen_focus = false
	await _settle()
	check(_unthrown_picking_enabled(), "clearing the modal restores unopened crates")


func _check_loaded_ownership() -> void:
	var found_instances := CollectionManager.get_instances_for_card(KEY_ID)
	if found_instances.is_empty():
		check(false, "the reload scenario has its discovered card to preserve")
		return
	var saved_instance_id := str(found_instances[0].get("instance_id"))
	CollectionManager.save_collection()
	main.queue_free()
	await _settle()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	var loaded_instances := CollectionManager.get_instances_for_card(KEY_ID)
	check(CollectionManager.get_amount(KEY_ID) == 1 and loaded_instances.size() == 1 and str(loaded_instances[0].get("instance_id")) == saved_instance_id, "save/load preserves the exact discovered card instance")
	await _spawn_main()
	var secret := basement._secret_crate
	check(not is_instance_valid(basement._hidden_card) or not basement._hidden_card.is_visible_in_tree(), "a new Main with an owned key has no second hidden reward to reveal")
	await _enter_basement()
	await _face_crate(secret)
	await _click_at(_crate_pointer(secret))
	check(secret._launched, "already owning the key does not disable ordinary crate throwing")
	var final_instances := CollectionManager.get_instances_for_card(KEY_ID)
	check(CollectionManager.get_amount(KEY_ID) == 1 and discoveries == [KEY_ID] and final_instances.size() == 1 and str(final_instances[0].get("instance_id")) == saved_instance_id, "throwing the secret crate after reload preserves ownership without another award or signal")


func _all_picking_disabled() -> bool:
	for crate in basement.get_crates():
		if crate._pick_area.input_ray_pickable or crate._pick_area.collision_layer != 0:
			return false
	return true


func _unthrown_picking_enabled() -> bool:
	for crate in basement.get_crates():
		if not crate._launched and (not crate.interaction_enabled or not crate._pick_area.input_ray_pickable or crate._pick_area.collision_layer == 0):
			return false
	return true


func _enter_basement() -> void:
	for area in main.progression_areas:
		if area.room_index == 3:
			await _face_target(area.door.doorway_area.global_position)
			await _click_at(main.main_camera.unproject_position(area.door.doorway_area.global_position))
			check(main._room_transition_active and _all_picking_disabled(), "camera flight keeps basement crates inactive until arrival")
			await _wait_arrival()
			return


func _leave_basement() -> void:
	var door := basement.get_node("ReturnDoor") as HospitalDoor
	await _face_target(door.doorway_area.global_position)
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	check(main._room_transition_active and _all_picking_disabled(), "the return flight immediately disables basement crate input")
	await _wait_arrival()


func _wait_arrival() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while main._room_transition_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _settle()


func _find_normal_crate() -> BasementCrate:
	for _step in range(4):
		for crate in basement.get_crates():
			if crate != basement._secret_crate and not crate._launched and _ray_hits_crate(crate):
				return crate
		main._begin_turn(1)
		await _settle(0.18)
	return null


func _face_crate(crate: BasementCrate) -> void:
	await _face_target(crate.to_global(crate._center_local))


func _face_target(target: Vector3) -> void:
	_move_pointer(Vector2(5, 700))
	await _settle(0.5)
	for _step in range(4):
		if _target_visible(target):
			return
		main._begin_turn(1)
		await _settle(0.18)
	check(false, "target is visible using the existing cardinal camera turns")


func _target_visible(target: Vector3) -> bool:
	return not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20).has_point(main.main_camera.unproject_position(target))


func _crate_pointer(crate: BasementCrate) -> Vector2:
	return main.main_camera.unproject_position(crate.to_global(crate._center_local))


func _ray_hits_crate(crate: BasementCrate) -> bool:
	if not _target_visible(crate.to_global(crate._center_local)):
		return false
	var point := _crate_pointer(crate)
	var origin := main.main_camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + main.main_camera.project_ray_normal(point) * main.main_camera.far)
	query.collide_with_areas = true
	return main.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == crate._pick_area


func _send_area_event(crate: BasementCrate) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	crate._pick_area.input_event.emit(main.main_camera, event, crate.global_position, Vector3.UP, 0)


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	viewport.push_input(event, true)


func _click_at(position: Vector2) -> void:
	_move_pointer(position)
	await _settle(0.04)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://basement-discovery-%s.png" % stage)


func _finish() -> void:
	print("BASEMENT_DISCOVERY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
