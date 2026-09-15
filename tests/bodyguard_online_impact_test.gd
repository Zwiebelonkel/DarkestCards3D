extends Node3D

# Observe real damage-number/death presentation without replacing any validator,
# impact handler, damage effect, state application or slot removal.
class ObservedTable extends "res://scenes/table/GameTable.gd":
	var numbers: Array[Dictionary] = []
	var deaths: Dictionary = {}

	func _spawn_damage_number(card: Card3D, amount: int) -> void:
		var before := _damage_numbers.size()
		super._spawn_damage_number(card, amount)
		numbers.append({
			"identity":str(card.card_data.get("instance_id", "")),
			"amount":amount, "hp":card.current_hp,
			"created":_damage_numbers.size() > before,
			"frame":Engine.get_process_frames(),
		})

	func _animate_card_death(card: Card3D, side: String, origin: Vector3 = Vector3(INF, INF, INF)) -> Tween:
		var identity := str(card.card_data.get("instance_id", ""))
		deaths[identity] = int(deaths.get(identity, 0)) + 1
		return super._animate_card_death(card, side, origin)

var checks := 0
var failures := 0
var identity := 0
var table: ObservedTable


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run bodyguard_online_impact_test only in the isolated match-feature fixture.")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	SettingsManager.set_damage_numbers_enabled(true)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	var node := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate()
	var properties := {}
	for property: Dictionary in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			properties[str(property.name)] = node.get(str(property.name))
	node.set_script(ObservedTable)
	for key: String in properties:
		node.set(key, properties[key])
	properties.clear()
	table = node as ObservedTable
	table.table_camera = camera
	add_child(table)
	table.visible = false
	table.set_process(false)
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	table.draw_animation_duration = 0.01
	table.replacement_draw_delay = 0.01
	await get_tree().process_frame
	for spectator: bool in [false, true]:
		_check_valid_contact(spectator)
		_check_rejections(spectator)
		_check_guard_defense_state(spectator)
		await _check_shared_lava_death(spectator)
	# The table's normal death barrier ends after slot clearance, NOT after
	# the remaining cosmetic flight. Keep the table alive until those jobs
	# have resumed and released their Tween/card references before teardown.
	await _drain_death_animations()
	table._retire_online_battle_presentation()
	table._online_mode = false
	table._online_is_spectator = false
	table._reset_online_sync_tracking()
	table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame
	table.queue_free()
	table = null
	node = null
	# Its camera must outlive table-owned shake/menu tweens during _exit_tree.
	await get_tree().process_frame
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish.call_deferred()


func _finish() -> void:
	# Leave the async setup/test frame before shutdown releases script resources.
	print("BODYGUARD_ONLINE_IMPACT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _drain_death_animations() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while not table._pending_card_deaths.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not table._pending_card_deaths.is_empty():
		failures += 1
		push_error("Bodyguard test teardown timed out waiting for cosmetic death jobs.")
		# Retain the table for two further frames so cancelled jobs observe the
		# changed generation and finish, even on the failure cleanup path.
		table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame


func _reset(spectator: bool) -> void:
	table._online_mode = false
	table._clear_match()
	table._reset_online_sync_tracking()
	table._table_state = GameTable.TableState.PLAYING
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = spectator
	table._online_turn_sequence = 7
	table.numbers.clear()
	table.deaths.clear()


func _side(canonical_side: String, spectator: bool) -> String:
	return canonical_side if spectator else ("enemy" if canonical_side == "player" else "player")


func _role(spectator: bool) -> String:
	return "spectator" if spectator else "mirrored fighter"


func _spawn(side: String, slot: int, effects: Array = []) -> Card3D:
	identity += 1
	var data := CardDatabase.get_card("corpse").duplicate(true)
	data["instance_id"] = "guard-impact-%d" % identity
	data["attack"] = 4
	data["defense"] = 20
	data["animated"] = false
	data["effects"] = effects.duplicate(true)
	data["active_effects"] = effects.duplicate(true)
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	var card := table._get_card_from_slot(side, slot)
	card.set_process(false)
	card.description_label.skip()
	return card


func _id(card: Card3D) -> String:
	return str(card.card_data.get("instance_id", ""))


func _state(card: Card3D, hp: int) -> Dictionary:
	var state := card.get_network_state()
	state["current_hp"] = hp
	return state


func _hit(side: String, slot: int, card: Card3D, damage: int, hp: int) -> Dictionary:
	return {
		"side":side, "slot":slot, "state":_state(card, hp),
		"damage":damage, "shield_blocked":false,
		"survival_effect":"", "died":hp == 0,
	}


func _board(spectator: bool, lava: bool = true) -> Dictionary:
	_reset(spectator)
	var attacker_side := _side("player", spectator)
	var defender_side := _side("enemy", spectator)
	var attacker := _spawn(attacker_side, 2, [{"type":"lava"}] if lava else [])
	var defender := _spawn(defender_side, 2)
	var guard := _spawn(defender_side, 1, [{"type":"bodyguard", "percent":0.5}])
	var counter_guard := _spawn(attacker_side, 1, [{"type":"bodyguard", "percent":0.5}])
	var untouched := _spawn(defender_side, 4)
	var guard_hits: Array[Dictionary] = [
		_hit("enemy", 1, guard, 3, 11 if lava else 15),
		_hit("enemy", 1, guard, 2, 11 if lava else 15),
		_hit("player", 1, counter_guard, 1, 19),
	]
	var lava_hits: Array[Dictionary] = []
	if lava:
		lava_hits.append(_hit("enemy", 1, guard, 4, 11))
	var impact := {
		"turn_sequence":7, "attack_sequence":1,
		"attacker_side":"player", "attacker_slot":2,
		"defender_side":"enemy", "defender_slot":2,
		"attacker_state":_state(attacker, 18), "defender_state":_state(defender, 17),
		"attacker_damage":2, "attacker_damage_hits":[2], "defender_damage":3,
		"attacker_died":false, "defender_died":false,
		"damage_intensity":0.5, "guard_hits":guard_hits, "lava_hits":lava_hits,
	}
	var original_targets: Array[Card3D] = table._player_slots.duplicate() if defender_side == "player" else table._enemy_slots.duplicate()
	var context := {
		"attacker":attacker, "defender":defender,
		"canonical_attacker_side":"player", "attacker_slot":2,
		"canonical_defender_side":"enemy", "defender_slot":2,
		"lava_targets":original_targets,
		"board_targets":{"player":table._player_slots.duplicate(), "enemy":table._enemy_slots.duplicate()},
	}
	table._online_client_attack_contexts[1] = context
	table._online_client_attack_phases[1] = 1
	table._online_queued_impact_events[1] = impact
	return {"attacker":attacker, "defender":defender, "guard":guard, "counter_guard":counter_guard, "untouched":untouched, "impact":impact, "context":context}


func _numbers_for(card: Card3D) -> Array[int]:
	var result: Array[int] = []
	for entry: Dictionary in table.numbers:
		if entry.identity == _id(card):
			result.append(int(entry.amount))
	return result


func _check_valid_contact(spectator: bool) -> void:
	var board := _board(spectator)
	var label := _role(spectator)
	check(table._validate_online_guard_hits(board.impact, board.context), label + " accepts original bodyguards on both canonical sides and repeated hits")
	var frame := Engine.get_process_frames()
	table._try_present_online_impact(1)
	check(bool(table._online_applied_impact_sequences.get(1, false)) and table._online_queued_impact_events.is_empty(), label + " consumes one validated authoritative contact")
	check(board.attacker.current_hp == 18 and board.defender.current_hp == 17 and board.guard.current_hp == 11 and board.counter_guard.current_hp == 19 and board.untouched.current_hp == 20, label + " applies final primary, Lava and both-side guard states to correct local cards")
	check(_numbers_for(board.guard) == [3, 2, 4] and _numbers_for(board.counter_guard) == [1], label + " repeated guard records retain distinct damage numbers plus their own Lava hit")
	check(table.numbers.all(func(entry: Dictionary): return entry.created and int(entry.frame) == frame), label + " all contact damage uses real popup nodes in the same frame")
	var final_guard_hp := true
	for entry: Dictionary in table.numbers:
		if entry.identity == _id(board.guard):
			final_guard_hp = final_guard_hp and int(entry.hp) == 11
	check(final_guard_hp, label + " guard damage presentation always sees its final HP rather than intermediate snapshots")
	var count := table.numbers.size()
	table._online_queued_impact_events[1] = board.impact.duplicate(true)
	table._try_present_online_impact(1)
	check(table.numbers.size() == count and board.guard.current_hp == 11 and table.deaths.is_empty(), label + " replayed packet neither reapplies guard hits nor starts death")


func _check_rejections(spectator: bool) -> void:
	for kind: String in ["array", "entry", "overflow", "side", "negative_slot", "large_slot", "state_type", "empty_state", "wrong_identity", "nonguard", "replacement", "missing_board"]:
		var board := _board(spectator)
		var impact: Dictionary = board.impact
		var context: Dictionary = board.context
		match kind:
			"array":
				impact.guard_hits = "invalid"
			"entry":
				impact.guard_hits = ["invalid"]
			"overflow":
				var oversized: Array[Dictionary] = []
				for index in range(GameTable.HAND_SIZE * 2 + 1):
					oversized.append(impact.guard_hits[0].duplicate(true))
				impact.guard_hits = oversized
			"side":
				impact.guard_hits[0].side = "garbage"
			"negative_slot":
				impact.guard_hits[0].slot = -1
			"large_slot":
				impact.guard_hits[0].slot = GameTable.HAND_SIZE
			"state_type":
				impact.guard_hits[0].state = "invalid"
			"empty_state":
				impact.guard_hits[0].state = {}
			"wrong_identity":
				impact.guard_hits[0].state.card_data.instance_id = "retired-original"
			"nonguard":
				impact.guard_hits[0] = _hit("enemy", 4, board.untouched, 2, 18)
			"replacement":
				var old := board.guard as Card3D
				var replacement := _spawn(_side("enemy", spectator), 1, [{"type":"bodyguard", "percent":0.5}])
				# Even the same persisted card identity cannot authorize a NEW node
				# which entered the original slot after this attack began.
				replacement.card_data["instance_id"] = old.card_data["instance_id"]
				old.queue_free()
			"missing_board":
				context.erase("board_targets")
		check(not table._validate_online_guard_hits(impact, context), _role(spectator) + " validator rejects " + kind)
		table._try_present_online_impact(1)
		check(not bool(table._online_applied_impact_sequences.get(1, true)) and board.attacker.current_hp == 20 and board.defender.current_hp == 20 and table.numbers.is_empty() and table.deaths.is_empty(), _role(spectator) + " invalid " + kind + " rejects the whole contact before HP, popups or deaths")
	var board := _board(spectator)
	var bounded: Array[Dictionary] = []
	for index in range(GameTable.HAND_SIZE * 2):
		bounded.append(board.impact.guard_hits[0].duplicate(true))
	board.impact.guard_hits = bounded
	check(table._validate_online_guard_hits(board.impact, board.context), _role(spectator) + " accepts exactly the documented ten-record bound")
	board.impact.erase("guard_hits")
	check(table._validate_online_guard_hits(board.impact, {}), _role(spectator) + " legacy packet without guard hits needs no original-board map")


func _check_guard_defense_state(spectator: bool) -> void:
	var board := _board(spectator, false)
	var guard := board.guard as Card3D
	guard.card_data["effects"] = [{"type":"bodyguard"}, {"type":"shield_first_hit"}]
	guard.card_data["active_effects"] = guard.card_data.effects.duplicate(true)
	var shielded := _hit("enemy", 1, guard, 0, 20)
	shielded.shield_blocked = true
	shielded.state.first_hit_shield_available = false
	board.impact.guard_hits = [shielded]
	table._try_present_online_impact(1)
	check(guard.current_hp == 20 and not bool(guard.get_network_state().first_hit_shield_available) and _numbers_for(guard) == [0], _role(spectator) + " blocked guard share preserves HP, consumes shield and presents one zero")
	board = _board(spectator, false)
	guard = board.guard as Card3D
	guard.card_data["effects"] = [{"type":"bodyguard"}, {"type":"last_stand"}]
	guard.card_data["active_effects"] = guard.card_data.effects.duplicate(true)
	var rescued := _hit("enemy", 1, guard, 19, 1)
	rescued.survival_effect = "last_stand"
	rescued.state.last_stand_available = false
	board.impact.guard_hits = [rescued]
	table._try_present_online_impact(1)
	check(guard.current_hp == 1 and not bool(guard.get_network_state().last_stand_available) and table.deaths.is_empty(), _role(spectator) + " guard survival state is consumed without a death animation")


func _check_shared_lava_death(spectator: bool) -> void:
	var board := _board(spectator)
	var guard := board.guard as Card3D
	var guard_id := _id(guard)
	for hit: Dictionary in board.impact.guard_hits:
		if str(hit.side) == "enemy":
			hit.state.current_hp = 0
			hit.died = true
	board.impact.lava_hits[0].state.current_hp = 0
	board.impact.lava_hits[0].damage = 15
	board.impact.lava_hits[0].died = true
	var side := _side("enemy", spectator)
	var reserve: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	reserve.append(CardDatabase.get_card("corpse").duplicate(true))
	table._try_present_online_impact(1)
	check(table._get_card_from_slot(side, 1) == null and int(table.deaths.get(guard_id, 0)) == 1, _role(spectator) + " guard also killed as a Lava target leaves its slot and flies away exactly once")
	check(_numbers_for(guard) == [3, 2, 15], _role(spectator) + " lethal combined contact preserves each guard/Lava damage number")
	var popup_count := table.numbers.size()
	table._online_queued_impact_events[1] = board.impact.duplicate(true)
	table._try_present_online_impact(1)
	check(int(table.deaths.get(guard_id, 0)) == 1 and table.numbers.size() == popup_count, _role(spectator) + " replay of a lethal guard/Lava packet cannot kill or display twice")
	await table._wait_for_pending_card_deaths()
	check(reserve.size() == 1 and table._get_card_from_slot(side, 1) == null, _role(spectator) + " remote guard death never consumes a replacement reserved for the authority")
	# Do not cancel this still-running flight in the next role's _reset.
	await _drain_death_animations()
