extends Node

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(CardUpgradeManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	var lava := EffectDatabase.get_effect("lava")
	var armor := EffectDatabase.get_effect("armor")
	check(not lava.is_empty() and not armor.is_empty(), "The real effect catalog supplies Lava and armor")
	var lava_cards: Array[String] = []
	for card in CardDatabase.get_all_cards():
		if CardData.has_effect(card, "lava"):
			lava_cards.append(str(card.get("id", "")))
	check(lava_cards == ["piss"], "Only Pisse-Eimer has authored Lava")
	var safe_rolls := true
	seed(7919)
	for index in range(500):
		var random_effect := EffectDatabase.get_random_effect_weighted()
		safe_rolls = safe_rolls and not random_effect.is_empty() and str(random_effect.get("type", "")) != "lava"
		for effect in EffectDatabase.roll_effects():
			safe_rolls = safe_rolls and str(effect.get("type", "")) != "lava"
	check(safe_rolls, "Repeated weighted choices and multi-effect rolls never award Lava")
	var ordinary := CardDatabase.get_card("corpse")
	var bucket := CardDatabase.get_card("piss")
	for card_id in ["corpse", "piss"]:
		var instance := CardData.create_instance(card_id, 3, [lava, armor], true)
		check(instance.get("effects") == [armor] and instance.get("is_holo") == true and instance.get("level") == 3, "Instance creation removes only extra Lava for " + card_id)
		var rolled := CollectionManager.roll_card_instance(card_id, 2, [lava, armor])
		check(rolled.get("effects") == [armor], "Explicit acquisition effects cannot inject Lava into " + card_id)
		var base := CardDatabase.get_card(card_id)
		var merged := CardData.merge_card_and_instance(base, instance)
		check(CardData.has_effect(merged, "lava") == (card_id == "piss") and CardData.has_effect(merged, "armor"), "Merge preserves only authored Lava and valid extras for " + card_id)
		check(not CardUpgradeManager.add_effect(card_id, lava), "Even the Lava owner cannot buy a second Lava upgrade")
	var legacy_instance := {
		"instance_id": "legacy-lava-boundary", "card_id": "corpse", "level": 4,
		"effects": [lava, armor], "active_effects": [lava, armor], "is_holo": true,
		"kept_metadata": {"origin": "test-pack", "number": 17}
	}
	var stored := CollectionManager.add_card_instance(legacy_instance)
	check(stored.get("effects") == [armor] and stored.get("active_effects") == [armor], "Previously revealed reward storage filters both effect arrays")
	check(stored.get("kept_metadata") == legacy_instance.get("kept_metadata") and stored.get("instance_id") == legacy_instance.get("instance_id"), "Reward sanitation preserves identity and arbitrary metadata")
	check(legacy_instance.get("effects") == [lava, armor], "Acquisition never mutates the caller's reward dictionary")
	CollectionManager.collection = {"cards": {"corpse": 1}, "instances": [legacy_instance.duplicate(true)]}
	check(CollectionManager.save_collection(), "Write the isolated old collection fixture")
	CollectionManager.load_collection()
	var loaded: Dictionary = CollectionManager.get_instances_for_card("corpse")[0]
	check(loaded.get("effects") == [armor] and loaded.get("active_effects") == [armor], "Loading an old collection strips previously rolled Lava")
	check(loaded.get("instance_id") == legacy_instance.get("instance_id") and loaded.get("kept_metadata") == JSON.parse_string(JSON.stringify(legacy_instance.get("kept_metadata"))) and CardData.is_holo(loaded), "Legacy sanitation keeps copy identity, metadata and holographic state")
	var remote := ordinary.duplicate(true)
	remote["effects"] = [lava, armor]
	check(not CardData.has_effect(NetworkManager._sanitize_remote_card(remote), "lava") and CardData.has_effect(NetworkManager._sanitize_remote_card(remote), "armor"), "Network rejects injected Lava but accepts a normal effect")
	remote["active_effects"] = [lava, armor]
	check(not CardData.has_effect(NetworkManager._sanitize_remote_card(remote), "lava"), "Network also rejects active_effects injection")
	remote = bucket.duplicate(true)
	remote["effects"] = [lava, lava, armor]
	var remote_bucket := NetworkManager._sanitize_remote_card(remote)
	check(CardData.get_active_effects(remote_bucket).size() == 2 and CardData.has_effect(remote_bucket, "lava") and CardData.has_effect(remote_bucket, "armor"), "Network keeps one canonical bucket Lava and skips duplicates without losing armor")
	remote["effects"] = []
	check(not CardData.has_effect(NetworkManager._sanitize_remote_card(remote), "lava"), "An explicitly removed innate Lava is not reintroduced online")
	var legacy := ConfigFile.new()
	legacy.set_value("corpse", "effects", [lava, armor])
	legacy.set_value("corpse", "attack_bonus", 3)
	legacy.set_value("corpse", "health_bonus", 2)
	legacy.set_value("piss", "effects", [lava, armor])
	check(legacy.save(CardUpgradeManager.SAVE_PATH) == OK, "Write the isolated legacy upgrade fixture")
	CardUpgradeManager.load_upgrades()
	check(CardUpgradeManager.get_upgrade_effects("corpse") == [armor] and CardUpgradeManager.get_upgrade_effects("piss") == [armor], "Saved extra Lava is removed before slot capacity is applied")
	check(CardUpgradeManager.get_effect_roll_count("corpse") == 0 and CardUpgradeManager.get_stat_upgrade_count("corpse") == 5, "Legacy saves start a separate roll streak while retaining inferred stat progress")
	check(CardData.has_effect(CardUpgradeManager.apply_upgrades("piss", bucket), "lava"), "Loading extra-effect sanitation preserves the bucket's innate Lava")
	check(CardUpgradeManager.remove_effect_at("corpse", "upgrade", 0) and CardUpgradeManager.get_upgrade_effects("corpse").is_empty(), "Visible effect indices still remove the intended effect after legacy sanitation")
	print("LAVA_REWARD_BOUNDARY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
