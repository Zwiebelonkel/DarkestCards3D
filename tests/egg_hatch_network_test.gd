extends "res://tests/event_cards_network_test.gd"

# Reuse the real authority/guest ENet transports and production snapshot ACKs.
# Only the Steam-session lookup is replaced by the isolated runner fixture.
var checks := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	super.check(condition, description)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run egg_hatch_network_test with the isolated match-feature runner.")
		get_tree().quit(1)
		return
	await super._run()
	print("EGG_HATCH_NETWORK_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])


func _card(card_id: String, identity: String) -> Dictionary:
	var data := CardDatabase.get_card(card_id).duplicate(true)
	data["instance_id"] = identity
	data["card_id"] = card_id
	data["is_holo"] = false
	return data


func _identity(table: GameTable, side: String, slot: int) -> String:
	var card := table._get_card_from_slot(side, slot)
	return str(card.card_data.get("instance_id", "")) if is_instance_valid(card) else ""


func _is_card(table: GameTable, side: String, slot: int, card_id: String) -> bool:
	var card := table._get_card_from_slot(side, slot)
	return is_instance_valid(card) and str(card.card_data.get("id", "")) == card_id


func _is_chick(table: GameTable, side: String, slot: int) -> bool:
	return _is_card(table, side, slot, "chick")


func _seed_hatch(table: GameTable, hatches: bool) -> void:
	var probe := RandomNumberGenerator.new()
	for candidate in range(10000):
		probe.seed = candidate
		if (probe.randf() < 0.25) == hatches:
			table._egg_hatch_rng.seed = candidate
			return
	check(false, "deterministic network hatch fixture finds a suitable seed")


func _check_chick_state_transport(card: Card3D) -> void:
	var snapshot := card.get_network_state()
	var exported := card.export_event_deck_card()
	check(int(snapshot.get("chick_survived_turns", -1)) == 4 and not (snapshot["card_data"] as Dictionary).has("chick_survived_turns"), "Chick age is transported as runtime state outside authored card data")
	check(int((exported[Card3D.EVENT_MATCH_STATE_KEY] as Dictionary).get("chick_survived_turns", -1)) == 4 and not exported.has("chick_survived_turns"), "Steel exports the same four-turn Chick age inside battle-only combat state")
	var restored := host.card_scene.instantiate() as Card3D
	add_child(restored)
	restored.setup(exported)
	check(int(restored.get_meta("chick_survived_turns", -1)) == 4 and not restored.card_data.has(Card3D.EVENT_MATCH_STATE_KEY), "redrawing a stolen Chick restores age without retaining the transport envelope in card data")
	restored.apply_network_state(snapshot)
	check(int(restored.get_meta("chick_survived_turns", -1)) == 4 and restored.card_data == card.card_data, "applying a Chick snapshot preserves its exact identity and age")
	snapshot.erase("chick_survived_turns")
	restored.apply_network_state(snapshot)
	check(int(restored.get_meta("chick_survived_turns", -1)) == 0, "a snapshot without age starts the Chick at zero instead of leaking prior age")
	restored.setup(_card("chicken", "transport-fresh-chicken"))
	check(not restored.has_meta("chick_survived_turns") and not restored.get_network_state().has("chick_survived_turns"), "fresh Chicken setup clears Chick age and excludes it from subsequent snapshots")
	restored.queue_free()


func _check_chick_growth_replication() -> String:
	var initial_host_id := _identity(host, "player", 0)
	var initial_guest_id := _identity(host, "enemy", 0)
	var player_deck_before := host._player_deck.duplicate(true)
	var enemy_deck_before := host._enemy_deck.duplicate(true)
	check(int(host._player_slots[0].get_meta("chick_survived_turns", 0)) == 0 and int(guest._enemy_slots[0].get_meta("chick_survived_turns", 0)) == 0, "new hatch starts with zero survived turns on authority and guest")
	# These Chicks arrived during the already running player turn. Its ending
	# must not count as a complete survived turn; the next ten do count.
	await host._end_turn_to("enemy")
	check(_is_chick(host, "player", 0) and int(host._player_slots[0].get_meta("chick_survived_turns", 0)) == 0, "the unfinished turn in which a Chick hatched does not count toward its growth")
	for survived in range(1, 10):
		await host._end_turn_to("enemy" if host._current_turn == "player" else "player")
		check(_is_chick(host, "player", 0) and _is_chick(guest, "enemy", 0) and int(host._player_slots[0].get_meta("chick_survived_turns", -1)) == survived and int(guest._enemy_slots[0].get_meta("chick_survived_turns", -1)) == survived, "complete survived turn %d advances age exactly once on both peers" % survived)
		check(_identity(host, "player", 0) == initial_host_id and _identity(host, "enemy", 0) == initial_guest_id, "Chick identities remain unchanged before five complete rounds at turn %d" % survived)
		if survived == 4:
			_check_chick_state_transport(host._player_slots[0])
	host._broadcast_online_snapshot(0)
	await get_tree().create_timer(0.1).timeout
	check(int(host._player_slots[0].get_meta("chick_survived_turns", -1)) == 9 and int(guest._enemy_slots[0].get_meta("chick_survived_turns", -1)) == 9, "replaying a growth snapshot cannot age either Chick again")
	guest._prepare_chick_turn()
	await guest._advance_chick_growth()
	check(_is_chick(guest, "enemy", 0) and int(guest._enemy_slots[0].get_meta("chick_survived_turns", -1)) == 9, "a remote guest cannot advance age or evolve a Chick locally")
	await host._end_turn_to("enemy" if host._current_turn == "player" else "player")
	check(_is_card(host, "player", 0, "chicken") and _is_card(guest, "enemy", 0, "chicken") and _is_card(host, "enemy", 0, "chicken") and _is_card(guest, "player", 0, "chicken"), "five full rounds evolve both owners' Chicks to Chickens through the actual ENet turn barrier")
	var chicken_id := _identity(host, "player", 0)
	check(not chicken_id.is_empty() and chicken_id != initial_host_id and chicken_id == _identity(guest, "enemy", 0) and _identity(host, "enemy", 0) != initial_guest_id, "authority creates fresh Chicken identities and mirrors them exactly")
	check(host._player_deck == player_deck_before and host._enemy_deck == enemy_deck_before and guest._enemy_deck.size() == player_deck_before.size() and guest._player_deck.size() == enemy_deck_before.size(), "growth replaces occupied slots without consuming or adding any deck cards")
	if not _is_card(host, "player", 0, "chicken"):
		return ""
	var chicken := host._player_slots[0]
	check(chicken.current_hp == 10 and chicken.max_hp == 10 and chicken.attack_value == 3 and not chicken.has_meta("chick_survived_turns"), "grown Chicken starts with its full base combat values and no Chick age")
	var snapshot := host._build_online_snapshot(0, guest_id)
	check(snapshot["player_slots"][0].get("spawn_kind", "") == "chick_growth" and not snapshot["player_slots"][0]["card_data"].has("spawn_kind"), "growth's in-place presentation marker stays outside persistent card data")
	check(guest._enemy_slots[0].global_position.is_equal_approx(guest._get_slot_marker("enemy", 0).global_position) and guest._enemy_slots[0].scale.is_equal_approx(Vector3.ONE), "remote grown Chicken settles in the exact former Chick slot")
	var remote_chicken := guest._enemy_slots[0]
	host._broadcast_online_snapshot(0)
	await get_tree().create_timer(0.1).timeout
	check(guest._enemy_slots[0] == remote_chicken and _identity(guest, "enemy", 0) == chicken_id, "replaying growth preserves the same remote Chicken without duplicating its replacement")
	check(not chicken.export_event_deck_card().has("spawn_kind"), "moving a grown Chicken into a deck removes its one-time growth presentation marker")
	return chicken_id


func _check_event_rpcs() -> void:
	guest_id = guest_api.get_unique_id()
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, guest_id])
	NetworkManager._participants = {
		1: {"role": "player", "name": "Host"},
		guest_id: {"role": "player", "name": "Guest"},
	}
	host._clear_match()
	guest._clear_match()
	host._online_mode = true
	host._online_is_host = true
	host._online_is_spectator = false
	host._table_state = GameTable.TableState.PLAYING
	host._game_over = false
	host._current_turn = "player"
	host._online_turn_sequence = 20
	host.replacement_draw_delay = 0.06
	host.draw_animation_duration = 0.35
	guest.replacement_draw_delay = 0.06
	guest.draw_animation_duration = 0.35
	guest._online_mode = true
	guest._online_is_host = false
	guest._online_is_spectator = false
	host._player_deck.assign([
		_card("corpse", "host-reserve-bottom"), _card("bat", "host-reserve-top"),
		_card("corpse", "host-normal"), _card("eg", "host-egg"),
	])
	host._enemy_deck.assign([_card("corpse", "guest-reserve"), _card("eg", "guest-egg")])
	host._draw_to_slot("player", 0, false)
	host._draw_to_slot("player", 1, false)
	host._draw_to_slot("enemy", 0, false)
	var collection_before := CollectionManager.collection.duplicate(true)
	var deck_before := DeckManager.get_deck_cards()
	host._broadcast_online_snapshot(0)
	var arrived := await _wait_until(func(): return guest._online_turn_sequence == 20 and _identity(guest, "enemy", 0) == "host-egg" and _identity(guest, "player", 0) == "guest-egg")
	check(arrived, "initial host eggs arrive in the guest's mirrored slots over ENet")
	if not arrived:
		return
	# Remote death presentation owns no game rules or deck draw. It may retire
	# its egg before the authority has finished the corresponding impact.
	var remote_egg := guest._enemy_slots[0]
	var guest_rng_before := guest._egg_hatch_rng.state
	remote_egg.current_hp = 0
	guest._remove_dead_card(remote_egg, false, Vector3(INF, INF, INF), false)
	await get_tree().create_timer(0.12).timeout
	check(guest._enemy_slots[0] == null and guest._enemy_deck.size() == 2, "draw_replacement=false remote egg death neither hatches nor consumes a deck card")
	check(guest._egg_hatch_rng.state == guest_rng_before, "remote death presentation consumes no hatch randomness")
	var host_egg := host._player_slots[0]
	var host_normal := host._player_slots[1]
	host_egg.current_hp = 0
	host_normal.current_hp = 0
	_seed_hatch(host, true)
	host._remove_dead_card(host_egg, false)
	host._remove_dead_card(host_normal, false)
	check(host._player_slots[0] == null and host._player_slots[1] == null, "authoritative simultaneous deaths clear both exact slots before replacement")
	var hatched := await _wait_until(func(): return _is_chick(guest, "enemy", 0) and _identity(guest, "enemy", 1) == "host-reserve-top")
	check(hatched, "one authoritative snapshot mirrors a hatch together with an ordinary replacement")
	if not hatched:
		return
	var host_chick := host._player_slots[0]
	var guest_chick := guest._enemy_slots[0]
	var chick_id := _identity(host, "player", 0)
	check(not chick_id.is_empty() and chick_id != "host-egg" and _identity(guest, "enemy", 0) == chick_id, "host alone creates a fresh chick identity which the guest preserves")
	check(host._player_deck.size() == 1 and guest._enemy_deck.size() == 1 and host._enemy_deck.size() == 1 and guest._player_deck.size() == 1, "only the normal replacement changes deck counts on either peer")
	var hatch_slot := guest._get_slot_marker("enemy", 0).global_position
	check(guest_chick.global_position.distance_to(hatch_slot) < 0.85 and guest_chick.global_position.distance_to(guest._get_stack_top_position("enemy", 2)) > 1.0, "remote hatch appears at its egg slot instead of flying from the deck")
	var normal_draw := guest._enemy_slots[1]
	check(normal_draw.global_position.distance_to(guest._get_stack_top_position("enemy", 2)) < 0.8, "a simultaneous ordinary replacement still starts at the correct previous stack height")
	var snapshot := host._build_online_snapshot(0, guest_id)
	check(snapshot["player_slots"][0].get("spawn_kind", "") == "egg_hatch" and not snapshot["player_slots"][0]["card_data"].has("spawn_kind"), "hatch presentation marker travels outside persistent card data")
	check(not snapshot["player_slots"][1].has("spawn_kind") or snapshot["player_slots"][1]["spawn_kind"] != "egg_hatch", "ordinary replacement snapshot is not marked as hatching")
	check(await _wait_until(func(): return not host._has_pending_card_replacements() and host._online_pending_state_acks.is_empty()), "hatch and ordinary draw release the actual guest ACK barrier before turn progression")
	check(guest_chick.global_position.is_equal_approx(hatch_slot) and guest_chick.scale.is_equal_approx(Vector3.ONE), "remote hatch settles exactly into the original slot")
	host._broadcast_online_snapshot(0)
	await get_tree().create_timer(0.1).timeout
	check(guest._enemy_slots[0] == guest_chick and _identity(guest, "enemy", 0) == chick_id and guest_chick.global_position.is_equal_approx(hatch_slot), "replayed authoritative snapshot reuses the chick without replaying or duplicating its hatch")
	check(not host_chick.export_event_deck_card().has("spawn_kind"), "moving a hatched chick into a deck cannot retain its one-time spawn animation marker")
	# A last egg must keep its owner's fight alive even with no draw pile.
	host._enemy_deck.clear()
	host._rebuild_stack_visual("enemy")
	var guest_owned_egg := host._enemy_slots[0]
	guest_owned_egg.current_hp = 0
	_seed_hatch(host, true)
	host._remove_dead_card(guest_owned_egg, false)
	check(await _wait_until(func(): return _is_chick(guest, "player", 0) and not host._has_pending_card_replacements()), "guest-owned last egg hatches with an empty deck through the same authority path")
	check(host._enemy_deck.is_empty() and guest._player_deck.is_empty() and not host._check_game_over() and not guest._game_over, "last-card hatch preserves play and never fabricates a deck draw")
	check(_identity(host, "enemy", 0) == _identity(guest, "player", 0) and _identity(host, "enemy", 0) != chick_id, "both owners receive distinct, identically replicated chick instances")
	check(CollectionManager.collection == collection_before and DeckManager.get_deck_cards() == deck_before, "network hatching changes neither persistent collection nor saved battle deck")
	var grown_chicken_id := await _check_chick_growth_replication()
	check(CollectionManager.collection == collection_before and DeckManager.get_deck_cards() == deck_before, "network growth and replicated age never change persistent collection or saved battle deck")
	# The same public snapshot is consumed by spectators without fighter-side
	# mirroring, private deck contents, or any authority to create a Chicken.
	NetworkManager._participants[guest_id]["role"] = "spectator"
	guest._online_is_spectator = true
	host._online_turn_sequence += 1
	var spectator_sequence := host._online_turn_sequence
	host._broadcast_online_snapshot(0)
	check(await _wait_until(func(): return guest._online_turn_sequence == spectator_sequence and _identity(guest, "player", 0) == grown_chicken_id), "spectator snapshot shows the grown host Chicken on its canonical side")
	check(_identity(guest, "enemy", 0) == _identity(host, "enemy", 0) and guest._player_deck.size() == host._player_deck.size() and guest._enemy_deck.size() == host._enemy_deck.size(), "spectators receive the same unique grown Chickens and exact public deck counts")
	check(not host._build_online_snapshot(0, guest_id).has("own_event_hand"), "hatch snapshots do not reveal private event hands to spectators")
	# Return role for normal fixture cleanup and avoid leaving any animation
	# coroutine running when the shared multiplayer APIs are detached.
	NetworkManager._participants[guest_id]["role"] = "player"
	guest._online_is_spectator = false
	await _wait_until(func(): return host._pending_card_deaths.is_empty() and guest._pending_card_deaths.is_empty())
	await _check_failed_hatch_replication()
	check(guest._egg_hatch_rng.state == guest_rng_before, "all guest snapshots and hatch presentations leave hatch randomness untouched")


func _check_failed_hatch_replication() -> void:
	host._player_deck.append(_card("eg", "failed-hatch-host-egg"))
	host._draw_to_slot("player", 2, false)
	host._player_deck.append(_card("bat", "failed-hatch-reserve"))
	host._broadcast_online_snapshot(0)
	check(await _wait_until(func(): return _identity(guest, "enemy", 2) == "failed-hatch-host-egg"), "the second Egg reaches the guest before a failed hatch")
	_seed_hatch(host, false)
	var egg := host._player_slots[2]
	egg.current_hp = 0
	host._remove_dead_card(egg, false)
	var resolved_rng := host._egg_hatch_rng.state
	host._remove_dead_card(egg, false)
	check(host._egg_hatch_rng.state == resolved_rng, "duplicate authority death cannot reroll a failed hatch")
	check(await _wait_until(func(): return _identity(guest, "enemy", 2) == "failed-hatch-reserve" and not host._has_pending_card_replacements()), "a failed 25-percent roll replicates an ordinary deck replacement over ENet")
	check(_identity(host, "player", 2) == "failed-hatch-reserve" and host._player_deck.size() == guest._enemy_deck.size(), "failed-hatch peers agree on the replacement identity and remaining pile")
	var replacement := guest._enemy_slots[2]
	host._broadcast_online_snapshot(0)
	await get_tree().create_timer(0.1).timeout
	check(guest._enemy_slots[2] == replacement and host._egg_hatch_rng.state == resolved_rng, "replaying a failed-hatch snapshot neither rerolls nor creates a Chick")
	await _wait_until(func(): return host._pending_card_deaths.is_empty() and guest._pending_card_deaths.is_empty())
