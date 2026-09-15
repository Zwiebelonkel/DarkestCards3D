extends Node

const MAX_DECK_SIZE := 20
const MAX_STARTING_HAND_SIZE := 5
var SAVE_PATH: String:
	get:
		return SaveSlots.get_save_path("battle_deck.cfg")

var battle_deck: Array[String] = []
var starting_deck_indices: Array[int] = []
var deck_instance_ids: Array[String] = []

func _ready() -> void:
	load_deck()


func clear_profile_state() -> void:
	battle_deck.clear()
	starting_deck_indices.clear()
	deck_instance_ids.clear()


func reload_profile() -> void:
	load_deck()


func can_add_card(card_id: String) -> bool:
	_sanitize_deck()
	if not CardData.is_combat_card(CardDatabase.get_card(card_id)):
		return false
	if battle_deck.size() >= MAX_DECK_SIZE:
		return false

	var owned_amount := CollectionManager.get_amount(card_id)
	var deck_amount := get_card_count(card_id)

	return deck_amount < owned_amount

func add_card(card_id: String) -> bool:
	if not can_add_card(card_id):
		return false

	battle_deck.append(card_id)
	deck_instance_ids.append("")
	save_deck()
	return true

func remove_card(card_id: String) -> bool:
	_sanitize_deck()
	var index := battle_deck.find(card_id)
	return remove_card_at(index)


func remove_card_at(deck_index: int) -> bool:
	_sanitize_deck()
	if deck_index < 0 or deck_index >= battle_deck.size():
		return false
	battle_deck.remove_at(deck_index)
	deck_instance_ids.remove_at(deck_index)
	var surviving: Array[int] = []
	for selected: int in starting_deck_indices:
		surviving.append(-1 if selected == deck_index else (selected - 1 if selected > deck_index else selected))
	starting_deck_indices = surviving
	save_deck()
	return true


func get_starting_deck_indices() -> Array[int]:
	_sanitize_deck()
	return starting_deck_indices.duplicate()


func assign_starting_card(deck_index: int, slot_index: int = -1) -> bool:
	_sanitize_deck()
	if deck_index < 0 or deck_index >= battle_deck.size():
		return false
	var capacity := CollectionManager.get_starting_hand_slot_count()
	var previous_slot := starting_deck_indices.find(deck_index)
	if slot_index == -1:
		if previous_slot >= 0:
			return false
		slot_index = starting_deck_indices.find(-1)
		if slot_index < 0:
			slot_index = starting_deck_indices.size()
	if slot_index < 0 or slot_index >= capacity or slot_index == previous_slot:
		return false
	while starting_deck_indices.size() <= slot_index:
		starting_deck_indices.append(-1)
	# Moving a chosen copy swaps it with the target. A card from the fan
	# replaces the target, returning that previous selection to the fan.
	if previous_slot >= 0:
		starting_deck_indices[previous_slot] = starting_deck_indices[slot_index]
	starting_deck_indices[slot_index] = deck_index
	save_deck()
	return true


func remove_starting_card(slot_index: int) -> bool:
	_sanitize_deck()
	if slot_index < 0 or slot_index >= starting_deck_indices.size() or starting_deck_indices[slot_index] < 0:
		return false
	starting_deck_indices[slot_index] = -1
	save_deck()
	return true

func get_card_count(card_id: String) -> int:
	var count := 0
	for id in battle_deck:
		if id == card_id:
			count += 1
	return count

func is_full() -> bool:
	return battle_deck.size() >= MAX_DECK_SIZE
	
func is_empty() -> bool:
	return battle_deck.is_empty()

func save_deck() -> bool:
	_sanitize_deck()
	var cfg := ConfigFile.new()
	cfg.set_value("deck", "cards", battle_deck)
	cfg.set_value("deck", "starting_deck_indices", starting_deck_indices)
	cfg.set_value("deck", "instance_ids", deck_instance_ids)
	var temporary_path := SAVE_PATH + ".tmp"
	var error := cfg.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, SAVE_PATH)
	if error != OK:
		push_error("Could not save battle deck: " + error_string(error))
	return error == OK

func load_deck() -> void:
	clear_profile_state()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved_instances: Variant = cfg.get_value("deck", "instance_ids", [])
		_set_deck_from_raw(cfg.get_value("deck", "cards", []), cfg.get_value("deck", "starting_deck_indices", []), saved_instances)
		# Pin old occurrence-based decks once, before a later pack can insert a
		# newly acquired Holo ahead of the copy that was originally selected.
		if saved_instances != deck_instance_ids:
			save_deck()

func get_deck_cards() -> Array[String]:
	_sanitize_deck()
	return battle_deck.duplicate()


# Final battle/UI data retains the existing type-upgrade effect rules, then
# attaches the exact saved copy's identity. Do not apply upgrades twice.
func get_deck_card_data() -> Array[Dictionary]:
	_sanitize_deck()
	var owned := _owned_instances_by_id()
	var result: Array[Dictionary] = []
	for index in range(battle_deck.size()):
		var card_id := battle_deck[index]
		var upgraded := CardUpgradeManager.apply_upgrades(card_id, CardDatabase.get_card(card_id))
		var instance: Dictionary = owned.get(deck_instance_ids[index], {})
		result.append(CardData.merge_card_and_instance(CardData.with_instance_metadata(upgraded, instance)))
	return result


func _sanitize_deck() -> void:
	_set_deck_from_raw(battle_deck, starting_deck_indices, deck_instance_ids)


func _set_deck_from_raw(raw_cards: Variant, raw_starting: Variant, raw_instances: Variant = []) -> void:
	var cards: Array[String] = []
	var candidates: Array[String] = []
	var old_to_new := {}
	if raw_cards is Array or raw_cards is PackedStringArray:
		for index in range(raw_cards.size()):
			var value: Variant = raw_cards[index]
			if not (value is String) or not CardDatabase.has_card(value):
				continue
			if not CardData.is_combat_card(CardDatabase.get_card(value)):
				continue
			old_to_new[index] = cards.size()
			cards.append(value)
			var instance_id := ""
			if (raw_instances is Array or raw_instances is PackedStringArray) and index < raw_instances.size() and raw_instances[index] is String:
				instance_id = raw_instances[index]
			candidates.append(instance_id)
			if cards.size() >= MAX_DECK_SIZE:
				break
	var remapped: Array[int] = []
	if raw_starting is Array or raw_starting is PackedInt32Array or raw_starting is PackedInt64Array:
		for value: Variant in raw_starting:
			remapped.append(int(old_to_new[value]) if value is int and old_to_new.has(value) else -1)
	battle_deck = cards
	deck_instance_ids = _resolve_deck_instance_ids(cards, candidates)
	starting_deck_indices = sanitize_starting_indices(remapped, cards.size(), CollectionManager.get_starting_hand_slot_count())


func _owned_instances_by_id() -> Dictionary:
	var result := {}
	for raw: Variant in CollectionManager.get_card_instances():
		if not (raw is Dictionary):
			continue
		var instance := raw as Dictionary
		var id := str(instance.get("instance_id", ""))
		if not id.is_empty(): result[id] = instance
	return result


func _resolve_deck_instance_ids(cards: Array[String], candidates: Array[String]) -> Array[String]:
	var owned := _owned_instances_by_id()
	var result: Array[String] = []
	var used := {}
	# Reserve every surviving binding before filling missing/legacy ones. An
	# earlier empty slot must never steal an exact copy pinned to a later slot.
	for index in range(cards.size()):
		var id := candidates[index]
		if not owned.has(id) or used.has(id) or str(owned[id].get("card_id", "")) != cards[index]:
			id = ""
		result.append(id)
		if not id.is_empty(): used[id] = true
	for index in range(cards.size()):
		if not result[index].is_empty():
			continue
		# Keep the historical Holo-first acquisition order for unbound slots.
		for holo in [true, false]:
			for id: String in owned:
				var instance: Dictionary = owned[id]
				if used.has(id) or str(instance.get("card_id", "")) != cards[index] or CardData.is_holo(instance) != holo:
					continue
				result[index] = id
				used[id] = true
				break
			if not result[index].is_empty(): break
	return result


# Also used on untrusted online preferences. Never coerce strings, floats or
# booleans into copy indices. Invalid values become holes so later cards keep
# their exact table position; only trailing empty slots may be omitted.
func sanitize_starting_indices(raw_indices: Variant, card_count: int, unlocked_slots: int) -> Array[int]:
	var result: Array[int] = []
	var capacity := clampi(unlocked_slots, 0, MAX_STARTING_HAND_SIZE)
	if capacity == 0 or not (raw_indices is Array or raw_indices is PackedInt32Array or raw_indices is PackedInt64Array):
		return result
	for slot in range(mini(raw_indices.size(), capacity)):
		var value: Variant = raw_indices[slot]
		result.append(value if value is int and value >= 0 and value < card_count and not result.has(value) else -1)
	while not result.is_empty() and result.back() == -1:
		result.pop_back()
	return result


func prepare_match_deck(cards: Array[Dictionary], raw_indices: Variant, unlocked_slots: int, maximum_size: int = MAX_DECK_SIZE) -> Array[Dictionary]:
	var limit := clampi(maximum_size, 0, MAX_DECK_SIZE)
	var selected := sanitize_starting_indices(raw_indices, cards.size(), mini(unlocked_slots, limit))
	var selected_count := 0
	for index in selected:
		if index >= 0:
			selected_count += 1
	var remaining: Array[Dictionary] = []
	for index in range(cards.size()):
		if not selected.has(index):
			remaining.append(cards[index].duplicate(true))
	remaining.shuffle()
	remaining.resize(mini(remaining.size(), limit - selected_count))
	var opening: Array[Dictionary] = []
	# Fill gaps from the shuffled remainder before appending the whole opening
	# in reverse: the table draws with pop_back(). Empty placeholders matter
	# only for short decks with a chosen card beyond the last random copy.
	for slot in range(selected.size()):
		var index := selected[slot]
		opening.append(cards[index].duplicate(true) if index >= 0 else (remaining.pop_back() if not remaining.is_empty() else {}))
	for slot in range(opening.size() - 1, -1, -1):
		remaining.append(opening[slot])
	return remaining
