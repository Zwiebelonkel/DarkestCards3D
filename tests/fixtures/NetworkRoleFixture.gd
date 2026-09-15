extends "res://scripts/autoload/NetworkManager.gd"

# Only transport, Steam callbacks, and teardown are isolated. The tests use
# the production admission, readiness, role queries, and disconnect handling.
var published_rosters := 0
var closed_reason := ""


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	pass


func _publish_participants() -> void:
	published_rosters += 1


func leave_lobby(reason: String = "Lobby verlassen.") -> void:
	closed_reason = reason
	_match_in_progress = false
