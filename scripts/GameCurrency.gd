extends Node

signal coins_changed(coins: int)

var coins: int = 20

func _ready() -> void:
	load_currency()

func add_coins(amount: int) -> void:
	var gained := max(amount, 0)
	if gained <= 0:
		return

	coins += gained
	save()
	coins_changed.emit(coins)

func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true

	if coins < amount:
		return false

	coins -= amount
	save()
	coins_changed.emit(coins)
	return true

func has_coins(amount: int) -> bool:
	return coins >= amount

func get_coins() -> int:
	return coins

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "coins", coins)
	cfg.save("user://currency.cfg")

func load_currency() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://currency.cfg") == OK:
		coins = int(cfg.get_value("currency", "coins", 0))

	coins_changed.emit(coins)
