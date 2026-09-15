extends "res://tests/replacement_network_test.gd"

# Reuse the real two-peer ENet/actual Main fixture. All checks are ordinary
# branches, so the exact same assertions also run in an exported release PCK.
var _old_finalizer_returned := false
var _old_request_returned := false
var _close_observations := {"closing": 0, "closed": 0, "retired_at_closing": false}


class InviteNetworkFixture:
	extends "res://tests/fixtures/NetworkLifecycleFixture.gd"
	var join_requests: Array[int] = []

	# Observe resumed invitations without sending a real Steam request. The
	# production admission barrier, cancellation and callback handlers remain.
	func join_lobby(lobby_id: int, _as_spectator: bool = false) -> bool:
		if not _can_enter_lobby() or lobby_id <= 0:
			return false
		join_requests.append(lobby_id)
		_joining_lobby_id = lobby_id
		_session_generation += 1
		return true


class JoinCallbackFixture:
	extends "res://tests/fixtures/NetworkLifecycleFixture.gd"
	var validated_enter_lobbies: Array[int] = []

	func _lobby_is_compatible(lobby_id: int) -> bool:
		validated_enter_lobbies.append(lobby_id)
		# A fresh callback must reach validation; stop there because this fake
		# lobby has no Steam metadata or owner. Never query the SDK for fake IDs.
		return false


func _run() -> void:
	check(DeckManager.SAVE_PATH.begins_with("res://test-user/"), "Lifecycle fixture redirects player saves before autoload startup")
	await _check_native_teardown_order()
	await _check_pending_lobby_callbacks()
	await _check_canceled_join_retry()
	await _check_invites_during_lobby_barriers()
	await _check_queued_callback_generation()
	await _check_remote_lobby_host_departure()
	await _check_pending_lobby_ui()
	await super._run()
	print("NETWORK_LIFECYCLE_TESTS: " + ("PASS" if failures == 0 else "FAIL"))


func _frames(count: int = 4) -> void:
	for index in range(count):
		await get_tree().process_frame


func _new_network():
	var network = load("res://tests/fixtures/NetworkLifecycleFixture.gd").new()
	add_child(network)
	return network


func _check_native_teardown_order() -> void:
	var network = _new_network()
	# An unopened native peer has no Steam sockets and needs no Steam account.
	# A real ENet peer occupies MultiplayerAPI to make detachment observable.
	network._steam_peer = SteamMultiplayerPeer.new()
	var native_weak: WeakRef = weakref(network._steam_peer)
	var attached := ENetMultiplayerPeer.new()
	var error := attached.create_server(0, 1)
	check(error == OK, "Native teardown fixture creates an attached transport")
	if error == OK:
		get_tree().get_multiplayer().multiplayer_peer = attached
	network.current_lobby_id = 123
	network._match_in_progress = true
	network._connected_peer_ids.assign([1])
	network._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	var notices := {"closing": 0, "closed": 0, "released_before_closed": false}
	network.session_closing.connect(func():
		notices.closing += 1
		network.leave_lobby("Reentrant consumer close")
	)
	network.session_closed.connect(func(_reason: String):
		notices.closed += 1
		notices.released_before_closed = native_weak.get_ref() == null
	)
	network.receive_disconnect_callback()
	check(network.close_count == 0 and native_weak.get_ref() != null, "Native peer remains alive until all disconnect callbacks return")
	check(notices.closing == 1 and notices.closed == 0, "Reentrant closing observer schedules only one teardown")
	check(not network.has_active_session() and not network.is_match_in_progress(), "Closing invalidates session traffic synchronously")
	await _frames()
	check(network.close_count == 1 and not network.close_during_callback, "Production reset closes once outside the callback stack")
	check(network.detached_at_close and network.owner_cleared_at_close, "MultiplayerAPI detaches and owner clears before native close")
	check(native_weak.get_ref() == null and notices.released_before_closed, "Last native peer reference releases before session_closed")
	check(notices.closed == 1 and not network._is_leaving, "Deferred teardown completes once and unlocks future sessions")
	attached.close()
	network.queue_free()
	await _frames(2)


func _check_pending_lobby_callbacks() -> void:
	var creating = _new_network()
	creating._joining_lobby_id = -1
	creating.leave_lobby("Cancel creation before Steam replies")
	await _frames()
	check(creating._cancelled_create_pending and not creating._can_enter_lobby(), "Canceled create blocks a new request until its unidentifiable result arrives")
	creating._on_lobby_joined(700, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(creating._cancelled_create_pending and creating.peer_start_count == 0, "Early enter cannot consume the canceled-create barrier")
	creating._on_lobby_created(Steam.RESULT_OK, 700)
	await _frames(2)
	check(not creating._cancelled_create_pending and creating._can_enter_lobby() and creating.peer_start_count == 0, "Retired create callback releases admission without starting its stale peer")
	creating.queue_free()
	await _frames(2)
	for pending_id in [-1, 701]:
		var network = _new_network()
		network._joining_lobby_id = pending_id
		network.leave_lobby("Cancel pending lobby operation")
		check(network._joining_lobby_id == 0 and network._is_leaving, "Cancel %d immediately retires its pending operation" % pending_id)
		network._on_lobby_created(Steam.RESULT_OK, 701)
		network._on_lobby_joined(701, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
		await _frames()
		network._on_lobby_created(Steam.RESULT_OK, 701)
		network._on_lobby_joined(701, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
		await _frames(2)
		check(network.peer_start_count == 0 and not network.has_active_session(), "Canceled %d cannot start a peer from late create or join callbacks" % pending_id)
		check(network.abandoned_lobbies.has(701), "Late successful lobby callback explicitly retires its Steam lobby")
		network.queue_free()
		await _frames(2)
	var network = _new_network()
	network._joining_lobby_id = 702
	network._on_lobby_joined(701, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network._joining_lobby_id == 702 and network.peer_start_count == 0, "A stale join callback preserves a different pending lobby")
	network._joining_lobby_id = -1
	network._on_lobby_joined(703, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network._joining_lobby_id == -1 and network.peer_start_count == 0, "Early own-lobby enter cannot consume the pending create request")
	network._joining_lobby_id = 0
	network.queue_free()
	await _frames(2)


func _check_canceled_join_retry() -> void:
	var network := JoinCallbackFixture.new()
	add_child(network)
	network._joining_lobby_id = 740
	network.leave_lobby("Cancel join before Steam replies")
	await _frames()
	check(network._cancelled_join_lobby_id == 740 and network.is_lobby_operation_pending(), "Canceled join remains pending after local teardown until its Steam result")
	check(not network.join_lobby(740) and network._joining_lobby_id == 0, "Retry of the same lobby is blocked before the canceled join result")
	network._on_lobby_joined(741, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network._cancelled_join_lobby_id == 740, "A different lobby callback cannot release the canceled join barrier")
	network._on_lobby_joined(740, 0, false, 2)
	check(not network.is_lobby_operation_pending() and network._can_enter_lobby() and network.peer_start_count == 0, "Old failed join releases admission without starting a peer or consuming a retry")
	# With the old response consumed, the next request for A can safely own A's
	# next enter callback. Only request submission into Steam is simulated.
	network._joining_lobby_id = 740
	network._session_generation += 1
	network._on_lobby_joined(740, 0, false, Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS)
	check(network.validated_enter_lobbies == [740], "Fresh successful retry reaches lobby validation instead of being discarded after the old failure")
	var safe_state := preload("res://scripts/autoload/SessionDiagnostics.gd")._sanitize_state({"response": 2, "payload": "private"})
	check(safe_state.get("response") == 2 and not safe_state.has("payload"), "Diagnostics preserve the Steam enter response while excluding payloads")
	await _frames()
	network.queue_free()
	await _frames(2)


func _check_invites_during_lobby_barriers() -> void:
	for pending_id in [-1, 750]:
		var network := InviteNetworkFixture.new()
		add_child(network)
		network._joining_lobby_id = pending_id
		network._on_join_requested(760, 0)
		check(network._is_leaving and network._pending_invite_lobby_id == 760, "Invite during pending %d retires that request and keeps the invited lobby" % pending_id)
		await _frames()
		check(network.is_lobby_operation_pending() and network.join_requests.is_empty(), "Invite waits beyond local teardown for canceled %d Steam result" % pending_id)
		network._on_join_requested(770, 0)
		await _frames(1)
		check(network._pending_invite_lobby_id == 770 and network.join_requests.is_empty(), "Latest invite remains queued while canceled %d barrier is active" % pending_id)
		if pending_id == -1:
			network._on_lobby_created(2, 0)
		else:
			network._on_lobby_joined(pending_id, 0, false, 2)
		await _frames(2)
		check(network.join_requests == [770] and network._joining_lobby_id == 770 and network._pending_invite_lobby_id == 0, "Settled canceled %d resumes the latest invitation exactly once" % pending_id)
		network.queue_free()
		await _frames(2)


func _check_queued_callback_generation() -> void:
	var network = _new_network()
	network.current_lobby_id = 801
	var received := {"count": 0, "value": 0}
	var callback := func(value: int):
		received.count += 1
		received.value = value
	network._queue_peer_event(callback, [7])
	check(received.count == 0, "Native peer callback only queues work while its callback stack is active")
	await _frames(1)
	check(received.count == 1 and received.value == 7, "Queued callback dispatches once for the current session")
	var retired_generation: int = network._session_generation
	network._queue_peer_event(callback, [8])
	network.leave_lobby("Retire queued native callback")
	await _frames()
	check(received.count == 1, "Leave invalidates an already queued native callback")
	network.current_lobby_id = 802
	network._session_generation += 1
	network._dispatch_peer_event(callback, [9], retired_generation)
	check(received.count == 1 and network.current_lobby_id == 802, "Old transport generation cannot dispatch into a newly opened lobby")
	network._dispatch_peer_event(callback, [10], network._session_generation)
	check(received.count == 2 and received.value == 10, "Fresh generation continues receiving native events")
	network.queue_free()
	await _frames(2)


func _check_remote_lobby_host_departure() -> void:
	var network = _new_network()
	network.current_lobby_id = 811
	network.is_host = false
	network._host_steam_id = 11001
	var notices := {"closed": 0}
	network.session_closed.connect(func(_reason: String): notices.closed += 1)
	network._on_lobby_chat_update(999, 11001, 11001, Steam.CHAT_MEMBER_STATE_CHANGE_LEFT)
	network._on_lobby_chat_update(811, 22002, 22002, Steam.CHAT_MEMBER_STATE_CHANGE_LEFT)
	check(network.current_lobby_id == 811 and not network._is_leaving, "Another lobby or member departure cannot close the guest lobby")
	network._on_lobby_chat_update(811, 11001, 11001, Steam.CHAT_MEMBER_STATE_CHANGE_LEFT)
	check(network._is_leaving and not network.has_active_session(), "Original host leaving closes a waiting guest even before P2P connects")
	network._on_lobby_chat_update(811, 11001, 11001, Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED)
	network._on_server_disconnected()
	await _frames()
	check(notices.closed == 1, "Lobby departure and native disconnect produce one completed teardown")
	network.queue_free()
	await _frames(2)


func _configure_client() -> void:
	client_id = get_tree().get_multiplayer().get_unique_id()
	NetworkManager.current_lobby_id = 901
	NetworkManager.is_host = false
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1])
	NetworkManager._participants = {1: {"role": "player"}, client_id: {"role": "player"}}
	client._online_mode = true
	client._online_is_host = false
	client._online_is_spectator = false
	client._reset_online_sync_tracking()
	client._online_turn_sequence = 1
	client._game_over = false
	client._table_state = GameTable.TableState.PLAYING
	client.mode_buttons.visible = false
	client.end_buttons.visible = false


func _wait_old_finalizer() -> void:
	await client._finalize_online_exit_local(1)
	_old_finalizer_returned = true


func _wait_old_request() -> void:
	await client._wait_for_online_exit_response(1)
	_old_request_returned = true


func _check_exit_generation_reuse() -> void:
	_configure_client()
	client._online_active_exit_sequence = 1
	client._loss_exit_running = true
	_wait_old_finalizer()
	await _frames(1)
	check(not _old_finalizer_returned and client._online_exit_finalizing, "Old finalizer really waits for an in-flight cinematic")
	_configure_client()
	client._online_active_exit_sequence = 1
	client._match_status_message = "new-session-sentinel"
	client._loss_exit_running = false
	await _frames()
	check(_old_finalizer_returned, "Retired cinematic finalizer returns when its generation changes")
	check(NetworkManager.current_lobby_id == 901 and client._online_mode and not client.mode_buttons.visible, "Old exit sequence 1 cannot close the next session's exit sequence 1")
	check(client._match_status_message == "new-session-sentinel" and not client._online_exit_finalizing, "Retired finalizer leaves new session UI and finalization flags intact")
	_configure_client()
	client._online_exit_requested = true
	_wait_old_request()
	await _frames(1)
	check(not _old_request_returned, "Old exit request really awaits its response")
	_configure_client()
	client._match_status_message = "new-request-sentinel"
	client._online_action_in_progress = true
	await _frames()
	check(_old_request_returned and client._online_action_in_progress and client._match_status_message == "new-request-sentinel", "Retired exit request cannot unlock or overwrite a later turn 1")
	_configure_client()


func _check_pending_lobby_ui() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await _frames(1)
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table.matchmaking_screen.visible = true
	NetworkManager._joining_lobby_id = -1
	table.matchmaking_screen._update_controls()
	check(not table.matchmaking_screen.back_button.disabled, "Pending lobby operation keeps its visible Cancel control enabled")
	table.matchmaking_screen._on_back_pressed()
	check(NetworkManager._is_leaving and NetworkManager._joining_lobby_id == 0, "Lobby Back cancels a pending create even without an active lobby ID")
	await _frames()
	NetworkManager._on_lobby_created(Steam.RESULT_OK, 900)
	await _frames(2)
	check(not NetworkManager.is_lobby_operation_pending() and not table.matchmaking_screen.visible, "Late canceled create leaves lobby UI closed and permits another operation")
	main.queue_free()
	await _frames(2)


func _check_replacements() -> void:
	await _check_exit_generation_reuse()
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("before-disconnect", 1, 4))
	var arrived := await _wait_until(func(): return _cards_arrived("before-disconnect"))
	check(arrived, "Actual host RPC constructs client cards before disconnect regression")
	if not arrived:
		return
	var previous_generation := client._match_generation
	var closing_callback := func():
		_close_observations.closing += 1
		_close_observations.retired_at_closing = client._match_generation > previous_generation and client._online_client_presentation_depth == 0 and client._online_queued_snapshot.is_empty()
	var closed_callback := func(_reason: String): _close_observations.closed += 1
	NetworkManager.session_closing.connect(closing_callback)
	NetworkManager.session_closed.connect(closed_callback)
	NetworkManager._connect_multiplayer_signals()
	sender._rpc_play_online_attack.rpc_id(client_id, "player", 0, "enemy", 0, 1, 1)
	sender._rpc_apply_online_state.rpc_id(client_id, _snapshot("must-not-arrive", 1, 3))
	var queued := await _wait_until(func(): return client._online_client_presentation_depth > 0 and not client._online_queued_snapshot.is_empty())
	check(queued, "Real attack coroutine and replacement snapshot are pending at disconnect")
	server_peer.disconnect_peer(client_id)
	var closed := await _wait_until(func(): return _close_observations.closed > 0)
	check(closed, "Remote host departure reaches production teardown through ENet server_disconnected")
	check(_close_observations.closing == 1 and _close_observations.closed == 1 and _close_observations.retired_at_closing, "Session closing retires attack and queued replacement before native teardown")
	check(not NetworkManager.has_active_session() and get_tree().get_multiplayer().multiplayer_peer is OfflineMultiplayerPeer, "Guest transport is detached after actual server loss")
	check(client._table_state == GameTable.TableState.GAME_OVER and client.end_buttons.visible, "Disconnect during attack leaves a usable result and Exit control")
	await get_tree().create_timer(1.2).timeout
	check(client._online_client_attack_contexts.is_empty() and client._online_client_presentation_depth == 0 and client._online_queued_snapshot.is_empty(), "Late animation completion cannot resurrect retired contexts or replacements")
	check(str(client._player_slots[0].card_data.get("instance_id", "")).begins_with("before-disconnect"), "Queued replacement never overwrites disconnected result cards")
	client._show_main_menu()
	await _frames(2)
	check(not client._has_any_card(client._player_slots) and not client._has_any_card(client._enemy_slots) and client._pending_card_deaths.is_empty(), "Exit safely clears all cards and pending animation jobs")
	NetworkManager.session_closing.disconnect(closing_callback)
	NetworkManager.session_closed.disconnect(closed_callback)
