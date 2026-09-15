extends Node3D

const PACK_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")
const RARITIES: Array[String] = ["uncommon", "rare", "epic", "legendary", "mythic"]
var checks := 0
var failures := 0
var collection_events: Array = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.connect(func(ids: Array[String]): collection_events.append(ids.duplicate()))
	check(CollectionManager.get_starting_hand_slot_count() == 0, "new collections have no selectable starting-hand slots")
	var all_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	var pool: Array[Dictionary] = [CardDatabase.get_card("corpse")]
	for tier in range(1, 6):
		var data := CardDatabase.get_card("starting_hand_%d" % tier)
		pool.append(data)
		check(not data.is_empty() and data.get("starting_hand_slots") == tier and data.get("rarity") == RARITIES[tier - 1], "tier %d has its progressive rarity and slot count" % tier)
		check(CardData.is_unique_unlock(data) and not CardData.is_combat_card(data) and not CardDatabase.get_combat_cards().has(data), "tier %d is a unique noncombat special" % tier)
		check(ResourceLoader.exists(str(data.get("image", ""))), "tier %d artwork is imported" % tier)
		check(CollectionManager.can_obtain_card(str(data["id"])) == (tier == 1), "only the first tier is initially obtainable")
	for tier in range(1, 6):
		var card_id := "starting_hand_%d" % tier
		if tier < 5:
			var future_id := "starting_hand_%d" % (tier + 1)
			check(CollectionManager.add_card(future_id).is_empty() and CollectionManager.roll_card_instance(future_id).is_empty() and CollectionManager.add_card_instance(CardData.create_instance(future_id)).is_empty(), "future tier cannot bypass progression through award, roll or stored-instance APIs")
		CardDatabase.cards = pool
		CardDatabase.set_pack_rarity_weights({RARITIES[tier - 1]: 1.0})
		check(CardDatabase.get_random_card_for_current_pack().get("id") == card_id, "the next tier can actually drop from its pack rarity")
		var reserved: Array[String] = [card_id]
		check(CardDatabase.get_random_card_for_current_pack(reserved).get("id") == "corpse", "reserved unique tier rerolls without skipping to a future tier")
		var pack := PACK_SCENE.instantiate() as PackOpeningScreen
		pack.card_count = 5
		add_child(pack)
		pack.set_process(false)
		pack.set_process_input(false)
		await pack._spawn_cards_inside_pack()
		var unlock_count := 0
		var copies: Array[Dictionary] = []
		for card: Card3D in pack._card_stack:
			var instance: Dictionary = card.get_meta("collection_instance")
			copies.append(instance)
			if str(card.card_data.get("id", "")) == card_id:
				unlock_count += 1
				var expected_label := "SONDERKARTE" + (" · HOLO" if CardData.is_holo(instance) else "")
				check(not card.attack_label.visible and not card.defense_label.visible and card.rarity_label.text == expected_label, "real card presentation hides combat stats and preserves the rolled Holo label for tier %d" % tier)
				check((instance.get("effects", []) as Array).is_empty(), "rolled progression card has no random combat effects")
		check(pack._card_stack.size() == 5 and unlock_count == 1, "five-card pack reserves exactly one next-tier unlock and fills every other slot")
		check(CollectionManager.get_starting_hand_slot_count() == tier - 1, "reveal alone does not unlock uncollected cards")
		for instance in copies:
			CollectionManager.add_card_instance(instance)
		check(CollectionManager.get_starting_hand_slot_count() == tier and CollectionManager.get_amount(card_id) == 1, "collecting the exact pack instances unlocks the next slot once")
		var event_count := collection_events.size()
		for instance in copies:
			check(CollectionManager.add_card_instance(instance).is_empty(), "duplicate pack collection cannot re-award an instance")
		check(CollectionManager.add_card(card_id).is_empty() and CollectionManager.create_card_instance(card_id).is_empty() and CollectionManager.roll_card_instance(card_id).is_empty() and collection_events.size() == event_count, "owned unlock stays unique across all award paths without extra change signals")
		check(not DeckManager.can_add_card(card_id) and CardUpgradeManager.get_free_effect_slots(card_id) == 0, "owned progression cards cannot enter combat decks or buy combat effects")
		CardUpgradeManager.add_attack(card_id, 5)
		check(not CardUpgradeManager.upgrades.has(card_id), "combat stat upgrades reject progression cards")
		CollectionManager.load_collection()
		check(CollectionManager.get_starting_hand_slot_count() == tier and CollectionManager.get_instances_for_card(card_id).size() == 1, "slot progression and unique instance survive reload")
		pack.queue_free()
		await get_tree().process_frame
	CardDatabase.cards = all_cards
	CardDatabase.set_pack_rarity_weights({})
	check(CollectionManager.get_starting_hand_slot_count() == 5, "all five tiers unlock exactly five slots")
	CollectionManager.collection["cards"].erase("starting_hand_3")
	check(CollectionManager.get_starting_hand_slot_count() == 2 and CollectionManager.can_obtain_card("starting_hand_3") and not CollectionManager.can_obtain_card("starting_hand_4"), "a missing earlier tier cannot be bypassed by owning later tiers")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	check(CollectionManager.get_starting_hand_slot_count() == 0 and CollectionManager.can_obtain_card("starting_hand_1") and not CollectionManager.can_obtain_card("starting_hand_2"), "resetting collection relocks progression and restores the first eligible drop")
	if DisplayServer.get_name() != "headless":
		await _capture_cards()
	print("STARTING_HAND_PROGRESSION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _capture_cards() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.06, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	get_world_3d().environment = environment
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-25, -20, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position.z = 4
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.make_current()
	for tier in range(1, 6):
		var card := preload("res://scenes/table/Card3D.tscn").instantiate() as Card3D
		add_child(card)
		card.setup(CardDatabase.get_card("starting_hand_%d" % tier))
		card.description_label.skip()
		card.position.x = (tier - 3) * 1.1
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://starting-hand-cards.png") == OK, "all five progression cards render for visual review")
