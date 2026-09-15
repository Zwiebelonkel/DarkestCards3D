extends Node

const CONTENT := preload("res://scripts/ui/JournalContent.gd")
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	Localization.set_locale("de")
	var cards_before := CardDatabase.get_all_cards()
	var effects_before := EffectDatabase.get_all_effects()
	var collection_before := CollectionManager.collection.duplicate(true)
	var upgrades_before := CardUpgradeManager.upgrades.duplicate(true)
	var deck_before := DeckManager.battle_deck.duplicate()
	var deck_ids_before := DeckManager.deck_instance_ids.duplicate()
	var coins_before := GameCurrency.get_coin_cents()
	seed(442971)
	var next_random := randi()
	seed(442971)
	var chapters := CONTENT.build_chapters()
	check(randi() == next_random, "opening the journal does not change shared card or battle randomness")
	check(chapters.map(func(chapter: Dictionary) -> String: return str(chapter["id"])) == ["cards", "special_cards", "event_cards", "effects", "mechanics", "profile", "collection"], "all seven chapters use the agreed stable order and IDs")
	check(_chapter_entries(chapters, "profile").map(func(entry: Dictionary) -> String: return str(entry["id"])) == ["profile:overview", "profile:deck", "profile:collection"], "profile has three stable, separate subjects")
	check(_find(chapters, "cards").get("title") == Localization.text("KAMPFKARTEN") and _find(chapters, "special_cards").get("title") == Localization.text("SONDERKARTEN") and _find(chapters, "event_cards").get("title") == Localization.text("EVENT-KARTEN"), "combat, special and event chapters have separate localized titles")
	check(CollectionManager.collection == collection_before and CardUpgradeManager.upgrades == upgrades_before and DeckManager.battle_deck == deck_before and DeckManager.deck_instance_ids == deck_ids_before and GameCurrency.get_coin_cents() == coins_before, "catalog building never changes collection, upgrades, deck bindings or money")
	var entry_count := 0
	var maximum_body := 0
	var all_entry_ids := {}
	for chapter: Dictionary in chapters:
		var seen := {}
		var entries: Array = chapter["entries"]
		check(not entries.is_empty() and not str(chapter["title"]).is_empty(), "chapter has a title and content: " + str(chapter["id"]))
		for entry: Dictionary in entries:
			entry_count += 1
			var id := str(entry.get("id", ""))
			check(not id.is_empty() and not seen.has(id) and not str(entry.get("title", "")).is_empty() and not str(entry.get("subtitle", "")).is_empty() and not str(entry.get("body", "")).is_empty(), "entry has unique identity and readable content: " + id)
			check(not all_entry_ids.has(id), "entry appears in exactly one journal chapter: " + id)
			seen[id] = true
			all_entry_ids[id] = true
			maximum_body = maxi(maximum_body, str(entry["body"]).length())
	var card_entries := _chapter_entries(chapters, "cards")
	var special_entries := _chapter_entries(chapters, "special_cards")
	var event_entries := _chapter_entries(chapters, "event_cards")
	var collection_entries := _chapter_entries(chapters, "collection")
	check(collection_entries.size() == cards_before.size(), "collection reserves slots for collectible combat and special cards only")
	for source: Dictionary in card_entries + special_entries:
		var preview := _find(collection_entries, "collection:" + str(source["id"]))
		check(not preview.is_empty() and preview.get("card_data", {}) == source["card_data"], "collection includes authored card data for " + str(source["id"]))
	check(card_entries.size() + special_entries.size() == cards_before.size() and event_entries.size() == EventDeck.definitions().size(), "collectibles and every event definition appear in their separate chapters without ownership filtering")
	check(special_entries.size() == 25, "all 25 current special cards appear in the separate special chapter")
	for card: Dictionary in cards_before:
		var is_special := str(card.get("category", "combat")).to_lower() == "special"
		var entry_id := "card:" + str(card["id"])
		var entry := _find(special_entries if is_special else card_entries, entry_id)
		check(not entry.is_empty() and entry.get("card_data", {}) == card and entry.get("title") == Localization.text(str(card.get("name"))), "card page localizes its authored title and preserves base data: " + str(card["id"]))
		check(_find(card_entries if is_special else special_entries, entry_id).is_empty(), "card is excluded from the other card chapter: " + str(card["id"]))
	for event: Dictionary in EventDeck.definitions():
		var entry := _find(event_entries, "event:" + str(event["id"]))
		check(not entry.is_empty() and entry.get("card_data", {}) == event and str(entry.get("subtitle", "")).contains(Localization.text(" · Ereigniskarte · nur im Kampf")), "match-only event is documented: " + str(event["id"]))
		check(_find(card_entries + special_entries, "event:" + str(event["id"])).is_empty() and _find(collection_entries, "collection:event:" + str(event["id"])).is_empty(), "event is absent from combat, special and collection chapters: " + str(event["id"]))
		check(str(entry.get("body", "")).contains(Localization.text(CONTENT.EVENT_AVAILABILITY)), "event page explains universal unlocks without packs or collection ownership: " + str(event["id"]))
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		var localized := CONTENT.build_chapters()
		check(_is_card_ordered(_chapter_entries(localized, "cards")), "combat cards are alphabetized by localized title in " + locale)
		check(_is_card_ordered(_chapter_entries(localized, "special_cards")), "special cards are alphabetized by localized title in " + locale)
		check(_is_card_ordered(_chapter_entries(localized, "event_cards")) and _chapter_entries(localized, "event_cards").size() == EventDeck.definitions().size(), "all event cards are available and alphabetized by localized title in " + locale)
		check(_chapter_entries(localized, "collection").map(func(entry: Dictionary): return entry["id"]) == collection_entries.map(func(entry: Dictionary): return entry["id"]), "collection slots remain in the same fixed order across locales: " + locale)
		check(str(_find(_chapter_entries(localized, "cards"), "card:eg")["body"]).contains(Localization.text(CONTENT.EGG_RULE)) and str(_find(_chapter_entries(localized, "cards"), "card:chick")["body"]).contains(Localization.text(CONTENT.CHICK_RULE)), "Egg and Chick explain their shared localized transformation rules: " + locale)
		check(str(_find(_chapter_entries(localized, "cards"), "card:eg")["body"]).contains("25") and str(_find(_chapter_entries(localized, "mechanics"), "replacements")["body"]).contains("25"), "Egg card and replacement mechanics both state the 25-percent hatch chance: " + locale)
		var chance_effect := {"type": "stun", "chance": 0.37}
		check(CONTENT.effect_description(chance_effect).contains("37%") and EffectPresentation.get_description(chance_effect) == CONTENT.effect_description(chance_effect, true), "journal and card display share the actual localized chance in " + locale)
		check(CONTENT.effect_description({"type": "cleave", "side_damage": 0.2}).contains("20%") and _chapter_entries(localized, "effects").all(func(entry: Dictionary): return str(entry.get("effect_data", {}).get("type", "")) != "deck_burn"), "localized catalog retains parameter values and excludes the retired effect in " + locale)
		for hint_id: String in ["secret_room", "secret_graveyard", "area_keys"]:
			check(_find(_chapter_entries(localized, "mechanics"), hint_id).is_empty(), "journal omits room access and discovery hints in " + locale + ": " + hint_id)
		var secret_page := _find(_chapter_entries(localized, "mechanics"), "secret_rarity")
		check(not str(secret_page.get("body", "")).contains("%"), "Secret discovery page promises no random pack probability in " + locale)
		for pack_id: String in PackDefinition.PACK_TYPES:
			var pack_page := _find(_chapter_entries(localized, "mechanics"), "pack:" + pack_id)
			var rates := str(pack_page["body"]).split("\n\n")[1]
			check(not rates.contains(CONTENT.rarity_name("secret")), "pack rates exclude discovery-only Secret cards in " + locale + ": " + pack_id)
			var rate_pattern := RegEx.new()
			rate_pattern.compile("[0-9]+(?:[.,][0-9]+)?")
			var rate_total := 0.0
			for match_result in rate_pattern.search_all(rates):
				rate_total += match_result.get_string().replace(",", ".").to_float()
			check(is_equal_approx(rate_total, 100.0), "displayed baseline pack rates total 100 in " + locale + ": " + pack_id)
		for key_id: String in ["slot_room_key", "graveyard_key", "basement_key", "black_market_access"]:
			var key_card := CardDatabase.get_card(key_id)
			var expected_paragraphs: Array[String] = [Localization.text(str(key_card["description"]))]
			if not str(key_card.get("flavor_text", "")).is_empty():
				expected_paragraphs.append(Localization.text(str(key_card["flavor_text"])))
			var key_page := _find(_chapter_entries(localized, "special_cards"), "card:" + key_id)
			check(key_page.get("body") == "\n\n".join(expected_paragraphs), "key card retains only its normal card text without appended discovery or navigation tips in " + locale + ": " + key_id)
	Localization.set_locale("de")
	var egg_body := str(_find(card_entries, "card:eg")["body"])
	var chick_body := str(_find(card_entries, "card:chick")["body"])
	var chicken_body := str(_find(card_entries, "card:chicken")["body"])
	check(egg_body.contains(Localization.text("Chick")) and egg_body.contains("25 %") and egg_body.contains("sonst wird normal nachgezogen") and egg_body.contains("fünf volle Runden") and egg_body.contains("keine Karte nachgezogen oder zur Sammlung hinzugefügt"), "Egg describes its 25-percent battle-only hatch, ordinary replacement on failure and growth after five rounds")
	check(chick_body.contains("fünf vollständig") and chick_body.contains("je einen Zug beider Seiten") and chick_body.contains("bereits laufender Zug zählt nicht") and chick_body.contains("auch ein regulär gezogenes Küken"), "Chick page explains full-round timing and ordinary drawn Chicks")
	check(chick_body.contains("Im Nachziehstapel pausiert") and chick_body.contains("erhält den bisherigen Fortschritt") and chick_body.contains("kein Tod") and chick_body.contains("keine Kill-Effekte"), "Chick growth pauses in the pile and survives Steel without being a death or kill")
	check(chick_body.contains("frischen Grundwerten und Grundeffekten, ohne Upgrades, Holo oder übernommene Zustände") and chicken_body.contains("ersetzt das Küken") and chicken_body.contains("fünf volle Runden") and chicken_body.contains("nur zum laufenden Kampf"), "Chick and Chicken pages document the fresh base transformation in the current battle")
	var effect_entries := _chapter_entries(chapters, "effects")
	check(effect_entries.size() >= effects_before.size(), "effect chapter includes all database variants, not only unique effect types")
	for index in range(effects_before.size()):
		var source: Dictionary = effects_before[index]
		var entry := _find(effect_entries, "effect:catalog:%d:%s" % [index, source["type"]])
		check(not entry.is_empty() and entry.get("effect_data", {}) == EffectPresentation.resolve_defaults(source) and ResourceLoader.exists(str(entry.get("icon_path", ""))), "effect variant retains values and a loadable icon: " + str(source["name"]))
	check(_has_effect(effect_entries, "lifesteal", "percent", 1.0) and _has_effect(effect_entries, "neighbor_heal", "value", 1.0), "card-only lifesteal and neighbor-heal value variants are included")
	var guard_description := CONTENT.effect_description({"type": "bodyguard", "percent": 0.4})
	check(guard_description.contains("40%") and guard_description.contains("linke Vorrang") and guard_description.contains("vor der Aufteilung") and guard_description.contains("nicht erneut geteilt"), "Bodyguard explains actual raw-damage sharing, left priority, shield gate and nonrecursive routing")
	var legacy_effect := {"type": "deck_burn", "name": "Deck Burn", "amount": 8}
	var mailman_effect := {"type": "draw_on_kill"}
	check(CONTENT.effect_description(legacy_effect) == CONTENT.effect_description(mailman_effect) and EffectPresentation.get_title(legacy_effect) == EffectPresentation.get_title(mailman_effect) and EffectPresentation.get_icon_path(legacy_effect) == EffectPresentation.get_icon_path(mailman_effect), "legacy presentation uses the canonical Mailman title, icon and executable rules")
	check(CONTENT.effect_description({"type": "neighbor_heal", "value": 7}) == Localization.format_text("Heilt zu Beginn des eigenen Zuges die direkt links und rechts benachbarten eigenen Karten um %d HP, höchstens bis zu deren maximalen HP.", [7]), "neighbor heal uses real turn-start timing and the supplied value")
	check(CONTENT.effect_description({"type": "swarm_power"}).contains("beiden Tischseiten"), "swarm rule includes identical opposing copies")
	check(CONTENT.effect_description({"type": "stun", "chance": 0.5}).contains("50% Chance") and CONTENT.effect_description({"type": "cleave", "side_damage": 0.2}).contains("20%"), "effect explanations use supplied stun chance and Cleave fraction")
	check(CONTENT.effect_description({"type": "armor"}).contains("25%") and CONTENT.effect_description({"type": "lifesteal"}).contains("20%") and CONTENT.effect_description({"type": "lifesteal"}).contains("einschließlich Rundumschlag"), "display defaults match armor and lifesteal and include Cleave in the final heal")
	check(CONTENT.effect_description({"type": "triple_strike", "hits": 99}).contains("8 Treffer") and CONTENT.effect_description({"type": "double_strike", "hits": 0}).contains("1 Treffer") and EffectPresentation.get_value_badge({"type": "triple_strike", "hits": 99}).begins_with("8"), "hit descriptions and badges match the executable one-to-eight clamp")
	check(CONTENT.effect_description({"type": "poison"}).contains("nur nach tatsächlichem Trefferschaden") and CONTENT.effect_description({"type": "poison"}).contains("Grabesrückkehr können retten"), "poison requires real hit damage while survival effects protect against ticks")
	check(CONTENT.effect_description({"type": "execute"}).contains("bereits einen Überlebensschutz") and CONTENT.effect_description({"type": "shield_first_hit"}).contains("weder Gift noch Hinrichtung"), "Execute cannot bypass a shield or reuse a death save in the same hit")
	check(CONTENT.effect_description({"type": "last_stand"}).contains("auch Gift, Dornen und Hinrichtung") and CONTENT.effect_description({"type": "grave_return"}).contains("auch Gift, Dornen und Hinrichtung") and CONTENT.effect_description({"type": "chain_attack"}).contains("Rundumschlag-Treffer"), "survival and chain descriptions include newly supported damage paths")
	var mechanics := _chapter_entries(chapters, "mechanics")
	check(str(_find(mechanics, "egg_chicken")["body"]).contains(Localization.text(CONTENT.EGG_RULE)) and str(_find(mechanics, "egg_chicken")["body"]).contains(Localization.text(CONTENT.CHICK_RULE)), "mechanics describe both Egg-to-Chick and Chick-to-Chicken steps")
	check(str(_find(mechanics, "replacements")["body"]).contains("25 % Wahrscheinlichkeit ein Küken") and str(_find(mechanics, "holo")["body"]).contains("Geschlüpfte Küken und durch Wachstum entstandene Hühner erhalten weder Holo noch einen Holo-Wurf"), "replacement and Holo rules agree with the probabilistic life cycle")
	check(str(_find(mechanics, "event_steel")["body"]).contains("Wachstumsfortschritt") and str(_find(event_entries, "event:steel")["body"]).contains("im Nachziehstapel pausiert"), "both Steel pages preserve Chick growth progress while off the table")
	check(str(_find(mechanics, "events")["body"]).contains(Localization.text(CONTENT.EVENT_AVAILABILITY)) and str(_find(mechanics, "events")["body"]).contains(Localization.format_text("Jeder Spieler erhält zu Beginn jedes Matches %d zufällige Ereigniskarten, die bereits vor seinem ersten Angriff spielbar sind.", [EventDeck.STARTING_HAND_SIZE])), "event rules distinguish universal unlocks from the existing random match starting hand")
	for id: String in ["combat", "replacements", "egg_chicken", "collection_deck", "starting_hand", "active_effects", "turn_start", "events", "event_steel", "event_choices", "rarities", "pack:basic", "pack:ultra", "pack:god", "pack_quantity", "match_rewards", "player_levels", "clicker", "type_upgrades", "effect_upgrades", "holo", "forge", "forge_protection", "slot_bets", "slot_payouts"]:
		check(not _find(mechanics, id).is_empty(), "requested gameplay topic is covered: " + id)
	var god_pack: Dictionary = PackDefinition.PACK_TYPES["god"]
	check(str(_find(mechanics, "pack:god")["subtitle"]) == Localization.format_text("%d Soul Coins · %d Karten · ab Level %d", [int(god_pack["cost"]), int(god_pack["card_count"]), int(god_pack["minimum_level"])]), "GOD pack page carries its localized current price and unlock level")
	check(str(_find(mechanics, "slot_bets")["body"]).contains("1, 2, 5, 10, 20, 50") and str(_find(mechanics, "slot_payouts")["body"]).contains("×50"), "slot pages derive actual stakes and highest payout")
	check(str(_find(mechanics, "effect_upgrades")["body"]).contains("ohne Effekt enden") and str(_find(mechanics, "forge_protection")["body"]).contains("Kampfdeck"), "journal explains paid failed rolls and protected fusion inputs")
	for id: String in ["permanent_upgrades", "lucky_rewards", "income_boosts"]:
		check(not _find(mechanics, id).is_empty(), "new permanent progression topic is documented: " + id)
	check(str(_find(special_entries, "card:lucky_coin")["body"]).contains(Localization.text(str(CardDatabase.get_card("lucky_coin")["flavor_text"]))) and str(_find(special_entries, "card:lucky_coin")["subtitle"]).contains(Localization.text(" · dauerhaft")), "permanent card page preserves localized authored flavor and labels permanence")
	check(str(_find(mechanics, "forge")["subtitle"]).contains("5 / 4 / 3") and not str(_find(mechanics, "forge_protection")["body"]).contains("alle fünf"), "forge documents all three configured costs without a fixed-count rollback promise")
	check(str(_find(mechanics, "income_boosts")["body"]).contains("+2% / +5% / +10% / +15%"), "journal documents configured highest-tier progression")
	# Permanent upgrade descriptions are a read-only catalog, even when the
	# player's owned upgrade tiers differ or balancing data changes later.
	CollectionManager.collection = {"cards": {"lucky_coin": 1, "dealer_license": 1, "golden_clicker": 3, "clicker": 1, "fusion_upgrade_1": 1, "fusion_upgrade_2": 1, "graveyard_key": 1}, "instances": []}
	check(CONTENT.build_chapters().slice(0, 4) == chapters.slice(0, 4), "the four static catalog chapters remain independent of permanent upgrade ownership")
	check(_chapter_entries(CONTENT.build_chapters(), "collection") == collection_entries, "collection grid remains the complete base catalog when owned permanent upgrades change")
	var original_cheat_rarities := CardDatabase._cheat_reward_rarities.duplicate()
	CardDatabase.set_cheat_reward_rarities(["rare"])
	var filtered_mechanics := _chapter_entries(CONTENT.build_chapters(), "mechanics")
	for pack_id: String in PackDefinition.PACK_TYPES:
		check(_find(filtered_mechanics, "pack:" + pack_id) == _find(mechanics, "pack:" + pack_id), "baseline pack article ignores unlock ownership, luck and developer rarity filters: " + pack_id)
	CardDatabase.set_cheat_reward_rarities(original_cheat_rarities)
	CollectionManager.collection = collection_before
	var golden_modifiers: Dictionary = CardDatabase.get_card("golden_clicker")["upgrade_modifiers"]
	var golden_bonus: float = float(golden_modifiers["manual_click_bonus"])
	golden_modifiers["manual_click_bonus"] = 0.07
	check(str(_find(_chapter_entries(CONTENT.build_chapters(), "mechanics"), "clicker")["body"]).contains("0,07"), "clicker mechanics derive future balance values directly from card configuration")
	golden_modifiers["manual_click_bonus"] = golden_bonus
	# Output belongs to the book. Changing a preview or body must not poison
	# later journal openings or mutate the underlying authoritative catalogs.
	(card_entries[0]["card_data"] as Dictionary)["name"] = "mutated preview"
	(special_entries[0]["card_data"] as Dictionary)["name"] = "mutated special preview"
	(effect_entries[0]["effect_data"] as Dictionary)["value"] = 1000
	(mechanics[0] as Dictionary)["body"] = "mutated body"
	var original_gallery_card: Dictionary = collection_entries[0]["card_data"].duplicate(true)
	(collection_entries[0]["card_data"] as Dictionary)["name"] = "mutated gallery preview"
	var original_gallery_id := str(collection_entries[0]["id"]).trim_prefix("collection:")
	check(_find(card_entries + special_entries, original_gallery_id).get("card_data", {}).get("name") != "mutated gallery preview" and _chapter_entries(CONTENT.build_chapters(), "collection")[0]["card_data"] == original_gallery_card, "collection previews own their data independently of article previews and later catalog builds")
	check(CardDatabase.get_all_cards() == cards_before and EffectDatabase.get_all_effects() == effects_before and str(_chapter_entries(CONTENT.build_chapters(), "mechanics")[0]["body"]) != "mutated body", "all combat/special/effect/page data is independent of catalog and later book openings")
	# Real catalog additions must appear automatically without editing journal
	# code, including a new effect type and an uncatalogued numeric variant.
	var future_effect := {"type": "journal_fixture", "name": "Future Effect", "rarity": "rare", "description": "A future authored effect.", "value": 7}
	EffectDatabase.effects.append(future_effect)
	EffectDatabase.effects_by_type["journal_fixture"] = [future_effect]
	var future_card := {"id": "journal_fixture", "name": "Future Card", "rarity": "rare", "attack": 3, "defense": 4, "effects": [{"type": "poison", "damage": 7, "turns": 2}], "description": "Future catalog entry."}
	CardDatabase.cards.append(future_card)
	CardDatabase.cards_by_id["journal_fixture"] = future_card
	# Deliberately append matching special titles in reverse ID order to
	# exercise the same stable tie-break used by both localized card lists.
	for suffix: String in ["b", "a"]:
		var future_special := {"id": "journal_fixture_special_" + suffix, "name": "Future Special", "category": "special", "rarity": "common", "attack": 0, "defense": 0, "effects": [], "description": "Future special catalog entry."}
		CardDatabase.cards.append(future_special)
		CardDatabase.cards_by_id[future_special["id"]] = future_special
	# Imported event data must not re-enter collectible chapters, including
	# a reserved match-event ID whose imported category is incorrectly combat.
	var imported_event: Dictionary = EventDeck.definitions()[0].duplicate(true)
	imported_event["category"] = "combat"
	var future_event := {"id": "journal_fixture_event", "name": "Future Event", "category": "event", "rarity": "common", "description": "Future event catalog entry."}
	for event: Dictionary in [imported_event, future_event]:
		CardDatabase.cards.append(event)
		CardDatabase.cards_by_id[event["id"]] = event
	var expanded := CONTENT.build_chapters()
	var expanded_cards := _chapter_entries(expanded, "cards")
	var expanded_specials := _chapter_entries(expanded, "special_cards")
	var expanded_effects := _chapter_entries(expanded, "effects")
	var expanded_collection := _chapter_entries(expanded, "collection")
	check(expanded_collection.size() == collection_entries.size() + 3 and not _find(expanded_collection, "collection:card:journal_fixture").is_empty() and not _find(expanded_collection, "collection:card:journal_fixture_special_a").is_empty() and not _find(expanded_collection, "collection:card:journal_fixture_special_b").is_empty(), "collection automatically includes newly authored combat and special cards")
	check(_chapter_entries(expanded, "event_cards") == event_entries and _find(expanded_cards + expanded_specials, "card:" + str(imported_event["id"])).is_empty() and _find(expanded_cards + expanded_specials, "card:journal_fixture_event").is_empty(), "imported events stay outside collectible chapters and do not duplicate the dedicated event definitions")
	check(_is_collection_ordered(expanded_collection), "collection slots sort from common to secret, then by stable card and entry IDs")
	check(not _find(expanded_cards, "card:journal_fixture").is_empty() and _find(expanded_specials, "card:journal_fixture").is_empty(), "new unowned combat cards appear only in their chapter automatically")
	check(expanded_specials.size() == special_entries.size() + 2 and not _find(expanded_specials, "card:journal_fixture_special_a").is_empty() and not _find(expanded_specials, "card:journal_fixture_special_b").is_empty(), "new unowned special definitions appear automatically without a maintained ID list")
	check(_find(expanded_cards, "card:journal_fixture_special_a").is_empty() and _find(expanded_cards, "card:journal_fixture_special_b").is_empty(), "new special definitions never leak into combat cards")
	check(_is_card_ordered(expanded_specials), "equal localized special titles use a stable ascending entry ID tie-break")
	check(_has_effect(expanded_effects, "journal_fixture", "value", 7.0) and _has_effect(expanded_effects, "poison", "damage", 7.0), "new catalog types and card-only numeric variants appear automatically")
	CardDatabase.cards = cards_before
	CardDatabase.cards_by_id.erase("journal_fixture")
	CardDatabase.cards_by_id.erase("journal_fixture_special_a")
	CardDatabase.cards_by_id.erase("journal_fixture_special_b")
	CardDatabase.cards_by_id.erase(str(imported_event["id"]))
	CardDatabase.cards_by_id.erase("journal_fixture_event")
	EffectDatabase.effects = effects_before
	EffectDatabase.effects_by_type.erase("journal_fixture")
	print("JOURNAL_CONTENT_ENTRIES: %d combat cards, %d special cards, %d event cards, %d effects, %d mechanics; %d total; longest body %d characters" % [card_entries.size(), special_entries.size(), event_entries.size(), effect_entries.size(), mechanics.size(), entry_count, maximum_body])
	print("JOURNAL_CONTENT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _find(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _chapter_entries(chapters: Array, id: String) -> Array:
	return _find(chapters, id).get("entries", [])


func _is_card_ordered(entries: Array) -> bool:
	for index in range(1, entries.size()):
		var previous: Dictionary = entries[index - 1]
		var current: Dictionary = entries[index]
		var comparison := str(previous["title"]).naturalnocasecmp_to(str(current["title"]))
		if comparison > 0 or (comparison == 0 and str(previous["id"]) > str(current["id"])):
			return false
	return true


func _is_collection_ordered(entries: Array) -> bool:
	var rarity_order := ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic", "secret"]
	for index in range(1, entries.size()):
		var previous: Dictionary = entries[index - 1]
		var current: Dictionary = entries[index]
		var previous_rank := rarity_order.find(str(previous["card_data"]["rarity"]))
		var current_rank := rarity_order.find(str(current["card_data"]["rarity"]))
		if previous_rank > current_rank:
			return false
		if previous_rank < current_rank:
			continue
		var previous_id := str(previous["card_data"]["id"])
		var current_id := str(current["card_data"]["id"])
		if previous_id > current_id or (previous_id == current_id and str(previous["id"]) > str(current["id"])):
			return false
	return true


func _has_effect(entries: Array, type: String, key: String, value: float) -> bool:
	for entry: Dictionary in entries:
		var effect: Dictionary = entry.get("effect_data", {})
		if str(effect.get("type", "")) == type and effect.has(key) and is_equal_approx(float(effect[key]), value):
			return true
	return false
