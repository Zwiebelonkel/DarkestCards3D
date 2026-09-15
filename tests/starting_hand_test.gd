extends Node3D

var checks := 0
var failures := 0
var table: GameTable
const DECK_IDS: Array[String] = ["corpse", "harald", "corpse", "jd", "mrfork", "corpse", "harald", "jd"]


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not DeckManager.SAVE_PATH.begins_with("res://test-user/") or not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	_seed_profile(0)
	check(not DeckManager.assign_starting_card(3) and DeckManager.get_starting_deck_indices().is_empty(), "new profile has no assignable starting slots")
	_set_unlocks(1)
	CollectionManager.collection.cards["starting_hand_3"] = 1
	check(CollectionManager.get_starting_hand_slot_count() == 1 and DeckManager.assign_starting_card(4) and not DeckManager.assign_starting_card(0), "a skipped unlock tier cannot open another slot")
	_set_unlocks(3)
	check(DeckManager.assign_starting_card(1) and DeckManager.assign_starting_card(6) and DeckManager.get_starting_deck_indices() == [4, 1, 6], "unlocked slots append deck-copy indices in insertion order")
	check(not DeckManager.assign_starting_card(2) and not DeckManager.assign_starting_card(4) and not DeckManager.assign_starting_card(-1) and not DeckManager.assign_starting_card(99), "capacity, duplicates and invalid deck-copy indices are rejected")
	check(DeckManager.get_deck_cards() == DECK_IDS, "starting selection leaves the full combat deck intact")
	var detached := DeckManager.get_starting_deck_indices()
	detached.clear()
	check(DeckManager.get_starting_deck_indices() == [4, 1, 6], "selection getter cannot mutate stored slots")
	check(DeckManager.remove_starting_card(1) and DeckManager.get_starting_deck_indices() == [4, -1, 6], "removing a middle start slot leaves later cards in place")
	check(not DeckManager.remove_starting_card(-1) and not DeckManager.remove_starting_card(1) and not DeckManager.remove_starting_card(3) and DeckManager.assign_starting_card(2), "invalid or empty slot removal is harmless and default assignment fills the first gap")
	check(DeckManager.remove_card_at(0) and DeckManager.get_starting_deck_indices() == [3, 1, 5] and DeckManager.get_deck_cards() == ["harald", "corpse", "jd", "mrfork", "corpse", "harald", "jd"], "removing an earlier exact copy remaps surviving indices without moving their slots")
	check(DeckManager.remove_card_at(5) and DeckManager.get_starting_deck_indices() == [3, 1], "removing a selected copy drops only that slot")
	check(DeckManager.remove_card("corpse") and DeckManager.get_starting_deck_indices() == [2], "legacy remove-by-ID uses the same index-aware removal path")
	check(not DeckManager.remove_card_at(99) and not DeckManager.remove_card_at(-1) and DeckManager.get_starting_deck_indices() == [2], "invalid exact removals retain the selection")
	DeckManager.load_deck()
	check(DeckManager.get_starting_deck_indices() == [2] and DeckManager.get_deck_cards() == ["harald", "jd", "mrfork", "corpse", "jd"], "deck and remapped starting choices survive a ConfigFile reload")
	_test_save_sanitation()
	_test_pinned_instances()
	_test_sparse_selection()
	_seed_profile(5)
	var camera := Camera3D.new()
	add_child(camera)
	table = (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = camera
	add_child(table)
	await get_tree().process_frame
	var pool := table._build_player_pool()
	var original_pool := pool.duplicate(true)
	check(pool.size() == DECK_IDS.size() and pool[0].get("instance_id") == "copy-2" and pool[2].get("instance_id") == "copy-0", "full deck resolves separate saved Holo and normal occurrences before selection")
	var selected: Array[int] = [5, 0, 6]
	var seen_random_fills := {}
	var valid_piles := true
	for repeat in range(20):
		var pile := DeckManager.prepare_match_deck(pool, selected, 3)
		var dealt: Array[Dictionary] = []
		for slot in range(5):
			dealt.append(pile.pop_back())
		for slot in range(selected.size()):
			valid_piles = valid_piles and dealt[slot] == pool[selected[slot]]
		seen_random_fills[str(dealt[3].instance_id) + ":" + str(dealt[4].instance_id)] = true
		valid_piles = valid_piles and _same_instances(dealt + pile, pool)
	check(valid_piles, "twenty shuffled draws keep selected order, metadata and every deck copy exactly once")
	check(seen_random_fills.size() > 1 and pool == original_pool, "unassigned opening slots are random and preparation leaves the saved pool untouched")
	var capped := DeckManager.prepare_match_deck(pool, [7, 0, 6, 2, 4], 5, 5)
	var capped_ids: Array[String] = []
	while not capped.is_empty():
		capped_ids.append(str(capped.pop_back().instance_id))
	check(capped_ids == _ids_at(pool, [7, 0, 6, 2, 4]), "five selected cards retain order even when the match deck is capped to the opening hand")
	var malformed := DeckManager.prepare_match_deck(pool, [7, 7, -1, "0", 0.5, true, 99, 0], 5)
	check(malformed.pop_back() == pool[7] and _same_instances(malformed, _without_indices(pool, [7])), "draw construction rejects malformed, duplicate and out-of-capacity preferences without compacting or losing copies")
	_test_sparse_match_piles(pool)
	_test_payload_validation(pool)
	DeckManager.starting_deck_indices.assign(selected)
	table._start_match()
	check(_first_slot_ids("player", 3) == _ids_at(pool, selected), "real local match deals selected copies into table slots zero through two")
	check(_same_instances(_board_and_deck("player"), pool), "local opening hand and remaining deck contain each owned instance once")
	check(table._player_slots[1].card_data.get("is_holo") == true and CardData.get_active_effects(table._player_slots[0].card_data) == CardData.get_active_effects(pool[5]), "local chosen cards retain their exact Holo and effects")
	NetworkManager._refresh_local_player_data()
	check(NetworkManager.local_player_data.starting_deck_indices == selected and NetworkManager.local_player_data.starting_hand_slots == 5 and NetworkManager.local_player_data.deck == pool, "online handshake carries the full upgraded instance deck and ordered preferences")
	var remote := {"deck": pool.duplicate(true), "starting_hand_slots": 2, "starting_deck_indices": [6, 2, 0, 1]}
	for card: Dictionary in remote.deck:
		card.instance_id = "remote-" + str(card.instance_id)
	NetworkManager.remote_player_data = NetworkManager._sanitize_remote_deck_payload(remote)
	var remote_pool: Array[Dictionary] = NetworkManager.remote_player_data.deck
	table._online_mode = true
	table._online_is_host = true
	table._start_online_match()
	check(_first_slot_ids("player", 3) == _ids_at(pool, selected) and _first_slot_ids("enemy", 2) == _ids_at(remote_pool, [6, 2]), "authoritative online match honors each player's distinct ordered opening choices")
	check(_same_instances(_board_and_deck("player"), pool) and _same_instances(_board_and_deck("enemy"), remote_pool), "online validation and dealing introduce no extra copies on either side")
	var snapshot := table._build_online_snapshot()
	check(snapshot.player_slots[0].card_data.instance_id == pool[5].instance_id and snapshot.enemy_slots[0].card_data.instance_id == remote_pool[6].instance_id and not snapshot.has("starting_deck_indices"), "authoritative board snapshot exposes the dealt choices without leaking hidden deck preferences")
	_test_sparse_real_matches(pool)
	_seed_profile(0)
	table._start_match()
	check(table._player_slots.size() == 5 and _same_instances(_board_and_deck("player"), pool), "a locked or reset profile still starts an ordinary random five-card match")
	table._clear_match()
	table.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("STARTING_HAND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_save_sanitation() -> void:
	_set_unlocks(3)
	var cfg := ConfigFile.new()
	cfg.set_value("deck", "cards", ["corpse", "missing-card", "starting_hand_1", "harald", "corpse"])
	cfg.set_value("deck", "starting_deck_indices", [4, 3, 1, 4, -1, 0.5, "0", 0])
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.get_deck_cards() == ["corpse", "harald", "corpse"] and DeckManager.get_starting_deck_indices() == [2, 1], "load filters invalid/special cards while preserving bounded slot positions")
	_set_unlocks(1)
	check(DeckManager.get_starting_deck_indices() == [2], "loss of slot capacity keeps the first valid selection and drops locked excess")
	_set_unlocks(0)
	check(DeckManager.get_starting_deck_indices().is_empty(), "collection reset clears stale locked selections on the next read")
	_set_unlocks(5)
	cfg = ConfigFile.new()
	cfg.set_value("deck", "cards", ["corpse", "harald"])
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.get_deck_cards() == ["corpse", "harald"] and DeckManager.get_starting_deck_indices().is_empty(), "old saves without starting preferences retain their full deck and random opening")
	cfg.set_value("deck", "starting_deck_indices", {"0": 1})
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.get_starting_deck_indices().is_empty(), "malformed selection containers do not become start slots")
	cfg.set_value("deck", "cards", {"corpse": 2})
	cfg.set_value("deck", "starting_deck_indices", [0])
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.get_deck_cards().is_empty() and DeckManager.get_starting_deck_indices().is_empty(), "malformed deck containers clear both deck and choices")
	var many: Array[String] = []
	for index in range(25): many.append("corpse")
	cfg.set_value("deck", "cards", many)
	cfg.set_value("deck", "starting_deck_indices", [24, 19, 0])
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.get_deck_cards().size() == 20 and DeckManager.get_starting_deck_indices() == [-1, 19, 0], "oversized saves clear invalid copies without shifting later slots")
	check(DeckManager.sanitize_starting_indices([4, 3, 2, 1, 0, 5], 8, 99) == [4, 3, 2, 1, 0] and DeckManager.sanitize_starting_indices([0], 8, -1).is_empty(), "shared validation bounds starting capacity to zero through five")


func _test_payload_validation(pool: Array[Dictionary]) -> void:
	var raw := {"deck": [pool[0], {"id": "starting_hand_1"}, "bad", pool[2], pool[0], pool[3]], "starting_hand_slots": 99, "starting_deck_indices": [5, 3, 4, 0, 0, -1, 99, "3", 3.5]}
	var cleaned := NetworkManager._sanitize_remote_deck_payload(raw)
	check(cleaned.deck.size() == 3 and cleaned.starting_deck_indices == [2, 1, -1, 0] and cleaned.starting_hand_slots == 5, "host remaps selections after rejecting special, malformed and duplicate-instance deck entries while preserving holes")
	check(cleaned.deck[0].instance_id == pool[0].instance_id and cleaned.deck[0].is_holo == pool[0].is_holo and cleaned.deck[1].instance_id == pool[2].instance_id, "host preserves distinct same-type Holo and normal instance identities")
	var idless := pool[0].duplicate(true)
	idless.erase("instance_id")
	cleaned = NetworkManager._sanitize_remote_deck_payload({"deck": [idless, idless], "starting_hand_slots": 2, "starting_deck_indices": [1, 0, 1]})
	check(cleaned.deck.size() == 2 and cleaned.starting_deck_indices == [1, 0], "legacy copies without instance IDs remain selectable by separate valid indices")
	for capacity: Variant in ["5", true, 1.5, null]:
		cleaned = NetworkManager._sanitize_remote_deck_payload({"deck": pool, "starting_hand_slots": capacity, "starting_deck_indices": [0, 1, 2]})
		check(cleaned.starting_hand_slots == 0 and cleaned.starting_deck_indices.is_empty(), "non-integer remote capacity is locked: " + str(capacity))
	cleaned = NetworkManager._sanitize_remote_deck_payload({"deck": pool, "starting_hand_slots": 2, "starting_deck_indices": [7, 6, 5, 4]})
	check(cleaned.starting_deck_indices == [7, 6], "remote preferences cannot exceed that player's bounded unlocked capacity")
	cleaned = NetworkManager._sanitize_remote_deck_payload({"deck": pool})
	check(cleaned.starting_deck_indices.is_empty() and cleaned.deck.size() == pool.size(), "missing online preferences keep a valid deck with an ordinary random opening")


func _test_pinned_instances() -> void:
	var normal := {"card_id": "corpse", "instance_id": "pinned-normal", "level": 1, "is_holo": false, "effects": [{"type": "poison", "damage": 2, "turns": 3}]}
	var holo := {"card_id": "corpse", "instance_id": "pinned-holo", "level": 1, "is_holo": true, "effects": [{"type": "stun"}]}
	CollectionManager.collection = {"cards": {"corpse": 2}, "instances": [normal, holo]}
	_set_unlocks(2)
	DeckManager.battle_deck.assign(["corpse", "corpse"])
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	CardUpgradeManager.upgrades = {"corpse": {"attack_bonus": 3, "health_bonus": 2, "effects": [{"type": "cleave", "side_damage": 0.5}], "removed_base_effect_indices": []}}
	var before := DeckManager.get_deck_card_data()
	var expected_upgrade := CardUpgradeManager.apply_upgrades("corpse", CardDatabase.get_card("corpse"))
	check(before[0].instance_id == "pinned-holo" and before[1].instance_id == "pinned-normal", "unbound legacy deck pins its initial Holo-first occurrence order")
	check(before[1].attack == expected_upgrade.attack and CardData.get_active_effects(before[1]) == CardData.get_active_effects(expected_upgrade), "shared final deck data applies stats once and preserves existing type-wide effect rules")
	check(DeckManager.assign_starting_card(1) and DeckManager.remove_card_at(0), "normal copy can be selected before removing the earlier same-type Holo")
	var after := DeckManager.get_deck_card_data()
	check(after.size() == 1 and after[0] == before[1] and DeckManager.get_starting_deck_indices() == [0], "same-type removal preserves the selected normal instance, Holo flag and upgraded effects")
	DeckManager.load_deck()
	check(DeckManager.get_deck_card_data()[0] == before[1] and DeckManager.deck_instance_ids == ["pinned-normal"] and DeckManager.get_starting_deck_indices() == [0], "pinned selected copy survives save/reload after its earlier twin is removed")
	var acquired := holo.duplicate(true)
	acquired.instance_id = "new-holo"
	CollectionManager.add_card_instance(acquired)
	check(DeckManager.get_deck_card_data()[0] == before[1], "acquiring another Holo cannot replace the normal copy already pinned in the deck")
	check(DeckManager.add_card("corpse") and DeckManager.add_card("corpse") and not DeckManager.add_card("corpse"), "adding copies uses remaining owned instances once and respects the owned count")
	check(DeckManager.deck_instance_ids == ["pinned-normal", "pinned-holo", "new-holo"], "new slots cannot steal an instance reserved by an existing deck slot")
	var cfg := ConfigFile.new()
	cfg.set_value("deck", "cards", ["corpse", "corpse", "corpse"])
	cfg.set_value("deck", "instance_ids", ["pinned-normal", "pinned-normal", "missing-instance"])
	cfg.set_value("deck", "starting_deck_indices", [2, 0])
	cfg.save(DeckManager.SAVE_PATH)
	DeckManager.load_deck()
	check(DeckManager.deck_instance_ids == ["pinned-normal", "pinned-holo", "new-holo"] and DeckManager.get_starting_deck_indices() == [2, 0], "duplicate or missing saved bindings repair to distinct owned copies without sorting preferences")
	DeckManager.battle_deck.assign(["harald", "corpse"])
	check(DeckManager.get_deck_cards() == ["harald", "corpse"] and DeckManager.deck_instance_ids == ["", "pinned-holo"] and DeckManager.get_starting_deck_indices() == [-1, 0], "legacy direct deck replacement clears out-of-range selections without shifting the remaining slot")
	check(CollectionManager.get_instances_for_card("corpse")[0] == normal, "deck pinning and preparation never rewrite stored instance effects")


func _test_sparse_selection() -> void:
	_seed_profile(5)
	check(DeckManager.assign_starting_card(6, 2) and DeckManager.get_starting_deck_indices() == [-1, -1, 6], "explicit third slot keeps first and second slots empty")
	check(DeckManager.assign_starting_card(4, 4) and DeckManager.get_starting_deck_indices() == [-1, -1, 6, -1, 4], "fifth slot can be filled with earlier gaps")
	check(DeckManager.assign_starting_card(0) and DeckManager.get_starting_deck_indices() == [0, -1, 6, -1, 4], "legacy assignment uses the first actual empty slot")
	check(DeckManager.assign_starting_card(1, 2) and DeckManager.get_starting_deck_indices() == [0, -1, 1, -1, 4], "fan copy replaces an occupied target without duplicating or deleting deck copies")
	check(DeckManager.assign_starting_card(1, 1) and DeckManager.get_starting_deck_indices() == [0, 1, -1, -1, 4], "selected copy moves into an empty target leaving its previous slot empty")
	check(DeckManager.assign_starting_card(4, 0) and DeckManager.get_starting_deck_indices() == [4, 1, -1, -1, 0], "dragging between occupied start slots swaps exact copies")
	check(not DeckManager.assign_starting_card(4, 0) and not DeckManager.assign_starting_card(3, -2) and not DeckManager.assign_starting_card(3, 5), "same-slot drop and invalid destinations leave assignments unchanged")
	check(DeckManager.remove_starting_card(1) and DeckManager.get_starting_deck_indices() == [4, -1, -1, -1, 0], "removing a chosen card preserves the far-right card position")
	DeckManager.load_deck()
	check(DeckManager.get_starting_deck_indices() == [4, -1, -1, -1, 0], "sparse exact slots survive persistence")
	check(DeckManager.remove_card_at(4) and DeckManager.get_starting_deck_indices() == [-1, -1, -1, -1, 0], "deleting a selected deck copy clears only its own start slot")
	_set_unlocks(3)
	check(DeckManager.get_starting_deck_indices().is_empty() and not DeckManager.assign_starting_card(1, 3), "losing slot unlocks drops locked selections without shifting them into free slots")
	check(DeckManager.sanitize_starting_indices([-1, 3, "2", 0, 3], 8, 5) == [-1, 3, -1, 0], "sanitation retains malformed and duplicate gaps but trims trailing empties")
	check(DeckManager.sanitize_starting_indices(PackedInt32Array([-1, 3, -1, 0]), 8, 5) == [-1, 3, -1, 0], "packed integer preferences retain sparse positions")
	check(DeckManager.sanitize_starting_indices([-1, -1, -1, 0], 8, 3).is_empty(), "selection beyond unlocked slots cannot move into an earlier empty slot")


func _test_sparse_match_piles(pool: Array[Dictionary]) -> void:
	var preferences: Array[int] = [-1, 5, -1, 0, 6]
	var valid := true
	var random_fills := {}
	for repeat in range(30):
		var pile := DeckManager.prepare_match_deck(pool, preferences, 5)
		var dealt: Array[Dictionary] = []
		for slot in range(5):
			dealt.append(pile.pop_back())
		valid = valid and dealt[1] == pool[5] and dealt[3] == pool[0] and dealt[4] == pool[6] and _same_instances(dealt + pile, pool)
		random_fills[str(dealt[0].instance_id) + ":" + str(dealt[2].instance_id)] = true
	check(valid and random_fills.size() > 1, "thirty sparse openings retain exact chosen slots and every copy while randomizing both earlier gaps")
	var capped := DeckManager.prepare_match_deck(pool, preferences, 5, 5)
	var opening: Array[Dictionary] = []
	while not capped.is_empty(): opening.append(capped.pop_back())
	check(opening.size() == 5 and opening[1] == pool[5] and opening[3] == pool[0] and opening[4] == pool[6], "deck-size cap counts selected copies instead of occupied slot span")
	var short_pool: Array[Dictionary] = [pool[0], pool[1], pool[2]]
	var short_pile := DeckManager.prepare_match_deck(short_pool, [-1, -1, -1, -1, 2], 5)
	opening.clear()
	while not short_pile.is_empty(): opening.append(short_pile.pop_back())
	check(opening.size() == 5 and opening[2].is_empty() and opening[3].is_empty() and opening[4] == pool[2] and _same_instances([opening[0], opening[1], opening[4]], short_pool), "short deck reserves fifth chosen slot using only empty initial positions and all three real copies once")
	var empty_pool: Array[Dictionary] = []
	check(DeckManager.prepare_match_deck(empty_pool, [-1, -1, 0], 5).is_empty() and DeckManager.prepare_match_deck(pool, preferences, 5, 0).is_empty(), "empty or zero-limit decks never manufacture opening entries")


func _test_sparse_real_matches(pool: Array[Dictionary]) -> void:
	DeckManager.starting_deck_indices.assign([-1, 5, -1, 0, 6])
	table._online_mode = false
	table._start_match()
	check(table._player_slots[1].card_data == pool[5] and table._player_slots[3].card_data == pool[0] and table._player_slots[4].card_data == pool[6] and _same_instances(_board_and_deck("player"), pool), "real local match honors exact slots two, four and five with random cards in slots one and three")
	NetworkManager._refresh_local_player_data()
	var remote := {"deck": pool.duplicate(true), "starting_hand_slots": 5, "starting_deck_indices": [-1, 6, -1, 2]}
	for card: Dictionary in remote.deck: card.instance_id = "sparse-remote-" + str(card.instance_id)
	NetworkManager.remote_player_data = NetworkManager._sanitize_remote_deck_payload(remote)
	var remote_pool: Array[Dictionary] = NetworkManager.remote_player_data.deck
	check(NetworkManager.local_player_data.starting_deck_indices == [-1, 5, -1, 0, 6] and NetworkManager.remote_player_data.starting_deck_indices == [-1, 6, -1, 2], "local handshake and host remote sanitation both retain sparse exact positions")
	table._online_mode = true
	table._online_is_host = true
	table._start_online_match()
	check(table._player_slots[1].card_data.instance_id == pool[5].instance_id and table._player_slots[4].card_data.instance_id == pool[6].instance_id and table._enemy_slots[1].card_data.instance_id == remote_pool[6].instance_id and table._enemy_slots[3].card_data.instance_id == remote_pool[2].instance_id, "authoritative online match places both players' chosen cards into their individual sparse targets")
	check(_same_instances(_board_and_deck("player"), pool) and _same_instances(_board_and_deck("enemy"), remote_pool), "sparse online draws preserve all instance identities without extra copies")
	_seed_profile(5)
	DeckManager.battle_deck.assign(["corpse", "harald", "corpse"])
	DeckManager.assign_starting_card(2, 4)
	var short_pool := DeckManager.get_deck_card_data()
	table._online_mode = false
	table._start_match()
	check(is_instance_valid(table._player_slots[0]) and is_instance_valid(table._player_slots[1]) and not is_instance_valid(table._player_slots[2]) and not is_instance_valid(table._player_slots[3]) and table._player_slots[4].card_data == short_pool[2], "real three-card match leaves exhausted middle positions empty and places selected copy in slot five")
	check(table._player_deck.is_empty() and _same_instances(_board_and_deck("player"), short_pool), "short-match opening consumes every placeholder before play and creates exactly the real cards")
	var snapshot := table._build_online_snapshot()
	check(snapshot.player_slots[2] == null and snapshot.player_slots[3] == null and snapshot.player_slots[4].card_data.instance_id == short_pool[2].instance_id, "snapshot contains empty slots instead of placeholder card data")


func _seed_profile(unlocks: int) -> void:
	CollectionManager.collection = {"cards": {}, "instances": []}
	for index in range(DECK_IDS.size()):
		var id := DECK_IDS[index]
		CollectionManager.collection.cards[id] = int(CollectionManager.collection.cards.get(id, 0)) + 1
		CollectionManager.collection.instances.append({"card_id": id, "instance_id": "copy-%d" % index, "level": 1, "is_holo": index == 2, "effects": [{"type": "poison", "damage": index + 1, "turns": 2}]})
	_set_unlocks(unlocks)
	DeckManager.battle_deck.assign(DECK_IDS)
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	CardUpgradeManager.upgrades.clear()
	NetworkManager.local_player_data.clear()
	NetworkManager.remote_player_data.clear()


func _set_unlocks(count: int) -> void:
	for tier in range(1, 6):
		CollectionManager.collection.cards.erase("starting_hand_%d" % tier)
		if tier <= count: CollectionManager.collection.cards["starting_hand_%d" % tier] = 1


func _ids_at(pool: Array[Dictionary], indices: Array[int]) -> Array[String]:
	var ids: Array[String] = []
	for index in indices: ids.append(str(pool[index].instance_id))
	return ids


func _without_indices(pool: Array[Dictionary], indices: Array[int]) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = []
	for index in range(pool.size()):
		if not indices.has(index): remaining.append(pool[index])
	return remaining


func _same_instances(actual: Array[Dictionary], expected: Array[Dictionary]) -> bool:
	var actual_ids: Array[String] = []
	var expected_ids: Array[String] = []
	for card: Dictionary in actual: actual_ids.append(str(card.instance_id))
	for card: Dictionary in expected: expected_ids.append(str(card.instance_id))
	actual_ids.sort()
	expected_ids.sort()
	return actual_ids == expected_ids


func _first_slot_ids(side: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for slot in range(count):
		var card := table._get_card_from_slot(side, slot)
		ids.append(str(card.card_data.get("instance_id", "")) if is_instance_valid(card) else "missing")
	return ids


func _board_and_deck(side: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(table._player_deck if side == "player" else table._enemy_deck)
	for slot in range(5):
		var card := table._get_card_from_slot(side, slot)
		if is_instance_valid(card): result.append(card.card_data)
	return result
