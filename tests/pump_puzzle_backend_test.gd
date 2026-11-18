extends Node

var checks := 0
var failures := 0

class ControlledCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := true
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save

class ControlledWallet:
	extends "res://scripts/GameCurrency.gd"
	func _ready() -> void:
		set_process(false)
	func save() -> bool:
		return true


func check(condition: bool, label: String) -> void:
	checks += 1
	failures += 0 if condition else 1
	print(("PASS " if condition else "FAIL ") + label)


func _ready() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.weed_consumed = false
	var manager := ControlledCollection.new()
	add_child(manager)
	var solution: Array[bool] = [true, false, false, true, false]
	check(manager.claim_pump_puzzle_reward(solution).is_empty(), "even knowing the solution cannot bypass the first-trip gate")
	GameCurrency.weed_consumed = true
	for mask in range(32):
		var combination: Array[bool] = [bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8), bool(mask & 16)]
		if combination != solution:
			check(manager.claim_pump_puzzle_reward(combination).is_empty(), "incorrect switch combination %d cannot award the key" % mask)
	check(manager.claim_pump_puzzle_reward([true, false, false]).is_empty(), "the old three-lever solution cannot award the key")
	var before := manager.collection.duplicate(true)
	check(manager.claim_pump_puzzle_reward(solution).is_empty() and manager.collection == before,
		"a failed acquisition save preserves the entire collection and allows a retry")
	manager.reject_save = false
	var reward := manager.claim_pump_puzzle_reward(solution)
	check(reward.get("card_id") == "toilet_paper" and manager.get_amount("toilet_paper") == 1,
		"retry grants the exact single key after a successful save")
	check(manager.claim_pump_puzzle_reward(solution).is_empty(), "repeated claims cannot duplicate the key")
	manager.collection["cards"].erase("toilet_paper")
	manager.collection["instances"].clear()
	check(manager.claim_pump_puzzle_reward(solution).is_empty(), "historical acquisition also prevents farming after losing the key")
	manager.free()
	var wallet := ControlledWallet.new()
	add_child(wallet)
	wallet.level = 50
	wallet.award_match("win")
	check(not wallet.weed_reward_unlocked, "ordinary wins cannot unlock the package even at player level fifty")
	wallet.story_completed_level = 5
	wallet.award_story_win(6)
	check(not wallet.weed_reward_unlocked, "winning story level six cannot unlock the package")
	wallet.level = 1
	wallet.xp = 0
	wallet.award_story_win(7)
	check(wallet.level < 7 and wallet.weed_reward_unlocked, "winning story level seven unlocks the package independently of player level")
	wallet.reset_progression(false)
	check(wallet.consume_weed_reward(true) and wallet.weed_consumed and wallet.story_completed_level == 0,
		"an admin package can activate the trip without completing story levels")
	wallet.free()
	Localization.set_locale("de")
	check(Localization.text("Toilet Paper") == "Klopapier", "the German card name is Klopapier")
	var data := CardDatabase.get_card("toilet_paper")
	check(CardData.is_unique_unlock(data) and CardData.is_access_key(data) and not CardDatabase._is_random_reward(data),
		"the key is unique, excluded from packs and recognized as a key")
	check(ResourceLoader.exists(str(data.get("image", ""))), "the key has a native, immediately loadable pixel icon")
	print("PUMP_PUZZLE_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
