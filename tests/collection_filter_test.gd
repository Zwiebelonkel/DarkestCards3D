extends Node3D

const UPGRADE_IDS: Array[String] = [
	"clicker", "clicker_upgrade", "starting_hand_1", "starting_hand_2",
	"starting_hand_3", "starting_hand_4", "starting_hand_5",
]
const ACCESS_IDS: Array[String] = ["slot_room_key", "black_market_access", "graveyard_key", "basement_key"]

var checks := 0
var failures := 0
var screen: CollectionScreen
var wall: UpgradeWallCollection


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
	var special_catalog: Array[String] = []
	var regular_specials: Array[String] = []
	var combat_preserved := true
	for data: Dictionary in CardDatabase.get_all_cards():
		if str(data.get("category", "")) == "special":
			special_catalog.append(str(data.id))
		var is_upgrade := CardData.is_upgrade_collection_card(data)
		if is_upgrade:
			upgrade_catalog.append(str(data.id))
		elif str(data.get("category", "")) == "special":
			regular_specials.append(str(data.id))
		if CardData.is_combat_card(data):
			combat_preserved = combat_preserved and not is_upgrade
	upgrade_catalog.sort()
	special_catalog.sort()
	check(upgrade_catalog == special_catalog and upgrade_catalog.size() > UPGRADE_IDS.size(), "Every current special card and upgrade belongs to the separate wall collection")
	check(regular_specials.is_empty(), "No access key or other special type remains in the normal collection")
	check(combat_preserved and not CardData.is_upgrade_collection_card({}), "All combat cards keep their normal collection category")
	for card_id in UPGRADE_IDS:
		CollectionManager.create_card_instance(card_id)
	for card_id in ACCESS_IDS:
		CollectionManager.create_card_instance(card_id)
	CollectionManager.create_card_instance("clicker_upgrade")
	CollectionManager.create_card_instance("corpse")
	CollectionManager.create_card_instance("harald")
	var inventory_before := CollectionManager.collection.duplicate(true)
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0
	screen.detail_duration = 0.04
	screen.detail_mouse_tilt_strength = 0
	screen.add_button_slide_duration = 0.02
	add_child(screen)
	wall = (load("res://scenes/props/UpgradeWallCollection.tscn") as PackedScene).instantiate() as UpgradeWallCollection
	wall.camera = screen.camera
	wall.position = Vector3(100, 0, 0)
	add_child(wall)
	await settle()
	_disable_desktop_picking()
	check(_shown_ids() == ["corpse", "harald"], "The actual normal collection creates only the owned combat cards")
	var all_keys_on_wall := true
	for card_id in ACCESS_IDS:
		all_keys_on_wall = all_keys_on_wall and wall._cards.has(card_id)
	check(all_keys_on_wall and wall._cards.size() == UPGRADE_IDS.size() + ACCESS_IDS.size(), "The separate physical wall includes all four access keys alongside owned upgrades")
	check(not screen.empty_label.visible, "Owned visible cards suppress the empty-collection message")
	check(CollectionManager.collection == inventory_before, "Separating displays leaves every owned copy and instance identity intact")
	check(CollectionManager.get_starting_hand_slot_count() == 5, "The hidden upgrade cards still unlock all five starting slots")
	check(DeckManager.add_card("corpse") and DeckManager.assign_starting_card(0, 4), "A combat card can still use the fifth unlocked starting slot")
	check(DeckManager.get_starting_deck_indices() == [-1, -1, -1, -1, 0], "Existing sparse starting-slot assignments remain available")
	var progress := (load("res://scenes/ui/LevelProgress.tscn") as PackedScene).instantiate() as LevelProgress
	screen.camera.add_child(progress)
	progress.set_enabled(false)
	check(is_equal_approx(progress.coins_per_click, 0.04), "The real clicker still applies its unlock and both upgrade copies")
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	screen.refresh_collection()
	await settle()
	var saved_inventory: Dictionary = JSON.parse_string(JSON.stringify(inventory_before))
	check(CollectionManager.collection == saved_inventory and _shown_ids() == ["corpse", "harald"], "Save and reload preserve special-card ownership and the display partition")
	# A player who only owns upgrades must see an empty normal collection.
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	for card_id: String in ["corpse", "harald"]:
		CollectionManager.collection.cards.erase(card_id)
	CollectionManager.collection.instances = CollectionManager.collection.instances.filter(func(instance: Dictionary) -> bool: return UPGRADE_IDS.has(str(instance.card_id)) or ACCESS_IDS.has(str(instance.card_id)))
	var changed: Array[String] = []
	CollectionManager.collection_changed.emit(changed)
	screen.refresh_collection()
	await settle()
	check(_shown_ids().is_empty() and screen.cards_root.get_child_count() == 0 and screen.empty_label.visible, "An upgrade-only inventory shows the actual empty state without hidden card rows")
	check(CollectionManager.get_starting_hand_slot_count() == 5 and is_equal_approx(progress.coins_per_click, 0.04), "Empty normal collection does not reset slot unlocks or clicker earnings")
	CollectionManager.add_card("lucky_coin")
	await settle()
	check(_shown_ids().is_empty() and screen.empty_label.visible and wall._cards.has("lucky_coin"), "Acquiring another special card updates only the separate wall")
	screen.queue_free()
	wall.queue_free()
	await settle(0.3)
	print("COLLECTION_FILTER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _shown_ids() -> Array[String]:
	var ids: Array[String] = []
	for card: Card3D in screen._base_positions:
		ids.append(str(card.card_data.id))
	ids.sort()
	return ids


func _disable_desktop_picking() -> void:
	for card: Card3D in screen._base_positions:
		card.area.input_ray_pickable = false
		card.area.collision_layer = 0
