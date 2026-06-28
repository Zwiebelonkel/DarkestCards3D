extends Node

var coins: int = 0


func add_coins(amount: int) -> void:
	coins += max(amount, 0)
	save()


func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true

	if coins < amount:
		return false

	coins -= amount
	save()
	return true


func has_coins(amount: int) -> bool:
	return coins >= amount
	
func get_coins(amount: int) -> int:
	return coins


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "coins", coins)
	cfg.save("user://currency.cfg")


func load_currency() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://currency.cfg") == OK:
		coins = int(cfg.get_value("currency", "coins", 0))
