extends Node

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	GameCurrency.set_process(false)
	check(CollectionManager.get_fusion_requirement() == 5, "Default fusion still requires five")
	check(CollectionManager.get_soulcoin_multiplier() == 1.0 and CollectionManager.get_xp_multiplier() == 1.0, "New profiles have no bonuses")
	for id: String in ["golden_clicker", "auto_clicker", "fusion_upgrade_2", "soulcoin_boost_2", "xp_boost_2"]:
		check(not CollectionManager.can_obtain_card(id) and CollectionManager.add_card(id).is_empty(), "Missing prerequisite rejects award: " + id)
	# Edited saves cannot activate a late tier without its whole chain.
	CollectionManager.collection = {"cards": {"xp_boost_4": 1, "fusion_upgrade_2": 1, "auto_clicker": 1}, "instances": []}
	check(not CollectionManager.has_unlock("xp_boost_4") and CollectionManager.get_xp_multiplier() == 1.0, "Late XP tier does not bypass missing prerequisites")
	check(CollectionManager.get_fusion_requirement() == 5 and CollectionManager.get_auto_click_rate() == 0.0, "Injected fusion and auto unlocks are inactive without prerequisites")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.add_card("clicker")
	CollectionManager.add_card("clicker_upgrade")
	CollectionManager.add_card("golden_clicker")
	CollectionManager.add_card("golden_clicker")
	CollectionManager.add_card("auto_clicker")
	check(is_equal_approx(CollectionManager.get_manual_click_bonus(), 0.10) and CollectionManager.get_clicker_upgrade_count() == 1, "Golden copies stack alongside the original Clicker Upgrade")
	check(is_equal_approx(CollectionManager.get_auto_click_rate(), 0.02), "Auto Clicker reads its configured rate")
	for prefix: String in ["soulcoin_boost_", "xp_boost_"]:
		var expected := [1.02, 1.05, 1.10, 1.15]
		for index in range(4):
			var id := prefix + str(index + 1)
			check(not CollectionManager.add_card(id).is_empty(), "Ordered chain can unlock: " + id)
			var multiplier := CollectionManager.get_soulcoin_multiplier() if prefix.begins_with("soulcoin") else CollectionManager.get_xp_multiplier()
			check(is_equal_approx(multiplier, expected[index]), "Only highest tier applies: " + id)
			check(CollectionManager.add_card(id).is_empty(), "Unique tier rejects a duplicate: " + id)
	CollectionManager.add_card("lucky_coin")
	CollectionManager.add_card("dealer_license")
	check(is_equal_approx(CollectionManager.get_lucky_coin_bonus(), 0.05), "Lucky Coin relative bonus reads configuration")
	check(is_equal_approx(CollectionManager.get_shop_discount(), 0.10) and CollectionManager.get_shop_discount("black_market") == 0.0, "Dealer License only discounts normal shops")
	for tier in range(1, 3):
		CollectionManager.add_card("fusion_upgrade_" + str(tier))
		var required := 5 - tier
		check(CollectionManager.get_fusion_requirement() == required, "Fusion tier replaces the previous requirement")
		var inputs: Array[String] = []
		for index in range(required):
			inputs.append(str(CollectionManager.add_card("corpse")["instance_id"]))
		var before := CollectionManager.get_card_instances().size()
		check(not CollectionManager.validate_fusion(inputs.slice(1)).get("ok", false), "Reduced fusion still requires exact count")
		var result := CollectionManager.fuse_card_instances(inputs)
		check(result.get("ok", false) and result.get("required_cards", 0) == required, "Real fusion succeeds with reduced count")
		check(CollectionManager.get_card_instances().size() == before - required + 1, "Fusion consumes exactly the selected reduced count")
		check(not CollectionManager.fuse_card_instances(inputs).get("ok", false), "Repeated strike cannot grant a second reward")
	for area_id: String in ["black_market", "graveyard", "basement"]:
		check(not CollectionManager.has_area_access(area_id) and not CollectionManager.unlock_area(area_id), "Area starts locked: " + area_id)
		var key_id := CollectionManager.get_area_unlock_card_id(area_id)
		CollectionManager.add_card(key_id)
		check(not CollectionManager.has_area_access(area_id), "Owning an unused key does not open its area: " + area_id)
		check(CollectionManager.use_access_key(key_id) and CollectionManager.has_area_access(area_id), "Explicit key use opens its matching area: " + area_id)
		check(CollectionManager.get_amount(key_id) == 1, "Area access keeps its key")
	check(not CollectionManager.has_area_access("unknown") and not CollectionManager.unlock_area("unknown"), "Unknown areas fail closed")
	CollectionManager.collection["metadata"]["unrelated"] = "preserved"
	CollectionManager.save_collection()
	var expected_cards := CollectionManager.get_owned_cards()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	check(CollectionManager.get_owned_cards() == JSON.parse_string(JSON.stringify(expected_cards)), "Every permanent unlock and stacked Golden Clicker survives reload")
	check(CollectionManager.get_fusion_requirement() == 3 and is_equal_approx(CollectionManager.get_soulcoin_multiplier(), 1.15) and is_equal_approx(CollectionManager.get_xp_multiplier(), 1.15), "Reload restores active upgrade effects")
	check(CollectionManager.collection["metadata"]["unrelated"] == "preserved", "Upgrade saves preserve unrelated metadata")
	for area_id: String in ["black_market", "graveyard", "basement"]:
		check(CollectionManager.has_area_access(area_id), "Area remains accessible after restart: " + area_id)
	for id: String in expected_cards:
		var data := CardDatabase.get_card(id)
		if data.get("permanent_upgrade", false):
			check(not DeckManager.can_add_card(id) and not CardData.is_combat_card(data), "New permanent card is excluded from combat: " + id)
	# Cyclic prerequisites fail closed instead of overflowing recursion.
	var old_requires: Array = CardDatabase.cards_by_id["clicker"].get("requires", [])
	CardDatabase.cards_by_id["clicker"]["requires"] = ["auto_clicker"]
	check(not CollectionManager.has_unlock("auto_clicker") and not CollectionManager.can_obtain_card("golden_clicker"), "Cyclic prerequisite data fails closed")
	CardDatabase.cards_by_id["clicker"].erase("requires")
	if not old_requires.is_empty():
		CardDatabase.cards_by_id["clicker"]["requires"] = old_requires
	await _check_fusion_ui()
	print("PROGRESSION_UPGRADES_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_fusion_ui() -> void:
	CollectionManager.collection = {"cards": {}, "instances": []}
	var selected: Array[String] = []
	for index in range(5):
		selected.append(str(CollectionManager.add_card("corpse")["instance_id"]))
	var forge := FusionWorkbench.new()
	add_child(forge)
	forge.set_process(false)
	forge.selected_instance_ids = selected
	forge.refresh_collection()
	check(forge._slot_cards.size() == 5 and forge._slot_bases_root.get_child_count() == 5, "Workbench begins with five physical slots")
	for tier in range(1, 3):
		CollectionManager.add_card("fusion_upgrade_" + str(tier))
		forge.refresh_collection()
		var required := 5 - tier
		check(forge.selected_instance_ids.size() == required and forge._slot_cards.size() == required and forge._slot_bases_root.get_child_count() == required, "Open workbench adapts selection and physical slots to the reduced requirement")
		check(bool(forge._buttons["fuse"]["enabled"]) and forge._buttons["fuse"]["label"].text.contains("%d / %d" % [required, required]), "Fusion button displays and accepts the upgraded count")
	forge.queue_free()
	await get_tree().process_frame
