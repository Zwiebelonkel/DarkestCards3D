extends "res://scripts/GameCurrency.gd"

var refuse_saves := false
var save_count := 0

func save() -> bool:
	save_count += 1
	return false if refuse_saves else super.save()
