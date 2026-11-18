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
	check(_card(CollectionManager.SLOT_ROOM_KEY_ID) == null and not screen._collection_refresh_pending, "Key stays out of the normal collection after closing detail")
	check(CollectionManager.get_unused_access_key_ids().has(CollectionManager.SLOT_ROOM_KEY_ID), "Owned unused key is available to the lower tray even with a full combat deck")
	check(requests == 0 and not CollectionManager.is_slot_room_unlocked(), "Acquiring a key never uses it or starts a door reveal")
	check(not DeckManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID) and DeckManager.is_full(), "Access keys cannot enter the battle deck")
	await screen._open_detail_card(_card("corpse"))
	check(screen._deck_button.label.text == "DECK FULL" and screen._deck_button.disabled, "A regular card restores its own visible label and capacity rules")
	DeckManager.remove_card_at(0)
	screen._update_deck_button_state()
	screen._on_add_to_deck_pressed()
	check(DeckManager.is_full() and screen._deck_button.label.text == "DECK FULL", "Ordinary add-to-deck still works after acquiring the key")
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
	check(not screen._collection_refresh_pending and _card(CollectionManager.SLOT_ROOM_KEY_ID) == null, "Returning to the collection preserves the key partition")
	check(CollectionManager.use_access_key(CollectionManager.SLOT_ROOM_KEY_ID), "Owned key can be activated independently of normal collection details")
	await settle()
	check(not CollectionManager.get_unused_access_key_ids().has(CollectionManager.SLOT_ROOM_KEY_ID), "Used key leaves the tray inventory")
	check(CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1 and CardData.is_upgrade_collection_card(CardDatabase.get_card(CollectionManager.SLOT_ROOM_KEY_ID)), "Used key remains owned in the special collection")
	check(_card(CollectionManager.SLOT_ROOM_KEY_ID) == null and requests == 0, "Activating a key never adds a normal collection card or starts its legacy detail action")
	screen.queue_free()
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
