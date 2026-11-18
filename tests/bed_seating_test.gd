extends Node3D

const SEATS := preload("res://scripts/props/BedSeating.gd")
var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var seats: SEATS
var output := "res://test-user/bed-seating"
var samples: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func wait_until(predicate: Callable, timeout_ms: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func settle(seconds: float = 0.12) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _process(_delta: float) -> void:
	if is_instance_valid(seats) and seats.is_busy():
		samples.append({"state": seats.state, "bed": seats.selected_bed, "eye": main.main_camera.global_position, "forward": -main.main_camera.global_basis.z, "walking": main._walking_steps_active})


func move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	viewport.push_input(event, true)


func click(point: Vector2) -> void:
	move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)


func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)


func bed_pointer(index: int) -> Vector2:
	for z in [0.0, -1.0, 1.0, 2.0]:
		for x in [0.0, -0.8, 0.8]:
			var point := main.main_camera.unproject_position(seats.beds[index].to_global(Vector3(x, 0.3, z)))
			if viewport.get_visible_rect().has_point(point) and seats._bed_at(point) == index:
				return point
	return Vector2(-1, -1)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(output + "/" + label + ".png") == OK, "capture " + label)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use an isolated project.")
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	GameCurrency.set_process(false)
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.unlock_slot_room()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	main.room_travel_duration = 0.55
	viewport.add_child(main)
	seats = main.bed_seating
	seats.face_duration = 0.12
	seats.turn_duration = 0.28
	seats.sit_duration = 0.22
	move_pointer(Vector2(-50, -50))
	await settle(0.4)
	check(seats.beds.size() == 2 and seats.areas.size() == 2, "both user-placed beds have independent interactions")
	check(not seats.sit_on_bed(0) and seats.areas[0].collision_layer == 0, "beds cannot be used or block picking from the hub")
	main._on_room_door_activated(main.hub_door)
	check(await wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "real door route enters the jackpot room")
	await settle()
	for index in range(4):
		if bed_pointer(0).x >= 0.0 and bed_pointer(1).x >= 0.0:
			break
		main._request_turn(1)
		await settle(0.3)
	check(bed_pointer(0).x >= 0.0 and bed_pointer(1).x >= 0.0, "both beds are visible and pickable from their actual room view")
	if bed_pointer(0).x < 0.0:
		_finish()
		return
	var collection_before := CollectionManager.collection.duplicate(true)
	for index in range(2):
		await _check_bed(index)
	move_pointer(bed_pointer(0))
	await settle()
	main.pause_menu.open()
	check(seats.hovered_bed == -1 and not seats.can_start() and not seats.areas[0].input_ray_pickable, "Pause clears bed hover and disables picking")
	main.pause_menu.close()
	await settle()
	await face_bed(0)
	var original := main.camera_pivot.global_transform
	click(bed_pointer(0))
	check(await wait_until(func(): return seats.state == SEATS.State.WALKING), "early-return fixture reaches its walking phase")
	key(KEY_ESCAPE)
	check(await wait_until(func(): return not seats.is_busy()), "Escape during approach safely completes the return without getting stuck")
	check(main.camera_pivot.global_position.is_equal_approx(original.origin) and main._active_side == main.fusion_workbench.view_side and not main.pause_menu.visible and not main._walking_steps_active, "early Escape returns to the forge view and releases movement")
	check(CollectionManager.collection == collection_before, "sitting and returning do not change the player's cards or progress")
	var route_clearance := INF
	for sample in samples:
		if sample["state"] not in [SEATS.State.WALKING, SEATS.State.RETURNING]:
			continue
		for index in range(2):
			var point := seats.beds[index].to_local(sample["eye"])
			var box := seats.bounds[index]
			var dx := maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0)
			var dz := maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0.0)
			route_clearance = minf(route_clearance, Vector2(dx, dz).length())
	check(route_clearance > 1.0, "every sampled approach and direct return stays clear of both actual bed footprints")
	main._request_turn(1)
	await settle(0.3)
	check(main._phase == MainScene.Phase.IDLE and main._can_turn(), "normal cardinal turning remains available after using both beds")
	var report := {"validated_at_utc": Time.get_datetime_string_from_system(true), "checks": checks, "failures": failures, "samples": samples.size(), "minimum_approach_clearance": route_clearance, "bed_bounds": [str(seats.bounds[0]), str(seats.bounds[1])], "authored_beds_preserved": true}
	var file := FileAccess.open(output + "/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	main.queue_free()
	await settle()
	_finish()


func face_bed(index: int) -> void:
	for turn in range(4):
		if bed_pointer(index).x >= 0.0:
			return
		main._request_turn(1)
		await settle(0.3)


func _check_bed(index: int) -> void:
	await face_bed(index)
	var bed_pose := seats.beds[index].global_transform
	var original := main.camera_pivot.global_transform
	var camera_local := main.main_camera.transform
	var fov := main.main_camera.fov
	var side := main._active_side
	move_pointer(bed_pointer(index))
	await settle()
	check(seats.hovered_bed == index, "bed %d acquires hover from actual pointer input" % index)
	var correct := true
	for group in range(2):
		for mesh: MeshInstance3D in seats._mesh_groups[group]:
			correct = correct and (mesh.material_overlay == seats._outline if group == index else mesh.material_overlay == seats._original_overlays[mesh])
	check(correct, "only hovered bed %d receives the yellow outline" % index)
	await capture("bed-%d-hover" % index)
	click(bed_pointer(index))
	check(seats.is_busy() and seats.selected_bed == index and seats.hovered_bed == -1, "bed %d click starts one approach and clears its outline" % index)
	check(not seats.sit_on_bed(1 - index), "a second bed cannot steal an active seating sequence")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "bed sequence blocks room turning, doors and journal")
	check(await wait_until(func(): return seats.state == SEATS.State.WALKING), "bed %d visibly walks before turning" % index)
	await settle(0.15)
	check(main._walking_steps_active and main.camera_pivot.global_position.distance_to(original.origin) > 0.1, "walking uses actual movement, footsteps and the existing camera bob")
	await capture("bed-%d-walking" % index)
	check(await wait_until(func(): return seats.state == SEATS.State.TURNING), "bed %d reaches its free long edge before turning around" % index)
	var front := main.main_camera.global_transform
	check(await wait_until(func(): return seats.state == SEATS.State.SITTING), "bed %d turns before sitting down" % index)
	check(main.main_camera.global_basis.z.dot(front.basis.z) < -0.99, "bed %d turns through 180 degrees" % index)
	check(await wait_until(func(): return seats.state == SEATS.State.SEATED), "bed %d finishes in its seated state" % index)
	check(main.main_camera.global_transform.is_equal_approx(seats._seat), "bed %d uses its own actual seated camera pose" % index)
	var other_bed_center := seats.beds[1 - index].to_global(seats.bounds[1 - index].get_center())
	var toward_other_bed := (other_bed_center - main.main_camera.global_position).normalized()
	check((-main.main_camera.global_basis.z).dot(toward_other_bed) > 0.99999, "seated on bed %d looks directly at the center of the other bed" % index)
	check(main.main_camera.global_position.y < front.origin.y - 0.5 and not main._walking_steps_active, "sitting lowers the eye and stops footsteps")
	check(main._active_side == side and not main.screen_camera_focus.is_focused(), "seating retains logical room orientation without shop focus drift")
	await capture("bed-%d-seated" % index)
	key(KEY_J)
	check(not main._is_journal_active(), "seated key presses cannot open another camera-owning view")
	var return_sample_start := samples.size()
	var return_start_time := Time.get_ticks_msec()
	var seated_forward := -main.main_camera.global_basis.z
	key(KEY_ESCAPE)
	key(KEY_ESCAPE)
	check(seats.state in [SEATS.State.RISING, SEATS.State.RETURNING] and not main.pause_menu.visible, "Escape gets up and returns instead of opening Pause")
	check(await wait_until(func(): return not seats.is_busy()), "bed %d returns to the original standing position" % index)
	var return_seconds := (Time.get_ticks_msec() - return_start_time) / 1000.0
	check(return_seconds < main.room_travel_duration + seats.sit_duration * 0.25, "bed %d returns faster without the old corner pauses and final turn" % index)
	var yaw := atan2(seated_forward.x, seated_forward.z)
	var total_yaw := 0.0
	var straight := true
	var route_start := Vector2(seats._approach.origin.x, seats._approach.origin.z)
	var route_end := Vector2(seats._return_eye.origin.x, seats._return_eye.origin.z)
	for sample in samples.slice(return_sample_start):
		var forward: Vector3 = sample["forward"]
		var next_yaw := atan2(forward.x, forward.z)
		total_yaw += absf(wrapf(next_yaw - yaw, -PI, PI))
		yaw = next_yaw
		if sample["state"] == SEATS.State.RETURNING:
			var eye: Vector3 = sample["eye"]
			var point := Vector2(eye.x, eye.z)
			straight = straight and point.distance_to(Geometry2D.get_closest_point_to_segment(point, route_start, route_end)) < 0.01
	var end_forward := -seats._return_eye.basis.z
	var minimum_turn := absf(wrapf(atan2(end_forward.x, end_forward.z) - atan2(seated_forward.x, seated_forward.z), -PI, PI))
	check(total_yaw <= minimum_turn + 0.03, "bed %d camera turns smoothly in one direction without yaw zigzags" % index)
	check(straight, "bed %d walks directly through the aisle instead of weaving through old waypoints" % index)
	check(main.camera_pivot.global_transform.is_equal_approx(seats._return_pivot) and main.camera_pivot.global_position.is_equal_approx(original.origin) and main._active_side == main.fusion_workbench.view_side and main.fusion_workbench._interaction_enabled and main.main_camera.transform.is_equal_approx(camera_local) and main.camera_tilt.transform.is_equal_approx(Transform3D.IDENTITY) and is_equal_approx(main.main_camera.fov, fov), "bed %d returns facing the interactive forge with the original position and lens" % index)
	check(seats.beds[index].global_transform.is_equal_approx(bed_pose), "user placement of bed %d remains unchanged" % index)
	check(main._can_turn() and main._can_travel_between_rooms() and not main._walking_steps_active and main._room_travel_tween == null, "bed %d releases all movement locks after return" % index)


func _finish() -> void:
	print("BED_SEATING_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)
