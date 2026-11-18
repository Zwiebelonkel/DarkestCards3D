extends Node3D

const SAVE_PATH := "res://test-user/progression-economy.cfg"
const UPGRADE_SCENE := preload("res://scenes/UpgradeShop.tscn")
const PACK_UI_SCENE := preload("res://scenes/PackShopUI.tscn")
const PACK_OPENING_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")
var checks := 0
var failures := 0


class CountingWallet:
	extends "res://scripts/GameCurrency.gd"
	var save_count := 0
	func save() -> bool:
		save_count += 1
		return super.save()


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _set_cards(cards: Dictionary) -> void:
	CollectionManager.collection = {"cards": cards, "instances": []}
	var changed: Array[String] = []
	CollectionManager.collection_changed.emit(changed)


func _new_wallet() -> CountingWallet:
	var wallet := CountingWallet.new()
	wallet.save_path = SAVE_PATH
	add_child(wallet)
	wallet.set_process(false)
	return wallet


func _clear_wallet(wallet: CountingWallet) -> void:
	wallet.reset_progression(false)
	wallet.coins = 0.0
	wallet.save_count = 0


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_set_cards({})
	var wallet := _new_wallet()
	_clear_wallet(wallet)
	check(wallet.get_manual_click_reward() == 0.0, "Locked manual clicker has no reward")
	wallet.award_manual_click()
	wallet.advance_auto_clicker(50.0)
	check(wallet.coins == 0.0 and wallet.save_count == 0, "Locked clickers neither earn nor save")
	_set_cards({"golden_clicker": 2, "auto_clicker": 1, "clicker_upgrade": 3})
	check(wallet.get_manual_click_reward() == 0.0, "Golden and legacy upgrades require the original Clicker")
	wallet.advance_auto_clicker(20.0)
	_set_cards({"clicker": 1, "golden_clicker": 2, "auto_clicker": 1, "clicker_upgrade": 3})
	check(is_equal_approx(wallet.get_manual_click_base_reward(), 0.15), "Golden copies stack with the existing clicker upgrades")
	wallet.award_manual_click()
	check(wallet.get_coin_cents() == 15, "Manual award uses the centrally calculated reward")
	_clear_wallet(wallet)
	for _frame in range(60):
		wallet.advance_auto_clicker(1.0 / 60.0)
	check(wallet.get_coin_cents() == 2 and wallet.save_count == 1, "One online second earns two cents in one save without locked-time credit")
	wallet.advance_auto_clicker(0.5)
	wallet.save()
	wallet.free()
	wallet = _new_wallet()
	wallet.advance_auto_clicker(0.5)
	check(wallet.get_coin_cents() == 2, "Loading does not restore partial seconds or award offline income")
	wallet.advance_auto_clicker(0.5)
	check(wallet.get_coin_cents() == 4, "Automatic income resumes after a complete online second")
	wallet.advance_auto_clicker(0.75)
	_set_cards({})
	wallet.advance_auto_clicker(100.0)
	_set_cards({"clicker": 1, "auto_clicker": 1})
	wallet.advance_auto_clicker(0.25)
	check(wallet.get_coin_cents() == 4, "Removing and reacquiring the unlock discards locked and partial elapsed time")
	CollectionManager.save_collection()
	_set_cards({})
	CollectionManager.load_collection()
	wallet.advance_auto_clicker(1.0)
	check(wallet.get_coin_cents() == 6, "Reloading the collection refreshes the automatic earning cache immediately")

	_set_cards({"soulcoin_boost_1": 1, "xp_boost_1": 1})
	_clear_wallet(wallet)
	for _reward in range(25):
		wallet.add_coin_cents(1)
		wallet.add_xp(1)
	check(wallet.get_coin_cents() == 25 and wallet.xp == 25, "Sub-cent and sub-XP bonuses are retained rather than rounded up")
	wallet.free()
	wallet = _new_wallet()
	for _reward in range(25):
		wallet.add_coin_cents(1)
		wallet.add_xp(1)
	check(wallet.get_coin_cents() == 51 and wallet.xp == 51, "Fractional coin and XP boosts accumulate correctly across reload")
	_set_cards({"soulcoin_boost_1": 1, "soulcoin_boost_2": 1, "soulcoin_boost_3": 1, "soulcoin_boost_4": 1, "xp_boost_1": 1, "xp_boost_2": 1, "xp_boost_3": 1, "xp_boost_4": 1})
	_clear_wallet(wallet)
	var level_bonuses: Array[float] = []
	wallet.level_up.connect(func(_level: int, bonus: float): level_bonuses.append(bonus))
	var reward := wallet.award_match("win")
	check(reward.xp_awarded == 115 and wallet.level == 2 and wallet.xp == 15, "Only the highest XP tier applies to match rewards")
	check(is_equal_approx(reward.coins_reward, 11.5) and is_equal_approx(reward.coins_bonus, 28.75) and wallet.get_coin_cents() == 4025, "Match and level coins receive the highest multiplier exactly once")
	check(level_bonuses == [28.75] and wallet.save_count == 1, "Fractional level signal and all match rewards share one save")
	_set_cards({"clicker": 1, "auto_clicker": 1, "soulcoin_boost_1": 1})
	_clear_wallet(wallet)
	for _click in range(25):
		wallet.award_manual_click()
	check(wallet.get_coin_cents() == 51, "SoulCoin boosts apply to small manual clicks without losing fractions")
	_clear_wallet(wallet)
	wallet.advance_auto_clicker(25.0)
	check(wallet.get_coin_cents() == 51 and wallet.save_count == 1, "Automatic income gets the same SoulCoin boost in one batch")

	_set_cards({"dealer_license": 1, "soulcoin_boost_1": 1})
	wallet.coins = 20.0
	check(is_equal_approx(wallet.get_shop_price(5.0), 4.5) and is_equal_approx(wallet.get_shop_price(12.0), 10.8), "Dealer prices retain fractional coins")
	check(wallet.get_shop_price(5.0, "black_market") == 5.0 and wallet.get_shop_price(0.0) == 0.0, "Normal discounts leave separate shop pools and zero base prices intact")
	var reservation := wallet.begin_pack_purchase(450, 2)
	check(reservation > 0 and wallet.get_coin_cents() == 1100, "Pack reservation charges the already discounted unit price once")
	check(wallet.refund_queued_packs(reservation) and wallet.get_coin_cents() == 1550, "Unopened packs refund their exact paid price without income boosts")
	check(wallet.begin_slot_spin(100, 200) and wallet.complete_slot_spin() and wallet.get_coin_cents() == 1650, "Slot stakes and committed gambling payouts keep their advertised values")
	wallet.reset_progression()
	wallet.free()
	wallet = _new_wallet()
	check(wallet._coin_reward_remainder == 0.0 and wallet._xp_reward_remainder == 0.0, "Reset clears saved fractional progression")
	wallet.free()

	await _check_shop_integration()
	if failures == 0:
		print("PROGRESSION_ECONOMY_TESTS: PASS (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _check_shop_integration() -> void:
	_set_cards({"corpse": 1})
	CardUpgradeManager.upgrades.clear()
	GameCurrency.reset_progression(false)
	GameCurrency._rescued_npcs["angel"] = true
	GameCurrency.coins = 100.0
	check(PackDefinition.get_price("basic") == 5.0 and CardUpgradeManager.get_stat_upgrade_cost("corpse") == 5.0, "Existing prices remain unchanged without Dealer License")
	var shop := UPGRADE_SCENE.instantiate() as UpgradeMachine
	add_child(shop)
	shop.set_process(false)
	shop._on_card_selected("corpse")
	var pack_ui := PACK_UI_SCENE.instantiate() as PackShopUI
	add_child(pack_ui)
	pack_ui.set_packs(PackDefinition.PACK_TYPES)
	CollectionManager.add_card("dealer_license")
	check(is_equal_approx(PackDefinition.get_price("basic"), 4.5) and is_equal_approx(pack_ui.pack_previews.basic.pack_cost, 4.5), "Open pack previews refresh the discounted price immediately on unlock")
	check(shop.ui.attack_button.text.contains(GameCurrency.format_coins(4.5, true)) and shop.ui.effect_button.text.contains(GameCurrency.format_coins(10.8, true)), "Open upgrade UI shows discounted stat and effect prices")
	shop._upgrade_attack()
	check(GameCurrency.get_coin_cents() == 9550 and CardUpgradeManager.get_attack_bonus("corpse") == 1 and CardUpgradeManager.get_stat_upgrade_cost("corpse") == 9.0, "A stat purchase charges 4.50 then increases the shared next price to 9.00")
	shop._roll_effect()
	check(GameCurrency.get_coin_cents() == 8470, "Effect purchase charges the same 10.80 displayed in the shop")
	var pack := PACK_OPENING_SCENE.instantiate() as PackOpeningScreen
	add_child(pack)
	pack.set_process(false)
	check(pack.buy_pack("basic", PackDefinition.PACK_TYPES.basic) and GameCurrency.get_coin_cents() == 8020, "Actual pack purchase charges the displayed 4.50 without a second discount")
	pack.queue_free()
	pack_ui.queue_free()
	shop.queue_free()
	await get_tree().process_frame
