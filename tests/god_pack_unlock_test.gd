extends Node3D

const SHOP_SCENE := preload("res://scenes/PackShopMachine.tscn")

var checks := 0
var failures := 0
var purchases := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _set_coins(amount: float) -> void:
	GameCurrency.coins = amount
	GameCurrency.coins_changed.emit(GameCurrency.coins)


func _capture_ui(shop: PackShopMachine, stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	shop.pack_shop_viewport.get_texture().get_image().save_png("res://god-pack-%s.png" % stage)


func _run() -> void:
	if not DeckManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run god_pack_unlock_test.tscn through run_match_feature_tests.ps1 to isolate player saves.")
		get_tree().quit(1)
		return
	GameCurrency.level = 9
	GameCurrency.xp = 0
	_set_coins(100.0)
	var shop := SHOP_SCENE.instantiate() as PackShopMachine
	add_child(shop)
	var ui := shop.ui
	var screen := shop.pack_opening_screen
	screen.pack_opening_started.connect(func(): purchases += 1)
	var god_data: Dictionary = PackDefinition.PACK_TYPES["god"].duplicate(true)
	var cost := int(god_data["cost"])
	var collection_before := CollectionManager.collection.duplicate(true)
	var weights_before := CardDatabase._current_pack_weights.duplicate(true)
	var preview := ui.pack_previews["god"] as PackPreviewViewport
	check(PackDefinition.get_minimum_level("god") == 10 and PackShopMachine.PACK_TYPES["god"]["minimum_level"] == 10, "God purchase requirement comes from the shared level-10 definition")
	check(PackDefinition.is_unlocked("basic", 1) and PackDefinition.is_unlocked("ultra", 1), "Basic and Ultra remain available at the starting level")
	check(preview.pack_model != null and not preview._locked and preview.state_label.text == "AB LEVEL 10", "Locked God preview keeps its model visible and displays the level requirement")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	preview._gui_input(click)
	check(ui.selected_pack_id == "god" and ui.info_title_label.text == "GOD PACK", "Level-9 player can select God to inspect its details")
	check(ui.buy_button.disabled and ui.buy_button.text == "AB LEVEL 10 VERFÜGBAR" and ui.message_label.text.contains("DEIN LEVEL: 9"), "God purchase controls explain the level-9 lock despite sufficient coins")
	await _capture_ui(shop, "locked")
	ui._on_buy_button_pressed()
	shop._on_pack_buy_pressed("god")
	check(purchases == 0 and is_equal_approx(GameCurrency.coins, 100.0), "UI handler and machine purchase entry point both reject level-9 purchases without payment")
	check(not screen.buy_pack("god", god_data), "Direct purchase API rejects God below level 10")
	var forged_data := god_data.duplicate(true)
	forged_data.erase("minimum_level")
	check(not screen.buy_pack("god", forged_data), "Omitting minimum_level cannot bypass the direct purchase guard")
	forged_data["minimum_level"] = 1
	check(not screen.buy_pack("god", forged_data), "Lowering supplied minimum_level cannot bypass the canonical definition")
	check(not screen._pack_bought and not screen._opened and not screen.pack.visible and not screen.pack_top_area.input_ray_pickable, "Rejected God purchases cannot display or open a bought pack")
	check(purchases == 0 and is_equal_approx(GameCurrency.coins, 100.0) and CollectionManager.collection == collection_before and CardDatabase._current_pack_weights == weights_before, "Every rejected path preserves money, collection, rewards and rarity configuration")
	GameCurrency.add_xp(GameCurrency.get_xp_required())
	check(GameCurrency.get_level() == 10 and not ui.buy_button.disabled and preview.state_label.text == "AUSGEWÄHLT", "Actual XP level-up unlocks the selected God pack immediately without reopening the shop")
	check(not ui.message_label.text.contains("AB LEVEL"), "Level-up clears the earlier lock message immediately")
	await _capture_ui(shop, "unlocked")
	_set_coins(float(cost) - 0.01)
	check(ui.buy_button.disabled and ui.buy_button.text == "ZU WENIG COINS", "Level 10 still requires the full God pack price")
	check(not screen.buy_pack("god", god_data) and is_equal_approx(GameCurrency.coins, float(cost) - 0.01), "Under-price direct purchase leaves the balance unchanged at level 10")
	_set_coins(cost)
	check(not ui.buy_button.disabled, "Exactly the God pack price is sufficient at level 10")
	GameCurrency.reset_progression(false)
	_set_coins(100.0)
	check(ui.selected_pack_id == "god" and ui.buy_button.disabled and preview.state_label.text == "AB LEVEL 10", "Progress reset immediately re-locks God while retaining the inspected selection")
	check(not screen.buy_pack("god", god_data) and is_equal_approx(GameCurrency.coins, 100.0), "Reset progression also re-locks the direct purchase API")
	GameCurrency.level = 9
	GameCurrency.xp = 0
	GameCurrency.add_xp(GameCurrency.get_xp_required())
	_set_coins(cost)
	ui._on_buy_button_pressed()
	check(purchases == 1 and is_equal_approx(GameCurrency.coins, 0.0) and screen._pack_bought and ui.locked, "Unlocked UI purchase charges exactly once and enters the existing paid-pack flow")
	check(not screen._opened and CollectionManager.collection == collection_before, "Successful payment still waits for foil opening before awarding cards")
	var deadline := Time.get_ticks_msec() + 3000
	while screen._pack_transitioning and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not screen._pack_transitioning and screen.pack_top_area.input_ray_pickable and screen.pack.visible, "Purchased God pack completes its existing entrance and enables foil interaction")
	shop.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("GOD_PACK_UNLOCK_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)
