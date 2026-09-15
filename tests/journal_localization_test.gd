extends Node3D

const CONTENT := preload("res://scripts/ui/JournalContent.gd")
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run journal_localization_test with the isolated match feature runner.")
		get_tree().quit(1)
		return
	var collection_before := CollectionManager.collection.duplicate(true)
	var upgrades_before := CardUpgradeManager.upgrades.duplicate(true)
	var deck_before := DeckManager.deck_instance_ids.duplicate()
	var coins_before := GameCurrency.get_coin_cents()
	var font := Journal3D.FONT
	for character: String in "ĄĆĘŁŃÓŚŹŻąćęłńóśźżœŒ":
		var supported := font.has_char(character.unicode_at(0))
		for fallback: Font in font.fallbacks:
			supported = supported or fallback.has_char(character.unicode_at(0))
		check(supported, "journal font covers European glyph " + character)
	var csv := FileAccess.open("res://localization/journal.csv", FileAccess.READ)
	var header := csv.get_csv_line()
	var translations: Array[PackedStringArray] = []
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		check(row.size() == 6, "journal CSV row has all five locales")
		if row.size() == 6:
			translations.append(row)
	csv.close()
	var layout := Journal3D.new()
	add_child(layout)
	var original_tab_nodes: Array = []
	for index in range(layout.chapters.size()):
		original_tab_nodes.append(layout._buttons["chapter:%d" % index]["node"])
	var expected_ids: Array[String] = []
	var entry_count := 0
	var total_pages := 0
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		var column := header.find(locale)
		for row: PackedStringArray in translations:
			check(not row[column].is_empty() and Localization.text(row[0]) == row[column], "native CSV resolves exact source in " + locale + ": " + row[0].left(45))
		seed(610331)
		var next_random := randi()
		seed(610331)
		var chapters := CONTENT.build_chapters()
		check(randi() == next_random, "catalog localization does not consume gameplay RNG: " + locale)
		check(chapters.map(func(chapter: Dictionary): return chapter["id"]) == ["cards", "special_cards", "event_cards", "effects", "mechanics", "profile", "collection"], "seven translated chapters retain their stable order: " + locale)
		for index in range(chapters.size()):
			var tab: Dictionary = layout._buttons["chapter:%d" % index]
			check(tab["node"] == original_tab_nodes[index] and (tab["node"] as Node3D).get_parent() == layout._tab_contents, "translation reuses the persistent sidebar tab: %s:%s" % [locale, chapters[index]["id"]])
			var label := tab["label"] as Label3D
			var size: Vector2 = tab["size"]
			var rotated := absf(sin(label.rotation.z)) > 0.5
			var available_width := size.y if rotated else size.x
			var available_height := size.x if rotated else size.y
			var text_bounds := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size) * label.pixel_size
			check(label.text == str(chapters[index]["title"]).to_upper() and text_bounds.x <= available_width and text_bounds.y <= available_height, "complete translated chapter caption fits its tab: %s:%s" % [locale, chapters[index]["id"]])
		var ids: Array[String] = []
		for chapter: Dictionary in chapters:
			# Gallery entries have no printed headings or body paragraphs.
			# Their tab caption still receives the same fit checks above.
			if str(chapter["id"]) == "collection":
				continue
			var last_title := ""
			for entry: Dictionary in chapter["entries"]:
				entry_count += 1
				var id := str(entry["id"])
				var title := str(entry["title"])
				var subtitle := str(entry["subtitle"])
				ids.append(id)
				if chapter["id"] in ["cards", "special_cards", "event_cards"]:
					check(last_title.is_empty() or last_title.naturalnocasecmp_to(title) <= 0, "card index sorts translated names in " + locale)
					last_title = title
					check(title == Localization.text(str(entry["card_data"]["name"])), "card title is localized without altering its authored data: " + id)
				_check_heading(layout, title, 54, 36, 0.30, locale + ":" + id + ":title")
				_check_heading(layout, subtitle, 40, 28, 0.22, locale + ":" + id + ":subtitle")
				var illustrated := entry.has("card_data") or entry.has("profile_strength") or not str(entry.get("icon_path", "")).is_empty()
				var pages := layout._paginate(str(entry["body"]), 36, 12 if illustrated else 20)
				check(not pages.is_empty(), "body has pages: " + locale + ":" + id)
				total_pages += pages.size()
				for page: String in pages:
					var bounds := font.get_multiline_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, 46) * 0.0025
					check(bounds.x <= 2.741, "body fits page width: " + locale + ":" + id)
					check((0.12 if illustrated else 1.14) - bounds.y >= -1.71, "body clears page navigation: " + locale + ":" + id)
				check(_normalized(" ".join(pages)) == _normalized(str(entry["body"])), "pagination preserves all text while wrapping long words: " + locale + ":" + id)
		ids.sort()
		if expected_ids.is_empty():
			expected_ids = ids
		check(ids == expected_ids, "entry identities remain stable when translated: " + locale)
	# Change locale several times in the same frame. Old preview callbacks
	# must stay safe while old page nodes await queued deletion.
	layout._phase = Journal3D.Phase.OPEN
	layout.chapter_index = _find_index(layout.chapters, "cards")
	layout.entry_index = _find_index(layout._entries(), "card:eg")
	layout.index_page = layout.entry_index / Journal3D.INDEX_SIZE
	layout._build_spread()
	var positions: Array[int] = []
	for locale: String in ["en", "pl", "fr", "es", "de"]:
		Localization.set_locale(locale)
		positions.append(layout.entry_index)
		check(layout.chapters[layout.chapter_index]["entries"][layout.entry_index]["id"] == "card:eg", "language change preserves selected Egg page: " + locale)
		check(layout.index_page == layout.entry_index / Journal3D.INDEX_SIZE and layout._paper_contents.visible and not layout._flipping, "language change shows the correct index page without animation: " + locale)
	check(positions.min() != positions.max(), "selection test spans actual changes in translated card order")
	layout.set_chapter(_find_index(layout.chapters, "special_cards"))
	check(layout._flipping and layout._tab_contents.visible and not layout._paper_contents.visible, "special chapter change animates while its persistent sidebar stays visible")
	Localization.set_locale("en")
	layout.select_entry(_find_index(layout._entries(), "card:slot_room_key"))
	var special_positions: Array[int] = []
	for locale: String in ["pl", "fr", "es", "de", "en"]:
		Localization.set_locale(locale)
		special_positions.append(layout.entry_index)
		check(layout.chapters[layout.chapter_index]["id"] == "special_cards" and layout._entries()[layout.entry_index]["id"] == "card:slot_room_key", "language change preserves the selected special key subject and chapter: " + locale)
		check(layout.index_page == layout.entry_index / Journal3D.INDEX_SIZE and layout._paper_contents.visible and not layout._flipping, "special localization keeps the matching visible index page: " + locale)
	check(special_positions.min() != special_positions.max(), "special subject test spans actual changes in translated sorting")
	layout.set_chapter(_find_index(layout.chapters, "event_cards"))
	Localization.set_locale("de")
	layout.select_entry(_find_index(layout._entries(), "event:steel"))
	for locale: String in ["pl", "fr", "es", "de", "en"]:
		Localization.set_locale(locale)
		check(layout.chapters[layout.chapter_index]["id"] == "event_cards" and layout._entries()[layout.entry_index]["id"] == "event:steel", "translation preserves the selected event subject in its dedicated chapter: " + locale)
		check(layout._entries().size() == EventDeck.definitions().size() and layout._paper_contents.visible and not layout._flipping, "every event remains available after translation regardless of discovery: " + locale)
	layout.set_chapter(_find_index(layout.chapters, "effects"))
	check(layout._flipping, "category change still animates")
	var selected_effect_id: String = layout._entries()[layout.entry_index]["id"]
	Localization.set_locale("pl")
	check(not layout._flipping and layout._paper_contents.visible and layout._entries()[layout.entry_index]["id"] == selected_effect_id, "locale change safely ends a category animation and preserves its subject")
	layout.select_entry(1)
	check(not layout._flipping, "choosing an entry remains instant")
	layout.set_chapter(_find_index(layout.chapters, "profile"))
	Localization.set_locale("en")
	layout.select_entry(_find_index(layout._entries(), "profile:deck"))
	for locale: String in ["de", "fr", "pl", "es", "en"]:
		Localization.set_locale(locale)
		check(layout.chapters[layout.chapter_index]["id"] == "profile" and layout._entries()[layout.entry_index]["id"] == "profile:deck" and layout._paper_contents.visible and not layout._flipping, "translation preserves the selected live deck-profile subject: " + locale)
	for phase: int in [Journal3D.Phase.OPENING, Journal3D.Phase.CLOSING]:
		layout._phase = phase
		Localization.set_locale("en" if Localization.get_locale() != "en" else "de")
		check(layout._phase == phase and not layout._paper_contents.visible and not layout._tab_contents.visible, "locale refresh preserves an in-progress opening or closing phase without showing pages or tabs early")
	layout._phase = Journal3D.Phase.CLOSED
	layout.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	check(CollectionManager.collection == collection_before and CardUpgradeManager.upgrades == upgrades_before and DeckManager.deck_instance_ids == deck_before and GameCurrency.get_coin_cents() == coins_before, "journal translation and previews preserve collection, upgrades, deck and money")
	print("JOURNAL_LOCALIZATION_LAYOUT: %d localized entries and %d body pages measured" % [entry_count, total_pages])
	print("JOURNAL_LOCALIZATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_heading(layout: Journal3D, text: String, starting_size: int, minimum_size: int, max_height: float, context: String) -> void:
	var font_size := starting_size
	while font_size > minimum_size and layout._text_width(text, font_size) > 2.75:
		font_size -= 1
	var bounds := Journal3D.FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, 1100, font_size) * 0.0025
	check(bounds.x <= 2.751 and bounds.y <= max_height, "translated heading fits its area: " + context)


func _find_index(entries: Array, id: String) -> int:
	for index in range(entries.size()):
		if entries[index]["id"] == id:
			return index
	return -1


func _normalized(text: String) -> String:
	# The microwave's deliberately unbroken sound is longer than one line.
	# Line breaks may split it; no printed character may disappear.
	return text.replace("\n", "").replace(" ", "")
