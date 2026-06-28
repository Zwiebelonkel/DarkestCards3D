extends Node

const MAX_DECK_SIZE := 20
const SAVE_PATH := "user://battle_deck.cfg"

var battle_deck: Array[String] = []

func _ready() -> void:
	load_deck()

func can_add_card(card_id: String) -> bool:
	if battle_deck.size() >= MAX_DECK_SIZE:
		return false

	var owned_amount := CollectionManager.get_amount(card_id)
	var deck_amount := get_card_count(card_id)

	return deck_amount < owned_amount

func add_card(card_id: String) -> bool:
	if not can_add_card(card_id):
		return false

	battle_deck.append(card_id)
	save_deck()
	return true

func remove_card(card_id: String) -> bool:
	var index := battle_deck.find(card_id)
	if index == -1:
		return false

	battle_deck.remove_at(index)
	save_deck()
	return true

func get_card_count(card_id: String) -> int:
	var count := 0
	for id in battle_deck:
		if id == card_id:
			count += 1
	return count

func is_full() -> bool:
	return battle_deck.size() >= MAX_DECK_SIZE

func save_deck() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("deck", "cards", battle_deck)
	cfg.save(SAVE_PATH)

func load_deck() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		battle_deck = cfg.get_value("deck", "cards", [])

func get_deck_cards() -> Array[String]:
	return battle_deck.duplicate()
