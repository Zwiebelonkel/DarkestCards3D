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
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run card_localization_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	var original_cards := CardDatabase.get_all_cards()
	var original_effects := EffectDatabase.get_all_effects()
	var original_events := EventDeck.definitions()
	var original_packs: Dictionary = PackDefinition.PACK_TYPES.duplicate(true)
	var rows: Dictionary = {}
	for path in ["res://localization/cards.csv", "res://localization/effects.csv"]:
		var file := FileAccess.open(path, FileAccess.READ)
		check(file != null, "catalog opens: " + path)
		if file == null:
			continue
		check(file.get_csv_line() == PackedStringArray(["keys", "en", "de", "es", "fr", "pl"]), "catalog has all five languages")
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.size() == 1 and row[0].is_empty():
				continue
			check(row.size() == 6, "catalog row has six columns")
			if row.size() == 6:
				rows[row[0]] = row
		file.close()
	for data: Dictionary in original_cards + original_effects + original_events:
		check(rows.has(str(data["name"])) and rows.has(str(data["description"])), "authored name and description covered: " + str(data.get("id", data.get("type"))))
	var card := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(card)
	var data := CardDatabase.get_card("eg").duplicate(true)
	data["instance_id"] = "locale_test_egg"
	data["attack"] = 8
	data["defense"] = 20
	data["effects"] = [{"type": "shield_first_hit"}, {"type": "last_stand"}]
	card.setup(data)
	card.description_label.skip()
	card.consume_first_hit_shield()
	card.take_damage(7)
	card.apply_curse(2)
	card.apply_event_block(2)
	card.stun_next_attack()
	card.set_meta("poison_damage", 3)
	card.set_meta("poison_turns", 2)
	card.set_process(false)
	var before := card.get_network_state().duplicate(true)
	var rng_state: int = card._rng.state
	var artwork_frame: int = card._current_frame
	var locales := ["en", "de", "es", "fr", "pl"]
	for locale_index in locales.size():
		var locale: String = locales[locale_index]
		Localization.set_locale(locale)
		for source: String in rows:
			check(str(TranslationServer.translate(source)) == str(rows[source][locale_index + 1]), "imported " + locale + " translation: " + source)
		check(card.name_label.text == Localization.text("Egg"), "visible card name refreshes in " + locale)
		check(card.description_label.text == card._wrap_text(Localization.text(str(data["description"])), 45), "visible card description refreshes in " + locale)
		check(card.rarity_label.text == Localization.text(str(data["rarity"]).to_upper()), "card rarity refreshes in " + locale)
		check(card.get_node("AttackTitle").text == Localization.text("Attack"), "card heading refreshes in " + locale)
		check(card.get_network_state() == before, "language change preserves complete live combat state in " + locale)
		check(card._rng.state == rng_state and card._current_frame == artwork_frame, "language change preserves RNG and artwork frame in " + locale)
		check(card.attack_label.text == "6" and card.defense_label.text == "13", "damaged and cursed numeric labels remain in " + locale)
		check(is_instance_valid(card._event_block_badge) and card._event_block_badge.visible and card._event_block_badge.find_children("*", "Label3D", true, false).is_empty(), "the pinning knife remains visible without a text badge in " + locale)
		for effect: Dictionary in original_effects:
			var presentation := EffectPresentation.build(effect)
			check(presentation["title"] == Localization.text(str(effect["name"])) and presentation["description"] == Localization.text(str(effect["description"])), "effect title and description use " + locale)
			check(presentation["effect"] == EffectPresentation.resolve_defaults(effect), "effect presentation preserves canonical values")
		check(EffectPresentation.get_value_badge({"type": "poison", "damage": 3, "turns": 2}) == Localization.text("%d DMG · %dT") % [3, 2], "poison values survive translation in " + locale)
		check(EffectPresentation.get_value_badge({"type": "armor", "value": 0.75}) == Localization.text("%d%% ARMOR") % 75, "armor percentage survives translation in " + locale)
		for event: Dictionary in original_events:
			check(EventDeck.get_display_name(event) == Localization.text(str(event["name"])) and EventDeck.get_display_description(event) == Localization.text(str(event["description"])), "event getters localize only presentation in " + locale)
		for pack_id: String in original_packs:
			check(PackDefinition.get_display_name(pack_id) == Localization.text(str(original_packs[pack_id]["name"])) and PackDefinition.get_display_description(pack_id) == Localization.text(str(original_packs[pack_id]["description"])), "pack getters localize only presentation in " + locale)
			check(PackDefinition.get_unlock_message(pack_id) == Localization.text("AB LEVEL %d VERFÜGBAR") % PackDefinition.get_minimum_level(pack_id), "pack unlock placeholder uses " + locale)
		check(CardDatabase.get_all_cards() == original_cards and EffectDatabase.get_all_effects() == original_effects and EventDeck.definitions() == original_events and PackDefinition.PACK_TYPES == original_packs, "catalogs remain canonical in " + locale)
	_check_printed_widths(original_cards, original_events)
	Localization.set_locale("de")
	remove_child(card)
	Localization.set_locale("fr")
	check(card.get_network_state() == before, "a card removed by another locale callback ignores subsequent refresh safely")
	card.queue_free()
	Localization.set_locale("de")
	await get_tree().process_frame
	if failures == 0:
		print("CARD_LOCALIZATION_TESTS: PASS (%d checks)" % checks)
	else:
		print("CARD_LOCALIZATION_TESTS: FAIL (%d / %d checks)" % [failures, checks])
	get_tree().quit(1 if failures else 0)


func _printed_width(label: Label3D) -> float:
	# Include the outline, which otherwise reaches outside a fitted name.
	return (label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x + 2.0 * label.outline_size) * label.pixel_size * absf(label.scale.x)


func _check_printed_widths(cards: Array[Dictionary], events: Array[Dictionary]) -> void:
	var card := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(card)
	card.set_process(false)
	var original_name_size := card.name_label.font_size
	var original_attack_size: int = card.get_node("AttackTitle").font_size
	var original_defense_size: int = card.get_node("DefenseTitle").font_size
	var smaller_names := 0
	var maximum_width := 0.0
	for locale: String in ["en", "de", "es", "fr", "pl"]:
		Localization.set_locale(locale)
		var widest_name_data: Dictionary = {}
		var widest_original_name := 0.0
		for data: Dictionary in cards + events:
			# Presentation-only fixture: no combat setup/art animation is needed
			# to measure every catalog title with the actual font and fallback.
			card.card_data = data.duplicate(true)
			card._refresh_localized_text()
			var original_width := card.name_label.font.get_string_size(card.name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, original_name_size).x
			if original_width > widest_original_name:
				widest_original_name = original_width
				widest_name_data = data
			var width := _printed_width(card.name_label)
			maximum_width = maxf(maximum_width, width)
			smaller_names += int(card.name_label.font_size < original_name_size)
			check(card.name_label.text == Localization.text(str(data["name"])), "full translated title retained: " + locale + "/" + str(data["id"]))
			check(width <= 0.70001, "translated title fits physical header: " + locale + "/" + str(data["id"]))
			check(_printed_width(card.rarity_label) <= 0.70001, "rarity/footer stays within card: " + locale + "/" + str(data["id"]))
		for label: Label3D in [card.get_node("AttackTitle"), card.get_node("DefenseTitle")]:
			check(_printed_width(label) <= 0.22001, "stat heading fits its narrow column: " + locale + "/" + str(label.name))
		check(_printed_width(card.get_node("DescriptionTitle")) <= 0.70001, "description heading fits: " + locale)
		card.card_data = widest_name_data.duplicate(true)
		card._refresh_localized_text()
		check(card.name_label.font_size < original_name_size, "longest name needs smaller text before reuse: " + locale)
		card.card_data = CardDatabase.get_card("eg").duplicate(true)
		card._refresh_localized_text()
		check(card.name_label.font_size == original_name_size, "short name restores original font size: " + locale)
	check(smaller_names > 0, "catalog regression exercises actual long-name fitting")
	Localization.set_locale("en")
	check(card.get_node("AttackTitle").font_size == original_attack_size and card.get_node("DefenseTitle").font_size == original_defense_size, "short stat headings restore both original font sizes")
	print("CARD_TEXT_WIDTHS: %d names across five languages, %d fitted, max %.4f" % [(cards.size() + events.size()) * 5, smaller_names, maximum_width])
	card.queue_free()
