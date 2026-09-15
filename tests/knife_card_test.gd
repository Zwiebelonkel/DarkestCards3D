extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene


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
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
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
	viewport.add_child(main)
	await settle(0.2)
	var knife := main.get_node("ScenePivot/GameTable/decortaions/knife") as LocalTableProp
	var hidden_knife := main.get_node("decortaions/knife") as LocalTableProp
	var card := knife._knife_card
	check(card != null and card.get_parent() == knife and card.card_data.get("id") == CollectionManager.SLOT_ROOM_KEY_ID, "visible knife carries the real key card")
	check(hidden_knife._knife_card != null and not hidden_knife._knife_card.is_visible_in_tree(), "hidden duplicate knife keeps its attached card hidden")
	check((main.get_node("ScenePivot/GameTable/decortaions/usb") as LocalTableProp)._knife_card == null, "ordinary clutter receives no extra card")
	check(card.global_basis.z.normalized().dot(Vector3.DOWN) > 0.99, "key front faces down and its ordinary card back faces up")
	check(not card.area.input_ray_pickable and card.area.collision_layer == 0 and card.is_stack_decoration, "attached card cannot intercept gameplay or deck clicks")
	var body := card.card_model.get_node("Cube") as MeshInstance3D
	var bounds := body.global_transform * body.get_aabb()
	var contact := knife.to_global(LocalTableProp.KNIFE_BLADE_CONTACT)
	check(bounds.has_point(contact), "the blade actually intersects the card near its edge")
	check(bounds.size.y < 0.01 and bounds.size.x > 0.25 and bounds.size.x < 0.32, "pinned card has a paper-thin, half-size tabletop footprint")
	var table_mesh := main.get_node("ScenePivot/GameTable/table/Cube") as MeshInstance3D
	var table_bounds := table_mesh.global_transform * table_mesh.get_aabb()
	check(bounds.position.y >= table_bounds.end.y and bounds.end.y < table_bounds.end.y + 0.015, "card rests above the visible tabletop rather than inside it")
	check(not card.description_label._is_typing, "decorative card has no background typewriter playback")
	check(CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 0, "seeing the face-down card does not award the secret")
	await _capture("table")
	# A close-up is only a test camera; production keeps the normal player view.
	var closeup := Camera3D.new()
	main.add_child(closeup)
	closeup.global_position = contact + Vector3(0.8, 1.3, 0.5)
	closeup.look_at(contact + Vector3(-0.13, 0.13, 0.0), Vector3.UP)
	closeup.fov = 52
	closeup.make_current()
	await settle()
	await _capture("closeup")
	main.main_camera.make_current()
	closeup.queue_free()
	await settle()
	var motion := InputEventMouseMotion.new()
	motion.position = main.main_camera.unproject_position(knife.to_global(knife._center_local))
	motion.global_position = motion.position
	viewport.push_input(motion, true)
	await settle()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = motion.position
	click.global_position = click.position
	viewport.push_input(click, true)
	await settle(0.18)
	check(knife._launched and CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1, "actual mouse click throws the knife and silently grants one key")
	check(not is_instance_valid(card) and knife._knife_card == null, "unlocking the key immediately removes the pinned card from the thrown knife")
	check(hidden_knife._knife_card == null and hidden_knife.get_node_or_null("PinnedKeyCard") == null, "the same collection change removes the card from the hidden duplicate knife")
	await _capture("flight")
	knife._launch(main.main_camera)
	check(CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1, "repeat throw cannot duplicate the attached key reward")
	await settle(knife.flight_duration)
	check(not knife.is_visible_in_tree(), "the unpinned knife completes its ordinary flight")
	main.queue_free()
	await settle()
	CollectionManager.load_collection()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	viewport.add_child(main)
	await settle(0.2)
	knife = main.get_node("ScenePivot/GameTable/decortaions/knife") as LocalTableProp
	hidden_knife = main.get_node("decortaions/knife") as LocalTableProp
	check(knife._knife_card == null and hidden_knife._knife_card == null, "reloading the room with the saved key leaves both knives without a pinned card")
	knife._launch(main.main_camera)
	check(knife._launched and CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1, "a knife remains throwable after reload without granting another key")
	check(CollectionManager.unlock_slot_room(), "the acquired key still unlocks the slot room")
	main.queue_free()
	await settle()
	# Discovery remains permanent even if another feature later removes ownership.
	CollectionManager.collection["cards"].erase(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.collection["instances"] = []
	CollectionManager.collection["metadata"]["slot_room_unlocked"] = false
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	var discovered_knife := _fresh_knife()
	check(discovered_knife._knife_card == null, "saved discovery keeps a later knife bare even without a currently owned key")
	discovered_knife.queue_free()
	await settle()
	# Old profiles may contain only the permanent room flag and no discovery history.
	CollectionManager.collection = {"cards": {}, "instances": [], "metadata": {"slot_room_unlocked": true}}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	var unlocked_knife := _fresh_knife()
	check(unlocked_knife._knife_card == null, "a legacy unlocked slot room also suppresses the pinned key")
	unlocked_knife.queue_free()
	await settle()
	print("KNIFE_CARD_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _fresh_knife() -> LocalTableProp:
	var result := (load("res://assets/environments/props/knife/knife.glb") as PackedScene).instantiate()
	result.set_script(preload("res://scripts/table/LocalTableProp.gd"))
	result.name = "RenamedNativeKnife"
	viewport.add_child(result)
	return result as LocalTableProp


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://knife-card-%s.png" % stage)
