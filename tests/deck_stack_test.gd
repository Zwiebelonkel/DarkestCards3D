extends Node

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table.deck_size = 100
	table._player_deck = table._network_placeholder_deck(100)
	table._enemy_deck = table._network_placeholder_deck(25)
	table._rebuild_stack_visual("player")
	table._rebuild_stack_visual("enemy")
	check(table._player_stack_visuals.size() == 100, "full 100-card deck has one visible layer per remaining card")
	check(table._enemy_stack_visuals.size() == 25, "opponent stack also extends past the former 20-card cap")
	var top := table._player_stack_visuals.back() as Card3D
	check(is_equal_approx(top.global_position.y - table.player_deck_marker.global_position.y, 99 * 0.012), "full stack height represents all 100 cards")
	check(table._get_stack_top_position("player").is_equal_approx(top.global_position), "draw origin is the actual top card")
	check(top.process_mode == Node.PROCESS_MODE_DISABLED and not top.area.input_ray_pickable and top.area.collision_layer == 0, "stack decoration has no processing or card input")
	var base_id: int = table._player_stack_visuals[0].get_instance_id()
	table._rebuild_stack_visual("player")
	check(table._player_stack_visuals[0].get_instance_id() == base_id, "unchanged snapshot reuses stack cards")

	var count_and_height_match := true
	var top_removed_immediately := true
	for remaining: int in range(99, -1, -1):
		var removed_top := table._player_stack_visuals.back() as Card3D
		table._player_deck.pop_back()
		table._pop_stack_visual("player")
		count_and_height_match = count_and_height_match and table._player_stack_visuals.size() == remaining
		top_removed_immediately = top_removed_immediately and not removed_top.visible and removed_top.is_queued_for_deletion()
		if remaining > 0:
			var expected_y: float = table.player_deck_marker.global_position.y + (remaining - 1) * 0.012
			count_and_height_match = count_and_height_match and is_equal_approx(table._player_stack_visuals.back().global_position.y, expected_y)
		if remaining == 1:
			check(table._player_stack_visuals[0].get_instance_id() == base_id, "depletion preserves the existing bottom card")
	check(count_and_height_match, "every draw lowers the stack one layer through 20, one, and zero cards")
	check(top_removed_immediately, "drawn stack cards disappear immediately before deferred cleanup")
	check(table._player_stack_visuals.is_empty(), "empty deck leaves no phantom cards")
	check(table._get_stack_top_position("player").is_equal_approx(table.player_deck_marker.global_position), "empty stack origin remains at the deck marker")
	check(table._enemy_stack_visuals.size() == 25, "drawing the player deck leaves the opponent stack unchanged")
	await get_tree().process_frame

	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, 2])
	NetworkManager._participants = {
		1: {"role": "player", "name": "Host"},
		2: {"role": "player", "name": "Gast"},
		3: {"role": "spectator", "name": "Zuschauer"},
	}
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = false
	var snapshot := {
		"current_turn": "player", "turn_sequence": 1,
		"player_slots": [], "enemy_slots": [],
		"player_deck_count": 64, "enemy_deck_count": 31,
		"game_over": false, "action_in_progress": false,
	}
	table._apply_online_state_now(snapshot)
	check(table._player_stack_visuals.size() == 31 and table._enemy_stack_visuals.size() == 64, "joined fighter receives mirrored remaining-card stack heights")
	table._online_is_spectator = true
	table._apply_online_state_now(snapshot)
	check(table._player_stack_visuals.size() == 64 and table._enemy_stack_visuals.size() == 31, "spectator preserves host-side stack heights")
	snapshot["player_deck_count"] = 0
	snapshot["enemy_deck_count"] = 1
	table._apply_online_state_now(snapshot)
	check(table._player_stack_visuals.is_empty() and table._enemy_stack_visuals.size() == 1, "online snapshots show zero and one remaining card exactly")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("DECK_STACK_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
