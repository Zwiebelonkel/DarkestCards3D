extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var book: Journal3D
var closed_poses: Array[Dictionary] = []
var lens_material: ShaderMaterial
var grading_material: ShaderMaterial
var lens_parameters: Dictionary
var grading_parameters: Dictionary


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_msec: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run journal_test with the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	Localization.set_locale("de")
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	CollectionManager.add_card("corpse")
	CollectionManager.add_card("slot_room_key")
	CollectionManager.unlock_slot_room()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(1280, 720)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	main.wakeup_blur_duration = 0.05
	viewport.add_child(main)
	book = main.journal
	book.open_duration = 0.15
	book.close_duration = 0.12
	book.closed.connect(func(): closed_poses.append({"pose": main.main_camera.global_transform, "fov": main.main_camera.fov}))
	_move_pointer(Vector2(8, 8))
	await settle(0.4)
	check(InputMap.has_action("journal") and is_instance_valid(book) and book.get_parent() == main, "Main owns the 3D journal and registers its J key action")
	check(not book.is_active() and main._can_open_journal(), "journal starts closed and available at rest in the hub")
	var hub_pose := main.main_camera.global_transform
	var hub_fov := main.main_camera.fov
	var hub_environment := main.main_camera.environment
	lens_material = main.dirty_lens.material as ShaderMaterial
	grading_material = (main.main_camera.get_node("CanvasLayer2/ColorRect") as ColorRect).material as ShaderMaterial
	lens_parameters = _shader_parameters(lens_material)
	grading_parameters = _shader_parameters(grading_material)
	_press_key(KEY_J, true)
	check(not book.is_active(), "key repeat cannot accidentally open the journal")
	_press_key(KEY_J)
	check(book.is_active() and not main._can_travel_between_rooms(), "J starts opening and immediately blocks room travel")
	var side_before := main._active_side
	main._begin_turn(1)
	check(main._active_side == side_before, "journal opening blocks A/D rotation")
	check(await _wait_until(func(): return book.is_open()), "journal finishes its physical opening animation")
	check(main.main_camera.global_position.distance_to(hub_pose.origin) > 0.03 and (-main.main_camera.global_basis.z).dot(Vector3.DOWN) > 0.8, "camera moves down and looks down at the physical book")
	check(main.main_camera.environment != hub_environment and not main.main_camera.environment.glow_enabled, "journal uses a temporary reading environment without bloom washing out the paper")
	check(_screen_filters_unchanged(), "reading preserves the visible camera filters, original shader materials and every shader parameter")
	var frozen_pose := main.main_camera.global_transform
	_move_pointer(Vector2(1200, 650))
	await settle(0.15)
	check(main.main_camera.global_transform.is_equal_approx(frozen_pose) and not main.screen_camera_focus.is_focused(), "mouse tilt and shop focus cannot fight the reading camera")
	check(not get_tree().paused and not main.hub_door.doorway_area.input_ray_pickable, "reading keeps the game running while disabling underlying room input")
	_press_key(KEY_J, true)
	check(book.is_open(), "holding J does not repeatedly close and reopen the journal")
	check(book.chapters.map(func(chapter: Dictionary): return chapter["id"]) == ["cards", "special_cards", "event_cards", "effects", "mechanics", "profile", "collection"] and book.chapters.all(func(chapter: Dictionary): return not (chapter.get("entries", []) as Array).is_empty()), "journal contains seven populated chapters including a dedicated event-card chapter")
	check(not book._buttons.has("close"), "journal has no Close or X button")
	var normal_entries: Array = _chapter("cards")["entries"]
	var special_entries: Array = _chapter("special_cards")["entries"]
	check(normal_entries.size() + special_entries.size() == CardDatabase.get_all_cards().size(), "normal and special chapters together document the complete collectible catalog")
	check(normal_entries.all(func(entry: Dictionary): return CardData.is_combat_card(entry["card_data"])) and special_entries.all(func(entry: Dictionary): return str(entry["card_data"].get("category", "")) == "special"), "combat and special chapters contain only their respective collectible categories")
	check(_all_controls_fit(), "every physical journal control fits the landscape viewport completely")
	await capture("cards")
	await _click_button("index_next")
	check(book.index_page == 1, "physical page control advances the card index")
	await _click_button("entry:1")
	check(book.entry_index == 11, "physical index row changes to the second entry on the next page")
	await _click_chapter("special_cards")
	check(_current_chapter() == "special_cards" and book.index_page == 0 and _chapter("special_cards")["id"] == "special_cards", "physical special-card tab resets and opens its dedicated index")
	var special_preview: Card3D
	for child in book._paper_contents.get_children():
		if child is Card3D and child.visible:
			special_preview = child as Card3D
			break
	check(special_preview != null and str(special_preview.card_data.get("category", "")) == "special" and not CardData.is_combat_card(special_preview.card_data), "special-card tab displays an actual special Card3D preview without combat data")
	check(special_entries.any(func(entry: Dictionary): return entry["id"] == "card:slot_room_key"), "dedicated special index includes the original slot-room key")
	await capture("special-cards")
	await _click_button("index_next")
	await _click_button("entry:1")
	check(_current_chapter() == "special_cards" and book.entry_index == 11 and book._entry_title.text == str(_chapter("special_cards")["entries"][11]["title"]), "special-card index pagination selects the requested printed entry")
	await _click_chapter("event_cards")
	check(_current_chapter() == "event_cards" and book.index_page == 0 and book._entries().size() == EventDeck.definitions().size(), "physical event tab exposes every event article immediately")
	var event_preview: Card3D = null
	for child in book._paper_contents.get_children():
		if child is Card3D and child.visible:
			event_preview = child as Card3D
	check(event_preview != null and str(event_preview.card_data.get("category", "")) == "event" and event_preview.get_node_or_null("NewLabel") == null, "event chapter displays its real event preview without a NEW badge")
	await capture("event-cards")
	await _click_chapter("effects")
	check(_current_chapter() == "effects" and book.index_page == 0, "physical effects tab remains reachable and resets its index")
	var effect_icon: Sprite3D
	for child in book._paper_contents.get_children():
		if child is Sprite3D:
			effect_icon = child as Sprite3D
			break
	check(effect_icon != null and effect_icon.texture != null and effect_icon.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "displayed effect icon uses nearest texture filtering")
	await capture("effects")
	await _click_chapter("mechanics")
	check(_current_chapter() == "mechanics", "physical rules tab remains reachable and opens the game instructions")
	await capture("rules")
	await _click_chapter("profile")
	check(_current_chapter() == "profile" and book._entries()[0]["id"] == "profile:overview", "physical profile tab opens the player's profile overview")
	await capture("profile")
	_move_pointer(Vector2(8, 8))
	_press_key(KEY_ESCAPE)
	check(book.is_active() and not main.pause_menu.visible, "Escape begins closing the journal without opening Pause")
	check(await _wait_until(func(): return not book.is_active()), "journal closing animation releases input")
	check(_closed_at(hub_pose, hub_fov) and not main.pause_menu.visible and main._can_open_journal(), "closing restores the exact hub camera pose and FOV before controls resume")
	check(main.main_camera.environment == hub_environment, "closing restores the original camera environment")
	check(_screen_filters_unchanged(), "closing leaves both camera filters visible with their original materials and parameters")
	_press_key(KEY_J)
	_press_key(KEY_J)
	check(await _wait_until(func(): return not book.is_active()) and _closed_at(hub_pose, hub_fov), "J during the opening animation safely closes and restores the camera")
	_press_key(KEY_J)
	await _wait_until(func(): return book.is_open())
	book.set_chapter(_chapter_index("cards"))
	_press_key(KEY_J)
	await _wait_until(func(): return not book.is_active())
	_press_key(KEY_J)
	await _wait_until(func(): return book.is_open())
	check(_current_chapter() == "cards" and book._entry_title.text == str(_chapter("cards")["entries"][book.entry_index]["title"]) and not book._flipping and book._page_leaf == null, "closing during a page flip rebuilds the selected printed entry on reopening")
	_press_key(KEY_J)
	await _wait_until(func(): return not book.is_active())
	main._begin_turn(-1)
	_press_key(KEY_J)
	check(not book.is_active(), "J cannot open the journal during a cardinal turn")
	await settle(0.2)
	main._pack_opening_blocks_screen_focus = true
	_press_key(KEY_J)
	check(not book.is_active(), "unfinished pack opening blocks the journal")
	main._pack_opening_blocks_screen_focus = false
	var collection := main.scene_pivot.get_node("Collection") as CollectionScreen
	collection._deck_fan_tween_running = true
	check(not main._can_open_journal(), "moving deck cards block journal opening")
	collection._deck_fan_tween_running = false
	main.pause_menu.open()
	_press_key(KEY_J)
	check(not book.is_active(), "Pause blocks journal opening")
	main.pause_menu.close()
	await settle()
	main._on_room_door_activated(main.hub_door)
	_press_key(KEY_J)
	check(main._room_transition_active and not book.is_active(), "door travel blocks journal opening")
	check(await _wait_until(func(): return main._active_room == 1 and not main._room_transition_active), "journal fixture reaches the slot room through the normal door")
	var room_pose := main.main_camera.global_transform
	var room_fov := main.main_camera.fov
	_press_key(KEY_J)
	check(await _wait_until(func(): return book.is_open()), "J also opens the journal in the slot room")
	check(not main.slot_machine.interaction_enabled and not main.return_door.doorway_area.input_ray_pickable, "reading disables slot machine and return-door clicks")
	await capture("room")
	_press_key(KEY_ESCAPE)
	check(await _wait_until(func(): return not book.is_active()) and _closed_at(room_pose, room_fov), "Escape restores the exact slot-room camera")
	main._begin_turn(-1)
	await settle(0.25)
	main.fusion_workbench._busy = true
	check(not main._can_open_journal(), "active card fusion blocks journal opening")
	main.fusion_workbench._busy = false
	_move_pointer(Vector2(8, 8))
	main._on_room_door_activated(main.return_door)
	check(await _wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "room return remains available after reading")
	while main._active_side != 0:
		main._begin_turn(-1)
		await settle(0.15)
	await _check_narrow_reading()
	await _check_battle_reading()
	main.queue_free()
	await settle()
	print("JOURNAL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_narrow_reading() -> void:
	_move_pointer(Vector2(8, 8))
	_press_key(KEY_J)
	await _wait_until(func(): return book.is_open())
	book.set_chapter(_chapter_index("cards"))
	await settle(0.35)
	var entries: Array = _chapter("cards")["entries"]
	var longest_index := 0
	for index in range(entries.size()):
		if str(entries[index]["body"]).length() > str(entries[longest_index]["body"]).length():
			longest_index = index
	book.select_entry(longest_index)
	await settle(0.35)
	await capture("longest")
	check(book._body_pages.size() > 1, "the longest card entry offers physical continuation pages")
	if book._body_pages.size() > 1:
		var first_page := book._body_label.text
		await _click_button("body_next")
		check(book.body_page == 1 and book._body_label.text != first_page, "physical body-page control reveals the remaining long entry text")
	_press_key(KEY_J)
	await _wait_until(func(): return not book.is_active())
	viewport.size = Vector2i(800, 900)
	await settle()
	var narrow_pose := main.main_camera.global_transform
	var narrow_fov := main.main_camera.fov
	_press_key(KEY_J)
	check(await _wait_until(func(): return book.is_open()), "journal opens in a narrow portrait viewport")
	check(_all_controls_fit(), "all four corners of every physical journal control fit the 800x900 viewport")
	await capture("narrow")
	await _click_chapter("special_cards")
	var selected_special_id: String = _chapter("special_cards")["entries"][book.entry_index]["id"]
	for locale: String in ["en", "de", "fr", "pl", "es"]:
		Localization.set_locale(locale)
		await settle()
		check(_all_controls_fit() and _current_chapter() == "special_cards" and _chapter("special_cards")["entries"][book.entry_index]["id"] == selected_special_id, "all portrait controls fit and selected special subject survives live translation: " + locale)
		if locale in ["fr", "pl", "es"]:
			await capture("narrow-special-" + locale)
	await _click_chapter("effects")
	check(_current_chapter() == "effects", "effects tab accepts real pointer input in the translated portrait layout")
	await _click_chapter("event_cards")
	check(_current_chapter() == "event_cards" and _all_controls_fit(), "dedicated event tab accepts real pointer input and fits the translated portrait layout")
	await _click_chapter("mechanics")
	check(_current_chapter() == "mechanics", "rules tab accepts real pointer input in the translated portrait layout")
	await _click_chapter("profile")
	check(_current_chapter() == "profile" and book._entries()[0]["id"] == "profile:overview", "profile tab accepts real pointer input in the translated portrait layout")
	await _click_chapter("cards")
	check(_current_chapter() == "cards", "combat tab accepts real pointer input in the translated portrait layout")
	Localization.set_locale("de")
	_press_key(KEY_ESCAPE)
	await _wait_until(func(): return not book.is_active())
	check(not book.is_active() and _closed_at(narrow_pose, narrow_fov) and _screen_filters_unchanged(), "narrow-viewport close restores the exact camera and leaves the camera filters unchanged")
	viewport.size = Vector2i(1280, 720)
	_move_pointer(Vector2(8, 8))
	await settle()


func _check_battle_reading() -> void:
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	table._clear_match()
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table._local_action_in_progress = false
	table._online_action_in_progress = false
	for side in ["player", "enemy"]:
		var card := CardDatabase.get_card("corpse").duplicate(true)
		card["instance_id"] = "journal-battle-" + side
		card["attack"] = 1
		card["defense"] = 30
		card["effects"] = []
		var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
		deck.append(card)
		table._draw_to_slot(side, 2, false)
	table._move_camera_to_match_view()
	await settle(table.match_camera_duration + 0.15)
	var battle_pose := main.main_camera.global_transform
	var battle_fov := main.main_camera.fov
	_press_key(KEY_J)
	check(await _wait_until(func(): return book.is_open()), "journal is available during an idle card-battle turn")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	table._on_card_clicked(main.main_camera, click, Vector3.ZERO, Vector3.UP, 0, "player", 2)
	check(table._selected_player_card == null and not table._can_local_event_or_attack() and not get_tree().paused, "journal blocks underlying attacks and event input without pausing the match")
	table._resolve_duel(table._enemy_slots[2], table._player_slots[2], "enemy")
	check(not book.is_active() and _closed_at(battle_pose, battle_fov), "an opponent attack synchronously closes the journal before battle camera motion")
	await settle(0.9)
	check(table._player_slots[2].current_hp == 29 and not table._journal_input_blocked, "the interrupted battle continues and restores normal card input")
	table._local_action_in_progress = true
	_press_key(KEY_J)
	check(not book.is_active(), "an active combat action blocks reopening the journal")
	table._local_action_in_progress = false
	_press_key(KEY_J)
	check(await _wait_until(func(): return book.is_open()), "journal can reopen after the attack finishes")
	main.pause_menu.open()
	check(not book.is_active() and not table._journal_input_blocked, "opening Pause immediately closes the book and releases its battle-input guard")
	main.pause_menu.close()
	await _check_online_reading(table)
	table._show_main_menu()
	await settle()


func _check_online_reading(table: GameTable) -> void:
	NetworkManager.current_lobby_id = 123
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	NetworkManager._connected_peer_ids.assign([1])
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = false
	table._online_turn_sequence = 1
	table._online_action_in_progress = false
	table._local_action_in_progress = false
	var attacker := table._enemy_slots[2]
	var defender := table._player_slots[2]
	var defender_state := defender.get_network_state()
	defender_state["current_hp"] = defender.current_hp - 1
	table._online_queued_impact_events[1] = {
		"turn_sequence": 1, "attack_sequence": 1,
		"attacker_side": "player", "attacker_slot": 2,
		"defender_side": "enemy", "defender_slot": 2,
		"attacker_state": attacker.get_network_state(), "defender_state": defender_state,
		"attacker_damage": 0, "defender_damage": 1, "damage_intensity": 0.5, "lava_hits": [],
	}
	var online_pose := main.main_camera.global_transform
	var online_fov := main.main_camera.fov
	var online_environment := main.main_camera.environment
	_press_key(KEY_J)
	check(await _wait_until(func(): return book.is_open()), "journal opens during an idle online guest turn")
	# Run the real incoming attack presenter with its authoritative impact already
	# queued, just as a received packet would be, without needing Steam transport.
	table._rpc_play_online_attack("player", 2, "enemy", 2, 1, 1)
	check(not book.is_active() and _closed_at(online_pose, online_fov) and main.main_camera.environment == online_environment, "incoming online attack immediately restores camera and environment before presentation")
	check(_screen_filters_unchanged(), "online attack interruption leaves both visible camera filters unchanged")
	check(not get_tree().paused and not table._journal_input_blocked, "online interruption releases input without pausing the networked match")
	check(await _wait_until(func(): return table._online_client_presentation_depth == 0 and table._online_client_attack_contexts.is_empty()), "the real online attack animation completes after interrupting reading")
	check(defender.current_hp == int(defender_state["current_hp"]), "authoritative online damage still reaches the original defending card")
	table._online_mode = false
	table._online_action_in_progress = false
	table._reset_online_sync_tracking()
	NetworkManager._match_in_progress = false
	NetworkManager.current_lobby_id = 0
	NetworkManager._participants.clear()
	NetworkManager._connected_peer_ids.clear()


func _screen_filters_unchanged() -> bool:
	var grading_overlay := main.main_camera.get_node("CanvasLayer2/ColorRect") as ColorRect
	return main.dirty_lens.material == lens_material and grading_overlay.material == grading_material \
		and main.dirty_lens.is_visible_in_tree() and grading_overlay.is_visible_in_tree() \
		and (main.dirty_lens.get_parent() as CanvasLayer).visible and (grading_overlay.get_parent() as CanvasLayer).visible \
		and _shader_parameters(lens_material) == lens_parameters and _shader_parameters(grading_material) == grading_parameters


func _shader_parameters(material: ShaderMaterial) -> Dictionary:
	var parameters := {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var parameter := str(uniform["name"])
		parameters[parameter] = material.get_shader_parameter(parameter)
	return parameters


func _all_controls_fit() -> bool:
	for control: Dictionary in book._buttons.values():
		var node := control["node"] as Node3D
		var half_size: Vector2 = control["size"] * 0.5
		for x in [-half_size.x, half_size.x]:
			for y in [-half_size.y, half_size.y]:
				var corner := node.to_global(Vector3(x, y, 0.0))
				if main.main_camera.is_position_behind(corner) or not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(main.main_camera.unproject_position(corner)):
					return false
	return true


func _closed_at(pose: Transform3D, fov: float) -> bool:
	return not closed_poses.is_empty() and (closed_poses.back()["pose"] as Transform3D).is_equal_approx(pose) and is_equal_approx(float(closed_poses.back()["fov"]), fov)


func _chapter_index(id: String) -> int:
	for index in range(book.chapters.size()):
		if str(book.chapters[index]["id"]) == id:
			return index
	return -1


func _chapter(id: String) -> Dictionary:
	var index := _chapter_index(id)
	return book.chapters[index] if index >= 0 else {}


func _current_chapter() -> String:
	return str(book.chapters[book.chapter_index]["id"])


func _click_chapter(id: String) -> void:
	await _click_button("chapter:%d" % _chapter_index(id))


func _click_button(action: String) -> void:
	if not book._buttons.has(action):
		check(false, "journal physical control exists: " + action)
		return
	var node := book._buttons[action]["node"] as Node3D
	var point := main.main_camera.unproject_position(node.global_position)
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point), "journal control is visible: " + action)
	var old_index_page := book.index_page
	var old_entry_index := book.entry_index
	var old_index_text := (book._buttons["entry:0"]["label"] as Label3D).text
	var old_body_text := book._body_label.text
	var old_tabs: Array = []
	for index in range(book.chapters.size()):
		old_tabs.append(book._buttons["chapter:%d" % index]["node"])
	_move_pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	# Assert before a frame or tween can advance: only chapter tabs turn a leaf.
	if action.begins_with("chapter:"):
		check(book._flipping and book._page_leaf != null and not book._paper_contents.visible, "category click starts the physical page animation: " + action)
		check(old_tabs.all(func(tab: Node3D): return tab.is_visible_in_tree() and tab.get_parent() == book._tab_contents), "all sidebar tabs stay visible while the page contents turn")
	elif action.begins_with("entry:"):
		var entry: Dictionary = book.chapters[book.chapter_index]["entries"][book.entry_index]
		check(book.is_open() and book._page_leaf == null and book.entry_index != old_entry_index and book._entry_title.text == str(entry["title"]), "entry click updates its printed text immediately without a page animation")
	elif action.begins_with("index_"):
		check(book.is_open() and book._page_leaf == null and book.index_page != old_index_page and (book._buttons["entry:0"]["label"] as Label3D).text != old_index_text, "index-page click updates the visible list immediately without a page animation")
	elif action.begins_with("body_"):
		check(book.is_open() and book._page_leaf == null and book._body_label.text != old_body_text and book._body_label.text == book._body_pages[book.body_page], "body-page click updates its printed text immediately without a page animation")
	check(_screen_filters_unchanged(), "physical journal interaction leaves the camera filters unchanged: " + action)
	await settle(0.35)
	check(range(book.chapters.size()).all(func(index: int): return book._buttons["chapter:%d" % index]["node"] == old_tabs[index] and (old_tabs[index] as Node3D).is_visible_in_tree()), "journal interaction reuses the same visible sidebar tab nodes")


func _press_key(keycode: int, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		event.echo = echo and pressed
		viewport.push_input(event, true)


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://journal-%s.png" % stage) == OK, "saved journal screenshot: " + stage)
