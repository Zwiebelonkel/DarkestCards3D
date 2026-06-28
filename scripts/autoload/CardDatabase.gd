extends Node

const CARDS_PATH := "res://data/cards.json"

var cards: Array[Dictionary] = []
var cards_by_id: Dictionary = {}


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
	
#const RARITIES := [
	#{"id": "common", "drop_weight": 60.0},
	#{"id": "uncommon", "drop_weight": 25.0},
	#{"id": "rare", "drop_weight": 9.0},
	#{"id": "epic", "drop_weight": 4.0},
	#{"id": "legendary", "drop_weight": 1.5},
	#{"id": "mythic", "drop_weight": 0.4},
	#{"id": "exotic", "drop_weight": 0.1},
#]

const RARITIES := [
	{"id": "common", "drop_weight": 1.0},
	{"id": "uncommon", "drop_weight": 1.0},
	{"id": "rare", "drop_weight": 1.0},
	{"id": "epic", "drop_weight": 1.0},
	{"id": "legendary", "drop_weight": 1.0},
	{"id": "mythic", "drop_weight": 1.0},
	{"id": "exotic", "drop_weight": 1.0},
]

#const RARITIES := [
	#{"id": "common", "drop_weight": 0},
	#{"id": "uncommon", "drop_weight": 0},
	#{"id": "rare", "drop_weight": 0},
	#{"id": "epic", "drop_weight": 0},
	#{"id": "legendary", "drop_weight": 0},
	#{"id": "mythic", "drop_weight":.0},
	#{"id": "exotic", "drop_weight": 1.0},
#]


func get_random_rarity_weighted() -> String:
	var total_weight := 0.0
	
	for rarity in RARITIES:
		total_weight += float(rarity.get("drop_weight", 0.0))
	
	var roll := randf() * total_weight
	var current := 0.0
	
	for rarity in RARITIES:
		current += float(rarity.get("drop_weight", 0.0))
		
		if roll <= current:
			return str(rarity.get("id", "common"))
	
	return "common"


func get_random_card_weighted() -> Dictionary:
	if cards.is_empty():
		return {}
	
	var rarity := get_random_rarity_weighted()
	var pool := get_cards_by_rarity(rarity)
	
	if pool.is_empty():
		# Fallback, falls z.B. keine Mythic-Karten existieren
		return cards.pick_random()
	
	return pool.pick_random()
