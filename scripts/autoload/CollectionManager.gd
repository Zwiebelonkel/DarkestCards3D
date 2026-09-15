extends Node

signal collection_changed(card_ids: Array[String])
signal card_seen(card_id: String)

var SAVE_PATH: String:
	get:
		return SaveSlots.get_save_path("collection.json")
const SLOT_ROOM_KEY_ID := "slot_room_key"
const USB_SECRET_CARD_ID := "usb_stick"
const CIGARETTES_SECRET_CARD_ID := "cigarettes"
const MOEWENMILCH_SECRET_CARD_ID := "moewenmilch"
const PROP_SECRET_CARD_IDS: Array[String] = [USB_SECRET_CARD_ID, CIGARETTES_SECRET_CARD_ID, MOEWENMILCH_SECRET_CARD_ID]
const PROP_SECRET_THROW_REQUIREMENTS := {"usb_stick": 50, "cigarettes": 80, "moewenmilch": 150}
const JESTER_OFFERING_CARD_IDS: Array[String] = ["chick", "harald"]
const FUSION_REQUIRED_CARDS := 5
const BLACK_MARKET_OFFER_COUNT := 4
const BLACK_MARKET_PRICES_CENTS := {
	"common": 1200, "uncommon": 2200, "rare": 4000, "epic": 7500,
	"legendary": 14000, "mythic": 26000, "exotic": 50000,
}
const FUSION_RARITIES: Array[String] = [
	"common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic",
]
const STARTING_HAND_CARD_IDS: Array[String] = [
	"starting_hand_1", "starting_hand_2", "starting_hand_3", "starting_hand_4", "starting_hand_5",
]

var collection := {
	"cards": {},
	"instances": [],
	"metadata": {"slot_room_unlocked": false},
}
var _fusion_in_progress := false
var _jester_offering_in_progress := false
var _black_market_purchase_in_progress := false
var _prop_secret_discovery_in_progress := false


func _ready():
	load_collection()


func clear_profile_state() -> void:
	# A slot boundary must discard permanent unlock metadata as well as cards.
	# The controller clears all managers before publishing any load signals.
	collection = {"cards": {}, "instances": [], "metadata": {"slot_room_unlocked": false}}
	_fusion_in_progress = false
	_jester_offering_in_progress = false
	_black_market_purchase_in_progress = false
	_prop_secret_discovery_in_progress = false
	if has_meta("slot_room_key_focus_requested"):
		remove_meta("slot_room_key_focus_requested")


func reload_profile() -> void:
	clear_profile_state()
	load_collection()


func load_collection():
	_migrate_legacy_collection()
	var previous_collection := collection.duplicate(true)
	if not FileAccess.file_exists(SAVE_PATH):
		save_collection()
		_notify_collection_loaded(previous_collection)
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not read collection: " + error_string(FileAccess.get_open_error()))
		return
	collection = JSON.parse_string(file.get_as_text())
	file.close()

	if collection == null or typeof(collection) != TYPE_DICTIONARY:
		collection = {"cards": {}, "instances": []}
		_notify_collection_loaded(previous_collection)
		return

	_migrate_legacy_collection()
	_sanitize_loaded_instance_effects()
	# Preserve old ownership in memory; the next ordinary save persists the
	# history without turning a read-only journal visit into a disk migration.
	_seed_card_discoveries(collection)
	if _convert_duplicate_clickers():
		save_collection()
	_notify_collection_loaded(previous_collection)


func _notify_collection_loaded(previous_collection: Dictionary) -> void:
	# JSON loads normalize integers to floats. An unchanged reload must not
	# masquerade as another card award or replay acquisition listeners.
	if JSON.parse_string(JSON.stringify(previous_collection)) == JSON.parse_string(JSON.stringify(collection)):
		return
	var changed: Array[String] = []
	for card_id: Variant in previous_collection.get("cards", {}).keys() + get_owned_cards().keys():
		if not changed.has(str(card_id)):
			changed.append(str(card_id))
	collection_changed.emit(changed)


func save_collection() -> bool:
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	if _save_collection_snapshot(next_collection):
		collection = next_collection
		return true
	push_error("Could not save collection: " + SAVE_PATH)
	return false


func add_card(card_id: String) -> Dictionary:
	var instance := create_card_instance(card_id)
	if instance.is_empty():
		return {}
	save_collection()
	var changed_card_ids: Array[String] = [card_id]
	collection_changed.emit(changed_card_ids)
	return instance


func discover_usb_secret(random: RandomNumberGenerator) -> Dictionary:
	return discover_prop_secret(USB_SECRET_CARD_ID, random)


func get_prop_secret_throw_count(card_id: String) -> int:
	if not PROP_SECRET_THROW_REQUIREMENTS.has(card_id):
		return 0
	var metadata: Variant = collection.get("metadata", {})
	if not metadata is Dictionary:
		return 0
	var counts: Variant = metadata.get("prop_secret_throws", {})
	if not counts is Dictionary:
		return 0
	var count: Variant = counts.get(card_id, 0)
	if not (count is int or count is float) or not is_finite(float(count)):
		return 0
	return clampi(int(count), 0, int(PROP_SECRET_THROW_REQUIREMENTS[card_id]))


func discover_prop_secret(card_id: String, random: RandomNumberGenerator) -> Dictionary:
	# Discovery history survives losing the last copy, so throwing a new table's
	# props cannot farm these Secrets. Existing ownership also covers older saves.
	if card_id not in PROP_SECRET_CARD_IDS or random == null or _prop_secret_discovery_in_progress or has_discovered_card(card_id) or not can_obtain_card(card_id):
		return {}
	if not collection.get("cards") is Dictionary or not collection.get("instances") is Array:
		return {}
	var random_state := random.state
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	if not next_collection.get("metadata") is Dictionary:
		next_collection["metadata"] = {}
	var metadata: Dictionary = next_collection["metadata"]
	if not metadata.get("prop_secret_throws") is Dictionary:
		metadata["prop_secret_throws"] = {}
	var required := int(PROP_SECRET_THROW_REQUIREMENTS[card_id])
	var count := mini(get_prop_secret_throw_count(card_id) + 1, required)
	metadata["prop_secret_throws"][card_id] = count
	var instance: Dictionary = {}
	if count >= required:
		instance = {
			"instance_id": "%s_%s_%d" % [card_id, Time.get_unix_time_from_system(), random.randi()],
			"card_id": card_id,
			"level": 1,
			"effects": [],
			"is_holo": CardData.roll_holo(random.randi_range(0, CardData.HOLO_ROLL_SIDES - 1)),
		}
		next_collection["instances"].append(instance.duplicate(true))
		next_collection["cards"][card_id] = int(next_collection["cards"].get(card_id, 0)) + 1
		_record_card_discovery(next_collection, card_id)
	# Persist the exact instance and permanent discovery together before any
	# reveal listener runs. Cosmetic prop interactions use only their own RNG.
	_prop_secret_discovery_in_progress = true
	if not _save_collection_snapshot(next_collection, ".prop-secret.tmp"):
		_prop_secret_discovery_in_progress = false
		random.state = random_state
		return {}
	collection = next_collection
	if not instance.is_empty():
		var changed: Array[String] = [card_id]
		collection_changed.emit(changed)
	_prop_secret_discovery_in_progress = false
	return instance.duplicate(true)


func add_card_instance(instance: Dictionary) -> Dictionary:
	# Pack reveals already own their roll. Store that exact copy, never roll
	# again when the player finally collects it or a callback is repeated.
	var stored := _store_card_instance(instance)
	if stored.is_empty():
		return {}
	save_collection()
	var changed_card_ids: Array[String] = [str(stored["card_id"])]
	collection_changed.emit(changed_card_ids)
	return stored


func create_card_instance(card_id: String, level: int = 1, effects: Array = []) -> Dictionary:
	if not can_obtain_card(card_id):
		return {}
	_migrate_legacy_collection()
	return _store_card_instance(roll_card_instance(card_id, level, effects))


func roll_card_instance(card_id: String, level: int = 1, effects: Array = []) -> Dictionary:
	if not CardDatabase.has_card(card_id) or not can_obtain_card(card_id):
		return {}
	var rolled_effects: Array = effects
	if not CardData.is_combat_card(CardDatabase.get_card(card_id)):
		rolled_effects = []
	elif rolled_effects.is_empty():
		rolled_effects = EffectDatabase.roll_effects()
	return CardData.create_instance(card_id, level, rolled_effects, CardData.roll_holo())


func _store_card_instance(instance: Dictionary) -> Dictionary:
	var card_id := str(instance.get("card_id", ""))
	var instance_id := str(instance.get("instance_id", ""))
	if instance_id.is_empty() or not CardDatabase.has_card(card_id) or not can_obtain_card(card_id):
		return {}
	_migrate_legacy_collection()
	for owned: Dictionary in collection["instances"]:
		if str(owned.get("instance_id", "")) == instance_id:
			return {}
	var stored := instance.duplicate(true)
	_sanitize_instance_effects(stored)
	stored["is_holo"] = CardData.is_holo(instance)
	collection["instances"].append(stored)
	var cards: Dictionary = collection["cards"]
	cards[card_id] = int(cards.get(card_id, 0)) + 1
	_record_card_discovery(collection, card_id)
	return stored.duplicate(true)


func _sanitize_loaded_instance_effects() -> void:
	# Interpret legacy saves safely in memory; no migration-only disk write.
	var instances: Variant = collection.get("instances", [])
	if instances is Array:
		for instance: Variant in instances:
			if instance is Dictionary:
				_sanitize_instance_effects(instance)
	# Completed offerings retain a copy of the exact reward for later display.
	var metadata: Variant = collection.get("metadata", {})
	if metadata is Dictionary:
		var offering: Variant = metadata.get("jester_offering", {})
		if offering is Dictionary and offering.get("reward_instance") is Dictionary:
			_sanitize_instance_effects(offering["reward_instance"])


func _sanitize_instance_effects(instance: Dictionary) -> void:
	for field in ["effects", "active_effects"]:
		if instance.has(field):
			instance[field] = CardData.filter_instance_effects(instance[field])


func can_obtain_card(card_id: String) -> bool:
	if not CardDatabase.is_collectible_card(card_id):
		return false
	if not requirements_met(card_id):
		return false
	if CardData.is_unique_unlock(CardDatabase.get_card(card_id)) and get_amount(card_id) > 0:
		return false
	var starting_hand_tier := STARTING_HAND_CARD_IDS.find(card_id)
	return starting_hand_tier < 0 or starting_hand_tier == get_starting_hand_slot_count()


func requirements_met(card_id: String, visited: Array[String] = []) -> bool:
	if not CardDatabase.has_card(card_id) or visited.has(card_id):
		return false
	var path := visited.duplicate()
	path.append(card_id)
	var requires: Variant = CardDatabase.get_card(card_id).get("requires", [])
	if not requires is Array:
		return false
	for prerequisite: Variant in requires:
		if not prerequisite is String or not _has_unlock(str(prerequisite), path):
			return false
	return true


func has_unlock(card_id: String) -> bool:
	return _has_unlock(card_id, [])


func _has_unlock(card_id: String, visited: Array[String]) -> bool:
	if not CardDatabase.has_card(card_id) or get_amount(card_id) <= 0:
		return false
	return str(CardDatabase.get_card(card_id).get("category", "")) == "special" and requirements_met(card_id, visited)


func _get_upgrade_modifier(key: String, baseline: float, mode: String = "max") -> float:
	# Owned special cards are permanent: deck, stat-upgrade and fusion APIs
	# already exclude them. Reuse their saved quantities as the source of truth.
	var value := baseline
	for card_id: String in get_owned_cards():
		if not has_unlock(card_id):
			continue
		var modifiers: Variant = CardDatabase.get_card(card_id).get("upgrade_modifiers", {})
		if not modifiers is Dictionary or not modifiers.has(key):
			continue
		var modifier := float(modifiers[key])
		if not is_finite(modifier):
			continue
		match mode:
			"sum": value += modifier * get_amount(card_id)
			"min": value = minf(value, modifier)
			_: value = maxf(value, modifier)
	return value


func get_soulcoin_multiplier() -> float:
	return _get_upgrade_modifier("soulcoin_multiplier", 1.0)


func get_xp_multiplier() -> float:
	return _get_upgrade_modifier("xp_multiplier", 1.0)


func get_fusion_requirement() -> int:
	return maxi(2, roundi(_get_upgrade_modifier("fusion_requirement", float(FUSION_REQUIRED_CARDS), "min")))


func get_shop_discount(shop_pool: String = "normal") -> float:
	# More normal-shop discount sources can add the same modifier in card data.
	return clampf(_get_upgrade_modifier("shop_discount", 0.0, "sum"), 0.0, 1.0) if shop_pool == "normal" else 0.0


func get_lucky_coin_bonus() -> float:
	return _get_upgrade_modifier("lucky_coin_bonus", 0.0)


func get_manual_click_bonus() -> float:
	return maxf(_get_upgrade_modifier("manual_click_bonus", 0.0, "sum"), 0.0) if is_clicker_unlocked() else 0.0


func get_auto_click_rate() -> float:
	return maxf(_get_upgrade_modifier("auto_click_coins_per_second", 0.0), 0.0) if is_clicker_unlocked() else 0.0


func get_area_unlock_card_id(area_id: String) -> String:
	if area_id == "slot_room":
		return SLOT_ROOM_KEY_ID
	if area_id.is_empty():
		return ""
	for card: Dictionary in CardDatabase.get_all_cards():
		if str(card.get("area_unlock", "")) == area_id and str(card.get("category", "")) == "special":
			return str(card.get("id", ""))
	return ""


func has_area_access(area_id: String) -> bool:
	var card_id := get_area_unlock_card_id(area_id)
	if card_id.is_empty():
		return false
	if area_id == "slot_room" and is_slot_room_unlocked():
		return true
	var metadata: Variant = collection.get("metadata", {})
	if metadata is Dictionary:
		var areas: Variant = metadata.get("area_access", {})
		if areas is Dictionary and areas.get(area_id, false) == true:
			return true
	return has_unlock(card_id)


func unlock_area(area_id: String) -> bool:
	if area_id == "slot_room":
		return unlock_slot_room()
	if not has_area_access(area_id):
		return false
	var next_collection := collection.duplicate(true)
	if not next_collection.get("metadata") is Dictionary:
		next_collection["metadata"] = {}
	var metadata: Dictionary = next_collection["metadata"]
	if not metadata.get("area_access") is Dictionary:
		metadata["area_access"] = {}
	if metadata["area_access"].get(area_id, false) == true:
		return true
	metadata["area_access"][area_id] = true
	if not _save_collection_snapshot(next_collection):
		return false
	collection = next_collection
	var changed: Array[String] = [get_area_unlock_card_id(area_id)]
	collection_changed.emit(changed)
	return true


func get_starting_hand_slot_count() -> int:
	# Owning a later tier alone must never bypass a missing earlier unlock.
	var slots := 0
	for card_id in STARTING_HAND_CARD_IDS:
		if get_amount(card_id) <= 0:
			break
		slots += 1
	return slots


func get_black_market_day() -> String:
	# The local calendar, not elapsed play time, owns the midnight rotation.
	return Time.get_date_string_from_system(false)


func get_black_market_pool() -> Array[String]:
	# A separate allow-list: unlocks, discoveries, events and Secret cards never
	# enter the market, even when a normal pack's rarity settings change.
	var pool: Array[String] = []
	for card: Dictionary in CardDatabase.get_all_cards():
		var card_id := str(card.get("id", ""))
		if not CardData.is_combat_card(card) or not CardDatabase.is_collectible_card(card_id):
			continue
		if card.get("random_reward", true) == false or card.get("permanent_upgrade", false) == true or card.get("unique_unlock", false) == true:
			continue
		if not str(card.get("area_unlock", "")).is_empty() or not BLACK_MARKET_PRICES_CENTS.has(str(card.get("rarity", "")).to_lower()):
			continue
		var requires: Variant = card.get("requires", [])
		if not requires is Array or not requires.is_empty() or float(card.get("reward_weight", 1.0)) <= 0.0:
			continue
		pool.append(card_id)
	pool.sort()
	return pool


func get_black_market_offers() -> Dictionary:
	var day := get_black_market_day()
	var pool := get_black_market_pool()
	# Use our own RNG. Opening the board cannot change pack/combat rolls, and
	# reloading the same profile/date always shows the same four card types.
	var rng := RandomNumberGenerator.new()
	rng.seed = ("black-market-v1:" + day).hash()
	var offers: Array[Dictionary] = []
	for index in mini(BLACK_MARKET_OFFER_COUNT, pool.size()):
		var chosen := rng.randi_range(0, pool.size() - 1)
		var card_id := pool[chosen]
		pool.remove_at(chosen)
		var offer_id := "offer_%d_%s" % [index, card_id]
		var rarity := str(CardDatabase.get_card(card_id).get("rarity", "")).to_lower()
		offers.append({
			"offer_id": offer_id, "card_id": card_id,
			"price_cents": int(BLACK_MARKET_PRICES_CENTS[rarity]),
			"sold": has_black_market_receipt(day + ":" + offer_id),
		})
	return {"day": day, "offers": offers}


func has_black_market_receipt(transaction_id: String) -> bool:
	var metadata: Variant = collection.get("metadata", {})
	if not metadata is Dictionary:
		return false
	var receipts: Variant = metadata.get("black_market_purchases", {})
	return receipts is Dictionary and receipts.has(transaction_id)


func purchase_black_market_offer(day: String, offer_id: String) -> Dictionary:
	if _black_market_purchase_in_progress or _fusion_in_progress or _jester_offering_in_progress:
		return _black_market_failure("busy")
	if not has_area_access("black_market"):
		return _black_market_failure("locked")
	var board := get_black_market_offers()
	if day != str(board["day"]):
		return _black_market_failure("stale")
	var offer: Dictionary = {}
	for candidate: Dictionary in board["offers"]:
		if str(candidate["offer_id"]) == offer_id:
			offer = candidate
			break
	if offer.is_empty():
		return _black_market_failure("invalid_offer")
	if bool(offer["sold"]):
		return _black_market_failure("sold")
	var card_id := str(offer["card_id"])
	if not can_obtain_card(card_id):
		return _black_market_failure("invalid_offer")
	var price := int(offer["price_cents"])
	if GameCurrency.get_coin_cents() < price:
		return _black_market_failure("insufficient_funds")
	_black_market_purchase_in_progress = true
	var transaction_id := day + ":" + offer_id
	# Reserve the exact advertised amount with a durable refundable receipt.
	# No signal is sent until the collection and wallet agree on the outcome.
	if not GameCurrency.begin_black_market_purchase(transaction_id, price):
		_black_market_purchase_in_progress = false
		return _black_market_failure("save_failed")
	var instance := roll_card_instance(card_id)
	if instance.is_empty():
		GameCurrency.resolve_black_market_purchase(false)
		_black_market_purchase_in_progress = false
		return _black_market_failure("invalid_offer")
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	next_collection["instances"].append(instance.duplicate(true))
	next_collection["cards"][card_id] = int(next_collection["cards"].get(card_id, 0)) + 1
	_record_card_discovery(next_collection, card_id)
	var metadata: Dictionary = next_collection["metadata"]
	if not metadata.get("black_market_purchases") is Dictionary:
		metadata["black_market_purchases"] = {}
	# The durable receipt remains after selling/fusing a purchased card, so
	# neither consuming it nor reopening an older day can restock that offer.
	metadata["black_market_purchases"][transaction_id] = str(instance["instance_id"])
	if not _save_collection_snapshot(next_collection):
		GameCurrency.resolve_black_market_purchase(false)
		_black_market_purchase_in_progress = false
		return _black_market_failure("save_failed")
	collection = next_collection
	# A failed cleanup is safe: load recovery sees the collection receipt and
	# never refunds or grants a second copy of an already committed purchase.
	GameCurrency.resolve_black_market_purchase(true)
	var changed: Array[String] = [card_id]
	collection_changed.emit(changed)
	_black_market_purchase_in_progress = false
	return {
		"ok": true, "reason": "", "instance": instance.duplicate(true),
		"card_data": CardData.merge_card_and_instance(CardDatabase.get_card(card_id), instance),
	}


func _black_market_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "card_data": {}, "instance": {}}


func get_amount(card_id: String) -> int:
	if not CardDatabase.is_collectible_card(card_id):
		return 0
	_migrate_legacy_collection()
	return int((collection["cards"] as Dictionary).get(card_id, 0))


func is_clicker_unlocked() -> bool:
	return get_amount("clicker") > 0


func is_slot_room_unlocked() -> bool:
	var metadata: Variant = collection.get("metadata", {})
	return metadata is Dictionary and metadata.get("slot_room_unlocked", false) == true


func unlock_slot_room() -> bool:
	# Keeping the key in the collection lets the player revisit its door.
	if get_amount(SLOT_ROOM_KEY_ID) <= 0:
		return false
	if is_slot_room_unlocked():
		return true
	if not collection.has("metadata") or not collection["metadata"] is Dictionary:
		collection["metadata"] = {}
	collection["metadata"]["slot_room_unlocked"] = true
	save_collection()
	return true


func get_clicker_upgrade_count() -> int:
	return maxi(get_amount("clicker_upgrade"), 0)


func get_owned_cards() -> Dictionary:
	_migrate_legacy_collection()
	var owned: Dictionary = (collection["cards"] as Dictionary).duplicate(true)
	for card_id: Variant in owned.keys():
		if not CardDatabase.is_collectible_card(str(card_id)):
			owned.erase(card_id)
	return owned


func has_discovered_card(card_id: String) -> bool:
	# Reads must not migrate saves, generate instances or write to disk when
	# the journal opens. Existing ownership also covers saves before history.
	if not _is_discoverable_card(card_id):
		return false
	var metadata: Variant = collection.get("metadata", {})
	if metadata is Dictionary:
		var history: Variant = metadata.get("discovered_cards", {})
		if history is Dictionary and history.get(card_id, false) == true:
			return true
	return _discovered_card_ids_from_snapshot(collection).has(card_id)


func get_discovered_card_ids() -> Array[String]:
	return _discovered_card_ids_from_snapshot(collection)


func is_card_new(card_id: String) -> bool:
	if not has_discovered_card(card_id):
		return false
	var metadata: Variant = collection.get("metadata", {})
	if metadata is Dictionary:
		var seen: Variant = metadata.get("seen_cards", {})
		if seen is Dictionary and seen.get(card_id, false) == true:
			return false
	return true


func mark_card_seen(card_id: String) -> bool:
	if not has_discovered_card(card_id):
		return false
	if not is_card_new(card_id):
		return true
	# A hover acknowledges a card type permanently, independently of the
	# number of copies. Publish only after the save succeeds so failed writes
	# leave its badge visible and allow a later hover to retry.
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	var metadata: Dictionary = next_collection["metadata"]
	if not metadata.get("seen_cards") is Dictionary:
		metadata["seen_cards"] = {}
	metadata["seen_cards"][card_id] = true
	if not _save_collection_snapshot(next_collection):
		return false
	collection = next_collection
	# Badge listeners update in place; inventory listeners must not rebuild
	# the hovered collection or animate another acquisition.
	card_seen.emit(card_id)
	return true


func discover_cards(card_ids: Array) -> bool:
	# Discovery tracks collectible card types only. Playing a match event is
	# independent of collection ownership, hover history, and pack rewards.
	var discovered: Array[String] = []
	for raw: Variant in card_ids:
		if not raw is String or discovered.has(raw) or has_discovered_card(str(raw)) or not _is_discoverable_card(str(raw)):
			continue
		discovered.append(str(raw))
	if discovered.is_empty():
		return true
	var next_collection := collection.duplicate(true)
	for card_id: String in discovered:
		_record_card_discovery(next_collection, card_id)
	_seed_card_discoveries(next_collection)
	if not _save_collection_snapshot(next_collection):
		return false
	collection = next_collection
	collection_changed.emit(discovered)
	return true


func _is_discoverable_card(card_id: String) -> bool:
	return CardDatabase.is_collectible_card(card_id)


func _discovered_card_ids_from_snapshot(snapshot: Dictionary) -> Array[String]:
	var found := {}
	var metadata: Variant = snapshot.get("metadata", {})
	if metadata is Dictionary:
		var history: Variant = metadata.get("discovered_cards", {})
		if history is Dictionary:
			for card_id: Variant in history:
				if card_id is String and not str(card_id).is_empty() and history[card_id] == true:
					found[str(card_id)] = true
		# Past offerings are additional reliable evidence in older saves, even
		# after the last owned copy or the granted reward was consumed.
		var offering: Variant = metadata.get("jester_offering", {})
		if offering is Dictionary:
			var offered: Variant = offering.get("offered", [])
			if offered is Array:
				for card_id: String in JESTER_OFFERING_CARD_IDS:
					if offered.has(card_id):
						found[card_id] = true
			var reward: Variant = offering.get("reward_instance", {})
			if offering.get("completed", false) == true and reward is Dictionary and not str(reward.get("card_id", "")).is_empty():
				found[str(reward["card_id"])] = true
	var cards: Variant = snapshot.get("cards", {})
	if not snapshot.has("cards") and not snapshot.has("instances"):
		cards = snapshot
	if cards is Dictionary:
		for card_id: Variant in cards:
			var count: Variant = cards[card_id]
			if card_id is String and not str(card_id).is_empty() and (count is int or count is float) and int(count) > 0:
				found[str(card_id)] = true
	var instances: Variant = snapshot.get("instances", [])
	if instances is Array:
		for instance: Variant in instances:
			if instance is Dictionary and not str(instance.get("card_id", "")).is_empty():
				found[str(instance["card_id"])] = true
	var result: Array[String] = []
	for card_id: String in found:
		if _is_discoverable_card(card_id):
			result.append(card_id)
	result.sort()
	return result


func _record_card_discovery(snapshot: Dictionary, card_id: String) -> void:
	if not _is_discoverable_card(card_id):
		return
	if not snapshot.get("metadata") is Dictionary:
		snapshot["metadata"] = {}
	var metadata: Dictionary = snapshot["metadata"]
	if not metadata.get("discovered_cards") is Dictionary:
		metadata["discovered_cards"] = {}
	metadata["discovered_cards"][card_id] = true


func _seed_card_discoveries(snapshot: Dictionary) -> void:
	for card_id: String in _discovered_card_ids_from_snapshot(snapshot):
		_record_card_discovery(snapshot, card_id)


func get_card_instances() -> Array:
	_migrate_legacy_collection()
	var result: Array = []
	for instance: Variant in collection["instances"]:
		if instance is Dictionary and CardDatabase.is_collectible_card(str(instance.get("card_id", ""))):
			result.append(instance.duplicate(true))
	return result


func get_instances_for_card(card_id: String) -> Array:
	if not CardDatabase.is_collectible_card(card_id):
		return []
	_migrate_legacy_collection()
	var result := []
	for instance in collection["instances"]:
		if typeof(instance) == TYPE_DICTIONARY and str(instance.get("card_id", "")) == card_id:
			result.append((instance as Dictionary).duplicate(true))
	return result


func get_jester_offering_state() -> Dictionary:
	var offered: Array[String] = []
	var metadata: Variant = collection.get("metadata", {})
	var stored: Dictionary = {}
	if metadata is Dictionary and metadata.get("jester_offering") is Dictionary:
		stored = metadata["jester_offering"]
	var raw_offered: Variant = stored.get("offered", [])
	if raw_offered is Array:
		for card_id: String in JESTER_OFFERING_CARD_IDS:
			if raw_offered.has(card_id):
				offered.append(card_id)
	var reward: Dictionary = stored.get("reward_instance", {}) if stored.get("reward_instance", {}) is Dictionary else {}
	return {"offered": offered, "completed": stored.get("completed", false) == true, "reward_instance": reward.duplicate(true)}


func get_jester_offering_candidate(card_id: String) -> Dictionary:
	var reason := _jester_offering_unavailable_reason(card_id)
	if not reason.is_empty():
		return _jester_offering_failure(reason)
	var reserved := _get_fusion_reserved_instances()
	var instances := get_instances_for_card(card_id)
	for holo in [false, true]:
		for instance: Dictionary in instances:
			var identity := str(instance.get("instance_id", ""))
			if identity.is_empty() or reserved.has(identity) or CardData.is_holo(instance) != holo:
				continue
			return {"ok": true, "reason": "", "instance": instance.duplicate(true), "card_data": _jester_offering_card_data(instance)}
	return _jester_offering_failure("Im Kampfdeck – zuerst aus dem Deck entfernen." if not instances.is_empty() else "Du besitzt kein Exemplar dieser Karte.")


func _jester_offering_unavailable_reason(card_id: String) -> String:
	if _jester_offering_in_progress or _fusion_in_progress:
		return "Ein Opfer wird bereits verarbeitet."
	if card_id not in JESTER_OFFERING_CARD_IDS or not CardDatabase.has_card(card_id):
		return "Dieses Grab nimmt diese Karte nicht an."
	var state := get_jester_offering_state()
	if bool(state["completed"]):
		return "Das Opfer ist bereits abgeschlossen."
	if state["offered"].has(card_id):
		return "An diesem Grab wurde bereits geopfert."
	if get_amount(card_id) <= 0:
		return "Du besitzt kein Exemplar dieser Karte."
	return ""


func offer_jester_card(card_id: String, instance_id: String) -> Dictionary:
	var reason := _jester_offering_unavailable_reason(card_id)
	if not reason.is_empty():
		return _jester_offering_failure(reason)
	if _get_fusion_reserved_instances().has(instance_id):
		return _jester_offering_failure("Im Kampfdeck – zuerst aus dem Deck entfernen.")
	var instance: Dictionary = {}
	var identity_count := 0
	for raw: Variant in get_card_instances():
		if raw is Dictionary and not instance_id.is_empty() and str(raw.get("instance_id", "")) == instance_id:
			identity_count += 1
			if str(raw.get("card_id", "")) == card_id:
				instance = raw.duplicate(true)
	if identity_count != 1 or instance.is_empty():
		return _jester_offering_failure("Diese Karte ist nicht mehr in deiner Sammlung.")
	var state := get_jester_offering_state()
	var offered: Array[String] = state["offered"]
	offered.append(card_id)
	var completed := offered.size() == JESTER_OFFERING_CARD_IDS.size()
	var reward: Dictionary = {}
	if completed:
		var pool: Array[Dictionary] = []
		# This authored quest reward includes discovery Secrets, which remain
		# excluded from every random pack and regular reward pool.
		for card: Dictionary in CardDatabase.get_combat_cards():
			if str(card.get("rarity", "")) == "secret" and can_obtain_card(str(card.get("id", ""))) and float(card.get("reward_weight", 1.0)) > 0.0:
				pool.append(card)
		if pool.is_empty():
			return _jester_offering_failure("Keine Secret-Karte als Belohnung verfügbar.")
		var reward_card: Dictionary = pool.pick_random()
		reward = roll_card_instance(str(reward_card["id"]))
		if reward.is_empty():
			return _jester_offering_failure("Die Belohnung konnte nicht erstellt werden.")
		for owned: Dictionary in get_card_instances():
			if str(owned.get("instance_id", "")) == str(reward["instance_id"]):
				return _jester_offering_failure("Die Belohnung konnte nicht erstellt werden.")
	var card_data := _jester_offering_card_data(instance)
	var reward_card_data := _jester_offering_card_data(reward) if not reward.is_empty() else {}
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	var surviving: Array = []
	for owned: Dictionary in next_collection["instances"]:
		if str(owned.get("instance_id", "")) != instance_id:
			surviving.append(owned)
	var remaining := int(next_collection["cards"].get(card_id, 0)) - 1
	if remaining > 0:
		next_collection["cards"][card_id] = remaining
	else:
		next_collection["cards"].erase(card_id)
	var changed: Array[String] = [card_id]
	if completed:
		surviving.append(reward.duplicate(true))
		var reward_id := str(reward["card_id"])
		next_collection["cards"][reward_id] = int(next_collection["cards"].get(reward_id, 0)) + 1
		_record_card_discovery(next_collection, reward_id)
		changed.append(reward_id)
	next_collection["instances"] = surviving
	if not next_collection.get("metadata") is Dictionary:
		next_collection["metadata"] = {}
	next_collection["metadata"]["jester_offering"] = {"offered": offered, "completed": completed, "reward_instance": reward.duplicate(true)}
	# Persist consumption, progress and final reward together, then notify while
	# the guard is still held so a synchronous listener cannot offer again.
	_jester_offering_in_progress = true
	if not _save_collection_snapshot(next_collection, ".jester.tmp"):
		_jester_offering_in_progress = false
		return _jester_offering_failure("Speichern fehlgeschlagen. Deine Karten wurden behalten.")
	collection = next_collection
	var result := {"ok": true, "reason": "", "instance": instance, "card_data": card_data, "completed": completed, "reward_instance": reward.duplicate(true), "reward_card_data": reward_card_data}
	collection_changed.emit(changed)
	_jester_offering_in_progress = false
	return result


func _jester_offering_failure(reason: String) -> Dictionary:
	var state := get_jester_offering_state()
	return {"ok": false, "reason": reason, "instance": {}, "card_data": {}, "completed": state["completed"], "reward_instance": state["reward_instance"], "reward_card_data": {}}


func _jester_offering_card_data(instance: Dictionary) -> Dictionary:
	var card_id := str(instance.get("card_id", ""))
	var data := CardDatabase.get_card(card_id).duplicate(true)
	if data.is_empty():
		return {}
	# Match the deck's upgraded display without creating/migrating upgrade
	# entries merely because the player previews a sacrificial copy.
	var entry: Dictionary = CardUpgradeManager.upgrades.get(card_id, {})
	data["attack"] = int(data.get("attack", 0)) + int(entry.get("attack_bonus", 0))
	data["defense"] = int(data.get("defense", 0)) + int(entry.get("health_bonus", 0))
	var effects: Array[Dictionary] = []
	var base_effects := CardData.get_active_effects(data)
	var removed: Variant = entry.get("removed_base_effect_indices", [])
	for index in base_effects.size():
		if not (removed is Array and removed.has(index)):
			effects.append(base_effects[index])
	var additions: Variant = entry.get("effects", [])
	if additions is Array:
		for effect: Variant in additions:
			if effect is Dictionary and CardUpgradeManager._is_allowed_upgrade_effect(effect):
				effects.append(effect.duplicate(true))
	data["effects"] = CardData._limit_effects(effects)
	data["active_effects"] = data["effects"]
	return CardData.merge_card_and_instance(CardData.with_instance_metadata(data, instance))


func get_next_fusion_rarity(rarity: String) -> String:
	var index := FUSION_RARITIES.find(rarity.to_lower().strip_edges())
	return FUSION_RARITIES[index + 1] if index >= 0 and index + 1 < FUSION_RARITIES.size() else ""


func get_fusion_pool(source_rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var next_rarity := get_next_fusion_rarity(source_rarity)
	if next_rarity.is_empty():
		return result
	for card: Dictionary in CardDatabase.get_cards_by_rarity(next_rarity):
		if CardData.is_combat_card(card) and not CardData.is_unique_unlock(card) and can_obtain_card(str(card.get("id", ""))):
			result.append(card.duplicate(true))
	return result


func get_fusion_candidates() -> Array[Dictionary]:
	# Show each actual copy, including protected cards, so selecting a Holo or
	# an upgraded instance cannot silently consume a different owned copy.
	var reserved := _get_fusion_reserved_instances()
	var pool_available := {}
	var result: Array[Dictionary] = []
	for raw: Variant in get_card_instances():
		if not raw is Dictionary:
			continue
		var instance: Dictionary = raw
		var card_id := str(instance.get("card_id", ""))
		var instance_id := str(instance.get("instance_id", ""))
		var card := CardDatabase.get_card(card_id) if CardDatabase.has_card(card_id) else {}
		var rarity := str(card.get("rarity", "")).to_lower().strip_edges()
		if not pool_available.has(rarity):
			pool_available[rarity] = not get_fusion_pool(rarity).is_empty()
		var reason := _fusion_disabled_reason(instance, card, reserved, bool(pool_available[rarity]))
		result.append({
			"instance_id": instance_id,
			"card_id": card_id,
			"instance": instance.duplicate(true),
			"card_data": CardData.merge_card_and_instance(card, instance),
			"rarity": rarity,
			"next_rarity": get_next_fusion_rarity(rarity),
			"eligible": reason.is_empty(),
			"disabled_reason": reason,
		})
	return result


func validate_fusion(instance_ids: Array) -> Dictionary:
	if _fusion_in_progress or _jester_offering_in_progress:
		return _fusion_failure("Die Schmiede arbeitet bereits.")
	var required := get_fusion_requirement()
	if instance_ids.size() != required:
		return _fusion_failure("Wähle genau %d Karten derselben Seltenheit." % required)
	var candidates := {}
	for entry: Dictionary in get_fusion_candidates():
		candidates[str(entry["instance_id"])] = entry
	var seen := {}
	var amounts := {}
	var rarity := ""
	for raw: Variant in instance_ids:
		if not raw is String or str(raw).is_empty() or seen.has(raw):
			return _fusion_failure("Wähle %d unterschiedliche Kartenexemplare." % required)
		var instance_id := str(raw)
		if not candidates.has(instance_id):
			return _fusion_failure("Eine ausgewählte Karte ist nicht mehr in deiner Sammlung.")
		var entry: Dictionary = candidates[instance_id]
		if not bool(entry["eligible"]):
			return _fusion_failure(str(entry["disabled_reason"]))
		if not rarity.is_empty() and rarity != str(entry["rarity"]):
			return _fusion_failure("Alle %d Karten müssen dieselbe Seltenheit haben." % required)
		rarity = str(entry["rarity"])
		seen[instance_id] = true
		var card_id := str(entry["card_id"])
		amounts[card_id] = int(amounts.get(card_id, 0)) + 1
		if int(amounts[card_id]) > get_amount(card_id):
			return _fusion_failure("Die Kartensammlung hat sich geändert. Wähle die Karten erneut.")
	return {"ok": true, "reason": "", "rarity": rarity, "next_rarity": get_next_fusion_rarity(rarity), "required_cards": required}


func fuse_card_instances(instance_ids: Array) -> Dictionary:
	# Revalidate at the strike, not only when the cards were placed. A second
	# click/callback cannot spend the same identities a second time.
	var validation := validate_fusion(instance_ids)
	if not bool(validation["ok"]):
		return validation
	_fusion_in_progress = true
	var pool := get_fusion_pool(str(validation["rarity"]))
	if pool.is_empty():
		_fusion_in_progress = false
		return _fusion_failure("Keine Karte der nächsten Seltenheit verfügbar.")
	var reward_card: Dictionary = pool.pick_random()
	var reward := roll_card_instance(str(reward_card["id"]))
	if reward.is_empty():
		_fusion_in_progress = false
		return _fusion_failure("Die neue Karte konnte nicht erstellt werden.")
	var next_collection := collection.duplicate(true)
	_seed_card_discoveries(next_collection)
	var surviving: Array = []
	var changed: Array[String] = []
	var consumed: Array[String] = []
	for instance: Dictionary in next_collection["instances"]:
		var instance_id := str(instance.get("instance_id", ""))
		if instance_id == str(reward["instance_id"]):
			_fusion_in_progress = false
			return _fusion_failure("Bitte versuche die Fusion erneut.")
		if not instance_ids.has(instance_id):
			surviving.append(instance)
			continue
		consumed.append(instance_id)
		var card_id := str(instance["card_id"])
		var amount := int(next_collection["cards"].get(card_id, 0)) - 1
		if amount > 0:
			next_collection["cards"][card_id] = amount
		else:
			next_collection["cards"].erase(card_id)
		if not changed.has(card_id):
			changed.append(card_id)
	if consumed.size() != int(validation["required_cards"]):
		_fusion_in_progress = false
		return _fusion_failure("Die Kartensammlung hat sich geändert. Wähle die Karten erneut.")
	surviving.append(reward.duplicate(true))
	next_collection["instances"] = surviving
	var reward_id := str(reward["card_id"])
	next_collection["cards"][reward_id] = int(next_collection["cards"].get(reward_id, 0)) + 1
	_record_card_discovery(next_collection, reward_id)
	if not changed.has(reward_id):
		changed.append(reward_id)
	# Publish only after the full replacement is durable. Neither a failed
	# write nor a closed scene can leave missing cards without their reward.
	if not _save_fusion_collection(next_collection):
		_fusion_in_progress = false
		return _fusion_failure("Speichern fehlgeschlagen. Deine Karten wurden behalten.")
	collection = next_collection
	var result := validation.duplicate(true)
	result["instance"] = reward.duplicate(true)
	result["card_data"] = CardData.merge_card_and_instance(reward_card, reward)
	result["consumed_instance_ids"] = consumed
	collection_changed.emit(changed)
	_fusion_in_progress = false
	return result


func _fusion_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "rarity": "", "next_rarity": ""}


func _get_fusion_reserved_instances() -> Dictionary:
	var reserved := {}
	var deck_manager := get_node_or_null("/root/DeckManager")
	if deck_manager == null:
		return reserved
	# Resolve legacy occurrence-based decks using DeckManager's own Holo-first
	# rules before exposing cards. Exact saved copies and the starting hand stay.
	deck_manager.call("get_deck_cards")
	for instance_id: String in deck_manager.get("deck_instance_ids"):
		if not instance_id.is_empty():
			reserved[instance_id] = true
	return reserved


func _fusion_disabled_reason(instance: Dictionary, card: Dictionary, reserved: Dictionary, has_reward: bool) -> String:
	if card.is_empty() or str(instance.get("instance_id", "")).is_empty():
		return "Unbekannte Karte."
	if not CardData.is_combat_card(card) or CardData.is_unique_unlock(card):
		return "Sonder- und Ereigniskarten sind nicht schmiedbar."
	if card.get("random_reward", true) == false:
		return "Geheimniskarten bleiben erhalten."
	if get_next_fusion_rarity(str(card.get("rarity", ""))).is_empty():
		return "Höchste Seltenheit erreicht."
	if reserved.has(str(instance["instance_id"])):
		return "Im Kampfdeck – zuerst aus dem Deck entfernen."
	if not has_reward:
		return "Keine Karte der nächsten Seltenheit verfügbar."
	return ""


func _save_fusion_collection(next_collection: Dictionary) -> bool:
	return _save_collection_snapshot(next_collection, ".fusion.tmp")


func _save_collection_snapshot(next_collection: Dictionary, suffix: String = ".tmp") -> bool:
	var temporary_path := SAVE_PATH + suffix
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(next_collection, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error == OK:
		write_error = DirAccess.rename_absolute(temporary_path, SAVE_PATH)
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
	return write_error == OK


func get_display_card(card_id: String, occurrence: int = 0) -> Dictionary:
	if not CardDatabase.is_collectible_card(card_id):
		return {}
	var base_card := CardDatabase.get_card(card_id)
	if base_card.is_empty():
		return {}
	var instances := get_instances_for_card(card_id)
	# Collection/deck slots are grouped by card type. Prefer an owned Holo,
	# then consume distinct copies in their stable acquisition order.
	var ordered: Array[Dictionary] = []
	for holo in [true, false]:
		for instance: Dictionary in instances:
			if CardData.is_holo(instance) == holo:
				ordered.append(instance)
	if occurrence >= 0 and occurrence < ordered.size():
		return CardData.with_instance_metadata(base_card, ordered[occurrence])
	return CardData.with_instance_metadata(base_card)


func get_deck_card_data(card_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occurrences: Dictionary = {}
	for value: Variant in card_ids:
		var card_id := str(value)
		var occurrence := int(occurrences.get(card_id, 0))
		var data := get_display_card(card_id, occurrence)
		occurrences[card_id] = occurrence + 1
		if not data.is_empty():
			result.append(data)
	return result


func _migrate_legacy_collection() -> void:
	if collection.has("cards") and collection.has("instances"):
		return
	var legacy := collection.duplicate(true)
	collection = {"cards": {}, "instances": []}
	if legacy.get("metadata", {}) is Dictionary and legacy.has("metadata"):
		collection["metadata"] = legacy["metadata"].duplicate(true)
	for card_id in legacy.keys():
		if card_id == "metadata":
			continue
		var amount := int(legacy.get(card_id, 0))
		if amount <= 0:
			continue
		collection["cards"][card_id] = amount
		for i in range(amount):
			collection["instances"].append(CardData.create_instance(str(card_id)))


func _convert_duplicate_clickers() -> bool:
	# Old saves may contain several unlock cards. Keep their value as upgrades,
	# including each instance's identity, instead of removing owned cards.
	var kept_clicker := false
	var converted := 0
	for instance: Dictionary in collection["instances"]:
		if str(instance.get("card_id", "")) != "clicker":
			continue
		if not kept_clicker:
			kept_clicker = true
			continue
		instance["card_id"] = "clicker_upgrade"
		instance["effects"] = []
		converted += 1
	if converted == 0:
		return false
	var cards: Dictionary = collection["cards"]
	cards["clicker"] = 1
	cards["clicker_upgrade"] = int(cards.get("clicker_upgrade", 0)) + converted
	return true


func unlock_all_cards() -> void:
	var changed_card_ids: Array[String] = []

	for card: Dictionary in CardDatabase.get_all_cards():
		var card_id := str(card.get("id", ""))
		if card_id == "":
			continue

		# Upgrade copies keep stacking; the unlock card remains unique.
		if not create_card_instance(card_id).is_empty():
			changed_card_ids.append(card_id)

	save_collection()

	if not changed_card_ids.is_empty():
		collection_changed.emit(changed_card_ids)

	print("Alle Karten freigeschaltet.")
