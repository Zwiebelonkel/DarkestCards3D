extends "res://scripts/autoload/NetworkManager.gd"

# Transport-free fixture. Production role/admission policies have their own tests.
func _ready() -> void:
	pass

func _exit_tree() -> void:
	pass

func is_connected_game_peer(peer_id: int) -> bool:
	return _match_in_progress and current_lobby_id > 0 and _participants.has(peer_id)

