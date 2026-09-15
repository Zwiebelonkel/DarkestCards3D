extends Node3D

const PACK_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")
var checks := 0
var failures := 0
var started := 0
var completed := 0
var progress: Array[Vector2i] = []


class SaveControlledWallet:
	extends "res://scripts/GameCurrency.gd"
	var reject_save := false
	func save() -> bool:
		return false if reject_save else super.save()


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _wait_until(predicate: Callable, timeout_msec: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not DeckManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run pack_batch_test.tscn through the isolated match-feature runner.")
		get_tree().quit(1)
		return
	_test_wallet()
	await _test_screen()
	print("PACK_BATCH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_wallet() -> void:
	var wallet := SaveControlledWallet.new()
	wallet.save_path = "res://test-user/pack-batch-wallet.cfg"
	add_child(wallet)
	wallet.reset_progression(false)
	wallet.coins = 41.01
	wallet.level = 2
	wallet.xp = 17
	wallet.save()
	check(wallet.begin_pack_purchase(500, 0) == 0 and wallet.begin_pack_purchase(500, -1) == 0 and wallet.begin_pack_purchase(0, 8) == 0, "wallet rejects invalid counts and prices")
	check(wallet.begin_pack_purchase(500, 9) == 0 and wallet.get_coin_cents() == 4101, "wallet rejects a total exceeding funds without spending")
	check(wallet.begin_pack_purchase(500, 9223372036854775807) == 0 and wallet.get_coin_cents() == 4101, "overflow-sized count cannot produce a negative debit")
	var reentry: Array[int] = []
	var callback := func(_coins: float):
		reentry.append(wallet.begin_pack_purchase(1, 1))
		reentry.append(int(wallet.refund_queued_packs()))
	wallet.coins_changed.connect(callback)
	var token := wallet.begin_pack_purchase(500, 8)
	wallet.coins_changed.disconnect(callback)
	check(token > 0 and wallet.get_coin_cents() == 101 and wallet.get_queued_pack_count(token) == 7, "eight-pack purchase charges 40 coins once and reserves seven unopened packs")
	check(reentry == [0, 0], "synchronous coin listeners cannot purchase or refund during payment")
	var saved := ConfigFile.new()
	check(saved.load(wallet.save_path) == OK and saved.get_value("currency", "coin_cents") == 101 and saved.get_value("currency", "queued_pack_count") == 7, "debit and unused queue are persisted together")
	check(not wallet.consume_queued_pack(token + 1) and not wallet.refund_queued_packs(token + 1), "another screen cannot consume or refund this reservation")
	check(wallet.consume_queued_pack(token) and wallet.get_queued_pack_count(token) == 6 and wallet.get_coin_cents() == 101, "presenting the second pack consumes its reservation without charging again")
	wallet.add_coin_cents(2)
	check(wallet.refund_queued_packs(token) and wallet.get_coin_cents() == 3103 and wallet.get_queued_pack_count() == 0, "interruption refunds only the six unused packs and preserves earned cents")
	check(not wallet.refund_queued_packs(token) and wallet.get_coin_cents() == 3103, "repeated exit cannot refund a queue twice")
	var first_token := wallet.begin_pack_purchase(500, 3)
	check(first_token > 0 and wallet.begin_slot_spin(100, 250), "pack reservation can coexist with a committed slot result")
	wallet.load_currency()
	check(wallet.get_coin_cents() == 2753 and wallet.get_queued_pack_count() == 0 and not wallet.has_pending_slot_spin(), "reload recovers both unused packs and the pending slot payout")
	check(wallet.get_level() == 2 and wallet.get_xp() == 17, "queue recovery preserves level and XP")
	wallet.load_currency()
	check(wallet.get_coin_cents() == 2753, "second load cannot duplicate the refund or slot payout")
	wallet.reset_progression(false)
	wallet.coins = 41
	var stale_token := wallet.begin_pack_purchase(500, 3)
	wallet.reset_progression()
	var current_token := wallet.begin_pack_purchase(500, 2)
	check(not wallet.refund_queued_packs(stale_token) and wallet.get_queued_pack_count(current_token) == 1, "an old screen cannot refund a new batch after resetting progress")
	wallet.reset_progression()
	wallet.load_currency()
	check(wallet.get_coin_cents() == 2000 and wallet.get_queued_pack_count() == 0, "progress reset permanently clears an unused reservation")
	wallet.reject_save = true
	check(wallet.begin_pack_purchase(500, 3) == 0 and wallet.get_coin_cents() == 2000 and wallet.get_queued_pack_count() == 0, "failed payment save rolls back the entire debit and reservation")
	wallet.reject_save = false
	token = wallet.begin_pack_purchase(500, 3)
	wallet.reject_save = true
	check(not wallet.consume_queued_pack(token) and wallet.get_queued_pack_count(token) == 2, "failed handoff save keeps the next pack refundable")
	check(not wallet.refund_queued_packs(token) and wallet.get_coin_cents() == 500 and wallet.get_queued_pack_count(token) == 2, "failed refund save preserves the complete refund for recovery")
	wallet.load_currency()
	check(wallet.get_coin_cents() == 500 and wallet.get_queued_pack_count() == 2, "failed recovery leaves the stored refund pending")
	wallet.reject_save = false
	wallet.load_currency()
	wallet.load_currency()
	check(wallet.get_coin_cents() == 1500 and wallet.get_queued_pack_count() == 0, "recovery retry credits unused packs exactly once")
	wallet.free()


func _test_screen() -> void:
	GameCurrency.reset_progression(false)
	GameCurrency.coins = 41.0
	CollectionManager.collection = {"cards": {}, "instances": []}
	var original_database := CardDatabase.cards.duplicate(true)
	var fixture_card := CardDatabase.get_card("corpse").duplicate(true)
	CardDatabase.cards.assign([fixture_card])
	var screen := PACK_SCENE.instantiate() as PackOpeningScreen
	add_child(screen)
	screen.pack_appear_duration = 0.05
	screen.pack_disappear_duration = 0.05
	screen.cards_fly_duration = 0.1
	screen.cards_vanish_duration = 0.05
	screen.rarity_camera_shake_multiplier = 0.0
	screen.rarity_pack_shake_multiplier = 0.0
	screen.pack_opening_started.connect(func(): started += 1)
	screen.pack_ready_for_next_purchase.connect(func(): completed += 1)
	screen.pack_batch_progress.connect(func(current: int, total: int): progress.append(Vector2i(current, total)))
	var basic: Dictionary = PackDefinition.PACK_TYPES["basic"].duplicate(true)
	basic["rarity_weights"] = {"common": 1.0}
	check(not screen.buy_pack("basic", basic, 2) and GameCurrency.get_coin_cents() == 4100, "direct batch purchase is locked until level 2")
	GameCurrency.level = 2
	check(not screen.buy_pack("basic", basic, 0) and not screen.buy_pack("basic", basic, -1), "screen rejects invalid quantities")
	check(not screen.buy_pack("basic", basic, 9) and GameCurrency.get_coin_cents() == 4100, "screen rejects nine five-coin packs with a 41-coin balance")
	var reentry: Array[bool] = []
	var callback := func(_coins: float): reentry.append(screen.buy_pack("basic", basic, 2))
	GameCurrency.coins_changed.connect(callback)
	check(screen.buy_pack("basic", basic, 2), "two-pack purchase succeeds through the existing screen API")
	GameCurrency.coins_changed.disconnect(callback)
	check(reentry == [false] and GameCurrency.get_coin_cents() == 3100 and GameCurrency.get_queued_pack_count() == 1, "screen rejects reentry before its synchronous payment signal completes")
	check(started == 1 and completed == 0 and progress == [Vector2i(1, 2)], "batch starts one continuous opening with progress 1/2")
	basic["card_count"] = 99
	for index in range(2):
		check(await _wait_until(func(): return not screen._pack_transitioning and not screen._collecting_cards), "pack %d entrance finishes" % (index + 1))
		check(screen._pack_bought and not screen._opened and screen.card_count == 5 and is_zero_approx(screen._drag_progress), "pack %d has its own fresh sealed foil and original five-card definition" % (index + 1))
		check(not screen.buy_pack("basic", basic, 2), "pack %d cannot be replaced by an additional purchase" % (index + 1))
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(200, 200)
		screen._on_pack_top_input(screen.screen_flash_camera, press, Vector3.ZERO, Vector3.UP, 0)
		var motion := InputEventMouseMotion.new()
		motion.position = press.position + screen._drag_screen_axis * (screen._drag_screen_distance + 50.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		screen._input(motion)
		check(await _wait_until(func(): return screen._card_stack.size() == 5), "pack %d opens through foil dragging and creates exactly five cards" % (index + 1))
		for card in screen._card_stack.duplicate():
			screen._reveal_top_card(card)
		check(await _wait_until(func(): return screen._waiting_for_collect_click), "pack %d waits for collection after revealing its cards" % (index + 1))
		screen._collect_revealed_cards()
		screen._collect_revealed_cards()
		check(CollectionManager.get_amount("corpse") == (index + 1) * 5, "pack %d awards its cards exactly once even with a repeated collect callback" % (index + 1))
		if index == 0:
			check(await _wait_until(func(): return screen._pack_batch_current == 2 and not screen._collecting_cards), "collecting the first pack automatically presents the next paid pack")
			check(completed == 0 and started == 1 and screen._pack_bought and progress == [Vector2i(1, 2), Vector2i(2, 2)], "handoff keeps the shop locked and emits progress 2/2 without another start or ready signal")
			check(GameCurrency.get_coin_cents() == 3100 and GameCurrency.get_queued_pack_count() == 0, "second pack consumes the reservation without a second debit")
		else:
			check(await _wait_until(func(): return not screen._pack_bought and not screen._collecting_cards), "collecting the final pack returns to the normal purchase state")
	check(started == 1 and completed == 1 and GameCurrency.get_coin_cents() == 3100 and CollectionManager.get_amount("corpse") == 10, "complete batch unlocks once, grants ten cards, and charges only ten coins")
	basic["card_count"] = 5
	GameCurrency.coins = 41
	check(screen.buy_pack("basic", basic, 8) and GameCurrency.get_coin_cents() == 100, "eight-pack batch accepts the user's 41-coin example")
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameCurrency.get_coin_cents() == 3600 and GameCurrency.get_queued_pack_count() == 0, "leaving the screen refunds seven unused prepaid packs")
	GameCurrency.load_currency()
	check(GameCurrency.get_coin_cents() == 3600, "reload after a graceful exit does not refund the queue twice")
	CardDatabase.cards = original_database
	CardDatabase.set_pack_rarity_weights({})
