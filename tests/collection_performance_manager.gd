extends "res://scripts/autoload/CollectionManager.gd"

var save_attempts := 0


func _save_collection_snapshot(next_collection: Dictionary, suffix: String = ".tmp") -> bool:
	save_attempts += 1
	return super._save_collection_snapshot(next_collection, suffix)
