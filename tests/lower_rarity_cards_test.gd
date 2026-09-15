extends Node3D

const PLACEHOLDER := "res://assets/effects/placeholder.png"
const CARD_GROUPS := {
	"common": ["rat", "street_dog", "brick", "plastic_chair", "angry_pigeon", "moldy_bread", "bottle", "shopping_cart", "sock", "sewer_rat"],
	"uncommon": ["crab", "security_guard", "drunk_guy", "stray_cat", "broken_robot", "cactus_dealer", "sewer_worker", "angry_goose", "trash_monster", "rat_king"],
	"rare": ["butcher", "paramedic", "bouncer", "pickpocket", "rabid_dog", "cultist", "chainsaw_guy", "repair_bot"],
}
const IMPLEMENTED_EFFECTS := ["armor", "poison", "thorns", "lifesteal", "random_damage", "swarm_power", "cleave", "neighbor_heal", "curse", "grave_return"]
const FORBIDDEN_PROPERTIES := ["animated", "frame_count", "frame_columns", "frame_rows", "frame_fps", "requires", "unique_unlock", "permanent_upgrade", "area_unlock", "upgrade_effect", "evolution", "evolves_to"]

var checks := 0
var failures: Array[String] = []
var all_ids: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run lower_rarity_cards_test with the isolated match feature runner.")
		get_tree().quit(1)
		return
	Localization.set_locale("en")
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	CardUpgradeManager.upgrades.clear()
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	# Begin with an older profile, then verify additions preserve its contents.
	CollectionManager.collection = {"corpse": 2, "metadata": {"test_sentinel": "legacy profile"}}
	CollectionManager._migrate_legacy_collection()
	for rarity: String in CARD_GROUPS:
		for value: String in CARD_GROUPS[rarity]:
			all_ids.append(value)
	_check_catalog()
	_check_rewards()
	_check_collection_deck_and_network()
	_check_effect_execution()
	await _check_rendered_collection()
	for failure in failures:
		push_error(failure)
	print("LOWER_RARITY_CARDS_TESTS: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_catalog() -> void:
	check(all_ids.size() == 28 and CARD_GROUPS.common.size() == 10 and CARD_GROUPS.uncommon.size() == 10 and CARD_GROUPS.rare.size() == 8, "Requested roster contains exactly 10 Common, 10 Uncommon and 8 Rare cards")
	check(ResourceLoader.exists(PLACEHOLDER) and load(PLACEHOLDER) is Texture2D, "The shared existing placeholder loads as a texture")
	var catalog := CardDatabase.get_all_cards()
	var combat := CardDatabase.get_combat_cards()
	var occurrences: Dictionary = {}
	for data: Dictionary in catalog:
		var id := str(data.get("id", ""))
		occurrences[id] = int(occurrences.get(id, 0)) + 1
	for rarity: String in CARD_GROUPS:
		var rarity_pool := CardDatabase.get_cards_by_rarity(rarity)
		for id: String in CARD_GROUPS[rarity]:
			check(int(occurrences.get(id, 0)) == 1, id + " has one unique catalog entry")
			if not CardDatabase.has_card(id):
				continue
			var data := CardDatabase.get_card(id)
			check(str(data.get("rarity", "")) == rarity, id + " uses its requested rarity")
			check(CardData.is_combat_card(data) and not CardData.is_upgrade_collection_card(data) and not CardData.is_unique_unlock(data), id + " is a normal combat card")
			check(_contains_id(combat, id) and _contains_id(rarity_pool, id), id + " appears in combat and rarity catalogs")
			check(not str(data.get("name", "")).is_empty() and not str(data.get("description", "")).is_empty(), id + " has printed name and description")
			check(int(data.get("attack", 0)) > 0 and int(data.get("defense", 0)) > 0, id + " has positive combat stats")
			check(str(data.get("image", "")) == PLACEHOLDER, id + " reuses the common placeholder")
			for property: String in FORBIDDEN_PROPERTIES:
				check(not data.has(property), id + " does not introduce " + property)
			var effects: Variant = data.get("effects")
			check(effects is Array and effects.size() <= CardData.MAX_EFFECTS_PER_CARD, id + " uses the existing effects array")
			if effects is Array:
				for effect: Dictionary in effects:
					var type := str(effect.get("type", ""))
					check(type in IMPLEMENTED_EFFECTS and not EffectDatabase.get_effect(type).is_empty(), id + " uses implemented effect " + type)
					_check_effect_parameters(id, effect)


func _check_effect_parameters(id: String, effect: Dictionary) -> void:
	match str(effect.get("type", "")):
		"armor":
			check(effect.has("value") and float(effect.value) > 0.0 and float(effect.value) <= 0.95, id + " uses supported fractional armor value")
		"thorns", "lifesteal":
			check(effect.has("percent") and float(effect.percent) > 0.0 and float(effect.percent) <= 1.0, id + " uses supported fractional percent")
		"poison":
			check(int(effect.get("damage", 0)) > 0 and int(effect.get("turns", 0)) > 0, id + " defines poison damage and duration")
		"random_damage":
			check(float(effect.get("min", -1)) >= 0 and float(effect.get("max", -1)) >= float(effect.get("min", 0)), id + " has an ordered random-damage range")
		"cleave":
			check(is_equal_approx(float(effect.get("side_damage", 0)), 0.5), id + " describes the existing half-damage cleave")
		"neighbor_heal", "curse":
			check(int(effect.get("value", 0)) > 0, id + " has a supported effect value")


func _contains_id(cards: Array[Dictionary], id: String) -> bool:
	return cards.any(func(data: Dictionary): return str(data.get("id", "")) == id)


func _check_rewards() -> void:
	var eligible := CardDatabase._get_eligible_rewards()
	var original_catalog: Array[Dictionary] = CardDatabase.cards
	var original_weights: Dictionary = CardDatabase._current_pack_weights.duplicate()
	for id in all_ids:
		check(_contains_id(eligible, id), id + " belongs to the regular reward pool")
		if not CardDatabase.has_card(id):
			continue
		var data := CardDatabase.get_card(id)
		var rarity := str(data.rarity)
		# A one-card eligible catalog makes each actual random API deterministic;
		# no probabilistic retry loop or assumptions about drop frequencies.
		var single_card: Array[Dictionary] = [data]
		CardDatabase.cards = single_card
		CardDatabase.set_pack_rarity_weights({rarity: 1.0})
		check(str(CardDatabase.get_random_card().get("id", "")) == id, id + " can be drawn by normal rewards")
		check(str(CardDatabase.get_random_card_by_rarity(rarity).get("id", "")) == id, id + " can be drawn by fixed-rarity rewards")
		var pending: Array[String] = [id]
		check(str(CardDatabase.get_random_card_for_current_pack(pending).get("id", "")) == id, id + " can be drawn repeatedly within a pack")
	CardDatabase.cards = original_catalog
	CardDatabase.set_pack_rarity_weights(original_weights)


func _check_collection_deck_and_network() -> void:
	var saved_identities: Dictionary = {}
	for id in all_ids:
		if not CardDatabase.has_card(id):
			continue
		var instance := CollectionManager.add_card(id)
		check(not instance.is_empty() and CollectionManager.get_amount(id) == 1, id + " can be awarded into the existing collection")
		saved_identities[id] = str(instance.get("instance_id", ""))
		var display := CollectionManager.get_display_card(id)
		check(str(display.get("id", "")) == id and str(display.get("instance_id", "")) == saved_identities[id], id + " has normal collection display data and persistent identity")
		check(DeckManager.add_card(id), id + " can be added to a combat deck")
		var deck := DeckManager.get_deck_card_data()
		check(deck.size() == 1 and str(deck[0].get("id", "")) == id, id + " reaches actual battle deck data")
		if not deck.is_empty():
			var remote: Dictionary = NetworkManager._sanitize_remote_card(deck[0])
			check(str(remote.get("id", "")) == id and str(remote.get("image", "")) == PLACEHOLDER, id + " survives remote card sanitization with canonical artwork")
			check(int(remote.get("attack", 0)) == int(deck[0].attack) and int(remote.get("defense", 0)) == int(deck[0].defense), id + " retains combat stats during network reconstruction")
			var local_effects: Array = deck[0].get("effects", [])
			var remote_effects: Array = remote.get("effects", [])
			check(local_effects.size() == remote_effects.size(), id + " retains its implemented effects over the network")
			for index in range(mini(local_effects.size(), remote_effects.size())):
				# Presentation-only overrides need not be trusted from a remote peer.
				for field: String in ["type", "percent", "damage", "turns", "value", "min", "max", "side_damage"]:
					if local_effects[index].has(field):
						check(remote_effects[index].get(field) == local_effects[index][field], id + " preserves effect parameter " + field)
		check(DeckManager.remove_card(id), id + " can leave the deck without losing ownership")
	CollectionManager.save_collection()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	check(CollectionManager.get_amount("corpse") == 2 and CollectionManager.collection.get("metadata", {}).get("test_sentinel") == "legacy profile", "Adding the new cards preserves legacy ownership and unrelated save metadata")
	for id in saved_identities:
		var copies := CollectionManager.get_instances_for_card(id)
		check(copies.size() == 1 and str(copies[0].get("instance_id", "")) == saved_identities[id], id + " ownership and identity survive save/load")
		check(DeckManager.can_add_card(id), id + " remains deck-eligible after reloading the collection")


func _check_rendered_collection() -> void:
	var screen := (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	add_child(screen)
	await get_tree().create_timer(0.15).timeout
	var cards_by_id: Dictionary = {}
	for child in screen.cards_root.get_children():
		if child is Card3D:
			cards_by_id[str(child.card_data.get("id", ""))] = child
	var texture := load(PLACEHOLDER) as Texture2D
	for id in all_ids:
		check(cards_by_id.has(id), id + " appears in the actual CollectionScreen")
		if not cards_by_id.has(id):
			continue
		var card: Card3D = cards_by_id[id]
		var data := CardDatabase.get_card(id)
		check(not card._animated_image and card._frame_count == 1, id + " uses the existing static image path")
		check(card._card_material != null and card._card_material.albedo_texture == texture, id + " displays the shared placeholder texture")
		check(card._card_material.uv1_scale == Vector3.ONE and card._card_material.uv1_offset == Vector3.ZERO, id + " uses the entire static texture")
		check(card.attack_label.visible and card.defense_label.visible and card.get_node("AttackTitle").visible and card.get_node("DefenseTitle").visible, id + " shows combat stat labels")
		check(card.attack_label.text == str(int(data.attack)) and card.defense_label.text == str(int(data.defense)) and card.current_hp == int(data.defense), id + " prints its actual attack and HP")
		check(card.rarity_label.text == str(data.rarity).to_upper(), id + " shows the normal rarity badge")
	if cards_by_id.has("rat"):
		var reused: Card3D = cards_by_id.rat
		reused.setup(CardDatabase.get_card("harald"))
		reused.setup(CardDatabase.get_card("rat"))
		check(not reused._animated_image and reused._card_material.uv1_scale == Vector3.ONE and reused._card_material.uv1_offset == Vector3.ZERO, "Reusing an animated card node resets to a complete static placeholder")
		reused.setup(CardDatabase.get_card("lucky_coin"))
		reused.setup(CardDatabase.get_card("rat"))
		check(reused.attack_label.visible and reused.defense_label.visible and reused.rarity_label.text == "COMMON", "Reusing a special card node restores ordinary combat stats and rarity")
	screen.queue_free()
	await get_tree().process_frame


func _effect_card(id: String) -> Card3D:
	var card := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(card)
	card.setup(CardDatabase.get_card(id))
	return card


func _check_effect_execution() -> void:
	# Exercise production combat helpers with the new card data, not copied
	# formulas. The existing table tests cover effect routing and animations.
	for entry: Array in [["plastic_chair", 10], ["sewer_worker", 10], ["bouncer", 35]]:
		var armor := CardData.get_effect(CardDatabase.get_card(str(entry[0])), "armor")
		var expected_title := "Armor %d%%" % int(entry[1])
		var expected_description := "Reduces regular incoming damage by %d%% (rounded)." % int(entry[1])
		var local_presentation := EffectPresentation.build(armor)
		var remote_presentation := EffectPresentation.build(NetworkManager._sanitize_remote_effect(armor))
		check(str(local_presentation.title) == expected_title and str(local_presentation.description) == expected_description, str(entry[0]) + " locally describes its actual armor percentage")
		check(str(remote_presentation.title) == expected_title and str(remote_presentation.description) == expected_description, str(entry[0]) + " reconstructs accurate armor text after network metadata sanitization")
	for entry: Array in [["plastic_chair", 5, 5], ["sewer_worker", 5, 5], ["security_guard", 6, 5], ["bouncer", 5, 3]]:
		var defender := _effect_card(str(entry[0]))
		var hp_before := defender.current_hp
		var hit := CombatResolver.apply_incoming_damage(defender, int(entry[1]))
		check(int(hit.damage) == int(entry[2]) and defender.current_hp == hp_before - int(entry[2]), str(entry[0]) + " uses actual rounded armor mitigation")
		defender.queue_free()
	for entry: Array in [["crab", 3], ["cactus_dealer", 4]]:
		var defender := _effect_card(str(entry[0]))
		var attacker := _effect_card("shopping_cart")
		var hp_before := attacker.current_hp
		CombatResolver.apply_thorns(defender, attacker, 20)
		check(attacker.current_hp == hp_before - int(entry[1]), str(entry[0]) + " reflects its configured thorns damage")
		defender.queue_free()
		attacker.queue_free()
	var cat := _effect_card("stray_cat")
	cat.take_damage(3)
	check(CombatResolver.heal_from_lifesteal(cat, 10) == 1 and cat.current_hp == 3, "Stray Cat restores one HP from ten damage at 10% lifesteal")
	check(CombatResolver.heal_from_lifesteal(cat, 2) == 0 and cat.current_hp == 3, "Small lifesteal amounts keep the existing whole-HP rounding")
	cat.queue_free()
	for entry: Array in [["drunk_guy", 4, 12], ["trash_monster", 5, 8]]:
		var card := _effect_card(str(entry[0]))
		var within_bounds := true
		for index in range(32):
			var damage := CombatResolver.get_attack_damage(card)
			within_bounds = within_bounds and damage >= int(entry[1]) and damage <= int(entry[2])
		check(within_bounds, str(entry[0]) + " rolls damage within its configured rounded range")
		card.queue_free()
	var king := _effect_card("rat_king")
	check(CombatResolver.get_attack_damage(king, 1) == 3 and CombatResolver.get_attack_damage(king, 3) == 9 and CombatResolver.get_attack_damage(king, 5) == 15, "Rat King uses the existing identical-card multiplier with restrained base attack")
	king.queue_free()
	var rat := _effect_card("rat")
	check(CombatResolver.get_attack_damage(rat, 5) == 2, "The related Rat remains independent and gains no implicit swarm/evolution")
	rat.queue_free()
	var cultist := _effect_card("cultist")
	var first_death := CombatResolver.apply_incoming_damage(cultist, 99)
	check(not first_death.died and str(first_death.survival_effect) == "grave_return" and cultist.current_hp == 7, "Cultist returns once at the existing rounded half health")
	var second_death := CombatResolver.apply_incoming_damage(cultist, 99)
	check(second_death.died and cultist.current_hp == 0, "Cultist cannot repeat grave return without a new card instance")
	cultist.queue_free()
	var victim := _effect_card("shopping_cart")
	victim.apply_curse(int(CardData.get_effect(CardDatabase.get_card("pickpocket"), "curse").get("value", 0)))
	check(victim.attack_value == 1 and victim.attack_label.text == "1", "Pickpocket's curse value uses the existing stat-reduction method")
	victim.queue_free()
	for entry: Array in [["moldy_bread", 1], ["rabid_dog", 2]]:
		var poison := CardData.get_effect(CardDatabase.get_card(str(entry[0])), "poison")
		check(int(poison.get("damage", 0)) == int(entry[1]) and int(poison.get("turns", 0)) == 2, str(entry[0]) + " carries supported two-turn poison parameters")
	for id: String in ["paramedic", "repair_bot"]:
		check(int(CardData.get_effect(CardDatabase.get_card(id), "neighbor_heal").get("value", 0)) == 1, id + " uses one HP of existing neighbor healing")
