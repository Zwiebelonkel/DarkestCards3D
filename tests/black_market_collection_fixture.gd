extends "res://scripts/autoload/CollectionManager.gd"

var test_day := "2035-06-14"
var refuse_saves := false

func get_black_market_day() -> String:
	return test_day

func _save_collection_snapshot(snapshot: Dictionary, suffix: String = ".tmp") -> bool:
	return false if refuse_saves else super._save_collection_snapshot(snapshot, suffix)
