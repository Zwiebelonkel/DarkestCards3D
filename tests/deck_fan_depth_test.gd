extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with the isolated match feature test runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	for data: Dictionary in CardDatabase.get_all_cards():
		if CardData.is_combat_card(data) and not DeckManager.is_full():
			var card_id := str(data["id"])
			CollectionManager.create_card_instance(card_id)
			DeckManager.add_card(card_id)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	main.wakeup_blur_duration = 0.02
	viewport.add_child(main)
	screen = main.get_node("ScenePivot/Collection") as CollectionScreen
	screen.deck_fan_duration = 0.02
	screen.deck_fan_stagger = 0
	screen.deck_fan_reflow_duration = 0.02
	await settle()
	main._begin_turn(1)
	await settle()
	main._begin_turn(1)
	await settle()
	await screen._open_deck_fan()
	await settle()
	check(main._active_side == 2 and screen._deck_fan_cards.size() == 20, "Actual Main opens the complete twenty-card fan")
	for count in [20, 19, 16, 8, 6, 4, 3, 2, 1]:
		_apply_count(count)
		await settle()
		_check_geometry(count)
		if count in [20, 8, 3]:
			await capture("%d" % count)
	viewport.size = Vector2i(960, 720)
	_apply_count(20)
	await settle()
	_check_geometry(20)
	await capture("20-4by3")
	main.queue_free()
	await settle()
	print("DECK_FAN_DEPTH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _apply_count(count: int) -> void:
	for index in range(screen._deck_fan_cards.size()):
		var card := screen._deck_fan_cards[index]
		card.visible = index < count
		if index >= count:
			continue
		var pose := screen._calculate_fan_transform(index, count)
		card.global_position = pose.position
		card.rotation_degrees = pose.rotation
		card.scale = pose.scale


func _check_geometry(count: int) -> void:
	var visible_bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var inside := true
	var ordered := true
	var previous_x := -INF
	for index in range(count):
		var card := screen._deck_fan_cards[index]
		var projected := screen.camera.unproject_position(card.global_position)
		ordered = ordered and projected.is_finite() and projected.x > previous_x
		previous_x = projected.x
		for corner in [Vector3(-0.39, -0.54, 0), Vector3(0.39, -0.54, 0), Vector3(-0.39, 0.54, 0), Vector3(0.39, 0.54, 0)]:
			inside = inside and visible_bounds.has_point(screen.camera.unproject_position(card.to_global(corner)))
	check(ordered and inside, "%d-card fan keeps finite, left-to-right positions inside the viewport" % count)
	if count == 1:
		return
	var left_index := floori(float(count - 1) * 0.5)
	var right_index := left_index + 1
	var left := screen._deck_fan_cards[left_index]
	var right := screen._deck_fan_cards[right_index]
	var face_normal := left.global_basis.z.normalized()
	var plane_distance := absf((right.global_position - left.global_position).dot(face_normal))
	var body := left.get_node("card/Cube") as MeshInstance3D
	var body_thickness := (body.global_basis.z * body.get_aabb().size.z).length()
	check(absf(face_normal.dot(right.global_basis.z.normalized())) > 0.999 and plane_distance > body_thickness + 0.001, "%d-card central faces occupy distinct planes beyond the physical card thickness" % count)
	var left_point := screen.camera.unproject_position(left.to_global(Vector3(-0.32, 0.30, 0.06)))
	var right_point := screen.camera.unproject_position(right.to_global(Vector3(0.32, 0.30, 0.06)))
	check(left_point.x < right_point.x and right_point.x - left_point.x > 20, "%d-card middle pair retains visible horizontal separation" % count)


func settle() -> void:
	await get_tree().create_timer(0.12).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://deck-fan-%s.png" % stage)
