extends Node

var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1

func _run() -> void:
	if not SaveSlots.SAVE_ROOT.begins_with("res://test-user/") or GameCurrency.get("refuse_saves") == null or CollectionManager.get("test_income_multiplier") == null:
		push_error("Run this test with run_basement_cat_backend_tests.ps1 to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_shot()
	_check_spared()
	_check_save_failures()
	_check_old_saves()
	_check_profiles()
	print("BASEMENT_CAT_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _reset() -> void:
	GameCurrency.set("refuse_saves", false)
	GameCurrency.save_path = ""
	CollectionManager.set("test_income_multiplier", 1.0)
	GameCurrency.clear_profile_state()
	GameCurrency.coins = 23.45
	GameCurrency.save()

func _check_shot() -> void:
	_reset()
	check(GameCurrency.get_basement_cat_choice().is_empty(), "fresh profile starts with an undecided living cat")
	for invalid in ["", "dead", "SHOt", "spare"]:
		check(GameCurrency.resolve_basement_cat_choice(invalid)["reason"] == "invalid_choice", "invalid choice '%s' is rejected" % invalid)
	check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 2345, "invalid choices change neither cat nor balance")
	CollectionManager.set("test_income_multiplier", 7.5)
	GameCurrency.add_coins(1.0)
	check(GameCurrency.get_coin_cents() == 3095, "fixture exercises a real active regular-income multiplier")
	GameCurrency.set("_coin_reward_remainder", 0.37)
	GameCurrency.set("_xp_reward_remainder", 0.43)
	GameCurrency.save()
	var nested: Array[Dictionary] = []
	var snapshots: Array[Dictionary] = []
	var coin_listener := func(_coins: float):
		nested.append(GameCurrency.resolve_basement_cat_choice("shot"))
		var saved := ConfigFile.new()
		saved.load(GameCurrency.save_path)
		snapshots.append({"choice": saved.get_value("basement", "cat_choice", ""), "cents": saved.get_value("currency", "coin_cents", 0)})
	var choice_listener := func(_choice: String):
		nested.append(GameCurrency.resolve_basement_cat_choice("spared"))
	GameCurrency.coins_changed.connect(coin_listener)
	GameCurrency.basement_cat_choice_changed.connect(choice_listener)
	var result := GameCurrency.resolve_basement_cat_choice("shot")
	GameCurrency.coins_changed.disconnect(coin_listener)
	GameCurrency.basement_cat_choice_changed.disconnect(choice_listener)
	check(result == {"ok": true, "reason": "", "choice": "shot", "reward_coins": 1000}, "shot result reports the exact advertised reward")
	check(GameCurrency.get_coin_cents() == 103095, "shot awards exactly 1000 Soul Coins despite active income boost")
	check(GameCurrency.get("_coin_reward_remainder") == 0.37 and GameCurrency.get("_xp_reward_remainder") == 0.43, "fixed reward leaves fractional income and XP carry unchanged")
	check(nested.size() == 2 and nested[0]["reason"] == "busy" and nested[1]["reason"] == "busy", "wallet and choice callbacks cannot reenter the transaction")
	check(snapshots == [{"choice": "shot", "cents": 103095}], "signals only publish after choice and balance are durable together")
	check(GameCurrency.resolve_basement_cat_choice("shot")["reason"] == "already_resolved", "double clicking cannot pay a second reward")
	check(GameCurrency.resolve_basement_cat_choice("spared")["reason"] == "already_resolved", "a completed shot cannot change to spared")
	for _iteration in range(3):
		GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice() == "shot" and GameCurrency.get_coin_cents() == 103095, "repeated reloads retain cat death without granting more coins")
	check(GameCurrency.resolve_basement_cat_choice("shot")["reward_coins"] == 0, "repeat after reload reports no reward")

func _check_spared() -> void:
	_reset()
	var events: Array[String] = []
	var balances: Array[float] = []
	var choice_listener := func(choice: String): events.append(choice)
	var coin_listener := func(coins: float): balances.append(coins)
	GameCurrency.basement_cat_choice_changed.connect(choice_listener)
	GameCurrency.coins_changed.connect(coin_listener)
	var result := GameCurrency.resolve_basement_cat_choice("spared")
	GameCurrency.basement_cat_choice_changed.disconnect(choice_listener)
	GameCurrency.coins_changed.disconnect(coin_listener)
	check(result == {"ok": true, "reason": "", "choice": "spared", "reward_coins": 0}, "sparing reports success without a monetary reward")
	check(events == ["spared"] and balances.is_empty(), "sparing emits its choice once without a wallet change")
	check(GameCurrency.resolve_basement_cat_choice("shot")["reason"] == "already_resolved", "a spared cat cannot later be shot through the backend")
	GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice() == "spared" and GameCurrency.get_coin_cents() == 2345, "sparing persists with the original balance")
	GameCurrency.clear_profile_state()
	check(GameCurrency.get_basement_cat_choice().is_empty(), "clearing profile memory discards the previous cat choice")
	GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice() == "spared", "clearing memory does not overwrite the persisted decision")
	GameCurrency.reset_progression()
	GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice().is_empty(), "explicit progression reset permits a fresh encounter")

func _check_save_failures() -> void:
	for choice in ["shot", "spared"]:
		_reset()
		var original_file := FileAccess.get_file_as_string(GameCurrency.save_path)
		var events: Array[String] = []
		var listener := func(value: String): events.append(value)
		GameCurrency.basement_cat_choice_changed.connect(listener)
		GameCurrency.set("refuse_saves", true)
		var result := GameCurrency.resolve_basement_cat_choice(choice)
		GameCurrency.basement_cat_choice_changed.disconnect(listener)
		check(result["reason"] == "save_failed" and not result["ok"] and result["reward_coins"] == 0, "%s returns actionable failure when persistence fails" % choice)
		check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 2345, "%s save failure rolls back both memory changes" % choice)
		check(events.is_empty() and FileAccess.get_file_as_string(GameCurrency.save_path) == original_file, "%s failure publishes no choice and leaves the original save intact" % choice)
		GameCurrency.set("refuse_saves", false)
		GameCurrency.reload_profile()
		check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 2345, "%s failed choice remains undecided after restart" % choice)
		check(GameCurrency.resolve_basement_cat_choice(choice)["ok"], "%s can retry after storage recovers" % choice)
		GameCurrency.reload_profile()
		check(GameCurrency.get_coin_cents() == (102345 if choice == "shot" else 2345), "%s successful retry commits its reward only once" % choice)

func _check_old_saves() -> void:
	_reset()
	var cfg := ConfigFile.new()
	cfg.set_value("currency", "coins", 42.12)
	cfg.save(GameCurrency.save_path)
	GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 4212, "legacy currency-only saves preserve their balance and begin undecided")
	cfg.set_value("basement", "cat_choice", "unexpected_value")
	cfg.save(GameCurrency.save_path)
	GameCurrency.reload_profile()
	check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 4212, "unknown saved choice does not invent a completed outcome or reward")

func _check_profiles() -> void:
	_reset()
	check(SaveSlots.active_slot == 1, "isolated profile test starts on slot one")
	GameCurrency.resolve_basement_cat_choice("shot")
	check(SaveSlots.select_slot(2) == OK, "switching to a second slot succeeds")
	check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == 2000, "second slot starts with its own undecided cat and balance")
	GameCurrency.resolve_basement_cat_choice("spared")
	check(SaveSlots.select_slot(1) == OK, "returning to first slot succeeds")
	check(GameCurrency.get_basement_cat_choice() == "shot" and GameCurrency.get_coin_cents() == 102345, "first slot retains its dead cat and single reward")
	check(SaveSlots.select_slot(2) == OK, "returning to second slot succeeds")
	check(GameCurrency.get_basement_cat_choice() == "spared" and GameCurrency.get_coin_cents() == 2000, "second slot retains its spared cat without leaking another slot's reward")
