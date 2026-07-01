extends Node

const EFFECTS_PATH := "res://data/effects.json"
const MAX_EFFECTS_PER_CARD := 2

var effects: Array[Dictionary] = []
var effects_by_type: Dictionary = {}

const RARITY_WEIGHTS := {
	"common": 60.0,
	"rare": 24.0,
	"epic": 10.0,
	"legendary": 4.0,
	"exotic": 2.0,
}

func _ready() -> void:
	load_effects()

func load_effects() -> void:
	effects.clear()
	effects_by_type.clear()
	if not FileAccess.file_exists(EFFECTS_PATH):
		push_error("effects.json nicht gefunden: " + EFFECTS_PATH)
		return
	var file := FileAccess.open(EFFECTS_PATH, FileAccess.READ)
	if file == null:
		push_error("effects.json konnte nicht geöffnet werden.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		push_error("effects.json muss ein Array sein.")
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = entry
		var effect_type := str(effect.get("type", "")).strip_edges()
		if effect_type == "":
			continue
		effects.append(effect)
		if not effects_by_type.has(effect_type):
			effects_by_type[effect_type] = []
		(effects_by_type[effect_type] as Array).append(effect)

func get_effect(type: String) -> Dictionary:
	var variants: Array = effects_by_type.get(type, [])
	return {} if variants.is_empty() else (variants[0] as Dictionary).duplicate(true)

func get_all_effects() -> Array[Dictionary]:
	return effects.duplicate(true)

func get_random_effect_weighted() -> Dictionary:
	if effects.is_empty():
		return {}
	var total := 0.0
	for effect in effects:
		total += float(RARITY_WEIGHTS.get(str(effect.get("rarity", "common")), 1.0))
	var roll := randf() * total
	var current := 0.0
	for effect in effects:
		current += float(RARITY_WEIGHTS.get(str(effect.get("rarity", "common")), 1.0))
		if roll <= current:
			return (effect as Dictionary).duplicate(true)
	return (effects.pick_random() as Dictionary).duplicate(true)

func roll_effects(max_count: int = MAX_EFFECTS_PER_CARD) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := randi_range(0, max_count)
	var used := {}
	for i in range(count):
		var effect := get_random_effect_weighted()
		var effect_type := str(effect.get("type", ""))
		if effect_type == "" or used.has(effect_type):
			continue
		used[effect_type] = true
		result.append(effect)
	return result
