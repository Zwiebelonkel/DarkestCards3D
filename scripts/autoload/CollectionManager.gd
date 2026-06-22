extends Node

const SAVE_PATH := "user://collection.json"

var collection := {}


func _ready():
	load_collection()


func load_collection():
	if not FileAccess.file_exists(SAVE_PATH):
		save_collection()
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	collection = JSON.parse_string(file.get_as_text())

	if collection == null:
		collection = {}


func save_collection():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(collection, "\t"))


func add_card(card_id: String):
	if not collection.has(card_id):
		collection[card_id] = 0

	collection[card_id] += 1

	save_collection()


func get_amount(card_id: String) -> int:
	return collection.get(card_id, 0)
