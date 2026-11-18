extends "res://tests/event_cards_network_test.gd"


func _check_event_rpcs() -> void:
	guest_id = guest_api.get_unique_id()
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, guest_id])
	NetworkManager._participants = {1:{"role":"player", "name":"Host"}, guest_id:{"role":"player", "name":"Guest"}}
	host._clear_match()
	guest._clear_match()
	host._reset_online_sync_tracking()
	guest._reset_online_sync_tracking()
	host._online_mode = true
	host._online_is_host = true
	host._online_is_spectator = false
	host._table_state = GameTable.TableState.PLAYING
	host._game_over = false
	host._current_turn = "player"
	host._online_turn_sequence = 11
	guest._online_mode = true
	guest._online_is_host = false
	guest._online_is_spectator = false
	host._player_deck.assign([_combat_card("host-face")])
	host._enemy_deck.assign([_combat_card("guest-face")])
	host._draw_to_slot("player", 0, false)
	host._draw_to_slot("enemy", 0, false)
	host._initialize_event_deck()
	var target := host._enemy_slots[0]
	target.apply_eternal_suffering()
	target.advance_eternal_suffering()
	target.advance_eternal_suffering()
	host._broadcast_online_snapshot(0)
	var arrived := await _wait_until(func(): return is_instance_valid(guest._player_slots[0]) and guest._player_slots[0].eternal_suffering_damage == 5)
	check(arrived and guest._player_slots[0].get_node("CombatIndicators/EternalSuffering").visible, "ENet carries suffering and the red status to the affected fighter")
	target.cleanse_eternal_suffering_from_neighbor()
	host._broadcast_online_snapshot(0)
	var cured := await _wait_until(func(): return guest._player_slots[0].eternal_suffering_damage == 0)
	# Main can open its startup pause overlay in this transport fixture.
	# Resume gameplay before measuring the pause-bound indicator animation.
	get_tree().paused = false
	await get_tree().create_timer(0.3).timeout
	check(cured and not guest._player_slots[0].get_node("CombatIndicators/EternalSuffering").visible, "ENet removes the damage state and the red status after a neighbor cure")
	var data := target.card_data.duplicate(true)
	data["effects"] = [{"type":"draw_on_death"}]
	data["active_effects"] = data["effects"].duplicate(true)
	target.setup(data)
	# Actual death effects cross the same authority/private-state boundary.
	target.apply_eternal_suffering()
	target.advance_eternal_suffering()
	target.advance_eternal_suffering()
	host._enemy_deck.append(_combat_card("guest-neighbor"))
	host._draw_to_slot("enemy", 1, false)
	target.take_damage(target.current_hp)
	host._award_event_for_death(target)
	host._award_event_for_death(target)
	host._broadcast_online_snapshot(0)
	var drawn := await _wait_until(func(): return guest._player_event_hand.size() == 1)
	check(drawn and host._enemy_event_hand.size() == 1 and host._player_event_hand.is_empty(), "ENet gives the deceased card owner's private hand exactly one event")
	var poisoned := await _wait_until(func(): return is_instance_valid(guest._player_slots[1]) and int(guest._player_slots[1].get_meta("poison_damage", 0)) == 5)
	check(poisoned and int(guest._player_slots[1].get_meta("poison_turns", 0)) == 3 and guest._player_slots[1].eternal_suffering_damage == 0, "ENet replicates the one-time neighbor poison with the deceased card's suffering damage")
	host._clear_match()
	guest._clear_match()
