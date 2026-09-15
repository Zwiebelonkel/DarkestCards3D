extends Node

var failures := 0
var _departure_wait_finished := false
var _exit_finished := false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	await _check_transport_teardown()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	await _check_host_waits_for_guest_detachment(table)
	await _check_late_battle_state_during_exit(table)
	await _check_exit_waits_for_cinematic(table)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("MULTIPLAYER_EXIT_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_transport_teardown() -> void:
	var network = load("res://tests/fixtures/NetworkExitFixture.gd").new()
	add_child(network)
	network.current_lobby_id = 123
	network._match_in_progress = true
	network._connected_peer_ids.assign([1])
	network._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	var notifications := {"closing": 0, "closed": 0, "reset_before_closed": false}
	network.session_closing.connect(func(): notifications.closing += 1)
	network.session_closed.connect(func(_reason: String):
		notifications.closed += 1
		notifications.reset_before_closed = network.peer_reset_count == 1
	)
	network.receive_disconnect_callback()
	check(network.peer_reset_count == 0, "Disconnect callbacks never synchronously destroy the native peer")
	check(network._is_leaving, "Reentrant disconnects share one active teardown")
	check(not network.has_active_session() and not network.is_match_in_progress(), "Leaving immediately blocks new match and voice traffic")
	check(notifications.closing == 1 and notifications.closed == 0, "Consumers stop once before deferred peer cleanup")
	network._on_lobby_created(Steam.RESULT_OK, 321)
	network._on_lobby_joined(321, 0, 0, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network.peer_start_count == 0 and network.current_lobby_id == 0, "Late Steam create/join callbacks cannot restart a peer during teardown")
	for index in range(4):
		await get_tree().process_frame
	check(network.peer_reset_count == 1, "Repeated disconnect and leave notifications close the peer exactly once")
	check(not network.peer_reset_during_callback, "Peer cleanup runs after the callback has returned")
	check(notifications.closed == 1 and notifications.reset_before_closed, "Session closed is emitted once after peer cleanup")
	check(not network._is_leaving, "Teardown unlocks joining another lobby")
	network._on_lobby_created(Steam.RESULT_OK, 321)
	network._on_lobby_joined(321, 0, 0, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network.peer_start_count == 0 and not network.has_active_session(), "Retired lobby callbacks remain rejected after teardown finishes")
	network._joining_lobby_id = -1
	network._on_lobby_joined(456, 0, 0, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network._joining_lobby_id == -1 and network.peer_start_count == 0, "An early enter notification preserves an in-flight host create request")
	network._joining_lobby_id = 0
	network.queue_free()
	await get_tree().process_frame


func _configure_online_exit(table: GameTable, host: bool) -> void:
	table._reset_online_sync_tracking()
	table._online_mode = true
	table._online_is_host = host
	table._online_is_spectator = false
	table._online_active_exit_sequence = 1
	table._online_exit_local_finished = true
	NetworkManager.current_lobby_id = 123
	NetworkManager.is_host = host
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([2])
	NetworkManager._participants = {1: {"role": "player"}, 2: {"role": "player"}}


func _wait_for_guest(table: GameTable) -> void:
	await table._wait_for_online_exit_client_departure(1, 2)
	_departure_wait_finished = true


func _check_host_waits_for_guest_detachment(table: GameTable) -> void:
	_configure_online_exit(table, true)
	_departure_wait_finished = false
	_wait_for_guest(table)
	table._online_exit_finalize_acknowledged = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(not _departure_wait_finished, "Final ACK alone cannot close the host while the guest peer remains attached")
	check(NetworkManager.has_active_session(), "Host transport remains available until guest departure")
	NetworkManager._connected_peer_ids.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	check(_departure_wait_finished, "Guest departure releases the host without an additional timeout")
	_configure_online_exit(table, true)
	_departure_wait_finished = false
	_wait_for_guest(table)
	table._reset_online_sync_tracking()
	await get_tree().process_frame
	await get_tree().process_frame
	check(_departure_wait_finished, "An obsolete exit wait cannot retain a later session")


func _finish_local_exit(table: GameTable) -> void:
	await table._finalize_online_exit_local(1)
	_exit_finished = true


func _check_late_battle_state_during_exit(table: GameTable) -> void:
	_configure_online_exit(table, false)
	# Both cinematics reset the board before the guest detaches its transport.
	# An already queued state must not rebuild that board during the exit wait.
	table._show_main_menu()
	var previous_generation := table._match_generation
	table._online_queued_snapshot = {"turn_sequence": table._online_turn_sequence}
	table._online_client_presentation_depth = 1
	table._retire_online_battle_presentation()
	check(table._match_generation > previous_generation and table._online_client_presentation_depth == 0 and table._online_queued_snapshot.is_empty(), "Starting exit invalidates delayed battle callbacks and their queued snapshots")
	var card_data: Dictionary = CardDatabase.get_combat_cards()[0].duplicate(true)
	card_data["instance_id"] = "retired-match-card"
	var late_state := {
		"turn_sequence": table._online_turn_sequence,
		"current_turn": "player",
		"player_slots": [{"card_data": card_data}],
		"enemy_slots": [{"card_data": card_data}],
		"player_deck_count": 2,
		"enemy_deck_count": 2,
		"game_over": false,
	}
	table._apply_online_state_now(late_state)
	await get_tree().process_frame
	check(table._table_state == GameTable.TableState.MENU, "Late snapshot cannot reopen the battle after cinematic cleanup")
	check(not table._has_any_card(table._player_slots) and not table._has_any_card(table._enemy_slots), "Late snapshot cannot recreate freed cards while the peer is still attached")
	check(table._player_stack_visuals.is_empty() and table._enemy_stack_visuals.is_empty(), "Late snapshot cannot restart stack or replacement animations during exit")
	check(not table._has_live_online_client_session(), "Battle presentation closes before the exit handshake detaches the session")
	table._clear_match()


func _check_exit_waits_for_cinematic(table: GameTable) -> void:
	_configure_online_exit(table, false)
	table._loss_exit_running = true
	_exit_finished = false
	_finish_local_exit(table)
	table._finalize_online_exit_local(1)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not _exit_finished and NetworkManager.has_active_session(), "Duplicate finalize packets wait for the guest cinematic to finish")
	table._loss_exit_running = false
	for index in range(4):
		await get_tree().process_frame
	check(_exit_finished and not table._online_mode, "Guest returns to local mode after the animation completes")
	check(not NetworkManager.has_active_session(), "Guest releases its lobby after its cinematic")
	check(table._online_active_exit_sequence == 0 and not table._online_exit_finalizing, "Completed exit clears its barrier for subsequent matches")
	check(table.mode_buttons.visible, "Completed guest exit restores the mode menu")
