extends Node

const RULES := preload("res://scripts/match/OfflineMatchRules.gd")
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var catalog := CardDatabase.get_all_cards()
	for count in [1, 5, 20]:
		var previous_counts := [0, 0, 0, 0, 0, 0, 0]
		for level in range(1, 101):
			var deck := RULES.story_deck(level, count)
			check(deck.size() == count, "full deck at level %d / size %d" % [level, count])
			check(deck == RULES.story_deck(level, count), "replays retain their rarity mix")
			var counts := [0, 0, 0, 0, 0, 0, 0]
			for card: Dictionary in deck:
				var base := CardDatabase.get_card(str(card["id"]))
				var rank: int = RULES.STORY_RARITIES.find(card["rarity"])
				check(CardData.is_combat_card(card) and rank >= 0, "only real combat cards through Exotic")
				check(card["rarity"] == base["rarity"], "rarity belongs to the actual card")
				check(CardData.get_active_effects(card) == CardData.get_active_effects(CardData.merge_card_and_instance(base)), "native effects survive story scaling")
				check(card["attack"] == 1 + roundi((level - 1) * 0.95) and card["defense"] == 3 + roundi((level - 1) * 1.9), "story stat growth is reduced by five percent")
				for threshold in range(rank + 1):
					counts[threshold] += 1
			for threshold in range(counts.size()):
				check(counts[threshold] >= previous_counts[threshold], "higher levels never reduce rarity thresholds")
			previous_counts = counts
	var first := RULES.story_deck(1, 20)
	check(first.all(func(card: Dictionary) -> bool: return card["rarity"] == "common"), "level one remains all common")
	var final_counts := {}
	for card: Dictionary in RULES.story_deck(100, 20):
		var rarity: String = card["rarity"]
		final_counts[rarity] = int(final_counts.get(rarity, 0)) + 1
	check(final_counts == {"rare": 1, "epic": 3, "legendary": 6, "mythic": 6, "exotic": 4}, "final level uses the intended high-rarity mix")
	check(CardDatabase.get_all_cards() == catalog, "generation does not mutate the catalog")
	check(RULES.story_deck(0, 20).is_empty() and RULES.story_deck(101, 20).is_empty(), "invalid levels remain rejected")
	check(RULES.story_deck(1, 0).is_empty() and RULES.story_deck(1, -1).is_empty(), "nonpositive deck sizes remain empty")
	print("STORY_RARITY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
