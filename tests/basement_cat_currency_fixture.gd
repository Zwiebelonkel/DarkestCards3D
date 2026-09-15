extends "res://scripts/GameCurrency.gd"

var refuse_saves := false

func save() -> bool:
	return false if refuse_saves else super.save()
