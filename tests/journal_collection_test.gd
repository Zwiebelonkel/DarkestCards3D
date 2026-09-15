extends Node3D

const CONTENT := preload("res://scripts/ui/JournalContent.gd")

var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var book: Journal3D
var known_id := ""
var known_index := -1
var _captured_tab_flip := false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	for path in [SaveSlots.SAVE_ROOT, SaveSlots.REGISTRY_PATH, CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path, SettingsManager.CONFIG_PATH]:
		if not str(path).begins_with("res://test-user/"):
			push_error("Run journal_collection_test with the isolated match feature runner.")
			get_tree().quit(1)
			return
	GameCurrency.set_process(false)
	Localization.set_locale("de")
	CollectionManager.clear_profile_state()
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	var catalog: Array = _chapter(CONTENT.build_chapters(), "collection")["entries"]
	check(catalog.size() == CardDatabase.get_all_cards().size() and catalog.size() == 117 and catalog.all(func(entry: Dictionary): return str(entry["card_data"].get("category", "combat")) != "event"), "collection contains only the 117 collectible definitions and no event slots")
	for index in range(mini(Journal3D.COLLECTION_PAGE_SIZE, catalog.size())):
		var data: Dictionary = catalog[index]["card_data"]
		if CardData.is_combat_card(data) and CollectionManager.can_obtain_card(str(data["id"])):
			known_index = index
			known_id = str(data["id"])
			break
	check(known_index >= 0 and not _acquire(known_id, "journal-gallery-known").is_empty(), "gallery fixture acquires one exact combat copy from the first spread")
	if known_index < 0:
		_finish()
		return
	# This suite checks read-only browsing of familiar cards. First-hover
	# acknowledgement and its save are covered by collection_new_label_test.
	CollectionManager.mark_card_seen(known_id)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(viewport.size)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -20, 0)
	light.light_energy = 1.5
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 4)
	viewport.add_child(camera)
	camera.make_current()
	book = Journal3D.new()
	book.open_duration = 0.04
	book.close_duration = 0.04
	viewport.add_child(book)
	book.close_requested.connect(func(): book.close_journal())
	_move_pointer(Vector2(8, 8))
	await _settle()
	var state_before := _state()
	var files_before := _files()
	seed(146905)
	var expected_rng := randi()
	seed(146905)
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "journal opens using a real reading camera")
	await _click_chapter("collection")
	check(_current_chapter() == "collection" and book._index_page_size() == Journal3D.COLLECTION_PAGE_SIZE, "collection tab opens its grid with the correct pagination size")
	_check_spread()
	check(book._collection_slots.size() == 18 and book._collection_rest_transforms.filter(func(pose: Transform3D): return pose.origin.x < 0).size() == 9 and book._collection_rest_transforms.filter(func(pose: Transform3D): return pose.origin.x > 0).size() == 9, "first spread has a three-by-three grid on each physical page")
	await _capture("grid-rest")
	await _check_hover(known_index)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(book.index_page == 1 and book.entry_index == Journal3D.COLLECTION_PAGE_SIZE, "mouse wheel advances one complete grid spread")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	check(book.index_page == 0 and book.entry_index == 0, "mouse wheel returns to the first fixed-slot spread")
	await get_tree().process_frame
	var seen := {}
	var page_count := ceili(catalog.size() / float(Journal3D.COLLECTION_PAGE_SIZE))
	for page in range(page_count):
		check(book.index_page == page, "physical pagination reaches spread %d" % page)
		_check_spread()
		for local_index in range(book._collection_slots.size()):
			var entry: Dictionary = book._entries()[page * Journal3D.COLLECTION_PAGE_SIZE + local_index]
			check(not seen.has(entry["id"]), "fixed catalog slot appears only once: " + str(entry["id"]))
			seen[entry["id"]] = true
		if page + 1 < page_count:
			await _click("index_next")
	check(seen.size() == catalog.size() and catalog.all(func(entry: Dictionary): return seen.has(entry["id"])), "all authored collectible slots are reachable without gaps, duplicates or event slots")
	check(not bool(book._buttons["index_next"]["enabled"]), "last spread disables the next-page arrow")
	var last_page := book.index_page
	book.change_index_page(1)
	check(book.index_page == last_page, "pagination cannot go past the last catalog spread")
	await _capture("grid-last")
	var ordered_ids: Array = book._entries().map(func(entry: Dictionary): return entry["id"])
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		await _settle(0.02)
		check(_current_chapter() == "collection" and book.index_page == last_page and book._entries().map(func(entry: Dictionary): return entry["id"]) == ordered_ids, "locale change preserves fixed card slots and current spread: " + locale)
		_check_spread()
	Localization.set_locale("de")
	while book.index_page > 0:
		await _click("index_prev")
	check(not bool(book._buttons["index_prev"]["enabled"]), "first spread disables the previous-page arrow")
	await _click_chapter("cards")
	check(book._collection_slots.is_empty() and is_instance_valid(book._entry_title) and is_instance_valid(book._body_label) and not book._body_label.text.is_empty(), "returning to combat cards restores the existing article layout")
	await _click_chapter("profile")
	check(book._entries()[book.entry_index]["id"] == "profile:overview" and is_instance_valid(book._body_label) and not book._body_label.text.is_empty(), "profile tab restores its live text")
	await _click_chapter("collection")
	var card := book._collection_cards[known_index]
	_move_pointer(camera.unproject_position(card.global_position))
	await _settle(0.35)
	book.close_journal(true)
	check(not book.is_active(), "immediate closing safely interrupts a raised collection preview")
	_move_pointer(Vector2(8, 8))
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "collection can reopen after closing during hover")
	await _settle(0.35)
	check(book._collection_cards[known_index].transform.is_equal_approx(book._collection_rest_transforms[known_index]), "reopened collection cards return to their fixed rest poses")
	check(randi() == expected_rng, "opening, paging, hovering, translating and closing collection preserve shared gameplay RNG")
	check(_state() == state_before and _files() == files_before, "collection browsing preserves catalog, owned copies, upgrades, deck, wallet and every save/settings byte")
	await _check_event_chapter()
	await _check_discovery_refresh()
	await _check_card_details_navigation()
	await _close_with_escape()
	viewport.size = Vector2i(800, 900)
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "collection opens in a portrait viewport")
	_check_spread()
	check(_controls_fit() and _page_numbers_fit(), "all seven tabs, grid navigation and both page numbers fit the portrait viewport")
	await _capture("grid-portrait")
	await _close_with_escape()
	viewport.queue_free()
	await get_tree().process_frame
	_finish()


func _check_spread() -> void:
	var remaining := book._entries().size() - book.index_page * Journal3D.COLLECTION_PAGE_SIZE
	check(book._collection_slots.size() == mini(remaining, Journal3D.COLLECTION_PAGE_SIZE) and book._collection_cards.size() == book._collection_slots.size(), "current spread contains exactly its fixed catalog slots")
	check(book._entry_title == null and book._body_label == null and book._body_pages.is_empty() and not book._buttons.has("entry:0") and not book._buttons.has("body_next"), "collection has no article titles, descriptions, entry list or body navigation")
	check(not book._buttons.has("close"), "collection has no Close or X button")
	var allowed_labels: Array = book._buttons.values().map(func(button: Dictionary): return button["label"])
	var page_left := book._paper_contents.get_node_or_null("CollectionPageLeft") as Label3D
	var page_right := book._paper_contents.get_node_or_null("CollectionPageRight") as Label3D
	check(page_left != null and page_right != null and page_left.text == str(book.index_page * 2 + 1) and page_right.text == str(book.index_page * 2 + 2), "collection numbers each physical page consecutively across spreads")
	if page_left != null and page_right != null:
		allowed_labels.append_array([page_left, page_right])
		check(page_left.position.x < 0 and page_right.position.x > 0 and page_left.position.y < -1.5 and page_right.position.y < -1.5, "page numbers sit at the bottom of their respective physical pages")
	var extra_text := false
	for child in book._paper_contents.get_children():
		if child is Label3D and child.visible and not child in allowed_labels:
			extra_text = true
	check(not extra_text, "collection shows only cards, controls and its two numeric page labels")
	var previews_match := true
	var placeholders_match := true
	for index in range(book._collection_slots.size()):
		var entry: Dictionary = book._entries()[book.index_page * Journal3D.COLLECTION_PAGE_SIZE + index]
		var data: Dictionary = entry["card_data"]
		var card: Card3D = book._collection_cards[index]
		if CollectionManager.has_discovered_card(str(data["id"])):
			previews_match = previews_match and is_instance_valid(card) and str(card.card_data["id"]) == str(data["id"]) and str(card.card_data.get("instance_id", "")).is_empty()
			if is_instance_valid(card):
				for area: CollisionObject3D in card.find_children("*", "CollisionObject3D", true, false):
					previews_match = previews_match and not area.input_ray_pickable and area.collision_layer == 0 and area.collision_mask == 0
		else:
			var slot: Node3D = book._collection_slots[index]
			var question := slot.get_node_or_null("Placeholder") as Sprite3D
			var border := slot.get_node_or_null("DashedBorder") as MultiMeshInstance3D
			placeholders_match = placeholders_match and card == null and question != null and question.texture == Journal3D.COLLECTION_PLACEHOLDER and question.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and border != null and border.multimesh.instance_count > 4 and slot.find_children("*", "Card3D", true, false).is_empty() and slot.find_children("*", "Label3D", true, false).is_empty()
			placeholders_match = placeholders_match and str(slot.get_meta("catalog_id", "")) == str(data["id"]) and str(slot.get_meta("entry_id", "")) == str(entry["id"])
			var point := camera.unproject_position(slot.global_position)
			placeholders_match = placeholders_match and not book._hit_target(point).begins_with("collection_card:")
	check(previews_match, "discovered slots display real base Card3D previews without owned-instance bindings or gameplay input")
	check(placeholders_match, "undiscovered slots show static placeholders without hidden card art or hover targets")


func _check_hover(index: int) -> void:
	var card: Card3D = book._collection_cards[index]
	if not is_instance_valid(card):
		check(false, "known card is available for physical hover")
		return
	var rest: Transform3D = book._collection_rest_transforms[index]
	var point := camera.unproject_position(card.global_position)
	check(book._hit_target(point) == "collection_card:%d" % index, "pointer ray reaches the known card's fixed slot")
	_move_pointer(point)
	await _settle(0.35)
	check(card.position.z > rest.origin.z + 0.02, "hover raises the card above its paper slot")
	check(card.global_basis.z.normalized().dot((camera.global_position - card.global_position).normalized()) > 0.995, "hover turns the front-face normal toward the actual player camera")
	check(book._hit_target(point) == "collection_card:%d" % index, "raising and rotating the card keeps its original hover target stable")
	await _capture("grid-hover")
	_move_pointer(Vector2(8, 8))
	await _settle(0.35)
	check(card.transform.is_equal_approx(rest), "leaving the card restores its complete fixed-slot transform")


func _check_discovery_refresh() -> void:
	CollectionManager.collection["cards"].erase(known_id)
	CollectionManager.collection["instances"] = CollectionManager.collection["instances"].filter(func(instance: Dictionary): return str(instance.get("card_id", "")) != known_id)
	check(CollectionManager.save_collection(), "save a fixture whose previously discovered copy has been consumed")
	var changed: Array[String] = [known_id]
	CollectionManager.collection_changed.emit(changed)
	await _settle()
	check(CollectionManager.get_amount(known_id) == 0 and is_instance_valid(book._collection_cards[known_index]), "card remains revealed after its last owned copy is consumed")
	await _click("index_next")
	var page := book.index_page
	var first_id: String = book._entries()[page * Journal3D.COLLECTION_PAGE_SIZE]["id"]
	var newly_known_index := -1
	for index in range(book._collection_slots.size()):
		var data: Dictionary = book._entries()[page * Journal3D.COLLECTION_PAGE_SIZE + index]["card_data"]
		if CardData.is_combat_card(data) and CollectionManager.can_obtain_card(str(data["id"])) and not CollectionManager.has_discovered_card(str(data["id"])):
			newly_known_index = index
			check(book._collection_cards[index] == null and not _acquire(str(data["id"]), "journal-gallery-live").is_empty(), "acquire an unknown card while its placeholder is visible")
			break
	await _settle()
	check(newly_known_index >= 0 and is_instance_valid(book._collection_cards[newly_known_index]) and book.index_page == page and book._entries()[page * Journal3D.COLLECTION_PAGE_SIZE]["id"] == first_id, "acquisition replaces only its fixed placeholder while preserving the current spread")
	_check_spread()


func _acquire(card_id: String, instance_id: String) -> Dictionary:
	return CollectionManager.add_card_instance({"card_id": card_id, "instance_id": instance_id, "level": 1, "effects": [], "is_holo": false})


func _check_event_chapter() -> void:
	var expected_ids: Array = EventDeck.definitions().map(func(data: Dictionary): return "event:" + str(data["id"]))
	var state_before := _state()
	var files_before := _files()
	await _click_chapter("event_cards")
	check(book._entries().size() == 6 and book._entries().all(func(entry: Dictionary): return expected_ids.has(entry["id"])), "dedicated event tab contains all six authored events immediately")
	await _capture("event-cards")
	for index in range(book._entries().size()):
		await _click("entry:%d" % index)
		var preview: Card3D = null
		for child in book._paper_contents.get_children():
			if child is Card3D and child.visible:
				preview = child as Card3D
		check(preview != null and str(preview.card_data.get("category", "")) == "event" and str(preview.card_data["id"]) == str(book._entries()[index]["card_data"]["id"]) and preview.get_node_or_null("NewLabel") == null, "event article is readable without discovery or a NEW badge: " + str(book._entries()[index]["id"]))
	check(_state() == state_before and _files() == files_before, "reading all event articles creates no discovery, seen status or save changes")
	# A preexisting save may still contain event IDs from the former gallery.
	# Those obsolete flags must never create event slots in the collection.
	var metadata: Dictionary = CollectionManager.collection["metadata"]
	if not metadata.get("discovered_cards") is Dictionary:
		metadata["discovered_cards"] = {}
	if not metadata.get("seen_cards") is Dictionary:
		metadata["seen_cards"] = {}
	for data: Dictionary in EventDeck.definitions():
		metadata["discovered_cards"][data["id"]] = true
		metadata["seen_cards"][data["id"]] = true
	await _click_chapter("collection")
	check(book._entries().size() == 115 and book._entries().all(func(entry: Dictionary): return not str(entry["id"]).begins_with("collection:event:")), "legacy event discovery and seen flags cannot create collection slots")
	CollectionManager.collection = state_before["collection"].duplicate(true)


func _chapter(chapters: Array, id: String) -> Dictionary:
	for chapter: Dictionary in chapters:
		if str(chapter["id"]) == id:
			return chapter
	return {}


func _current_chapter() -> String:
	return str(book.chapters[book.chapter_index]["id"])


func _click_chapter(id: String) -> void:
	for index in range(book.chapters.size()):
		if str(book.chapters[index]["id"]) == id:
			await _click("chapter:%d" % index)
			return
	check(false, "journal chapter exists: " + id)


func _check_card_details_navigation() -> void:
	var unknown_index := book._collection_cards.find(null)
	check(unknown_index >= 0, "current spread contains an unknown slot for click coverage")
	if unknown_index >= 0:
		var page_before := book.index_page
		await _click_collection_slot(unknown_index, false)
		check(_current_chapter() == "collection" and book.index_page == page_before and book._body_label == null, "clicking an unknown placeholder keeps the collection open without revealing details")
	var catalog: Array = _chapter(book.chapters, "collection")["entries"]
	var cases: Array[Dictionary] = [{"chapter": "cards", "entry": "card:" + known_id, "card": known_id}]
	var combat_entries: Array = _chapter(book.chapters, "cards")["entries"]
	for index in range(Journal3D.INDEX_SIZE, combat_entries.size()):
		var entry: Dictionary = combat_entries[index]
		if str(entry["id"]).begins_with("card:") and _catalog_index(catalog, str(entry["id"])) >= Journal3D.COLLECTION_PAGE_SIZE:
			cases.append({"chapter": "cards", "entry": entry["id"], "card": entry["card_data"]["id"]})
			break
	check(cases.size() == 2, "navigation fixture includes a combat card on later collection and article-index pages")
	var special_entry: Dictionary = _chapter(book.chapters, "special_cards")["entries"][0]
	cases.append({"chapter": "special_cards", "entry": special_entry["id"], "card": special_entry["card_data"]["id"]})
	check(cases.size() == 3, "navigation fixtures cover consumed combat, later combat and special cards")
	for fixture: Dictionary in cases:
		CollectionManager.discover_cards([fixture["card"]])
		CollectionManager.mark_card_seen(str(fixture["card"]))
	await _settle()
	for locale: String in ["de", "en"]:
		Localization.set_locale(locale)
		await _settle()
		var state_before := _state()
		var files_before := _files()
		for fixture: Dictionary in cases:
			await _click_chapter("collection")
			var catalog_index := _catalog_index(book._entries(), str(fixture["entry"]))
			check(catalog_index >= 0, "localized collection retains the source entry identity: " + str(fixture["entry"]))
			if catalog_index < 0:
				continue
			var target_page := catalog_index / Journal3D.COLLECTION_PAGE_SIZE
			while book.index_page < target_page:
				await _click("index_next")
			while book.index_page > target_page:
				await _click("index_prev")
			await _click_collection_slot(catalog_index % Journal3D.COLLECTION_PAGE_SIZE, true)
			check(str(book.chapters[book.chapter_index]["id"]) == str(fixture["chapter"]) and str(book._entries()[book.entry_index]["id"]) == str(fixture["entry"]), "physical collection click opens the exact descriptive article in its chapter: %s (%s)" % [fixture["entry"], locale])
			var selected_row := "entry:%d" % (book.entry_index % Journal3D.INDEX_SIZE)
			check(book.index_page == book.entry_index / Journal3D.INDEX_SIZE and book._buttons.has(selected_row) and bool(book._buttons[selected_row]["selected"]), "destination index page includes and selects the opened article")
			check(book.body_page == 0 and is_instance_valid(book._body_label) and not book._body_label.text.is_empty() and is_instance_valid(book._entry_title) and book._entry_title.text == str(book._entries()[book.entry_index]["title"]), "destination displays the matching title and first page of card information")
		check(_state() == state_before and _files() == files_before, "following familiar-card links preserves gameplay state and save bytes: " + locale)
	Localization.set_locale("de")
	await _settle()
	await _click_chapter("collection")


func _catalog_index(entries: Array, original_entry_id: String) -> int:
	for index in range(entries.size()):
		if str(entries[index]["id"]) == "collection:" + original_entry_id:
			return index
	return -1


func _click_collection_slot(index: int, known: bool) -> void:
	var rest: Transform3D = book._collection_rest_transforms[index]
	var point := camera.unproject_position(book._paper_contents.to_global(rest.origin))
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point) and book._hit_target(point) == ("collection_card:%d" % index if known else ""), "fixed collection slot receives the expected pointer target")
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	check(await _wait_until(func(): return book.is_open()), "physical collection-slot click finishes its page turn")
	await get_tree().process_frame


func _state() -> Dictionary:
	return {"collection": CollectionManager.collection.duplicate(true), "upgrades": CardUpgradeManager.upgrades.duplicate(true), "deck": DeckManager.battle_deck.duplicate(), "ids": DeckManager.deck_instance_ids.duplicate(), "starting": DeckManager.starting_deck_indices.duplicate(), "coins": GameCurrency.get_coin_cents(), "level": GameCurrency.level, "xp": GameCurrency.xp, "cards": CardDatabase.get_all_cards(), "effects": EffectDatabase.get_all_effects()}


func _files() -> Dictionary:
	var result := {}
	var paths: Array[String] = [SaveSlots.REGISTRY_PATH, SettingsManager.CONFIG_PATH]
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			paths.append(SaveSlots.get_slot_directory(slot).path_join(file_name))
	for path in paths:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _controls_fit() -> bool:
	for control: Dictionary in book._buttons.values():
		var node := control["node"] as Node3D
		var half_size: Vector2 = control["size"] * 0.5
		for x in [-half_size.x, half_size.x]:
			for y in [-half_size.y, half_size.y]:
				var corner := node.to_global(Vector3(x, y, 0.0))
				if camera.is_position_behind(corner) or not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(camera.unproject_position(corner)):
					return false
	return true


func _page_numbers_fit() -> bool:
	for node_name: String in ["CollectionPageLeft", "CollectionPageRight"]:
		var label := book._paper_contents.get_node_or_null(node_name) as Label3D
		if label == null:
			return false
		var text_size := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size) * label.pixel_size
		for x in [-text_size.x * 0.5, text_size.x * 0.5]:
			for y in [-text_size.y * 0.5, text_size.y * 0.5]:
				var corner := label.to_global(Vector3(x, y, 0))
				if camera.is_position_behind(corner) or not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(camera.unproject_position(corner)):
					return false
	return true


func _chapter_nodes() -> Array:
	var nodes: Array = []
	for index in range(book.chapters.size()):
		nodes.append(book._buttons["chapter:%d" % index]["node"])
	return nodes


func _tabs_visible_and_unchanged(nodes: Array) -> bool:
	for index in range(nodes.size()):
		var node := nodes[index] as Node3D
		if not is_instance_valid(node) or not node.is_visible_in_tree() or book._buttons["chapter:%d" % index]["node"] != node or node.get_parent() != book._tab_contents:
			return false
	return true


func _tabs_render_above_page() -> bool:
	if not is_instance_valid(book._page_leaf):
		return false
	var leaf_mesh := book._page_leaf.get_child(0) as MeshInstance3D
	var leaf_material := leaf_mesh.material_override as StandardMaterial3D
	for index in range(book.chapters.size()):
		var tab: Dictionary = book._buttons["chapter:%d" % index]
		var mesh := tab["node"] as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		var label := tab["label"] as Label3D
		if material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or not material.no_depth_test or material.render_priority <= leaf_material.render_priority or not label.no_depth_test or label.render_priority <= material.render_priority:
			return false
	return true


func _close_with_escape() -> void:
	check(not book._buttons.has("close"), "journal closes from the keyboard without a Close or X control")
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		viewport.push_input(event, true)
	check(not book._paper_contents.visible and not book._tab_contents.visible, "closing hides both page contents and the persistent tabs")
	check(await _wait_until(func(): return not book.is_active()), "Escape finishes closing the journal")


func _click(action: String) -> void:
	check(book._buttons.has(action), "physical journal control exists: " + action)
	if not book._buttons.has(action):
		return
	var node := book._buttons[action]["node"] as Node3D
	var point := camera.unproject_position(node.global_position)
	var tab_nodes := _chapter_nodes()
	var changes_chapter := action.begins_with("chapter:") and int(action.trim_prefix("chapter:")) != book.chapter_index
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point) and book._hit_target(point) == action, "physical journal control is visible and pointer-reachable: " + action)
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	if changes_chapter:
		check(book._flipping and not book._paper_contents.visible and _tabs_visible_and_unchanged(tab_nodes), "chapter tabs stay visible as the physical page begins turning")
		check(_tabs_render_above_page(), "tab backgrounds and captions render above the turning page instead of being occluded")
		await _settle(0.1)
		check(book._flipping and _tabs_visible_and_unchanged(tab_nodes), "all chapter tab nodes remain unchanged and visible midway through the page turn")
		if not _captured_tab_flip:
			await _capture("tabs-flipping")
			_captured_tab_flip = true
	check(await _wait_until(func(): return book.is_open()), "physical journal click completes: " + action)
	check(_tabs_visible_and_unchanged(tab_nodes), "spread rebuild preserves all existing chapter tab nodes")
	await get_tree().process_frame


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _wheel(button_index: int) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(8, 8)
	event.global_position = event.position
	event.button_index = button_index
	event.pressed = true
	viewport.push_input(event, true)


func _settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://journal-collection-%s.png" % stage) == OK, "saved collection screenshot: " + stage)


func _finish() -> void:
	print("JOURNAL_COLLECTION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
