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
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not SaveSlots.SAVE_ROOT.begins_with("res://test-user/") or CollectionManager.get("test_day") == null:
		push_error("Run this test with run_black_market_backend_tests.ps1 to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_rotation_and_pool()
	_check_purchase()
	_check_save_failures()
	_check_interrupted_transactions()
	_check_profiles()
	print("BLACK_MARKET_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _reset() -> void:
	CollectionManager.set("refuse_saves", false)
	CollectionManager.set("test_day", "2035-06-14")
	GameCurrency.set("fail_on_save", 0)
	CollectionManager.clear_profile_state()
	CollectionManager.collection["metadata"]["area_access"] = {"black_market": true}
	CollectionManager.save_collection()
	GameCurrency.clear_profile_state()
	GameCurrency.coins = 2000.0
	GameCurrency.save()
	GameCurrency.set("save_calls", 0)

func _first() -> Dictionary:
	return CollectionManager.get_black_market_offers()["offers"][0]

func _buy(offer: Dictionary = {}) -> Dictionary:
	if offer.is_empty():
		offer = _first()
	return CollectionManager.purchase_black_market_offer(CollectionManager.get_black_market_day(), str(offer["offer_id"]))

func _check_rotation_and_pool() -> void:
	_reset()
	var pool := CollectionManager.get_black_market_pool()
	check(pool.size() >= 4 and not pool.has("slot_room_key") and not pool.has("black_market_access") and not pool.has("graveyard_key"), "market excludes keys, access cards and discovery-only unlocks")
	var discovery := CardDatabase.get_card("corpse").duplicate(true)
	discovery["id"] = "market_test_discovery"
	discovery["random_reward"] = false
	CardDatabase.cards.append(discovery)
	CardDatabase.cards_by_id[discovery["id"]] = discovery
	check(not CollectionManager.get_black_market_pool().has(str(discovery["id"])), "even combat cards with an acquisition-only flag never enter the market")
	CardDatabase.cards.erase(discovery)
	CardDatabase.cards_by_id.erase(discovery["id"])
	var valid := true
	for card_id: String in pool:
		var card := CardDatabase.get_card(card_id)
		valid = valid and CardData.is_combat_card(card) and card.get("random_reward", true) != false and str(card.get("rarity", "")) != "secret" and not CardDatabase.is_event_card(card)
	check(valid, "every market card is an eligible combat reward outside Secret rarity")
	seed(93271)
	var expected_random := randi()
	seed(93271)
	var board := CollectionManager.get_black_market_offers()
	check(randi() == expected_random, "reading offers does not consume the shared combat/pack RNG")
	var identities := {}
	for offer: Dictionary in board["offers"]:
		identities[offer["card_id"]] = true
	check(board["offers"].size() == 4 and identities.size() == 4, "each day contains four distinct cards")
	check(CollectionManager.get_black_market_offers() == board, "reopening a board never rerolls the daily stock")
	CollectionManager.reload_profile()
	check(CollectionManager.get_black_market_offers() == board, "saved profile reload keeps the same daily stock")
	var before_discount := CollectionManager.get_black_market_offers()
	CollectionManager.add_card("dealer_license")
	check(CollectionManager.get_shop_discount() > 0.0 and CollectionManager.get_black_market_offers() == before_discount, "Dealer License never discounts or rerolls Black Market prices")
	CollectionManager.set("test_day", "2035-06-15")
	check(CollectionManager.get_black_market_offers() != board, "the next local calendar day rotates the board")
	var coins_before := GameCurrency.get_coin_cents()
	check(CollectionManager.purchase_black_market_offer(str(board["day"]), str(board["offers"][0]["offer_id"]))["reason"] == "stale" and GameCurrency.get_coin_cents() == coins_before, "a board left open over midnight cannot purchase yesterday's offer")
	CollectionManager.set("test_day", "2035-06-14")
	var detached := CollectionManager.get_black_market_offers()
	detached["offers"][0]["price_cents"] = 1
	check(CollectionManager.get_black_market_offers() == board, "callers cannot mutate displayed prices or backend stock")

func _check_purchase() -> void:
	_reset()
	var offer := _first()
	CollectionManager.collection["metadata"]["area_access"] = {}
	check(_buy(offer)["reason"] == "locked", "direct purchase API requires permanent Black Market access")
	CollectionManager.collection["metadata"]["area_access"] = {"black_market": true}
	GameCurrency.coins = 0.0
	check(_buy(offer)["reason"] == "insufficient_funds" and not _first()["sold"], "unaffordable purchases do not consume stock")
	GameCurrency.coins = 2000.0
	GameCurrency.save()
	check(CollectionManager.purchase_black_market_offer(CollectionManager.get_black_market_day(), "offer_0_forged")["reason"] == "invalid_offer", "forged offer identities are rejected")
	var before := GameCurrency.get_coin_cents()
	var nested: Array[Dictionary] = []
	var seen: Array[bool] = []
	var listener := func(_coins: float):
		nested.append(_buy(offer))
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH))
		seen.append(saved["metadata"].get("black_market_purchases", {}).has(CollectionManager.get_black_market_day() + ":" + str(offer["offer_id"])))
	GameCurrency.coins_changed.connect(listener)
	var purchase := _buy(offer)
	GameCurrency.coins_changed.disconnect(listener)
	check(purchase["ok"] and GameCurrency.get_coin_cents() == before - int(offer["price_cents"]), "successful purchase debits the exact displayed price once")
	check(nested.size() == 1 and nested[0]["reason"] == "busy" and seen == [true], "synchronous wallet listeners see durable card ownership and cannot reenter purchase")
	check(CollectionManager.get_amount(str(offer["card_id"])) == 1 and CollectionManager.has_discovered_card(str(offer["card_id"])), "purchase adds and discovers exactly one owned card")
	var instance: Dictionary = purchase["instance"]
	check(not str(instance["instance_id"]).is_empty() and purchase["card_data"]["instance_id"] == instance["instance_id"] and instance["level"] == 1, "the returned card contains the exact acquired instance")
	check(_first()["sold"] and _buy(offer)["reason"] == "sold", "a repeated click cannot buy today's sold offer again")
	CollectionManager.reload_profile()
	GameCurrency.load_currency()
	check(_first()["sold"] and _buy(offer)["reason"] == "sold" and GameCurrency.get_coin_cents() == before - int(offer["price_cents"]), "reload preserves stock and price without a second debit")
	CollectionManager.set("test_day", "2035-06-15")
	var available := true
	for next_offer: Dictionary in CollectionManager.get_black_market_offers()["offers"]:
		available = available and not bool(next_offer["sold"])
	check(available, "new-day stock starts unsold")
	CollectionManager.set("test_day", "2035-06-14")
	check(_first()["sold"], "returning the clock to an older day does not restock purchased offers")

func _check_save_failures() -> void:
	_reset()
	var before := GameCurrency.get_coin_cents()
	GameCurrency.set("fail_on_save", 1)
	check(_buy()["reason"] == "save_failed" and GameCurrency.get_coin_cents() == before and not _first()["sold"], "failed currency reservation preserves coins and stock")
	GameCurrency.set("fail_on_save", 0)
	CollectionManager.set("refuse_saves", true)
	check(_buy()["reason"] == "save_failed" and GameCurrency.get_coin_cents() == before and CollectionManager.get_card_instances().is_empty(), "failed collection commit fully refunds without granting a card")
	GameCurrency.set("save_calls", 0)
	GameCurrency.set("fail_on_save", 2)
	check(_buy()["reason"] == "save_failed" and GameCurrency.get_coin_cents() == before, "even a failed refund write leaves the full balance available in memory")
	CollectionManager.set("refuse_saves", false)
	GameCurrency.set("fail_on_save", 0)
	GameCurrency.load_currency()
	GameCurrency.load_currency()
	check(GameCurrency.get_coin_cents() == before and CollectionManager.get_card_instances().is_empty() and not _first()["sold"], "reload recovers an unwritten refund exactly once")
	GameCurrency.set("save_calls", 0)
	GameCurrency.set("fail_on_save", 2)
	var offer := _first()
	check(_buy(offer)["ok"], "a committed purchase remains successful when wallet cleanup cannot be written")
	GameCurrency.set("fail_on_save", 0)
	CollectionManager.reload_profile()
	GameCurrency.load_currency()
	GameCurrency.load_currency()
	check(GameCurrency.get_coin_cents() == before - int(offer["price_cents"]) and CollectionManager.get_amount(str(offer["card_id"])) == 1 and _first()["sold"], "receipt recovery neither refunds a committed purchase nor duplicates the acquired card")

func _check_interrupted_transactions() -> void:
	_reset()
	var before := GameCurrency.get_coin_cents()
	var offer := _first()
	var identity := CollectionManager.get_black_market_day() + ":" + str(offer["offer_id"])
	check(GameCurrency.begin_black_market_purchase(identity, int(offer["price_cents"])), "interrupted purchase fixture reserves a durable debit")
	GameCurrency.load_currency()
	GameCurrency.load_currency()
	check(GameCurrency.get_coin_cents() == before and not _first()["sold"] and CollectionManager.get_card_instances().is_empty(), "closing after debit but before collection commit recovers all coins without consuming stock")

func _check_profiles() -> void:
	_reset()
	var offer := _first()
	check(_buy(offer)["ok"], "first profile buys its daily offer")
	var first_balance := GameCurrency.get_coin_cents()
	check(SaveSlots.select_slot(2) == OK, "a different save profile can be selected")
	check(not _first()["sold"] and not CollectionManager.has_area_access("black_market"), "new profile inherits neither daily purchases nor area access")
	check(SaveSlots.select_slot(1) == OK and _first()["sold"] and GameCurrency.get_coin_cents() == first_balance, "returning to the original profile restores its sold stock and wallet")
	check(SaveSlots.reset_slot(1) == OK and not _first()["sold"], "resetting a profile clears its purchase receipts")
