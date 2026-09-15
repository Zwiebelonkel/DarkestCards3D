extends Node3D

class ObservedTable extends "res://scenes/table/GameTable.gd":
	var observations: Array[Dictionary] = []
	var healing_observations: Array[Dictionary] = []

	func _spawn_damage_number(card: Card3D, amount: int) -> void:
		var identity := str(card.card_data.get("instance_id", "")) if is_instance_valid(card) else ""
		var before := _damage_numbers.size()
		super._spawn_damage_number(card, amount)
		observations.append({
			"identity": identity, "amount": amount,
			"spawned": _damage_numbers.size() > before,
			"frame": Engine.get_process_frames(),
		})

	func _spawn_healing_number(card: Card3D, amount: int) -> void:
		var identity := str(card.card_data.get("instance_id", "")) if is_instance_valid(card) else ""
		var before := _damage_numbers.size()
		super._spawn_healing_number(card, amount)
		healing_observations.append({
			"identity": identity, "amount": amount,
			"spawned": _damage_numbers.size() > before,
		})

var checks := 0
var failures := 0
var _identity := 0
var table: ObservedTable


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use tests/run_match_feature_tests.ps1 to isolate player saves.")
		get_tree().quit(1)
		return
	SettingsManager.set_damage_numbers_enabled(true)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	var table_node := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate()
	# Replacing the script with the observing subclass resets exported values.
	# Preserve the real scene's card scene, resources and tuning before doing so.
	var scene_properties := {}
	for property: Dictionary in table_node.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property["usage"]) & PROPERTY_USAGE_STORAGE:
			scene_properties[str(property["name"])] = table_node.get(property["name"])
	table_node.set_script(ObservedTable)
	for property_name: String in scene_properties:
		table_node.set(property_name, scene_properties[property_name])
	table = table_node as ObservedTable
	table.table_camera = camera
	add_child(table)
	table.set_process(false)
	table.enemy_turn_delay = 60.0
	table.draw_animation_duration = 0.01
	table.replacement_draw_delay = 0.01
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	await get_tree().process_frame
	await _check_local_duels()
	await _check_other_damage()
	await _check_local_healing()
	for spectator: bool in [false, true]:
		await _check_remote_impacts(spectator)
		await _check_generic_events(spectator)
		await _check_remote_healing(spectator)
	await _check_clear_lifecycle()
	await _check_setting_behavior()
	_reset()
	table.queue_free()
	camera.queue_free()
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	NetworkManager._connected_peer_ids.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	print("DAMAGE_NUMBERS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _reset() -> void:
	table._online_mode = false
	table._clear_match()
	table._reset_online_sync_tracking()
	table._online_is_host = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING
	table.observations.clear()
	table.healing_observations.clear()
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	NetworkManager._connected_peer_ids.clear()


func _data(attack: int, health: int, effects: Array = []) -> Dictionary:
	_identity += 1
	var data := CardDatabase.get_card("corpse").duplicate(true)
	data["instance_id"] = "damage-number-%d" % _identity
	data["attack"] = attack
	data["defense"] = health
	data["animated"] = false
	data["effects"] = effects.duplicate(true)
	data["active_effects"] = effects.duplicate(true)
	return data


func _spawn(side: String, slot: int, attack: int, health: int, effects: Array = []) -> Card3D:
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(_data(attack, health, effects))
	table._draw_to_slot(side, slot, false)
	var card := table._get_card_from_slot(side, slot)
	card.attack_out_duration = 0.025
	card.attack_hit_duration = 0.015
	card.attack_return_duration = 0.035
	card.description_label.skip()
	return card


func _id(card: Card3D) -> String:
	return str(card.card_data["instance_id"])


func _amounts(identity: String) -> Array[int]:
	var result: Array[int] = []
	for hit: Dictionary in table.observations:
		if hit["identity"] == identity:
			result.append(int(hit["amount"]))
	return result


func _real_popups() -> bool:
	return not table.observations.is_empty() and table.observations.all(func(hit: Dictionary): return bool(hit["spawned"]))


func _healed_amounts(identity: String) -> Array[int]:
	var result: Array[int] = []
	for healing: Dictionary in table.healing_observations:
		if healing["identity"] == identity and bool(healing["spawned"]):
			result.append(int(healing["amount"]))
	return result


func _check_local_healing() -> void:
	_reset()
	var regenerating := _spawn("enemy", 2, 1, 20, [{"type":"regeneration","value":8}])
	regenerating.current_hp = 17
	await table._apply_start_turn_effects("enemy")
	check(regenerating.current_hp == 20 and _healed_amounts(_id(regenerating)) == [3], "regeneration displays actual restored HP after the max-HP cap")
	var popup: DamageNumber3D = table._damage_numbers.back() if not table._damage_numbers.is_empty() else null
	check(is_instance_valid(popup) and popup.is_healing and popup.amount == 3 and popup.damage_amount == 0 and popup.label.text == "+3" and table.observations.is_empty(), "regeneration creates a real positive healing popup without a damage observation")
	table._clear_damage_numbers()
	table.healing_observations.clear()
	await table._apply_start_turn_effects("enemy")
	check(regenerating.current_hp == 20 and table._damage_numbers.is_empty(), "full-HP regeneration creates no zero or nominal healing popup")
	_reset()
	var healer := _spawn("enemy", 2, 1, 20, [{"type":"neighbor_heal","value":6}])
	var left := _spawn("enemy", 1, 1, 20)
	var right := _spawn("enemy", 3, 1, 20)
	var far := _spawn("enemy", 4, 1, 20)
	left.current_hp = 18
	right.current_hp = 10
	far.current_hp = 5
	table._apply_neighbor_heal(healer)
	check(left.current_hp == 20 and right.current_hp == 16 and _healed_amounts(_id(left)) == [2] and _healed_amounts(_id(right)) == [6], "neighbor healing shows each recipient's actual capped HP increase separately")
	check(far.current_hp == 5 and _healed_amounts(_id(far)).is_empty() and _healed_amounts(_id(healer)).is_empty() and table._damage_numbers.size() == 2, "neighbor healing creates no popup for its source or a nonadjacent card")
	_reset()
	var attacker := _spawn("enemy", 2, 8, 20, [{"type":"lifesteal","percent":0.75}])
	var defender := _spawn("player", 2, 0, 30)
	attacker.current_hp = 18
	await table._resolve_duel(attacker, defender, "enemy")
	check(attacker.current_hp == 20 and _healed_amounts(_id(attacker)) == [2] and _amounts(_id(defender)) == [8], "lifesteal shows the two HP actually restored rather than its nominal six-point heal")
	table._clear_damage_numbers()
	table.healing_observations.clear()
	await table._resolve_duel(attacker, defender, "enemy")
	check(attacker.current_hp == 20 and _healed_amounts(_id(attacker)).is_empty() and table._damage_numbers.all(func(number): return not number.is_healing), "lifesteal on a full-HP attacker never creates a healing popup")
	await get_tree().process_frame


func _check_local_duels() -> void:
	_reset()
	var attacker := _spawn("enemy", 2, 6, 30)
	var defender := _spawn("player", 2, 3, 20, [{"type":"armor","value":0.5}])
	var attacker_id := _id(attacker)
	var defender_id := _id(defender)
	await table._resolve_duel(attacker, defender, "enemy")
	check(_amounts(defender_id) == [3] and _amounts(attacker_id) == [3], "regular hit shows armor-reduced damage and a separate counter")
	check(defender.current_hp == 17 and attacker.current_hp == 27 and _real_popups(), "local hit numbers accompany real HP changes and actual popup nodes")
	await _wait_until(func(): return table._damage_numbers.is_empty())
	check(table._damage_numbers.is_empty(), "naturally expired numbers leave no tracked popup nodes")
	_reset()
	attacker = _spawn("enemy", 2, 4, 20, [{"type":"shield_first_hit"}])
	defender = _spawn("player", 2, 3, 20, [{"type":"shield_first_hit"}])
	attacker_id = _id(attacker)
	defender_id = _id(defender)
	await table._resolve_duel(attacker, defender, "enemy")
	check(_amounts(defender_id) == [0] and _amounts(attacker_id) == [0] and _real_popups(), "blocked attack and blocked counter each create a visible zero")
	check(attacker.current_hp == 20 and defender.current_hp == 20, "zero numbers do not imply lost HP")
	_reset()
	attacker = _spawn("enemy", 2, 99, 30)
	defender = _spawn("player", 2, 1, 2)
	_spawn("player", 0, 1, 20)
	attacker_id = _id(attacker)
	defender_id = _id(defender)
	await table._resolve_duel(attacker, defender, "enemy")
	check(_amounts(defender_id) == [2] and _amounts(attacker_id) == [1], "lethal overkill number is capped to available HP and the dead defender still counters")
	_reset()
	attacker = _spawn("enemy", 2, 6, 30, [{"type":"double_strike"}])
	defender = _spawn("player", 2, 1, 30, [{"type":"thorns","percent":0.5}])
	attacker_id = _id(attacker)
	defender_id = _id(defender)
	await table._resolve_duel(attacker, defender, "enemy")
	check(_amounts(defender_id) == [6, 6] and _amounts(attacker_id) == [3, 1, 3], "double strike keeps each thorns hit separate from its single counter")
	check(table.observations.size() == 5 and attacker.current_hp == 23 and defender.current_hp == 18 and _real_popups(), "multi-hit popups match every actual hit without an extra aggregated attacker number")


func _check_other_damage() -> void:
	_reset()
	var poisoned := _spawn("enemy", 1, 1, 3, [{"type":"armor","value":0.95},{"type":"shield_first_hit"}])
	var healthy := _spawn("enemy", 3, 1, 20, [{"type":"regeneration","value":3}])
	healthy.current_hp = 10
	var poison_id := _id(poisoned)
	var healthy_id := _id(healthy)
	poisoned.set_meta("poison_damage", 5)
	poisoned.set_meta("poison_turns", 1)
	await table._apply_start_turn_effects("enemy")
	check(_amounts(poison_id) == [3], "poison number bypasses armor/shield but is capped to remaining HP")
	check(_amounts(healthy_id).is_empty() and healthy.current_hp == 13 and _real_popups(), "healing and undamaged cards create no damage numbers")
	_reset()
	var attacker := _spawn("enemy", 2, 6, 30, [{"type":"cleave"}])
	var center := _spawn("player", 2, 1, 20)
	var left := _spawn("player", 1, 1, 20, [{"type":"armor","value":0.5}])
	var right := _spawn("player", 3, 1, 20, [{"type":"shield_first_hit"}])
	var far := _spawn("player", 4, 1, 20)
	table._apply_cleave(attacker, 2, "enemy")
	check(_amounts(_id(left)) == [2] and _amounts(_id(right)) == [0], "cleave shows rounded armor damage and a blocked neighbor's zero")
	check(_amounts(_id(center)).is_empty() and _amounts(_id(far)).is_empty() and table.observations.size() == 2, "cleave creates no numbers on its center or nonadjacent slots")
	_reset()
	attacker = _spawn("enemy", 2, 4, 30, [{"type":"lava"}])
	var targets: Array[Card3D] = [
		_spawn("player", 0, 1, 20, [{"type":"shield_first_hit"}]),
		_spawn("player", 1, 1, 20, [{"type":"armor","value":0.5}]),
		_spawn("player", 2, 1, 20),
		_spawn("player", 3, 1, 20, [{"type":"thorns","percent":0.5}]),
		_spawn("player", 4, 1, 20),
	]
	var attacker_id := _id(attacker)
	await table._resolve_duel(attacker, targets[2], "enemy")
	var all_targets_correct := true
	for index in range(5):
		all_targets_correct = all_targets_correct and _amounts(_id(targets[index])) == [[0], [2], [4], [4], [4]][index]
	check(all_targets_correct and _amounts(attacker_id) == [2, 1], "lava shows one mitigated number per target and separate secondary thorns/main counter")
	check(table.observations.size() == 7 and _real_popups(), "lava creates seven real popups without duplicate primary or counter totals")


func _remote_board(spectator: bool) -> Dictionary:
	_reset()
	NetworkManager.current_lobby_id = 987
	NetworkManager._match_in_progress = true
	# Direct handler calls have sender 0; no transport ACK destination is needed.
	NetworkManager._participants = {0: {"role":"player"}, 1: {"role":"player"}}
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 7
	var local_attacker_side := "player" if spectator else "enemy"
	var local_defender_side := "enemy" if spectator else "player"
	var attacker := _spawn(local_attacker_side, 2, 4, 20, [{"type":"lava"}])
	var targets: Array[Card3D] = []
	for slot in range(5):
		targets.append(_spawn(local_defender_side, slot, 1, 20))
	var attacker_state := attacker.get_network_state()
	attacker_state["current_hp"] = 14
	var defender_state := targets[2].get_network_state()
	defender_state["current_hp"] = 16
	var extras: Array[Dictionary] = []
	for slot in [0, 1, 3, 4]:
		var target_state := targets[slot].get_network_state()
		var damage := 0 if slot == 0 else 2
		target_state["current_hp"] = 20 - damage
		extras.append({"side":"enemy","slot":slot,"state":target_state,"damage":damage,"died":false,"damage_intensity":0.5})
	var impact := {
		"turn_sequence":7,"attack_sequence":1,
		"attacker_side":"player","attacker_slot":2,"defender_side":"enemy","defender_slot":2,
		"attacker_state":attacker_state,"defender_state":defender_state,
		"attacker_damage":6,"attacker_damage_hits":[2, 1, 3],"defender_damage":4,
		"damage_intensity":0.5,"lava_hits":extras,
	}
	_arm_impact(attacker, targets, impact)
	return {"attacker":attacker,"targets":targets,"impact":impact}


func _arm_impact(attacker: Card3D, targets: Array[Card3D], impact: Dictionary) -> void:
	var sequence := int(impact["attack_sequence"])
	table._online_client_attack_contexts[sequence] = {
		"attacker":attacker,"defender":targets[2],
		"canonical_attacker_side":"player","attacker_slot":2,
		"canonical_defender_side":"enemy","defender_slot":2,"lava_targets":targets.duplicate(),
	}
	table._online_client_attack_phases[sequence] = 1


func _check_remote_impacts(spectator: bool) -> void:
	var role := "spectator" if spectator else "mirrored client"
	var board := _remote_board(spectator)
	var attacker: Card3D = board["attacker"]
	var targets: Array[Card3D] = board["targets"]
	var impact: Dictionary = board["impact"]
	table._rpc_play_online_impact(impact)
	check(_amounts(_id(attacker)) == [2, 1, 3] and _amounts(_id(targets[2])) == [4], role + " preserves separate authoritative thorns/counter numbers")
	check(_amounts(_id(targets[0])) == [0] and _amounts(_id(targets[4])) == [2] and table.observations.size() == 8 and _real_popups(), role + " maps all lava numbers including zero to the correct cards")
	var count := table.observations.size()
	table._rpc_play_online_impact(impact)
	check(table.observations.size() == count, role + " ignores duplicate primary impact packets")
	var stale := impact.duplicate(true)
	stale["attack_sequence"] = 2
	stale["turn_sequence"] = 6
	_arm_impact(attacker, targets, stale)
	table._rpc_play_online_impact(stale)
	check(table.observations.size() == count, role + " rejects a stale-turn impact before creating numbers")
	var wrong_copy := impact.duplicate(true)
	wrong_copy["attack_sequence"] = 3
	wrong_copy["defender_state"]["card_data"]["instance_id"] = "retired-copy"
	_arm_impact(attacker, targets, wrong_copy)
	table._rpc_play_online_impact(wrong_copy)
	check(table.observations.size() == count, role + " rejects an impact for another owned copy")
	var legacy := impact.duplicate(true)
	legacy["attack_sequence"] = 4
	legacy.erase("attacker_damage_hits")
	_arm_impact(attacker, targets, legacy)
	table._rpc_play_online_impact(legacy)
	check(_amounts(_id(attacker)) == [2, 1, 3, 6], role + " supports legacy aggregate attacker damage exactly once")
	# A fresh snapshot may correct HP but carries no hit event to replay.
	var canonical_player := table._player_slots if spectator else table._enemy_slots
	var canonical_enemy := table._enemy_slots if spectator else table._player_slots
	var player_states := table._serialize_online_slots(canonical_player)
	var enemy_states := table._serialize_online_slots(canonical_enemy)
	enemy_states[2]["current_hp"] = 12
	var snapshot := {"turn_sequence":8,"current_turn":"player","player_slots":player_states,"enemy_slots":enemy_states,"player_deck_count":0,"enemy_deck_count":0,"game_over":false,"action_in_progress":false}
	count = table.observations.size()
	table._apply_online_state_now(snapshot)
	check(targets[2].current_hp == 12 and table.observations.size() == count, role + " applies an HP snapshot without inventing or replaying damage numbers")
	await get_tree().process_frame


func _check_generic_events(spectator: bool) -> void:
	var role := "spectator" if spectator else "mirrored client"
	var board := _remote_board(spectator)
	var targets: Array[Card3D] = board["targets"]
	var target := targets[1]
	var identity := _id(target)
	table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "burst", 0.5, false, "", -1, 3, identity)
	check(_amounts(identity) == [3] and target.current_hp == 20, role + " generic poison/cleave packet displays damage without applying it twice")
	table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "burst", 0.5, false, "", -1, 3, identity)
	check(_amounts(identity) == [3], role + " deduplicates generic damage packets")
	table._rpc_play_online_blood(7, 2, 0, "enemy", 1, "damage", 0.5, false, "", -1, 0, identity)
	check(_amounts(identity) == [3, 0] and _real_popups(), role + " pure no-blood damage packet still displays a zero")
	table._rpc_play_online_blood(6, 3, 0, "enemy", 1, "burst", 0.5, false, "", -1, 5, identity)
	table._rpc_play_online_blood(7, 3, 0, "enemy", 1, "burst", 0.5, false, "", -1, 5, "retired-copy")
	check(_amounts(identity) == [3, 0], role + " rejects stale turns and stale generic target identities")
	# Queue before animation contact, then replace the card identity before flush.
	table._online_client_attack_phases[9] = 0
	table._rpc_play_online_blood(7, 4, 9, "enemy", 1, "burst", 0.5, false, "", -1, 2, identity)
	check(_amounts(identity) == [3, 0], role + " holds generic numbers until attack contact")
	target.card_data["instance_id"] = identity + "-replacement"
	table._online_client_attack_phases[9] = 1
	table._flush_queued_online_blood_events(9)
	check(table.observations.size() == 2, role + " queued number cannot land on a replacement occupying the old slot")
	table._rpc_play_online_blood(7, 5, 0, "enemy", 1, "burst", 0.5, false, "", -1)
	check(table.observations.size() == 2, role + " legacy blood-only packet never invents a damage amount")
	await get_tree().process_frame


func _check_remote_healing(spectator: bool) -> void:
	var role := "spectator" if spectator else "mirrored client"
	var board := _remote_board(spectator)
	var targets: Array[Card3D] = board["targets"]
	var target := targets[1]
	target.current_hp = 9
	var identity := _id(target)
	table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, identity)
	check(_healed_amounts(identity) == [3] and target.current_hp == 9 and table.observations.is_empty(), role + " displays authoritative healing without applying HP a second time or creating a damage number")
	table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, identity)
	table._rpc_play_online_blood(6, 2, 0, "enemy", 1, "heal", 0.0, false, "", -1, 8, identity)
	table._rpc_play_online_blood(7, 3, 0, "enemy", 1, "heal", 0.0, false, "", -1, 8, "retired-copy")
	check(_healed_amounts(identity) == [3] and target.current_hp == 9, role + " rejects replayed, stale-turn and wrong-card healing packets")
	table._rpc_play_online_blood(7, 4, 0, "enemy", 1, "heal", 0.0, false, "", -1, 0, identity)
	table._rpc_play_online_blood(7, 5, 0, "enemy", 1, "heal", 0.0, false, "", -1)
	check(_healed_amounts(identity) == [3], role + " ignores zero or absent healing amounts instead of inventing +0")
	table._online_client_attack_phases[9] = 0
	table._rpc_play_online_blood(7, 6, 9, "enemy", 1, "heal", 0.0, false, "", -1, 2, identity)
	check(_healed_amounts(identity) == [3], role + " holds healing presentation until attack contact")
	table._online_client_attack_phases[9] = 1
	table._flush_queued_online_blood_events(9)
	check(_healed_amounts(identity) == [3, 2] and target.current_hp == 9, role + " queued healing appears exactly once at contact without changing HP")
	table._online_client_attack_phases[10] = 0
	table._rpc_play_online_blood(7, 7, 10, "enemy", 1, "heal", 0.0, false, "", -1, 4, identity)
	target.card_data["instance_id"] = identity + "-replacement"
	table._online_client_attack_phases[10] = 1
	table._flush_queued_online_blood_events(10)
	check(_healed_amounts(identity) == [3, 2] and _healed_amounts(_id(target)).is_empty(), role + " queued healing cannot land on a replacement in the old slot")
	await get_tree().process_frame


func _check_clear_lifecycle() -> void:
	var board := _remote_board(true)
	table._rpc_play_online_impact(board["impact"])
	var targets: Array[Card3D] = board["targets"]
	table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, _id(targets[1]))
	var popups := table._damage_numbers.duplicate()
	check(not popups.is_empty() and not table._damage_number_lanes.is_empty(), "active hit numbers are owned and tracked by their GameTable")
	check(popups.any(func(number): return number.is_healing) and popups.any(func(number): return not number.is_healing), "healing and damage share the same tracked popup lifecycle")
	table._online_active_exit_sequence = 1
	table._clear_match()
	check(table._damage_numbers.is_empty() and table._damage_number_lanes.is_empty(), "match cleanup immediately resets popup and lane bookkeeping")
	var count := table.observations.size()
	var heal_count := table.healing_observations.size()
	table._rpc_play_online_impact(board["impact"])
	table._rpc_play_online_blood(7, 99, 0, "enemy", 1, "damage", 0.5, false, "", -1, 0, "late-hit")
	table._rpc_play_online_blood(7, 100, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, "late-heal")
	check(table.observations.size() == count and table.healing_observations.size() == heal_count and table._damage_numbers.is_empty(), "late online damage and healing cannot recreate popups after match exit")
	await get_tree().process_frame
	check(popups.all(func(popup): return not is_instance_valid(popup)), "all popup nodes are freed after match cleanup")


func _check_setting_behavior() -> void:
	_reset()
	var attacker := _spawn("enemy", 2, 4, 20)
	var defender := _spawn("player", 2, 2, 20)
	SettingsManager.set_damage_numbers_enabled(false)
	await table._resolve_duel(attacker, defender, "enemy")
	check(defender.current_hp == 16 and attacker.current_hp == 18, "disabled numbers preserve actual attack and counter damage")
	check(table.observations.size() == 2 and table._damage_numbers.is_empty(), "disabled numbers suppress only the presentation of local hits")
	check(defender.get_blood_intensity() > 0.0 and attacker.get_blood_intensity() > 0.0, "disabled numbers retain existing hit effects")
	var regenerating := _spawn("enemy", 0, 1, 20, [{"type":"regeneration","value":3}])
	regenerating.current_hp = 5
	await table._apply_start_turn_effects("enemy")
	check(regenerating.current_hp == 8 and table._damage_numbers.is_empty(), "disabled numbers preserve real regeneration while suppressing its popup")
	SettingsManager.set_damage_numbers_enabled(true)
	await table._resolve_duel(attacker, defender, "enemy")
	check(table._damage_numbers.size() == 2, "re-enabling numbers displays the next hits")
	table._present_healing(defender, 2, false)
	check(table._damage_numbers.size() == 3 and table._damage_numbers.back().is_healing, "re-enabled healing joins active damage numbers under the shared setting")
	var active := table._damage_numbers.duplicate()
	get_tree().paused = true
	SettingsManager.set_damage_numbers_enabled(false)
	check(table._damage_numbers.is_empty() and active.all(func(number): return not number.visible), "disabling in paused settings immediately hides and clears existing numbers")
	SettingsManager.set_damage_numbers_enabled(true)
	check(table._damage_numbers.is_empty(), "re-enabling while paused never replays an old hit")
	get_tree().paused = false
	await get_tree().process_frame
	check(active.all(func(number): return not is_instance_valid(number)), "disabled active numbers free without waiting for the combat animation")
	for spectator: bool in [false, true]:
		var board := _remote_board(spectator)
		var remote_attacker: Card3D = board["attacker"]
		var targets: Array[Card3D] = board["targets"]
		SettingsManager.set_damage_numbers_enabled(false)
		table._rpc_play_online_impact(board["impact"])
		check(remote_attacker.current_hp == 14 and targets[2].current_hp == 16 and table._damage_numbers.is_empty(), "local number preference preserves authoritative online damage for " + ("spectator" if spectator else "client"))
		table._rpc_play_online_blood(7, 1, 0, "enemy", 1, "burst", 0.5, false, "", -1, 3, _id(targets[1]))
		check(table._damage_numbers.is_empty() and targets[1].get_blood_intensity() > 0.0, "disabled remote secondary numbers preserve blood presentation")
		var hp_before_healing := targets[1].current_hp
		table._rpc_play_online_blood(7, 2, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, _id(targets[1]))
		check(table._damage_numbers.is_empty() and targets[1].current_hp == hp_before_healing, "disabled remote healing remains presentation-only for " + ("spectator" if spectator else "client"))
		SettingsManager.set_damage_numbers_enabled(true)
		table._rpc_play_online_impact(board["impact"])
		table._rpc_play_online_blood(7, 2, 0, "enemy", 1, "heal", 0.0, false, "", -1, 3, _id(targets[1]))
		check(table._damage_numbers.is_empty(), "re-enabled online numbers do not replay a duplicate impact or heal")
	SettingsManager.set_damage_numbers_enabled(true)


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())
