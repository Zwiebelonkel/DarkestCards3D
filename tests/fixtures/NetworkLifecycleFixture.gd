extends "res://scripts/autoload/NetworkManager.gd"

# Preserve production teardown and callback policy. Only calls into Steam are
# replaced; notably, _reset_multiplayer_peer itself is exercised unchanged.
var trace: Array[String] = []
var close_count := 0
var detached_at_close := false
var owner_cleared_at_close := false
var close_during_callback := false
var callback_running := false
var abandoned_lobbies: Array[int] = []
var peer_start_count := 0


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	pass


func trace_session_event(event: String) -> void:
	trace.append(event)


func _close_multiplayer_peer(_peer: MultiplayerPeer) -> void:
	close_count += 1
	detached_at_close = multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	owner_cleared_at_close = _steam_peer == null
	close_during_callback = callback_running


func _leave_abandoned_lobby(lobby_id: int) -> void:
	abandoned_lobbies.append(lobby_id)


func _configure_host_lobby() -> void:
	pass


func _lobby_is_compatible(_lobby_id: int) -> bool:
	return true


func _require_steam() -> bool:
	return true


func _start_host_peer() -> bool:
	peer_start_count += 1
	return true


func _start_client_peer(_host_steam_id: int) -> bool:
	peer_start_count += 1
	return true


func _register_host_participant() -> void:
	_participants[1] = {"role": ROLE_PLAYER}


func _publish_participants() -> void:
	pass


func receive_disconnect_callback() -> void:
	callback_running = true
	_on_server_disconnected()
	_on_peer_disconnected(1)
	leave_lobby("Repeated callback close")
	callback_running = false
