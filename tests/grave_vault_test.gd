extends "res://tests/grave_name_puzzle_test.gd"

var entry: Node3D
var hall: Node3D
var route_samples: Array[Dictionary] = []
var route_obstructions := 0
var fog_discontinuities := 0
var expected_fog: Dictionary = {}


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://test-user/vault")
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	CollectionManager.add_card("graveyard_key")
	CollectionManager.use_access_key("graveyard_key")
	GameCurrency._basement_cat_choice = "shot"
	check(GameCurrency.consume_story_package("mdma", true), "the real MDMA use enables the grave puzzle")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	_make_vault_main()
	if main == null:
		return
	await _settle(0.5)
	check(not entry.is_open and not entry.pick_area.input_ray_pickable and not entry.stairs.visible,
		"unsolved profiles have no visible or clickable secret stair")
	main._enter_underground_vault()
	check(main._active_room == 0 and not main._room_transition_active, "the hub cannot enter the secret remotely")
	await _travel_to(2)
	await _face_graves()
	await _capture("graveyard-closed")
	var originals: Array[Vector3] = []
	var rotations: Array[Vector3] = []
	for grave in puzzle.graves:
		originals.append(grave.position)
		rotations.append(grave.rotation)
	var baseline := await _sample_cost()
	for index in range(4):
		await _click_at(_grave_point(index))
	check(entry.is_opening and not entry.is_open and CollectionManager.get_amount("silver_bullet") == 1,
		"solving with real grave clicks starts the reveal and grants the existing story card")
	check(not main._can_turn(false) and not main._can_travel_between_rooms() and not entry.pick_area.input_ray_pickable,
		"the reveal locks turning, room exits and early stair clicks")
	await _settle(entry.reward_hold_duration + entry.slide_duration * 0.45)
	check(entry.open_amount > 0 and entry.open_amount < 1, "the original ground opens gradually with the stone movement")
	check(puzzle.graves[0].position.z > originals[0].z and puzzle.graves[1].position.z > originals[1].z
		and puzzle.graves[2].position.z < originals[2].z and puzzle.graves[3].position.z < originals[3].z,
		"the two right graves slide right and the two left graves slide left")
	var all_wobbling := true
	for index in range(puzzle.graves.size()):
		all_wobbling = all_wobbling and puzzle.graves[index].rotation.distance_to(rotations[index]) > 0.005
	check(all_wobbling, "all four graves visibly rock while sliding sideways")
	await _capture("graveyard-sliding")
	main.pause_menu.open()
	var frozen_opening: float = entry.open_amount
	var frozen_grave: Vector3 = puzzle.graves[0].position
	var frozen_rotation: Vector3 = puzzle.graves[0].rotation
	await _settle(0.2)
	check(is_equal_approx(entry.open_amount, frozen_opening) and puzzle.graves[0].position.is_equal_approx(frozen_grave)
		and puzzle.graves[0].rotation.is_equal_approx(frozen_rotation),
		"Pause freezes the moving/wobbling graves and the ground reveal")
	main.pause_menu.close()
	check(await _wait_until(func(): return entry.open_amount > 0.88), "the opening reaches the final fade while moving")
	var all_fading := true
	for visuals: Array in entry._grave_visuals:
		for visual: GeometryInstance3D in visuals:
			all_fading = all_fading and visual.is_visible_in_tree() and visual.transparency > 0.1 and visual.transparency < 1.0
	check(all_fading, "grave stone, soil and inscriptions fade together before the animation ends")
	await _capture("graveyard-fading")
	check(await _wait_until(func(): return entry.is_open and not entry.is_opening), "the slide finishes and releases the stair")
	var all_hidden := true
	for grave in puzzle.graves:
		all_hidden = all_hidden and not grave.visible
	var faded_before_hidden := true
	for visuals: Array in entry._grave_visuals:
		for visual: GeometryInstance3D in visuals:
			faded_before_hidden = faded_before_hidden and is_equal_approx(visual.transparency, 1.0)
	check(faded_before_hidden, "the final hide cannot cause a visible pop because every grave visual is already transparent")
	check(all_hidden and not puzzle.interaction_enabled and entry.pick_area.input_ray_pickable,
		"all four graves disappear to the sides and their old picking areas are disabled")
	check(entry.floor_meshes.size() >= 3 and is_equal_approx(entry.open_amount, 1.0), "the overlapping earth, grass and path surfaces all expose the shaft")
	var synced := true
	for mesh in entry.floor_meshes:
		synced = synced and is_equal_approx(float(mesh.get_instance_shader_parameter("grave_opening_amount")), 1.0)
	check(synced, "the visible hole is applied to every overlapping floor layer")
	await _capture("graveyard-open")
	var after := await _sample_cost()
	var point := main.main_camera.unproject_position(entry.pick_area.global_position)
	_move_pointer(point)
	await _settle()
	check(entry._hovered, "the revealed stair has a real yellow mouse hover")
	await _capture("stair-hover")
	main.pause_menu.open()
	await _settle()
	var blocked := InputEventMouseButton.new()
	blocked.pressed = true
	blocked.button_index = MOUSE_BUTTON_LEFT
	entry.pick_area.input_event.emit(main.main_camera, blocked, Vector3.ZERO, Vector3.ZERO, 0)
	check(main._active_room == 2 and not main._room_transition_active and not entry._hovered, "Pause blocks secret stair activation and clears hover")
	main.pause_menu.close()
	await _settle()
	var saved_pose := main.camera_pivot.global_transform
	var saved_side := main._active_side
	var saved_environment := main.main_camera.environment
	expected_fog = _fog_signature(_effective_environment())
	await _click_at(point)
	check(main._room_transition_active, "a real left click starts the descent")
	check(await _observe_travel(5), "the actual shared camera follows the full stair route into the vault")
	check(main._active_room == 5 and hall.visible and hall.exit_area.input_ray_pickable and not entry.pick_area.input_ray_pickable,
		"the new room enables only its own return passage")
	check(main.main_camera.environment == hall.room_environment and main._can_turn(false), "the vault has its own underground lighting and normal cardinal turns")
	check(_fog_signature(_effective_environment()) == expected_fog and hall.room_environment.volumetric_fog_enabled,
		"the graveyard fog remains enabled with exactly the same settings inside the vault")
	check(not bool(CollectionManager.collection.metadata.get("silver_bullet_return_dialogue_seen", false)), "visiting the secret room does not consume the separate main-room Satan dialogue")
	await _capture("vault-nave")
	var vault_cost := await _sample_cost()
	for side in [1, 2, 3, 0]:
		await _turn_to(side)
		await _capture("vault-side-%d" % side)
	check(hall.get_node("Foundation").scale.x >= 32 and hall.get_node("Foundation").scale.z >= 63,
		"the saved underground chamber has the intended large footprint")
	var floor_y: float = hall.global_position.y
	var roof_top := floor_y + 13.56
	check(roof_top < main.get_node("GraveyardRoom").global_position.y - 1.0, "the entire barrel vault sits below the graveyard surface")
	await _turn_to(2)
	var exit_point := main.main_camera.unproject_position(hall.exit_area.global_position)
	_move_pointer(exit_point)
	await _settle()
	check(hall._hovered, "the exit portal is clickable and outlined from the real reverse view")
	await _capture("vault-exit-hover")
	await _click_at(exit_point)
	check(await _observe_travel(2), "the same camera climbs back to the graveyard through the stair shaft")
	check(main.camera_pivot.global_transform.is_equal_approx(saved_pose) and main._active_side == saved_side
		and main.main_camera.environment == saved_environment, "return restores the exact graveyard camera, turning state and environment")
	check(route_obstructions == 0 and route_samples.size() > 10, "a camera-sized sphere clears every observed forward/reverse travel position")
	check(fog_discontinuities == 0, "fog settings remain unchanged at every observed descent and ascent frame")
	await _capture("graveyard-return")
	check(CollectionManager.get_amount("silver_bullet") == 1, "opening and travelling never duplicate or consume the reward")
	main.queue_free()
	await _settle()
	CollectionManager.reload_profile()
	GameCurrency.load_currency()
	_make_vault_main()
	await _settle(0.2)
	check(entry.is_open and not entry.is_opening and entry.open_amount == 1.0, "a solved save restores an already-open stair without replaying the animation")
	var hidden_after_reload := true
	for grave in puzzle.graves:
		hidden_after_reload = hidden_after_reload and not grave.visible
	check(hidden_after_reload and not entry.pick_area.input_ray_pickable, "reload keeps the moved graves gone and prevents hub interaction with the remote stair")
	var base_environment: Environment = hall.room_environment
	var base_fog := _fog_signature(base_environment)
	var override := main.get_world_3d().environment.duplicate() as Environment
	override.fog_enabled = true
	override.fog_density = 0.017
	override.volumetric_fog_density = 0.068
	var override_fog := _fog_signature(override)
	hall.inherit_fog(override)
	check(_fog_signature(hall.room_environment) == override_fog and _fog_signature(base_environment) == base_fog
		and _fog_signature(override) == override_fog and hall.room_environment.ambient_light_energy == base_environment.ambient_light_energy,
		"camera-specific fog is copied without mutating either shared resource or the hall lighting")
	main.queue_free()
	await _settle()
	await _capture_asset_views()
	var report := {"checks": checks, "failures": failures, "captures": captures, "diagnostics": diagnostics,
		"route_samples": route_samples, "route_obstructions": route_obstructions, "fog_discontinuities": fog_discontinuities,
		"graveyard_before": baseline, "graveyard_open": after, "vault": vault_cost,
		"audio_driver": AudioServer.get_driver_name(), "scene_modified_unix": FileAccess.get_modified_time("res://scenes/rooms/UndergroundVault.tscn")}
	var file := FileAccess.open("res://test-user/vault/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GRAVE_VAULT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _make_vault_main() -> void:
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	if main == null:
		get_tree().quit(1)
		return
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.05
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	main.vault_travel_duration = 0.9
	viewport.add_child(main)
	puzzle = main.grave_puzzle
	entry = main.grave_vault_entrance
	hall = main.underground_vault


func _observe_travel(destination: int) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	var captured_descent := false
	var shape := SphereShape3D.new()
	shape.radius = 0.18
	while main._room_transition_active and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if _fog_signature(_effective_environment()) != expected_fog:
			fog_discontinuities += 1
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, main.main_camera.global_position)
		query.collision_mask = 1
		query.collide_with_areas = false
		var hits := main.get_world_3d().direct_space_state.intersect_shape(query)
		route_obstructions += hits.size()
		route_samples.append({"position": str(main.main_camera.global_position), "obstructions": hits.size()})
		var local_position: Vector3 = entry.stairs.to_local(main.main_camera.global_position)
		if destination == 5 and not captured_descent and local_position.z < -5 and local_position.z > -8:
			await _capture("stair-descent")
			captured_descent = true
	return main._active_room == destination and not main._room_transition_active


func _effective_environment() -> Environment:
	return main.main_camera.environment if main.main_camera.environment != null else main.get_world_3d().environment


func _fog_signature(environment: Environment) -> Dictionary:
	var values: Dictionary = {}
	for property in environment.get_property_list():
		var property_name := String(property.name)
		if property_name.begins_with("fog_") or property_name.begins_with("volumetric_fog_"):
			values[property.name] = environment.get(property.name)
	return values


func _sample_cost() -> Dictionary:
	for index in range(6):
		await get_tree().process_frame
	var times: Array[float] = []
	var start := Time.get_ticks_usec()
	for index in range(30):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - start) / 1000.0)
		start = now
	times.sort()
	var total := 0.0
	for value in times:
		total += value
	return {"mean_frame_ms": total / times.size(), "p95_frame_ms": times[28], "draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var snapshot := viewport.get_texture().get_image()
	var path := "res://test-user/vault/" + label + ".png"
	check(snapshot.save_png(path) == OK, "capture " + label)
	captures.append(path)
	var luminance := 0.0
	var samples := 0
	for y in range(0, snapshot.get_height(), 16):
		for x in range(0, snapshot.get_width(), 16):
			var color := snapshot.get_pixel(x, y)
			luminance += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			samples += 1
	diagnostics[label] = {"utc": Time.get_datetime_string_from_system(true), "camera": str(viewport.get_camera_3d().global_transform), "mean_luminance": luminance / samples}


func _capture_asset_views() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var view := SubViewport.new()
	view.size = Vector2i(1000, 750)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var room: Node3D = load("res://scenes/rooms/UndergroundVault.tscn").instantiate()
	view.add_child(room)
	var camera := Camera3D.new()
	camera.environment = room.room_environment
	camera.far = 180
	view.add_child(camera)
	var shots := {"asset-front": [Vector3(0, 14, 70), Vector3(0, 4, 0)], "asset-back": [Vector3(0, 14, -70), Vector3(0, 4, 0)],
		"asset-left": [Vector3(-48, 14, 0), Vector3(0, 4, 0)], "asset-right": [Vector3(48, 14, 0), Vector3(0, 4, 0)],
		"asset-roof": [Vector3(0, 50, 15), Vector3(0, 0, 0)], "portal-exterior": [Vector3(0, 2.1, 35), Vector3(0, 2.1, 10)],
		"portal-interior": [Vector3(3, 2.1, 25), Vector3(0, 2.1, 31.5)], "capital-junction": [Vector3(6, 4.1, 22), Vector3(9, 4.2, 20.25)],
		"roof-junction": [Vector3(0, 10.8, 27), Vector3(0, 11.8, 31.2)], "side-aisle": [Vector3(12, 2, 24), Vector3(12, 2, -20)]}
	var main_view := viewport
	viewport = view
	for label: String in shots:
		camera.position = shots[label][0]
		camera.look_at(shots[label][1])
		await _settle(0.08)
		await _capture(label)
	viewport = main_view
	view.queue_free()
	await _settle()
