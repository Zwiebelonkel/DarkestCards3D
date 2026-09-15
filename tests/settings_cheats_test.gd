extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var settings: SettingsMenu
var main: MainScene
var collection: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated test runner to protect real player saves.")
		get_tree().quit(1)
		return
	SettingsManager.set_fullscreen(false)
	GameCurrency.reset_progression(false)
	GameCurrency.coins = 20.37
	GameCurrency.xp = 40
	GameCurrency.save()
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.starting_deck_indices.clear()
	DeckManager.deck_instance_ids.clear()
	CollectionManager.add_card("corpse")
	DeckManager.add_card("corpse")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(viewport.size)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	main.mouse_tilt_strength = 0
	main.rotation_duration = 0.02
	main.settle_duration = 0.02
	viewport.add_child(main)
	await settle(0.2)
	main._begin_turn(1)
	await settle(0.12)
	main._begin_turn(1)
	await settle(0.12)
	collection = main.get_node("ScenePivot/Collection") as CollectionScreen
	collection.deck_fan_duration = 0.04
	collection.deck_fan_stagger = 0
	await collection._open_deck_fan()
	main.pause_menu.open()
	main.pause_menu._open_settings()
	settings = main.pause_menu.settings_menu
	await settle()
	check(get_tree().paused and settings.visible and not settings.cheats_actions.visible, "Paused settings contain a collapsed Cheats section")
	await click(settings.cheats_toggle)
	check(settings.cheats_actions.visible, "Real mouse click opens the cheat actions")
	check(settings.cheat_rarity_check_boxes.size() == 8, "Cheats expose all eight drop rarities including Secret")
	var common_toggle := settings.cheat_rarity_check_boxes["common"] as CheckBox
	check(common_toggle.button_pressed, "Drop rarities start enabled")
	await click(common_toggle)
	check(not common_toggle.button_pressed and not SettingsManager.is_cheat_rarity_enabled("common"), "A real click disables Common while paused")
	SettingsManager.load_settings()
	settings.close()
	main.pause_menu._open_settings()
	await settle()
	check(not common_toggle.button_pressed and not SettingsManager.is_cheat_rarity_enabled("common"), "The rarity selection survives reload and reopening settings")
	await click(common_toggle)
	check(common_toggle.button_pressed and SettingsManager.is_cheat_rarity_enabled("common"), "A second click re-enables Common")
	for rarity: String in CardDatabase.REWARD_RARITIES:
		if rarity != "secret":
			SettingsManager.set_cheat_rarity_enabled(rarity, false)
	var secret_toggle := settings.cheat_rarity_check_boxes["secret"] as CheckBox
	await click(secret_toggle)
	check(secret_toggle.button_pressed and SettingsManager.is_cheat_rarity_enabled("secret"), "Clicking the last enabled rarity keeps a valid selection")
	check(settings.cheat_status.text == Localization.text("Mindestens eine Seltenheit muss aktiviert bleiben."), "Rejecting an empty selection explains why the last checkbox stays checked")
	var locale_before := Localization.get_locale()
	SettingsManager.set_language("en")
	check(secret_toggle.text == "Secret" and common_toggle.text == "Common" and not common_toggle.button_pressed, "Changing language updates rarity labels while preserving the selection")
	SettingsManager.set_language(locale_before)
	for rarity: String in CardDatabase.REWARD_RARITIES:
		SettingsManager.set_cheat_rarity_enabled(rarity, true)
	await click(settings.cheat_level_button)
	check(GameCurrency.get_level() == 2 and GameCurrency.get_xp() == 40, "Level +1 advances exactly once while retaining earned XP")
	check(GameCurrency.get_coin_cents() == 4537, "Level cheat applies the existing level bonus without losing fractional coins")
	await click(settings.cheat_coins_button)
	check(GameCurrency.get_coin_cents() == 9537, "+50 Soul Coins adds exactly fifty to the current balance")
	GameCurrency.load_currency()
	check(GameCurrency.get_level() == 2 and GameCurrency.get_xp() == 40 and GameCurrency.get_coin_cents() == 9537, "Level, XP and cheated coins persist together")
	await click(settings.cheat_level_button)
	check(GameCurrency.get_level() == 3 and GameCurrency.get_xp() == 40, "Repeated level-up uses the next growing XP threshold")
	await click(settings.cheat_starting_hand_button)
	check(CollectionManager.get_starting_hand_slot_count() == 5 and settings.cheat_starting_hand_button.disabled, "Unlock cheat grants all five tiers and disables its completed action")
	check(collection._starting_hand_view._unlocked_slots == 5, "Already-open starting slots update while the game is paused")
	check(DeckManager.get_deck_cards() == ["corpse"] and DeckManager.get_starting_deck_indices().is_empty(), "Unlocking grants special cards without editing the combat deck or assigning cards")
	var ids: Array[String] = []
	for card_id in CollectionManager.STARTING_HAND_CARD_IDS:
		check(CollectionManager.get_amount(card_id) == 1, "%s is granted exactly once" % card_id)
		ids.append(str(CollectionManager.get_instances_for_card(card_id)[0].instance_id))
	settings._cheat_unlock_starting_hand()
	CollectionManager.load_collection()
	for index in range(5):
		var card_id: String = CollectionManager.STARTING_HAND_CARD_IDS[index]
		check(CollectionManager.get_amount(card_id) == 1 and str(CollectionManager.get_instances_for_card(card_id)[0].instance_id) == ids[index], "Repeated unlock/reload preserves the same unique tier %d" % (index + 1))
	(settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer).ensure_control_visible(settings.cheat_status)
	await settle()
	await capture("cheats")
	settings.close()
	main.pause_menu.close()
	await settle(0.15)
	check(collection._base_positions.size() == 1 and not collection._collection_refresh_pending, "Returning to the game keeps the five upgrade cards out of the normal collection")
	await collection._close_deck_fan()
	await settle()
	# Partial progress keeps the existing tier identity and grants only the rest.
	for index in range(2, 5):
		var card_id: String = CollectionManager.STARTING_HAND_CARD_IDS[index]
		CollectionManager.collection.cards.erase(card_id)
		CollectionManager.collection.instances = CollectionManager.collection.instances.filter(func(instance: Dictionary) -> bool: return str(instance.card_id) != card_id)
	settings._refresh_cheat_controls()
	check(not settings.cheat_starting_hand_button.disabled and CollectionManager.get_starting_hand_slot_count() == 2, "Partial progression can still use the unlock action")
	settings._cheat_unlock_starting_hand()
	check(CollectionManager.get_starting_hand_slot_count() == 5 and str(CollectionManager.get_instances_for_card("starting_hand_1")[0].instance_id) == ids[0], "Partial unlock retains owned card identities")
	var before_pending := GameCurrency.get_coin_cents()
	GameCurrency.begin_slot_spin(100, 1000)
	settings._cheat_add_coins()
	check(GameCurrency.has_pending_slot_spin(), "Coin cheat keeps an ongoing slot payout reserved")
	GameCurrency.complete_slot_spin()
	check(GameCurrency.get_coin_cents() == before_pending - 100 + 5000 + 1000, "Slot payout and cheated coins are both credited exactly once")
	main.queue_free()
	await settle()
	print("SETTINGS_CHEATS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func click(button: Button) -> void:
	var scroll := settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer
	scroll.ensure_control_visible(button)
	await settle()
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await settle(0.02)


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://settings-%s.png" % stage)
