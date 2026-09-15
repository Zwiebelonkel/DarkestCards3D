extends Node

const LEGACY := {"type": "deck_burn", "amount": 4, "name": "Deck Burn", "description": "Legacy deck removal"}
const MAILMAN := {"type": "draw_on_kill"}
const POISON := {"type": "poison", "damage": 3, "turns": 2}
const REGEN := {"type": "regeneration", "value": 3}
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(CardUpgradeManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run deck_burn_migration_test through the isolated match-feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	_check_normalization()
	_check_catalog()
	_check_collection()
	_check_upgrades()
	_check_network()
	print("DECK_BURN_MIGRATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_normalization() -> void:
	var legacy := LEGACY.duplicate(true)
	check(CardData.normalize_effect(legacy) == MAILMAN and legacy == LEGACY, "legacy effect becomes only canonical Mailman without mutating its source")
	var poison := POISON.duplicate(true)
	var normalized := CardData.normalize_effect(poison)
	normalized["damage"] = 99
	check(poison == POISON, "unrelated effect parameters retain independent copies")
	check(CardData._limit_effects([LEGACY, MAILMAN, POISON]) == [MAILMAN, POISON], "alias duplicates collapse before the two-effect limit so poison is retained")
	check(CardData._limit_effects([POISON, POISON, REGEN]) == [POISON, POISON], "migration preserves existing duplicate semantics for unrelated effects and the two-effect limit")
	check(CardData.get_active_effects({"effects": [LEGACY]}) == [MAILMAN] and not CardData.has_effect({"effects": [LEGACY]}, "deck_burn"), "combat readers expose only the replacement effect for old cards")
	var instance := CardData.create_instance("corpse", 7, [LEGACY, {"type":"lava"}, POISON], true)
	check(instance["effects"] == [MAILMAN, POISON] and instance["level"] == 7 and instance["is_holo"] == true and not str(instance["instance_id"]).is_empty(), "new instance boundary migrates effects while preserving level/Holo and filtering non-innate Lava")
	var input := {"card_id":"mailman", "instance_id":"merged-old-copy", "level":4, "is_holo":true, "effects":[LEGACY, POISON]}
	var before := input.duplicate(true)
	var merged := CardData.merge_card_and_instance(CardDatabase.get_card("mailman"), input)
	check(CardData.get_active_effects(merged) == [MAILMAN, POISON] and merged["effects"] == merged["active_effects"], "innate Mailman and migrated instance effect merge once while retaining the second distinct effect")
	check(input == before and merged["instance_id"] == "merged-old-copy" and merged["level"] == 4 and CardData.is_holo(merged), "merge preserves exact copy metadata without rewriting preview inputs")
	var lava_card := CardData.merge_card_and_instance(CardDatabase.get_card("piss"), {"effects":[LEGACY, {"type":"lava"}]})
	check(CardData.has_effect(lava_card, "lava") and CardData.has_effect(lava_card, "draw_on_kill") and CardData.get_active_effects(lava_card).size() == 2, "innate Lava survives while the instance contributes only the migrated Mailman")
	check(CardData.get_active_effects({"category":"special", "effects":[LEGACY]}).is_empty(), "migration cannot turn a special card into a combat-effect carrier")


func _check_catalog() -> void:
	check(EffectDatabase.get_effect("deck_burn").is_empty() and not EffectDatabase.get_effect("draw_on_kill").is_empty(), "retired effect is no longer retrievable and canonical Mailman remains catalogued")
	check(EffectDatabase.get_all_effects().all(func(effect: Dictionary): return str(effect.get("type", "")) != "deck_burn"), "complete effect catalog contains no retired entry")
	check(EffectDatabase.get_rollable_effects().all(func(effect: Dictionary): return str(effect.get("type", "")) not in ["deck_burn", "lava"]), "random pool contains neither retired effect nor innate-only Lava")
	var original := EffectDatabase.effects.duplicate(true)
	EffectDatabase.effects.assign([LEGACY, MAILMAN, POISON])
	check(EffectDatabase.get_rollable_effects() == [MAILMAN, POISON], "an old in-memory pool is normalized without double-weighting Mailman")
	EffectDatabase.effects.assign([LEGACY])
	check(EffectDatabase.get_random_effect_weighted() == MAILMAN, "even the weighted single-entry fallback cannot return the retired effect")
	EffectDatabase.effects = original


func _check_collection() -> void:
	var old_instance := {"card_id":"corpse", "instance_id":"saved-holo-copy", "level":7, "is_holo":true, "effects":[LEGACY, {"type":"lava"}, POISON], "active_effects":[LEGACY, MAILMAN, POISON]}
	var legacy_collection := {"cards":{"corpse":1}, "instances":[old_instance], "metadata":{"slot_room_unlocked":true, "jester_offering":{"offered":["chick","harald"], "completed":true, "reward_instance":old_instance.duplicate(true)}}}
	var file := FileAccess.open(CollectionManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_collection))
	file.close()
	var disk_before := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	CollectionManager.load_collection()
	var loaded: Dictionary = CollectionManager.get_card_instances()[0]
	# JSON numeric values load as floats; compare against the same save format.
	var saved_effects: Array = JSON.parse_string(JSON.stringify([MAILMAN, POISON]))
	check(loaded["effects"] == saved_effects and loaded["active_effects"] == saved_effects, "collection reload normalizes both persisted effect fields and keeps Lava excluded")
	check(loaded["instance_id"] == "saved-holo-copy" and loaded["level"] == 7 and loaded["is_holo"] == true and CollectionManager.get_amount("corpse") == 1, "collection migration preserves ownership count and exact Holo instance identity")
	check(CollectionManager.is_slot_room_unlocked() and CollectionManager.get_jester_offering_state()["completed"] and CollectionManager.get_jester_offering_state()["reward_instance"]["effects"] == saved_effects, "unrelated unlock metadata survives and a stored offering reward mirror is normalized too")
	check(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == disk_before, "reading and previewing an old collection performs no migration-only disk write")
	check(CollectionManager.save_collection(), "normal collection save persists the migrated profile")
	check(not FileAccess.get_file_as_string(CollectionManager.SAVE_PATH).contains("deck_burn"), "normal save removes legacy aliases from owned copies and reward metadata")
	CollectionManager.reload_profile()
	check(CollectionManager.get_card_instances()[0]["effects"] == saved_effects and CollectionManager.get_card_instances()[0]["instance_id"] == "saved-holo-copy", "migrated collection survives another save/load without changing its copy")
	var incoming := {"card_id":"corpse", "instance_id":"incoming-old-copy", "level":2, "is_holo":false, "effects":[LEGACY, POISON]}
	var stored := CollectionManager.add_card_instance(incoming)
	check(stored["effects"] == [MAILMAN, POISON] and incoming["effects"] == [LEGACY, POISON] and stored["instance_id"] == incoming["instance_id"], "direct collection admission also migrates an old reward without modifying its caller")


func _check_upgrades() -> void:
	var cfg := ConfigFile.new()
	var effects_by_card := {"corpse":[LEGACY, MAILMAN, POISON], "piss":[LEGACY, {"type":"lava"}, REGEN], "haendler":[REGEN], "mailman":[LEGACY, POISON]}
	for card_id: String in effects_by_card:
		cfg.set_value(card_id, "attack_bonus", 4)
		cfg.set_value(card_id, "health_bonus", 3)
		cfg.set_value(card_id, "stat_upgrade_count", 11)
		cfg.set_value(card_id, "effect_roll_count", 7)
		cfg.set_value(card_id, "effects", effects_by_card[card_id])
		cfg.set_value(card_id, "removed_base_effect_indices", [0] if card_id in ["piss", "haendler"] else [])
	check(cfg.save(CardUpgradeManager.SAVE_PATH) == OK, "legacy upgrade fixture saves only in the isolated slot")
	var before := FileAccess.get_file_as_string(CardUpgradeManager.SAVE_PATH)
	CardUpgradeManager.load_upgrades()
	check(CardUpgradeManager.get_upgrade_effects("corpse") == [MAILMAN, POISON] and CardUpgradeManager.get_upgrade_effects("piss") == [MAILMAN, REGEN], "upgrade load migrates old effects before capacity checks and excludes bought Lava")
	check(CardUpgradeManager.get_upgrade_effects("mailman") == [POISON] and CardUpgradeManager.get_free_effect_slots("mailman") == 0, "an alias matching innate Mailman cannot displace its distinct purchased effect or consume an extra slot")
	check(CardUpgradeManager.get_stat_upgrade_count("corpse") == 11 and CardUpgradeManager.get_effect_roll_count("corpse") == 7 and CardUpgradeManager.get_attack_bonus("corpse") == 4 and CardUpgradeManager.get_health_bonus("corpse") == 3, "migration preserves stat purchases, effect-roll pricing and accumulated bonuses")
	var stale := CardData.merge_card_and_instance(CardDatabase.get_card("corpse"))
	var stale_before := stale.duplicate(true)
	var upgraded := CardUpgradeManager.apply_upgrades("corpse", stale)
	check(CardData.get_active_effects(upgraded) == [MAILMAN, POISON] and upgraded["active_effects"] == upgraded["effects"] and stale == stale_before, "apply_upgrades replaces stale preferred active_effects so bought effects remain usable without mutating input")
	var piss := CardUpgradeManager.apply_upgrades("piss", CardData.merge_card_and_instance(CardDatabase.get_card("piss")))
	check(CardData.get_active_effects(piss) == [MAILMAN, REGEN] and not CardData.has_effect(piss, "lava") and CardUpgradeManager.upgrades["piss"]["removed_base_effect_indices"] == [0], "preferred active_effects cannot resurrect a removed innate Lava after upgrade migration")
	check(CardUpgradeManager.get_base_effects("haendler").is_empty() and CardData.get_active_effects(CardUpgradeManager.apply_upgrades("haendler", CardDatabase.get_card("haendler"))) == [REGEN], "an explicitly removed former innate effect remains removed after its authored replacement")
	check(FileAccess.get_file_as_string(CardUpgradeManager.SAVE_PATH) == before, "upgrade load and all pure previews avoid extra persistence writes")
	check(CardUpgradeManager.save_upgrades() and not FileAccess.get_file_as_string(CardUpgradeManager.SAVE_PATH).contains("deck_burn"), "normal upgrade save persists only canonical effects")
	CardUpgradeManager.load_upgrades()
	check(CardUpgradeManager.get_upgrade_effects("corpse") == [MAILMAN, POISON] and CardUpgradeManager.upgrades["piss"]["removed_base_effect_indices"] == [0] and CardUpgradeManager.get_effect_roll_count("piss") == 7, "canonical upgrade lists, removal indices and roll counters survive another reload")
	check(CardUpgradeManager.remove_effect_at("corpse", "upgrade", 0) and CardUpgradeManager.get_upgrade_effects("corpse") == [POISON], "visible upgraded-effect index removes the migrated Mailman rather than its neighbor")
	check(CardUpgradeManager.add_effect("corpse", LEGACY) and CardUpgradeManager.get_upgrade_effects("corpse") == [POISON, MAILMAN] and CardUpgradeManager.get_effect_roll_count("corpse") == 7, "legacy direct add migrates canonically while preserving independent roll progression")
	check(not CardUpgradeManager.add_effect("corpse", {"type":"lava"}), "normalizing a legacy type never opens the upgrade Lava boundary")


func _check_network() -> void:
	check(NetworkManager._sanitize_remote_effect({"type":"double_strike", "hits":99})["hits"] == 8 and NetworkManager._sanitize_remote_effect({"type":"triple_strike", "hits":0})["hits"] == 1, "network hit counts share the executable one-to-eight range")
	check(NetworkManager._sanitize_remote_effect(LEGACY) == MAILMAN, "remote legacy effect migrates before catalog validation and drops obsolete amount fields")
	var raw := {"card_id":"corpse", "instance_id":"remote-old-holo", "is_holo":true, "attack":7, "defense":12, "active_effects":[LEGACY, {"type":"lava"}, MAILMAN, POISON]}
	var before := raw.duplicate(true)
	var remote := NetworkManager._sanitize_remote_card(raw)
	check(remote["effects"] == [MAILMAN, POISON] and remote["active_effects"] == [MAILMAN, POISON] and remote["instance_id"] == "remote-old-holo" and remote["is_holo"] == true and raw == before, "remote card keeps exact identity/Holo and distinct effects while removing alias duplicates and illegal Lava")
	var second := raw.duplicate(true)
	second["instance_id"] = "remote-second-copy"
	var payload := NetworkManager._sanitize_remote_deck_payload({"deck":[raw, raw.duplicate(true), second], "starting_hand_slots":2, "starting_deck_indices":[0,2]})
	check(payload["deck"].size() == 2 and payload["starting_deck_indices"] == [0,1] and payload["deck"][1]["instance_id"] == "remote-second-copy", "payload migration preserves duplicate-instance rejection and remaps chosen starting copies")
	check(payload["deck"].all(func(card: Dictionary): return card["effects"] == [MAILMAN, POISON]), "all accepted network deck copies carry only canonical effects")
	var active_override := NetworkManager._sanitize_remote_card({"card_id":"corpse", "effects":[LEGACY], "active_effects":[POISON]})
	check(active_override["effects"] == [POISON], "an explicit authoritative active list remains authoritative instead of reviving an inactive legacy effect")
	var piss := NetworkManager._sanitize_remote_card({"card_id":"piss", "active_effects":[LEGACY, {"type":"lava", "amount":99}, MAILMAN]})
	check(piss["effects"] == [MAILMAN, CardData.get_effect(CardDatabase.get_card("piss"), "lava")], "only Pisse-Eimer retains its canonical innate Lava beside migrated Mailman")
	var removed := NetworkManager._sanitize_remote_card({"card_id":"piss", "active_effects":[LEGACY, POISON]})
	check(removed["effects"] == [MAILMAN, POISON] and not CardData.has_effect(removed, "lava"), "network normalization does not restore a deliberately removed innate Lava")
