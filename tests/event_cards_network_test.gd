extends Node


class GuestTable:
	extends GameTable

	# Both peers share one autoload in this test process. Its role lookup is
	# deliberately host-scoped so production request authorization is real.
	# Route only the guest ACK destination explicitly; the ACK still crosses
	# ENet and is validated by the production authoritative handler.
	func _send_online_state_ack(turn_sequence: int, state_sync_sequence: int) -> void:
		if state_sync_sequence > 0:
			_rpc_ack_online_state_applied.rpc_id(1, turn_sequence, state_sync_sequence)


# Run through run_match_feature_tests.ps1, which replaces only the Steam
# transport with match_features_network.gd and isolates player saves.
var failures := 0
var host: GameTable
var guest: GameTable
var guest_id := 0
var guest_api: SceneMultiplayer
var host_peer: ENetMultiplayerPeer
var guest_peer: ENetMultiplayerPeer


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	host = main.get_node("ScenePivot/GameTable") as GameTable
	# The default API and NetworkManager belong to the authority. The guest
	# gets a real second peer and the same relative production RPC node path.
	var guest_root := Node.new()
	guest_root.name = "TestGuest"
	get_tree().root.add_child(guest_root)
	guest_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(guest_api, guest_root.get_path())
	var guest_main := Node3D.new()
	guest_main.name = main.name
	guest_root.add_child(guest_main)
	var pivot := Node3D.new()
	pivot.name = "ScenePivot"
	guest_main.add_child(pivot)
	var camera := Camera3D.new()
	guest_main.add_child(camera)
	guest = (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	var guest_card_scene := guest.card_scene
	guest.set_script(GuestTable)
	guest.card_scene = guest_card_scene
	guest.table_camera = camera
	pivot.add_child(guest)
	await get_tree().process_frame
	host_peer = ENetMultiplayerPeer.new()
	var port := 36000 + int(Time.get_ticks_msec() % 10000)
	var server_error := host_peer.create_server(port, 1)
	check(server_error == OK, "event test starts a loopback ENet authority")
	if server_error == OK:
		get_tree().get_multiplayer().multiplayer_peer = host_peer
		guest_peer = ENetMultiplayerPeer.new()
		var client_error := guest_peer.create_client("127.0.0.1", port)
		check(client_error == OK, "event test starts a separate guest transport")
		if client_error == OK:
			guest_api.multiplayer_peer = guest_peer
			var connected := await _wait_until(func(): return guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not get_tree().get_multiplayer().get_peers().is_empty())
			check(connected, "host and guest event peers connect")
			if connected:
				await _check_event_rpcs()
	host._online_mode = false
	guest._online_mode = false
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	NetworkManager._connected_peer_ids.clear()
	if guest_peer != null:
		guest_peer.close()
	host_peer.close()
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	guest_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().set_multiplayer(null, guest_root.get_path())
	guest_api = null
	host_peer = null
	guest_peer = null
	main.queue_free()
	guest_root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("EVENT_CARDS_NETWORK_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _combat_card(identity: String) -> Dictionary:
	var data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	data["instance_id"] = identity
	data["effects"] = []
	data["attack"] = 100
	data["defense"] = 100
	return data


func _give_event(side: String, event_id: String) -> Dictionary:
	for index in range(host._event_deck.size()):
		if str(host._event_deck[index].get("id", "")) == event_id:
			var event := host._event_deck[index]
			host._event_deck.remove_at(index)
			if side == "player":
				host._player_event_hand.append(event)
			else:
				host._enemy_event_hand.append(event)
			return event
	check(false, "requested fixture event exists: " + event_id)
	return {}


func _hand_has_uid(hand: Array[Dictionary], uid: String) -> bool:
	return hand.any(func(event: Dictionary) -> bool: return str(event.get("uid", "")) == uid)


func _has_private_events(hand: Array[Dictionary]) -> bool:
	return hand.any(func(event: Dictionary) -> bool: return not str(event.get("uid", "")).is_empty())


func _check_opening_hands_over_enet() -> void:
	var old_local := NetworkManager.local_player_data.duplicate(true)
	var old_remote := NetworkManager.remote_player_data.duplicate(true)
	var host_deck: Array[Dictionary] = []
	var guest_deck: Array[Dictionary] = []
	for index in range(8):
		host_deck.append(_combat_card("opening-host-%d" % index))
		guest_deck.append(_combat_card("opening-guest-%d" % index))
	NetworkManager.local_player_data = {"name": "Host", "deck": host_deck}
	NetworkManager.remote_player_data = {"name": "Gast", "deck": guest_deck}
	host._online_mode = true
	host._online_is_host = true
	host._online_is_spectator = false
	host._online_action_in_progress = true
	guest._online_mode = true
	guest._online_is_host = false
	guest._online_is_spectator = false
	guest._online_action_in_progress = true
	await host._start_online_match()
	var arrived := await _wait_until(func(): return guest._player_event_hand.size() == 3 and guest._online_turn_sequence == 1 and not guest._online_action_in_progress)
	check(arrived, "real online match start deals and synchronizes three guest events before releasing turn one")
	check(host._player_event_hand.size() == 3 and host._enemy_event_hand.size() == 3 and host._event_deck.size() == 18, "host deals exactly three opening events to each fighter from the 24-card shared pile")
	check(host._online_pending_state_acks.is_empty() and not host._online_action_in_progress, "opening hand synchronization completes the real ENet ACK barrier")
	check(host._can_local_event_or_attack() and not host._event_played_this_turn and host._event_notice.is_empty(), "opening events are available on the first host turn without a next-turn notice")
	check(guest._player_event_hand == host._enemy_event_hand and not _has_private_events(guest._enemy_event_hand), "guest receives exactly its random opening hand and no host event identities")
	var original_host := host._player_event_hand.duplicate(true)
	var original_guest := guest._player_event_hand.duplicate(true)
	guest._rpc_request_online_state.rpc_id(1)
	await get_tree().create_timer(0.1).timeout
	check(host._player_event_hand == original_host and guest._player_event_hand == original_guest and host._event_deck.size() == 18, "requesting the opening snapshot again neither rerolls nor duplicates starting events")
	var public_state := host._build_online_snapshot()
	check(not public_state.has("own_event_hand") and int(public_state.get("player_event_hand_count", -1)) == 3 and int(public_state.get("enemy_event_hand_count", -1)) == 3, "public opening snapshot exposes equal hand counts without private cards")
	NetworkManager.local_player_data = old_local
	NetworkManager.remote_player_data = old_remote


func _check_event_rpcs() -> void:
	guest_id = guest_api.get_unique_id()
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, guest_id])
	NetworkManager._participants = {
		1: {"role": "player", "name": "Host"},
		guest_id: {"role": "player", "name": "Gast"},
	}
	await _check_opening_hands_over_enet()
	host._clear_match()
	guest._clear_match()
	host._reset_online_sync_tracking()
	guest._reset_online_sync_tracking()
	host._online_mode = true
	host._online_is_host = true
	host._online_is_spectator = false
	host._table_state = GameTable.TableState.PLAYING
	host._game_over = false
	host._current_turn = "enemy"
	host._online_turn_sequence = 11
	guest._online_mode = true
	guest._online_is_host = false
	guest._online_is_spectator = false
	host._player_deck.assign([_combat_card("host-reserve"), _combat_card("host-face")])
	host._enemy_deck.assign([_combat_card("guest-reserve"), _combat_card("guest-face")])
	host._draw_to_slot("player", 0, false)
	host._draw_to_slot("enemy", 0, false)
	host._initialize_event_deck()
	var host_steel := _give_event("player", "steel")
	var guest_strength := _give_event("enemy", "strength_200")
	var guest_block := _give_event("enemy", "block")
	var guest_switch := _give_event("enemy", "switch")
	if host_steel.is_empty() or guest_strength.is_empty() or guest_block.is_empty() or guest_switch.is_empty():
		return
	check(host._is_online_opponent(guest_id), "production sender authorization recognizes the actual guest peer")
	_check_snapshot_privacy(str(host_steel["uid"]))
	host._broadcast_online_snapshot(0)
	var initial_arrived := await _wait_until(func(): return guest._online_turn_sequence == 11 and guest._player_event_hand.size() == 3 and guest._get_card_from_slot("player", 0) != null)
	check(initial_arrived, "recipient snapshot delivers the guest hand through production ENet RPC")
	if not initial_arrived:
		return
	check(guest._current_turn == "player" and str(guest._player_slots[0].card_data.get("instance_id", "")) == "guest-face", "guest turn and combat-card coordinates are mirrored together")
	check(_hand_has_uid(guest._player_event_hand, str(guest_strength["uid"])) and not _has_private_events(guest._enemy_event_hand), "guest receives its event identities without learning the host hand")
	var strength_uid := str(guest_strength["uid"])
	guest._rpc_request_event.rpc_id(1, strength_uid, 0, 10)
	await get_tree().create_timer(0.1).timeout
	check(host._enemy_slots[0].attack_value == 100 and host._enemy_event_hand.size() == 3, "stale-turn event request cannot spend a card or change stats")
	guest._rpc_request_event.rpc_id(1, str(host_steel["uid"]), 0, 11)
	guest._rpc_request_event.rpc_id(1, strength_uid, 99, 11)
	guest._rpc_request_event.rpc_id(1, strength_uid, 1, 11)
	await get_tree().create_timer(0.1).timeout
	check(host._player_event_hand.size() == 1 and host._enemy_event_hand.size() == 3 and host._event_discard.is_empty(), "foreign event UID, out-of-range target and empty slot are rejected over ENet")
	host._current_turn = "player"
	guest._rpc_request_event.rpc_id(1, strength_uid, 0, 11)
	await get_tree().create_timer(0.1).timeout
	check(host._enemy_slots[0].attack_value == 100 and host._enemy_event_hand.size() == 3, "guest cannot play an event during the host turn")
	host._current_turn = "enemy"
	host._online_action_in_progress = true
	guest._rpc_request_event.rpc_id(1, strength_uid, 0, 11)
	await get_tree().create_timer(0.1).timeout
	check(host._enemy_event_hand.size() == 3 and host._enemy_slots[0].attack_value == 100, "event requests cannot interrupt an attack or synchronization barrier")
	host._online_action_in_progress = false
	guest._rpc_request_event.rpc_id(1, strength_uid, 0, 11)
	var strength_applied := await _wait_until(func(): return host._enemy_slots[0].attack_value == 200 and guest._player_slots[0].attack_value == 200 and guest._player_event_hand.size() == 2)
	check(strength_applied, "valid guest event is resolved on the authority and mirrored back to its own card")
	check(host._player_slots[0].attack_value == 100 and host._current_turn == "enemy" and host._online_turn_sequence == 11, "strength leaves opponent stats and the player's pending attack turn intact")
	check(host._enemy_event_hand.size() == 2 and host._event_discard.size() == 1 and host._event_played_this_turn, "event consumption and the once-per-turn flag remain authoritative")
	check(host._online_action_in_progress and guest._online_action_in_progress and not guest._can_local_event_or_attack(), "both peers keep input locked while the event is being revealed")
	var presented_sequence := guest._event_presented_sequence
	var reveal_deadline := guest._event_reveal_deadline_msec
	check(presented_sequence > 0 and Time.get_ticks_msec() < reveal_deadline and Time.get_ticks_msec() < host._event_reveal_deadline_msec, "host and guest begin the same public reveal before its lock expires")
	host._broadcast_online_snapshot(0)
	await get_tree().create_timer(0.18).timeout
	check(guest._event_presented_sequence == presented_sequence and guest._event_reveal_deadline_msec == reveal_deadline, "a duplicate event snapshot neither replays nor extends the reveal")
	check(host._online_action_in_progress and guest._online_action_in_progress and not host._online_pending_state_acks.is_empty(), "duplicate snapshots cannot acknowledge or unlock an unfinished reveal")
	var strength_unlocked := await _wait_until(func(): return not host._online_action_in_progress and host._online_pending_state_acks.is_empty(), 1000)
	check(strength_unlocked, "guest event snapshot ACK releases the real host barrier before timeout")
	check(Time.get_ticks_msec() >= reveal_deadline, "the event barrier releases only after the guest reveal has finished")
	guest._rpc_request_event.rpc_id(1, strength_uid, 0, 11)
	guest._rpc_request_event.rpc_id(1, str(guest_block["uid"]), 0, 11)
	await get_tree().create_timer(0.1).timeout
	check(host._enemy_slots[0].attack_value == 200 and host._enemy_event_hand.size() == 2 and host._event_discard.size() == 1 and not host._player_slots[0].is_event_blocked(), "replayed requests and a second distinct event cannot double-spend the turn")

	# Advance the fixture turn without a combat animation. Event and turn
	# state barriers still use the real ENet request and ACK handlers.
	host._online_turn_sequence = 12
	host._event_played_this_turn = false
	host._broadcast_online_snapshot(0)
	await _wait_until(func(): return guest._online_turn_sequence == 12)
	guest._rpc_request_event.rpc_id(1, str(guest_block["uid"]), 0, 12)
	var block_applied := await _wait_until(func(): return host._player_slots[0].event_block_turns == 2 and guest._enemy_slots[0].event_block_turns == 2)
	check(block_applied and not host._enemy_slots[0].is_event_blocked(), "guest Block targets the opposing host card and keeps mirrored block duration")
	var badge := guest._enemy_slots[0].get_node_or_null("EventBlockBadge") as Node3D
	check(badge != null and badge.visible, "networked block has a visible remaining-turn badge")
	var block_unlocked := await _wait_until(func(): return not host._online_action_in_progress and host._online_pending_state_acks.is_empty(), 1000)
	check(block_unlocked, "Block presentation completes its real ENet ACK barrier")
	await _check_spectator_rejection(str(guest_switch["uid"]))


func _check_snapshot_privacy(host_uid: String) -> void:
	var public_state := host._build_online_snapshot()
	check(not public_state.has("own_event_hand") and not str(public_state).contains(host_uid), "default broadcast-safe snapshot omits private event identities")
	check(int(public_state.get("player_event_hand_count", -1)) == 1 and int(public_state.get("enemy_event_hand_count", -1)) == 3, "public snapshot carries both hand counts")
	check(not public_state.has("event_deck") and not public_state.has("event_discard") and not public_state.has("player_event_hand") and not public_state.has("enemy_event_hand"), "public state never serializes shuffled event order or whole hands")
	var recipient_state := host._build_online_snapshot(0, guest_id)
	check(recipient_state.get("own_event_hand", []) == host._enemy_event_hand and not str(recipient_state).contains(host_uid), "recipient snapshot includes only that fighter's event hand")
	var copied_hand: Array = recipient_state.get("own_event_hand", [])
	if not copied_hand.is_empty():
		(copied_hand[0] as Dictionary)["uid"] = "mutated-copy"
	check(not _hand_has_uid(host._enemy_event_hand, "mutated-copy"), "recipient snapshot deep-copies authoritative hand data")
	check(not host._build_online_snapshot(0, 123456789).has("own_event_hand"), "unknown snapshot recipient receives no private cards")
	NetworkManager._participants[guest_id]["role"] = "spectator"
	check(not host._build_online_snapshot(0, guest_id).has("own_event_hand"), "connected spectator receives no fighter hand")
	NetworkManager._participants[guest_id]["role"] = "player"


func _check_spectator_rejection(switch_uid: String) -> void:
	host._online_turn_sequence = 13
	host._event_played_this_turn = false
	host._current_turn = "enemy"
	host._enemy_slots[0].apply_event_block(2)
	NetworkManager._participants[guest_id]["role"] = "spectator"
	guest._online_is_spectator = true
	check(not host._is_online_opponent(guest_id), "production authorization excludes a connected spectator")
	var host_reserve := host._player_deck.duplicate(true)
	var guest_reserve := host._enemy_deck.duplicate(true)
	guest._rpc_request_event.rpc_id(1, switch_uid, -1, 13)
	guest._rpc_request_event_pass.rpc_id(1, 13)
	await get_tree().create_timer(0.15).timeout
	check(host._enemy_event_hand.size() == 1 and host._event_discard.size() == 2 and not host._event_played_this_turn, "spectator cannot spend a known fighter event UID")
	check(host._player_deck == host_reserve and host._enemy_deck == guest_reserve and host._online_turn_sequence == 13 and host._current_turn == "enemy", "spectator event and pass commands cannot change decks or advance the turn")
	host._broadcast_online_snapshot(0)
	var spectator_arrived := await _wait_until(func(): return guest._online_turn_sequence == 13)
	check(spectator_arrived and not _has_private_events(guest._player_event_hand) and not _has_private_events(guest._enemy_event_hand), "spectator snapshot removes any previous private hand data")
	NetworkManager._participants[guest_id]["role"] = "player"
	guest._online_is_spectator = false
	host._online_turn_sequence = 14
	host._broadcast_online_snapshot(0)
	await _wait_until(func(): return guest._online_turn_sequence == 14)
	guest._rpc_request_event_pass.rpc_id(1, 14)
	var pass_applied := await _wait_until(func(): return host._online_turn_sequence == 15 and guest._online_turn_sequence == 15 and not host._online_action_in_progress)
	check(pass_applied and host._current_turn == "player" and guest._current_turn == "enemy", "fully blocked guest can pass through an authorized RPC and synchronized turn barrier")
	check(host._enemy_slots[0].event_block_turns == 1 and guest._player_slots[0].event_block_turns == 1, "passing ticks the blocked owner's card once on both peers")
	guest._rpc_request_event_pass.rpc_id(1, 14)
	await get_tree().create_timer(0.1).timeout
	check(host._online_turn_sequence == 15 and host._enemy_slots[0].event_block_turns == 1, "replayed pass cannot skip another turn or tick block twice")
