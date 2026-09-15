extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const PACK_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")

var _failures: Array[String] = []
var _checks := 0
var _collection_events: Array = []


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# The runner redirects every autoload save before this scene starts.
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use tests/run_match_feature_tests.ps1 with special_cards_test.tscn to isolate player saves.")
		get_tree().quit(1)
		return

	var clicker: Dictionary = CardDatabase.get_card("clicker")
	var upgrade: Dictionary = CardDatabase.get_card("clicker_upgrade")
	var fighter: Dictionary = CardDatabase.get_card("corpse")
	_expect(not clicker.is_empty() and not upgrade.is_empty(), "Both special cards are registered")
	_expect(not CardData.is_combat_card(clicker) and not CardData.is_combat_card(upgrade), "Special cards cannot fight")
	_expect(CardData.is_combat_card(fighter) and not CardData.is_combat_card({}), "Legacy combat cards keep working; empty data is rejected")
	var combat_pool := CardDatabase.get_combat_cards()
	_expect(combat_pool.has(fighter) and not combat_pool.has(clicker) and not combat_pool.has(upgrade), "AI pool includes only combat cards")
	_expect(CardDatabase.get_cards_by_rarity("common").has(clicker) and CardDatabase.get_cards_by_rarity("uncommon").has(upgrade), "Special cards belong to existing pack rarity pools")
	CollectionManager.collection = {"cards": {}, "instances": []}
	var all_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	CardDatabase.cards = [clicker, upgrade]
	CardDatabase.set_pack_rarity_weights({"common": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "clicker", "Pack selection can award the unlock card")
	CardDatabase.set_pack_rarity_weights({"uncommon": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "clicker_upgrade", "Pack selection can award upgrade copies")
	CardDatabase.set_pack_rarity_weights({"common": 1.0})
	var pack := PACK_SCENE.instantiate() as PackOpeningScreen
	add_child(pack)
	pack.set_process(false)
	pack.set_process_input(false)
	await pack._spawn_cards_inside_pack()
	var unlock_count := 0
	for card: Card3D in pack._card_stack:
		if str(card.card_data.get("id", "")) == "clicker":
			unlock_count += 1
	_expect(pack._card_stack.size() == pack.card_count and unlock_count == 1, "Real pack spawning reserves a single Clicker before collection and fills every paid slot")
	pack.queue_free()
	await get_tree().process_frame
	CardDatabase.cards = all_cards
	CardDatabase.set_pack_rarity_weights({})

	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.connect(func(ids: Array[String]) -> void: _collection_events.append(ids.duplicate()))
	_expect(not CollectionManager.is_clicker_unlocked() and CollectionManager.get_clicker_upgrade_count() == 0, "New collection starts with a locked clicker")
	var first_upgrade: Dictionary = CollectionManager.add_card("clicker_upgrade")
	CollectionManager.add_card("clicker_upgrade")
	_expect(not CollectionManager.is_clicker_unlocked() and CollectionManager.get_clicker_upgrade_count() == 2, "Upgrade copies stack without unlocking the clicker on their own")
	_expect((first_upgrade.get("effects", []) as Array).is_empty(), "Pack-awarded special cards get no random combat effects")
	CollectionManager.add_card("clicker")
	var events_before_duplicate := _collection_events.size()
	var duplicate: Dictionary = CollectionManager.add_card("clicker")
	_expect(duplicate.is_empty() and CollectionManager.create_card_instance("clicker").is_empty(), "Both award APIs reject a second unlock instance")
	_expect(CollectionManager.is_clicker_unlocked() and CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_clicker_upgrade_count() == 2, "The unlock card stays unique without awarding free upgrades")
	_expect(_collection_events.size() == events_before_duplicate, "Rejected duplicate awards do not emit collection changes")
	CardDatabase.cards = [clicker, upgrade]
	CardDatabase.set_pack_rarity_weights({"common": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "clicker_upgrade", "An owned unlock rerolls to another eligible card even when its rarity pool is exhausted")
	CardDatabase.cards = all_cards
	var all_rerolls_are_common := true
	for i in range(50):
		var rerolled: Dictionary = CardDatabase.get_random_card_for_current_pack()
		all_rerolls_are_common = all_rerolls_are_common and str(rerolled.get("id", "")) != "clicker" and str(rerolled.get("rarity", "")) == "common"
	_expect(all_rerolls_are_common, "Owned unlock exclusion preserves the selected rarity when eligible cards remain")
	CardDatabase.set_pack_rarity_weights({})
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	_expect(CollectionManager.is_clicker_unlocked() and CollectionManager.get_clicker_upgrade_count() == 2, "Unlock and stacked upgrades survive a reload")
	var injected_instance: Dictionary = CollectionManager.create_card_instance("clicker_upgrade", 1, [{"type": "poison", "damage": 10}])
	_expect((injected_instance.get("effects", []) as Array).is_empty(), "Special instance creation also rejects explicit combat effects")
	var merged := CardData.merge_card_and_instance(clicker, {"instance_id": "special_copy", "effects": [{"type": "cleave"}]})
	_expect(merged.get("instance_id") == "special_copy" and CardData.get_active_effects(merged).is_empty(), "Instance merging preserves identity without activating combat effects")
	var changed_before := _collection_events.size()
	CollectionManager.unlock_all_cards()
	CollectionManager.unlock_all_cards()
	_expect(CollectionManager.get_clicker_upgrade_count() == 5 and _collection_events.size() == changed_before + 2, "Bulk duplicate awards notify the clicker and count every upgrade")
	_expect(CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_instances_for_card("clicker").size() == 1, "Repeated bulk unlocks preserve the unique Clicker")
	_expect(not (_collection_events.back() as Array).has("clicker"), "Bulk awards only notify about cards that were actually added")

	DeckManager.battle_deck.clear()
	_expect(not DeckManager.can_add_card("clicker") and not DeckManager.add_card("clicker_upgrade"), "Owned specials cannot be manually added to a deck")
	_expect(DeckManager.add_card("corpse") and DeckManager.get_deck_cards() == ["corpse"], "Owned combat cards can still be added")
	DeckManager.battle_deck = ["clicker", "corpse", "clicker_upgrade", "missing_card"]
	_expect(DeckManager.get_deck_cards() == ["corpse"], "Deck payload reads strip special and unknown cards")
	DeckManager.save_deck()
	_expect(DeckManager.battle_deck == ["corpse"], "Saving normalizes the in-memory deck")
	var saved_deck := ConfigFile.new()
	saved_deck.set_value("deck", "cards", ["clicker_upgrade", "corpse", "clicker", "missing_card"])
	saved_deck.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	_expect(DeckManager.battle_deck == ["corpse"], "Legacy or edited deck saves cannot load special cards into combat")
	var remote_special := clicker.duplicate(true)
	remote_special["category"] = "combat"
	_expect(NetworkManager._sanitize_remote_card(remote_special).is_empty() and NetworkManager._sanitize_remote_card(upgrade).is_empty(), "Network deck validation uses database category and rejects disguised specials")
	_expect(not NetworkManager._sanitize_remote_card(fighter).is_empty(), "Network validation still accepts combat cards")

	CardUpgradeManager.upgrades.clear()
	CardUpgradeManager.add_attack("clicker", 5)
	CardUpgradeManager.add_health("clicker_upgrade", 5)
	_expect(not CardUpgradeManager.upgrades.has("clicker") and not CardUpgradeManager.upgrades.has("clicker_upgrade"), "Combat stat upgrades cannot be applied to special cards")
	_expect(not CardUpgradeManager.add_effect("clicker", {"type": "cleave"}) and CardUpgradeManager.get_free_effect_slots("clicker_upgrade") == 0, "Special cards have no purchasable combat effect slots")
	CardUpgradeManager.upgrades["clicker"] = {"attack_bonus": 99, "health_bonus": 99, "effects": [{"type": "cleave"}]}
	var unchanged := CardUpgradeManager.apply_upgrades("clicker", clicker)
	_expect(int(unchanged.get("attack", 0)) == 0 and int(unchanged.get("defense", 0)) == 0 and CardData.get_active_effects(unchanged).is_empty(), "Old or injected combat upgrades do not affect special cards")
	CardUpgradeManager.add_attack("corpse", 2)
	_expect(int(CardUpgradeManager.apply_upgrades("corpse", fighter).get("attack")) == int(fighter.get("attack")) + 2, "Ordinary combat upgrades retain their behavior")
	_test_unique_save_migration()

	if DisplayServer.get_name() != "headless":
		await _capture_visuals(clicker, upgrade)

	if _failures.is_empty():
		print("SPECIAL_CARD_TESTS: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _test_unique_save_migration() -> void:
	var first := CardData.create_instance("clicker")
	var second := CardData.create_instance("clicker", 1, [{"type": "poison"}])
	var third := CardData.create_instance("clicker")
	CollectionManager.collection = {
		"cards": {"clicker": 3, "clicker_upgrade": 1},
		"instances": [first, second, third, CardData.create_instance("clicker_upgrade")],
	}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	_expect(CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_clicker_upgrade_count() == 3 and CollectionManager.get_card_instances().size() == 4, "Existing duplicate unlocks become upgrades without deleting owned cards")
	var instances := CollectionManager.get_card_instances()
	_expect(str(instances[0].get("instance_id")) == str(first.get("instance_id")) and str(instances[1].get("instance_id")) == str(second.get("instance_id")) and str(instances[2].get("instance_id")) == str(third.get("instance_id")), "Save migration preserves all converted instance identities")
	_expect((instances[1].get("effects", []) as Array).is_empty(), "Converted upgrades lose legacy combat effects")
	CollectionManager.load_collection()
	_expect(CollectionManager.get_card_instances() == instances and CollectionManager.get_clicker_upgrade_count() == 3, "Conversion is persisted and repeated loads do not award more upgrades")
	CollectionManager.collection = {"clicker": 3, "clicker_upgrade": 2, "corpse": 1}
	CollectionManager.save_collection()
	CollectionManager.load_collection()
	_expect(CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_clicker_upgrade_count() == 4 and CollectionManager.get_card_instances().size() == 6, "Legacy quantity-only saves also preserve total ownership with one unlock card")
	var legacy_instances := CollectionManager.get_card_instances()
	var legacy_instance_ids: Array = legacy_instances.map(func(instance: Dictionary) -> String: return str(instance.get("instance_id", "")))
	CollectionManager.load_collection()
	var reloaded_instance_ids: Array = CollectionManager.get_card_instances().map(func(instance: Dictionary) -> String: return str(instance.get("instance_id", "")))
	_expect(reloaded_instance_ids == legacy_instance_ids and CollectionManager.get_amount("clicker") == 1 and CollectionManager.get_clicker_upgrade_count() == 4, "Legacy conversion and generated instance identities survive a second load")


func _capture_visuals(clicker: Dictionary, upgrade: Dictionary) -> void:
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
	camera.position = Vector3(0, 0, 3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.7
	camera.make_current()
	var cards: Array[Card3D] = []
	for data: Dictionary in [clicker, upgrade]:
		var card := CARD_SCENE.instantiate() as Card3D
		add_child(card)
		card.setup(data)
		card.description_label.skip()
		card.position.x = -0.55 if cards.is_empty() else 0.55
		cards.append(card)
		_expect(not card.attack_label.visible and not card.defense_label.visible and card.rarity_label.text == "SONDERKARTE", "Special card presentation hides combat values and labels its category")
		var art := card.card_image.material_override as StandardMaterial3D
		_expect(art != null and art.albedo_texture != null and art.albedo_texture.resource_path == str(data.get("image")), "Special card artwork loads into the real card material")
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png("res://special-cards.png") == OK, "Special card render saves for visual review")
	for card in cards:
		card.queue_free()
	await get_tree().process_frame
