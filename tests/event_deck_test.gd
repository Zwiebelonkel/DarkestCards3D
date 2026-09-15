extends SceneTree

const EVENTS := preload("res://scripts/events/EventDeck.gd")
const CARD_DATA := preload("res://scripts/card/CardData.gd")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 9042
	second_rng.seed = 9042
	var deck := EVENTS.create_shuffled(first_rng)
	var same_seed_deck := EVENTS.create_shuffled(second_rng)
	_expect(deck.size() == EVENTS.DECK_SIZE, "Each match starts with 24 events")
	_expect(deck == same_seed_deck, "The match RNG determines the complete order")
	_expect(deck.all(func(card: Dictionary) -> bool: return card.get("category") == "event" and not CARD_DATA.is_combat_card(card)), "Events cannot enter combat-card pools")
	var ids: Dictionary = {}
	var counts: Dictionary = {}
	for card: Dictionary in deck:
		_expect(not ids.has(card["uid"]), "Every physical event has its own identity")
		ids[card["uid"]] = true
		counts[card["id"]] = int(counts.get(card["id"], 0)) + 1
	_expect(counts["steel"] == 1, "There is exactly one Steel")
	for event_id: String in counts:
		if event_id != "steel":
			_expect(int(counts[event_id]) > int(counts["steel"]), "Steel is strictly rarer than every other event")

	var discard: Array[Dictionary] = []
	var hand: Array[Dictionary] = []
	for _index in range(EVENTS.DECK_SIZE):
		hand.append(EVENTS.draw(deck, discard, first_rng))
	_expect(deck.is_empty() and discard.is_empty(), "Drawing moves every event out of the shared pile")
	_expect(EVENTS.draw(deck, discard, first_rng).is_empty(), "Holding every card does not create extra events")
	var played: Dictionary = hand.pop_back()
	discard.append(played)
	var recycled := EVENTS.draw(deck, discard, first_rng)
	_expect(recycled == played and discard.is_empty() and deck.is_empty(), "An empty pile recycles only the played card")
	_expect(hand.size() == EVENTS.DECK_SIZE - 1, "Recycling leaves held cards untouched")

	var remaining: Array[Dictionary] = [{"uid": "still_in_deck"}]
	var waiting: Array[Dictionary] = [{"uid": "already_played"}]
	_expect(EVENTS.draw(remaining, waiting, first_rng)["uid"] == "still_in_deck", "An existing draw pile is exhausted before recycling")
	_expect(waiting.size() == 1, "Discard stays separate until another draw needs it")
	var definitions := EVENTS.definitions()
	definitions[0]["name"] = "Modified UI copy"
	_expect(EVENTS.definitions()[0]["name"] == "Switch", "UI changes cannot mutate the event definitions")
	deck = EVENTS.create_shuffled(first_rng)
	deck[0]["description"] = "Modified hand"
	_expect(not EVENTS.create_shuffled(second_rng).any(func(card: Dictionary) -> bool: return card["description"] == "Modified hand"), "Match card instances do not share mutable definitions")

	if _failures.is_empty():
		print("EVENT_DECK_TESTS: PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
