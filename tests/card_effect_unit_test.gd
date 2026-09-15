extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")

var checks := 0
var failures := 0
var _cards: Array[Card3D] = []
var _saved_files: Dictionary = {}
var _catalog_before: Array[Dictionary] = []
var _effects_before: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	for path in [SaveSlots.SAVE_ROOT, SaveSlots.REGISTRY_PATH, CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path, SettingsManager.CONFIG_PATH]:
		if not str(path).begins_with("res://test-user/"):
			push_error("Use the isolated match-feature runner; never run this suite against player saves.")
			get_tree().quit(1)
			return
	GameCurrency.set_process(false)
	Localization.set_locale("en")
	for path in [CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path, SettingsManager.CONFIG_PATH, "res://data/cards.json", "res://data/effects.json"]:
		_saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	_catalog_before = CardDatabase.get_all_cards().duplicate(true)
	_effects_before = EffectDatabase.get_all_effects().duplicate(true)
	_check_damage_and_healing()
	_check_armor_and_shield()
	_check_survival()
	_check_attack_parameters()
	_check_lifesteal_and_thorns()
	_check_network_and_stolen_state()
	_check_catalog_setup()
	check(CardDatabase.get_all_cards() == _catalog_before and EffectDatabase.get_all_effects() == _effects_before, "combat methods and card setup never mutate either shared catalog")
	for path: String in _saved_files:
		var after: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(after == _saved_files[path], "unit combat leaves file bytes unchanged: " + path.get_file())
	for card in _cards:
		card.queue_free()
	await get_tree().process_frame
	print("CARD_EFFECT_UNIT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _card(attack: int = 7, hp: int = 10, effects: Array = [], holo: bool = false) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	add_child(card)
	card.position.x = 1000.0 + _cards.size() * 2.0
	card.setup({
		"id": "effect_unit", "instance_id": "effect-unit-%d" % _cards.size(),
		"name": "Effect unit", "category": "combat", "rarity": "common",
		"attack": attack, "defense": hp, "effects": effects.duplicate(true),
		"image": "res://assets/effects/placeholder.png", "is_holo": holo,
	})
	card.description_label.skip()
	_cards.append(card)
	return card


func _check_damage_and_healing() -> void:
	var card := _card()
	var authored := card.card_data.duplicate(true)
	var death_count: Array[int] = [0]
	card.died.connect(func(_dead_card: Card3D): death_count[0] += 1)
	check(not card.take_damage(4) and card.current_hp == 6 and card.defense_label.text == "6", "direct damage updates current HP and its printed number")
	card.take_damage(-4)
	card.take_damage(0)
	check(card.current_hp == 6 and death_count[0] == 0, "nonpositive damage never heals or emits a death")
	card.heal(3)
	check(card.current_hp == 9 and card.max_hp == 10 and card.defense_label.text == "9", "ordinary healing restores missing HP without increasing maximum HP")
	card.heal(99)
	check(card.current_hp == 10, "ordinary healing caps at maximum HP")
	card.heal(5, true)
	check(card.current_hp == 15 and card.max_hp == 10, "explicit overheal preserves the separate maximum")
	card.heal(3)
	card.heal(-8, true)
	card.heal(0)
	check(card.current_hp == 15 and card.defense_label.text == "15", "capped, negative and zero heals cannot remove preexisting overheal")
	card.apply_curse(3)
	check(card.attack_value == 4 and card.attack_label.text == "4", "Curse reduces the current attack and its label")
	card.apply_curse(-3)
	card.apply_curse(0)
	check(card.attack_value == 4, "nonpositive Curse never becomes a stat increase")
	card.apply_curse(99)
	check(card.attack_value == 0 and card.attack_label.text == "0", "Curse cannot make attack negative")
	check(card.take_damage(99) and card.current_hp == 0 and death_count[0] == 1, "a lethal hit clamps HP and emits one death notification")
	check(card.take_damage(1) and card.take_damage(0) and death_count[0] == 1, "further hits on a dead card never emit duplicate death notifications")
	card.heal(10)
	card.heal(10, true)
	check(card.current_hp == 0 and not card.try_survive_death(), "ordinary healing cannot resurrect a card without an available death save")
	check(card.card_data == authored, "damage, healing and curses remain transient combat state")


func _check_armor_and_shield() -> void:
	check(is_equal_approx(float(EffectDatabase.get_effect("armor").get("value", -1)), 0.25), "catalog default armor is 25 percent")
	for sample: Array in [[0.10, 5, 5], [0.25, 6, 5], [0.35, 5, 3], [0.5, 7, 4], [0.75, 6, 2], [1.0, 20, 1], [-0.2, 7, 7]]:
		var defender := _card(1, 100, [{"type": "armor", "value": sample[0]}, {"type": "shield_first_hit"}])
		var before := defender.get_network_state()
		check(CombatResolver.get_damage_after_armor(defender, int(sample[1])) == int(sample[2]) and defender.get_network_state() == before, "pure armor mitigation rounds and clamps without consuming state: " + str(sample[0]))
		var blocked := CombatResolver.apply_incoming_damage(defender, int(sample[1]))
		check(blocked["shield_blocked"] and int(blocked["damage"]) == 0 and defender.current_hp == 100, "first-hit shield precedes armor and blocks exactly one positive hit")
		var actual := CombatResolver.apply_incoming_damage(defender, int(sample[1]))
		check(not actual["shield_blocked"] and int(actual["damage"]) == int(sample[2]) and defender.current_hp == 100 - int(sample[2]), "later hits use the configured armor after the shield is spent")
	var default_armor := _card(1, 100, [{"type": "armor"}])
	check(CombatResolver.get_damage_after_armor(default_armor, 20) == 15, "a type-only armor effect uses the actual 25-percent catalog default")
	check(default_armor._get_effect_icon_path({"type": "armor"}) == "res://assets/effects/armor_25.png", "type-only armor uses the matching default 25-percent icon")
	check(CombatResolver.get_damage_after_armor(default_armor, -20) == 0, "pure armor never turns negative damage into healing")
	var shield := _card(1, 10, [{"type": "shield_first_hit"}, {"type": "last_stand"}])
	var before := shield.get_network_state()
	for amount in [-3, 0]:
		var no_hit := CombatResolver.apply_incoming_damage(shield, amount)
		check(int(no_hit["damage"]) == 0 and not no_hit["shield_blocked"] and not no_hit["died"] and shield.get_network_state() == before, "nonpositive incoming damage leaves both one-use defenses available")
	check(CombatResolver.apply_incoming_damage(shield, 50)["shield_blocked"] and shield.current_hp == 10 and shield._last_stand_available, "the next actual hit still consumes only the intact shield")
	var raw_target := _card(1, 10, [{"type": "armor", "value": 0.75}, {"type": "shield_first_hit"}])
	var raw := CombatResolver.apply_damage_with_survival(raw_target, 4)
	check(int(raw["damage"]) == 4 and raw_target.current_hp == 6 and raw_target._first_hit_shield_available and not raw["shield_blocked"], "raw-damage helper bypasses armor and preserves the first-hit shield")
	var frail := _card(1, 3, [{"type": "armor", "value": 0.25}])
	var overkill := CombatResolver.apply_incoming_damage(frail, 100)
	check(overkill["died"] and int(overkill["damage"]) == 3 and frail.current_hp == 0, "overkill reports only the three HP actually removed")


func _check_survival() -> void:
	var survivor := _card(7, 10, [{"type": "last_stand"}, {"type": "grave_return"}], true)
	var body := survivor.card_model.get_node("Cube") as MeshInstance3D
	var body_material := body.get_active_material(0)
	var initial := survivor.get_network_state()
	check(not survivor.try_survive_death() and survivor.get_network_state() == initial, "checking a living card does not consume either survival charge")
	var first := CombatResolver.apply_damage_with_survival(survivor, 100)
	check(not first["died"] and first["survival_effect"] == "last_stand" and survivor.current_hp == 1 and int(first["damage"]) == 9 and int(first["healed"]) == 0, "Last Stand has priority, prevents the final HP of damage and creates no healing")
	check(not survivor._last_stand_available and survivor._grave_return_available and not survivor.has_meta("last_survival_effect"), "the resolver consumes only the used charge and clears its presentation marker")
	check(survivor._death_dissolve == null and body.get_active_material(0) == body_material and survivor.attack_label.visible and survivor.defense_label.visible, "saving a Holo card never starts dissolve or replaces its live material")
	check(CombatResolver.apply_damage_with_survival(survivor, 0)["survival_effect"] == "" and survivor._grave_return_available, "a zero-damage continuation cannot consume the second survival effect")
	var second := CombatResolver.apply_damage_with_survival(survivor, 100)
	check(not second["died"] and second["survival_effect"] == "grave_return" and survivor.current_hp == 5 and int(second["damage"]) == 1 and int(second["healed"]) == 5, "Grave Return reports the actual lethal hit separately from its restored half-health")
	var third := CombatResolver.apply_damage_with_survival(survivor, 100)
	check(third["died"] and int(third["damage"]) == 5 and survivor.current_hp == 0, "a third lethal hit kills after both independent survival charges are consumed")
	var dead_state := survivor.get_network_state()
	check(CombatResolver.apply_damage_with_survival(survivor, 20)["died"] and survivor.get_network_state() == dead_state, "already dead cards cannot consume or recreate survival state")
	var odd := _card(1, 13, [{"type": "grave_return"}])
	var revival := CombatResolver.apply_incoming_damage(odd, 99)
	check(odd.current_hp == 7 and revival["survival_effect"] == "grave_return" and int(revival["damage"]) == 13 and int(revival["healed"]) == 7, "odd maximum HP uses rounded half-health revival without hiding damage already taken")
	var wounded := _card(1, 20, [{"type": "grave_return"}])
	wounded.take_damage(18)
	var recovered := CombatResolver.apply_damage_with_survival(wounded, 100)
	check(wounded.current_hp == 10 and int(recovered["damage"]) == 2 and int(recovered["healed"]) == 10, "a two-HP grave return still reports its real hit and separate ten-HP revival")
	var minimum := _card(1, 1, [{"type": "grave_return"}])
	check(not CombatResolver.apply_damage_with_survival(minimum, 99)["died"] and minimum.current_hp == 1, "one-HP Grave Return never rounds down to a dead card")
	var other := _card(7, 10, [{"type": "last_stand"}], true)
	var other_material := (other.card_model.get_node("Cube") as MeshInstance3D).get_active_material(0)
	survivor.begin_death_dissolve()
	survivor.set_death_dissolve_progress(0.5)
	check((other.card_model.get_node("Cube") as MeshInstance3D).get_active_material(0) == other_material and other._death_dissolve == null and other._last_stand_available, "dissolving the confirmed dead card leaves another Holo card and its survival untouched")


func _check_attack_parameters() -> void:
	var ordinary := _card(7, 10)
	check(CombatResolver.get_hit_count(ordinary) == 1 and CombatResolver.get_attack_damage(ordinary, 5) == 7, "ordinary cards get one hit and no implicit identical-card bonus")
	for sample: Array in [[{"type": "double_strike"}, 2], [{"type": "double_strike", "hits": 4}, 4], [{"type": "triple_strike"}, 3], [{"type": "triple_strike", "hits": 6}, 6], [{"type": "double_strike", "hits": 0}, 1], [{"type": "triple_strike", "hits": 500}, 8]]:
		var attacker := _card(7, 10, [sample[0]])
		check(CombatResolver.get_hit_count(attacker) == int(sample[1]), "multi-strike uses its configured bounded hit count: " + str(sample[0]))
	var combined := _card(7, 10, [{"type": "double_strike", "hits": 8}, {"type": "triple_strike", "hits": 4}])
	check(CombatResolver.get_hit_count(combined) == 4, "Triple Strike retains precedence when both effects are present")
	check(CombatResolver.get_hit_count(_card(1, 10, [EffectDatabase.get_effect("double_strike")])) == 2 and CombatResolver.get_hit_count(_card(1, 10, [EffectDatabase.get_effect("triple_strike")])) == 3, "type-only strike defaults match both catalog entries")
	var swarm := _card(3, 10, [{"type": "swarm_power"}])
	check(CombatResolver.get_attack_damage(swarm, 0) == 3 and CombatResolver.get_attack_damage(swarm, 1) == 3 and CombatResolver.get_attack_damage(swarm, 4) == 12, "Swarm Power multiplies by identical living copies with a minimum factor of one")
	swarm.apply_curse(2)
	check(CombatResolver.get_attack_damage(swarm, 4) == 4, "Swarm Power uses cursed current attack rather than immutable catalog attack")
	seed(90217)
	var expected_rng := randi()
	seed(90217)
	CombatResolver.get_attack_damage(ordinary, 5)
	CombatResolver.get_attack_damage(swarm, 5)
	check(randi() == expected_rng, "attacks without Random Damage do not consume RNG")
	var random := _card(20, 10, [{"type": "random_damage", "min": 0.5, "max": 1.8}])
	var sequence: Array[int] = []
	seed(54321)
	for index in range(32):
		sequence.append(CombatResolver.get_attack_damage(random))
	var repeat: Array[int] = []
	seed(54321)
	for index in range(32):
		repeat.append(CombatResolver.get_attack_damage(random))
	check(sequence == repeat and sequence.all(func(value: int): return value >= 10 and value <= 36) and sequence.min() != sequence.max(), "custom random-damage bounds produce a reproducible variable damage sequence")
	var fixed_random := _card(20, 10, [{"type": "swarm_power"}, {"type": "random_damage", "min": 0.5, "max": 0.5}])
	check(CombatResolver.get_attack_damage(fixed_random, 3) == 30, "Random Damage multiplies the swarm total using its explicit custom parameters")
	var default_random := _card(100, 10, [{"type": "random_damage"}])
	var defaults_match := true
	seed(3109)
	for index in range(32):
		var damage := CombatResolver.get_attack_damage(default_random)
		defaults_match = defaults_match and damage >= 75 and damage <= 125
	check(defaults_match and EffectDatabase.get_effect("random_damage")["min"] == 0.75 and EffectDatabase.get_effect("random_damage")["max"] == 1.25, "type-only random-damage bounds match the catalog")


func _check_lifesteal_and_thorns() -> void:
	check(EffectDatabase.get_effect("lifesteal")["percent"] == 0.2 and EffectDatabase.get_effect("thorns")["percent"] == 0.25, "Lifesteal and Thorns catalog percentages match combat defaults")
	var leech := _card(7, 10, [{"type": "lifesteal"}])
	leech.take_damage(6)
	check(CombatResolver.heal_from_lifesteal(leech, 20) == 4 and leech.current_hp == 8, "type-only Lifesteal heals 20 percent of real damage")
	check(CombatResolver.heal_from_lifesteal(leech, 20) == 2 and leech.current_hp == 10, "Lifesteal returns only the health actually restored at its cap")
	check(CombatResolver.heal_from_lifesteal(leech, 100) == 0 and leech.current_hp == 10, "full-health Lifesteal produces zero effective healing")
	leech.heal(5, true)
	check(CombatResolver.heal_from_lifesteal(leech, 100) == 0 and leech.current_hp == 15, "capped Lifesteal preserves existing overheal and reports no gain")
	var cat := _card(4, 5, [{"type": "lifesteal", "percent": 0.1}])
	cat.take_damage(3)
	check(CombatResolver.heal_from_lifesteal(cat, 10) == 1 and cat.current_hp == 3, "a custom 10-percent Lifesteal uses whole-HP rounding")
	check(CombatResolver.heal_from_lifesteal(cat, 2) == 0 and CombatResolver.heal_from_lifesteal(cat, -10) == 0 and cat.current_hp == 3, "small and nonpositive lifesteal amounts do not invent a heal")
	cat.take_damage(99)
	check(CombatResolver.heal_from_lifesteal(cat, 100) == 0 and cat.is_dead(), "Lifesteal never revives a dead attacker")
	for sample: Array in [[{"type": "thorns"}, 8, 2], [{"type": "thorns", "percent": 0.15}, 20, 3], [{"type": "thorns", "percent": 0.2}, 20, 4], [{"type": "thorns", "percent": 0.25}, 2, 1]]:
		var defender := _card(1, 10, [sample[0]])
		var attacker := _card(1, 10, [{"type": "armor", "value": 0.75}, {"type": "shield_first_hit"}])
		check(not CombatResolver.apply_thorns(defender, attacker, int(sample[1])) and attacker.current_hp == 10 - int(sample[2]) and attacker._first_hit_shield_available, "Thorns rounds its percentage and bypasses armor and the first-hit shield: " + str(sample[0]))
	var no_hit := _card(1, 10, [{"type": "thorns", "percent": 1.0}])
	var no_target := _card()
	check(not CombatResolver.apply_thorns(no_hit, no_target, 0) and no_target.current_hp == 10, "zero damage received never reflects phantom thorns")
	var regen := _card(1, 10, [EffectDatabase.get_effect("regeneration")])
	regen.take_damage(5)
	regen.heal(int(CardData.get_effect(regen.card_data, "regeneration")["value"]))
	check(regen.current_hp == 8 and regen.defense_label.text == "8", "the real heal method applies the catalog's three-HP regeneration value")


func _check_network_and_stolen_state() -> void:
	var source := _card(9, 13, [{"type": "shield_first_hit"}, {"type": "last_stand"}], true)
	CombatResolver.apply_incoming_damage(source, 10)
	CombatResolver.apply_incoming_damage(source, 100)
	source.heal(16, true)
	source.apply_curse(2)
	source.stun_next_attack()
	source.apply_event_block(3)
	source.apply_event_block(1)
	source.tick_event_block()
	source.set_meta("poison_damage", 2)
	source.set_meta("poison_turns", 3)
	var snapshot := source.get_network_state()
	check(source.current_hp == 17 and source.max_hp == 13 and source.attack_value == 7 and source.event_block_turns == 2, "a mixed live state retains damage saves, overheal, Curse and refreshed block duration")
	var replica := _card()
	replica.apply_network_state(snapshot)
	check(replica.get_network_state() == snapshot and CardData.is_holo(replica.card_data), "network round-trip preserves exact HP, attack, effects, Holo, poison, stun and consumed survival flags")
	check(replica.defense_label.text == "17" and replica.attack_label.text == "7" and replica._event_block_badge.visible, "restored state immediately prints its actual combat values and block badge")
	check(replica.consume_stun() and not replica.consume_stun() and not replica.consume_first_hit_shield() and not replica._last_stand_available, "restored one-use states cannot be replayed")
	var stolen_data := source.export_event_deck_card()
	var redrawn := _card()
	redrawn.setup(stolen_data)
	check(redrawn.get_network_state() == snapshot and not redrawn.card_data.has(Card3D.EVENT_MATCH_STATE_KEY), "stolen-card redraw restores transient state once without leaking the embedded match snapshot into card data")
	snapshot["card_data"]["effects"][0]["type"] = "curse"
	check(CardData.has_effect(source.card_data, "shield_first_hit") and CardData.has_effect(replica.card_data, "shield_first_hit"), "network dictionaries are detached from both original and replica card effects")
	var swapped := _card(4, 11, [{"type": "swap_stats"}, {"type": "last_stand"}])
	check(swapped.attack_value == 11 and swapped.max_hp == 4 and swapped.current_hp == 4, "Swap Stats exchanges the supplied upgraded attack and maximum HP exactly once")
	swapped.apply_curse(5)
	swapped.take_damage(1)
	swapped.apply_event_strength(1.5)
	check(swapped.attack_value == 9 and swapped.max_hp == 6 and swapped.current_hp == 5, "Strength scales current swapped and cursed values while preserving proportional damage with rounding")
	var swapped_snapshot := swapped.get_network_state()
	replica.apply_network_state(swapped_snapshot)
	redrawn.setup(swapped.export_event_deck_card())
	check(replica.get_network_state() == swapped_snapshot and redrawn.get_network_state() == swapped_snapshot, "network update and stolen redraw never apply Swap Stats a second time")
	Localization.set_locale("de")
	check(swapped.get_network_state() == swapped_snapshot and replica.get_network_state() == swapped_snapshot, "changing language does not heal, re-swap or restore consumed combat state")
	source.set_meta("last_survival_effect", "grave_return")
	source.setup(source.card_data.duplicate(true))
	check(source.current_hp == 13 and source.attack_value == 9 and source._first_hit_shield_available and source._last_stand_available and not source._skip_next_attack and source.event_block_turns == 0, "fresh setup resets mutable values and one-use charges for a new match")
	check(not source.has_meta("poison_turns") and not source.has_meta("poison_damage") and not source.has_meta("last_survival_effect"), "fresh setup clears poison and stale survival presentation metadata")


func _check_catalog_setup() -> void:
	var card := _card()
	var valid_stats := true
	var valid_flags := true
	var count := 0
	for data: Dictionary in CardDatabase.get_all_cards():
		card.setup(data)
		card.description_label.skip()
		if not CardData.is_combat_card(data):
			valid_flags = valid_flags and not card.attack_label.visible and not card.defense_label.visible and not card._first_hit_shield_available and not card._last_stand_available and not card._grave_return_available
			continue
		count += 1
		var attack := int(data.get("attack", 0))
		var hp := int(data.get("defense", 0))
		if CardData.has_effect(data, "swap_stats"):
			var original_attack := attack
			attack = hp
			hp = original_attack
		valid_stats = valid_stats and card.attack_value == attack and card.max_hp == hp and card.current_hp == hp and card.attack_label.text == str(attack) and card.defense_label.text == str(hp)
		valid_flags = valid_flags and card._first_hit_shield_available == CardData.has_effect(data, "shield_first_hit") and card._last_stand_available == CardData.has_effect(data, "last_stand") and card._grave_return_available == CardData.has_effect(data, "grave_return")
	check(count > 50 and valid_stats, "every authored combat card initializes its exact stats, including active Swap Stats")
	check(valid_flags, "reusing one node across the complete catalog neither leaks survival charges nor activates them on special/event cards")
