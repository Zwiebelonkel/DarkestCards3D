extends Node3D

var checks := 0
var failures := 0
var output := "res://test-user/detail-rotation"


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func _settle(seconds: float = 0.12) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _button(pointer: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pointer
	event.global_position = pointer
	get_viewport().push_input(event, true)


func _motion(pointer: Vector2, relative: Vector2 = Vector2.ZERO, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pointer
	event.global_position = pointer
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output + "/" + label + ".png") == OK, "capture " + label)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run in an isolated project with redirected saves.")
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().root.size = Vector2i(1280, 900)
	get_viewport().physics_object_picking = true
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	CollectionManager.create_card_instance("corpse")
	CollectionManager.create_card_instance("wanderer")
	CollectionManager.create_card_instance("clicker")
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.035, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	world.environment = environment
	add_child(world)
	await _check_collection()
	await _check_wall()
	print("CARD_DETAIL_ROTATION_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _check_collection() -> void:
	var screen := (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D")
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.detail_duration = 0.12
	screen.detail_scale = 0.7
	screen.detail_rotation = Vector3.ZERO
	screen.detail_mouse_tilt_strength = 0.0
	screen.add_button_slide_duration = 0.02
	add_child(screen)
	screen.camera.position = Vector3(0, 0, 3)
	screen.camera.look_at(Vector3.ZERO)
	screen.camera.make_current()
	await _settle(0.5)
	var card: Card3D
	for candidate: Card3D in screen._base_positions:
		if candidate.card_data["id"] == "corpse":
			card = candidate
	var base_position: Vector3 = screen._base_positions[card]
	var base_rotation: Vector3 = screen._base_rotations[card]
	var base_scale: Vector3 = screen._base_scales[card]
	screen._open_detail_card(card)
	check(not screen._can_rotate_detail(), "collection rejects rotation during entry")
	await _settle(0.3)
	var center := screen.camera.unproject_position(card.global_position)
	_motion(center)
	await _settle()
	await _capture("collection-front")
	var start := card.global_transform
	_button(center, true)
	check(screen._detail_rotation.dragging and screen._detail_card == card, "pressing the open card starts a drag without closing it")
	_motion(center + Vector2(140, 45), Vector2(140, 45), true)
	check(not card.global_basis.is_equal_approx(start.basis), "horizontal and vertical dragging rotate the collection card")
	check(card.global_position.is_equal_approx(start.origin) and card.global_basis.get_scale().is_equal_approx(start.basis.get_scale()), "rotation preserves position and scale")
	await _capture("collection-angled")
	_motion(Vector2(-80, -80), Vector2(260, 0), true)
	check(card.global_basis.z.normalized().dot(screen.camera.global_basis.z.normalized()) < -0.8, "drag continues outside the card and turns through 180 degrees to its back")
	_button(Vector2(-80, -80), false)
	check(not screen._detail_rotation.dragging and screen._detail_card == card, "release outside stops rotation and keeps detail open")
	var released := card.global_basis
	_motion(Vector2(1000, 700), Vector2(90, 90))
	await _settle()
	check(card.global_basis.is_equal_approx(released), "idle mouse movement leaves the manually chosen orientation unchanged")
	await _capture("collection-back")
	center = screen.camera.unproject_position(card.global_position)
	_button(center, true)
	check(screen._detail_rotation.dragging, "the back of the collection card can be grabbed again")
	_motion(center, Vector2(TAU / screen._detail_rotation.radians_per_pixel, 0), true)
	check(card.global_basis.is_equal_approx(released), "a complete 360-degree turn returns to the same orientation without clamping")
	get_window().focus_exited.emit()
	check(not screen._detail_rotation.dragging, "window focus loss cancels the collection drag")
	_button(center, true)
	get_tree().paused = true
	check(not screen._detail_rotation.dragging, "pause cancels an active collection drag")
	get_tree().paused = false
	_button(center, true)
	screen.suspend_deck_input(true)
	check(not screen._detail_rotation.dragging, "suspending collection interaction cancels rotation")
	screen.suspend_deck_input(false)
	_button(center, true)
	screen._show_next_detail_card(1)
	check(not screen._detail_rotation.dragging and not screen._detail_rotation.has_rotated, "switching cards resets the gesture and its orientation")
	await _settle(0.3)
	check(card.position.is_equal_approx(base_position) and card.rotation_degrees.is_equal_approx(base_rotation) and card.scale.is_equal_approx(base_scale), "switching restores the original collection transform")
	await screen._close_detail_card()
	await screen._open_detail_card(card)
	await _settle()
	check(not screen._detail_rotation.has_rotated, "reopening a card starts with its normal front orientation")
	# Put the real button in front of the card, deliberately overlapping it.
	# This also avoids relying on the hub-specific button position with this
	# fixture's standalone camera and tests that rotation respects occlusion.
	screen._deck_button.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 0.15), card.global_position + screen.camera.global_basis.z * 0.25)
	await _settle()
	var button_shape := screen._deck_button.get_node("Area3D/CollisionShape3D") as CollisionShape3D
	var button_center := screen.camera.unproject_position(button_shape.global_position)
	check(screen._collection_card_under_mouse(button_center) == null and screen._detail_rotation.contains_pointer(card, screen.camera, button_center), "button fixture overlaps the card and wins front-most picking")
	_motion(button_center)
	await _settle()
	_button(button_center, true)
	await _settle()
	_button(button_center, false)
	check(not screen._detail_rotation.dragging, "Add to Deck remains a button instead of starting rotation")
	check(DeckManager.get_card_count("corpse") == 1, "the real Add to Deck click still adds exactly one copy")
	_button(Vector2(1240, 860), true)
	_button(Vector2(1240, 860), false)
	await _settle(0.3)
	check(screen._detail_card == null, "clicking the background still closes the collection detail")
	screen.queue_free()
	await _settle()


func _check_wall() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	add_child(camera)
	camera.make_current()
	var wall := (load("res://scenes/props/UpgradeWallCollection.tscn") as PackedScene).instantiate() as UpgradeWallCollection
	wall.camera = camera
	wall.detail_flight_duration = 0.12
	add_child(wall)
	wall.set_interaction_enabled(true)
	await _settle()
	var card: Card3D = wall._cards["clicker"]
	var original := card.global_transform
	wall.open_detail("clicker")
	check(not wall._can_rotate_detail(), "wall rejects rotation during entry")
	await _settle(0.3)
	var center := camera.unproject_position(card.global_position)
	_button(center, true)
	check(wall._detail_rotation.dragging and wall.is_detail_open(), "wall overlay starts rotation when its actual detail card is pressed")
	_motion(Vector2(-100, -100), Vector2(400, 20), true)
	_button(Vector2(-100, -100), false)
	await _settle()
	check(wall.is_detail_open() and card.global_basis.z.normalized().dot(camera.global_basis.z.normalized()) < -0.9, "wall keeps the freely rotated back visible after release outside")
	var released := card.global_basis
	_motion(Vector2(1100, 700), Vector2(100, 50))
	await _settle()
	check(card.global_basis.is_equal_approx(released), "the wall's camera-relative positioning does not overwrite manual rotation")
	await _capture("wall-back")
	_button(center, true)
	check(wall._detail_rotation.dragging, "wall detail can be grabbed from its back")
	get_window().focus_exited.emit()
	check(not wall._detail_rotation.dragging, "window focus loss cancels the wall drag")
	_button(center, true)
	get_tree().paused = true
	check(not wall._detail_rotation.dragging, "pause cancels an active wall drag")
	get_tree().paused = false
	_button(center, true)
	_motion(center, Vector2(90, 45), true)
	wall.close_detail()
	check(not wall._detail_rotation.dragging, "closing mid-drag cancels the wall gesture")
	await _settle(0.3)
	check(not wall.is_detail_open() and card.global_transform.is_equal_approx(original), "rotated wall card flies back to its exact original transform")
	wall.open_detail("clicker")
	await _settle(0.3)
	check(not wall._detail_rotation.has_rotated and card.global_basis.z.normalized().dot(camera.global_basis.z.normalized()) > 0.99, "reopening wall detail restores the front")
	_button(Vector2(1240, 860), true)
	_button(Vector2(1240, 860), false)
	await _settle(0.3)
	check(not wall.is_detail_open(), "wall background click still closes detail")
	wall.queue_free()
	camera.queue_free()
	await _settle()
