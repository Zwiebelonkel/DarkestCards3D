extends Node

const STAT_UPGRADE_COST_STEP := 5
const PISS_UPGRADE_MULTIPLIER := 5

var SAVE_PATH: String:
	get:
		return SaveSlots.get_save_path("card_upgrades.cfg")

var upgrades: Dictionary = {}

signal upgrades_changed(card_id: String)

func _ready() -> void:
	load_upgrades()


func clear_profile_state() -> void:
	upgrades.clear()


func reload_profile() -> void:
	load_upgrades()


func _get_entry(card_id: String) -> Dictionary:
	if not upgrades.has(card_id):
		upgrades[card_id] = {
			"attack_bonus": 0,
			"health_bonus": 0,
			"stat_upgrade_count": 0,
			"effect_roll_count": 0,
			"effects": [],
			"removed_base_effect_indices": []
		}

	if not upgrades[card_id].has("removed_base_effect_indices"):
		upgrades[card_id]["removed_base_effect_indices"] = []
	if not upgrades[card_id].has("effect_roll_count"):
		upgrades[card_id]["effect_roll_count"] = 0
	if not upgrades[card_id].has("stat_upgrade_count"):
		# Legacy upgrades were sold one stat point at a time. Preserve their
		# progression instead of resetting an upgraded card to its first price.
		upgrades[card_id]["stat_upgrade_count"] = maxi(int(upgrades[card_id].get("attack_bonus", 0)), 0) + maxi(int(upgrades[card_id].get("health_bonus", 0)), 0)

	return upgrades[card_id]


func add_attack(card_id: String, amount: int = 1) -> void:
	if not _can_upgrade(card_id) or amount <= 0:
		return
	var entry := _get_entry(card_id)
	entry["attack_bonus"] = int(entry.get("attack_bonus", 0)) + amount
	entry["stat_upgrade_count"] = get_stat_upgrade_count(card_id) + 1
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)


func add_health(card_id: String, amount: int = 1) -> void:
	if not _can_upgrade(card_id) or amount <= 0:
		return
	var entry := _get_entry(card_id)
	entry["health_bonus"] = int(entry.get("health_bonus", 0)) + amount
	entry["stat_upgrade_count"] = get_stat_upgrade_count(card_id) + 1
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)


func get_stat_upgrade_count(card_id: String) -> int:
	if not _can_upgrade(card_id):
		return 0
	var entry: Dictionary = upgrades.get(card_id, {})
	var legacy_count := maxi(int(entry.get("attack_bonus", 0)), 0) + maxi(int(entry.get("health_bonus", 0)), 0)
	return maxi(int(entry.get("stat_upgrade_count", legacy_count)), 0)


func get_stat_upgrade_cost(card_id: String, base_cost: int = 5) -> float:
	# Attack and defense share progression on this card, never on other cards.
	var price := maxi(base_cost, 1) + get_stat_upgrade_count(card_id) * STAT_UPGRADE_COST_STEP
	return GameCurrency.get_shop_price(price * _get_upgrade_multiplier(card_id))


func get_effect_roll_count(card_id: String) -> int:
	if not _can_upgrade(card_id):
		return 0
	var entry: Dictionary = upgrades.get(card_id, {})
	return maxi(int(entry.get("effect_roll_count", 0)), 0)


func get_effect_roll_cost(card_id: String, base_cost: int = 12) -> float:
	var price := maxi(base_cost, 1) * (get_effect_roll_count(card_id) + 1)
	return GameCurrency.get_shop_price(price * _get_upgrade_multiplier(card_id))


func record_effect_roll(card_id: String, received_effect: bool) -> void:
	# Called only for a completed, paid roll. Removal and rejected purchases
	# must never alter this streak, nor the independent stat purchase count.
	if not _can_upgrade(card_id):
		return
	var entry := _get_entry(card_id)
	entry["effect_roll_count"] = get_effect_roll_count(card_id) + 1 if received_effect else 0
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)


func _get_upgrade_multiplier(card_id: String) -> int:
	return PISS_UPGRADE_MULTIPLIER if card_id == "piss" else 1


func _is_allowed_upgrade_effect(effect: Dictionary) -> bool:
	var effect_type: Variant = effect.get("type", "")
	return effect_type is String and not effect_type.strip_edges().is_empty() and not CardData.is_innate_only_effect(effect_type)


func add_effect(card_id: String, effect: Dictionary) -> bool:
	if not _is_allowed_upgrade_effect(effect) or get_free_effect_slots(card_id) <= 0:
		return false

	var effects: Array = get_upgrade_effects(card_id)
	var previous_count := effects.size()
	effects.append(CardData.normalize_effect(effect))
	var limited := _limit_upgrade_effects_for_card(card_id, effects)
	if limited.size() <= previous_count:
		return false
	var entry := _get_entry(card_id)
	entry["effects"] = limited

	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)

	return true

func remove_last_effect(card_id: String) -> bool:
	if not upgrades.has(card_id):
		return false

	var entry := _get_entry(card_id)
	var effects: Array = get_upgrade_effects(card_id)

	if effects.is_empty():
		return false

	effects.remove_at(effects.size() - 1)

	entry["effects"] = effects
	upgrades[card_id] = entry

	save_upgrades()
	upgrades_changed.emit(card_id)

	return true
	
func get_upgrade_effects(card_id: String) -> Array:
	if not _can_upgrade(card_id):
		return []
	var entry := _get_entry(card_id)
	return _limit_upgrade_effects_for_card(card_id, entry.get("effects", []))
	
func get_free_effect_slots(card_id: String) -> int:
	if not _can_upgrade(card_id):
		return 0
	var base_count := get_base_effect_count(card_id)
	var upgrade_count := get_upgrade_effects(card_id).size()

	return max(CardData.MAX_EFFECTS_PER_CARD - base_count - upgrade_count, 0)
	
func _limit_upgrade_effects_for_card(card_id: String, effects: Variant) -> Array:
	var limited: Array[Dictionary] = []
	if not _can_upgrade(card_id):
		return limited
	var base_effects := get_base_effects(card_id)
	var max_upgrade_count :int= max(CardData.MAX_EFFECTS_PER_CARD - base_effects.size(), 0)
	var has_mailman := base_effects.any(func(effect: Dictionary): return str(effect.get("type", "")) == "draw_on_death")

	if not (effects is Array):
		return limited

	for effect in CardData._normalize_effects(effects):
		if limited.size() >= max_upgrade_count:
			break

		if effect is Dictionary and _is_allowed_upgrade_effect(effect):
			if str(effect.get("type", "")) == "draw_on_death":
				if has_mailman:
					continue
				has_mailman = true
			limited.append(effect.duplicate(true))

	return limited
	
func get_base_effect_count(card_id: String) -> int:
	return get_base_effects(card_id).size()

func apply_upgrades(card_id: String, data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	if not CardData.is_combat_card(data):
		result["effects"] = []
		result["active_effects"] = []
		return result
	var entry := _get_entry(card_id)

	result["attack"] = int(result.get("attack", 0)) + int(entry.get("attack_bonus", 0))
	result["defense"] = int(result.get("defense", 0)) + int(entry.get("health_bonus", 0))

	var combined_effects: Array = []

	for effect in get_base_effects(card_id):
		if effect is Dictionary:
			combined_effects.append(effect.duplicate(true))

	for effect in get_upgrade_effects(card_id):
		if effect is Dictionary:
			combined_effects.append(effect.duplicate(true))

	result["effects"] = CardData._limit_effects(combined_effects)
	# Canonical/remote cards may already carry this preferred field. Leaving
	# it stale would hide bought effects or resurrect removed innate effects.
	result["active_effects"] = result["effects"].duplicate(true)

	return result

func get_attack_bonus(card_id: String) -> int:
	if not _can_upgrade(card_id):
		return 0
	return int(_get_entry(card_id).get("attack_bonus", 0))


func get_health_bonus(card_id: String) -> int:
	if not _can_upgrade(card_id):
		return 0
	return int(_get_entry(card_id).get("health_bonus", 0))


func get_effects(card_id: String) -> Array:
	return get_upgrade_effects(card_id)


func get_active_effect_count(card_id: String) -> int:
	var base_card := CardDatabase.get_card(card_id)
	if base_card.is_empty():
		return get_effects(card_id).size()
	return CardData.get_active_effects(apply_upgrades(card_id, base_card)).size()


func save_upgrades() -> bool:
	var cfg := ConfigFile.new()

	for card_id in upgrades.keys():
		var entry: Dictionary = upgrades[card_id]

		cfg.set_value(card_id, "attack_bonus", int(entry.get("attack_bonus", 0)))
		cfg.set_value(card_id, "health_bonus", int(entry.get("health_bonus", 0)))
		cfg.set_value(card_id, "stat_upgrade_count", get_stat_upgrade_count(card_id))
		cfg.set_value(card_id, "effect_roll_count", get_effect_roll_count(card_id))
		cfg.set_value(card_id, "effects", _limit_upgrade_effects_for_card(card_id, entry.get("effects", [])))
		cfg.set_value(card_id, "removed_base_effect_indices", entry.get("removed_base_effect_indices", []))

	var temporary_path := SAVE_PATH + ".tmp"
	var error := cfg.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, SAVE_PATH)
	if error != OK:
		push_error("Could not save card upgrades: " + error_string(error))
	return error == OK

func load_upgrades() -> void:
	clear_profile_state()

	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	for section in cfg.get_sections():
		if not _can_upgrade(section):
			continue
		var attack_bonus := int(cfg.get_value(section, "attack_bonus", 0))
		var health_bonus := int(cfg.get_value(section, "health_bonus", 0))
		var legacy_upgrade_count := maxi(attack_bonus, 0) + maxi(health_bonus, 0)
		upgrades[section] = {
			"attack_bonus": attack_bonus,
			"health_bonus": health_bonus,
			"stat_upgrade_count": maxi(int(cfg.get_value(section, "stat_upgrade_count", legacy_upgrade_count)), 0),
			"effect_roll_count": maxi(int(cfg.get_value(section, "effect_roll_count", 0)), 0),
			"effects": [],
			"removed_base_effect_indices": cfg.get_value(section, "removed_base_effect_indices", [])
		}
		# Removed innate effects must be known before calculating free slots.
		# Otherwise a removed Lava would still occupy one slot during loading.
		upgrades[section]["effects"] = _limit_upgrade_effects_for_card(section, cfg.get_value(section, "effects", []))

func _limit_effects(effects: Variant) -> Array[Dictionary]:
	return CardData._limit_effects(effects)

func _can_upgrade(card_id: String) -> bool:
	return CardDatabase.has_card(card_id) and CardData.is_combat_card(CardDatabase.get_card(card_id))

func get_effect_entries(card_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	var base_card := CardDatabase.get_card(card_id)

	if not base_card.is_empty():
		var base_effects: Array = CardData.get_active_effects(base_card)
		var removed_indices: Array = _get_entry(card_id).get("removed_base_effect_indices", [])

		for i in range(base_effects.size()):
			if removed_indices.has(i):
				continue

			var effect = base_effects[i]

			if effect is Dictionary:
				entries.append({
					"source": "base",
					"index": i,
					"effect": effect.duplicate(true)
				})

	var upgrade_effects: Array = get_upgrade_effects(card_id)

	for i in range(upgrade_effects.size()):
		var effect = upgrade_effects[i]

		if effect is Dictionary:
			entries.append({
				"source": "upgrade",
				"index": i,
				"effect": effect.duplicate(true)
			})

	return entries
	
func remove_effect_at(card_id: String, effect_source: String, effect_index: int) -> bool:
	if not _can_upgrade(card_id):
		return false
	var entry := _get_entry(card_id)

	if effect_source == "upgrade":
		var effects: Array = get_upgrade_effects(card_id)

		if effect_index < 0 or effect_index >= effects.size():
			return false

		effects.remove_at(effect_index)

		entry["effects"] = effects
		upgrades[card_id] = entry

		save_upgrades()
		upgrades_changed.emit(card_id)

		return true

	if effect_source == "base":
		var base_card := CardDatabase.get_card(card_id)

		if base_card.is_empty():
			return false

		var base_effects: Array = CardData.get_active_effects(base_card)

		if effect_index < 0 or effect_index >= base_effects.size():
			return false

		var removed_indices: Array = entry.get("removed_base_effect_indices", [])

		if removed_indices.has(effect_index):
			return false

		removed_indices.append(effect_index)
		removed_indices.sort()

		entry["removed_base_effect_indices"] = removed_indices
		upgrades[card_id] = entry

		save_upgrades()
		upgrades_changed.emit(card_id)

		return true

	return false

func get_base_effects(card_id: String) -> Array[Dictionary]:
	var base_card := CardDatabase.get_card(card_id)

	if base_card.is_empty():
		return []

	var base_effects: Array = CardData.get_active_effects(base_card)
	var removed_indices: Array = _get_entry(card_id).get("removed_base_effect_indices", [])

	var visible_effects: Array[Dictionary] = []

	for i in range(base_effects.size()):
		if removed_indices.has(i):
			continue

		var effect = base_effects[i]

		if effect is Dictionary:
			visible_effects.append(effect.duplicate(true))

	return visible_effects
