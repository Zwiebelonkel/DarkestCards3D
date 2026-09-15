extends "res://tests/replacement_network_test.gd"

# Actual collection occurrences, host validation and production snapshots travel
# through the existing two-peer ENet fixture. No cosmetic roll occurs here.
const HOLO_ID := "saved-holo-corpse"
const NORMAL_ID := "saved-normal-corpse"
var _holo: Dictionary = {}
var _normal: Dictionary = {}


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run holo_match_network_test with the isolated feature runner.")
		get_tree().quit(1)
		return
	var saved_collection := CollectionManager.collection.duplicate(true)
	var saved_deck := DeckManager.battle_deck.duplicate()
	var saved_upgrades := CardUpgradeManager.upgrades.duplicate(true)
	CollectionManager.collection = {
		"cards": {"corpse": 2},
		"instances": [
			{"instance_id": NORMAL_ID, "card_id": "corpse", "level": 1, "effects": [], "is_holo": false},
			{"instance_id": HOLO_ID, "card_id": "corpse", "level": 1, "effects": [], "is_holo": true},
		],
	}
	DeckManager.battle_deck.assign(["corpse", "corpse"])
	CardUpgradeManager.upgrades = {
		"corpse": {"attack_bonus": 3, "health_bonus": 2, "effects": [], "removed_base_effect_indices": []},
	}
	await super._run()
	CollectionManager.collection = saved_collection
	DeckManager.battle_deck.assign(saved_deck)
	CardUpgradeManager.upgrades = saved_upgrades
	print("HOLO_MATCH_NETWORK_TESTS: " + ("PASS" if failures == 0 else "FAIL"))


func _check_replacements() -> void:
	_check_saved_deck_and_validation()
	await _check_mirrored_replacements()
	await _check_event_transfers()


func _check_saved_deck_and_validation() -> void:
	var original_instances := CollectionManager.get_card_instances()
	var local_pool := client._build_player_pool()
	check(local_pool.size() == 2, "Two copies of one card type produce two battle instances")
	if local_pool.size() != 2:
		return
	check(local_pool[0].get("is_holo") == true and local_pool[0].get("instance_id") == HOLO_ID, "Aggregated deck selects the stored Holo occurrence first")
	check(local_pool[1].get("is_holo") == false and local_pool[1].get("instance_id") == NORMAL_ID, "Second deck occurrence keeps its separate normal identity")
	var base := CardDatabase.get_card("corpse")
	check(int(local_pool[0].attack) == int(base.attack) + 3 and int(local_pool[1].defense) == int(base.defense) + 2, "Existing type upgrades apply once to Holo and normal copies")
	check(client._build_player_pool() == local_pool and CollectionManager.get_card_instances() == original_instances, "Rebuilding a deck neither rerolls Holo nor mutates stored instances")
	NetworkManager._refresh_local_player_data()
	var outgoing: Array = NetworkManager.local_player_data.deck
	check(outgoing == local_pool, "Online handshake uses the same upgraded saved instances as the local deck")
	_holo = NetworkManager._sanitize_remote_card(outgoing[0])
	_normal = NetworkManager._sanitize_remote_card(outgoing[1])
	check(_holo.get("is_holo") == true and _holo.get("instance_id") == HOLO_ID and _holo.get("card_id") == "corpse", "Host validation preserves Holo identity and cosmetic flag")
	check(_normal.get("is_holo") == false and _normal.get("instance_id") == NORMAL_ID, "Host validation preserves the separate normal copy")
	var malformed := _normal.duplicate(true)
	malformed["is_holo"] = "true"
	malformed["instance_id"] = {"unexpected": "nested"}
	malformed["private_metadata"] = {"not": "replicated"}
	var cleaned := NetworkManager._sanitize_remote_card(malformed)
	check(cleaned.get("is_holo") == false and not cleaned.has("private_metadata") and not cleaned.has("instance_id"), "Remote cosmetic metadata accepts only a boolean and bounded text identity")
	malformed["instance_id"] = "x".repeat(200)
	check(str(NetworkManager._sanitize_remote_card(malformed).get("instance_id", "")).length() == 128, "Remote instance identities are bounded before becoming authoritative state")
	malformed.erase("is_holo")
	check(NetworkManager._sanitize_remote_card(malformed).get("is_holo") == false, "Legacy handshake cards without Holo remain normal")
	var pool := sender._deck_from_player_payload({"deck": [_holo, _normal]})
	check(pool.size() == 2 and pool[0].get("is_holo") == true and pool[1].get("is_holo") == false, "Authoritative deck construction retains both validated cosmetic variants")
	pool[0]["is_holo"] = false
	check(_holo.get("is_holo") == true, "Authoritative match deck is independent of the received payload")


func _variant_snapshot(near: Dictionary, far: Dictionary, sequence: int) -> Dictionary:
	return {
		"current_turn": "player", "turn_sequence": sequence,
		"player_slots": [{"card_data": far.duplicate(true)}],
		"enemy_slots": [{"card_data": near.duplicate(true)}],
		"player_deck_count": 1, "enemy_deck_count": 1,
		"state_sync_sequence": sequence, "game_over": false,
		"action_in_progress": false,
	}


func _variants_arrived(near_id: String, far_id: String) -> bool:
	var near := client._get_card_from_slot("player", 0)
	var far := client._get_card_from_slot("enemy", 0)
	return (
		is_instance_valid(near) and is_instance_valid(far)
		and near.card_data.get("instance_id") == near_id
		and far.card_data.get("instance_id") == far_id
		and not client._online_action_in_progress
	)


func _check_mirrored_replacements() -> void:
	client_id = get_tree().get_multiplayer().get_unique_id()
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1])
	NetworkManager._participants = {1: {"role": "player"}, client_id: {"role": "player"}}
	client._online_mode = true
	client._online_is_host = false
	client._online_is_spectator = false
	client.draw_animation_duration = 0.02
	sender._rpc_apply_online_state.rpc_id(client_id, _variant_snapshot(_normal, _holo, 1))
	var arrived := await _wait_until(func(): return _variants_arrived(NORMAL_ID, HOLO_ID))
	check(arrived, "Actual ENet snapshot mirrors Holo and normal instances to the guest")
	if not arrived:
		return
	var old_normal := client._player_slots[0]
	var old_holo := client._enemy_slots[0]
	check(not bool(old_normal.card_data.get("is_holo")) and bool(old_holo.card_data.get("is_holo")), "Guest sees exactly the host's Holo flags on both table sides")
	var public_state := client._build_online_snapshot()
	check(bool(public_state.player_slots[0].card_data.is_holo) == false and bool(public_state.enemy_slots[0].card_data.is_holo), "Board snapshots include each visible card's Holo state")
	sender._rpc_apply_online_state.rpc_id(client_id, _variant_snapshot(_holo, _normal, 2))
	sender._rpc_release_online_turn.rpc_id(client_id, 2)
	arrived = await _wait_until(func(): return _variants_arrived(HOLO_ID, NORMAL_ID))
	check(arrived, "Same-type replacement swaps saved Holo identities over ENet")
	await get_tree().process_frame
	check(not is_instance_valid(old_normal) and not is_instance_valid(old_holo), "Different occurrences replace the old card nodes instead of reusing one identity")
	check(bool(client._player_slots[0].card_data.get("is_holo")) and not bool(client._enemy_slots[0].card_data.get("is_holo")), "Replacement presentation keeps the incoming Holo flag on each side")
	var legacy_holo := _holo.duplicate(true)
	legacy_holo.erase("instance_id")
	var legacy_normal := _normal.duplicate(true)
	legacy_normal.erase("instance_id")
	client._player_slots[0].setup(legacy_holo)
	check(not client._online_card_matches_state(client._player_slots[0], {"card_data": legacy_normal}), "Legacy same-type cards with different Holo flags are distinct replacements")


func _reset_local_events() -> void:
	client._online_mode = false
	client._clear_match()
	client._reset_online_sync_tracking()
	client._table_state = GameTable.TableState.PLAYING
	client._current_turn = "player"
	client._local_action_in_progress = false
	client._initialize_event_deck()


func _give_event(event_id: String) -> String:
	for event: Dictionary in client._event_deck:
		if event.get("id") == event_id:
			client._event_deck.erase(event)
			client._player_event_hand.append(event)
			return str(event.uid)
	return ""


func _check_event_transfers() -> void:
	_reset_local_events()
	client._player_deck.assign([_holo.duplicate(true)])
	client._enemy_deck.assign([_normal.duplicate(true)])
	check(client._try_play_event("player", _give_event("switch")), "Switch accepts two saved cosmetic variants")
	check(client._enemy_deck[0].get("instance_id") == HOLO_ID and client._enemy_deck[0].get("is_holo") == true and client._player_deck[0].get("instance_id") == NORMAL_ID and client._player_deck[0].get("is_holo") == false, "Switch transfers whole Holo and normal instances without rerolling")
	_reset_local_events()
	client._enemy_deck.assign([_normal.duplicate(true), _holo.duplicate(true)])
	client._draw_to_slot("enemy", 0, false)
	var target := client._enemy_slots[0]
	check(target.card_data.get("instance_id") == HOLO_ID, "Steel fixture draws the saved Holo target")
	target.current_hp = maxi(target.max_hp - 1, 1)
	var saved_hp := target.current_hp
	check(client._try_play_event("player", _give_event("steel"), 0), "Steel accepts the opponent's Holo instance")
	check(client._player_deck.size() == 1 and client._player_deck[0].get("is_holo") == true and client._player_deck[0].get("instance_id") == HOLO_ID, "Steel puts the original Holo instance into the receiving deck")
	client._draw_to_slot("player", 0, false)
	check(client._player_slots[0].card_data.get("is_holo") == true and client._player_slots[0].card_data.get("instance_id") == HOLO_ID and client._player_slots[0].current_hp == saved_hp, "Redrawing a stolen Holo retains cosmetic identity and match health")
	check(client._enemy_slots[0].card_data.get("instance_id") == NORMAL_ID and client._enemy_slots[0].card_data.get("is_holo") == false, "Steel replacement draws the other saved normal instance")
	await get_tree().create_timer(0.05).timeout
	client._clear_match()
