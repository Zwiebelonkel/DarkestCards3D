extends Node3D

var checks := 0
var failures := 0
var requests := 0
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with the isolated match feature test runner.")
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1280, 720)
	SettingsManager.set_fullscreen(false)
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	for index in range(21):
		CollectionManager.create_card_instance("corpse")
		if index < 20:
			DeckManager.add_card("corpse")
	CollectionManager.create_card_instance("clicker")
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0
	screen.hover_duration = 0.01
	screen.detail_duration = 0.04
	screen.detail_mouse_tilt_strength = 0
	screen.add_button_slide_duration = 0.03
	screen.slot_room_key_requested.connect(_on_requested)
	add_child(screen)
	await settle()
	_disable_card_picking()
	var combat := _card("corpse")
	await screen._open_detail_card(combat)
	check(screen._deck_button.disabled, "Full combat deck keeps its normal detail action disabled")
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	await settle()
	check(screen._detail_card == combat and screen._collection_refresh_pending, "Silent key acquisition waits for the current detail to close")
	check(requests == 0 and not screen.fly_sfx.playing, "Receiving the key does not request the door or play a reward sound")
	check(_card(CollectionManager.SLOT_ROOM_KEY_ID) == null, "Deferred discovery does not replace the inspected card underneath the pointer")
	await screen._close_detail_card()
	await settle()
	_disable_card_picking()
	var key := _card(CollectionManager.SLOT_ROOM_KEY_ID)
	check(key != null and not screen._collection_refresh_pending, "Key appears among the owned collection cards after closing detail")
	await screen._open_detail_card(key)
	await settle()
	check(screen._deck_button.visible and not screen._deck_button.disabled and DeckManager.is_full(), "Owned key action is available even with twenty cards in the deck")
	check(screen._deck_button.label_text == "Zur Tür" and screen._deck_button.label.text == "Zur Tür", "Rendered action text reads exactly Zur Tür")
	var button_shape := screen._deck_button.area.get_node("CollisionShape3D") as CollisionShape3D
	var pointer := screen.camera.unproject_position(button_shape.global_position)
	var query := PhysicsRayQueryParameters3D.create(screen.camera.project_ray_origin(pointer), screen.camera.project_ray_origin(pointer) + screen.camera.project_ray_normal(pointer) * 100)
	query.collide_with_areas = true
	var hit := screen.get_world_3d().direct_space_state.intersect_ray(query)
	check(get_viewport().get_visible_rect().has_point(pointer) and hit.get("collider") == screen._deck_button.area, "Camera-relative key button is on screen and reachable by its actual physics ray")
	var key_fits := true
	for corner: Vector3 in [Vector3(-0.4, -0.64, 0), Vector3(0.4, -0.64, 0), Vector3(-0.4, 0.64, 0), Vector3(0.4, 0.64, 0)]:
		key_fits = key_fits and get_viewport().get_visible_rect().has_point(screen.camera.unproject_position(key.to_global(corner)))
	check(key_fits, "Whole key card fits the standalone detail camera without clipping its title or bottom")
	await capture()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._deck_button.area.input_event.emit(screen.camera, click, Vector3.ZERO, Vector3.UP, 0)
	check(screen._slot_room_key_request_pending and requests == 0, "Button first closes the detail and reserves one door request")
	screen._on_add_to_deck_pressed()
	screen._on_deck_overview_pressed()
	screen._open_detail_card(_card("corpse"))
	await settle()
	check(requests == 1 and screen._detail_card == null and not screen._deck_fan_open, "Repeated clicks cannot duplicate the request or reopen a collection view")
	check(DeckManager.get_card_count(CollectionManager.SLOT_ROOM_KEY_ID) == 0 and DeckManager.is_full(), "Door action never puts the special key into the battle deck")
	check(not CollectionManager.is_slot_room_unlocked(), "Collection leaves unlocking to Main after the camera has turned")
	screen.finish_slot_room_key_request()
	check(not screen._slot_room_key_request_pending, "Main can release the request lock after the reveal or a rejection")
	await screen._open_detail_card(_card("corpse"))
	check(screen._deck_button.label.text == "DECK FULL" and screen._deck_button.disabled, "A regular card restores its own visible label and capacity rules")
	DeckManager.remove_card_at(0)
	screen._update_deck_button_state()
	screen._on_add_to_deck_pressed()
	check(DeckManager.is_full() and screen._deck_button.label.text == "DECK FULL", "Ordinary add-to-deck still works after using the key")
	await screen._close_detail_card()
	check(_card("clicker") == null and CollectionManager.is_clicker_unlocked(), "Other special cards are absent from the normal collection without losing their unlock effect")
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	screen.hide()
	var changed: Array[String] = [CollectionManager.SLOT_ROOM_KEY_ID]
	CollectionManager.collection_changed.emit(changed)
	await settle()
	check(screen._collection_refresh_pending, "A collection suspended while looking elsewhere remembers the silent reward refresh")
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	screen.show()
	await settle()
	_disable_card_picking()
	check(not screen._collection_refresh_pending and _card(CollectionManager.SLOT_ROOM_KEY_ID) != null, "Returning to the collection safely discovers the key")
	await screen._open_detail_card(_card(CollectionManager.SLOT_ROOM_KEY_ID))
	screen.suspend_deck_input(true)
	screen._on_add_to_deck_pressed()
	check(requests == 1 and not screen._slot_room_key_request_pending, "Suspended collection ignores the door action")
	screen.suspend_deck_input(false)
	screen.slot_room_key_requested.disconnect(_on_requested)
	# Keep this test outside current_scene so it can observe standalone navigation.
	remove_child(screen)
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen
	screen._on_add_to_deck_pressed()
	await settle(0.8)
	var hub := get_tree().current_scene as MainScene
	check(hub != null, "Standalone collection action loads the actual hub instead of dropping its request")
	check(not CollectionManager.has_meta("slot_room_key_focus_requested"), "Main consumes the transient standalone focus request")
	print("SLOT_ROOM_KEY_UI_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _on_requested() -> void:
	requests += 1


func _card(card_id: String) -> Card3D:
	for card: Card3D in screen._base_positions:
		if str(card.card_data.get("id", "")) == card_id:
			return card
	return null


func _disable_card_picking() -> void:
	for card: Card3D in screen._base_positions:
		card.area.input_ray_pickable = false
		card.area.collision_layer = 0


func capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("res://slot-room-key-detail.png")
