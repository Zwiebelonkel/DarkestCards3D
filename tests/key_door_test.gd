extends Node3D

var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	SettingsManager.set_fullscreen(false)
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
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
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(viewport.size)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.room_travel_duration = 0.35
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	viewport.add_child(main)
	_move_pointer(Vector2(5, 700))
	await settle(0.15)
	check(main.hub_door.locked and not main.hub_door.doorway_area.input_ray_pickable, "fresh profile has a locked slot-room door")
	main.hub_door._on_mouse_entered()
	main._on_room_door_activated(main.hub_door)
	await settle()
	check(is_zero_approx(main.hub_door.hinge.rotation.y) and main._active_room == 0 and not main._room_transition_active, "hover and direct activation cannot bypass the missing key")
	var knife := main.get_node("ScenePivot/GameTable/decortaions/knife") as LocalTableProp
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	knife._pick_area.input_event.emit(main.main_camera, click, knife.global_position, Vector3.UP, 0)
	await settle(0.5)
	check(knife._launched and CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1, "throwing the actual table knife grants one key")
	check(main.hub_door.locked and not CollectionManager.is_slot_room_unlocked(), "discovering the key alone does not open the door")
	var collection := main.get_node("ScenePivot/Collection") as CollectionScreen
	collection.detail_mouse_tilt_strength = 0.0
	check(collection._detail_card == null and not collection._deck_button.visible, "secret reward creates no card popup or detail action")
	await _turn(1)
	await _turn(1)
	var key_in_normal_collection := false
	for child in collection.cards_root.get_children():
		if child is Card3D and str(child.card_data.get("id", "")) == CollectionManager.SLOT_ROOM_KEY_ID:
			key_in_normal_collection = true
	check(not key_in_normal_collection and main.upgrade_collection._cards.has(CollectionManager.SLOT_ROOM_KEY_ID), "the discovered key belongs to the special wall instead of the normal collection")
	_move_pointer(Vector2(640, 718))
	await settle(0.5)
	check(main.access_key_tray.is_expanded() and main.access_key_tray._key_tiles.has(CollectionManager.SLOT_ROOM_KEY_ID), "bottom hover unfolds the discovered key's tray entry")
	if not main.access_key_tray._key_tiles.has(CollectionManager.SLOT_ROOM_KEY_ID):
		_finish()
		return
	await _capture("key-tray")
	var key_tile := main.access_key_tray._key_tiles[CollectionManager.SLOT_ROOM_KEY_ID] as Node3D
	await _click_point(main.main_camera.unproject_position(key_tile.global_position))
	check(main._room_transition_active and not main.access_key_tray.is_expanded(), "real tray click begins one key cinematic and stows the keys")
	var original_steps := main._settle_step_index
	main._begin_turn(1)
	check(main._settle_step_index == original_steps, "A/D cannot interrupt the key cinematic")
	await _wait_for_transition_start()
	check(collection._detail_card == null and main._room_transition_active, "the tray grants camera control without creating a card detail popup")
	check(main.hub_door.locked and not CollectionManager.is_slot_room_unlocked(), "door stays locked until the camera is looking at it")
	var camera_before := main.main_camera.global_basis
	main.pause_menu.open()
	main._on_slot_room_key_requested()
	check(not main.pause_menu.visible and main._room_transition_active, "pause and duplicate activation cannot interrupt the key cinematic")
	await settle(0.5)
	check(not main.main_camera.global_basis.is_equal_approx(camera_before), "camera turns gradually toward the doorway")
	await _wait_for_transition_end()
	check(CollectionManager.is_slot_room_unlocked() and not main.hub_door.locked, "looking at the door permanently unlocks access")
	check(is_equal_approx(main.hub_door.hinge.rotation.y, deg_to_rad(main.hub_door.travel_open_degrees)), "player sees the door fully swing open")
	var target := main.hub_door.doorway_area.global_position
	var pointer := main.main_camera.unproject_position(target)
	check(not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().has_point(pointer) and absf(pointer.x - 640) < 50, "opened door is centered in the actual camera view")
	check(main._active_room == 0 and not collection._slot_room_key_request_pending and not main.access_key_tray._key_tiles.has(CollectionManager.SLOT_ROOM_KEY_ID), "key action leaves the player at the door with controls restored and the used key removed from the tray")
	check(DeckManager.battle_deck.is_empty() and CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1, "using the key neither consumes it nor adds it to the combat deck")
	await _capture("door-open")
	CollectionManager.load_collection()
	check(CollectionManager.is_slot_room_unlocked(), "door unlock survives save reload")
	await _click_area(main.hub_door.doorway_area)
	await _wait_for_transition_end()
	check(main._active_room == 1 and main.return_door.doorway_area.input_ray_pickable, "opened door allows normal travel and exposes a return door")
	await _turn(1)
	await _turn(1)
	await _click_area(main.return_door.doorway_area)
	await _wait_for_transition_end()
	check(main._active_room == 0 and main._active_side == 3, "return flight restores the nearest normal hub side")
	var basis := main.camera_pivot.basis
	for index in range(4):
		await _turn(1)
	check(main.camera_pivot.basis.is_equal_approx(basis), "A/D retains exact cardinal alignment after key view and round trip")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	await settle(0.4)
	check(main.hub_door.locked and not main.hub_door.doorway_area.input_ray_pickable, "resetting collection also locks the slot-room door again")
	# The standalone collection carries its request into a newly loaded Main.
	main.queue_free()
	await settle()
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.set_meta("slot_room_key_focus_requested", true)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.4
	main.door_key_look_duration = 0.3
	main.mouse_tilt_strength = 0.0
	viewport.add_child(main)
	await settle()
	check(not CollectionManager.has_meta("slot_room_key_focus_requested") and main._room_transition_active, "standalone handoff is consumed once and takes camera control")
	check(main.hub_door.locked and main._wakeup_blur_tween.is_running(), "standalone opening waits until initial wake blur has settled")
	await _wait_for_transition_end()
	check(CollectionManager.is_slot_room_unlocked() and not main.hub_door.locked and main._active_room == 0, "standalone handoff completes the same visible door unlock")
	CollectionManager.add_card("graveyard_key")
	main._on_access_key_requested("graveyard_key")
	await settle()
	var pending_tween := main._door_key_tween
	main.queue_free()
	await settle()
	main = null
	check(not pending_tween.is_valid() and not CollectionManager.has_meta("slot_room_key_focus_requested"), "scene exit cancels an interrupted key look without a stale handoff")
	_finish()


func _turn(direction: int) -> void:
	main._begin_turn(direction)
	await settle(0.12)


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	viewport.push_input(event, true)


func _click_area(area: Area3D) -> void:
	var position := main.main_camera.unproject_position(area.global_position)
	await _click_point(position)


func _click_point(position: Vector2) -> void:
	_move_pointer(position)
	await settle()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _wait_for_transition_start() -> void:
	for index in range(180):
		if main._room_transition_active:
			return
		await get_tree().process_frame
	check(false, "key camera starts in bounded time")


func _wait_for_transition_end() -> void:
	for index in range(600):
		if not main._room_transition_active:
			return
		await get_tree().process_frame
	check(false, "key/travel camera finishes in bounded time")


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://key-door-%s.png" % stage)


func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	print("KEY_DOOR_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
