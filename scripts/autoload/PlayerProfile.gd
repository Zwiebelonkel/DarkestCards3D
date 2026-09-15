extends Node
class_name PlayerProfile

## Read-only statistics for the current slot. Never call the collection/deck
## repair getters or the upgrade manager's entry-creating presentation getters.
static func snapshot() -> Dictionary:
	var profile := {
		"slot": SaveSlots.active_slot,
		"level": GameCurrency.level,
		"xp": GameCurrency.xp,
		"xp_required": GameCurrency.get_xp_required(),
		"coins": GameCurrency.get_coins(),
		"deck_count": 0,
		"deck_capacity": DeckManager.MAX_DECK_SIZE,
		"total_attack": 0,
		"total_health": 0,
		"deck_strength": 0,
		"average_strength": 0.0,
		"unique_deck_cards": 0,
		"effect_count": 0,
		"unique_effects": 0,
		"holo_deck_count": 0,
		"strongest_card_id": "",
		"strongest_strength": 0,
		"collection_count": 0,
		"combat_copies": 0,
		"combat_types": 0,
		"combat_catalog_count": 0,
		"special_types": 0,
		"special_catalog_count": 0,
		"holo_collection_count": 0,
		"stat_purchases": 0,
	}
	var catalog: Dictionary = CardDatabase.cards_by_id
	var collection: Dictionary = CollectionManager.collection
	var upgrades: Dictionary = CardUpgradeManager.upgrades
	var counts: Dictionary = collection.get("cards", {}) if collection.get("cards", {}) is Dictionary else {}
	if not collection.has("cards") and not collection.has("instances"):
		# Old saves were simply {card_id: count}. Reading them must not create
		# replacement instances or consume random numbers for new identities.
		counts = collection
	for card_id: Variant in catalog:
		var card: Dictionary = catalog[card_id]
		if CardDatabase.is_event_card(card):
			continue
		var combat := CardData.is_combat_card(card)
		var special := str(card.get("category", "")).to_lower() == "special"
		if combat:
			profile["combat_catalog_count"] += 1
		elif special:
			profile["special_catalog_count"] += 1
		var raw_count: Variant = counts.get(card_id, 0)
		var copies := maxi(int(raw_count), 0) if raw_count is int or raw_count is float else 0
		profile["collection_count"] += copies
		if copies > 0:
			if combat:
				profile["combat_copies"] += copies
				profile["combat_types"] += 1
			elif special:
				profile["special_types"] += 1
		if combat:
			var entry := _upgrade_entry(upgrades, str(card_id))
			var legacy_count := maxi(int(entry.get("attack_bonus", 0)), 0) + maxi(int(entry.get("health_bonus", 0)), 0)
			profile["stat_purchases"] += maxi(int(entry.get("stat_upgrade_count", legacy_count)), 0)

	var instances_by_id := {}
	var raw_instances: Variant = collection.get("instances", [])
	if raw_instances is Array:
		for raw: Variant in raw_instances:
			if not raw is Dictionary:
				continue
			var instance: Dictionary = raw
			var card_id := str(instance.get("card_id", ""))
			if not catalog.has(card_id) or CardDatabase.is_event_card(catalog[card_id]):
				continue
			if CardData.is_holo(instance):
				profile["holo_collection_count"] += 1
			var instance_id := str(instance.get("instance_id", ""))
			if not instance_id.is_empty():
				instances_by_id[instance_id] = instance

	var deck_types := {}
	var effect_types := {}
	var used_instances := {}
	for index in range(DeckManager.battle_deck.size()):
		var card_id: String = DeckManager.battle_deck[index]
		if not catalog.has(card_id):
			continue
		var base: Dictionary = catalog[card_id]
		if not CardData.is_combat_card(base) or CardDatabase.is_event_card(base):
			continue
		if int(profile["deck_count"]) >= DeckManager.MAX_DECK_SIZE:
			break
		var entry := _upgrade_entry(upgrades, card_id)
		var effects := _deck_effects(base, entry)
		var attack := int(base.get("attack", 0)) + int(entry.get("attack_bonus", 0))
		var health := int(base.get("defense", 0)) + int(entry.get("health_bonus", 0))
		var swap_stats := false
		for effect in effects:
			var effect_type := str(effect.get("type", ""))
			effect_types[effect_type] = true
			swap_stats = swap_stats or effect_type == "swap_stats"
		if swap_stats:
			# Card3D swaps once when the effect is present, even if duplicated.
			var original_attack := attack
			attack = health
			health = original_attack
		var strength := attack + health
		profile["deck_count"] += 1
		profile["total_attack"] += attack
		profile["total_health"] += health
		profile["deck_strength"] += strength
		profile["effect_count"] += effects.size()
		deck_types[card_id] = true
		if str(profile["strongest_card_id"]).is_empty() or strength > int(profile["strongest_strength"]) or (strength == int(profile["strongest_strength"]) and card_id < str(profile["strongest_card_id"])):
			profile["strongest_card_id"] = card_id
			profile["strongest_strength"] = strength
		if index < DeckManager.deck_instance_ids.size():
			var instance_id: String = DeckManager.deck_instance_ids[index]
			var instance: Dictionary = instances_by_id.get(instance_id, {})
			if not instance_id.is_empty() and not used_instances.has(instance_id) and str(instance.get("card_id", "")) == card_id:
				used_instances[instance_id] = true
				if CardData.is_holo(instance):
					profile["holo_deck_count"] += 1
	profile["unique_deck_cards"] = deck_types.size()
	profile["unique_effects"] = effect_types.size()
	if int(profile["deck_count"]) > 0:
		profile["average_strength"] = float(profile["deck_strength"]) / float(profile["deck_count"])
	return profile


static func _upgrade_entry(upgrades: Dictionary, card_id: String) -> Dictionary:
	var entry: Variant = upgrades.get(card_id, {})
	return entry if entry is Dictionary else {}


static func _deck_effects(base: Dictionary, entry: Dictionary) -> Array[Dictionary]:
	# Match DeckManager's type-upgrade payload, without calling apply_upgrades:
	# assigned instance effects are intentionally not part of combat there.
	var result: Array[Dictionary] = []
	var base_effects := CardData.get_active_effects(base)
	var raw_removed: Variant = entry.get("removed_base_effect_indices", [])
	var removed: Array = raw_removed if raw_removed is Array else []
	for index in range(base_effects.size()):
		if not removed.has(index):
			result.append(base_effects[index])
	var raw_upgrades: Variant = entry.get("effects", [])
	if raw_upgrades is Array:
		for effect: Variant in raw_upgrades:
			if result.size() >= CardData.MAX_EFFECTS_PER_CARD:
				break
			if not effect is Dictionary:
				continue
			var effect_type: Variant = effect.get("type", "")
			if effect_type is String and not effect_type.strip_edges().is_empty() and not CardData.is_innate_only_effect(effect_type):
				result.append(effect.duplicate(true))
	return result
