extends Node3D

var checks := 0
var failures := 0
var main: MainScene
var viewport: SubViewport


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS: " if condition else "FAIL: ") + message)


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	SettingsManager.set_fullscreen(false)
	Localization.set_locale("en")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	main.mouse_tilt_strength = 0.0
	viewport.add_child(main)
	_move_pointer(Vector2(5, 700))
	await settle(0.6)
	check(main.progression_areas.size() == 3, "Main exposes three distinct progression entrances")
	var market: ProgressionArea
	for area in main.progression_areas:
		check(area.door.locked and not area.open(), area.area_id + " cannot be entered without its card")
		check(not CollectionManager.unlock_area(area.area_id), area.area_id + " persistence cannot bypass access")
		if area.area_id == "black_market":
			market = area
		else:
			check(area.room_index == (2 if area.area_id == "graveyard" else 3), area.area_id + " routes to its physical Main room")
		check(not area.is_open() and area.find_children("*", "SubViewport", true, false).is_empty() and area.find_child("DestinationScreen", true, false) == null, area.area_id + " does not host an independent world or destination screen")
		var card_id := CollectionManager.get_area_unlock_card_id(area.area_id)
		CollectionManager.add_card(card_id)
		await settle()
		check(not area.door.locked, area.area_id + " acquisition refreshes the existing world door immediately")
		check(CollectionManager.get_amount(card_id) == 1 and DeckManager.battle_deck.is_empty(), area.area_id + " access neither consumes the key nor adds it to a battle deck")
	check(main.hub_door.locked, "new area cards do not unlock the independent slot-room door")
	check(market != null and market.room_index == 4, "Black Market routes to its physical Main room")
	if market != null:
		await _check_market(market)
	CollectionManager.load_collection()
	for area in main.progression_areas:
		check(CollectionManager.has_area_access(area.area_id), area.area_id + " access survives save/load")
	check(main._active_room == 0 and not get_tree().paused and main._can_turn(), "area access management preserves normal hub controls")
	main.queue_free()
	await settle()
	print("PROGRESSION_AREAS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_market(area: ProgressionArea) -> void:
	var room := main.get_node_or_null("BlackMarketRoom") as Node3D
	check(room != null and main.connected_rooms.has(4), "Black Market is a permanent connected Main room")
	check(room != null and room.get_node_or_null("OfferBoard") is BlackMarketBoard, "physical Black Market contains its daily offer board")
	check(area.shop_pool == "black_market" and not CollectionManager.get_black_market_offers().get("offers", []).is_empty(), "Black Market supplies daily stock from its independent shop pool")
	CollectionManager.add_card("dealer_license")
	check(is_equal_approx(area.get_shop_price(100.0), 100.0), "Black Market excludes normal-shop Dealer License discount")
	var saved := CollectionManager.collection.duplicate(true)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var changed: Array[String] = ["black_market_access", "graveyard_key", "basement_key"]
	CollectionManager.collection_changed.emit(changed)
	await settle()
	check(not area.is_open() and area.door.locked, "removing Black Market access locks its physical entrance")
	for other in main.progression_areas:
		check(other.door.locked and not other.open(), other.area_id + " persistent discovery does not override loss of its access card")
	CollectionManager.collection = saved
	CollectionManager.collection_changed.emit(changed)
	CollectionManager.save_collection()
	await settle()


func _move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
