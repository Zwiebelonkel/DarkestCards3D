extends Node

const MANAGER := preload("res://scripts/autoload/AchievementManager.gd")
var checks := 0
var failures := 0


class TestManager:
	extends "res://scripts/autoload/AchievementManager.gd"
	func _ready() -> void:
		pass
	func _steam_available() -> bool:
		return is_instance_valid(_steam)


class FakeSteam:
	extends RefCounted
	signal user_stats_stored(game_id: int, result: int)
	var achieved := {}
	var set_ok := true
	var store_ok := true
	var stores := 0
	var sets: Array[String] = []
	func getAchievement(id: String) -> Dictionary:
		return {"ret": true, "achieved": achieved.has(id)}
	func setAchievement(id: String) -> bool:
		sets.append(id)
		if set_ok:
			achieved[id] = true
		return set_ok
	func storeStats() -> bool:
		stores += 1
		return store_ok


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)


func _manager(file_name: String) -> TestManager:
	var manager := TestManager.new()
	manager.save_path = "res://test-user/" + file_name
	add_child(manager)
	manager.set_process(false)
	return manager


func _run() -> void:
	if not AchievementManager.save_path.begins_with("res://test-user/"):
		push_error("Run through run_collection_tests.ps1 with isolated saves and Steam disabled.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	check(MANAGER.ACHIEVEMENTS.size() == 10 and MANAGER.RARITY_ACHIEVEMENTS.size() == 8,
		"exactly eight rarity achievements and two Satan achievements are registered")
	var steam: Object = Engine.get_singleton("Steam")
	for method in ["getAchievement", "setAchievement", "storeStats"]:
		check(steam.has_method(method), "installed GodotSteam supports " + method)
	var stored_arguments := -1
	for entry: Dictionary in steam.get_signal_list():
		if str(entry["name"]) == "user_stats_stored":
			stored_arguments = entry["args"].size()
	check(stored_arguments == 2, "installed Steam store callback has game ID and result arguments")
	_test_collection()
	await _test_sync()
	print("ACHIEVEMENT_MANAGER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_collection() -> void:
	CollectionManager.clear_profile_state()
	AchievementManager._unlocked.clear()
	AchievementManager._pending.clear()
	var awards: Array[String] = []
	AchievementManager.achievement_unlocked.connect(func(id: String): awards.append(id))
	for rarity: String in CardDatabase.REWARD_RARITIES:
		var card_id := ""
		for card: Dictionary in CardDatabase.get_all_cards():
			if str(card.get("rarity", "")) == rarity and CardData.is_combat_card(card) and CollectionManager.can_obtain_card(str(card["id"])):
				card_id = str(card["id"])
				break
		check(not card_id.is_empty(), "an obtainable fixture exists for " + rarity)
		if card_id.is_empty():
			continue
		var id: String = MANAGER.RARITY_ACHIEVEMENTS[rarity]
		var instance := CollectionManager.roll_card_instance(card_id)
		check(not instance.is_empty() and not AchievementManager.is_unlocked(id),
			"rolling a preview does not unlock " + rarity)
		if rarity == "common":
			var temporary := CollectionManager.SAVE_PATH + ".tmp"
			check(DirAccess.make_dir_absolute(temporary) == OK, "temporarily block the collection's atomic save")
			var failed := CollectionManager.add_card_instance(instance)
			check(failed.is_empty() and not AchievementManager.is_unlocked(id), "a failed acquisition save cannot award an achievement")
			check(DirAccess.remove_absolute(temporary) == OK, "restore collection saving for a retry")
		var before := awards.size()
		var added := CollectionManager.add_card_instance(instance)
		check(not added.is_empty() and AchievementManager.is_unlocked(id) and awards.size() == before + 1,
			"committing the first " + rarity + " card unlocks only its own achievement")
		CollectionManager.add_card_instance(instance)
		CollectionManager.add_card(card_id)
		check(awards.size() == before + 1, "duplicate callbacks and additional " + rarity + " cards never award twice")
	check(awards.size() == 8 and not AchievementManager.is_unlocked(MANAGER.SATAN_PISS),
		"card acquisition awards all eight rarities without awarding Satan interactions")
	var legacy := _manager("achievement-legacy.cfg")
	legacy._on_collection_changed(CollectionManager.get_discovered_card_ids())
	check(legacy._unlocked.size() == 8, "existing collection history backfills every already-acquired rarity")
	legacy.free()
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(AchievementManager._unlocked.size() == 8, "a fresh or reloaded save slot retains achievements")
	var reloaded := _manager("achievements.cfg")
	reloaded._load_state()
	check(reloaded._unlocked.size() == 8 and reloaded._pending.size() == 8, "offline unlocks survive restart for Steam reconciliation")
	reloaded.free()


func _test_sync() -> void:
	var manager := _manager("achievement-sync.cfg")
	var notifications: Array[String] = []
	manager.achievement_synced.connect(func(id: String): notifications.append(id))
	check(not manager.unlock("UNKNOWN") and manager._unlocked.is_empty(), "unknown achievement IDs are rejected")
	manager.record_satan_stream(false)
	check(not manager.is_unlocked(MANAGER.SATAN_PISS), "stopping an effect cannot award the Piss achievement")
	manager.record_satan_stream(true)
	manager.record_satan_stream(true)
	check(manager._unlocked.size() == 1 and manager._pending.size() == 1, "repeated offline Piss triggers queue one unlock")
	var fake := FakeSteam.new()
	manager._steam = fake
	fake.set_ok = false
	manager._connect_steam()
	check(fake.stores == 0 and manager._pending.size() == 1, "a rejected setAchievement stays queued without storing")
	fake.set_ok = true
	fake.store_ok = false
	manager.sync_pending()
	check(fake.stores == 1 and manager._pending.size() == 1 and manager._inflight.is_empty(), "a rejected storeStats keeps the unlock pending")
	fake.store_ok = true
	manager.sync_pending()
	check(fake.stores == 2 and manager._pending.size() == 1, "a locally staged achievement still needs a confirmed Steam store")
	manager.record_satan_jumpscare()
	check(fake.stores == 2 and manager._pending.size() == 2, "an unlock during a store waits for the next batch")
	fake.user_stats_stored.emit(480, 1)
	await get_tree().process_frame
	check(manager._pending.size() == 2 and notifications.is_empty(), "another game's callback cannot confirm our achievements")
	fake.user_stats_stored.emit(NetworkManager.APP_ID, 2)
	await get_tree().process_frame
	check(manager._pending.size() == 2 and notifications.is_empty(), "failed asynchronous storage preserves every pending unlock")
	manager._process(MANAGER.RETRY_SECONDS)
	check(fake.stores == 3 and manager._inflight.size() == 2, "the timed retry submits both pending achievements")
	fake.user_stats_stored.emit(NetworkManager.APP_ID, 1)
	await get_tree().process_frame
	check(manager._pending.is_empty() and notifications.size() == 2, "only Steam's success callback confirms both achievements")
	manager.sync_pending()
	check(fake.stores == 3, "an empty queue never sends redundant Steam writes")
	var restored := _manager("achievement-sync.cfg")
	restored._load_state()
	restored._steam = fake
	restored._connect_steam()
	check(restored._unlocked.size() == 2 and restored._pending.is_empty() and fake.stores == 3,
		"restart merges already-synchronized Steam achievements without another store")
	var remote := _manager("achievement-remote.cfg")
	remote._steam = fake
	remote._connect_steam()
	check(remote.is_unlocked(MANAGER.SATAN_JUMPSCARE) and remote.is_unlocked(MANAGER.SATAN_PISS),
		"Steam ownership is restored when the local achievement file is absent")
	remote.free()
	restored.free()
	manager.free()
