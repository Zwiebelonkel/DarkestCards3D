extends Node

const DIAGNOSTICS := preload("res://scripts/autoload/SessionDiagnostics.gd")

signal steam_status_changed(ready: bool, message: String)
signal lobby_list_updated(lobbies: Array)
signal lobby_state_changed
signal connection_state_changed
signal match_started
signal session_closing
signal session_closed(reason: String)
signal voice_packet_received(
	stream_id: int,
	sequence: int,
	pitch_percent: int,
	payload: PackedByteArray
)

const APP_ID := 480
const PROTOCOL_VERSION := 6
const MAX_PLAYERS := 2
const MAX_SPECTATORS := 2
const MAX_LOBBY_MEMBERS := MAX_PLAYERS + MAX_SPECTATORS
const ROLE_PLAYER := "player"
const ROLE_SPECTATOR := "spectator"
const MAX_DECK_SIZE := 20
const MAX_STAT_BONUS := 100
const VOICE_MAX_PACKET_BYTES := 4096
const VOICE_MAX_PACKETS_PER_SECOND := 120
const VOICE_MAX_BYTES_PER_SECOND := 96 * 1024
const VOICE_MAX_STREAM_ID := 2_000_000_000
const VOICE_MAX_SEQUENCE := 1_999_999_999

const LOBBY_GAME_KEY := "game"
const LOBBY_GAME_VALUE := "darkest_cards_3d"
const LOBBY_PROTOCOL_KEY := "protocol"
const LOBBY_STATUS_KEY := "status"
const LOBBY_STATUS_WAITING := "waiting"
const LOBBY_STATUS_PLAYING := "playing"

var steam_ready := false
var current_lobby_id := 0
var is_host := false
var lobby_entries: Array[Dictionary] = []
var local_player_data: Dictionary = {}
var remote_player_data: Dictionary = {}

var _steam_peer: SteamMultiplayerPeer = null
var _connected_peer_ids: Array[int] = []
# Only the host admits participants. Decks stay on the host; the replicated
# roster contains identity and role only, never another player's hidden deck.
var _participants: Dictionary = {}
var _requested_role := ROLE_PLAYER
var _match_in_progress := false
var _is_leaving := false
var _is_shutting_down := false
var _session_generation := 0
var _host_steam_id := 0
var _cancelled_create_pending := false
var _cancelled_join_lobby_id := 0
var _multiplayer_signals_connected := false
var _abandoned_lobbies: Dictionary = {}
var _joining_lobby_id := 0
var _pending_invite_lobby_id := 0
var _invite_dialog_pending := false
var _voice_rate_peer_id := 0
var _voice_rate_window_started_msec := 0
var _voice_rate_packet_count := 0
var _voice_rate_byte_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_launch_invite()
	_connect_steam_signals()
	_connect_multiplayer_signals()
	_initialize_steam()


func _process(_delta: float) -> void:
	# GodotSteam 4.22 cannot embed callbacks together with engine-startup
	# initialization, so one always-running autoload pumps them explicitly.
	# Once local teardown starts, the old peer must not receive another Steam
	# disconnect callback while its sockets and queued packets are being retired.
	# Lobby callbacks resume as soon as the peer has been closed and released.
	if steam_ready and not _is_shutting_down and not _is_leaving:
		Steam.run_callbacks()


func _exit_tree() -> void:
	DIAGNOSTICS.note_shutdown("network_exit_tree")
	_is_shutting_down = true
	_is_leaving = true
	_session_generation += 1
	# Release native peers while Steam is still available. Its destructor also
	# calls close(); no peer may survive steamShutdown().
	_reset_multiplayer_peer()
	if current_lobby_id > 0 and steam_ready:
		Steam.leaveLobby(current_lobby_id)
	if steam_ready:
		trace_session_event("steam shutdown begin")
		Steam.steamShutdown()
		trace_session_event("steam shutdown returned")
	steam_ready = false


func _connect_steam_signals() -> void:
	_connect_steam_signal(Steam.lobby_created, _on_lobby_created)
	_connect_steam_signal(Steam.lobby_joined, _on_lobby_joined)
	_connect_steam_signal(Steam.lobby_match_list, _on_lobby_match_list)
	_connect_steam_signal(Steam.lobby_chat_update, _on_lobby_chat_update)
	_connect_steam_signal(Steam.join_requested, _on_join_requested)
	# These observers only write flushed diagnostics. They run before deferred
	# game handlers, retaining the native disconnect reason even if Steam faults.
	if not Steam.network_connection_status_changed.is_connected(_trace_native_connection):
		Steam.network_connection_status_changed.connect(_trace_native_connection)
	if not Steam.lobby_chat_update.is_connected(_trace_native_lobby_update):
		Steam.lobby_chat_update.connect(_trace_native_lobby_update)


func _connect_steam_signal(steam_signal: Signal, callback: Callable) -> void:
	if not steam_signal.is_connected(callback):
		# Creating/destroying a Steam peer registers native callbacks. Do that
		# only after Steam.run_callbacks() has finished dispatching its own list.
		steam_signal.connect(callback, CONNECT_DEFERRED)


func _capture_launch_invite() -> void:
	# Steam uses this command-line pair when an invitation launches a game that
	# was not already running. The joined lobby is still validated afterwards.
	var arguments := OS.get_cmdline_args()
	for index in range(arguments.size()):
		var argument := str(arguments[index])
		var lobby_id := 0
		if argument == "+connect_lobby" and index + 1 < arguments.size():
			lobby_id = int(str(arguments[index + 1]))
		elif argument.begins_with("+connect_lobby="):
			lobby_id = int(argument.trim_prefix("+connect_lobby="))
		if lobby_id > 0:
			_pending_invite_lobby_id = lobby_id
			return


func _connect_multiplayer_signals() -> void:
	if _multiplayer_signals_connected:
		return
	_multiplayer_signals_connected = true
	multiplayer.peer_connected.connect(func(peer_id: int): _queue_peer_event(_on_peer_connected, [peer_id]))
	multiplayer.peer_disconnected.connect(func(peer_id: int): _queue_peer_event(_on_peer_disconnected, [peer_id]))
	multiplayer.connected_to_server.connect(func(): _queue_peer_event(_on_connected_to_server))
	multiplayer.connection_failed.connect(func(): _queue_peer_event(_on_connection_failed))
	multiplayer.server_disconnected.connect(func(): _queue_peer_event(_on_server_disconnected))


func _queue_peer_event(callback: Callable, arguments: Array = []) -> void:
	DIAGNOSTICS.record("online.peer.signal", {"event": str(callback.get_method()), "generation": _session_generation, "leaving": _is_leaving})
	_dispatch_peer_event.call_deferred(callback, arguments, _session_generation)


func _dispatch_peer_event(callback: Callable, arguments: Array, generation: int) -> void:
	if generation != _session_generation or _is_leaving or _is_shutting_down or current_lobby_id <= 0:
		DIAGNOSTICS.record("online.peer.stale_callback", {"event": str(callback.get_method()), "generation": generation, "current_generation": _session_generation})
		return
	callback.callv(arguments)


func _trace_native_connection(_handle: int, connection: Dictionary, old_state: int) -> void:
	DIAGNOSTICS.record("steam.connection.callback", {
		"old_state": old_state, "connection_state": int(connection.get("connection_state", -1)),
		"end_reason": int(connection.get("end_reason", 0)), "is_host": is_host,
		"message": str(connection.get("end_debug", "")),
		"generation": _session_generation, "leaving": _is_leaving,
	})


func _trace_native_lobby_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	DIAGNOSTICS.record("steam.lobby.callback", {
		"active_lobby": lobby_id == current_lobby_id, "original_host_changed": changed_id == _host_steam_id,
		"chat_state": chat_state, "generation": _session_generation, "leaving": _is_leaving,
	})


func _initialize_steam() -> void:
	if _is_shutting_down:
		return
	if not Engine.has_singleton("Steam"):
		steam_ready = false
		steam_status_changed.emit(false, "GodotSteam wurde nicht geladen.")
		return

	# GodotSteam initializes at engine startup through project.godot. This is
	# early enough for the Steam overlay to hook the graphics device.
	var result: Dictionary = Steam.get_steam_init_result()
	if result.is_empty():
		# Fallback for development setups without automatic initialization.
		result = Steam.steamInitEx(APP_ID, false)
	_apply_steam_init_result(result)


func _apply_steam_init_result(result: Dictionary) -> void:
	var status := int(result.get("status", -1))
	DIAGNOSTICS.record("steam.init", {"status": status, "version": str(Steam.get_godotsteam_version()), "debug_build": OS.is_debug_build()})
	if OS.get_name() == "Windows":
		var dll_name := "libgodotsteam.windows.template_%s.x86_64.dll" % ("debug" if OS.is_debug_build() else "release")
		var dll_path := OS.get_executable_path().get_base_dir().path_join(dll_name)
		if not FileAccess.file_exists(dll_path):
			dll_path = "res://addons/godotsteam/win64/" + dll_name
		DIAGNOSTICS.record("steam.binary", {"library": dll_name, "sha256": FileAccess.get_sha256(dll_path)})
	if status != Steam.STEAM_API_INIT_RESULT_OK:
		steam_ready = false
		var detail := str(result.get("verbal", "Unbekannter Steam-Fehler")).strip_edges()
		steam_status_changed.emit(false, Localization.format_text("Steam konnte nicht gestartet werden: %s", [Localization.localized_arg(detail) if detail == "Unbekannter Steam-Fehler" else detail]))
		return

	steam_ready = true
	Steam.initRelayNetworkAccess()
	_refresh_local_player_data()
	steam_status_changed.emit(true, Localization.format_text("Steam verbunden als %s.", [Steam.getPersonaName()]))
	if _pending_invite_lobby_id > 0:
		var invited_lobby_id := _pending_invite_lobby_id
		_pending_invite_lobby_id = 0
		join_lobby.call_deferred(invited_lobby_id)


func request_lobbies() -> bool:
	if not _require_steam():
		return false
	if current_lobby_id > 0:
		_report("Verlasse zuerst die aktuelle Lobby.")
		return false

	# App 480 is shared by many test projects; filters are mandatory and apply
	# only to this one request.
	Steam.addRequestLobbyListStringFilter(LOBBY_GAME_KEY, LOBBY_GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(LOBBY_PROTOCOL_KEY, str(PROTOCOL_VERSION), Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(LOBBY_STATUS_KEY, LOBBY_STATUS_WAITING, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(50)
	Steam.requestLobbyList()
	return true


func create_lobby() -> bool:
	if not _can_enter_lobby():
		return false
	_requested_role = ROLE_PLAYER
	_refresh_local_player_data()
	if _local_deck_is_empty():
		_report("Dein Kampfdeck ist leer. Baue zuerst ein Deck.")
		return false

	# A negative value marks the asynchronous create request as pending. This
	# prevents double-clicks from creating multiple Steam lobbies.
	_joining_lobby_id = -1
	_session_generation += 1
	trace_session_event("lobby create requested")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_LOBBY_MEMBERS)
	return true


func join_lobby(lobby_id: int, as_spectator: bool = false) -> bool:
	if not _can_enter_lobby() or lobby_id <= 0:
		return false
	_requested_role = ROLE_SPECTATOR if as_spectator else ROLE_PLAYER
	_refresh_local_player_data()
	if not as_spectator and _local_deck_is_empty():
		_report("Dein Kampfdeck ist leer. Baue zuerst ein Deck.")
		return false

	_joining_lobby_id = lobby_id
	_session_generation += 1
	trace_session_event("lobby join requested")
	Steam.joinLobby(lobby_id)
	return true


func invite_friends() -> bool:
	if not steam_ready or current_lobby_id <= 0:
		return false
	if Steam.isOverlayEnabled():
		Steam.activateGameOverlayInviteDialog(current_lobby_id)
		return true
	if _invite_dialog_pending:
		return true

	_invite_dialog_pending = true
	_report("Steam-Overlay wird geladen …")
	_open_invite_dialog_when_ready(current_lobby_id)
	return true


func _open_invite_dialog_when_ready(lobby_id: int) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if _is_shutting_down or current_lobby_id != lobby_id or not steam_ready:
			_invite_dialog_pending = false
			return
		if Steam.isOverlayEnabled():
			_invite_dialog_pending = false
			Steam.activateGameOverlayInviteDialog(lobby_id)
			_report("Steam-Freundesliste geöffnet.")
			return
		await get_tree().create_timer(0.25).timeout

	_invite_dialog_pending = false
	_report("Steam-Overlay ist nicht aktiv. Starte das Spiel über Steam und prüfe, ob das Overlay aktiviert ist.")


func leave_lobby(reason: String = "Lobby verlassen.") -> void:
	if _is_leaving or _is_shutting_down:
		return
	if current_lobby_id <= 0 and _joining_lobby_id == 0 and _steam_peer == null:
		return
	trace_session_event("leave requested: " + reason)
	_is_leaving = true
	_session_generation += 1
	_cancelled_create_pending = _cancelled_create_pending or _joining_lobby_id == -1
	if _joining_lobby_id > 0:
		_cancelled_join_lobby_id = _joining_lobby_id

	var old_lobby_id := current_lobby_id
	current_lobby_id = 0
	_host_steam_id = 0
	is_host = false
	remote_player_data.clear()
	_connected_peer_ids.clear()
	_participants.clear()
	_requested_role = ROLE_PLAYER
	_match_in_progress = false
	_joining_lobby_id = 0
	_invite_dialog_pending = false
	_reset_voice_rate_limit()

	# Voice capture and all session consumers must stop while Steam is still
	# fully initialized. The native peer is deliberately kept alive for one more
	# frame so callbacks already on the stack can return before it is detached.
	session_closing.emit()
	connection_state_changed.emit()
	_finish_session_teardown.call_deferred(old_lobby_id, reason, _session_generation)


func _finish_session_teardown(old_lobby_id: int, reason: String, generation: int) -> void:
	await get_tree().process_frame
	if _is_shutting_down or generation != _session_generation:
		return

	_reset_multiplayer_peer()
	if old_lobby_id > 0 and steam_ready:
		trace_session_event("steam lobby leave begin")
		Steam.leaveLobby(old_lobby_id)
		trace_session_event("steam lobby leave returned")

	_is_leaving = false
	trace_session_event("peer teardown completed")
	lobby_state_changed.emit()
	session_closed.emit(reason)
	_join_pending_invite_if_any()


func trace_session_event(event: String) -> void:
	DIAGNOSTICS.record("online.session", {"event": event, "generation": _session_generation,
		"is_host": is_host, "active_lobby": current_lobby_id > 0, "leaving": _is_leaving,
		"peer_count": _connected_peer_ids.size(), "match_in_progress": _match_in_progress})
	print("[OnlineSession %d] %s" % [Time.get_ticks_msec(), event])


func _join_pending_invite_if_any() -> void:
	if _pending_invite_lobby_id <= 0 or _is_shutting_down or current_lobby_id > 0 or is_lobby_operation_pending():
		return
	var invited_lobby_id := _pending_invite_lobby_id
	_pending_invite_lobby_id = 0
	join_lobby.call_deferred(invited_lobby_id)


func has_active_session() -> bool:
	return current_lobby_id > 0


func has_connected_opponent() -> bool:
	return get_connected_opponent_peer_id() > 0


func get_connected_opponent_peer_id() -> int:
	if _is_leaving or _is_shutting_down or current_lobby_id <= 0:
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return 0
	if is_local_spectator():
		return 0
	for peer_id in get_fighter_peer_ids():
		if peer_id != multiplayer.get_unique_id() and _connected_peer_ids.has(peer_id):
			return peer_id
	return 0


func is_local_spectator() -> bool:
	if _is_leaving or _is_shutting_down or current_lobby_id <= 0:
		return _requested_role == ROLE_SPECTATOR
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return _requested_role == ROLE_SPECTATOR
	var local_id := multiplayer.get_unique_id()
	if _participants.has(local_id):
		return is_spectator_peer(local_id)
	return _requested_role == ROLE_SPECTATOR


func is_spectator_peer(peer_id: int) -> bool:
	return str((_participants.get(peer_id, {}) as Dictionary).get("role", "")) == ROLE_SPECTATOR


func get_participant_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id: Variant in _participants:
		result.append(int(peer_id))
	result.sort()
	return result


func get_connected_participant_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id in get_participant_peer_ids():
		if _connected_peer_ids.has(peer_id):
			result.append(peer_id)
	return result


func get_fighter_peer_ids() -> Array[int]:
	return _get_peer_ids_for_role(ROLE_PLAYER)


func get_spectator_peer_ids() -> Array[int]:
	return _get_peer_ids_for_role(ROLE_SPECTATOR)


func _get_peer_ids_for_role(role: String) -> Array[int]:
	var result: Array[int] = []
	for peer_id in get_participant_peer_ids():
		if str((_participants[peer_id] as Dictionary).get("role", "")) == role:
			result.append(peer_id)
	return result


func get_player_data_for_peer(peer_id: int) -> Dictionary:
	return (_participants.get(peer_id, {}) as Dictionary).duplicate(true)


func is_connected_game_peer(peer_id: int) -> bool:
	return (
		peer_id > 0
		and _steam_peer != null
		and current_lobby_id > 0
		and _match_in_progress
		and _connected_peer_ids.has(peer_id)
		and _participants.has(peer_id)
	)


func send_voice_packet(
	stream_id: int,
	sequence: int,
	pitch_percent: int,
	payload: PackedByteArray
) -> bool:
	if (
		not _match_in_progress
		or stream_id <= 0
		or stream_id > VOICE_MAX_STREAM_ID
		or sequence < 0
		or sequence > VOICE_MAX_SEQUENCE
		or pitch_percent < 35
		or pitch_percent > 90
		or payload.is_empty()
		or payload.size() > VOICE_MAX_PACKET_BYTES
	):
		return false
	var opponent_peer_id := get_connected_opponent_peer_id()
	if not is_connected_game_peer(opponent_peer_id):
		return false
	_rpc_receive_voice_packet.rpc_id(
		opponent_peer_id,
		stream_id,
		sequence,
		pitch_percent,
		payload
	)
	return true


func is_lobby_operation_pending() -> bool:
	return _joining_lobby_id != 0 or _is_leaving or _cancelled_create_pending or _cancelled_join_lobby_id > 0


func is_match_in_progress() -> bool:
	return _match_in_progress


func end_match() -> void:
	if not _match_in_progress:
		return
	_match_in_progress = false
	_reset_voice_rate_limit()
	connection_state_changed.emit()


func can_start_match() -> bool:
	return (
		steam_ready
		and is_host
		and current_lobby_id > 0
		and has_connected_opponent()
		and not _local_deck_is_empty()
		and _player_data_has_deck(remote_player_data)
		and get_connected_participant_peer_ids().size() == _connected_peer_ids.size()
		and not _match_in_progress
	)


func start_match() -> bool:
	if not can_start_match():
		return false

	_match_in_progress = true
	Steam.setLobbyData(current_lobby_id, LOBBY_STATUS_KEY, LOBBY_STATUS_PLAYING)
	Steam.setLobbyJoinable(current_lobby_id, false)
	# The reliable roster is sent before start, so every participant knows which
	# two peers may play even if a spectator was the last person to join.
	_publish_participants()
	for peer_id in get_connected_participant_peer_ids():
		_rpc_start_match.rpc_id(peer_id)
	_rpc_start_match()
	return true


func get_lobby_member_names() -> Array[String]:
	var names: Array[String] = []
	if current_lobby_id <= 0:
		return names
	for role in [ROLE_PLAYER, ROLE_SPECTATOR]:
		var role_ids := _get_peer_ids_for_role(role)
		var slot_limit := MAX_PLAYERS if role == ROLE_PLAYER else MAX_SPECTATORS
		var role_label := Localization.localized_arg("Spieler" if role == ROLE_PLAYER else "Zuschauer")
		for slot in range(slot_limit):
			var member_name := Localization.text("Frei")
			if slot < role_ids.size():
				var peer_id := role_ids[slot]
				member_name = str((_participants[peer_id] as Dictionary).get("name", Localization.text("Steam-Spieler")))
				if peer_id == 1:
					member_name += Localization.text(" (Host)")
				elif peer_id == multiplayer.get_unique_id():
					member_name += Localization.text(" (Du)")
			names.append(Localization.format_text("%s %d: %s", [role_label, slot + 1, member_name]))
	return names


func _can_enter_lobby() -> bool:
	if not _require_steam():
		return false
	if current_lobby_id > 0 or is_lobby_operation_pending():
		_report("Es ist bereits eine Lobby aktiv.")
		return false
	return true


func _require_steam() -> bool:
	if steam_ready:
		return true
	steam_status_changed.emit(false, "Steam ist nicht verfügbar. Starte den Steam-Client und melde dich an.")
	return false


func _report(message: String, arguments: Array = []) -> void:
	DIAGNOSTICS.record("online.status", {"message": message, "steam_ready": steam_ready, "generation": _session_generation})
	steam_status_changed.emit(steam_ready, Localization.format_text(message, arguments) if not arguments.is_empty() else message)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	DIAGNOSTICS.record("steam.lobby.created", {"result": result, "generation": _session_generation, "cancelled": _cancelled_create_pending})
	if _cancelled_create_pending:
		_cancelled_create_pending = false
		_discard_abandoned_lobby(lobby_id)
		lobby_state_changed.emit()
		_join_pending_invite_if_any()
		return
	if _is_shutting_down or _is_leaving or _joining_lobby_id != -1:
		_discard_abandoned_lobby(lobby_id)
		return
	if result != Steam.RESULT_OK or lobby_id <= 0:
		_joining_lobby_id = 0
		_report("Steam konnte die Lobby nicht erstellen (Fehler %d).", [result])
		return

	current_lobby_id = lobby_id
	is_host = true
	_host_steam_id = Steam.getSteamID()
	_joining_lobby_id = 0
	_configure_host_lobby()
	if not _start_host_peer():
		leave_lobby("Steam-P2P-Host konnte nicht gestartet werden.")
		return
	_register_host_participant()
	lobby_state_changed.emit()
	connection_state_changed.emit()


func _configure_host_lobby() -> void:
	var persona_name := Steam.getPersonaName().strip_edges()
	if persona_name.is_empty():
		persona_name = "Steam-Spieler"
	Steam.setLobbyData(current_lobby_id, LOBBY_GAME_KEY, LOBBY_GAME_VALUE)
	Steam.setLobbyData(current_lobby_id, LOBBY_PROTOCOL_KEY, str(PROTOCOL_VERSION))
	Steam.setLobbyData(current_lobby_id, LOBBY_STATUS_KEY, LOBBY_STATUS_WAITING)
	Steam.setLobbyData(current_lobby_id, "name", "%ss Darkest-Cards-Lobby" % persona_name)
	Steam.setLobbyData(current_lobby_id, "owner_name", persona_name)
	Steam.setLobbyData(current_lobby_id, "host_id", str(Steam.getSteamID()))
	Steam.setLobbyData(current_lobby_id, "players", "1")
	Steam.setLobbyData(current_lobby_id, "spectators", "0")
	Steam.setLobbyJoinable(current_lobby_id, true)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	DIAGNOSTICS.record("steam.lobby.joined", {"response": response, "generation": _session_generation, "cancelled": _cancelled_create_pending or (_cancelled_join_lobby_id > 0 and _cancelled_join_lobby_id == lobby_id)})
	# Steam enter callbacks identify the lobby, but not the request. Keep all
	# admission blocked until a canceled join settles, so an old failure cannot
	# cancel a later retry of that same lobby. A queued invite resumes afterward.
	if _cancelled_join_lobby_id > 0 and lobby_id == _cancelled_join_lobby_id:
		_cancelled_join_lobby_id = 0
		if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
			_discard_abandoned_lobby(lobby_id)
		lobby_state_changed.emit()
		_join_pending_invite_if_any()
		return
	if _cancelled_create_pending:
		_discard_abandoned_lobby(lobby_id)
		return
	# Creating a lobby also produces an enter notification. Its create callback
	# owns configuration and peer startup, regardless of callback delivery order.
	if _joining_lobby_id == -1 and not _is_leaving and not _is_shutting_down:
		return
	# Steam may deliver a successful enter after the user has already left.
	# Such a callback must never create a fresh native peer during exit cleanup.
	if (
		_is_shutting_down or _is_leaving
		or (lobby_id != _joining_lobby_id and lobby_id != current_lobby_id)
	):
		_discard_abandoned_lobby(lobby_id)
		return
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_joining_lobby_id = 0
		_report("Lobby-Beitritt fehlgeschlagen (Antwort %d).", [response])
		return
	if not _lobby_is_compatible(lobby_id):
		_joining_lobby_id = 0
		current_lobby_id = lobby_id
		leave_lobby("Diese Steam-Einladung gehört nicht zu einer kompatiblen Darkest-Cards-Lobby.")
		return

	current_lobby_id = lobby_id
	_joining_lobby_id = 0
	var owner_id := Steam.getLobbyOwner(lobby_id)
	_host_steam_id = owner_id
	is_host = owner_id == Steam.getSteamID()

	var peer_started := true
	if _steam_peer == null:
		peer_started = _start_host_peer() if is_host else _start_client_peer(owner_id)
	if not peer_started:
		leave_lobby("Steam-P2P-Verbindung konnte nicht gestartet werden.")
		return
	if is_host and not _participants.has(1):
		_register_host_participant()

	lobby_state_changed.emit()
	connection_state_changed.emit()


func _discard_abandoned_lobby(lobby_id: int) -> void:
	if lobby_id <= 0 or lobby_id == current_lobby_id or _abandoned_lobbies.has(lobby_id):
		return
	_abandoned_lobbies[lobby_id] = true
	trace_session_event("ignored callback for a retired lobby")
	# LeaveLobby can post more Steam callbacks; keep it outside this callback.
	_leave_abandoned_lobby.call_deferred(lobby_id)


func _leave_abandoned_lobby(lobby_id: int) -> void:
	if steam_ready and not _is_shutting_down and lobby_id != current_lobby_id:
		Steam.leaveLobby(lobby_id)
	_abandoned_lobbies.erase(lobby_id)


func _lobby_is_compatible(lobby_id: int) -> bool:
	if lobby_id <= 0:
		return false
	return (
		Steam.getLobbyData(lobby_id, LOBBY_GAME_KEY) == LOBBY_GAME_VALUE
		and Steam.getLobbyData(lobby_id, LOBBY_PROTOCOL_KEY) == str(PROTOCOL_VERSION)
		and Steam.getLobbyData(lobby_id, LOBBY_STATUS_KEY) == LOBBY_STATUS_WAITING
		and Steam.getLobbyMemberLimit(lobby_id) == MAX_LOBBY_MEMBERS
	)


func _on_lobby_match_list(lobbies: Array) -> void:
	lobby_entries.clear()
	for lobby_value: Variant in lobbies:
		var lobby_id := int(lobby_value)
		if not _lobby_is_compatible(lobby_id):
			continue

		var max_members := Steam.getLobbyMemberLimit(lobby_id)
		if max_members <= 0:
			max_members = MAX_LOBBY_MEMBERS
		var owner_name := Steam.getLobbyData(lobby_id, "owner_name").strip_edges()
		var owner_name_is_fallback := owner_name.is_empty()
		if owner_name.is_empty():
			owner_name = "Unbekannt"
		var lobby_name := Steam.getLobbyData(lobby_id, "name").strip_edges()
		var lobby_name_source := "%ss Darkest-Cards-Lobby" if lobby_name == "%ss Darkest-Cards-Lobby" % owner_name else ""
		if lobby_name.is_empty():
			lobby_name = "Lobby von %s" % owner_name
			lobby_name_source = "Lobby von %s"

		lobby_entries.append({
			"id": lobby_id,
			"name": lobby_name,
			"members": Steam.getNumLobbyMembers(lobby_id),
			"max_members": max_members,
			"players": clampi(int(Steam.getLobbyData(lobby_id, "players")), 1, MAX_PLAYERS),
			"spectators": clampi(int(Steam.getLobbyData(lobby_id, "spectators")), 0, MAX_SPECTATORS),
			"owner_id": int(Steam.getLobbyData(lobby_id, "host_id")),
			"owner_name": owner_name,
			"owner_name_is_fallback": owner_name_is_fallback,
			"name_source": lobby_name_source,
		})
	lobby_list_updated.emit(lobby_entries.duplicate(true))


func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if _is_leaving or _is_shutting_down or lobby_id != current_lobby_id or current_lobby_id <= 0:
		return
	# Steam migrates lobby ownership automatically. The game server does not:
	# retain the original host, including before the P2P handshake completes.
	if not is_host and _host_steam_id > 0 and changed_id == _host_steam_id and (chat_state & 30) != 0:
		leave_lobby("Der Host hat die Lobby verlassen.")
		return
	lobby_state_changed.emit()


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	if lobby_id <= 0 or _is_shutting_down:
		return
	_pending_invite_lobby_id = lobby_id
	if _is_leaving or _cancelled_create_pending or _cancelled_join_lobby_id > 0:
		return
	if current_lobby_id > 0 or _joining_lobby_id != 0:
		leave_lobby("Wechsle zur eingeladenen Lobby.")
		return
	_join_pending_invite_if_any()


func _start_host_peer() -> bool:
	if _steam_peer != null:
		return true
	var peer := SteamMultiplayerPeer.new()
	trace_session_event("native host peer create begin")
	peer.server_relay = true
	peer.no_nagle = true
	var error := peer.create_host(0)
	DIAGNOSTICS.record("steam.peer.create_host", {"error": error, "generation": _session_generation})
	if error != OK:
		_report("Steam-Hostfehler: %s", [error_string(error)])
		return false
	_steam_peer = peer
	multiplayer.multiplayer_peer = peer
	return true


func _start_client_peer(host_steam_id: int) -> bool:
	if host_steam_id <= 0:
		return false
	var peer := SteamMultiplayerPeer.new()
	trace_session_event("native client peer create begin")
	peer.server_relay = true
	peer.no_nagle = true
	var error := peer.create_client(host_steam_id, 0)
	DIAGNOSTICS.record("steam.peer.create_client", {"error": error, "generation": _session_generation})
	if error != OK:
		_report("Steam-Clientfehler: %s", [error_string(error)])
		return false
	_steam_peer = peer
	multiplayer.multiplayer_peer = peer
	return true


func _reset_multiplayer_peer() -> void:
	var peer_to_close: SteamMultiplayerPeer = _steam_peer
	_steam_peer = null
	# Detach first so MultiplayerAPI can no longer poll or dispatch through the
	# native peer while close() releases its Steam sockets and queued packets.
	if peer_to_close != null:
		trace_session_event("detaching native peer")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer_to_close != null:
		trace_session_event("closing native peer")
		_close_multiplayer_peer(peer_to_close)
		trace_session_event("releasing native peer")
		peer_to_close = null
		trace_session_event("native peer released")
	_reset_voice_rate_limit()


func _close_multiplayer_peer(peer: MultiplayerPeer) -> void:
	peer.close()


func _on_peer_connected(peer_id: int) -> void:
	if _is_leaving or _is_shutting_down or current_lobby_id <= 0 or peer_id <= 0:
		return
	if is_host and (_match_in_progress or not _is_authorized_lobby_peer(peer_id)):
		if _steam_peer != null:
			_disconnect_game_peer.call_deferred(peer_id, _session_generation)
		return

	if not _connected_peer_ids.has(peer_id):
		_connected_peer_ids.append(peer_id)
	if is_host:
		_expire_pending_participant(peer_id, current_lobby_id)
	connection_state_changed.emit()
	if not is_host and peer_id == 1:
		_submit_local_player_data()


func _on_peer_disconnected(peer_id: int) -> void:
	if _is_leaving or _is_shutting_down or current_lobby_id <= 0:
		return
	var was_fighter := get_fighter_peer_ids().has(peer_id)
	_connected_peer_ids.erase(peer_id)
	_participants.erase(peer_id)
	if is_host:
		if was_fighter:
			remote_player_data.clear()
			_reset_voice_rate_limit()
			if _match_in_progress:
				for participant_id in get_connected_participant_peer_ids():
					_rpc_session_ended.rpc_id(participant_id, "Gegenspieler hat die Verbindung getrennt.")
				leave_lobby("Gegenspieler hat die Verbindung getrennt.")
				return
		_publish_participants()
		connection_state_changed.emit()
	elif peer_id == 1:
		_handle_server_loss("Verbindung zum Host wurde getrennt.")
	lobby_state_changed.emit()


func _on_connected_to_server() -> void:
	if _is_leaving or _is_shutting_down or current_lobby_id <= 0:
		return
	if not _connected_peer_ids.has(1):
		_connected_peer_ids.append(1)
	connection_state_changed.emit()
	_submit_local_player_data()


func _on_connection_failed() -> void:
	if not _is_leaving and not _is_shutting_down and current_lobby_id > 0:
		_handle_server_loss("Verbindung zum Host fehlgeschlagen.")


func _on_server_disconnected() -> void:
	if not _is_leaving and not _is_shutting_down and current_lobby_id > 0:
		_handle_server_loss("Der Host hat das Online-Match beendet.")


func _handle_server_loss(reason: String) -> void:
	leave_lobby(reason)


func _is_authorized_lobby_peer(peer_id: int) -> bool:
	if _steam_peer == null or current_lobby_id <= 0:
		return false
	var steam_id := _steam_peer.get_steam_id_for_peer_id(peer_id)
	if steam_id <= 0 or steam_id == Steam.getSteamID():
		return false
	if _connected_peer_ids.size() >= MAX_LOBBY_MEMBERS - 1 and not _connected_peer_ids.has(peer_id):
		return false
	for index in range(Steam.getNumLobbyMembers(current_lobby_id)):
		var member_id := Steam.getLobbyMemberByIndex(current_lobby_id, index)
		if member_id == steam_id:
			return true
	return false


func _submit_local_player_data() -> void:
	if is_host or not _connected_peer_ids.has(1):
		return
	_refresh_local_player_data()
	_rpc_submit_player_data.rpc_id(1, local_player_data)


@rpc("any_peer", "call_remote", "unreliable", 1)
func _rpc_receive_voice_packet(
	stream_id: int,
	sequence: int,
	pitch_percent: int,
	payload: PackedByteArray
) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if (
		not is_connected_game_peer(sender_id)
		or sender_id != get_connected_opponent_peer_id()
		or stream_id <= 0
		or stream_id > VOICE_MAX_STREAM_ID
		or sequence < 0
		or sequence > VOICE_MAX_SEQUENCE
		or pitch_percent < 35
		or pitch_percent > 90
		or payload.is_empty()
		or payload.size() > VOICE_MAX_PACKET_BYTES
	):
		return
	if not _accept_voice_packet_rate(sender_id, payload.size()):
		return
	voice_packet_received.emit(stream_id, sequence, pitch_percent, payload)


func _accept_voice_packet_rate(sender_id: int, byte_count: int) -> bool:
	var now_msec := Time.get_ticks_msec()
	if (
		_voice_rate_peer_id != sender_id
		or now_msec - _voice_rate_window_started_msec >= 1000
	):
		_voice_rate_peer_id = sender_id
		_voice_rate_window_started_msec = now_msec
		_voice_rate_packet_count = 0
		_voice_rate_byte_count = 0
	if (
		_voice_rate_packet_count >= VOICE_MAX_PACKETS_PER_SECOND
		or _voice_rate_byte_count + byte_count > VOICE_MAX_BYTES_PER_SECOND
	):
		return false
	_voice_rate_packet_count += 1
	_voice_rate_byte_count += byte_count
	return true


func _reset_voice_rate_limit() -> void:
	_voice_rate_peer_id = 0
	_voice_rate_window_started_msec = 0
	_voice_rate_packet_count = 0
	_voice_rate_byte_count = 0


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_player_data(payload: Dictionary) -> void:
	if not is_host or _steam_peer == null or _is_leaving:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _connected_peer_ids.has(sender_id):
		return
	# Duplicate handshakes cannot change seats or decks, especially after start.
	if _participants.has(sender_id):
		return
	if _match_in_progress:
		_reject_participant(sender_id, "Das Match läuft bereits. Ein Beitritt ist nur vor dem Start möglich.")
		return
	var sender_steam_id := _steam_peer.get_steam_id_for_peer_id(sender_id)
	var sanitized := _sanitize_remote_player_data(payload, sender_steam_id)
	var rejection := _register_participant(sender_id, sanitized, str(payload.get("role", "")))
	if not rejection.is_empty():
		_reject_participant(sender_id, rejection)
		return
	_publish_participants()
	connection_state_changed.emit()
	lobby_state_changed.emit()


func _register_host_participant() -> void:
	_requested_role = ROLE_PLAYER
	_refresh_local_player_data()
	var host_data := local_player_data.duplicate(true)
	host_data["role"] = ROLE_PLAYER
	_participants[1] = host_data
	_publish_participants()


func _register_participant(peer_id: int, player_data: Dictionary, requested_role: String) -> String:
	if not is_host or _match_in_progress or peer_id <= 1 or not _connected_peer_ids.has(peer_id):
		return "Dieser Lobby-Beitritt ist nicht mehr verfügbar."
	if _participants.has(peer_id):
		return "Dieser Teilnehmer hat bereits einen Platz."
	if player_data.is_empty() or not [ROLE_PLAYER, ROLE_SPECTATOR].has(requested_role):
		return "Ungültige Lobby-Daten. Bitte aktualisiere das Spiel."
	var role_limit := MAX_PLAYERS if requested_role == ROLE_PLAYER else MAX_SPECTATORS
	if _get_peer_ids_for_role(requested_role).size() >= role_limit:
		return (
			"Beide Spielerplätze sind belegt. Wähle beim Beitritt einen Zuschauerplatz."
			if requested_role == ROLE_PLAYER
			else "Beide Zuschauerplätze sind bereits belegt."
		)
	if requested_role == ROLE_PLAYER and not _player_data_has_deck(player_data):
		return "Für einen Spielerplatz brauchst du ein gültiges Kampfdeck."
	var accepted := player_data.duplicate(true)
	accepted["role"] = requested_role
	if requested_role == ROLE_SPECTATOR:
		accepted["deck"] = []
		accepted["starting_deck_indices"] = []
		accepted["starting_hand_slots"] = 0
	else:
		remote_player_data = accepted.duplicate(true)
	_participants[peer_id] = accepted
	return ""


func _publish_participants() -> void:
	if not is_host or _is_leaving:
		return
	if steam_ready and current_lobby_id > 0:
		Steam.setLobbyData(current_lobby_id, "players", str(get_fighter_peer_ids().size()))
		Steam.setLobbyData(current_lobby_id, "spectators", str(get_spectator_peer_ids().size()))
	var roster: Dictionary = {}
	for peer_id in get_participant_peer_ids():
		var participant: Dictionary = _participants[peer_id]
		roster[peer_id] = {
			"role": participant["role"],
			"name": participant.get("name", "Steam-Spieler"),
			"steam_id": participant.get("steam_id", 0),
		}
	for peer_id in get_connected_participant_peer_ids():
		_rpc_receive_roster.rpc_id(peer_id, roster)


func _reject_participant(peer_id: int, reason: String) -> void:
	_rpc_join_rejected.rpc_id(peer_id, reason)
	var lobby_id := current_lobby_id
	var generation := _session_generation
	await get_tree().create_timer(0.3).timeout
	if current_lobby_id == lobby_id and not _participants.has(peer_id):
		_disconnect_game_peer(peer_id, generation)


func _disconnect_game_peer(peer_id: int, generation: int) -> void:
	if _steam_peer == null or _is_leaving or _is_shutting_down or generation != _session_generation:
		return
	DIAGNOSTICS.record("steam.peer.disconnect", {"peer_id": peer_id, "generation": generation})
	_steam_peer.disconnect_peer(peer_id, true)


func _expire_pending_participant(peer_id: int, lobby_id: int) -> void:
	await get_tree().create_timer(12.0).timeout
	if (
		is_host and not _is_leaving and current_lobby_id == lobby_id
		and _connected_peer_ids.has(peer_id) and not _participants.has(peer_id)
	):
		_reject_participant(peer_id, "Die Anmeldung an der Lobby hat zu lange gedauert.")


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_roster(roster: Dictionary) -> void:
	if is_host or _is_leaving or multiplayer.get_remote_sender_id() != 1 or current_lobby_id <= 0:
		return
	if not roster.has(multiplayer.get_unique_id()) or roster.size() > MAX_LOBBY_MEMBERS:
		return
	_participants = roster.duplicate(true)
	remote_player_data = get_player_data_for_peer(1)
	connection_state_changed.emit()
	lobby_state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_join_rejected(reason: String) -> void:
	if not is_host and not _is_leaving and multiplayer.get_remote_sender_id() == 1:
		leave_lobby(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_session_ended(reason: String) -> void:
	if not is_host and not _is_leaving and multiplayer.get_remote_sender_id() == 1:
		leave_lobby(reason)


@rpc("authority", "call_local", "reliable")
func _rpc_start_match() -> void:
	# The Steam peer intentionally survives leave_lobby() for one frame so
	# native callbacks can unwind safely. Reject a start packet that was already
	# queued for the session being torn down instead of reviving that match.
	if (
		_is_leaving
		or _is_shutting_down
		or not steam_ready
		or current_lobby_id <= 0
		or _steam_peer == null
		or not _participants.has(multiplayer.get_unique_id())
		or get_fighter_peer_ids().size() != MAX_PLAYERS
	):
		return
	if not is_host:
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id != 1 or not _connected_peer_ids.has(sender_id):
			return
	_match_in_progress = true
	match_started.emit()
	lobby_state_changed.emit()


func _refresh_local_player_data() -> void:
	var deck := DeckManager.get_deck_card_data()

	var persona_name := "Spieler"
	var steam_id := 0
	if steam_ready:
		persona_name = Steam.getPersonaName()
		steam_id = Steam.getSteamID()
	local_player_data = {
		"version": PROTOCOL_VERSION,
		"role": _requested_role,
		"steam_id": steam_id,
		"name": persona_name.substr(0, 48),
		"deck": deck,
		"starting_deck_indices": DeckManager.get_starting_deck_indices(),
		"starting_hand_slots": CollectionManager.get_starting_hand_slot_count(),
	}


func _sanitize_remote_player_data(payload: Dictionary, actual_steam_id: int) -> Dictionary:
	if int(payload.get("version", -1)) != PROTOCOL_VERSION:
		return {}
	var preferences := _sanitize_remote_deck_payload(payload)
	var actual_name := Steam.getFriendPersonaName(actual_steam_id).strip_edges()
	if actual_name.is_empty():
		actual_name = str(payload.get("name", "Steam-Spieler")).strip_edges().substr(0, 48)
	preferences.merge({
		"version": PROTOCOL_VERSION,
		"steam_id": actual_steam_id,
		"name": actual_name,
	})
	return preferences


func _sanitize_remote_deck_payload(payload: Dictionary) -> Dictionary:
	var result_deck: Array[Dictionary] = []
	var old_to_new := {}
	var seen_instances := {}
	var raw_deck: Variant = payload.get("deck", [])
	if raw_deck is Array:
		for index in range(mini(raw_deck.size(), MAX_DECK_SIZE)):
			var raw_card: Variant = raw_deck[index]
			if not (raw_card is Dictionary):
				continue
			var sanitized_card := _sanitize_remote_card(raw_card as Dictionary)
			if sanitized_card.is_empty():
				continue
			var instance_id := str(sanitized_card.get("instance_id", ""))
			if not instance_id.is_empty():
				if seen_instances.has(instance_id):
					continue
				seen_instances[instance_id] = true
			old_to_new[index] = result_deck.size()
			result_deck.append(sanitized_card)
	var raw_slots: Variant = payload.get("starting_hand_slots", 0)
	var slot_count := clampi(raw_slots, 0, 5) if raw_slots is int else 0
	var remapped: Array[int] = []
	var raw_starting: Variant = payload.get("starting_deck_indices", [])
	if raw_starting is Array or raw_starting is PackedInt32Array or raw_starting is PackedInt64Array:
		for index: Variant in raw_starting:
			remapped.append(int(old_to_new[index]) if index is int and old_to_new.has(index) else -1)
	return {
		"deck": result_deck,
		"starting_deck_indices": DeckManager.sanitize_starting_indices(remapped, result_deck.size(), slot_count),
		"starting_hand_slots": slot_count,
	}


func _sanitize_remote_card(raw_card: Dictionary) -> Dictionary:
	var card_id := str(raw_card.get("card_id", raw_card.get("id", ""))).strip_edges()
	var base_card: Dictionary = CardDatabase.get_card(card_id)
	if base_card.is_empty() or not CardData.is_combat_card(base_card):
		return {}

	var result := base_card.duplicate(true)
	result["card_id"] = card_id
	var instance_id: Variant = raw_card.get("instance_id", "")
	if instance_id is String:
		result["instance_id"] = (instance_id as String).strip_edges().substr(0, 128)
	var is_holo: Variant = raw_card.get("is_holo", false)
	result["is_holo"] = is_holo is bool and is_holo
	var base_attack := int(base_card.get("attack", 0))
	var base_defense := int(base_card.get("defense", 0))
	result["attack"] = clampi(int(raw_card.get("attack", base_attack)), 0, base_attack + MAX_STAT_BONUS)
	result["defense"] = clampi(int(raw_card.get("defense", base_defense)), 1, base_defense + MAX_STAT_BONUS)

	var sanitized_effects: Array[Dictionary] = []
	var innate_lava: Dictionary = CardData.get_effect(base_card, "lava") if card_id == "piss" else {}
	var has_lava := false
	var raw_effects: Variant = raw_card.get("active_effects", raw_card.get("effects", []))
	if raw_effects is Array:
		for raw_effect: Variant in CardData._normalize_effects(raw_effects):
			if sanitized_effects.size() >= CardData.MAX_EFFECTS_PER_CARD:
				break
			if raw_effect is Dictionary:
				var effect := _sanitize_remote_effect(raw_effect as Dictionary)
				if effect.is_empty():
					continue
				if CardData.is_innate_only_effect(str(effect.get("type", ""))):
					# Keep at most the canonical innate Lava, only when the peer
					# actually includes it: the machine may have removed it.
					if innate_lava.is_empty() or has_lava:
						continue
					effect = innate_lava.duplicate(true)
					has_lava = true
				sanitized_effects.append(effect)
	result["effects"] = sanitized_effects
	result["active_effects"] = sanitized_effects.duplicate(true)
	return result


func _sanitize_remote_effect(raw_effect: Dictionary) -> Dictionary:
	raw_effect = CardData.normalize_effect(raw_effect)
	var effect_type := str(raw_effect.get("type", "")).strip_edges()
	if effect_type.is_empty() or EffectDatabase.get_effect(effect_type).is_empty():
		return {}

	# Copy only gameplay fields with strict bounds. Arbitrary nested keys from a
	# remote dictionary must never become part of the authoritative card state.
	var result := {"type": effect_type}
	if raw_effect.has("percent"):
		result["percent"] = clampf(float(raw_effect["percent"]), 0.0, 1.0)
	if raw_effect.has("value"):
		result["value"] = clampf(float(raw_effect["value"]), 0.0, 100.0)
	if raw_effect.has("damage"):
		result["damage"] = clampi(int(raw_effect["damage"]), 0, 50)
	if raw_effect.has("turns"):
		result["turns"] = clampi(int(raw_effect["turns"]), 0, 20)
	if raw_effect.has("min"):
		result["min"] = clampf(float(raw_effect["min"]), 0.0, 5.0)
	if raw_effect.has("max"):
		result["max"] = clampf(float(raw_effect["max"]), float(result.get("min", 0.0)), 5.0)
	if raw_effect.has("threshold"):
		result["threshold"] = clampf(float(raw_effect["threshold"]), 0.0, 1.0)
	if raw_effect.has("hits"):
		result["hits"] = clampi(int(raw_effect["hits"]), 1, 8)
	if raw_effect.has("amount"):
		result["amount"] = clampi(int(raw_effect["amount"]), 0, 10)
	if raw_effect.has("side_damage"):
		result["side_damage"] = clampf(float(raw_effect["side_damage"]), 0.0, 1.0)
	if raw_effect.has("chance"):
		result["chance"] = clampf(float(raw_effect["chance"]), 0.0, 1.0)
	return result


func _player_data_has_deck(player_data: Dictionary) -> bool:
	var deck: Variant = player_data.get("deck", [])
	return deck is Array and not (deck as Array).is_empty()


func _local_deck_is_empty() -> bool:
	return not _player_data_has_deck(local_player_data)
