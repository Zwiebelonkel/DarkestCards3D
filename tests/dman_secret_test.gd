extends Node3D

class FailingCollection extends "res://scripts/autoload/CollectionManager.gd":
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return false

var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_run.call_deferred()


func settle(seconds: float = 0.15) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://dman-" + label + ".png")


func key(code: Key, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	viewport.push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	viewport.push_input(event, true)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	SaveSlots.select_slot(1)
	SaveSlots.reset_slot(1)
	var data := CardDatabase.get_card("dman")
	check(data.get("name") == "DMAN" and data.get("rarity") == "secret" and data.get("attack") == 20 and data.get("defense") == 20, "DMAN has the requested name, rarity and stats")
	check(data.get("description") == "funny streamer from america. Loves indie games. Loves me. AMERICA MENTIONED!!", "description is verbatim")
	check(not data.has("artwork_scene") and ResourceLoader.exists(str(data.get("image", ""))), "DMAN uses a normal image")
	check(not CardDatabase._get_eligible_rewards().has(data) and float(data.get("reward_weight", 1)) == 0, "DMAN cannot drop from packs or the Jester")
	var before := CollectionManager.collection.duplicate(true)
	for invalid in ["", "d", "dma", "dmans", "hello"]:
		check(CollectionManager.redeem_wall_secret(invalid).is_empty(), "incomplete and wrong codes do not award cards")
	check(CollectionManager.collection == before, "wrong codes leave the collection unchanged")
	var failing := FailingCollection.new()
	add_child(failing)
	check(failing.redeem_wall_secret("dman").is_empty() and not failing.has_discovered_card("dman") and failing.get_amount("dman") == 0, "failed saves grant neither ownership nor discovery")
	failing.free()
	var instance := CollectionManager.redeem_wall_secret(" DMAN ")
	check(not instance.is_empty() and CollectionManager.get_amount("dman") == 1, "code tolerates letter case and surrounding spaces")
	CollectionManager.reload_profile()
	check(CollectionManager.redeem_wall_secret("dman").is_empty() and CollectionManager.get_amount("dman") == 1, "reload and resubmission cannot duplicate the reward")
	CollectionManager.collection["cards"].erase("dman")
	CollectionManager.collection["instances"] = []
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(CollectionManager.redeem_wall_secret("dman").is_empty(), "discovery survives losing the last copy")
	SaveSlots.select_slot(2)
	SaveSlots.reset_slot(2)
	check(not CollectionManager.has_discovered_card("dman") and not CollectionManager.redeem_wall_secret("dman").is_empty(), "another save slot has its own discovery")
	SaveSlots.select_slot(1)
	SaveSlots.reset_slot(1)
	CollectionManager.add_card("slot_room_key")
	CollectionManager.unlock_slot_room()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.mouse_tilt_strength = 0
	main.wakeup_blur_duration = 0.01
	main.room_travel_duration = 0.1
	main.rotation_duration = 0.01
	main.settle_duration = 0.01
	viewport.add_child(main)
	await settle(0.4)
	var wall: Node3D = main.secret_wall_input
	wall._submit("dman")
	check(CollectionManager.get_amount("dman") == 0, "wall is inactive outside the slot room")
	main._on_room_door_activated(main.hub_door)
	await settle(0.8)
	check(main._active_room == 1, "real room travel reaches the slot room")
	main._begin_turn(1)
	await settle(0.2)
	main._begin_turn(1)
	await settle(0.3)
	check(main._active_side == 2 and wall._enabled, "door-facing view enables the wall input")
	await capture("wall")
	var mouse := InputEventMouseMotion.new()
	mouse.position = wall.panel_to_screen(wall.entry.get_global_rect().get_center())
	viewport.push_input(mouse, true)
	await settle(0.7)
	check(main.screen_camera_focus._focused_screen == wall.focus_area, "hover focuses the wall text field")
	mouse.position = wall.panel_to_screen(wall.entry.get_global_rect().get_center())
	viewport.push_input(mouse, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = mouse.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)
		await get_tree().process_frame
	check(wall.entry.has_focus(), "projected wall click focuses the real LineEdit")
	for character in "dman":
		await key(character.to_upper().unicode_at(0), character.unicode_at(0))
	check(wall.entry.text == "dman" and main._active_side == 2 and not main._can_turn(), "D/A type letters without triggering room turns")
	await capture("input")
	await key(KEY_ENTER)
	await settle(0.85)
	check(CollectionManager.get_amount("dman") == 1 and is_instance_valid(wall._reveal_card), "Enter saves one card and starts the shared Secret reveal")
	if is_instance_valid(wall._reveal_card):
		check(wall._reveal_card._diorama_art == null and wall._reveal_card.card_data.get("instance_id") == CollectionManager.get_instances_for_card("dman")[0].get("instance_id"), "reveal shows the saved copy with flat artwork")
	await capture("reveal")
	await settle(3.1)
	check(not is_instance_valid(wall._reveal_card) and wall.entry.editable, "reveal ends and input becomes usable again")
	wall._submit("dman")
	check(CollectionManager.get_amount("dman") == 1 and not is_instance_valid(wall._reveal_card), "repeat entry cannot replay the award")
	wall.entry.grab_focus()
	await key(KEY_ESCAPE)
	check(not wall.entry.has_focus() and not main.pause_menu.visible and main._can_turn(), "Escape releases typing and restores turning without pausing")
	main._begin_turn(1)
	await settle(0.2)
	check(not wall._enabled and not wall.entry.has_focus(), "turning away disables wall input")
	main.queue_free()
	await settle()
	print("DMAN_SECRET_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
