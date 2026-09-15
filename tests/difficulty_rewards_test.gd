extends Node3D

const CURRENCY := preload("res://scripts/GameCurrency.gd")
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _reset_wallet(wallet: Node) -> void:
	wallet.clear_profile_state()
	wallet.coins = 0.0
	wallet.level = 100 # Isolate the match reward from separate level bonuses.


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run difficulty_rewards_test through the isolated match-feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	GameCurrency.save_path = "res://test-user/difficulty-match-currency.cfg"
	CollectionManager.clear_profile_state()
	var wallet := CURRENCY.new()
	wallet.save_path = "res://test-user/difficulty-api-currency.cfg"
	_check_reward_api(wallet)
	_check_boosts_and_save(wallet)
	wallet.free()
	CollectionManager.clear_profile_state()
	await _check_match_lifecycle()
	print("DIFFICULTY_REWARDS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_reward_api(wallet: Node) -> void:
	var difficulties := ["easy", "normal", "hard", "insane"]
	var outcomes := ["win", "draw", "loss"]
	var expected_xp := [[50, 25, 13], [100, 50, 25], [150, 75, 38], [300, 150, 75]]
	var expected_coins := [[5.0, 2.5, 1.0], [10.0, 5.0, 2.0], [15.0, 7.5, 3.0], [30.0, 15.0, 6.0]]
	for difficulty_index in difficulties.size():
		var difficulty: String = difficulties[difficulty_index]
		for outcome_index in outcomes.size():
			var outcome: String = outcomes[outcome_index]
			var xp_expected: int = expected_xp[difficulty_index][outcome_index]
			var coins_expected: float = expected_coins[difficulty_index][outcome_index]
			check(wallet.get_match_xp(outcome, difficulty) == xp_expected and is_equal_approx(wallet.get_match_coins(outcome, difficulty), coins_expected), "%s %s has the exact pre-boost XP/coin reward" % [difficulty, outcome])
			_reset_wallet(wallet)
			var result: Dictionary = wallet.award_match(outcome, difficulty)
			check(result["xp_awarded"] == xp_expected and is_equal_approx(result["coins_reward"], coins_expected) and wallet.xp == xp_expected and wallet.get_coin_cents() == roundi(coins_expected * 100.0), "%s %s awards rounded XP and preserves fractional coins" % [difficulty, outcome])
	check(wallet.get_match_xp("win") == 100 and wallet.get_match_coins("win") == 10.0, "omitting difficulty preserves existing normal rewards")
	check(wallet.get_match_xp("win", "unknown") == 100 and wallet.get_match_coins("win", "unknown") == 10.0, "an unknown difficulty safely uses the normal factor")
	var before := Vector3(wallet.coins, wallet.level, wallet.xp)
	var invalid: Dictionary = wallet.award_match("spectator", "insane")
	check(invalid["xp_awarded"] == 0 and invalid["coins_awarded"] == 0.0 and Vector3(wallet.coins, wallet.level, wallet.xp) == before, "unknown outcomes grant nothing even at the highest difficulty")


func _check_boosts_and_save(wallet: Node) -> void:
	CollectionManager.collection = {"cards": {"soulcoin_boost_1": 1, "xp_boost_1": 1}, "instances": []}
	_reset_wallet(wallet)
	check(wallet.get_match_xp("loss", "hard") == 38 and wallet.get_match_coins("draw", "easy") == 2.5, "preview getters remain pre-boost when permanent boosts are owned")
	var first: Dictionary = wallet.award_match("loss", "hard")
	check(first["xp_awarded"] == 38 and is_equal_approx(first["coins_reward"], 3.06), "difficulty rounds base XP before applying the existing two-percent boosts")
	var reloaded := CURRENCY.new()
	reloaded.save_path = wallet.save_path
	reloaded.load_currency()
	var second: Dictionary = reloaded.award_match("loss", "hard")
	check(second["xp_awarded"] == 39 and reloaded.xp == 77 and reloaded.get_coin_cents() == 612, "saved XP remainders survive between difficulty-scaled match rewards")
	_reset_wallet(wallet)
	var fractional: Dictionary = wallet.award_match("draw", "easy")
	check(is_equal_approx(fractional["coins_reward"], 2.55) and wallet.get_coin_cents() == 255, "the coin boost applies after the fractional easy-draw payout without integer truncation")
	reloaded.load_currency()
	check(reloaded.get_coin_cents() == 255 and reloaded.xp == 25, "boosted fractional reward and XP persist together")
	reloaded.free()
	CollectionManager.clear_profile_state()
	wallet.clear_profile_state()
	wallet.coins = 0.0
	var level_result: Dictionary = wallet.award_match("win", "insane")
	check(level_result["xp_awarded"] == 300 and level_result["coins_reward"] == 30.0 and level_result["coins_bonus"] == 60.0 and wallet.level == 3 and wallet.xp == 50, "insane match XP can cross levels without multiplying separate level-up coin bonuses")


func _check_match_lifecycle() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var table := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = camera
	add_child(table)
	table.set_process(false)
	await get_tree().process_frame
	var instance := CardData.create_instance("corpse")
	CollectionManager.collection = {"cards": {"corpse": 1}, "instances": [instance]}
	DeckManager.battle_deck.assign(["corpse"])
	DeckManager.deck_instance_ids.assign([str(instance["instance_id"])])
	DeckManager.starting_deck_indices.clear()
	_reset_wallet(GameCurrency)
	table._on_difficulty_selected("hard")
	check(table._match_reward_difficulty == "hard" and table._table_state == GameTable.TableState.PLAYING, "the real KI start captures the selected difficulty for this match")
	table._selected_difficulty = "easy"
	table._clear_match()
	table._player_deck.append(CardDatabase.get_card("corpse").duplicate(true))
	check(table._check_game_over(), "an exhausted opponent resolves the actual offline game-over path")
	check(GameCurrency.xp == 150 and GameCurrency.get_coin_cents() == 1500, "the result retains its captured hard reward after menu-selection changes and board cleanup")
	table._check_game_over()
	table._grant_match_rewards()
	table._clear_match()
	table._grant_match_rewards()
	check(GameCurrency.xp == 150 and GameCurrency.get_coin_cents() == 1500, "repeat result and cleanup callbacks cannot grant the same difficulty reward again")
	# Online startup is exercised as host with no supplied decks. This stops
	# before RPC traffic while still checking reset of the prior KI difficulty.
	table._online_mode = true
	table._online_is_host = true
	table._match_reward_difficulty = "insane"
	NetworkManager.local_player_data = {}
	NetworkManager.remote_player_data = {}
	table._start_online_match()
	check(table._match_reward_difficulty == "normal", "online startup discards the previous KI match's reward difficulty")
	for host in [true, false]:
		for winner in ["player", "enemy", "draw"]:
			table._clear_match()
			table._online_mode = true
			table._online_is_host = host
			table._online_is_spectator = false
			table._selected_difficulty = "insane"
			table._match_reward_difficulty = "insane" # A stale value must still be harmless online.
			table._match_reward_granted = false
			_reset_wallet(GameCurrency)
			table._apply_online_result(winner)
			var outcome := "draw" if winner == "draw" else ("win" if (winner == "player") == host else "loss")
			var expected_xp := GameCurrency.get_match_xp(outcome)
			var expected_cents := roundi(GameCurrency.get_match_coins(outcome) * 100.0)
			check(GameCurrency.xp == expected_xp and GameCurrency.get_coin_cents() == expected_cents, "%s receives normal %s rewards despite a previous insane KI selection" % ["host" if host else "guest", outcome])
			table._apply_online_result(winner)
			check(GameCurrency.xp == expected_xp and GameCurrency.get_coin_cents() == expected_cents, "duplicate authoritative result remains guarded for " + ("host" if host else "guest"))
	for winner in ["player", "enemy", "draw"]:
		table._match_reward_granted = false
		table._online_is_spectator = true
		_reset_wallet(GameCurrency)
		table._apply_online_result(winner)
		table._grant_match_rewards()
		check(GameCurrency.xp == 0 and GameCurrency.get_coin_cents() == 0, "spectator receives no reward for canonical result " + winner)
	table._online_mode = false
	table._clear_match()
	table.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
