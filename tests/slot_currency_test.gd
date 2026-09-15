extends Node

const CURRENCY := preload("res://scripts/GameCurrency.gd")
const SAVE_PATH := "res://test-user/slot-currency-test.cfg"
var failures := 0
var checks := 0


class SaveControlledWallet:
	extends "res://scripts/GameCurrency.gd"
	var reject_save := false
	func save() -> bool:
		return false if reject_save else super.save()


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _new_wallet() -> Node:
	var wallet := CURRENCY.new()
	wallet.save_path = SAVE_PATH
	add_child(wallet)
	return wallet


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	var legacy := ConfigFile.new()
	legacy.set_value("currency", "coins", 100.37)
	legacy.set_value("progression", "level", 3)
	legacy.set_value("progression", "xp", 17)
	check(legacy.save(SAVE_PATH) == OK, "legacy fixture uses an isolated wallet")
	var wallet := _new_wallet()
	check(wallet.get_coin_cents() == 10037 and not wallet.has_pending_slot_spin(), "legacy fractional balance loads without inventing a pending spin")
	check(not wallet.begin_slot_spin(0, 100) and not wallet.begin_slot_spin(-100, 100) and not wallet.begin_slot_spin(100, -1), "invalid stakes and negative payouts are rejected")
	check(not wallet.begin_slot_spin(10038, 20000) and wallet.get_coin_cents() == 10037, "one cent below the stake rejects without charging")
	check(wallet.begin_slot_spin(1000, 2500) and wallet.get_coin_cents() == 9037, "accepted spin charges exactly one stake")
	var saved := ConfigFile.new()
	check(saved.load(SAVE_PATH) == OK and int(saved.get_value("currency", "coin_cents")) == 9037 and bool(saved.get_value("currency", "slot_spin_pending")) and int(saved.get_value("currency", "slot_payout_cents")) == 2500, "debit and committed payout are persisted together")
	check(not wallet.begin_slot_spin(1000, 9900) and wallet.get_coin_cents() == 9037, "pending spin rejects replacement and a second debit")
	check(wallet.complete_slot_spin() and wallet.get_coin_cents() == 11537 and not wallet.has_pending_slot_spin(), "completion credits the stored payout and clears pending state")
	check(not wallet.complete_slot_spin() and wallet.get_coin_cents() == 11537, "duplicate completion cannot pay twice")
	var reentrant: Array[bool] = []
	var callback := func(_coins: float):
		reentrant.append(wallet.begin_slot_spin(100, 100))
		reentrant.append(wallet.complete_slot_spin())
	wallet.coins_changed.connect(callback)
	check(wallet.begin_slot_spin(1000, 0) and wallet.complete_slot_spin(), "zero-payout spin starts and completes")
	wallet.coins_changed.disconnect(callback)
	check(reentrant == [false, false, false, false] and wallet.get_coin_cents() == 10537, "synchronous balance listeners cannot start or settle another transaction")
	check(wallet.begin_slot_spin(537, 2000), "fractional stake commits before interrupted animation")
	wallet.add_coin_cents(2)
	wallet.free()
	wallet = _new_wallet()
	check(wallet.get_coin_cents() == 12002 and not wallet.has_pending_slot_spin(), "reload recovers the interrupted payout and preserves other earned cents")
	check(wallet.get_level() == 3 and wallet.get_xp() == 17, "slot recovery preserves level and XP")
	wallet.load_currency()
	check(wallet.get_coin_cents() == 12002 and not wallet.complete_slot_spin(), "second reload cannot recover the same payout again")
	check(wallet.begin_slot_spin(12002, 0) and wallet.get_coin_cents() == 0, "an exact-balance stake is accepted")
	wallet.load_currency()
	check(wallet.get_coin_cents() == 0 and not wallet.has_pending_slot_spin(), "zero-payout recovery clears the pending spin without refunding its stake")
	wallet.coins = 20.0
	check(wallet.begin_slot_spin(100, 10000), "reset scenario starts with a pending reward")
	wallet.reset_progression()
	wallet.load_currency()
	check(wallet.get_coin_cents() == 2000 and wallet.get_level() == 1 and wallet.get_xp() == 0 and not wallet.has_pending_slot_spin() and not wallet.complete_slot_spin(), "progress reset clears pending payouts in memory and persistence")
	wallet.free()
	var controlled := SaveControlledWallet.new()
	controlled.save_path = "res://test-user/slot-currency-save-failure.cfg"
	add_child(controlled)
	controlled.reset_progression(false)
	controlled.coins = 10.37
	check(controlled.save(), "save-failure fixture starts with a persisted balance")
	var signals: Array[int] = [0]
	controlled.coins_changed.connect(func(_coins: float): signals[0] += 1)
	controlled.reject_save = true
	check(not controlled.begin_slot_spin(137, 500) and controlled.get_coin_cents() == 1037 and not controlled.has_pending_slot_spin() and signals[0] == 0, "failed debit save restores balance and emits no transaction")
	controlled.reject_save = false
	check(controlled.begin_slot_spin(137, 500), "transaction can retry after its debit save failed")
	controlled.reject_save = true
	check(not controlled.complete_slot_spin() and controlled.get_coin_cents() == 900 and controlled.has_pending_slot_spin() and signals[0] == 1, "failed payout save preserves the pending debit without announcing a payout")
	controlled.reject_save = false
	check(controlled.complete_slot_spin() and controlled.get_coin_cents() == 1400 and not controlled.complete_slot_spin(), "retry after failed completion pays once")
	check(controlled.begin_slot_spin(400, 800), "recovery scenario commits before a save failure")
	controlled.reject_save = true
	controlled.load_currency()
	check(controlled.get_coin_cents() == 1000 and controlled.has_pending_slot_spin(), "failed recovery save retains the committed pending payout")
	controlled.reject_save = false
	controlled.load_currency()
	controlled.load_currency()
	check(controlled.get_coin_cents() == 1800 and not controlled.has_pending_slot_spin(), "recovery retries successfully and the next reload cannot duplicate it")
	controlled.free()
	print("SLOT_CURRENCY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
