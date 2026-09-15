extends Node3D

const PACK_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")
const LABEL_SCRIPT := preload("res://scripts/card/NewCardLabel.gd")

var checks := 0
var failures := 0
var screen: PackOpeningScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run pack_new_label_test.tscn through the isolated match-feature runner.")
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1280, 900)
	GameCurrency.reset_progression(false)
	GameCurrency.coins = 100
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	var original_database := CardDatabase.cards.duplicate(true)
	# A single common type makes duplicate discovery deterministic while keeping
	# the actual pack roll, reveal, acquisition and cleanup paths in use.
	CardDatabase.cards.assign([CardDatabase.get_card("corpse").duplicate(true)])
	screen = PACK_SCENE.instantiate() as PackOpeningScreen
	add_child(screen)
	screen.pack_appear_duration = 0.05
	screen.pack_disappear_duration = 0.05
	screen.cards_fly_duration = 0.12
	screen.cards_vanish_duration = 0.05
	screen.base_shake_strength = 0.0
	screen.base_shake_rotation_strength = 0.0
	screen.rarity_camera_shake_multiplier = 0.0
	screen.rarity_pack_shake_multiplier = 0.0
	_setup_visual_environment()
	_test_animation()
	await _test_first_discovery_and_duplicate()
	await _test_known_and_consumed()
	await _test_collection_during_flip()
	CardDatabase.cards = original_database
	CardDatabase.set_pack_rarity_weights({})
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PACK_NEW_LABEL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_animation() -> void:
	var label := LABEL_SCRIPT.new()
	add_child(label)
	label.set_process(false)
	var frame_count: int = label.hframes * label.vframes
	check(label.texture.resource_path == "res://assets/cards/newlabel.png" and label.texture.get_width() == label.hframes * 64 and label.texture.get_height() == label.vframes * 64 and frame_count > 1, "NEW animation uses every 64 x 64 frame of the supplied sprite sheet")
	check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and not label.shaded, "NEW sprite faces the camera on both axes and keeps its pixel artwork readable")
	check(label.frame == 0, "animation starts on its first frame")
	label._process(1.0 / 24.0)
	check(label.frame == 0, "half a 12 FPS frame does not advance the animation")
	label._process(1.0 / 24.0)
	check(label.frame == 1, "one twelfth of a second advances one sprite frame")
	label._process(0.25)
	check(label.frame == 4 % frame_count, "a delayed render advances all elapsed animation frames")
	label._process(float(frame_count) / 12.0 + 0.001)
	check(label.frame == 4 % frame_count, "animation wraps and continues after a complete sprite-sheet loop")
	label.free()


func _open_pack(count: int) -> void:
	var data: Dictionary = PackDefinition.PACK_TYPES["basic"].duplicate(true)
	data["card_count"] = count
	data["rarity_weights"] = {"common": 1.0}
	check(screen.buy_pack("basic", data), "%d-card fixture pack can be purchased" % count)
	check(await _wait_until(func(): return not screen._pack_transitioning), "purchased pack entrance completes")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200, 200)
	screen._on_pack_top_input(screen.screen_flash_camera, press, Vector3.ZERO, Vector3.UP, 0)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + screen._drag_screen_axis * (screen._drag_screen_distance + 50.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	screen._input(motion)
	check(await _wait_until(func(): return screen._card_stack.size() == count), "pack produces the expected card stack")
	await get_tree().create_timer(0.75).timeout
	check(screen.find_children("NewLabel", "Sprite3D", true, false).is_empty(), "unrevealed cards do not expose a NEW badge")


func _collect() -> void:
	screen._collect_revealed_cards()
	check(await _wait_until(func(): return not screen._collecting_cards and not screen._pack_bought), "collection animation returns the screen to its purchase state")
	await get_tree().process_frame
	check(screen._revealed_cards.is_empty() and screen._pending_collection_card_ids.is_empty() and screen.find_children("NewLabel", "Sprite3D", true, false).is_empty(), "pack reset clears the pending discoveries and all label nodes")


func _test_first_discovery_and_duplicate() -> void:
	await _open_pack(2)
	var first: Card3D = screen._card_stack[0]
	var duplicate: Card3D = screen._card_stack[1]
	check(not CollectionManager.has_discovered_card("corpse"), "rolling an unseen type does not record acquisition")
	screen._reveal_top_card(first)
	check(first.get_meta("new_discovery", false) and first.get_node_or_null("NewLabel") == null, "first discovery is marked at reveal without a badge on the face-down card")
	await get_tree().create_timer(0.12).timeout
	check(first.get_node_or_null("NewLabel") == null, "the badge stays hidden during the initial face-down lift")
	check(await _wait_until(func(): return first.get_node_or_null("NewLabel") != null), "first discovery receives its NEW badge after the reveal animation")
	var label := first.get_node_or_null("NewLabel") as Sprite3D
	check(label != null and first.rotation_degrees.is_equal_approx(screen.revealed_rotation), "badge appears only once the card is face up")
	if label != null:
		check(label.position.is_equal_approx(Vector3(-0.396, 0.57, 0.06)) and is_equal_approx(label.pixel_size, 0.005), "badge is attached to the upper-left card corner at its intended size")
		var frame_before := label.frame
		check(await _wait_until(func(): return label.frame != frame_before, 500), "a revealed card badge animates during ordinary scene processing")
		await _snapshot(label)
	screen._reveal_top_card(first)
	check(first.find_children("NewLabel", "Sprite3D", true, false).size() == 1 and screen._pending_collection_card_ids.size() == 1, "repeated reveal callbacks cannot duplicate the badge or pending reward")
	screen._reveal_top_card(duplicate)
	check(not duplicate.get_meta("new_discovery", true), "the second copy in the same uncollected pack is already known for NEW detection")
	await get_tree().create_timer(0.8).timeout
	check(duplicate.get_node_or_null("NewLabel") == null and screen.find_children("NewLabel", "Sprite3D", true, false).size() == 1, "only the first copy of a newly drawn type receives a badge")
	check(not CollectionManager.has_discovered_card("corpse") and CollectionManager.get_amount("corpse") == 0, "reveal labels do not award cards or persist discovery before collection")
	screen._collect_revealed_cards()
	check(label != null and not label.visible, "the badge disappears immediately when collection starts")
	check(await _wait_until(func(): return not screen._collecting_cards and not screen._pack_bought), "first pack collection finishes")
	await get_tree().process_frame
	check(not is_instance_valid(label) and CollectionManager.get_amount("corpse") == 2 and CollectionManager.has_discovered_card("corpse"), "collection frees its badge and records both rewards plus permanent discovery")


func _test_known_and_consumed() -> void:
	await _open_pack(1)
	var owned: Card3D = screen._card_stack[0]
	screen._reveal_top_card(owned)
	await get_tree().create_timer(0.8).timeout
	check(not owned.get_meta("new_discovery", true) and owned.get_node_or_null("NewLabel") == null, "a type owned before this pack never receives a NEW badge")
	await _collect()
	# Emulate a save after the final owned copy was consumed. The persistence
	# tests separately exercise real fusion/offerings; this checks reveal policy.
	CollectionManager.collection["cards"].clear()
	CollectionManager.collection["instances"].clear()
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(CollectionManager.get_amount("corpse") == 0 and CollectionManager.has_discovered_card("corpse"), "fixture retains discovery after the last copy is gone and the save reloads")
	await _open_pack(1)
	var consumed: Card3D = screen._card_stack[0]
	screen._reveal_top_card(consumed)
	await get_tree().create_timer(0.8).timeout
	check(not consumed.get_meta("new_discovery", true) and consumed.get_node_or_null("NewLabel") == null, "redrawing a previously consumed type does not claim a new discovery")
	await _collect()


func _test_collection_during_flip() -> void:
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	await _open_pack(1)
	var card: Card3D = screen._card_stack[0]
	screen._reveal_top_card(card)
	check(card.get_meta("new_discovery", false), "fresh profile independently recognizes its first discovery")
	await _collect()
	await get_tree().create_timer(0.8).timeout
	check(not is_instance_valid(card) and screen.find_children("NewLabel", "Sprite3D", true, false).is_empty(), "collecting during the flip cannot create a late or orphaned NEW badge")


func _setup_visual_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.032, 0.041, 0.057)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 1.0)
	environment.ambient_light_energy = 0.75
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -34, 0)
	light.light_energy = 1.8
	add_child(light)
	var camera := screen.get_node("Camera3D") as Camera3D
	camera.position = Vector3(0.1, 1.7, 4.7)
	camera.look_at(screen.revealed_stack_position)
	camera.fov = 35.0
	camera.current = true
	screen.screen_flash_camera = camera
	screen.get_node("MenuNavigation/MenuButton").hide()


func _snapshot(label: Sprite3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	label.set_process(false)
	label.frame = 0
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://pack-new-label-revealed-frame0.png") == OK, "rendered NEW-card first-frame preview saved")
	label.frame = 1
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://pack-new-label-revealed-frame1.png") == OK, "rendered NEW-card second-frame preview saved")
	label.set_process(true)
