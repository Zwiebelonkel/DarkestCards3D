extends Node3D

const SHOP_SCENE := preload("res://scenes/UpgradeShop.tscn")

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with tests/run_match_feature_tests.ps1 to isolate player saves.")
		get_tree().quit(1)
		return
	CardUpgradeManager.upgrades.clear()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.add_card("corpse")
	CollectionManager.add_card("jd")
	CollectionManager.add_card("clicker")
	GameCurrency.coins = 100
	GameCurrency._rescued_npcs["angel"] = true
	var shop := SHOP_SCENE.instantiate() as UpgradeMachine
	add_child(shop)
	shop.set_process(false)
	shop._on_card_selected("corpse")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [5]) and shop.ui.health_button.text == Localization.format_text("LEBEN +1\n%d SOUL COINS", [5]), "Fresh card shows both starting prices")
	shop._upgrade_attack()
	_expect(GameCurrency.get_coins() == 95 and CardUpgradeManager.get_attack_bonus("corpse") == 1, "First attack purchase charges five and grants one point")
	_expect(CardUpgradeManager.get_stat_upgrade_count("corpse") == 1, "Successful attack advances this card's shared counter once")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [10]) and shop.ui.health_button.text == Localization.format_text("LEBEN +1\n%d SOUL COINS", [10]), "Attack purchase immediately raises both displayed prices")
	shop._on_card_selected("jd")
	await get_tree().process_frame
	_expect(shop.selected_card_id == "jd" and shop.ui.selected_card_id == "jd", "Deferred refresh for the upgraded card cannot overwrite a later selection")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [5]), "Displayed price remains attached to the card the machine would actually buy")
	shop._on_card_selected("corpse")
	shop._upgrade_health()
	_expect(GameCurrency.get_coins() == 85 and CardUpgradeManager.get_health_bonus("corpse") == 1, "Switching to defense charges the next shared price")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [15]) and shop.ui.health_button.text == Localization.format_text("LEBEN +1\n%d SOUL COINS", [15]), "Defense purchase also raises both displayed prices")
	shop._upgrade_attack()
	_expect(GameCurrency.get_coins() == 70 and CardUpgradeManager.get_stat_upgrade_cost("corpse") == 20, "Repeated purchase reads the current price rather than a stale button value")
	shop._on_card_selected("jd")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [5]), "Another card retains its own starting price")
	shop._upgrade_health()
	_expect(GameCurrency.get_coins() == 65 and CardUpgradeManager.get_stat_upgrade_cost("jd") == 10, "Second card progresses independently")
	shop._on_card_selected("corpse")
	_expect(shop.ui.health_button.text == Localization.format_text("LEBEN +1\n%d SOUL COINS", [20]), "Returning to the first card restores its current price")
	GameCurrency.coins = 19.99
	GameCurrency.coins_changed.emit(GameCurrency.coins)
	_expect(shop.ui.attack_button.disabled and shop.ui.health_button.disabled, "Both buttons become unavailable just below the current price")
	shop._upgrade_health()
	_expect(GameCurrency.get_coin_cents() == 1999 and CardUpgradeManager.get_stat_upgrade_count("corpse") == 3, "Rejected purchase changes neither money nor upgrade progression")
	GameCurrency.add_coin_cents(1)
	_expect(not shop.ui.attack_button.disabled and not shop.ui.health_button.disabled, "Exact-price balance enables both actions immediately")
	shop._upgrade_health()
	_expect(GameCurrency.get_coin_cents() == 0 and CardUpgradeManager.get_health_bonus("corpse") == 2, "Exact-price purchase spends only the shown amount")
	_expect(CardUpgradeManager.get_stat_upgrade_cost("corpse") == 25 and shop.ui.attack_button.disabled, "Successful purchase advances once even when the balance reaches zero")
	GameCurrency.coins = 100
	for invalid_id in ["missing_card", "clicker", "mailman"]:
		shop.selected_card_id = invalid_id
		shop._upgrade_attack()
		shop._upgrade_health()
	_expect(GameCurrency.get_coins() == 100 and CardUpgradeManager.get_stat_upgrade_count("clicker") == 0, "Unknown, special and unowned cards cannot consume upgrade money")
	CardUpgradeManager.load_upgrades()
	_expect(CardUpgradeManager.get_stat_upgrade_cost("corpse") == 25 and CardUpgradeManager.get_stat_upgrade_cost("jd") == 10, "Independent counters and prices survive reloading")
	_expect(CardUpgradeManager.get_attack_bonus("corpse") == 2 and CardUpgradeManager.get_health_bonus("corpse") == 2, "Reload preserves both upgraded stats")
	var legacy := ConfigFile.new()
	legacy.set_value("corpse", "attack_bonus", 3)
	legacy.set_value("corpse", "health_bonus", 2)
	var upgrade_path := str(DeckManager.SAVE_PATH).get_base_dir().path_join("card_upgrades.cfg")
	_expect(legacy.save(upgrade_path) == OK, "Legacy upgrade fixture saves to the isolated profile")
	CardUpgradeManager.load_upgrades()
	_expect(CardUpgradeManager.get_stat_upgrade_count("corpse") == 5 and CardUpgradeManager.get_stat_upgrade_cost("corpse") == 30, "Old saves derive existing purchase progress instead of returning to the cheapest price")
	CardUpgradeManager.add_attack("corpse", 0)
	CardUpgradeManager.add_health("corpse", -1)
	_expect(CardUpgradeManager.get_stat_upgrade_count("corpse") == 5 and CardUpgradeManager.get_health_bonus("corpse") == 2, "No-op or negative stat changes do not raise prices or remove stats")
	CardUpgradeManager.add_attack("corpse", 3)
	_expect(CardUpgradeManager.get_stat_upgrade_count("corpse") == 6 and CardUpgradeManager.get_stat_upgrade_cost("corpse") == 35, "One successful upgrade advances one purchase even if it grants several points")
	CardUpgradeManager.load_upgrades()
	_expect(CardUpgradeManager.get_stat_upgrade_count("corpse") == 6, "Explicit purchase count persists independently of total stat bonus")
	shop._on_card_selected("corpse")
	_expect(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [35]), "Selection refresh shows the reloaded price")
	shop.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("UPGRADE_COST_TESTS: PASS (%d checks)" % _checks)
	else:
		print("UPGRADE_COST_TESTS: FAIL (%d/%d)" % [_failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

