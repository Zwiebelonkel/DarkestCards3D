extends Node3D

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	GameCurrency._rescued_npcs = {"angel": true, "dealer": true, "jester": true, "prisoner": true}
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run world_localization_test with the isolated match feature runner.")
		get_tree().quit(1)
		return
	_check_imported_catalogs()
	Localization.set_locale("en")
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	CardUpgradeManager.upgrades.clear()
	for index in range(6):
		CollectionManager.add_card("corpse")
	CollectionManager.add_card("bat")
	CollectionManager.add_card("clicker")
	CollectionManager.unlock_slot_room()
	GameCurrency.coins = 41.25
	GameCurrency.level = 2
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0.0
	add_child(main)
	await get_tree().create_timer(0.3).timeout
	var upgrade := main.get_node("ScenePivot/UpgradeMachine") as UpgradeMachine
	var shop := main.get_node("ScenePivot/PackShopMachine") as PackShopMachine
	var slot := main.slot_machine
	var forge := main.fusion_workbench
	var progress := main.level_progress as LevelProgress
	upgrade._on_card_selected("bat")
	var selected_effect := -1
	if not upgrade.ui.effect_entries.is_empty():
		upgrade.ui.effect_slot_buttons[0].button_pressed = true
		upgrade.ui._on_effect_slot_pressed(0)
		selected_effect = 0
	shop.ui._select_pack("basic")
	shop.ui._change_purchase_quantity(1)
	forge.rarity_filter = "common"
	forge.selected_instance_ids = [str(CollectionManager.get_instances_for_card("corpse")[0]["instance_id"])]
	forge.refresh_collection()
	var selection := forge.selected_instance_ids.duplicate()
	upgrade.ui.show_message("Nicht genug Soul Coins")
	upgrade.ui.message_tween.kill()
	upgrade.ui.message_tween = null
	var purchase_source := Localization.format_text("%s GEKAUFT · PACK AUFREISSEN", [Localization.localized_arg(str(PackDefinition.PACK_TYPES["basic"]["name"]))])
	shop.ui.show_message(purchase_source)
	shop.ui.message_tween.kill()
	shop.ui.message_tween = null
	var collection_before: Dictionary = CollectionManager.collection.duplicate(true)
	var upgrades_before: Dictionary = CardUpgradeManager.upgrades.duplicate(true)
	var card_before: Dictionary = upgrade.preview_card.get_network_state().duplicate(true)
	for locale: String in ["de", "en", "es", "fr", "pl"]:
		Localization.set_locale(locale)
		await get_tree().process_frame
		await get_tree().process_frame
		check(GameCurrency.format_coins() == ("41.25" if locale == "en" else "41,25"), "currency decimal in " + locale)
		check(GameCurrency.format_coins(20.0) == ("20.00" if locale == "en" else "20,00"), "fixed currency precision in " + locale)
		check(upgrade.ui.selected_name_label.text == Localization.text("Bat").to_upper(), "upgrade card title in " + locale)
		check(upgrade.ui.selected_effect_entry_index == selected_effect, "effect selection remains in " + locale)
		check(upgrade.ui.selected_rarity_label.text == Localization.rarity_name(str(CardDatabase.get_card("bat")["rarity"]), true), "upgrade rarity in " + locale)
		check(upgrade.ui.attack_button.text == Localization.format_text("ANGRIFF +1\n%d SOUL COINS", [5]), "upgrade price in " + locale)
		check(upgrade.ui.message_label.text == Localization.text("Nicht genug Soul Coins").to_upper(), "existing upgrade notice in " + locale)
		check(shop.ui.message_label.text == Localization.text(purchase_source).to_upper(), "existing pack purchase notice in " + locale)
		check(shop.ui.get_purchase_quantity() == 2 and shop.ui.selected_pack_id == "basic", "pack selection/quantity preserved in " + locale)
		check(shop.ui.buy_button.text == Localization.format_text("%s  //  %d COINS", [Localization.format_text("%d PACKS KAUFEN", [2]), 10]), "complete pack price in " + locale)
		check(slot._credit_label.text == Localization.format_text("SOUL COINS  %s", [GameCurrency.format_coins()]), "slot balance in " + locale)
		check(slot._bet_label.text == Localization.format_text("EINSATZ  %s SC", [Localization.decimal(1.0)]), "slot stake in " + locale)
		check(forge._rarity_label.text == Localization.rarity_name("common", true) and forge.selected_instance_ids == selection, "forge filter/selection in " + locale)
		check(progress.coin_label.text == Localization.format_text("%s Soul Coins", [GameCurrency.format_coins()]), "progress panel currency in " + locale)
		check(upgrade.preview_card.get_network_state() == card_before, "preview state unchanged in " + locale)
		check(CollectionManager.collection == collection_before and CardUpgradeManager.upgrades == upgrades_before and GameCurrency.coins == 41.25, "no gameplay or economy mutation in " + locale)
		await _capture(shop.pack_shop_viewport, "packs-" + locale)
		await _capture(upgrade.upgrade_viewport, "upgrades-" + locale)
		shop.ui._select_pack("god")
		check(shop.ui.info_description_label.text == Localization.format_text("%s Available from player level %d.", [Localization.localized_arg(str(PackDefinition.PACK_TYPES["god"]["description"])), 10]), "locked pack description in " + locale)
		await _capture(shop.pack_shop_viewport, "locked-pack-" + locale)
		shop.ui._select_pack("basic")
		shop.ui._change_purchase_quantity(1)
		shop.ui.show_message(purchase_source)
		shop.ui.message_tween.kill()
		shop.ui.message_tween = null
	main.queue_free()
	await get_tree().process_frame
	print("WORLD_LOCALIZATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _capture(viewport: SubViewport, suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://localization-" + suffix + ".png") == OK, "render " + suffix)


func _check_imported_catalogs() -> void:
	var rows: Dictionary = {}
	for catalog: String in ["game", "menus", "models"]:
		var file := FileAccess.open("res://localization/" + catalog + ".csv", FileAccess.READ)
		check(file != null, "catalog available: " + catalog)
		if file == null:
			continue
		file.get_csv_line()
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.size() == 6:
				rows[row[0]] = row
		file.close()
	var locales := ["en", "de", "es", "fr", "pl"]
	for index in locales.size():
		Localization.set_locale(locales[index])
		for source: String in rows:
			check(str(TranslationServer.translate(source)) == str(rows[source][index + 1]), "native CSV import " + str(locales[index]) + ": " + source)
