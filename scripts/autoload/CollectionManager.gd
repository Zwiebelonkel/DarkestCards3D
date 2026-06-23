extends Node

const SAVE_PATH := "user://collection.json"

var collection := {
	"cards": {},
	"instances": []
}


func _ready():
	load_collection()


func load_collection():
	if not FileAccess.file_exists(SAVE_PATH):
		save_collection()
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	collection = JSON.parse_string(file.get_as_text())

	if collection == null or typeof(collection) != TYPE_DICTIONARY:
		collection = {"cards": {}, "instances": []}
		return

	_migrate_legacy_collection()


func save_collection():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(collection, "\t"))


func add_card(card_id: String) -> Dictionary:
	var instance := create_card_instance(card_id)
	save_collection()
	return instance


func create_card_instance(card_id: String, level: int = 1, perks: Array = []) -> Dictionary:
	_migrate_legacy_collection()
	var rolled_perks: Array = perks
	if rolled_perks.is_empty():
		rolled_perks = PerkDatabase.roll_perks()
	var instance := CardData.create_instance(card_id, level, rolled_perks)
	collection["instances"].append(instance)
	var cards: Dictionary = collection["cards"]
	cards[card_id] = int(cards.get(card_id, 0)) + 1
	return instance


func get_amount(card_id: String) -> int:
	_migrate_legacy_collection()
	return int((collection["cards"] as Dictionary).get(card_id, 0))


func get_owned_cards() -> Dictionary:
	_migrate_legacy_collection()
	return (collection["cards"] as Dictionary).duplicate(true)


func get_card_instances() -> Array:
	_migrate_legacy_collection()
	return (collection["instances"] as Array).duplicate(true)


func get_instances_for_card(card_id: String) -> Array:
	var result := []
	for instance in get_card_instances():
		if typeof(instance) == TYPE_DICTIONARY and str(instance.get("card_id", "")) == card_id:
			result.append((instance as Dictionary).duplicate(true))
	return result


func _migrate_legacy_collection() -> void:
	if collection.has("cards") and collection.has("instances"):
		return
	var legacy := collection.duplicate(true)
	collection = {"cards": {}, "instances": []}
	for card_id in legacy.keys():
		var amount := int(legacy.get(card_id, 0))
		if amount <= 0:
			continue
		collection["cards"][card_id] = amount
		for i in range(amount):
			collection["instances"].append(CardData.create_instance(str(card_id)))
