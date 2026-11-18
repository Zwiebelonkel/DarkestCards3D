extends Node3D

const SHOP_SCENE := preload("res://scenes/UpgradeShop.tscn")

var checks := 0
var failures := 0
var shop: UpgradeMachine
var saved_effects: Array[Dictionary] = []
var hit_seed := -1


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	for path in [SaveSlots.SAVE_ROOT, SaveSlots.LEGACY_ROOT, SaveSlots.REGISTRY_PATH, CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path]:
		if not str(path).begins_with("res://test-user/"):
			push_error("Use the isolated match-feature runner; this suite resets fixture slots 1 and 2.")
			get_tree().quit(1)
			return
	GameCurrency.set_process(false)
	saved_effects = EffectDatabase.effects.duplicate(true)
	if not _select_slot(1):
		_finish()
		return
	for slot in [1, 2]:
		var reset_error: Error = SaveSlots.reset_slot(slot)
		check(reset_error == OK, "clear isolated fixture slot %d" % slot)
		if reset_error != OK:
			_finish()
			return
	for card_id in ["corpse", "corpse", "jd", "piss", "clicker"]:
		check(not CollectionManager.add_card(card_id).is_empty(), "own fixture card " + card_id)
	_set_coins(10000.0)
	var armor := EffectDatabase.get_effect("armor")
	check(not armor.is_empty(), "catalog supplies a genuine non-Lava roll candidate")
	EffectDatabase.effects.assign([armor])
	for candidate_seed in range(100):
		seed(candidate_seed)
		if not EffectDatabase.roll_effects().is_empty():
			hit_seed = candidate_seed
			break
	check(hit_seed >= 0, "a bounded seed search finds a deterministic successful roll")
	if armor.is_empty() or hit_seed < 0:
		_finish()
		return
	_new_shop()
	shop._on_card_selected("corpse")
	_check_prices(5.0, 12.0, "new ordinary card")
	var before := GameCurrency.get_coin_cents()
	shop.ui.attack_button.pressed.emit()
	check(GameCurrency.get_coin_cents() == before - 500 and CardUpgradeManager.get_attack_bonus("corpse") == 1, "real attack button purchases its five-coin stat upgrade")
	_check_prices(10.0, 12.0, "stat purchase leaves the roll price unchanged")
	for cost in [12.0, 24.0, 36.0]:
		_successful_roll(cost, cost + 12.0)
		if cost < 36.0:
			_remove_upgrade()
	check(CollectionManager.get_amount("corpse") == 2 and CardUpgradeManager.get_effect_roll_count("corpse") == 3, "copies of the same card share one card-id roll streak")
	_check_prices(10.0, 48.0, "three successful rolls do not advance stat progression")
	shop._on_card_selected("jd")
	await get_tree().process_frame
	check(shop.selected_card_id == "jd" and shop.ui.selected_card_id == "jd", "deferred upgrade refresh cannot replace a newer card selection")
	_check_prices(5.0, 12.0, "another card keeps its initial prices")
	shop._on_card_selected("corpse")
	_successful_roll(48.0, 60.0)
	check(CardUpgradeManager.get_free_effect_slots("corpse") == 0 and shop.ui.effect_button.disabled, "the real second effect fills the card and disables further rolls")
	_expect_rejected_roll("full effect slots")
	_remove_upgrade()
	_remove_upgrade()
	_paid_miss(60.0, 12.0)
	_check_prices(10.0, 12.0, "paid miss resets only the effect streak")
	_successful_roll(12.0, 24.0)
	_remove_upgrade()
	_set_coins(23.99)
	check(shop.ui.effect_button.disabled, "one cent below the current price disables rolling")
	_expect_rejected_roll("insufficient coins")
	GameCurrency.add_coin_cents(1)
	check(not shop.ui.effect_button.disabled, "exact-price balance immediately enables rolling")
	_successful_roll(24.0, 36.0)
	check(GameCurrency.get_coin_cents() == 0, "exact-price roll leaves a zero balance")
	_remove_upgrade()
	_set_coins(10000.0)
	for card_id in ["", "missing_card", "clicker", "mailman"]:
		shop._on_card_selected(card_id)
		check(shop.ui.effect_button.disabled, "invalid or unowned selection disables its roll button: " + card_id)
		_expect_rejected_roll("invalid or unowned card: " + card_id)
	shop._on_card_selected("jd")
	_successful_roll(12.0, 24.0)
	_remove_upgrade()
	_successful_roll(24.0, 36.0)
	_remove_upgrade()
	_check_piss_prices()
	_check_lava_boundary(armor)
	_check_removed_innate_reload()
	var persisted := CardUpgradeManager.upgrades.duplicate(true)
	check(CardUpgradeManager.save_upgrades(), "save the completed independent upgrade counters")
	CardUpgradeManager.load_upgrades()
	check(CardUpgradeManager.upgrades == persisted, "reload preserves effects, stat counts and effect-roll streaks exactly")
	shop._on_card_selected("corpse")
	_check_prices(9.0, 32.4, "reloaded ordinary card retains its discounted independent prices")
	await _check_slot_isolation()
	_finish()


func _new_shop() -> void:
	GameCurrency._rescued_npcs["angel"] = true
	shop = SHOP_SCENE.instantiate() as UpgradeMachine
	add_child(shop)
	shop.set_process(false)


func _set_coins(amount: float) -> void:
	GameCurrency.coins = amount
	GameCurrency.coins_changed.emit(GameCurrency.coins)
	check(GameCurrency.save(), "persist the isolated test balance")


func _check_prices(stat_cost: float, roll_cost: float, label: String) -> void:
	var card_id := shop.selected_card_id
	check(is_equal_approx(CardUpgradeManager.get_stat_upgrade_cost(card_id), stat_cost) and is_equal_approx(CardUpgradeManager.get_effect_roll_cost(card_id), roll_cost), label + ": manager prices")
	check(shop.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%s SOUL COINS", [GameCurrency.format_coins(stat_cost, true)]) and shop.ui.health_button.text == Localization.format_text("LEBEN +1\n%s SOUL COINS", [GameCurrency.format_coins(stat_cost, true)]) and shop.ui.effect_button.text == Localization.format_text("EFFEKT WÜRFELN\n%s SOUL COINS", [GameCurrency.format_coins(roll_cost, true)]), label + ": all three visible button prices")


func _successful_roll(cost: float, next_cost: float) -> void:
	var card_id := shop.selected_card_id
	var cents_before := GameCurrency.get_coin_cents()
	var count_before := CardUpgradeManager.get_effect_roll_count(card_id)
	var stats_before := CardUpgradeManager.get_stat_upgrade_count(card_id)
	var effects_before := CardUpgradeManager.get_upgrade_effects(card_id).size()
	check(not shop.ui.effect_button.disabled and is_equal_approx(CardUpgradeManager.get_effect_roll_cost(card_id), cost), "%s roll is offered at %.2f coins" % [card_id, cost])
	# No production injection: replay the RNG state found using the real roller.
	seed(hit_seed)
	shop.ui.effect_button.pressed.emit()
	check(GameCurrency.get_coin_cents() == cents_before - roundi(cost * 100.0) and CardUpgradeManager.get_upgrade_effects(card_id).size() == effects_before + 1, "%s successful UI roll charges exactly %.2f and grants one effect" % [card_id, cost])
	check(CardUpgradeManager.get_effect_roll_count(card_id) == count_before + 1 and CardUpgradeManager.get_stat_upgrade_count(card_id) == stats_before, "successful roll advances only this card's effect counter once")
	_check_prices(CardUpgradeManager.get_stat_upgrade_cost(card_id), next_cost, "successful roll updates its next price immediately")


func _remove_upgrade(effect_source: String = "upgrade") -> void:
	var card_id := shop.selected_card_id
	var cents_before := GameCurrency.get_coin_cents()
	var count_before := CardUpgradeManager.get_effect_roll_count(card_id)
	var effects_before := CardUpgradeManager.get_effect_entries(card_id).size()
	var entry_index := -1
	for index in range(shop.ui.effect_entries.size()):
		if str(shop.ui.effect_entries[index].get("source", "")) == effect_source:
			entry_index = index
			break
	check(entry_index >= 0, "an actual %s effect is available for UI removal" % effect_source)
	if entry_index < 0:
		return
	shop.ui.effect_slot_buttons[entry_index].pressed.emit()
	check(not shop.ui.remove_effect_button.disabled, "selecting its effect slot enables the remove button")
	shop.ui.remove_effect_button.pressed.emit()
	check(CardUpgradeManager.get_effect_entries(card_id).size() == effects_before - 1 and GameCurrency.get_coin_cents() == cents_before and CardUpgradeManager.get_effect_roll_count(card_id) == count_before, "effect removal is free and does not reset or advance the roll streak")


func _paid_miss(cost: float, next_cost: float) -> void:
	var card_id := shop.selected_card_id
	var cents_before := GameCurrency.get_coin_cents()
	var effects_before := CardUpgradeManager.get_upgrade_effects(card_id).duplicate(true)
	var stats_before := CardUpgradeManager.get_stat_upgrade_count(card_id)
	var pool := EffectDatabase.effects.duplicate(true)
	EffectDatabase.effects.clear()
	shop.ui.effect_button.pressed.emit()
	EffectDatabase.effects = pool
	check(GameCurrency.get_coin_cents() == cents_before - roundi(cost * 100.0) and CardUpgradeManager.get_upgrade_effects(card_id) == effects_before, "paid empty roll charges its previous price without granting an effect")
	check(CardUpgradeManager.get_effect_roll_count(card_id) == 0 and CardUpgradeManager.get_stat_upgrade_count(card_id) == stats_before, "paid empty roll resets its own effect streak and preserves stat progression")
	_check_prices(CardUpgradeManager.get_stat_upgrade_cost(card_id), next_cost, "empty roll refreshes the cheaper next price immediately")


func _snapshot() -> Dictionary:
	return {"upgrades": CardUpgradeManager.upgrades.duplicate(true), "collection": CollectionManager.collection.duplicate(true), "coins": GameCurrency.get_coin_cents(), "upgrades_file": FileAccess.get_file_as_bytes(CardUpgradeManager.SAVE_PATH), "wallet_file": FileAccess.get_file_as_bytes(GameCurrency.save_path)}


func _expect_rejected_roll(label: String) -> void:
	var before := _snapshot()
	shop._roll_effect()
	check(_snapshot() == before, label + " changes neither money, progression, ownership nor saved bytes")


func _check_piss_prices() -> void:
	shop._on_card_selected("piss")
	_check_prices(25.0, 60.0, "Pisse-Eimer starts at five times both ordinary prices")
	for cost in [25.0, 50.0]:
		var before := GameCurrency.get_coin_cents()
		if cost == 25.0:
			shop.ui.attack_button.pressed.emit()
		else:
			shop.ui.health_button.pressed.emit()
		check(GameCurrency.get_coin_cents() == before - roundi(cost * 100.0), "Pisse-Eimer stat button charges %.2f" % cost)
		_check_prices(cost + 25.0, 60.0, "Pisse-Eimer shares its attack/health progression only")
	_successful_roll(60.0, 120.0)
	_remove_upgrade()
	_successful_roll(120.0, 180.0)
	_remove_upgrade()
	check(not CollectionManager.add_card("dealer_license").is_empty(), "acquire the real ten-percent shop discount")
	_check_prices(67.5, 162.0, "discount applies once after both Pisse-Eimer progressions")
	var before := GameCurrency.get_coin_cents()
	shop.ui.health_button.pressed.emit()
	check(GameCurrency.get_coin_cents() == before - 6750, "discounted Pisse-Eimer stat purchase keeps its half-coin amount")
	_successful_roll(162.0, 216.0)
	_remove_upgrade()
	_paid_miss(216.0, 54.0)
	_check_prices(90.0, 54.0, "Pisse-Eimer miss keeps its multiplier and discount but resets the streak")
	_successful_roll(54.0, 108.0)
	_remove_upgrade()


func _check_lava_boundary(armor: Dictionary) -> void:
	var lava := EffectDatabase.get_effect("lava")
	check(not lava.is_empty(), "Lava remains available in the effect catalog")
	EffectDatabase.effects.assign([lava])
	check(EffectDatabase.get_rollable_effects().is_empty() and EffectDatabase.get_random_effect_weighted().is_empty(), "Lava-only catalog has no random candidates or fallback")
	seed(hit_seed)
	check(EffectDatabase.roll_effects().is_empty(), "a normally successful random roll cannot grant Lava")
	shop._on_card_selected("corpse")
	var before := _snapshot()
	check(not CardUpgradeManager.add_effect("corpse", lava) and _snapshot() == before, "direct upgrade admission rejects Lava without persisting or changing progression")
	var innate := CardData.get_active_effects(CardUpgradeManager.apply_upgrades("piss", CardDatabase.get_card("piss")))
	check(innate.size() == 1 and str(innate[0].get("type", "")) == "lava", "Pisse-Eimer retains innate Lava after purchases, removals and a miss")
	EffectDatabase.effects.assign([armor])


func _check_removed_innate_reload() -> void:
	shop._on_card_selected("piss")
	_remove_upgrade("base")
	check(CardUpgradeManager.get_free_effect_slots("piss") == 2, "removing innate Lava opens both Pisse-Eimer effect slots")
	_successful_roll(108.0, 162.0)
	_successful_roll(162.0, 216.0)
	CardUpgradeManager.load_upgrades()
	shop._on_card_selected("piss")
	var upgraded := CardUpgradeManager.apply_upgrades("piss", CardDatabase.get_card("piss"))
	check(CardUpgradeManager.get_upgrade_effects("piss").size() == 2 and CardUpgradeManager.get_base_effects("piss").is_empty() and not CardData.has_effect(upgraded, "lava"), "reload restores removed innate indices before limiting both purchased effects")
	var remote := NetworkManager._sanitize_remote_card(upgraded)
	check(CardData.get_active_effects(remote).size() == 2 and not CardData.has_effect(remote, "lava"), "network presentation preserves both replacement effects without resurrecting Lava")
	var empty_remote := NetworkManager._sanitize_remote_card({"card_id": "piss", "active_effects": []})
	check(not empty_remote.is_empty() and CardData.get_active_effects(empty_remote).is_empty(), "an explicitly empty remote Pisse-Eimer remains without Lava")
	_check_prices(90.0, 216.0, "removed innate effect and both rolls preserve their reloaded progression")


func _select_slot(slot: int) -> bool:
	var error: Error = SaveSlots.select_slot(slot)
	check(error == OK and SaveSlots.active_slot == slot, "select fixture save slot %d through its public API" % slot)
	return error == OK


func _check_slot_isolation() -> void:
	shop.queue_free()
	await get_tree().process_frame
	var original := CardUpgradeManager.upgrades.duplicate(true)
	if not _select_slot(2):
		return
	check(CardUpgradeManager.get_effect_roll_count("corpse") == 0 and CardUpgradeManager.get_stat_upgrade_count("corpse") == 0 and is_equal_approx(CardUpgradeManager.get_effect_roll_cost("corpse"), 12.0), "fresh slot inherits neither streak, stat progress nor discount")
	check(not CollectionManager.add_card("corpse").is_empty(), "own the same combat id in the second slot")
	_set_coins(100.0)
	_new_shop()
	shop._on_card_selected("corpse")
	_successful_roll(12.0, 24.0)
	shop.queue_free()
	await get_tree().process_frame
	if not _select_slot(1):
		return
	check(CardUpgradeManager.upgrades == original and CardUpgradeManager.get_effect_roll_count("piss") == 3 and is_equal_approx(CardUpgradeManager.get_effect_roll_cost("piss"), 216.0), "returning restores the first slot's full counters and discounted Pisse-Eimer price")
	if not _select_slot(2):
		return
	CardUpgradeManager.load_upgrades()
	check(CardUpgradeManager.get_effect_roll_count("corpse") == 1 and CardUpgradeManager.get_stat_upgrade_count("corpse") == 0 and is_equal_approx(CardUpgradeManager.get_effect_roll_cost("corpse"), 24.0), "second slot preserves its own one-roll streak across switch and reload")


func _finish() -> void:
	EffectDatabase.effects = saved_effects
	print("EFFECT_UPGRADE_COST_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
