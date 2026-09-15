extends Node3D

const CONTENT := preload("res://scripts/ui/JournalContent.gd")
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
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use an isolated copy with test saves for this scene.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.level = 20
	GameCurrency.coins = 1000.0
	var ids: Array[String] = []
	for index in range(5):
		var instance := CardData.create_instance("usb_stick", 1, [], index == 0)
		CollectionManager.add_card_instance(instance)
		ids.append(str(instance["instance_id"]))
	CollectionManager.add_card("cigarettes")
	CardUpgradeManager.add_attack("usb_stick", 2)
	CollectionManager.reload_profile()
	check(CollectionManager.get_amount("usb_stick") == 5 and CardData.is_holo(CollectionManager.get_instances_for_card("usb_stick")[0]), "Secret copies and Holo identity persist")
	var before := CollectionManager.collection.duplicate(true)
	check(CollectionManager.get_next_fusion_rarity("secret").is_empty() and CollectionManager.get_next_fusion_rarity("exotic").is_empty(), "Exotic remains the fusion ceiling")
	check(not CollectionManager.fuse_card_instances(ids).get("ok", false) and CollectionManager.collection == before, "Five Secret copies cannot be sacrificed")
	for entry: Dictionary in CollectionManager.get_fusion_candidates():
		check(not entry["eligible"], "Secret copies are visible and protected in the forge")
	DeckManager.add_card("usb_stick")
	check(DeckManager.get_card_count("usb_stick") == 1, "Secret combat cards can join the deck")
	var display := CardUpgradeManager.apply_upgrades("usb_stick", CollectionManager.get_display_card("usb_stick"))
	var remote := NetworkManager._sanitize_remote_card(display)
	check(str(remote.get("rarity")) == "secret" and int(remote.get("attack")) == int(CardDatabase.get_card("usb_stick")["attack"]) + 2, "Secret rarity and stat upgrades survive online serialization")
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.05
	main.mouse_tilt_strength = 0.0
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	var collection := main.scene_pivot.get_node("Collection") as CollectionScreen
	check(collection._row_cards.get("secret", []).size() == 2 and collection._row_cards.get("common", []).is_empty(), "Owned Secret types appear in their own collection row")
	var screen := main.scene_pivot.get_node("PackShopMachine/PackOpeningScreen") as PackOpeningScreen
	screen._play_rarity_sound("secret")
	check(screen._rarity_audio_player.stream != null and screen._rarity_audio_player.stream.resource_path.ends_with("secret.mp3"), "Secret reveal plays its dedicated sound")
	var cards := CardDatabase.cards.duplicate()
	CardDatabase.cards.assign([CardDatabase.get_card("usb_stick"), CardDatabase.get_card("cigarettes")])
	var cents := GameCurrency.get_coin_cents()
	check(not screen.buy_pack("basic", PackDefinition.PACK_TYPES["basic"]), "A Secret-only catalog refuses a paid pack")
	check(GameCurrency.get_coin_cents() == cents and screen._pack_reservation == 0 and not screen._pack_bought, "Rejected pack takes neither money nor a reservation")
	CardDatabase.cards.assign(cards)
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	table._show_difficulty_menu()
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		for node_name: String in table.difficulty_buttons.DIFFICULTIES:
			var button := table.difficulty_buttons.get_node(node_name) as Table3DButton
			var difficulty: String = table.difficulty_buttons.DIFFICULTIES[node_name][0]
			check(button.label.text.contains(str(GameCurrency.get_match_xp("win", difficulty))) and button.label.text.split("\n").size() == 2, "Difficulty button shows its current reward in " + locale + ": " + difficulty)
			var width := 0.0
			for line: String in button.label.text.split("\n"):
				width = maxf(width, button.label.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, button.label.font_size).x)
			check(width * button.label.pixel_size * absf(button.label.scale.x) <= button._label_available_size.x + 0.001, "Translated reward stays inside its physical button")
		var chapters := CONTENT.build_chapters()
		var mechanics: Array = _entry(chapters, "mechanics").get("entries", [])
		var basic := _entry(mechanics, "pack:basic")
		var pack_body := str(basic.get("body", ""))
		var secret_rate := RegEx.new()
		secret_rate.compile(CONTENT.rarity_name("secret") + " [0-9]")
		check(not pack_body.is_empty() and secret_rate.search(pack_body) == null and not pack_body.contains("0,001") and not pack_body.contains("0.001"), "Book lists eligible pack rarities without obsolete Secret odds in " + locale)
		check(not _entry(mechanics, "secret_rarity").is_empty() and not _entry(mechanics, "difficulty_rewards").is_empty(), "Both new mechanics pages exist in " + locale)
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.1).timeout
			RenderingServer.force_draw(false)
			check(get_viewport().get_texture().get_image().save_png("res://difficulty-%s.png" % locale) == OK, "Capture the actual difficulty menu in " + locale)
	Localization.set_locale("de")
	main.queue_free()
	await get_tree().process_frame
	print("SECRET_INTEGRATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _entry(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("id") == id:
			return entry
	return {}
