extends "res://scripts/GameCurrency.gd"

var fail_on_save := 0
var save_calls := 0

func save() -> bool:
	save_calls += 1
	return false if fail_on_save > 0 and save_calls == fail_on_save else super.save()
