extends Node3D

const PROP_SCRIPT := preload("res://scripts/table/LocalTableProp.gd")
var checks := 0
var failures := 0
var changes: Array = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	var key_id := CollectionManager.SLOT_ROOM_KEY_ID
	var key := CardDatabase.get_card(key_id)
	var fighter := CardDatabase.get_card("corpse")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.connect(func(ids: Array[String]): changes.append(ids.duplicate()))
	check(key.get("name") == "Schlüsselkarte" and CardData.is_unique_unlock(key), "the named key is registered as a unique unlock")
	check(not CardData.is_combat_card(key) and not CardDatabase.get_combat_cards().has(key), "the key cannot enter the enemy combat pool")
	check(ResourceLoader.exists(str(key.get("image", ""))), "the key's original SVG art imports successfully")
	check(CardDatabase.get_all_cards().has(key) and not CardDatabase.get_cards_by_rarity(str(key["rarity"])).has(key), "collection/debug listing includes the secret, rarity reward pools exclude it")
	check(not CollectionManager.is_slot_room_unlocked() and not CollectionManager.unlock_slot_room() and changes.is_empty(), "a fresh collection cannot unlock the room without its key")
	var all_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	CardDatabase.cards = [key]
	check(CardDatabase.get_random_card().is_empty() and CardDatabase.get_random_card_by_rarity("legendary").is_empty() and CardDatabase.get_random_card_for_current_pack().is_empty(), "no random API can award the key even when it is the only card")
	CardDatabase.cards = [key, fighter]
	CardDatabase.set_pack_rarity_weights({"legendary": 1.0})
	check(CardDatabase.get_random_card().get("id") == "corpse" and CardDatabase.get_random_card_for_current_pack().get("id") == "corpse", "random selection and exhausted-rarity fallback choose an ordinary reward")
	CardDatabase.cards = all_cards
	CardDatabase.set_pack_rarity_weights({})
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1, 4)
	camera.make_current()
	var wrong_camera := Camera3D.new()
	add_child(wrong_camera)
	var coins_before := GameCurrency.get_coin_cents()
	for source in ["res://scenes/main/Main.tscn", "res://scenes/table/GameTable.tscn"]:
		CollectionManager.collection = {"cards": {}, "instances": []}
		changes.clear()
		var knife := _scene_knife(source)
		if knife == null:
			continue
		check(not knife._launched and CollectionManager.get_amount(key_id) == 0 and changes.is_empty(), source + ": spawning the knife does not reveal or grant a card")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = false
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		knife._on_input_event(camera, InputEventMouseMotion.new(), Vector3.ZERO, Vector3.ZERO, 0)
		check(not knife._launched and changes.is_empty(), source + ": right click, release and hover cannot trigger the secret")
		click.pressed = true
		knife.hide()
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		knife.show()
		get_tree().paused = true
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		get_tree().paused = false
		knife._on_input_event(wrong_camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		check(not knife._launched and changes.is_empty(), source + ": hidden/paused/other-camera clicks cannot grant the key")
		seed(708315)
		var next_random := randi()
		seed(708315)
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		check(randi() == next_random, source + ": throwing and receiving the key preserve shared battle randomness")
		check(knife._launched and knife.is_physics_processing() and not knife._pick_area.input_ray_pickable, source + ": a real throw starts flight and disables repeated picking")
		check(CollectionManager.get_amount(key_id) == 1 and changes == [[key_id]] and GameCurrency.get_coin_cents() == coins_before, source + ": one silent collection addition costs no Soul Coins")
		var instance := CollectionManager.get_instances_for_card(key_id)[0] as Dictionary
		check((instance.get("effects", []) as Array).is_empty() and not CollectionManager.is_slot_room_unlocked(), source + ": receiving a key neither grants combat effects nor opens its door early")
		knife._launch(camera)
		knife._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
		check(changes.size() == 1 and CollectionManager.get_instances_for_card(key_id) == [instance], source + ": repeated throw callbacks cannot duplicate or reroll the key")
		CollectionManager.load_collection()
		var reloaded := CollectionManager.get_instances_for_card(key_id)
		check(reloaded.size() == 1 and reloaded[0].get("instance_id") == instance["instance_id"] and CardData.is_holo(reloaded[0]) == CardData.is_holo(instance) and int(reloaded[0].get("level", 0)) == 1 and not CollectionManager.is_slot_room_unlocked(), source + ": the silently earned key survives reload while the room stays locked")
		knife.free()
		var later_knife := _scene_knife(source)
		later_knife._launch(camera)
		check(changes.size() == 1 and CollectionManager.get_card_instances() == reloaded, source + ": throwing a newly entered scene's knife preserves the already owned key")
		later_knife.free()
	var retained := CollectionManager.get_card_instances()
	check(not DeckManager.add_card(key_id) and CardUpgradeManager.get_free_effect_slots(key_id) == 0, "the owned key cannot enter a combat deck or buy combat effects")
	check(CollectionManager.add_card(key_id).is_empty() and CollectionManager.add_card_instance(CardData.create_instance(key_id)).is_empty(), "all award APIs preserve unique ownership")
	CollectionManager.collection["metadata"] = {"other_secret": "retained"}
	check(CollectionManager.unlock_slot_room() and CollectionManager.is_slot_room_unlocked() and CollectionManager.get_card_instances() == retained, "using the key unlocks its room and retains the exact card")
	var unlocked_save := CollectionManager.collection.duplicate(true)
	check(CollectionManager.unlock_slot_room() and CollectionManager.collection == unlocked_save and CollectionManager.collection["metadata"]["other_secret"] == "retained", "repeated use is idempotent and preserves unrelated metadata")
	CollectionManager.load_collection()
	check(CollectionManager.is_slot_room_unlocked() and CollectionManager.get_card_instances() == retained, "the unlocked room and key identity survive reload")
	CollectionManager.collection = {"corpse": 2}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	check(not CollectionManager.is_slot_room_unlocked() and CollectionManager.get_amount("corpse") == 2 and CollectionManager.get_card_instances().size() == 2, "quantity-only legacy saves keep cards and default to a locked room")
	CollectionManager.collection = {"cards": {"corpse": 1}, "instances": [CardData.create_instance("corpse")]}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	check(not CollectionManager.is_slot_room_unlocked() and CollectionManager.get_amount("corpse") == 1, "existing instance saves without metadata default to locked")
	var clutter := PROP_SCRIPT.new() as LocalTableProp
	clutter.name = "energy"
	add_child(clutter)
	clutter._launch(camera)
	check(clutter._launched and CollectionManager.get_amount(key_id) == 0, "throwing another table prop never grants the key")
	clutter.free()
	CollectionManager.unlock_all_cards()
	check(CollectionManager.get_amount(key_id) == 1 and not CollectionManager.is_slot_room_unlocked(), "explicit debug card unlock can grant the key without using it")
	CollectionManager.unlock_slot_room()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	check(not CollectionManager.is_slot_room_unlocked() and CollectionManager.get_amount(key_id) == 0, "game-reset collection state relocks the room and removes the key")
	if DisplayServer.get_name() != "headless":
		await _capture_key(key, camera)
	print("SLOT_ROOM_KEY_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _scene_knife(scene_path: String) -> LocalTableProp:
	# Inspect the actual scene's imported model and attached prop script without
	# booting a second whole Main or starting a match in this backend fixture.
	var packed := load(scene_path) as PackedScene
	var state := packed.get_state()
	for index in range(state.get_node_count()):
		if not str(state.get_node_path(index)).ends_with("decortaions/knife"):
			continue
		var prop := state.get_node_instance(index).instantiate() as Node3D
		var attached_script: Script
		for property_index in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index, property_index) == "script":
				attached_script = state.get_node_property_value(index, property_index) as Script
		check(attached_script == PROP_SCRIPT, scene_path + ": the shipped knife has the real reward-capable prop script")
		prop.set_script(attached_script)
		prop.name = "knife"
		add_child(prop)
		return prop as LocalTableProp
	check(false, scene_path + ": expected knife was found")
	return null


func _capture_key(data: Dictionary, camera: Camera3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.06, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	get_world_3d().environment = environment
	camera.position = Vector3(0, 0, 3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.8
	var card := preload("res://scenes/table/Card3D.tscn").instantiate() as Card3D
	add_child(card)
	card.setup(data)
	card.description_label.skip()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(not card.attack_label.visible and not card.defense_label.visible and card.rarity_label.text == "SONDERKARTE", "the rendered key hides combat values and identifies itself as a special card")
	check(get_viewport().get_texture().get_image().save_png("res://slot-room-key-card.png") == OK, "the actual key card render saves for review")
	card.queue_free()
	await get_tree().process_frame
