extends Node

var failures := 0
var client: GameTable
var sender: GameTable
var client_id := 0
var server_api: SceneMultiplayer
var server_peer: ENetMultiplayerPeer
var client_peer: ENetMultiplayerPeer


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
	client = main.get_node("ScenePivot/GameTable") as GameTable
	# A separate MultiplayerAPI gives the actual production RPCs a server peer
	# with the same relative node path. Only the transport autoload is a fixture.
	var server_root := Node.new()
	server_root.name = "TestServer"
	get_tree().root.add_child(server_root)
	server_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	var server_main := Node3D.new()
	server_main.name = main.name
	server_root.add_child(server_main)
	var scene_pivot := Node3D.new()
	scene_pivot.name = "ScenePivot"
	server_main.add_child(scene_pivot)
	var camera := Camera3D.new()
	server_main.add_child(camera)
	sender = (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	sender.table_camera = camera
	scene_pivot.add_child(sender)
	await get_tree().process_frame
	server_peer = ENetMultiplayerPeer.new()
	var port := 36000 + int(Time.get_ticks_msec() % 10000)
	var server_error := server_peer.create_server(port, 1)
	check(server_error == OK, "loopback ENet server starts")
	if server_error == OK:
		server_api.multiplayer_peer = server_peer
		client_peer = ENetMultiplayerPeer.new()
		var client_error := client_peer.create_client("127.0.0.1", port)
		check(client_error == OK, "joined-client ENet transport starts")
		if client_error == OK:
			get_tree().get_multiplayer().multiplayer_peer = client_peer
			var connected := await _wait_until(func(): return client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not server_api.get_peers().is_empty())
			check(connected, "separate host and joined-client peers connect")
			if connected:
				await _check_replacements()
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	client._online_mode = false
	if client_peer != null:
		client_peer.close()
	server_peer.close()
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	server_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().set_multiplayer(null, server_root.get_path())
	server_api = null
	server_peer = null
	client_peer = null
	main.queue_free()
	server_root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("REPLACEMENT_NETWORK_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _snapshot(prefix: String, turn: int, remaining: int) -> Dictionary:
	var near_data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	near_data["instance_id"] = prefix + "-guest"
	near_data["effects"] = []
	var far_data := near_data.duplicate(true)
	far_data["instance_id"] = prefix + "-host"
	return {
		"current_turn": "player", "turn_sequence": turn,
		"player_slots": [{"card_data": far_data}],
		"enemy_slots": [{"card_data": near_data}],
		"player_deck_count": remaining, "enemy_deck_count": remaining,
		"state_sync_sequence": turn, "game_over": false,
		"action_in_progress": false,
	}


func _cards_arrived(prefix: String) -> bool:
	for side: String in ["player", "enemy"]:
		var card := client._get_card_from_slot(side, 0)
		if not is_instance_valid(card):
			return false
		if not str(card.card_data.get("instance_id", "")).begins_with(prefix):
			return false
		if not card.global_position.is_equal_approx(client._get_slot_marker(side, 0).global_position) or not card.scale.is_equal_approx(Vector3.ONE):
			return false
	return not client._online_action_in_progress


func _check_replacements() -> void:
	client_id = get_tree().get_multiplayer().get_unique_id()
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, client_id])
	NetworkManager._participants = {
		1: {"role": "player", "name": "Host"},
		client_id: {"role": "player", "name": "Gast"},
	}
	client._online_mode = true
	client._online_is_host = false
	client._online_is_spectator = false
	# Sender is just the host transport endpoint; all presentation runs on the
	# regular client table and all ACKs travel back over ENet harmlessly.
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("first", 1, 4))
	var initial_arrived := await _wait_until(func(): return _cards_arrived("first"))
	check(initial_arrived, "authoritative initial snapshot creates the joined-client board over ENet")
	if not initial_arrived:
		return
	var original_near := client._player_slots[0]
	var original_far := client._enemy_slots[0]
	var first_impact := await _double_death_and_replace("second", 1, 1, 3)
	check(is_instance_valid(original_near) and is_instance_valid(original_far), "both original cards still fly after both replacements have arrived")
	check(client._pending_card_deaths.size() == 2 and not client._has_pending_card_replacements(), "cosmetic double death remains tracked without blocking the next turn")
	if not _cards_arrived("second"):
		return
	var second_near := client._player_slots[0]
	var second_far := client._enemy_slots[0]
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("second", 2, 3))
	var turn_arrived := await _wait_until(func(): return client._online_turn_sequence == 2)
	check(turn_arrived, "next authoritative turn starts before the old death flights finish")
	await _double_death_and_replace("third", 2, 2, 2)
	var cleanup_finished := await _wait_until(func(): return client._pending_card_deaths.is_empty(), 5000)
	check(cleanup_finished, "both consecutive double-death flights clean up without a stalled barrier")
	check(not is_instance_valid(original_near) and not is_instance_valid(original_far) and not is_instance_valid(second_near) and not is_instance_valid(second_far), "all four retired card nodes are safely freed")
	# A delayed packet still contains the old card identities after those nodes
	# have been freed. It must be rejected without touching their old contexts.
	sender._rpc_play_online_impact.rpc_id(client_id, first_impact)
	sender._rpc_play_online_attack.rpc_id(client_id, "player", 0, "enemy", 0, 1, 1)
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("first", 1, 4))
	await get_tree().create_timer(0.1).timeout
	check(_cards_arrived("third") and client._online_turn_sequence == 2, "late packets cannot revive freed cards or disturb the following turn")
	check(client._online_client_presentation_depth == 0 and client._online_queued_snapshot.is_empty(), "joined client finishes with no stranded presentation or snapshot")
	await _check_retired_match_packets()


func _check_retired_match_packets() -> void:
	# Keep both real ENet peers connected while mimicking the board cleanup at
	# the end of the cinematic. This used to reopen the board on a late packet.
	client._online_active_exit_sequence = 1
	client._retire_online_battle_presentation()
	client._show_main_menu()
	client._online_action_in_progress = true
	var late_turn := client._online_turn_sequence
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("retired", late_turn, 4))
	sender._rpc_play_online_attack.rpc_id(client_id, "player", 0, "enemy", 0, late_turn, 100)
	sender._rpc_play_online_impact.rpc_id(client_id, {"turn_sequence": late_turn, "attack_sequence": 100})
	sender._rpc_play_online_blood.rpc_id(client_id, late_turn, 100, 0, "player", 0, "burst", 1.0, false, "", -1)
	sender._rpc_apply_online_selection.rpc_id(client_id, "player", 0, late_turn)
	sender._rpc_release_online_turn.rpc_id(client_id, late_turn)
	await get_tree().create_timer(0.2).timeout
	check(client._table_state == GameTable.TableState.MENU and not client._has_any_card(client._player_slots) and not client._has_any_card(client._enemy_slots), "late battle RPCs cannot recreate the cleared board during the online exit handshake")
	check(client._online_queued_snapshot.is_empty() and client._online_queued_impact_events.is_empty() and client._online_queued_blood_events.is_empty(), "retired match packets do not retain freed-card contexts or queue new effects")
	check(client._online_action_in_progress and client._online_selected_slot == -1 and client._online_last_received_attack_sequence < 100, "late selection, attack and release packets cannot unlock or change the exit state")
	check(client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "exit protocol transport stays connected while battle traffic is retired")


func _double_death_and_replace(prefix: String, turn: int, sequence: int, remaining: int) -> Dictionary:
	var attacker_state := client._enemy_slots[0].get_network_state()
	var defender_state := client._player_slots[0].get_network_state()
	attacker_state["current_hp"] = 0
	defender_state["current_hp"] = 0
	var impact := {
		"turn_sequence": turn, "attack_sequence": sequence,
		"attacker_side": "player", "attacker_slot": 0,
		"defender_side": "enemy", "defender_slot": 0,
		"attacker_state": attacker_state, "defender_state": defender_state,
		"attacker_died": true, "defender_died": true,
	}
	sender._rpc_play_online_attack.rpc_id(client_id, "player", 0, "enemy", 0, turn, sequence)
	sender._rpc_play_online_impact.rpc_id(client_id, impact)
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot(prefix, turn, remaining))
	sender._rpc_release_online_turn.rpc_id(client_id, turn)
	var queued := await _wait_until(func(): return client._online_client_presentation_depth > 0 and not client._online_queued_snapshot.is_empty())
	check(queued, "%s replacement snapshot queues behind the real attack animation" % prefix)
	var death_started := await _wait_until(func(): return client._player_slots[0] == null)
	check(death_started, "%s impact releases the defender slot" % prefix)
	var start_msec := Time.get_ticks_msec()
	var arrived := await _wait_until(func(): return _cards_arrived(prefix))
	var elapsed_msec := Time.get_ticks_msec() - start_msec
	check(arrived and elapsed_msec < 1000, "%s mirrored replacements finish within 1s of death (%dms)" % [prefix, elapsed_msec])
	check(client._player_stack_visuals.size() == remaining and client._enemy_stack_visuals.size() == remaining, "%s queued replacement updates both remaining-card stacks" % prefix)
	return impact
