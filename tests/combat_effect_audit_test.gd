extends Node3D

# Execute the production duel and turn-start paths. Only automatic scheduling
# of the NEXT turn is stopped, so each assertion names its exact combat boundary.
# Damage, defenses, deaths, replacements, rewards and animation contacts are real.
class AuditTable extends "res://scenes/table/GameTable.gd":
	var ended_turns: Array[String] = []
	var target_hit_records: Array[Dictionary] = []
	var thorns_hit_records: Array[Dictionary] = []
	func _end_turn_to(next_turn: String) -> void:
		ended_turns.append(next_turn)
		_current_turn = next_turn
	func _resolve_attack_target_hit(attacker: Card3D, target: Card3D, damage: int, poisoned_targets: Dictionary, eligible_guards: Variant = null) -> Dictionary:
		var result := super._resolve_attack_target_hit(attacker, target, damage, poisoned_targets, eligible_guards)
		target_hit_records.append({
			"damage": int(result.get("damage", 0)), "healed": int(result.get("healed", 0)),
			"survival_effect": str(result.get("survival_effect", "")),
			"poison_applied": bool(result.get("poison_applied", false)),
		})
		return result
	func _apply_attack_target_thorns(attacker: Card3D, target_hit: Dictionary, attacker_result: Dictionary) -> int:
		var damage := super._apply_attack_target_thorns(attacker, target_hit, attacker_result)
		if damage > 0:
			thorns_hit_records.append({
				"damage": damage, "healed": int(attacker_result.get("healed", 0)),
				"survival_effect": str(attacker_result.get("survival_effect", "")),
				"damage_hits": attacker_result.get("damage_hits", []).duplicate(),
			})
		return damage

const COVERED_TYPES := [
	"armor", "regeneration", "poison", "lifesteal", "thorns", "cleave",
	"lava", "double_strike", "stun", "chain_attack", "triple_strike",
	"last_stand", "execute", "shield_first_hit", "swarm_power",
	"grave_return", "draw_on_kill", "curse", "swap_stats", "random_damage",
	"bodyguard", "neighbor_heal",
]
var checks := 0
var failures := 0
var identity := 0
var table: AuditTable
var mirror: AuditTable


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run combat_effect_audit_test only in the isolated match-feature fixture.")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	table = _make_table(camera)
	mirror = _make_table(camera)
	await get_tree().process_frame
	_check_catalog_coverage()
	for side: String in ["player", "enemy"]:
		await _check_defenses(side)
		await _check_strikes(side)
		await _check_attack_modifiers(side)
		await _check_on_hit_status(side)
		await _check_poison_and_regeneration(side)
		await _check_survival(side)
		await _check_revival_damage_records(side)
		await _check_cleave_and_chain(side)
		await _check_lava_and_draw(side)
		await _check_bodyguard(side)
		await _check_neighbor_heal(side)
	await _drain_death_animations()
	for finished_table: AuditTable in [table, mirror]:
		finished_table._retire_online_battle_presentation()
		finished_table._online_mode = false
		finished_table._online_is_spectator = false
		finished_table._reset_online_sync_tracking()
		finished_table.target_hit_records.clear()
		finished_table.thorns_hit_records.clear()
		finished_table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame
	table.queue_free()
	mirror.queue_free()
	table = null
	mirror = null
	# Table-owned tweens and deferred callbacks must retire before the camera.
	await get_tree().process_frame
	await get_tree().process_frame
	camera.queue_free()
	camera = null
	await get_tree().process_frame
	await get_tree().process_frame
	_finish.call_deferred()


func _finish() -> void:
	print("COMBAT_EFFECT_AUDIT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _drain_death_animations() -> void:
	# The gameplay barrier frees slots before the full cosmetic flight ends.
	var deadline := Time.get_ticks_msec() + 6000
	while (not table._pending_card_deaths.is_empty() or not mirror._pending_card_deaths.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not table._pending_card_deaths.is_empty() or not mirror._pending_card_deaths.is_empty():
		failures += 1
		push_error("Combat audit teardown timed out waiting for cosmetic death jobs.")
		table._clear_match()
		mirror._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame


func _make_table(camera: Camera3D) -> AuditTable:
	var node := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate()
	var properties := {}
	for property: Dictionary in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			properties[str(property.name)] = node.get(str(property.name))
	node.set_script(AuditTable)
	for key: String in properties:
		node.set(key, properties[key])
	properties.clear()
	var result := node as AuditTable
	result.table_camera = camera
	add_child(result)
	result.set_process(false)
	result.visible = false
	result.draw_animation_duration = 0.01
	result.replacement_draw_delay = 0.01
	result.blood_burst_scene = null
	result.blood_decal_scene = null
	return result


func _check_catalog_coverage() -> void:
	var types := {}
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/effects.json"))
	for effect: Dictionary in catalog:
		types[str(effect.get("type", ""))] = true
	for data: Dictionary in CardDatabase.get_all_cards():
		for effect: Dictionary in data.get("effects", []):
			types[str(effect.get("type", ""))] = true
	check(not types.has("deck_burn"), "Deck Burn is absent from both effect and innate-card catalogs")
	for type: String in types:
		check(type in COVERED_TYPES, "Runtime audit covers declared catalog/card effect " + type)
	for type: String in COVERED_TYPES:
		check(types.has(type), "Audit type still has an actual catalog/card declaration: " + type)


func _reset() -> void:
	table._online_mode = false
	table._clear_match()
	table._reset_online_sync_tracking()
	table._online_is_host = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table.ended_turns.clear()
	table.target_hit_records.clear()
	table.thorns_hit_records.clear()
	table._initialize_event_deck()


func _opponent(side: String) -> String:
	return "enemy" if side == "player" else "player"


func _spawn(side: String, slot: int, attack: int, health: int, effects: Array = [], card_id: String = "corpse") -> Card3D:
	identity += 1
	var data := CardDatabase.get_card(card_id).duplicate(true)
	data["instance_id"] = "effect-audit-%d" % identity
	data["attack"] = attack
	data["defense"] = health
	data["animated"] = false
	data["effects"] = effects.duplicate(true)
	data["active_effects"] = effects.duplicate(true)
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	var card := table._get_card_from_slot(side, slot)
	card.attack_out_duration = 0.015
	card.attack_hit_duration = 0.01
	card.attack_return_duration = 0.015
	card.description_label.skip()
	return card


func _keep_match_alive(side: String) -> void:
	_spawn(side, 4, 0, 100)
	_spawn(_opponent(side), 4, 0, 100)


func _check_online_mirror(description: String) -> void:
	# Exercise the actual table serializer/reconciler for both presentation roles.
	# ENet authorization, impact ACKs and private hands are covered separately by
	# event_cards_network_test, lava_effect_test and damage_numbers_test.
	var snapshot := table._build_online_snapshot()
	for spectator: bool in [false, true]:
		mirror._clear_match()
		mirror._table_state = GameTable.TableState.PLAYING
		mirror._online_is_spectator = spectator
		var near_side := "player" if spectator else "enemy"
		var far_side := "enemy" if spectator else "player"
		mirror._reconcile_online_slots("player", snapshot[near_side + "_slots"], false)
		mirror._reconcile_online_slots("enemy", snapshot[far_side + "_slots"], false)
		check(mirror._serialize_online_slots(mirror._player_slots) == snapshot[near_side + "_slots"] and mirror._serialize_online_slots(mirror._enemy_slots) == snapshot[far_side + "_slots"], description + (" spectator" if spectator else " fighter") + " snapshot preserves actual HP, effects and one-use state")


func _check_defenses(side: String) -> void:
	for armor: float in [0.1, 0.25, 0.35, 0.5, 0.75]:
		_reset()
		var attacker := _spawn(side, 2, 10, 40)
		var defender := _spawn(_opponent(side), 2, 2, 40, [{"type":"armor", "value":armor}])
		await table._resolve_duel(attacker, defender, side)
		check(defender.current_hp == 40 - roundi(10.0 * (1.0 - armor)) and attacker.current_hp == 38, side + " armor " + str(armor) + " reduces a real hit, preserving one counter")
	_reset()
	var attacker := _spawn(side, 2, 4, 30)
	var defender := _spawn(_opponent(side), 2, 0, 30, [{"type":"shield_first_hit"}])
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 30 and not defender.get_network_state().first_hit_shield_available, side + " shield blocks and consumes the first hit")
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 26, side + " shield does not block the second hit")
	_check_online_mirror(side + " armor/shield")
	_reset()
	attacker = _spawn(side, 2, 0, 30)
	defender = _spawn(_opponent(side), 2, 0, 30, [{"type":"shield_first_hit"}])
	await table._resolve_duel(attacker, defender, side)
	check(bool(defender.get_network_state().first_hit_shield_available), side + " zero attack does not spend an unused first-hit shield")


func _check_strikes(side: String) -> void:
	for entry: Array in [["double_strike", 2], ["triple_strike", 3]]:
		_reset()
		var attacker := _spawn(side, 2, 5, 40, [{"type":entry[0], "hits":entry[1]}])
		var defender := _spawn(_opponent(side), 2, 2, 40, [{"type":"thorns", "percent":0.4}])
		await table._resolve_duel(attacker, defender, side)
		check(defender.current_hp == 40 - 5 * int(entry[1]), side + " " + str(entry[0]) + " executes every hit")
		check(attacker.current_hp == 38 - 2 * int(entry[1]), side + " thorns reacts to each strike, normal counter only once")
	_check_online_mirror(side + " multi-hit/thorns")
	_reset()
	var attacker := _spawn(side, 2, 4, 30, [{"type":"double_strike", "hits":3}])
	var defender := _spawn(_opponent(side), 2, 2, 30)
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 18 and attacker.current_hp == 28, side + " explicit hits overrides the strike default and still counters only once")


func _check_attack_modifiers(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 4, 30, [{"type":"random_damage", "min":1.5, "max":1.5}])
	var defender := _spawn(_opponent(side), 2, 0, 30)
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 24, side + " deterministic random-damage interval modifies the actual hit")
	_reset()
	attacker = _spawn(side, 2, 2, 30, [{"type":"swarm_power"}], "ant")
	_spawn(side, 0, 0, 30, [], "ant")
	_spawn(_opponent(side), 0, 0, 30, [], "ant")
	defender = _spawn(_opponent(side), 2, 0, 30)
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 24, side + " swarm counts the three identical cards across the battlefield")
	_reset()
	attacker = _spawn(side, 2, 3, 11, [{"type":"swap_stats"}])
	defender = _spawn(_opponent(side), 2, 0, 40)
	await table._resolve_duel(attacker, defender, side)
	check(attacker.max_hp == 3 and attacker.current_hp == 3 and defender.current_hp == 29, side + " swapped stats determine real damage and health")
	_check_online_mirror(side + " swap_stats")
	_reset()
	_keep_match_alive(side)
	attacker = _spawn(side, 2, 12, 20, [{"type":"lifesteal", "percent":0.5}])
	attacker.current_hp = 5
	defender = _spawn(_opponent(side), 2, 0, 3)
	await table._resolve_duel(attacker, defender, side)
	check(attacker.current_hp == 7, side + " lifesteal uses actual three HP lost, not twelve overkill damage")
	_check_online_mirror(side + " lifesteal/overkill")


func _check_on_hit_status(side: String) -> void:
	for chance: float in [0.0, 1.0]:
		_reset()
		var attacker := _spawn(side, 2, 2, 30, [{"type":"stun", "chance":chance}, {"type":"curse", "value":3}])
		var defender := _spawn(_opponent(side), 2, 2, 30)
		await table._resolve_duel(attacker, defender, side)
		check(bool(defender.get_network_state().skip_next_attack) == (chance == 1.0), side + " stun honors exact chance " + str(chance))
		check(defender.attack_value == 0, side + " curse permanently subtracts its value without negative attack")
		_check_online_mirror(side + " curse/stun " + str(chance))
	_reset()
	var attacker := _spawn(side, 2, 1, 30, [{"type":"stun", "chance":1.0}])
	var defender := _spawn(_opponent(side), 2, 4, 30)
	await table._resolve_duel(attacker, defender, side)
	var before := attacker.current_hp
	await table._resolve_duel(defender, attacker, _opponent(side))
	check(attacker.current_hp == before and not defender.get_network_state().skip_next_attack, side + " stun prevents and consumes exactly the next requested attack")
	await table._resolve_duel(defender, attacker, _opponent(side))
	check(attacker.current_hp == before - 4, side + " card can attack normally after its stun was consumed")


func _check_poison_and_regeneration(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 1, 40, [{"type":"poison", "damage":3, "turns":3}])
	var defender := _spawn(_opponent(side), 2, 0, 40)
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 39 and int(defender.get_meta("poison_turns", 0)) == 3, side + " attack applies configured poison without an extra immediate tick")
	for turn in range(3):
		await table._apply_start_turn_effects(_opponent(side))
		check(defender.current_hp == 36 - 3 * turn, side + " poison deals configured damage on owner turn " + str(turn + 1))
	await table._apply_start_turn_effects(_opponent(side))
	check(defender.current_hp == 30 and not defender.has_meta("poison_turns"), side + " poison expires after its configured three ticks")
	_reset()
	attacker = _spawn(side, 2, 1, 40, [{"type":"poison", "damage":3, "turns":3}])
	defender = _spawn(_opponent(side), 2, 0, 40, [{"type":"shield_first_hit"}])
	await table._resolve_duel(attacker, defender, side)
	check(defender.current_hp == 40 and not defender.has_meta("poison_turns"), side + " fully blocked hits cannot apply poison")
	_reset()
	var regenerating := _spawn(side, 2, 0, 20, [{"type":"regeneration", "value":3}])
	regenerating.current_hp = 16
	await table._apply_start_turn_effects(side)
	check(regenerating.current_hp == 19, side + " regeneration executes on owner turn start")
	await table._apply_start_turn_effects(side)
	check(regenerating.current_hp == 20, side + " regeneration respects maximum HP")
	_check_online_mirror(side + " poison/regeneration")


func _check_survival(side: String) -> void:
	for type: String in ["last_stand", "grave_return"]:
		var remaining := 1 if type == "last_stand" else 10
		_reset()
		_keep_match_alive(side)
		var attacker := _spawn(_opponent(side), 2, 30, 40)
		var defender := _spawn(side, 2, 0, 20, [{"type":type}])
		await table._resolve_duel(attacker, defender, _opponent(side))
		check(table._get_card_from_slot(side, 2) == defender and defender.current_hp == remaining, side + " " + type + " survives a lethal ordinary hit")
		_check_online_mirror(side + " consumed " + type)
		await table._resolve_duel(attacker, defender, _opponent(side))
		check(table._get_card_from_slot(side, 2) == null, side + " " + type + " cannot survive twice")
		_reset()
		_keep_match_alive(side)
		defender = _spawn(side, 2, 0, 20, [{"type":type}])
		defender.current_hp = 2
		defender.set_meta("poison_turns", 1)
		defender.set_meta("poison_damage", 3)
		await table._apply_start_turn_effects(side)
		check(table._get_card_from_slot(side, 2) == defender and defender.current_hp == remaining, side + " " + type + " also survives lethal poison")
		_reset()
		_keep_match_alive(side)
		attacker = _spawn(_opponent(side), 2, 2, 40, [{"type":"execute", "threshold":0.25}])
		defender = _spawn(side, 2, 0, 20, [{"type":type}])
		defender.current_hp = 7
		await table._resolve_duel(attacker, defender, _opponent(side))
		check(table._get_card_from_slot(side, 2) == defender and defender.current_hp == remaining, side + " " + type + " survives the execute portion of a hit")
		_reset()
		_keep_match_alive(side)
		attacker = _spawn(_opponent(side), 2, 30, 40, [{"type":"execute", "threshold":0.75}])
		defender = _spawn(side, 2, 0, 20, [{"type":type}])
		await table._resolve_duel(attacker, defender, _opponent(side))
		check(table._get_card_from_slot(side, 2) == defender and defender.current_hp == remaining, side + " execute cannot kill again after the same hit consumed " + type)
	_reset()
	_keep_match_alive(side)
	var executioner := _spawn(side, 2, 2, 40, [{"type":"execute", "threshold":0.25}])
	var above := _spawn(_opponent(side), 2, 0, 20)
	above.current_hp = 8
	await table._resolve_duel(executioner, above, side)
	check(above.current_hp == 6, side + " execute leaves a target above its threshold alive")
	await table._resolve_duel(executioner, above, side)
	check(table._get_card_from_slot(_opponent(side), 2) == null, side + " execute destroys a target reaching its threshold")


func _check_revival_damage_records(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 8, 40, [{"type":"poison", "damage":3, "turns":3}])
	var defender := _spawn(_opponent(side), 2, 0, 20, [{"type":"grave_return"}, {"type":"thorns", "percent":1.0}])
	defender.current_hp = 2
	await table._resolve_duel(attacker, defender, side)
	check(
		defender.current_hp == 10 and attacker.current_hp == 38
		and int(defender.get_meta("poison_turns", 0)) == 3
		and table.target_hit_records.size() == 1
		and table.target_hit_records[0] == {"damage":2, "healed":10, "survival_effect":"grave_return", "poison_applied":true}
		and table.thorns_hit_records.size() == 1 and int(table.thorns_hit_records[0]["damage"]) == 2,
		side + " two-HP Grave Return preserves the actual hit, poison application and two reflected HP despite gaining health"
	)
	_reset()
	attacker = _spawn(side, 2, 2, 40, [{"type":"execute", "threshold":0.25}, {"type":"lifesteal", "percent":0.5}])
	attacker.current_hp = 10
	defender = _spawn(_opponent(side), 2, 0, 20, [{"type":"grave_return"}])
	defender.current_hp = 7
	await table._resolve_duel(attacker, defender, side)
	check(
		defender.current_hp == 10 and attacker.current_hp == 14
		and table.target_hit_records.size() == 1
		and table.target_hit_records[0] == {"damage":7, "healed":10, "survival_effect":"grave_return", "poison_applied":false},
		side + " Execute records two normal plus five execution HP before Grave Return, yielding four actual Lifesteal HP"
	)
	_reset()
	attacker = _spawn(side, 2, 4, 20, [{"type":"grave_return"}])
	attacker.current_hp = 2
	defender = _spawn(_opponent(side), 2, 0, 40, [{"type":"thorns", "percent":1.0}])
	await table._resolve_duel(attacker, defender, side)
	check(
		attacker.current_hp == 10 and defender.current_hp == 36
		and table.thorns_hit_records.size() == 1
		and table.thorns_hit_records[0] == {"damage":2, "healed":10, "survival_effect":"grave_return", "damage_hits":[2]},
		side + " lethal Thorns preserves its two-HP damage record separately from the attacker's ten-HP revival"
	)
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave", "side_damage":0.5}, {"type":"lifesteal", "percent":0.5}])
	attacker.current_hp = 10
	defender = _spawn(_opponent(side), 2, 0, 40)
	var left := _spawn(_opponent(side), 1, 0, 40)
	var right := _spawn(_opponent(side), 3, 0, 40)
	var guard := _spawn(_opponent(side), 0, 0, 20, [{"type":"bodyguard", "percent":0.5}, {"type":"grave_return"}])
	guard.current_hp = 2
	await table._resolve_duel(attacker, defender, side)
	check(
		defender.current_hp == 32 and left.current_hp == 38 and right.current_hp == 36
		and guard.current_hp == 10 and not guard.get_network_state()["grave_return_available"]
		and attacker.current_hp == 18,
		side + " Cleave includes a reviving bodyguard's two redirected HP in its real damage total and eight-HP Lifesteal"
	)


func _check_cleave_and_chain(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 8, 40, [{"type":"cleave", "side_damage":0.25}])
	var main := _spawn(_opponent(side), 2, 0, 40)
	var left := _spawn(_opponent(side), 1, 0, 40)
	var right := _spawn(_opponent(side), 3, 0, 40)
	var far := _spawn(_opponent(side), 4, 0, 40)
	await table._resolve_duel(attacker, main, side)
	check(main.current_hp == 32 and left.current_hp == 38 and right.current_hp == 38 and far.current_hp == 40, side + " cleave uses side_damage and reaches only adjacent targets")
	_check_online_mirror(side + " cleave")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"chain_attack"}])
	main = _spawn(_opponent(side), 2, 0, 1)
	var next := _spawn(_opponent(side), 0, 0, 40)
	await table._resolve_duel(attacker, main, side)
	check(next.current_hp == 32 and table.ended_turns.size() == 1, side + " chain attack performs a second real duel after a kill then ends once")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave", "side_damage":0.5}, {"type":"chain_attack"}])
	main = _spawn(_opponent(side), 2, 0, 40)
	_spawn(_opponent(side), 1, 0, 1)
	await table._resolve_duel(attacker, main, side)
	check(main.current_hp == 24, side + " a cleave-only kill also earns the chain attack")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave", "side_damage":0.5}, {"type":"lifesteal", "percent":0.5}])
	attacker.current_hp = 10
	main = _spawn(_opponent(side), 2, 0, 40)
	_spawn(_opponent(side), 1, 0, 40)
	_spawn(_opponent(side), 3, 0, 40)
	await table._resolve_duel(attacker, main, side)
	check(attacker.current_hp == 18, side + " lifesteal includes actual primary and both cleave damage totals")


func _check_lava_and_draw(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 4, 40, [{"type":"lava"}, {"type":"draw_on_kill"}], "piss")
	var targets: Array[Card3D] = []
	for slot in range(GameTable.HAND_SIZE):
		targets.append(_spawn(_opponent(side), slot, 2, 1 if slot < 2 else 20))
	await table._resolve_duel(attacker, targets[2], side)
	check(targets[2].current_hp == 16 and targets[3].current_hp == 16 and targets[4].current_hp == 16 and attacker.current_hp == 38, side + " Lava hits all initial targets and takes only the selected counter")
	check(table._event_hand(side).size() == 2 and table._event_hand(_opponent(side)).is_empty() and table._event_deck.size() == 22, side + " Draw On Kill awards exactly one shared event per actual Lava kill")
	_check_online_mirror(side + " lava/draw_on_kill")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"draw_on_kill"}])
	var defender := _spawn(_opponent(side), 2, 0, 4, [{"type":"last_stand"}])
	await table._resolve_duel(attacker, defender, side)
	check(table._event_hand(side).is_empty(), side + " surviving a lethal hit never awards a kill event")
	_reset()
	attacker = _spawn(side, 2, 10, 40, [{"type":"lava"}, {"type":"triple_strike", "hits":3}], "piss")
	defender = _spawn(_opponent(side), 2, 0, 100)
	var original_neighbor := _spawn(_opponent(side), 1, 0, 1)
	var original_identity := str(original_neighbor.card_data.get("instance_id", ""))
	# Queue a real deck draw; do not place the replacement on the board.
	identity += 1
	var replacement_identity := "effect-audit-replacement-guard-%d" % identity
	var replacement_data := CardDatabase.get_card("corpse").duplicate(true)
	replacement_data["instance_id"] = replacement_identity
	replacement_data["attack"] = 0
	replacement_data["defense"] = 20
	replacement_data["animated"] = false
	replacement_data["effects"] = [{"type":"bodyguard", "percent":0.5}]
	replacement_data["active_effects"] = replacement_data["effects"].duplicate(true)
	var replacement_deck: Array[Dictionary] = table._enemy_deck if side == "player" else table._player_deck
	replacement_deck.append(replacement_data)
	await table._resolve_duel(attacker, defender, side)
	var replacement := table._get_card_from_slot(_opponent(side), 1)
	check(
		defender.current_hp == 70 and is_instance_valid(replacement)
		and str(replacement.card_data.get("instance_id", "")) == replacement_identity
		and str(replacement.card_data.get("instance_id", "")) != original_identity
		and replacement_deck.is_empty()
		and CardData.has_effect(replacement.card_data, "bodyguard")
		and replacement.max_hp == 20 and replacement.current_hp == 20,
		side + " triple Lava kills and replaces the original neighbor, but the newly drawn guard cannot intercept later hits of that same attack"
	)


func _check_bodyguard(side: String) -> void:
	_reset()
	var attacker := _spawn(_opponent(side), 2, 8, 40)
	var protected := _spawn(side, 2, 0, 30)
	var guard := _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	var far := _spawn(side, 4, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 26 and guard.current_hp == 26 and far.current_hp == 30, side + " adjacent bodyguard takes half a real hit, distant bodyguard takes none")
	_check_online_mirror(side + " bodyguard")
	_reset()
	attacker = _spawn(_opponent(side), 2, 8, 40)
	protected = _spawn(side, 2, 0, 30)
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}, {"type":"armor", "value":0.5}])
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 26 and guard.current_hp == 28, side + " bodyguard's own armor mitigates its redirected share")
	_reset()
	attacker = _spawn(_opponent(side), 2, 8, 40)
	protected = _spawn(side, 2, 0, 30, [{"type":"shield_first_hit"}])
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 30 and guard.current_hp == 30, side + " protected target's first-hit shield blocks the entire hit before redirection")
	_reset()
	attacker = _spawn(_opponent(side), 2, 8, 40)
	protected = _spawn(side, 2, 0, 30)
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	var second := _spawn(side, 3, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 26 and guard.current_hp == 26 and second.current_hp == 30, side + " two bodyguards select only the living left neighbor without recursive sharing")
	_reset()
	attacker = _spawn(side, 2, 0, 30)
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}])
	protected = _spawn(_opponent(side), 2, 8, 40)
	await table._resolve_duel(attacker, protected, side)
	check(attacker.current_hp == 26 and guard.current_hp == 26, side + " bodyguard also redirects the selected target's counterattack")
	_check_online_mirror(side + " counterattack/bodyguard")
	_reset()
	attacker = _spawn(_opponent(side), 2, 8, 40)
	protected = _spawn(side, 2, 0, 30)
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.25}])
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 24 and guard.current_hp == 28, side + " bodyguard honors a custom redirected percentage")
	_reset()
	attacker = _spawn(_opponent(side), 2, 8, 40)
	protected = _spawn(side, 2, 0, 30)
	guard = _spawn(side, 1, 0, 30, [{"type":"bodyguard", "percent":0.5}, {"type":"last_stand"}])
	guard.current_hp = 2
	await table._resolve_duel(attacker, protected, _opponent(side))
	check(protected.current_hp == 26 and table._get_card_from_slot(side, 1) == guard and guard.current_hp == 1, side + " redirected lethal damage respects bodyguard's Last Stand")


func _check_neighbor_heal(side: String) -> void:
	_reset()
	var attacker := _spawn(_opponent(side), 2, 3, 40)
	var healer := _spawn(side, 2, 0, 30, [{"type":"neighbor_heal", "value":2}])
	var neighbor := _spawn(side, 1, 0, 30)
	var far := _spawn(side, 4, 0, 30)
	neighbor.current_hp = 20
	far.current_hp = 20
	await table._resolve_duel(attacker, healer, _opponent(side))
	check(neighbor.current_hp == 20 and far.current_hp == 20 and healer.current_hp == 27, side + " neighbor-heal does not trigger early from received damage")
	await table._apply_start_turn_effects(side)
	check(neighbor.current_hp == 22 and far.current_hp == 20 and healer.current_hp == 27, side + " catalog neighbor-heal heals only adjacent allies on owner turn start")
	_check_online_mirror(side + " turn-start neighbor_heal")
	for card_id: String in ["paramedic", "repair_bot"]:
		_reset()
		var data := CardDatabase.get_card(card_id)
		healer = _spawn(side, 2, 0, 30, data.get("effects", []), card_id)
		neighbor = _spawn(side, 1, 0, 30)
		neighbor.current_hp = 20
		await table._apply_start_turn_effects(side)
		check(neighbor.current_hp == 21, side + " authored " + card_id + " heals one adjacent HP at turn start")
		attacker = _spawn(_opponent(side), 2, 3, 40)
		await table._resolve_duel(attacker, healer, _opponent(side))
		check(neighbor.current_hp == 21, side + " authored " + card_id + " does not gain an extra damage trigger")
