extends Node3D

const CONTENT := preload("res://scripts/ui/JournalContent.gd")
const COLLECTION_SCENE := preload("res://scenes/ui/CollectionScreen.tscn")

var checks := 0
var failures := 0
var table_view: SubViewport
var journal_view: SubViewport
var screen: CollectionScreen
var book: Journal3D
var camera: Camera3D
var card_ids: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run collection_new_label_test through the isolated match-feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	var entries: Array = _collection_chapter(CONTENT.build_chapters())["entries"]
	for entry: Dictionary in entries.slice(0, Journal3D.COLLECTION_PAGE_SIZE):
		var data: Dictionary = entry["card_data"]
		if CardData.is_combat_card(data) and CollectionManager.can_obtain_card(str(data["id"])):
			card_ids.append(str(data["id"]))
			if card_ids.size() == 2:
				break
	check(card_ids.size() == 2, "two collectible combat types occupy the first fixed journal spread")
	if card_ids.size() != 2:
		_finish()
		return
	for card_id in card_ids:
		check(not CollectionManager.add_card_instance({"card_id": card_id, "instance_id": "badge-" + card_id, "level": 1, "effects": [], "is_holo": false}).is_empty(), "fixture acquires " + card_id)
		check(CollectionManager.is_card_new(card_id), "newly acquired type starts unread: " + card_id)

	table_view = _make_viewport()
	screen = COLLECTION_SCENE.instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.hover_duration = 0.03
	table_view.add_child(screen)
	_move_pointer(table_view, Vector2(8, 8))
	await _settle()
	_disable_table_picking()
	await get_tree().physics_frame
	screen._reset_collection_hover()
	var table_first := _table_card(card_ids[0])
	var table_second := _table_card(card_ids[1])
	check(table_first != null and table_second != null, "table collection renders both acquired types")
	if table_first == null or table_second == null:
		_finish()
		return
	check(await _wait_until(func(): return table_first.area.mouse_entered.is_connected(screen._on_card_hovered.bind(table_first))), "table entrance connects the real Area3D hover callback")

	journal_view = _make_viewport()
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 4)
	journal_view.add_child(camera)
	camera.make_current()
	book = Journal3D.new()
	book.open_duration = 0.04
	book.close_duration = 0.04
	journal_view.add_child(book)
	_move_pointer(journal_view, Vector2(8, 8))
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "journal opens with its own reading camera")
	book.set_chapter(book.chapters.find(_collection_chapter(book.chapters)))
	check(await _wait_until(func(): return book.is_open()), "journal page turn reaches the collection grid")
	await _settle()
	var journal_first := _journal_card(card_ids[0])
	var journal_second := _journal_card(card_ids[1])
	check(journal_first != null and journal_second != null, "journal reveals both acquired fixed slots")
	if journal_first == null or journal_second == null:
		_finish()
		return
	for card: Card3D in [table_first, table_second, journal_first, journal_second]:
		_check_badge(card)
	var unknown_slots := 0
	var unknown_badges := 0
	for index in range(book._collection_slots.size()):
		if book._collection_cards[index] == null:
			unknown_slots += 1
			unknown_badges += book._collection_slots[index].find_children("NewLabel", "Sprite3D", true, false).size()
	check(unknown_slots > 0 and unknown_badges == 0, "unknown question-mark slots never expose a NEW badge")
	await _capture(table_view, "table-before-hover")
	await _capture(journal_view, "journal-before-hover")
	var animated_badge := table_first.get_node("NewLabel") as Sprite3D
	var first_frame := animated_badge.frame
	check(await _wait_until(func(): return animated_badge.frame != first_frame), "collection NEW badge animates through ordinary scene processing")

	screen.hide()
	table_first.area.mouse_entered.emit()
	await _settle()
	check(CollectionManager.is_card_new(card_ids[0]) and _has_badge(table_first) and _has_badge(journal_first), "a late table hover while hidden cannot acknowledge a new card")
	screen.show()
	screen.suspend_deck_input(true)
	table_first.area.mouse_entered.emit()
	await _settle()
	check(CollectionManager.is_card_new(card_ids[0]) and _has_badge(table_first) and _has_badge(journal_first), "suspended table interaction cannot acknowledge a new card")
	screen.suspend_deck_input(false)
	table_first.area.input_ray_pickable = false
	table_first.area.mouse_entered.emit()
	await _settle()
	check(CollectionManager.is_card_new(card_ids[0]) and _has_badge(table_first), "disabled card picking cannot acknowledge a new card")
	table_first.area.input_ray_pickable = true
	var positions_before := screen._base_positions.duplicate()
	var journal_pose := journal_first.transform
	table_first.area.mouse_entered.emit()
	await _settle()
	check(not CollectionManager.is_card_new(card_ids[0]) and not _has_badge(table_first) and not _has_badge(journal_first), "first table hover clears that type's NEW badge from both open collections")
	check(_table_card(card_ids[0]) == table_first and _table_card(card_ids[1]) == table_second and screen._base_positions == positions_before, "table acknowledgement preserves existing card nodes and row layout")
	check(_journal_card(card_ids[0]) == journal_first and journal_first.transform.is_equal_approx(journal_pose), "table acknowledgement preserves the journal preview node and fixed pose")
	check(CollectionManager.is_card_new(card_ids[1]) and _has_badge(table_second) and _has_badge(journal_second), "hovering one type leaves the other type unread in both collections")
	var saved_after_first := FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH)
	table_first.area.mouse_exited.emit()
	table_first.area.mouse_entered.emit()
	await _settle()
	check(FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH) == saved_after_first, "repeated hover of a seen card does not rewrite its save")
	table_first.area.mouse_exited.emit()
	await _settle()

	var table_second_pose := table_second.transform
	var second_point := camera.unproject_position(journal_second.global_position)
	check(book._hit_target(second_point).begins_with("collection_card:"), "pointer ray reaches the second acquired journal card")
	_move_pointer(journal_view, second_point)
	await _settle(0.35)
	check(not CollectionManager.is_card_new(card_ids[1]) and not _has_badge(journal_second) and not _has_badge(table_second), "first journal hover clears that type's NEW badge in both open collections")
	check(_journal_card(card_ids[1]) == journal_second and _table_card(card_ids[1]) == table_second and table_second.transform.is_equal_approx(table_second_pose), "journal acknowledgement preserves both card nodes and the table pose")
	check(journal_second.global_basis.z.normalized().dot((camera.global_position - journal_second.global_position).normalized()) > 0.995, "acknowledging the badge preserves the journal's camera-facing hover animation")
	_move_pointer(journal_view, Vector2(8, 8))
	await _settle(0.35)
	book.close_journal(true)
	CollectionManager.reload_profile()
	check(card_ids.all(func(card_id: String): return not CollectionManager.is_card_new(card_id)), "seen status survives an actual collection save reload")
	screen.refresh_collection()
	await _settle()
	_disable_table_picking()
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "journal collection reopens after persistence reload")
	await _settle()
	check(card_ids.all(func(card_id: String): return not _has_badge(_table_card(card_id)) and not _has_badge(_journal_card(card_id))), "rebuilding and reopening both collections cannot restore acknowledged badges")
	check(not CollectionManager.add_card_instance({"card_id": card_ids[0], "instance_id": "badge-duplicate", "level": 1, "effects": [], "is_holo": false}).is_empty(), "a duplicate of the seen type can still be acquired")
	screen.refresh_collection()
	await _settle()
	check(not CollectionManager.is_card_new(card_ids[0]) and not _has_badge(_table_card(card_ids[0])) and not _has_badge(_journal_card(card_ids[0])), "receiving another copy of a seen type does not restart the NEW notification")
	book.close_journal(true)
	await _check_detail_wheel_acknowledgement()
	table_view.queue_free()
	journal_view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _check_detail_wheel_acknowledgement() -> void:
	# Keep the pointer away from every card so only opening/scrolling the
	# detail view can acknowledge these freshly acquired types.
	table_view.physics_object_picking = false
	_move_pointer(table_view, Vector2(8, 8))
	screen._reset_collection_hover()
	CollectionManager.clear_profile_state()
	var fixture_ids: Array[String] = []
	for entry: Dictionary in _collection_chapter(CONTENT.build_chapters())["entries"]:
		var data: Dictionary = entry["card_data"]
		var card_id := str(data.get("id", ""))
		if CardData.is_combat_card(data) and CollectionManager.can_obtain_card(card_id):
			fixture_ids.append(card_id)
			CollectionManager.add_card_instance({"card_id": card_id, "instance_id": "wheel-badge-" + card_id, "level": 1, "effects": [], "is_holo": false})
			if fixture_ids.size() == 4:
				break
	screen.detail_duration = 0.04
	screen.add_button_slide_duration = 0.02
	screen.detail_mouse_tilt_strength = 0.0
	screen.refresh_collection()
	await _settle()
	_disable_table_picking()
	var ordered: Array[Card3D] = []
	for rarity in screen.RARITY_ORDER:
		for card: Card3D in screen._row_cards.get(rarity, []):
			ordered.append(card)
	check(ordered.size() == 4 and fixture_ids.all(func(card_id: String): return CollectionManager.is_card_new(card_id) and _has_badge(_table_card(card_id))), "detail-wheel fixture begins with four genuinely unread card types")
	if ordered.size() != 4:
		return
	var hover_events: Array[int] = [0]
	for card in ordered:
		card.area.mouse_entered.connect(func(): hover_events[0] += 1)
	var previous := ordered[0]
	var first := ordered[1]
	var next := ordered[2]
	var untouched := ordered[3]
	var first_id := str(first.card_data["id"])
	var next_id := str(next.card_data["id"])
	var previous_id := str(previous.card_data["id"])
	var untouched_id := str(untouched.card_data["id"])
	await screen._open_detail_card(first)
	await _settle()
	check(screen._detail_card == first and not CollectionManager.is_card_new(first_id) and not _has_badge(first), "opening detail without a prior hover acknowledges the inspected card and removes its NEW label")
	check(CollectionManager.is_card_new(next_id) and CollectionManager.is_card_new(previous_id) and CollectionManager.is_card_new(untouched_id), "opening one detail leaves every uninspected neighbor unread")
	await _scroll_detail(MOUSE_BUTTON_WHEEL_DOWN)
	check(screen._detail_card == next and not CollectionManager.is_card_new(next_id) and not _has_badge(next), "real wheel-down input acknowledges the next unhovered detail card and removes its NEW label")
	var saved_after_next := FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH)
	await _scroll_detail(MOUSE_BUTTON_WHEEL_UP)
	check(screen._detail_card == first and FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH) == saved_after_next, "scrolling back to an already inspected detail does not rewrite its save")
	await _scroll_detail(MOUSE_BUTTON_WHEEL_UP)
	check(screen._detail_card == previous and not CollectionManager.is_card_new(previous_id) and not _has_badge(previous), "real wheel-up input acknowledges the previous unhovered detail card and removes its NEW label")
	check(hover_events[0] == 0 and CollectionManager.is_card_new(untouched_id) and _has_badge(untouched), "detail browsing never needs a hover event and leaves the unvisited fourth card NEW")
	await _capture(table_view, "detail-after-wheel")
	_move_pointer(table_view, Vector2(8, 8))
	await screen._close_detail_card()
	CollectionManager.reload_profile()
	var inspected_ids: Array[String] = [first_id, next_id, previous_id]
	check(inspected_ids.all(func(card_id: String): return not CollectionManager.is_card_new(card_id)) and CollectionManager.is_card_new(untouched_id), "reload preserves all wheel-inspected seen flags while the unvisited card remains unread")
	screen.refresh_collection()
	await _settle()
	_disable_table_picking()
	check(inspected_ids.all(func(card_id: String): return not _has_badge(_table_card(card_id))) and _has_badge(_table_card(untouched_id)), "rebuilding the collection restores only the unvisited card's NEW label")


func _scroll_detail(button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = Vector2(640, 360)
		event.global_position = event.position
		table_view.push_input(event, true)
	await _settle(0.12)


func _collection_chapter(chapters: Array) -> Dictionary:
	for chapter: Dictionary in chapters:
		if str(chapter["id"]) == "collection":
			return chapter
	return {}


func _make_viewport() -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.physics_object_picking = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	view.notify_mouse_entered()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -20, 0)
	light.light_energy = 1.5
	view.add_child(light)
	return view


func _disable_table_picking() -> void:
	for card: Card3D in screen._base_positions:
		# Real Area3D signals are emitted explicitly so a desktop pointer cannot
		# accidentally read a fixture card before the controlled hover.
		card.area.collision_layer = 0


func _table_card(card_id: String) -> Card3D:
	for card: Card3D in screen._base_positions:
		if str(card.card_data.get("id", "")) == card_id:
			return card
	return null


func _journal_card(card_id: String) -> Card3D:
	for card: Card3D in book._collection_cards:
		if is_instance_valid(card) and str(card.card_data.get("id", "")) == card_id:
			return card
	return null


func _has_badge(card: Card3D) -> bool:
	return is_instance_valid(card) and card.get_node_or_null("NewLabel") != null


func _check_badge(card: Card3D) -> void:
	var badge := card.get_node_or_null("NewLabel") as Sprite3D
	check(badge != null, "unread card owns a Sprite3D NEW label: " + str(card.card_data["id"]))
	if badge != null:
		check(badge.texture.resource_path == "res://assets/cards/newlabel.png" and badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED and badge.position.is_equal_approx(Vector3(-0.396, 0.57, 0.06)), "collection badge reuses the authored animation and camera-facing upper-left attachment")


func _move_pointer(view: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	view.push_input(event, true)


func _settle(seconds: float = 0.12) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _capture(view: SubViewport, stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png("res://collection-new-label-%s.png" % stage) == OK, "saved new-label preview: " + stage)


func _finish() -> void:
	print("COLLECTION_NEW_LABEL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
