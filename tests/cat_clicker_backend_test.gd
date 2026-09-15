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
	if not SaveSlots.SAVE_ROOT.begins_with("res://test-user/") or GameCurrency.get("refuse_saves") == null:
		push_error("Use run_cat_clicker_backend_tests.ps1 to isolate all player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_departure()
	_check_save_failure()
	_check_timing()
	_check_rewards()
	_check_profiles()
	await _check_pause()
	print("CAT_CLICKER_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _reset(clicker: bool = false, activate: bool = false) -> void:
	GameCurrency.set("refuse_saves", false)
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	GameCurrency.reset_progression()
	if clicker:
		CollectionManager.add_card("clicker")
	if activate:
		GameCurrency.resolve_basement_cat_choice("spared")
		GameCurrency.mark_basement_cat_left()

func _check_departure() -> void:
	_reset()
	check(not GameCurrency.mark_basement_cat_left(), "an undecided cat cannot leave the basement")
	GameCurrency.resolve_basement_cat_choice("shot")
	check(not GameCurrency.mark_basement_cat_left() and not GameCurrency.is_cat_clicker_active(), "a shot cat never becomes a helper")
	_reset()
	GameCurrency.resolve_basement_cat_choice("spared")
	check(not GameCurrency.is_cat_clicker_active(), "sparing alone leaves the cat in the basement")
	check(GameCurrency.mark_basement_cat_left() and GameCurrency.has_basement_cat_left(), "leaving is recorded while Clicker remains locked")
	check(not GameCurrency.is_cat_clicker_active(), "departure does not bypass the Clicker card")
	GameCurrency.advance_cat_clicker(20.0)
	check(GameCurrency.get_coin_cents() == 2000 and GameCurrency.get_cat_clicker_frame() == 0, "locked helper accumulates neither coins nor frame time")
	GameCurrency.reload_profile()
	check(GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active(), "locked departure survives a reload")
	var persisted: Array[bool] = []
	var listener := func(active: bool):
		var cfg := ConfigFile.new()
		cfg.load(GameCurrency.save_path)
		persisted.append(active and cfg.get_value("basement", "cat_left", false))
	GameCurrency.cat_clicker_changed.connect(listener)
	CollectionManager.add_card("clicker")
	GameCurrency.cat_clicker_changed.disconnect(listener)
	check(GameCurrency.is_cat_clicker_active() and persisted == [true], "unlock activates the already departed cat against durable state")
	check(not GameCurrency.mark_basement_cat_left(), "repeated room exits cannot restart or resave departure")
	_reset(true)
	check(not GameCurrency.is_cat_clicker_active(), "owned Clicker without a spared cat grants no helper")
	GameCurrency.resolve_basement_cat_choice("spared")
	check(not GameCurrency.is_cat_clicker_active(), "spared cat waits for the first completed basement departure")
	check(GameCurrency.mark_basement_cat_left() and GameCurrency.is_cat_clicker_active(), "spare plus departure plus owned Clicker activates the helper")

func _check_save_failure() -> void:
	_reset(true)
	GameCurrency.resolve_basement_cat_choice("spared")
	var before := FileAccess.get_file_as_string(GameCurrency.save_path)
	var events: Array[bool] = []
	var listener := func(active: bool): events.append(active)
	GameCurrency.cat_clicker_changed.connect(listener)
	GameCurrency.set("refuse_saves", true)
	check(not GameCurrency.mark_basement_cat_left(), "failed departure persistence returns failure")
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active(), "failed departure rolls back memory and helper activation")
	check(events.is_empty() and FileAccess.get_file_as_string(GameCurrency.save_path) == before, "failed save publishes no activation and preserves the original file")
	GameCurrency.set("refuse_saves", false)
	var nested: Array[bool] = []
	var reentrant := func(active: bool):
		if active:
			nested.append(GameCurrency.mark_basement_cat_left())
	GameCurrency.cat_clicker_changed.connect(reentrant)
	check(GameCurrency.mark_basement_cat_left(), "departure succeeds after storage recovers")
	GameCurrency.cat_clicker_changed.disconnect(reentrant)
	GameCurrency.cat_clicker_changed.disconnect(listener)
	check(events == [true] and nested == [false], "successful departure emits once and rejects callback reentry")
	GameCurrency.reload_profile()
	check(GameCurrency.has_basement_cat_left() and GameCurrency.is_cat_clicker_active(), "successful departure is restored after restart")

func _check_timing() -> void:
	_reset(true, true)
	var frames: Array[int] = []
	var pulses: Array[int] = []
	var on_frame := func(frame: int): frames.append(frame)
	var on_click := func(): pulses.append(GameCurrency.get_coin_cents())
	GameCurrency.cat_clicker_frame_changed.connect(on_frame)
	GameCurrency.cat_clicker_clicked.connect(on_click)
	for delta in [0.0, -1.0, INF, NAN]:
		GameCurrency.advance_cat_clicker(delta)
	check(GameCurrency.get_coin_cents() == 2000 and frames.is_empty(), "invalid or nonpositive frame deltas cannot award income")
	GameCurrency.advance_cat_clicker(1.0 / 3.0)
	check(GameCurrency.get_cat_clicker_frame() == 1 and GameCurrency.get_coin_cents() == 2000, "second sprite appears before any click")
	GameCurrency.advance_cat_clicker(1.0 / 3.0)
	check(GameCurrency.get_cat_clicker_frame() == 2 and GameCurrency.get_coin_cents() == 2002, "third sprite pays exactly one manual click")
	GameCurrency.advance_cat_clicker(0.1)
	check(GameCurrency.get_cat_clicker_frame() == 2 and GameCurrency.get_coin_cents() == 2002, "remaining on the click sprite never pays twice")
	GameCurrency.advance_cat_clicker(1.0 / 3.0 - 0.1)
	check(GameCurrency.get_cat_clicker_frame() == 0 and GameCurrency.get_coin_cents() == 2002, "loop restart does not create another click")
	GameCurrency.set("save_count", 0)
	GameCurrency.advance_cat_clicker(100.0)
	check(GameCurrency.get_coin_cents() == 2202 and GameCurrency.get_cat_clicker_frame() == 0, "a long frame counts every third-frame crossing exactly once")
	check(GameCurrency.get("save_count") == 1 and pulses.size() == 2, "long frames batch wallet persistence and UI pulses")
	check(frames == [1, 2, 0], "frame signal reports only visible frame changes")
	GameCurrency.cat_clicker_frame_changed.disconnect(on_frame)
	GameCurrency.cat_clicker_clicked.disconnect(on_click)
	GameCurrency.advance_cat_clicker(0.5)
	var before := GameCurrency.get_coin_cents()
	GameCurrency.reload_profile()
	check(GameCurrency.get_cat_clicker_frame() == 0 and GameCurrency.get_coin_cents() == before, "reload resets animation time without offline income")
	GameCurrency.advance_cat_clicker(0.5)
	check(GameCurrency.get_coin_cents() == before, "reload discards partial time instead of resuming toward an early click")
	CollectionManager.clear_profile_state()
	var changed_ids: Array[String] = ["clicker"]
	CollectionManager.collection_changed.emit(changed_ids)
	check(not GameCurrency.is_cat_clicker_active() and GameCurrency.get_cat_clicker_frame() == 0, "loss of the required Clicker resets and deactivates the clock")
	GameCurrency.advance_cat_clicker(10.0)
	check(GameCurrency.get_coin_cents() == before, "inactive helpers award no accumulated income")

func _check_rewards() -> void:
	_reset(true, true)
	for id in ["clicker_upgrade", "clicker_upgrade", "golden_clicker", "soulcoin_boost_1"]:
		CollectionManager.add_card(id)
	check(is_equal_approx(GameCurrency.get_manual_click_base_reward(), 0.09), "fixture includes two upgrades and the Golden Clicker bonus")
	GameCurrency.advance_cat_clicker(50.0)
	check(GameCurrency.get_coin_cents() == 2459, "50 helper clicks apply the 2 percent boost once and retain fractional cents")
	var cat_cents := GameCurrency.get_coin_cents()
	var cat_remainder := float(GameCurrency.get("_coin_reward_remainder"))
	GameCurrency.coins = 20.0
	GameCurrency.set("_coin_reward_remainder", 0.0)
	for _index in range(50):
		GameCurrency.award_manual_click()
	check(GameCurrency.get_coin_cents() == cat_cents and is_equal_approx(GameCurrency.get("_coin_reward_remainder"), cat_remainder), "batched cat income matches repeated manual clicks exactly")
	CollectionManager.add_card("auto_clicker")
	var before := GameCurrency.get_coin_cents()
	GameCurrency.advance_auto_clicker(50.0)
	GameCurrency.advance_cat_clicker(50.0)
	check(GameCurrency.get_coin_cents() - before == 561, "Auto Clicker and the cat award their separate boosted income together")
	GameCurrency.advance_cat_clicker(2.0 / 3.0)
	GameCurrency.reset_progression()
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active() and GameCurrency.get_cat_clicker_frame() == 0, "progression reset removes helper state and frame progress")

func _check_profiles() -> void:
	_reset(true, true)
	GameCurrency.advance_cat_clicker(0.5)
	var events: Array[bool] = []
	var listener := func(active: bool): events.append(active)
	GameCurrency.cat_clicker_changed.connect(listener)
	check(SaveSlots.select_slot(2) == OK, "second isolated slot can be selected")
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active() and events == [false], "profile switch publishes inactive state without leaking the old helper")
	check(SaveSlots.select_slot(1) == OK, "original isolated slot can be restored")
	check(GameCurrency.is_cat_clicker_active() and GameCurrency.get_cat_clicker_frame() == 0 and events == [false, true], "restoring a slot publishes its helper and starts a fresh animation")
	GameCurrency.cat_clicker_changed.disconnect(listener)
	var cfg := ConfigFile.new()
	cfg.set_value("basement", "cat_choice", "spared")
	cfg.save(GameCurrency.save_path)
	GameCurrency.reload_profile()
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active(), "legacy spared saves wait for their next basement departure")
	cfg.set_value("basement", "cat_choice", "shot")
	cfg.set_value("basement", "cat_left", true)
	cfg.save(GameCurrency.save_path)
	GameCurrency.reload_profile()
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active(), "invalid saved departure never revives a shot cat")

func _check_pause() -> void:
	_reset(true, true)
	GameCurrency.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.8, true).timeout
	check(GameCurrency.get_coin_cents() == 2000 and GameCurrency.get_cat_clicker_frame() == 0, "SceneTree pause stops the shared helper clock")
	get_tree().paused = false
	GameCurrency.set_process(false)
