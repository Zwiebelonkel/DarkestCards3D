extends Node3D

const SHOP_SCENE := preload("res://scenes/PackShopMachine.tscn")

var checks := 0
var failures := 0
var purchase_signals := 0
var ready_signals := 0
var shop: PackShopMachine
var ui: PackShopUI
var screen: PackOpeningScreen


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


func _set_coins(amount: float) -> void:
	GameCurrency.coins = amount
	GameCurrency.coins_changed.emit(amount)


func _click_button(button: Button) -> void:
	# Hit the rendered 3D screen mesh at the control's actual pixel position,
	# then use the machine's production world-to-SubViewport input forwarding.
	var uv := button.get_global_rect().get_center() / Vector2(shop.pack_shop_viewport.size)
	var mesh_size := (shop.screen_mesh.mesh as QuadMesh).size
	var world_hit := shop.screen_mesh.to_global(Vector3((uv.x - 0.5) * mesh_size.x, (0.5 - uv.y) * mesh_size.y, 0.0))
	var forwarder := shop.get_node("PackShopScreenInput") as PackShopScreenInput
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(400, 300)
	forwarder._on_screen_input_event(screen.screen_flash_camera, motion, world_hit, Vector3.FORWARD, 0)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = motion.position
		forwarder._on_screen_input_event(screen.screen_flash_camera, click, world_hit, Vector3.FORWARD, 0)
	await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(shop.pack_shop_viewport.get_texture().get_image().save_png("res://pack-quantity-%s.png" % stage) == OK, "shop screenshot saved: " + stage)


func _run() -> void:
	if not DeckManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run pack_quantity_test through run_match_feature_tests.ps1 to isolate player saves.")
		get_tree().quit(1)
		return
	GameCurrency.reset_progression(false)
	_set_coins(41.0)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var original_database := CardDatabase.cards.duplicate(true)
	CardDatabase.cards.assign([CardDatabase.get_card("corpse").duplicate(true)])
	shop = SHOP_SCENE.instantiate() as PackShopMachine
	add_child(shop)
	ui = shop.ui
	screen = shop.pack_opening_screen
	screen.pack_opening_started.connect(func(): purchase_signals += 1)
	screen.pack_ready_for_next_purchase.connect(func(): ready_signals += 1)
	screen.base_shake_strength = 0.0
	screen.base_shake_rotation_strength = 0.0
	screen.rarity_camera_shake_multiplier = 0.0
	screen.rarity_pack_shake_multiplier = 0.0
	var camera := screen.get_node("Camera3D") as Camera3D
	camera.current = true
	screen.screen_flash_camera = camera
	await get_tree().process_frame
	await get_tree().process_frame
	check(not ui.quantity_controls.visible and ui.get_purchase_quantity() == 1, "level 1 hides both quantity buttons and starts with one pack")
	await _capture("level-1")
	GameCurrency.add_xp(GameCurrency.get_xp_required())
	_set_coins(41.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameCurrency.level == 2 and ui.quantity_controls.visible, "actual level-up immediately reveals quantity controls")
	check(ui.decrease_button.disabled and not ui.increase_button.disabled, "one pack is the minimum and a second is affordable")
	await _click_button(ui.decrease_button)
	check(ui.get_purchase_quantity() == 1, "disabled minus cannot reduce the minimum below one pack")
	var buy_rect := ui.buy_button.get_global_rect()
	var controls_rect := ui.quantity_controls.get_global_rect()
	check(is_equal_approx(buy_rect.size.y, controls_rect.size.y) and is_equal_approx(buy_rect.position.y, controls_rect.position.y), "quantity column matches purchase button height and vertical alignment")
	check(controls_rect.end.x < buy_rect.position.x and ui.increase_button.global_position.y < ui.decrease_button.global_position.y, "plus sits above minus immediately left of purchase")
	check(ui.increase_button.size.x <= 45.0 and ui.increase_button.size.y <= 32.0, "quantity buttons remain small")
	var active_color := (ui.increase_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var disabled_color := (ui.increase_button.get_theme_stylebox("disabled") as StyleBoxFlat).bg_color
	check(active_color.r > active_color.g * 2.0 and disabled_color.r < active_color.r, "quantity buttons are red with a darker disabled background")
	check(ui.increase_button.get_theme_color("font_color").is_equal_approx(Color.WHITE) and ui.decrease_button.get_theme_color("font_disabled_color").is_equal_approx(Color.WHITE), "both active and disabled symbols use white text")
	for index in range(7):
		await _click_button(ui.increase_button)
	check(ui.get_purchase_quantity() == 8 and ui.buy_button.text == _purchase_caption(8, 40), "seven physical screen clicks select eight packs for 40 coins")
	check(ui.increase_button.disabled and not ui.buy_button.disabled, "41 coins can buy eight packs but cannot enable a ninth")
	await _click_button(ui.increase_button)
	check(ui.get_purchase_quantity() == 8 and is_equal_approx(GameCurrency.coins, 41.0), "disabled plus ignores real clicks without spending coins")
	await _capture("8-packs-limit")
	await _click_button(ui.decrease_button)
	check(ui.get_purchase_quantity() == 7 and ui.buy_button.text == _purchase_caption(7, 35) and not ui.increase_button.disabled, "minus lowers the total and enables adding a pack again")
	await _click_button(ui.increase_button)
	_set_coins(45.0)
	check(not ui.increase_button.disabled, "balance reaching the next total enables plus immediately")
	_set_coins(41.0)
	check(ui.increase_button.disabled, "balance dropping below the next total disables plus again")
	ui._on_pack_preview_pressed("ultra")
	await get_tree().process_frame
	check(ui.get_purchase_quantity() == 1 and ui.buy_button.text == _purchase_caption(1, 20), "switching pack type resets quantity and uses its own price")
	await _click_button(ui.increase_button)
	check(ui.get_purchase_quantity() == 2 and ui.buy_button.text == _purchase_caption(2, 40) and ui.increase_button.disabled, "two Ultra packs also use their correct combined cost")
	ui._on_pack_preview_pressed("god")
	check(ui.buy_button.disabled and ui.increase_button.disabled and PackDefinition.get_minimum_level("god") == 10 and ui.buy_button.text == PackDefinition.get_unlock_message("god"), "multi-buy cannot bypass God Pack's level requirement")
	ui._on_pack_preview_pressed("basic")
	await get_tree().process_frame
	await _click_button(ui.increase_button)
	check(ui.get_purchase_quantity() == 2 and ui.buy_button.text == _purchase_caption(2, 10), "two Basic packs display the requested quantity and total")
	await _capture("2-packs")
	await _click_button(ui.buy_button)
	check(purchase_signals == 1 and is_equal_approx(GameCurrency.coins, 31.0) and ui.locked, "one purchase click charges both packs once and locks the shop")
	check(ui.get_purchase_quantity() == 2 and ui.increase_button.disabled and ui.decrease_button.disabled, "quantity stays fixed during the prepaid opening")
	await _click_button(ui.buy_button)
	await _click_button(ui.increase_button)
	check(purchase_signals == 1 and is_equal_approx(GameCurrency.coins, 31.0), "clicks during opening cannot start or charge another purchase")
	check(await _wait_until(func(): return screen._pack_bought and not screen._pack_transitioning), "first purchased foil becomes ready")
	await _open_and_collect(1)
	check(await _wait_until(func(): return screen._pack_bought and not screen._opened and not screen._pack_transitioning and not screen._collecting_cards), "second paid pack appears automatically after first collection")
	check(ready_signals == 0 and ui.locked and purchase_signals == 1, "between packs the shop and screen focus remain locked without a new purchase")
	check(is_zero_approx(screen._drag_progress) and screen.pack_top_area.input_ray_pickable, "second pack has fresh sealed foil and working input")
	check(is_equal_approx(GameCurrency.coins, 31.0), "automatic next pack never deducts more coins")
	await _open_and_collect(2)
	check(await _wait_until(func(): return not screen._pack_bought and not screen._collecting_cards), "second collection finishes the batch")
	check(ready_signals == 1 and not ui.locked and purchase_signals == 1, "only the completed batch unlocks the shop exactly once")
	check(CollectionManager.get_amount("corpse") == 10 and is_equal_approx(GameCurrency.coins, 31.0), "two Basic packs award exactly ten cards for ten coins")
	_set_coins(4.99)
	check(ui.get_purchase_quantity() == 1 and ui.buy_button.disabled and ui.increase_button.disabled, "low fractional balance clamps quantity and blocks unaffordable purchase")
	GameCurrency.reset_progression(false)
	check(not ui.quantity_controls.visible and ui.get_purchase_quantity() == 1, "progress reset hides quantity controls again")
	CardDatabase.cards = original_database
	CardDatabase.set_pack_rarity_weights({})
	shop.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PACK_QUANTITY_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _open_and_collect(pack_number: int) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(310, 340)
	screen._on_pack_top_input(screen.screen_flash_camera, press, Vector3.ZERO, Vector3.UP, 0)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = press.position + screen._drag_screen_axis * (screen._drag_screen_distance + screen.rip_grab_slack_pixels + 20.0)
	motion.relative = motion.position - press.position
	screen._input(motion)
	check(await _wait_until(func(): return screen._opened and screen._card_stack.size() == 5), "pack %d opens through its real foil drag and spawns five cards" % pack_number)
	await get_tree().create_timer(0.85).timeout
	for card in screen._card_stack.duplicate():
		screen._reveal_top_card(card)
	await get_tree().create_timer(0.85).timeout
	check(screen._waiting_for_collect_click and screen._pending_collection_instances.size() == 5, "pack %d reveals all five rewards before collection" % pack_number)
	check(CollectionManager.get_amount("corpse") == (pack_number - 1) * 5, "pack %d is awarded only on collection" % pack_number)
	screen._input(press)
	screen._input(press)
	check(CollectionManager.get_amount("corpse") == pack_number * 5, "pack %d double collect click awards each card once" % pack_number)


func _purchase_caption(quantity: int, cost: int) -> String:
	var action := Localization.text("PACK KAUFEN") if quantity == 1 else Localization.format_text("%d PACKS KAUFEN", [quantity])
	return Localization.format_text("%s  //  %d COINS", [action, cost])
