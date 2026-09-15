extends "res://scripts/autoload/NetworkManager.gd"

# Exercise the real leave_lobby coroutine and notifications without a Steam
# account or native sockets. Only the callback pump and socket operation vary.
var peer_reset_count := 0
var peer_reset_during_callback := false
var callback_running := false
var peer_start_count := 0


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	pass


func _reset_multiplayer_peer() -> void:
	peer_reset_count += 1
	peer_reset_during_callback = callback_running


func _configure_host_lobby() -> void:
	pass


func _lobby_is_compatible(_lobby_id: int) -> bool:
	return true


func _start_host_peer() -> bool:
	peer_start_count += 1
	return true


func _start_client_peer(_host_steam_id: int) -> bool:
	peer_start_count += 1
	return true


func receive_disconnect_callback() -> void:
	callback_running = true
	_on_server_disconnected()
	_on_peer_disconnected(1)
	leave_lobby("Repeated close")
	callback_running = false
