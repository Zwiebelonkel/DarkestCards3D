extends Node

signal steam_status_changed(ready: bool, message: String)
signal lobby_list_updated(lobbies: Array)
signal lobby_state_changed
signal connection_state_changed
signal match_started
signal session_closed(reason: String)

const APP_ID := 480
const PROTOCOL_VERSION := 1
const MAX_PLAYERS := 2
const MAX_DECK_SIZE := 20
const MAX_STAT_BONUS := 100

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
var _match_in_progress := false
var _is_leaving := false
var _is_shutting_down := false
var _joining_lobby_id := 0
var _pending_invite_lobby_id := 0
var _invite_dialog_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_launch_invite()
	_connect_steam_signals()
	_connect_multiplayer_signals()
	_initialize_steam()


func _process(_delta: float) -> void:
	# GodotSteam 4.22 cannot embed callbacks together with engine-startup
	# initialization, so one always-running autoload pumps them explicitly.
	if steam_ready and not _is_shutting_down:
		Steam.run_callbacks()


func _exit_tree() -> void:
	_is_shutting_down = true
	_is_leaving = true
	if current_lobby_id > 0 and steam_ready:
		Steam.leaveLobby(current_lobby_id)
	_reset_multiplayer_peer()
	if steam_ready:
		Steam.steamShutdown()
	steam_ready = false


func _connect_steam_signals() -> void:
	_connect_steam_signal(Steam.lobby_created, _on_lobby_created)
	_connect_steam_signal(Steam.lobby_joined, _on_lobby_joined)
	_connect_steam_signal(Steam.lobby_match_list, _on_lobby_match_list)
	_connect_steam_signal(Steam.lobby_chat_update, _on_lobby_chat_update)
	_connect_steam_signal(Steam.join_requested, _on_join_requested)


func _connect_steam_signal(steam_signal: Signal, callback: Callable) -> void:
	if not steam_signal.is_connected(callback):
		steam_signal.connect(callback)


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
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _initialize_steam(force_manual := false) -> void:
	if _is_shutting_down:
		return
	if not Engine.has_singleton("Steam"):
		steam_ready = false
		steam_status_changed.emit(false, "GodotSteam wurde nicht geladen.")
		return

	var result: Dictionary = {}
	if not force_manual:
		# GodotSteam initializes at engine startup through project.godot. This is
		# early enough for the Steam overlay to hook the graphics device.
		result = Steam.get_steam_init_result()
	if result.is_empty():
		# Fallback for development setups without automatic initialization, and
		# for the explicit SDK restart used after closing a 4.22 peer session.
		if force_manual:
			var initialized := Steam.steamInit(APP_ID, false)
			result = {
				"status": Steam.STEAM_API_INIT_RESULT_OK if initialized else -1,
				"verbal": "" if initialized else "Steam API konnte nach dem Netzwerk-Reset nicht neu gestartet werden.",
			}
		else:
			result = Steam.steamInitEx(APP_ID, false)
	_apply_steam_init_result(result)


func _apply_steam_init_result(result: Dictionary) -> void:
	var status := int(result.get("status", -1))
	if status != Steam.STEAM_API_INIT_RESULT_OK:
		steam_ready = false
		var detail := str(result.get("verbal", "Unbekannter Steam-Fehler")).strip_edges()
		steam_status_changed.emit(false, "Steam konnte nicht gestartet werden: %s" % detail)
		return

	steam_ready = true
	Steam.initRelayNetworkAccess()
	_refresh_local_player_data()
	steam_status_changed.emit(true, "Steam verbunden als %s." % Steam.getPersonaName())
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
	_refresh_local_player_data()
	if _local_deck_is_empty():
		_report("Dein Kampfdeck ist leer. Baue zuerst ein Deck.")
		return false

	# A negative value marks the asynchronous create request as pending. This
	# prevents double-clicks from creating multiple Steam lobbies.
	_joining_lobby_id = -1
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)
	return true


func join_lobby(lobby_id: int) -> bool:
	if not _can_enter_lobby() or lobby_id <= 0:
		return false
	_refresh_local_player_data()
	if _local_deck_is_empty():
		_report("Dein Kampfdeck ist leer. Baue zuerst ein Deck.")
		return false

	_joining_lobby_id = lobby_id
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
	if _is_leaving:
		return
	_is_leaving = true

	var old_lobby_id := current_lobby_id
	var had_peer := _steam_peer != null
	_reset_multiplayer_peer()
	if old_lobby_id > 0 and steam_ready:
		Steam.leaveLobby(old_lobby_id)

	current_lobby_id = 0
	is_host = false
	remote_player_data.clear()
	_connected_peer_ids.clear()
	_match_in_progress = false
	_joining_lobby_id = 0
	_invite_dialog_pending = false
	lobby_state_changed.emit()
	connection_state_changed.emit()
	session_closed.emit(reason)
	_is_leaving = false

	# GodotSteam 4.22 currently fails to release SteamMultiplayerPeer sockets in
	# _close(). Restarting the SDK releases the native handles so a second
	# host/join attempt remains possible in the same process.
	if had_peer and steam_ready and not _is_shutting_down:
		_restart_steam_after_peer_cleanup()


func has_active_session() -> bool:
	return current_lobby_id > 0


func has_connected_opponent() -> bool:
	return not _connected_peer_ids.is_empty()


func is_connected_game_peer(peer_id: int) -> bool:
	return (
		peer_id > 0
		and _steam_peer != null
		and current_lobby_id > 0
		and _match_in_progress
		and _connected_peer_ids.has(peer_id)
	)


func is_lobby_operation_pending() -> bool:
	return _joining_lobby_id != 0


func is_match_in_progress() -> bool:
	return _match_in_progress


func can_start_match() -> bool:
	return (
		steam_ready
		and is_host
		and current_lobby_id > 0
		and has_connected_opponent()
		and not _local_deck_is_empty()
		and _player_data_has_deck(remote_player_data)
		and not _match_in_progress
	)


func start_match() -> bool:
	if not can_start_match():
		return false

	_match_in_progress = true
	Steam.setLobbyData(current_lobby_id, LOBBY_STATUS_KEY, LOBBY_STATUS_PLAYING)
	Steam.setLobbyJoinable(current_lobby_id, false)
	_rpc_start_match.rpc()
	return true


func get_lobby_member_names() -> Array[String]:
	var names: Array[String] = []
	if not steam_ready or current_lobby_id <= 0:
		return names

	var owner_id := Steam.getLobbyOwner(current_lobby_id)
	var local_id := Steam.getSteamID()
	for index in range(Steam.getNumLobbyMembers(current_lobby_id)):
		var member_id := Steam.getLobbyMemberByIndex(current_lobby_id, index)
		var member_name := Steam.getPersonaName() if member_id == local_id else Steam.getFriendPersonaName(member_id)
		if member_name.strip_edges().is_empty():
			member_name = "Steam-Spieler %s" % str(member_id)
		if member_id == owner_id:
			member_name += " (Host)"
		names.append(member_name)
	return names


func _can_enter_lobby() -> bool:
	if not _require_steam():
		return false
	if current_lobby_id > 0 or _joining_lobby_id != 0:
		_report("Es ist bereits eine Lobby aktiv.")
		return false
	return true


func _require_steam() -> bool:
	if steam_ready:
		return true
	steam_status_changed.emit(false, "Steam ist nicht verfügbar. Starte den Steam-Client und melde dich an.")
	return false


func _report(message: String) -> void:
	steam_status_changed.emit(steam_ready, message)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.RESULT_OK or lobby_id <= 0:
		_joining_lobby_id = 0
		_report("Steam konnte die Lobby nicht erstellen (Fehler %d)." % result)
		return

	current_lobby_id = lobby_id
	is_host = true
	_joining_lobby_id = 0
	_configure_host_lobby()
	if not _start_host_peer():
		leave_lobby("Steam-P2P-Host konnte nicht gestartet werden.")
		return
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
	Steam.setLobbyJoinable(current_lobby_id, true)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_joining_lobby_id = 0
		_report("Lobby-Beitritt fehlgeschlagen (Antwort %d)." % response)
		return
	if not _lobby_is_compatible(lobby_id):
		_joining_lobby_id = 0
		current_lobby_id = lobby_id
		leave_lobby("Diese Steam-Einladung gehört nicht zu einer kompatiblen Darkest-Cards-Lobby.")
		return

	current_lobby_id = lobby_id
	_joining_lobby_id = 0
	var owner_id := Steam.getLobbyOwner(lobby_id)
	is_host = owner_id == Steam.getSteamID()

	var peer_started := true
	if _steam_peer == null:
		peer_started = _start_host_peer() if is_host else _start_client_peer(owner_id)
	if not peer_started:
		leave_lobby("Steam-P2P-Verbindung konnte nicht gestartet werden.")
		return

	lobby_state_changed.emit()
	connection_state_changed.emit()


func _lobby_is_compatible(lobby_id: int) -> bool:
	if lobby_id <= 0:
		return false
	return (
		Steam.getLobbyData(lobby_id, LOBBY_GAME_KEY) == LOBBY_GAME_VALUE
		and Steam.getLobbyData(lobby_id, LOBBY_PROTOCOL_KEY) == str(PROTOCOL_VERSION)
		and Steam.getLobbyData(lobby_id, LOBBY_STATUS_KEY) == LOBBY_STATUS_WAITING
		and Steam.getLobbyMemberLimit(lobby_id) == MAX_PLAYERS
	)


func _on_lobby_match_list(lobbies: Array) -> void:
	lobby_entries.clear()
	for lobby_value: Variant in lobbies:
		var lobby_id := int(lobby_value)
		if not _lobby_is_compatible(lobby_id):
			continue

		var max_members := Steam.getLobbyMemberLimit(lobby_id)
		if max_members <= 0:
			max_members = MAX_PLAYERS
		var owner_name := Steam.getLobbyData(lobby_id, "owner_name").strip_edges()
		if owner_name.is_empty():
			owner_name = "Unbekannt"
		var lobby_name := Steam.getLobbyData(lobby_id, "name").strip_edges()
		if lobby_name.is_empty():
			lobby_name = "Lobby von %s" % owner_name

		lobby_entries.append({
			"id": lobby_id,
			"name": lobby_name,
			"members": Steam.getNumLobbyMembers(lobby_id),
			"max_members": max_members,
			"owner_id": int(Steam.getLobbyData(lobby_id, "host_id")),
			"owner_name": owner_name,
		})
	lobby_list_updated.emit(lobby_entries.duplicate(true))


func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if lobby_id == current_lobby_id:
		lobby_state_changed.emit()


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	if lobby_id <= 0:
		return
	if current_lobby_id > 0:
		_pending_invite_lobby_id = lobby_id
		leave_lobby("Wechsle zur eingeladenen Lobby.")
		return
	join_lobby.call_deferred(lobby_id)


func _start_host_peer() -> bool:
	if _steam_peer != null:
		return true
	var peer := SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.no_nagle = true
	var error := peer.create_host(0)
	if error != OK:
		_report("Steam-Hostfehler: %s" % error_string(error))
		return false
	_steam_peer = peer
	multiplayer.multiplayer_peer = peer
	return true


func _start_client_peer(host_steam_id: int) -> bool:
	if host_steam_id <= 0:
		return false
	var peer := SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.no_nagle = true
	var error := peer.create_client(host_steam_id, 0)
	if error != OK:
		_report("Steam-Clientfehler: %s" % error_string(error))
		return false
	_steam_peer = peer
	multiplayer.multiplayer_peer = peer
	return true


func _reset_multiplayer_peer() -> void:
	if _steam_peer != null:
		_steam_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_steam_peer = null


func _restart_steam_after_peer_cleanup() -> void:
	Steam.steamShutdown()
	steam_ready = false
	steam_status_changed.emit(false, "Steam-Netzwerk wird zurückgesetzt …")
	_reinitialize_steam_deferred()


func _reinitialize_steam_deferred() -> void:
	await get_tree().process_frame
	if not _is_shutting_down:
		_initialize_steam(true)


func _on_peer_connected(peer_id: int) -> void:
	if _is_leaving or peer_id <= 0:
		return
	if is_host and not _is_authorized_lobby_peer(peer_id):
		if _steam_peer != null:
			_steam_peer.disconnect_peer(peer_id, true)
		return

	if not _connected_peer_ids.has(peer_id):
		_connected_peer_ids.append(peer_id)
	connection_state_changed.emit()
	if not is_host and peer_id == 1:
		_submit_local_player_data()


func _on_peer_disconnected(peer_id: int) -> void:
	if _is_leaving:
		return
	_connected_peer_ids.erase(peer_id)
	if is_host:
		remote_player_data.clear()
		connection_state_changed.emit()
		if _match_in_progress:
			session_closed.emit("Gegenspieler hat die Verbindung getrennt.")
	elif peer_id == 1:
		_handle_server_loss("Verbindung zum Host wurde getrennt.")


func _on_connected_to_server() -> void:
	if _is_leaving:
		return
	if not _connected_peer_ids.has(1):
		_connected_peer_ids.append(1)
	connection_state_changed.emit()
	_submit_local_player_data()


func _on_connection_failed() -> void:
	if not _is_leaving:
		_handle_server_loss("Verbindung zum Host fehlgeschlagen.")


func _on_server_disconnected() -> void:
	if not _is_leaving:
		_handle_server_loss("Der Host hat das Online-Match beendet.")


func _handle_server_loss(reason: String) -> void:
	if _is_leaving:
		return
	_is_leaving = true
	var old_lobby_id := current_lobby_id
	var had_peer := _steam_peer != null
	_reset_multiplayer_peer()
	if old_lobby_id > 0 and steam_ready:
		Steam.leaveLobby(old_lobby_id)
	current_lobby_id = 0
	is_host = false
	remote_player_data.clear()
	_connected_peer_ids.clear()
	_match_in_progress = false
	_joining_lobby_id = 0
	lobby_state_changed.emit()
	connection_state_changed.emit()
	session_closed.emit(reason)
	_is_leaving = false
	if had_peer and steam_ready and not _is_shutting_down:
		_restart_steam_after_peer_cleanup()


func _is_authorized_lobby_peer(peer_id: int) -> bool:
	if _steam_peer == null or current_lobby_id <= 0:
		return false
	var steam_id := _steam_peer.get_steam_id_for_peer_id(peer_id)
	if steam_id <= 0 or steam_id == Steam.getSteamID():
		return false
	var non_owner_members := 0
	for index in range(Steam.getNumLobbyMembers(current_lobby_id)):
		var member_id := Steam.getLobbyMemberByIndex(current_lobby_id, index)
		if member_id != Steam.getSteamID():
			non_owner_members += 1
		if member_id == steam_id:
			return non_owner_members <= 1 and _connected_peer_ids.is_empty()
	return false


func _submit_local_player_data() -> void:
	if is_host or not has_connected_opponent():
		return
	_refresh_local_player_data()
	_rpc_submit_player_data.rpc_id(1, local_player_data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_player_data(payload: Dictionary) -> void:
	if not is_host or _steam_peer == null:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _connected_peer_ids.has(sender_id):
		return
	var sender_steam_id := _steam_peer.get_steam_id_for_peer_id(sender_id)
	var sanitized := _sanitize_remote_player_data(payload, sender_steam_id)
	if not _player_data_has_deck(sanitized):
		_report("Der Gegenspieler hat kein gültiges Deck übertragen.")
		return
	remote_player_data = sanitized
	connection_state_changed.emit()
	lobby_state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_start_match() -> void:
	_match_in_progress = true
	match_started.emit()
	lobby_state_changed.emit()


func _refresh_local_player_data() -> void:
	var deck: Array[Dictionary] = []
	for card_id_value: Variant in DeckManager.get_deck_cards().slice(0, MAX_DECK_SIZE):
		var card_id := str(card_id_value)
		var base_card: Dictionary = CardDatabase.get_card(card_id)
		if base_card.is_empty():
			continue
		var upgraded := CardUpgradeManager.apply_upgrades(card_id, base_card)
		deck.append(CardData.merge_card_and_instance(upgraded))

	var persona_name := "Spieler"
	var steam_id := 0
	if steam_ready:
		persona_name = Steam.getPersonaName()
		steam_id = Steam.getSteamID()
	local_player_data = {
		"version": PROTOCOL_VERSION,
		"steam_id": steam_id,
		"name": persona_name.substr(0, 48),
		"deck": deck,
	}


func _sanitize_remote_player_data(payload: Dictionary, actual_steam_id: int) -> Dictionary:
	if int(payload.get("version", -1)) != PROTOCOL_VERSION:
		return {}
	var result_deck: Array[Dictionary] = []
	var raw_deck: Variant = payload.get("deck", [])
	if raw_deck is Array:
		for raw_card: Variant in (raw_deck as Array).slice(0, MAX_DECK_SIZE):
			if not (raw_card is Dictionary):
				continue
			var sanitized_card := _sanitize_remote_card(raw_card as Dictionary)
			if not sanitized_card.is_empty():
				result_deck.append(sanitized_card)

	var actual_name := Steam.getFriendPersonaName(actual_steam_id).strip_edges()
	if actual_name.is_empty():
		actual_name = str(payload.get("name", "Steam-Spieler")).strip_edges().substr(0, 48)
	return {
		"version": PROTOCOL_VERSION,
		"steam_id": actual_steam_id,
		"name": actual_name,
		"deck": result_deck,
	}


func _sanitize_remote_card(raw_card: Dictionary) -> Dictionary:
	var card_id := str(raw_card.get("card_id", raw_card.get("id", ""))).strip_edges()
	var base_card: Dictionary = CardDatabase.get_card(card_id)
	if base_card.is_empty():
		return {}

	var result := base_card.duplicate(true)
	var base_attack := int(base_card.get("attack", 0))
	var base_defense := int(base_card.get("defense", 0))
	result["attack"] = clampi(int(raw_card.get("attack", base_attack)), 0, base_attack + MAX_STAT_BONUS)
	result["defense"] = clampi(int(raw_card.get("defense", base_defense)), 1, base_defense + MAX_STAT_BONUS)

	var sanitized_effects: Array[Dictionary] = []
	var raw_effects: Variant = raw_card.get("active_effects", raw_card.get("effects", []))
	if raw_effects is Array:
		for raw_effect: Variant in raw_effects:
			if sanitized_effects.size() >= CardData.MAX_EFFECTS_PER_CARD:
				break
			if raw_effect is Dictionary:
				var effect := _sanitize_remote_effect(raw_effect as Dictionary)
				if not effect.is_empty():
					sanitized_effects.append(effect)
	result["effects"] = sanitized_effects
	result["active_effects"] = sanitized_effects.duplicate(true)
	return result


func _sanitize_remote_effect(raw_effect: Dictionary) -> Dictionary:
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
		result["hits"] = clampi(int(raw_effect["hits"]), 1, 3)
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
