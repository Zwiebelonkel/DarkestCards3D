extends RefCounted
class_name EventDeck

## Events belong to a match, never to the collectible combat-card database.
## The host deals the opening hands and owns subsequent effect-driven draws.
const DECK_SIZE := 31
const STARTING_HAND_SIZE := 3

const CARD_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "switch", "name": "Switch", "category": "event", "rarity": "common", "target": "none",
		"description": "Tauscht eine zufällige Karte deines Nachziehstapels mit einer zufälligen Karte des gegnerischen Nachziehstapels.",
		"copies": 6,
	},
	{
		"id": "block", "name": "Block", "category": "event", "rarity": "uncommon", "target": "enemy",
		"description": "Wähle eine gegnerische Karte auf dem Tisch. Bis zum Ende ihrer nächsten 2 Züge kann sie weder angreifen noch kontern.",
		"block_turns": 2, "copies": 5,
	},
	{
		"id": "steel", "name": "Steel", "category": "event", "rarity": "legendary", "target": "enemy",
		"description": "Wähle eine gegnerische Karte auf dem Tisch und mische sie in deinen Nachziehstapel. Der Gegner zieht eine Ersatzkarte, falls sein Stapel nicht leer ist.",
		"copies": 1,
	},
	{
		"id": "strength_120", "name": "Stärke ×1,2", "category": "event", "rarity": "common", "target": "ally",
		"description": "Wähle eine eigene Karte auf dem Tisch. Multipliziere ihren Angriff und ihre Lebenspunkte mit 1,2 (aufgerundet).",
		"multiplier": 1.2, "copies": 7,
	},
	{
		"id": "strength_150", "name": "Stärke ×1,5", "category": "event", "rarity": "rare", "target": "ally",
		"description": "Wähle eine eigene Karte auf dem Tisch. Multipliziere ihren Angriff und ihre Lebenspunkte mit 1,5 (aufgerundet).",
		"multiplier": 1.5, "copies": 3,
	},
	{
		"id": "strength_200", "name": "Stärke ×2", "category": "event", "rarity": "epic", "target": "ally",
		"description": "Wähle eine eigene Karte auf dem Tisch. Verdopple ihren Angriff und ihre Lebenspunkte.",
		"multiplier": 2.0, "copies": 2,
	},
	{
		# Keep the collectible Piss Bucket's existing "piss" ID separate.
		"id": "piss_event", "name": "Piss", "category": "event", "rarity": "legendary", "target": "none",
		"description": "Ein Piss-Strahl trifft den Tisch. Der Gegner sieht für seine nächsten 2 Züge keine Werte oder Effekte aller Tischkarten, auch nachgezogener Karten.",
		"hidden_turns": 2, "copies": 1,
	},
	{
		"id": "heal_event", "name": "Heal", "category": "event", "rarity": "rare", "target": "ally",
		"description": "Wähle eine verletzte eigene Karte auf dem Tisch. Stelle ihre Lebenspunkte vollständig wieder her.",
		"copies": 3,
	},
	{
		"id": "rearrange_event", "name": "Rearrange", "category": "event", "rarity": "uncommon", "target": "ally",
		"description": "Wähle nacheinander zwei eigene Karten auf dem Tisch. Tausche ihre Plätze. Alle Werte und Zustände bleiben erhalten.",
		"copies": 3,
	},
]


static func definitions() -> Array[Dictionary]:
	# Callers may customize a UI copy without changing subsequent matches.
	return CARD_DEFINITIONS.duplicate(true)


static func get_display_name(card: Dictionary) -> String:
	return Localization.text(str(card.get("name", "")))


static func get_display_description(card: Dictionary) -> String:
	return Localization.text(str(card.get("description", "")))


static func create_shuffled(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for definition: Dictionary in CARD_DEFINITIONS:
		for copy_index in range(int(definition["copies"])):
			var card := definition.duplicate(true)
			card.erase("copies")
			# Unique within a match and stable while moving between hand/discard.
			card["uid"] = "%s_%d" % [str(card["id"]), copy_index]
			cards.append(card)
	shuffle(cards, rng)
	return cards


static func shuffle(cards: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	# Use the match RNG rather than Array.shuffle()'s shared global RNG.
	for index in range(cards.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var card: Dictionary = cards[index]
		cards[index] = cards[other]
		cards[other] = card


static func draw(
	cards: Array[Dictionary], discard: Array[Dictionary], rng: RandomNumberGenerator
) -> Dictionary:
	# Only played cards return. Cards held by either player stay in their hand.
	if cards.is_empty() and not discard.is_empty():
		cards.append_array(discard)
		discard.clear()
		shuffle(cards, rng)
	if cards.is_empty():
		return {}
	return cards.pop_back()
