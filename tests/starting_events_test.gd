extends Node3D

var checks := 0
var failures := 0
var table: GameTable
var profile_before: Dictionary
var files_before: Dictionary


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run starting_events_test only with isolated match-feature saves.")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	_seed_profile()
	# Resolve the already pinned deck before the persistence baseline so this
	# feature test does not conflate legacy migration with event dealing.
	DeckManager.get_deck_card_data()
	profile_before = _profile_state()
	files_before = _save_bytes()
	var camera := Camera3D.new()
	add_child(camera)
	table = (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = camera
	table.match_camera_duration = 0.01
	table.draw_animation_duration = 0.01
	table.replacement_draw_delay = 0.01
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	add_child(table)
	table.set_process(false)
	table.visible = false
	await get_tree().process_frame
	check(EventDeck.STARTING_HAND_SIZE == 3, "the shared starting event hand rule is three")
	for difficulty: String in ["easy", "normal", "hard", "insane"]:
		table._selected_difficulty = difficulty
		table._start_match()
		check(table._table_state == GameTable.TableState.PLAYING and table._player_slots.all(func(card): return is_instance_valid(card)) and table._enemy_slots.all(func(card): return is_instance_valid(card)), difficulty + " starts through the real offline match path with both combat hands")
		_check_deal(difficulty + " offline")
		await get_tree().process_frame
	_check_first_turn()
	var dealt_state := _event_state()
	var rng_state := table._rng.state
	table._deal_starting_event_hands()
	check(_event_state() == dealt_state and table._rng.state == rng_state, "duplicate initial-deal call cannot refill a partially played hand or consume RNG")
	table._start_match()
	check(_is_three_each() and table._event_deck.size() == EventDeck.DECK_SIZE - 6 and table._event_discard.is_empty() and not table._event_played_this_turn, "a second real match resets used events and deals exactly three new cards to each hand")
	_check_helper_authority()
	await _check_online_start()
	_check_snapshot_privacy()
	check(_profile_state() == profile_before, "starting events preserve owned inventory, deck, upgrades, currency and unrelated metadata")
	check(_save_bytes() == files_before, "offline and online event dealing leaves every save file unchanged, including collection history")
	_check_event_presentation()
	table._online_mode = false
	table._retire_online_battle_presentation()
	table._clear_match()
	check(table._player_event_hand.is_empty() and table._enemy_event_hand.is_empty() and table._event_deck.is_empty() and not table._starting_events_dealt, "match cleanup clears both event hands, pile and the initial-deal guard")
	_clear_network_fixture()
	await get_tree().process_frame
	await get_tree().process_frame
	table.queue_free()
	table = null
	await get_tree().process_frame
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	_finish.call_deferred()


func _finish() -> void:
	print("STARTING_EVENTS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _seed_profile() -> void:
	CollectionManager.collection = {"cards":{"corpse":8}, "instances":[], "metadata":{"slot_room_unlocked":false}}
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	CardUpgradeManager.upgrades.clear()
	for index in range(8):
		var identity := "starting-event-combat-%d" % index
		CollectionManager.collection.instances.append({
			"card_id":"corpse", "instance_id":identity,
			"level":1, "is_holo":false, "effects":[],
		})
		DeckManager.battle_deck.append("corpse")
		DeckManager.deck_instance_ids.append(identity)
	_clear_network_fixture()


func _clear_network_fixture() -> void:
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	NetworkManager._connected_peer_ids.clear()
	NetworkManager.local_player_data.clear()
	NetworkManager.remote_player_data.clear()


func _profile_state() -> Dictionary:
	var owned := CollectionManager.collection.duplicate(true)
	return {
		"collection":owned,
		"deck":DeckManager.battle_deck.duplicate(),
		"instances":DeckManager.deck_instance_ids.duplicate(),
		"starting":DeckManager.starting_deck_indices.duplicate(),
		"upgrades":CardUpgradeManager.upgrades.duplicate(true),
		"coins":GameCurrency.get_coins(), "level":GameCurrency.level, "xp":GameCurrency.xp,
	}


func _save_bytes() -> Dictionary:
	var result := {}
	for path: String in [CollectionManager.SAVE_PATH, DeckManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, GameCurrency.save_path]:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _is_three_each() -> bool:
	return table._player_event_hand.size() == 3 and table._enemy_event_hand.size() == 3


func _event_state() -> Dictionary:
	return {"player":table._player_event_hand.duplicate(true), "enemy":table._enemy_event_hand.duplicate(true), "deck":table._event_deck.duplicate(true), "discard":table._event_discard.duplicate(true), "dealt":table._starting_events_dealt}


func _check_deal(label: String) -> void:
	check(_is_three_each() and table._starting_events_dealt, label + " receives exactly three events per player")
	check(table._event_deck.size() == EventDeck.DECK_SIZE - 6 and table._event_discard.is_empty(), label + " deals six from the shared 31-card pile, leaving twenty-five")
	var dealt := table._player_event_hand + table._enemy_event_hand
	var uids := {}
	var valid := true
	for event: Dictionary in dealt:
		var uid := str(event.get("uid", ""))
		valid = valid and not uid.is_empty() and str(event.get("category", "")) == "event"
		uids[uid] = true
	for event: Dictionary in table._event_deck:
		valid = valid and not uids.has(str(event.get("uid", "")))
	check(valid and uids.size() == 6, label + " deals six distinct match identities with no copy remaining in the pile")
	# Exercise the real hand presenter even though this fixture disables processing.
	var before := CollectionManager.collection.duplicate(true)
	var before_files := _save_bytes()
	table._refresh_event_hand()
	check(table._player_event_hand.all(func(event: Dictionary): return not CollectionManager.has_discovered_card(str(event["id"])) and not CollectionManager.is_card_new(str(event["id"]))), label + " does not treat its received events as collectible discoveries or new cards")
	check(CollectionManager.collection == before and _save_bytes() == before_files, label + " hand presentation leaves collection state and save bytes unchanged")


func _check_event_presentation() -> void:
	check(CollectionManager.save_collection(), "save isolated combat inventory fixture")
	var definitions := EventDeck.definitions()
	var own: Dictionary = definitions[0].duplicate(true)
	var opponent: Dictionary = definitions[1].duplicate(true)
	own["uid"] = "discovery-own"
	opponent["uid"] = "discovery-opponent"
	table._player_event_hand.assign([own])
	table._enemy_event_hand.assign([opponent])
	table._table_state = GameTable.TableState.PLAYING
	table._game_over = false
	table._loss_exit_running = false
	table._journal_input_blocked = false
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = true
	var before := CollectionManager.collection.duplicate(true)
	var before_files := _save_bytes()
	table._refresh_event_hand()
	check(CollectionManager.collection == before and _save_bytes() == before_files and not CollectionManager.has_discovered_card(str(own["id"])) and not CollectionManager.has_discovered_card(str(opponent["id"])), "spectator presentation writes no event collection or discovery state")
	table._online_is_spectator = false
	table._refresh_event_hand()
	check(CollectionManager.collection == before and _save_bytes() == before_files and not CollectionManager.has_discovered_card(str(own["id"])) and not CollectionManager.has_discovered_card(str(opponent["id"])) and CollectionManager.get_amount(str(own["id"])) == 0, "online guest receives its event hand without permanent copies, discoveries or save writes")
	before = CollectionManager.collection.duplicate(true)
	before_files = _save_bytes()
	table._refresh_event_hand()
	table._refresh_event_hand()
	check(CollectionManager.collection == before and _save_bytes() == before_files, "repeated event-hand refreshes preserve collection and save bytes")


func _check_first_turn() -> void:
	# The single Steel card can be skipped: at least two of the three random
	# cards use immediate effects, so no asynchronous theft fixture is needed.
	var first: Dictionary = {}
	for event: Dictionary in table._player_event_hand:
		if str(event.get("id", "")) != "steel":
			first = event
			break
	var target := -1 if str(first.get("target", "")) == "none" else 0
	check(table._current_turn == "player" and not first.is_empty() and table._try_play_event("player", str(first.get("uid", "")), target), "a randomly dealt event is playable before the first attack of the first turn")
	var second: Dictionary = table._player_event_hand[0] if not table._player_event_hand.is_empty() else {}
	var second_target := -1 if str(second.get("target", "")) == "none" else 0
	check(not table._try_play_event("player", str(second.get("uid", "")), second_target) and table._player_event_hand.size() == 2 and table._event_discard.size() == 1 and table._event_played_this_turn, "starting with three cards still permits only one event per turn")


func _check_helper_authority() -> void:
	table._online_mode = false
	table._clear_event_match()
	table._initialize_event_deck()
	check(table._event_deck.size() == EventDeck.DECK_SIZE and table._player_event_hand.is_empty() and table._enemy_event_hand.is_empty() and not table._starting_events_dealt, "plain event-pile initialization remains separate from starting-hand dealing")
	for spectator: bool in [false, true]:
		table._online_mode = true
		table._online_is_host = false
		table._online_is_spectator = spectator
		var before := _event_state()
		var rng_state := table._rng.state
		table._deal_starting_event_hands()
		check(_event_state() == before and table._rng.state == rng_state and not table._starting_events_dealt, ("spectator" if spectator else "online client") + " cannot deal a local starting hand or consume its guard/RNG")
	table._online_mode = false
	table._online_is_spectator = false
	table._deal_starting_event_hands()
	check(_is_three_each() and table._event_deck.size() == EventDeck.DECK_SIZE - 6 and table._starting_events_dealt, "authorized offline helper deals normally after rejected remote-role calls")


func _check_online_start() -> void:
	_clear_network_fixture()
	var pool := DeckManager.get_deck_card_data()
	NetworkManager.local_player_data = {"deck":pool.duplicate(true), "starting_hand_slots":0, "starting_deck_indices":[]}
	var remote_pool := pool.duplicate(true)
	for card: Dictionary in remote_pool:
		card["instance_id"] = "remote-" + str(card.get("instance_id", ""))
	NetworkManager.remote_player_data = {"deck":remote_pool, "starting_hand_slots":0, "starting_deck_indices":[]}
	table._online_mode = true
	table._online_is_host = true
	table._online_is_spectator = false
	# No fake RPC/ACK hooks: the production host-start path sees valid payloads
	# but no connected recipients, so its normal state barrier is empty.
	await table._start_online_match()
	check(table._table_state == GameTable.TableState.PLAYING and not table._game_over and table._player_slots.all(func(card): return is_instance_valid(card)) and table._enemy_slots.all(func(card): return is_instance_valid(card)), "real online authority startup deals both valid combat decks")
	_check_deal("online authority")
	var before := _event_state()
	table._deal_starting_event_hands()
	check(_event_state() == before, "online authority cannot double-deal starting events")


func _check_snapshot_privacy() -> void:
	# This uses the standard transport-free match_features_network fixture;
	# production recipient authorization still resolves the participant roles.
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([2, 3])
	NetworkManager._participants = {1:{"role":"player"}, 2:{"role":"player"}, 3:{"role":"spectator"}}
	var public_state := table._build_online_snapshot()
	check(int(public_state.get("player_event_hand_count", -1)) == 3 and int(public_state.get("enemy_event_hand_count", -1)) == 3 and int(public_state.get("event_deck_count", -1)) == EventDeck.DECK_SIZE - 6 and not public_state.has("own_event_hand"), "public snapshot advertises three cards per hand and twenty-five in the pile without private identities")
	var guest_state := table._build_online_snapshot(0, 2)
	check(guest_state.get("own_event_hand", []) == table._enemy_event_hand and guest_state.get("own_event_hand", []).size() == 3, "guest snapshot contains exactly its own three starting event identities")
	var no_host_leak := true
	for event: Dictionary in table._player_event_hand:
		no_host_leak = no_host_leak and not str(guest_state).contains(str(event.uid))
	check(no_host_leak and not guest_state.has("event_deck") and not guest_state.has("player_event_hand"), "guest snapshot exposes neither the host's starting events nor hidden pile order")
	var spectator_state := table._build_online_snapshot(0, 3)
	var no_spectator_leak := not spectator_state.has("own_event_hand")
	for event: Dictionary in table._player_event_hand + table._enemy_event_hand:
		no_spectator_leak = no_spectator_leak and not str(spectator_state).contains(str(event.uid))
	check(no_spectator_leak, "spectator receives counts but none of the six starting event identities")
	check(not table._build_online_snapshot(0, 1234567).has("own_event_hand"), "unknown recipient receives no starting hand")
