extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error(description)


func _run() -> void:
	# Load after SceneTree has registered the project's autoload names.
	var lobby = load("res://tests/fixtures/NetworkRoleFixture.gd").new()
	root.add_child(lobby)
	lobby.is_host = true
	lobby.steam_ready = true
	lobby.current_lobby_id = 123
	lobby.local_player_data = {"name": "Host", "deck": [{"id": "host_card"}]}
	lobby._participants = {1: {"role": "player", "name": "Host"}}
	lobby._connected_peer_ids.assign([2, 3, 4])
	var viewer := {"name": "Viewer", "deck": []}
	var fighter := {"name": "Fighter", "deck": [{"id": "fighter_card"}]}

	_expect(lobby._register_participant(2, viewer, "spectator").is_empty(), "First spectator can join without a deck")
	_expect(lobby._register_participant(3, viewer, "spectator").is_empty(), "Second spectator can join without a deck")
	_expect(lobby.get_connected_opponent_peer_id() == 0, "Spectators do not occupy the fighter seat or activate voice")
	_expect(not lobby.can_start_match(), "Two spectators cannot replace an opponent")
	_expect(not lobby._register_participant(4, viewer, "spectator").is_empty(), "A third spectator is rejected")
	_expect(not lobby._register_participant(4, viewer, "player").is_empty(), "An empty deck is rejected for a fighter")
	_expect(not lobby._register_participant(4, fighter, "admin").is_empty(), "Unknown roles are rejected")
	_expect(not lobby._register_participant(99, fighter, "player").is_empty(), "Unconnected senders cannot register")
	_expect(lobby._register_participant(4, fighter, "player").is_empty(), "A fighter can take the remaining player seat after two spectators join")
	_expect(lobby.get_fighter_peer_ids() == [1, 4], "Exactly the host and fighter occupy the player slots")
	_expect(lobby.get_spectator_peer_ids() == [2, 3], "Exactly two spectator slots are occupied")
	_expect(lobby.get_connected_opponent_peer_id() == 4, "Opponent lookup ignores both spectators")
	_expect(lobby.remote_player_data.get("name") == "Fighter", "Spectator payloads cannot replace the opponent deck")
	_expect(lobby.can_start_match(), "Two fighters with accepted spectators are ready to start")
	_expect(lobby.get_lobby_member_names().size() == 4, "Lobby displays all four explicitly labelled slots")
	_expect(not lobby._register_participant(2, fighter, "player").is_empty(), "Accepted spectators cannot switch roles through a duplicate handshake")
	_expect(lobby.is_spectator_peer(2), "Rejected role changes preserve the assigned spectator role")
	lobby._connected_peer_ids.append(5)
	_expect(not lobby._register_participant(5, fighter, "player").is_empty(), "A third fighter is rejected even with a valid deck")
	_expect(not lobby.can_start_match(), "Pending or rejected native connections block match start until disconnected")
	lobby._connected_peer_ids.erase(5)
	lobby._match_in_progress = true
	lobby._connected_peer_ids.append(5)
	_expect(not lobby._register_participant(5, viewer, "spectator").is_empty(), "Late joins are rejected once a match is active")
	lobby._connected_peer_ids.erase(5)
	lobby._on_peer_disconnected(2)
	_expect(lobby._match_in_progress, "A spectator leaving preserves the active match")
	_expect(lobby.closed_reason.is_empty(), "Spectator departure does not emit session teardown")
	_expect(lobby.get_connected_opponent_peer_id() == 4, "Spectator departure preserves the actual opponent")
	_expect(lobby.remote_player_data.get("name") == "Fighter", "Spectator departure preserves the opponent deck")
	_expect(lobby.get_spectator_peer_ids() == [3], "Only the departing spectator is removed")
	lobby._on_peer_disconnected(3)
	lobby._on_peer_disconnected(4)
	_expect(not lobby.closed_reason.is_empty(), "Fighter departure ends the match")
	_expect(not lobby._match_in_progress, "Fighter departure clears the active-match state")
	lobby._participants.clear()
	lobby._requested_role = "spectator"
	lobby._connected_peer_ids.assign([2, 3])
	lobby._participants = {2: {"role": "player"}, 3: {"role": "player"}}
	lobby._match_in_progress = true
	_expect(lobby.is_local_spectator(), "A requested spectator remains a spectator while host confirmation is pending")
	_expect(lobby.get_connected_opponent_peer_id() == 0, "A spectator has no voice opponent even with two fighters connected")
	_expect(not lobby.send_voice_packet(1, 0, 50, PackedByteArray([1])), "Spectators cannot send player voice packets")
	lobby.free()
	if _failures.is_empty():
		print("Network role tests passed: capacities, admission, pending readiness, opponent isolation, and departures.")
	quit(0 if _failures.is_empty() else 1)
