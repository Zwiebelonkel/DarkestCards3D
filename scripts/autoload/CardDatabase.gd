extends Node

const CARDS_PATH := "res://data/cards.json"

var cards: Array[Dictionary] = []
var cards_by_id: Dictionary = {}
var _current_pack_weights := {}


func _ready() -> void:
	load_cards()


func load_cards() -> void:
	cards.clear()
	cards_by_id.clear()
	
	if not FileAccess.file_exists(CARDS_PATH):
		push_error("cards.json nicht gefunden: " + CARDS_PATH)
		return
	
	var file := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if file == null:
		push_error("cards.json konnte nicht geöffnet werden.")
		return
	
	var text := file.get_as_text()
	file.close()
	
	var parsed = JSON.parse_string(text)
	
	if typeof(parsed) != TYPE_ARRAY:
		push_error("cards.json muss ein Array sein.")
		return
	
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		
		var card: Dictionary = entry
		var id := str(card.get("id", "")).strip_edges()
		
		if id == "":
			push_warning("Karte ohne ID übersprungen.")
			continue
		
		if cards_by_id.has(id):
			push_warning("Doppelte Karten-ID gefunden: " + id)
			continue
		
		cards.append(card)
		cards_by_id[id] = card
	
	print("CardDatabase geladen: ", cards.size(), " Karten")


func get_card(card_id: String) -> Dictionary:
	if not cards_by_id.has(card_id):
		push_warning("Karte nicht gefunden: " + card_id)
		return {}
	
	return cards_by_id[card_id]


func has_card(card_id: String) -> bool:
	return cards_by_id.has(card_id)


func get_all_cards() -> Array[Dictionary]:
	return cards.duplicate(true)


func get_cards_by_rarity(rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target := rarity.to_lower()
	
	for card in cards:
		if str(card.get("rarity", "")).to_lower() == target:
			result.append(card)
	
	return result


func get_random_card() -> Dictionary:
	if cards.is_empty():
		return {}
	
	return cards.pick_random()


func get_random_card_by_rarity(rarity: String) -> Dictionary:
	var pool := get_cards_by_rarity(rarity)
	
	if pool.is_empty():
		return {}
	
	return pool.pick_random()
	

func set_pack_rarity_weights(weights: Dictionary) -> void:
	_current_pack_weights = weights.duplicate()


func get_random_card_for_current_pack() -> Dictionary:
	if cards.is_empty():
		return {}

	if _current_pack_weights.is_empty():
		return get_random_card()

	var rarity := _roll_rarity(_current_pack_weights)
	var pool := get_cards_by_rarity(rarity)

	if pool.is_empty():
		return get_random_card()

	return pool.pick_random()


func _roll_rarity(weights: Dictionary) -> String:
	var total := 0.0

	for value in weights.values():
		total += float(value)

	if total <= 0.0:
		return "common"

	var roll := randf() * total
	var current := 0.0

	for rarity in weights.keys():
		current += float(weights[rarity])

		if roll <= current:
			return str(rarity)

	return "common"
