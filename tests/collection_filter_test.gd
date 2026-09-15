extends Node3D

const UPGRADE_IDS: Array[String] = [
	"clicker", "clicker_upgrade", "starting_hand_1", "starting_hand_2",
	"starting_hand_3", "starting_hand_4", "starting_hand_5",
]

var checks := 0
var failures := 0
var door_requests := 0
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.12) -> void:
	await get_tree().create_timer(seconds).timeout
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
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	var upgrade_catalog: Array[String] = []
	var regular_specials: Array[String] = []
	var combat_preserved := true
	for data: Dictionary in CardDatabase.get_all_cards():
		var is_upgrade := CardData.is_upgrade_collection_card(data)
		if is_upgrade:
			upgrade_catalog.append(str(data.id))
		elif str(data.get("category", "")) == "special":
			regular_specials.append(str(data.id))
		if CardData.is_combat_card(data):
			combat_preserved = combat_preserved and not is_upgrade
	upgrade_catalog.sort()
	var expected_catalog := UPGRADE_IDS.duplicate()
	expected_catalog.sort()
	check(upgrade_catalog == expected_catalog, "All seven upgrade types belong to the separate wall collection")
	check(regular_specials == [CollectionManager.SLOT_ROOM_KEY_ID], "The key is the only special type remaining in the normal collection")
	check(combat_preserved and not CardData.is_upgrade_collection_card({}), "All combat cards keep their normal collection category")
	for card_id in UPGRADE_IDS:
		CollectionManager.create_card_instance(card_id)
	CollectionManager.create_card_instance("clicker_upgrade")
	CollectionManager.create_card_instance("corpse")
	CollectionManager.create_card_instance("harald")
	CollectionManager.create_card_instance(CollectionManager.SLOT_ROOM_KEY_ID)
	var inventory_before := CollectionManager.collection.duplicate(true)
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0
	screen.detail_duration = 0.04
	screen.detail_mouse_tilt_strength = 0
	screen.add_button_slide_duration = 0.02
	screen.slot_room_key_requested.connect(func(): door_requests += 1)
	add_child(screen)
	await settle()
	_disable_desktop_picking()
	check(_shown_ids() == ["corpse", "harald", "slot_room_key"], "The actual collection creates only combat cards and the key")
	check(not screen.empty_label.visible, "Owned visible cards suppress the empty-collection message")
	check(CollectionManager.collection == inventory_before, "Separating displays leaves every owned copy and instance identity intact")
	check(CollectionManager.get_starting_hand_slot_count() == 5, "The hidden upgrade cards still unlock all five starting slots")
	check(DeckManager.add_card("corpse") and DeckManager.assign_starting_card(0, 4), "A combat card can still use the fifth unlocked starting slot")
	check(DeckManager.get_starting_deck_indices() == [-1, -1, -1, -1, 0], "Existing sparse starting-slot assignments remain available")
	var progress := (load("res://scenes/ui/LevelProgress.tscn") as PackedScene).instantiate() as LevelProgress
	screen.camera.add_child(progress)
	progress.set_enabled(false)
	check(is_equal_approx(progress.coins_per_click, 0.04), "The real clicker still applies its unlock and both upgrade copies")
	await screen._open_detail_card(_card(CollectionManager.SLOT_ROOM_KEY_ID))
	await settle()
	check(screen._deck_button.visible and not screen._deck_button.disabled and screen._deck_button.label.text == "Zur Tür", "The remaining key retains its visible and enabled door action")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._deck_button.area.input_event.emit(screen.camera, click, Vector3.ZERO, Vector3.UP, 0)
	await settle()
	check(door_requests == 1 and screen._detail_card == null, "The key's actual button still closes detail and requests the door once")
	check(CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 1 and DeckManager.get_card_count(CollectionManager.SLOT_ROOM_KEY_ID) == 0, "Using the key keeps ownership and does not put it in the battle deck")
	screen.finish_slot_room_key_request()
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	screen.refresh_collection()
	await settle()
	var saved_inventory: Dictionary = JSON.parse_string(JSON.stringify(inventory_before))
	check(CollectionManager.collection == saved_inventory and _shown_ids() == ["corpse", "harald", "slot_room_key"], "Save and reload preserve upgrade ownership and the display partition")
	# A player who only owns upgrades must see an empty normal collection.
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	for card_id: String in ["corpse", "harald", CollectionManager.SLOT_ROOM_KEY_ID]:
		CollectionManager.collection.cards.erase(card_id)
	CollectionManager.collection.instances = CollectionManager.collection.instances.filter(func(instance: Dictionary) -> bool: return UPGRADE_IDS.has(str(instance.card_id)))
	var changed: Array[String] = []
	CollectionManager.collection_changed.emit(changed)
	screen.refresh_collection()
	await settle()
	check(_shown_ids().is_empty() and screen.cards_root.get_child_count() == 0 and screen.empty_label.visible, "An upgrade-only inventory shows the actual empty state without hidden card rows")
	check(CollectionManager.get_starting_hand_slot_count() == 5 and is_equal_approx(progress.coins_per_click, 0.04), "Empty normal collection does not reset slot unlocks or clicker earnings")
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	await settle()
	check(_shown_ids() == ["slot_room_key"] and not screen.empty_label.visible, "Acquiring the key refreshes an upgrade-only collection into a visible key-only collection")
	screen.queue_free()
	await settle(0.3)
	print("COLLECTION_FILTER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _shown_ids() -> Array[String]:
	var ids: Array[String] = []
	for card: Card3D in screen._base_positions:
		ids.append(str(card.card_data.id))
	ids.sort()
	return ids


func _card(card_id: String) -> Card3D:
	for card: Card3D in screen._base_positions:
		if str(card.card_data.id) == card_id:
			return card
	return null


func _disable_desktop_picking() -> void:
	for card: Card3D in screen._base_positions:
		card.area.input_ray_pickable = false
		card.area.collision_layer = 0
