extends Node

const PERKS_PATH := "res://data/perks.json"
const MAX_PERKS_PER_CARD := 2

var perks: Array[Dictionary] = []
var perks_by_type: Dictionary = {}

const RARITY_WEIGHTS := {
	"common": 60.0,
	"rare": 24.0,
	"epic": 10.0,
	"legendary": 4.0,
	"exotic": 2.0,
}

func _ready() -> void:
	load_perks()

func load_perks() -> void:
	perks.clear()
	perks_by_type.clear()
	if not FileAccess.file_exists(PERKS_PATH):
		push_error("perks.json nicht gefunden: " + PERKS_PATH)
		return
	var file := FileAccess.open(PERKS_PATH, FileAccess.READ)
	if file == null:
		push_error("perks.json konnte nicht geöffnet werden.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		push_error("perks.json muss ein Array sein.")
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var perk: Dictionary = entry
		var perk_type := str(perk.get("type", "")).strip_edges()
		if perk_type == "":
			continue
		perks.append(perk)
		if not perks_by_type.has(perk_type):
			perks_by_type[perk_type] = []
		(perks_by_type[perk_type] as Array).append(perk)

func get_perk(type: String) -> Dictionary:
	var variants: Array = perks_by_type.get(type, [])
	return {} if variants.is_empty() else (variants[0] as Dictionary).duplicate(true)

func get_all_perks() -> Array[Dictionary]:
	return perks.duplicate(true)

func get_random_perk_weighted() -> Dictionary:
	if perks.is_empty():
		return {}
	var total := 0.0
	for perk in perks:
		total += float(RARITY_WEIGHTS.get(str(perk.get("rarity", "common")), 1.0))
	var roll := randf() * total
	var current := 0.0
	for perk in perks:
		current += float(RARITY_WEIGHTS.get(str(perk.get("rarity", "common")), 1.0))
		if roll <= current:
			return (perk as Dictionary).duplicate(true)
	return (perks.pick_random() as Dictionary).duplicate(true)

func roll_perks(max_count: int = MAX_PERKS_PER_CARD) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := randi_range(0, max_count)
	var used := {}
	for i in range(count):
		var perk := get_random_perk_weighted()
		var perk_type := str(perk.get("type", ""))
		if perk_type == "" or used.has(perk_type):
			continue
		used[perk_type] = true
		result.append(perk)
	return result
