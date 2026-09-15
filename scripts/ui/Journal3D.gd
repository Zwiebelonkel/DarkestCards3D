extends Node3D
class_name Journal3D

signal close_requested
signal closed
signal opened

const BOOK_MODEL := preload("res://scripts/props/JournalBookModel.gd")
const CONTENT := preload("res://scripts/ui/JournalContent.gd")
const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const NEW_CARD_LABEL := preload("res://scripts/card/NewCardLabel.gd")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const PAGE_SOUND := preload("res://assets/sounds/SFX/button.mp3")
const COLLECTION_PLACEHOLDER := preload("res://assets/effects/placeholder.png")
const INDEX_SIZE := 10
const COLLECTION_PAGE_SIZE := 18
const COLLECTION_CARD_SIZE := Vector2(0.792, 1.14)
const COLLECTION_CARD_SCALE := 0.82
const COLLECTION_HOVER_LIFT := 0.44
const COLLECTION_HOVER_SCALE := 1.14
const INK := Color("30251d")
const PAPER := Color("b9a988")
const ACCENT := Color("783a30")
enum Phase { CLOSED, OPENING, OPEN, CLOSING }

@export var camera: Camera3D
@export var open_duration := 0.65
@export var close_duration := 0.4
var chapters: Array[Dictionary] = []
var chapter_index := 0
var entry_index := 0
var index_page := 0
var body_page := 0
var _phase := Phase.CLOSED
var _book: Node3D
var _paper_contents: Node3D
var _tab_contents: Node3D
var _buttons: Dictionary = {}
var _body_pages: Array[String] = []
var _body_label: Label3D
var _entry_title: Label3D
var _motion_tween: Tween
var _page_tween: Tween
var _page_leaf: Node3D
var _flipping := false
var _hover := ""
var _saved_camera_pose := Transform3D.IDENTITY
var _saved_fov := 58.0
var _saved_environment: Environment
var _book_pose := Transform3D.IDENTITY
var _stowed_pose := Transform3D.IDENTITY
var _sound: AudioStreamPlayer
var _profile_refresh_elapsed := 0.0
var _collection_cards: Array[Card3D] = []
var _collection_slots: Array[Node3D] = []
var _collection_rest_transforms: Array[Transform3D] = []
var _collection_hover_amounts: Array[float] = []
var _collection_border: MultiMesh
var _collection_refresh_pending := false


func _ready() -> void:
	_book = BOOK_MODEL.new()
	add_child(_book)
	_paper_contents = Node3D.new()
	add_child(_paper_contents)
	_tab_contents = Node3D.new()
	add_child(_tab_contents)
	_sound = AudioStreamPlayer.new()
	_sound.stream = PAGE_SOUND
	_sound.bus = &"SFX"
	_sound.volume_db = -19.0
	add_child(_sound)
	chapters = CONTENT.build_chapters()
	Localization.locale_changed.connect(_on_locale_changed)
	CollectionManager.collection_changed.connect(_on_collection_changed)
	_build_spread()
	hide()


func is_active() -> bool:
	return _phase != Phase.CLOSED


func is_open() -> bool:
	return _phase == Phase.OPEN and not _flipping


func open_journal(view_camera: Camera3D) -> bool:
	if is_active() or not is_instance_valid(view_camera) or chapters.is_empty():
		return false
	camera = view_camera
	refresh_profile(false)
	_build_spread()
	_saved_camera_pose = camera.global_transform
	_saved_fov = camera.fov
	_enable_reading_environment()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var center := _saved_camera_pose.origin + forward * 0.55 - Vector3.UP * 1.05
	_book_pose = Transform3D(Basis(right, forward, Vector3.UP).scaled(Vector3.ONE * 0.22), center)
	_stowed_pose = _book_pose
	_stowed_pose.origin -= Vector3.UP * 0.38
	global_transform = _stowed_pose
	var reading_pose := Transform3D(Basis.IDENTITY, center + Vector3.UP * 0.95 - forward * 0.36)
	reading_pose = reading_pose.looking_at(center, forward)
	_phase = Phase.OPENING
	_book.set_open_amount(0.0)
	_paper_contents.hide()
	_tab_contents.hide()
	show()
	_sound.play()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.tween_property(self, "global_transform", _book_pose, open_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(camera, "global_transform", reading_pose, open_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.tween_property(camera, "fov", _reading_fov(), open_duration)
	_motion_tween.tween_method(_book.set_open_amount, 0.0, 1.0, open_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_callback(func():
		_phase = Phase.OPEN
		_motion_tween = null
		_paper_contents.show()
		_tab_contents.show()
		opened.emit()
	)
	return true


func _reading_fov() -> float:
	# Preserve the full spread on narrow desktop windows as well as 16:9.
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	return maxf(63.0, rad_to_deg(2.0 * atan(0.96 / maxf(aspect, 0.5))))


func _enable_reading_environment() -> void:
	_saved_environment = camera.environment
	var source := _saved_environment
	if source == null:
		source = camera.get_world_3d().environment
	var reading := source.duplicate(true) as Environment if source != null else Environment.new()
	# The room's strong bloom otherwise washes printed ink out of the paper.
	# Keep the override on this camera and restore the original resource on exit.
	reading.glow_enabled = false
	reading.fog_enabled = false
	reading.volumetric_fog_enabled = false
	camera.environment = reading


func _restore_reading_environment() -> void:
	if is_instance_valid(camera):
		camera.environment = _saved_environment
	_saved_environment = null


func close_journal(immediate: bool = false) -> void:
	if not is_active() or (_phase == Phase.CLOSING and not immediate):
		return
	_cancel_page_turn()
	if _motion_tween != null:
		_motion_tween.kill()
		_motion_tween = null
	_paper_contents.hide()
	_tab_contents.hide()
	_phase = Phase.CLOSING
	if immediate or not is_instance_valid(camera):
		_finish_close()
		return
	_sound.play()
	_motion_tween = create_tween().set_parallel(true)
	_motion_tween.tween_property(camera, "global_transform", _saved_camera_pose, close_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.tween_property(camera, "fov", _saved_fov, close_duration)
	_motion_tween.tween_property(self, "global_transform", _stowed_pose, close_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion_tween.tween_method(_book.set_open_amount, float(_book.get_open_amount()), 0.0, close_duration)
	_motion_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	if is_instance_valid(camera):
		camera.global_transform = _saved_camera_pose
		camera.fov = _saved_fov
	_restore_reading_environment()
	_motion_tween = null
	_phase = Phase.CLOSED
	_hover = ""
	hide()
	closed.emit()


func _process(delta: float) -> void:
	if not is_active():
		return
	if not is_instance_valid(camera) or get_viewport().get_camera_3d() != camera:
		close_journal(true)
		return
	if _phase == Phase.OPEN:
		camera.fov = _reading_fov()
		if is_open() and _collection_refresh_pending and _is_collection_chapter():
			_build_spread()
		if is_open() and str(chapters[chapter_index]["id"]) == "profile":
			_profile_refresh_elapsed += delta
			if _profile_refresh_elapsed >= 0.5:
				_profile_refresh_elapsed = 0.0
				refresh_profile()
	var target := _hit_target(get_viewport().get_mouse_position()) if is_open() else ""
	if target != _hover:
		_hover = target
		_update_highlights()
		if target.begins_with("collection_card:"):
			var index := int(target.trim_prefix("collection_card:"))
			if index >= 0 and index < _collection_cards.size() and is_instance_valid(_collection_cards[index]):
				CollectionManager.mark_card_seen(str(_collection_cards[index].card_data.get("id", "")))
	_update_collection_hover(delta)


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
		return
	if event is InputEventKey:
		# Main handles the J toggle; all other keys stay out of the world.
		if not event.is_action("journal"):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
	if not is_open() or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		change_index_page(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_press_button(_hit_target(event.position))


func _entries() -> Array:
	return chapters[chapter_index]["entries"] if not chapters.is_empty() else []


func _is_collection_chapter() -> bool:
	return not chapters.is_empty() and str(chapters[chapter_index]["id"]) == "collection"


func _index_page_size() -> int:
	return COLLECTION_PAGE_SIZE if _is_collection_chapter() else INDEX_SIZE


func _on_collection_changed(_ids: Array[String]) -> void:
	_collection_refresh_pending = true


func refresh_profile(rebuild: bool = true) -> void:
	for index in range(chapters.size()):
		if str(chapters[index]["id"]) != "profile":
			continue
		var updated := CONTENT.build_profile_chapter()
		if updated != chapters[index]:
			chapters[index] = updated
			if rebuild and chapter_index == index and not _flipping:
				_build_spread()
		return


func _on_locale_changed() -> void:
	# Names are sorted in the chosen language. Keep the selected subject by
	# its stable identity rather than jumping to a different sorted row.
	var chapter_id := str(chapters[chapter_index]["id"]) if not chapters.is_empty() else "cards"
	var old_entries := _entries()
	var entry_id := str(old_entries[entry_index]["id"]) if entry_index >= 0 and entry_index < old_entries.size() else ""
	_cancel_page_turn()
	chapters = CONTENT.build_chapters()
	chapter_index = 0
	for index in range(chapters.size()):
		if str(chapters[index]["id"]) == chapter_id:
			chapter_index = index
			break
	entry_index = 0
	var entries := _entries()
	for index in range(entries.size()):
		if str(entries[index]["id"]) == entry_id:
			entry_index = index
			break
	index_page = entry_index / _index_page_size()
	_hover = ""
	_build_spread()
	_paper_contents.visible = _phase == Phase.OPEN
	_tab_contents.visible = _phase == Phase.OPEN


func set_chapter(index: int) -> void:
	if not is_open() or index < 0 or index >= chapters.size() or index == chapter_index:
		return
	chapter_index = index
	entry_index = 0
	index_page = 0
	body_page = 0
	if str(chapters[index]["id"]) == "profile":
		refresh_profile(false)
	_turn_page()


func select_entry(index: int) -> void:
	if not is_open() or _is_collection_chapter() or index < 0 or index >= _entries().size() or index == entry_index:
		return
	entry_index = index
	body_page = 0
	_build_spread()


func change_index_page(direction: int) -> void:
	if not is_open():
		return
	var page_size := _index_page_size()
	var next := clampi(index_page + signi(direction), 0, maxi(ceili(_entries().size() / float(page_size)) - 1, 0))
	if next == index_page:
		return
	index_page = next
	entry_index = index_page * page_size
	body_page = 0
	_build_spread()


func change_body_page(direction: int) -> void:
	if not is_open():
		return
	var next := clampi(body_page + signi(direction), 0, maxi(_body_pages.size() - 1, 0))
	if next == body_page:
		return
	body_page = next
	_build_spread()


func _press_button(action: String) -> void:
	if action.begins_with("collection_card:"):
		_open_collection_card(int(action.trim_prefix("collection_card:")))
		return
	if action.is_empty() or not _buttons.has(action) or not bool(_buttons[action]["enabled"]):
		return
	if action.begins_with("chapter:"):
		set_chapter(int(action.trim_prefix("chapter:")))
	elif action.begins_with("entry:"):
		select_entry(index_page * INDEX_SIZE + int(action.trim_prefix("entry:")))
	else:
		match action:
			"index_prev": change_index_page(-1)
			"index_next": change_index_page(1)
			"body_prev": change_body_page(-1)
			"body_next": change_body_page(1)


func _open_collection_card(index: int) -> void:
	if not is_open() or not _is_collection_chapter() or index < 0 or index >= _collection_cards.size():
		return
	if not is_instance_valid(_collection_cards[index]):
		return
	# Resolve the original catalog entry by identity: rarity order and
	# translated card names place the same card at different list indices.
	var entry_id := str(_entries()[index_page * COLLECTION_PAGE_SIZE + index]["id"]).trim_prefix("collection:")
	for destination in range(chapters.size()):
		if str(chapters[destination]["id"]) not in ["cards", "special_cards"]:
			continue
		var entries: Array = chapters[destination]["entries"]
		for entry in range(entries.size()):
			if str(entries[entry]["id"]) != entry_id:
				continue
			chapter_index = destination
			entry_index = entry
			index_page = entry / INDEX_SIZE
			body_page = 0
			_turn_page()
			return


func _turn_page() -> void:
	_flipping = true
	_paper_contents.hide()
	_build_chapter_tabs()
	_update_highlights()
	_sound.play()
	_page_leaf = Node3D.new()
	_page_leaf.position.z = 0.14
	add_child(_page_leaf)
	_box(_page_leaf, Vector3(3.02, 4.12, 0.009), Vector3(1.58, 0, 0), PAPER)
	_page_tween = create_tween()
	_page_tween.tween_property(_page_leaf, "rotation:y", -PI, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_page_tween.tween_callback(func():
		_cancel_page_turn()
		_build_spread()
		_paper_contents.show()
	)


func _cancel_page_turn() -> void:
	if _page_tween != null:
		_page_tween.kill()
	_page_tween = null
	if is_instance_valid(_page_leaf):
		_page_leaf.queue_free()
	_page_leaf = null
	_flipping = false


func _build_spread() -> void:
	for child in _paper_contents.get_children():
		# Locale callbacks on card previews can still run during this signal.
		# Keep retiring nodes in the tree until their queued deletion completes.
		if child is Node3D:
			child.hide()
		# Release the footer names before building the next spread this frame.
		if child.name in [&"CollectionPageLeft", &"CollectionPageRight"]:
			child.name = "RetiredCollectionPage_%d" % child.get_instance_id()
		child.queue_free()
	# Chapter tabs belong to the cover and stay in place while pages change.
	for action: String in _buttons.keys():
		if not action.begins_with("chapter:"):
			_buttons.erase(action)
	_collection_cards.clear()
	_collection_slots.clear()
	_collection_rest_transforms.clear()
	_collection_hover_amounts.clear()
	_body_label = null
	_entry_title = null
	_body_pages.clear()
	_hover = ""
	if chapters.is_empty():
		return
	var entries := _entries()
	_build_chapter_tabs()
	if _is_collection_chapter():
		_build_collection_spread(entries)
		_collection_refresh_pending = false
		_update_highlights()
		return
	_label(str(chapters[chapter_index]["title"]).to_upper(), Vector3(-3.07, 1.85, 0.11), 56)
	_label(Localization.format_text("%d EINTRÄGE", [entries.size()]), Vector3(-3.07, 1.53, 0.11), 30)
	for row in range(INDEX_SIZE):
		var index := index_page * INDEX_SIZE + row
		if index >= entries.size():
			break
		var title := str(entries[index]["title"])
		while _text_width(title, 42) > 2.65:
			title = title.trim_suffix("…").substr(0, title.trim_suffix("…").length() - 1) + "…"
		_button("entry:%d" % row, title, Vector3(-1.66, 1.18 - row * 0.282, 0.11), Vector2(2.82, 0.245), true, index == entry_index, true)
	var index_pages := maxi(ceili(entries.size() / float(INDEX_SIZE)), 1)
	_button("index_prev", "<", Vector3(-2.87, -1.86, 0.11), Vector2(0.34, 0.28), index_page > 0)
	_button("index_next", ">", Vector3(-0.46, -1.86, 0.11), Vector2(0.34, 0.28), index_page + 1 < index_pages)
	_label("%d / %d" % [index_page + 1, index_pages], Vector3(-1.66, -1.86, 0.13), 26, false)
	if entries.is_empty():
		return
	entry_index = clampi(entry_index, 0, entries.size() - 1)
	var entry: Dictionary = entries[entry_index]
	_entry_title = _label(str(entry["title"]), Vector3(0.28, 1.91, 0.11), 54)
	_entry_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry_title.width = 1100
	_entry_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_fit_heading(_entry_title, 2.75, 36)
	var subtitle := _label(str(entry.get("subtitle", "")), Vector3(0.28, 1.54, 0.11), 40)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.width = 1100
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_fit_heading(subtitle, 2.75, 28)
	var profile_overview := entry.has("profile_strength")
	var illustrated := entry.has("card_data") or not str(entry.get("icon_path", "")).is_empty() or profile_overview
	if entry.has("card_data"):
		var card := CARD_SCENE.instantiate() as Card3D
		_paper_contents.add_child(card)
		card.setup(CardData.merge_card_and_instance(entry["card_data"]))
		card.description_label.skip()
		card.position = Vector3(1.66, 0.82, 0.15)
		card.scale = Vector3.ONE * 0.90
		_disable_card_input(card)
	elif profile_overview:
		var strength_caption := _label(Localization.text("GESAMTSTÄRKE"), Vector3(1.66, 1.04, 0.13), 36, false)
		_fit_heading(strength_caption, 2.70, 24)
		var strength_value := _label(str(entry["profile_strength"]), Vector3(1.66, 0.65, 0.13), 128, false)
		strength_value.name = "ProfileStrength"
		strength_value.modulate = ACCENT
		_fit_heading(strength_value, 2.70, 36)
	elif illustrated:
		var icon := Sprite3D.new()
		icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		icon.texture = load(str(entry["icon_path"])) as Texture2D
		if icon.texture != null:
			icon.pixel_size = 0.80 / maxf(icon.texture.get_width(), icon.texture.get_height())
		icon.position = Vector3(1.66, 0.84, 0.14)
		_box(_paper_contents, Vector3(1.04, 1.04, 0.009), Vector3(1.66, 0.84, 0.12), INK)
		_paper_contents.add_child(icon)
	_body_pages = _paginate(str(entry.get("body", "")), 36, 12 if illustrated else 20)
	body_page = clampi(body_page, 0, maxi(_body_pages.size() - 1, 0))
	_body_label = _label(_body_pages[body_page], Vector3(0.28, 0.12 if illustrated else 1.14, 0.12), 46)
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if _body_pages.size() > 1:
		_button("body_prev", "<", Vector3(0.53, -1.86, 0.11), Vector2(0.34, 0.28), body_page > 0)
		_button("body_next", ">", Vector3(2.89, -1.86, 0.11), Vector2(0.34, 0.28), body_page + 1 < _body_pages.size())
		_label("%d / %d" % [body_page + 1, _body_pages.size()], Vector3(1.66, -1.86, 0.13), 26, false)
	_update_highlights()


func _build_chapter_tabs() -> void:
	var tab_slot_height := 3.90 / chapters.size()
	var tab_height := minf(0.92, tab_slot_height - 0.05)
	for index in range(chapters.size()):
		var action := "chapter:%d" % index
		var tab_y := 1.95 - (index + 0.5) * tab_slot_height
		if not _buttons.has(action):
			_button(action, "", Vector3(3.47, tab_y, 0.11), Vector2(0.36, tab_height))
			(_buttons[action]["node"] as Node3D).reparent(_tab_contents, false)
			(_buttons[action]["label"] as Node3D).reparent(_tab_contents, false)
			# The raised page can project over the cover edge while turning.
			# Keep both the tab backing and its text in front of that sheet.
			var tab_material := _buttons[action]["node"].material_override as StandardMaterial3D
			tab_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tab_material.no_depth_test = true
			tab_material.render_priority = 2
		_buttons[action]["selected"] = index == chapter_index
		var tab_label := _buttons[action]["label"] as Label3D
		tab_label.no_depth_test = true
		tab_label.render_priority = 3
		tab_label.text = str(chapters[index]["title"]).to_upper()
		tab_label.rotation.z = -PI / 2.0
		tab_label.font_size = 34
		_fit_heading(tab_label, tab_height - 0.10, 16)


func _build_collection_spread(entries: Array) -> void:
	var page_count := maxi(ceili(entries.size() / float(COLLECTION_PAGE_SIZE)), 1)
	index_page = clampi(index_page, 0, page_count - 1)
	var first := index_page * COLLECTION_PAGE_SIZE
	var discovered := CollectionManager.get_discovered_card_ids()
	for index in range(first, mini(first + COLLECTION_PAGE_SIZE, entries.size())):
		var cell := index - first
		var on_page := cell % 9
		var page_center := -1.66 if cell < 9 else 1.66
		var at := Vector3(page_center + (on_page % 3 - 1) * 0.91, 1.22 - (on_page / 3) * 1.17, 0.15)
		var data: Dictionary = entries[index]["card_data"]
		var card_id := str(data.get("id", ""))
		var slot: Node3D
		var card: Card3D = null
		if discovered.has(card_id):
			card = CARD_SCENE.instantiate() as Card3D
			_paper_contents.add_child(card)
			card.setup(CardData.merge_card_and_instance(data))
			card.description_label.skip()
			_disable_card_input(card)
			if CollectionManager.is_card_new(card_id):
				var new_label := NEW_CARD_LABEL.new()
				new_label.name = "NewLabel"
				card.add_child(new_label)
				new_label.watch_collection_card(card_id)
			slot = card
		else:
			slot = _create_collection_placeholder()
		slot.name = "CollectionSlot_%d" % index
		slot.set_meta("catalog_id", card_id)
		slot.set_meta("entry_id", str(entries[index]["id"]))
		slot.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * COLLECTION_CARD_SCALE), at)
		_collection_slots.append(slot)
		_collection_cards.append(card)
		_collection_rest_transforms.append(slot.transform)
		_collection_hover_amounts.append(0.0)
	_button("index_prev", "<", Vector3(-2.87, -1.86, 0.11), Vector2(0.34, 0.28), index_page > 0)
	_button("index_next", ">", Vector3(2.87, -1.86, 0.11), Vector2(0.34, 0.28), index_page + 1 < page_count)
	var left_number := _label(str(index_page * 2 + 1), Vector3(-1.66, -1.86, 0.13), 26, false)
	left_number.name = "CollectionPageLeft"
	var right_number := _label(str(index_page * 2 + 2), Vector3(1.66, -1.86, 0.13), 26, false)
	right_number.name = "CollectionPageRight"


func _create_collection_placeholder() -> Node3D:
	var slot := Node3D.new()
	_paper_contents.add_child(slot)
	if _collection_border == null:
		_collection_border = MultiMesh.new()
		_collection_border.transform_format = MultiMesh.TRANSFORM_3D
		var dash := QuadMesh.new()
		dash.size = Vector2.ONE
		_collection_border.mesh = dash
		_collection_border.instance_count = 40
		var dash_index := 0
		for side in [-1.0, 1.0]:
			for index in range(8):
				var x := ((index + 0.5) / 8.0 - 0.5) * COLLECTION_CARD_SIZE.x
				_collection_border.set_instance_transform(dash_index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.064, 0.016, 1)), Vector3(x, side * COLLECTION_CARD_SIZE.y * 0.5, 0)))
				dash_index += 1
			for index in range(12):
				var y := ((index + 0.5) / 12.0 - 0.5) * COLLECTION_CARD_SIZE.y
				_collection_border.set_instance_transform(dash_index, Transform3D(Basis.IDENTITY.scaled(Vector3(0.016, 0.061, 1)), Vector3(side * COLLECTION_CARD_SIZE.x * 0.5, y, 0)))
				dash_index += 1
	var border := MultiMeshInstance3D.new()
	border.name = "DashedBorder"
	border.multimesh = _collection_border
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("796b56")
	border.material_override = ink
	slot.add_child(border)
	var question := Sprite3D.new()
	question.name = "Placeholder"
	question.texture = COLLECTION_PLACEHOLDER
	question.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	question.pixel_size = 0.32 / maxf(COLLECTION_PLACEHOLDER.get_width(), COLLECTION_PLACEHOLDER.get_height())
	question.modulate = INK
	question.position.z = 0.01
	slot.add_child(question)
	return slot


func _update_collection_hover(delta: float) -> void:
	for index in range(_collection_cards.size()):
		var card := _collection_cards[index]
		if not is_instance_valid(card):
			continue
		var active := is_open() and _hover == "collection_card:%d" % index
		var amount := move_toward(_collection_hover_amounts[index], 1.0 if active else 0.0, delta / 0.18)
		_collection_hover_amounts[index] = amount
		var rest := _collection_rest_transforms[index]
		if is_zero_approx(amount):
			card.transform = rest
			continue
		var at := rest.origin + Vector3(0, 0, COLLECTION_HOVER_LIFT)
		var front := (_paper_contents.to_local(camera.global_position) - at).normalized()
		var up := (_paper_contents.global_basis.inverse() * camera.global_basis.y).normalized()
		var right := up.cross(front).normalized()
		up = front.cross(right).normalized()
		var facing := Basis(right, up, front).scaled(Vector3.ONE * COLLECTION_CARD_SCALE * COLLECTION_HOVER_SCALE)
		var eased := amount * amount * (3.0 - 2.0 * amount)
		card.transform = rest.interpolate_with(Transform3D(facing, at), eased)


func _paginate(text: String, columns: int, rows: int) -> Array[String]:
	var lines: Array[String] = []
	var max_width := minf(_text_width("M".repeat(columns), 46), 2.74)
	for paragraph in text.split("\n"):
		var line := ""
		for word: String in paragraph.split(" ", false):
			if not line.is_empty() and _text_width(line + " " + word, 46) > max_width:
				lines.append(line)
				line = ""
			# Long translated compound words must fit too; character counts are
			# insufficient when the font uses fallback glyphs for Polish accents.
			while _text_width(word, 46) > max_width:
				var split_at := 1
				while split_at < word.length() and _text_width(word.substr(0, split_at + 1), 46) <= max_width:
					split_at += 1
				lines.append(word.substr(0, split_at))
				word = word.substr(split_at)
			line += (" " if not line.is_empty() else "") + word
		lines.append(line)
	var pages: Array[String] = []
	# Accented fallback glyphs can make a line taller than the pixel font.
	# Keep the row cap, but also fit the actual space above the page arrows.
	var max_height := 1.83 if rows <= 12 else 2.85
	var first := 0
	while first < lines.size():
		var last := mini(first + maxi(rows, 1), lines.size())
		var page := "\n".join(lines.slice(first, last))
		while last > first + 1 and FONT.get_multiline_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).y * 0.0025 > max_height:
			last -= 1
			page = "\n".join(lines.slice(first, last))
		pages.append(page)
		first = last
	if pages.is_empty():
		pages.append("")
	return pages


func _text_width(text: String, size: int) -> float:
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.0025


func _fit_heading(label: Label3D, max_width: float, minimum_size: int) -> void:
	while label.font_size > minimum_size and _text_width(label.text, label.font_size) > max_width:
		label.font_size -= 1


func _label(text: String, at: Vector3, size: int, align_left: bool = true) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = size
	label.pixel_size = 0.0025
	label.position = at
	label.modulate = INK
	label.outline_size = 0
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if align_left else HORIZONTAL_ALIGNMENT_CENTER
	_paper_contents.add_child(label)
	return label


func _button(action: String, text: String, at: Vector3, dimensions: Vector2, enabled: bool = true, selected: bool = false, align_left: bool = false) -> void:
	var mesh := _box(_paper_contents, Vector3(dimensions.x, dimensions.y, 0.009), at, PAPER)
	var label := _label(text, at + Vector3(-dimensions.x * 0.47 if align_left else 0.0, 0, 0.012), 42, align_left)
	_buttons[action] = {"node": mesh, "label": label, "size": dimensions, "enabled": enabled, "selected": selected}


func _box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


func _update_highlights() -> void:
	for action: String in _buttons:
		var button: Dictionary = _buttons[action]
		var selected := bool(button["selected"])
		var hovered := _hover == action and bool(button["enabled"])
		(button["node"].material_override as StandardMaterial3D).albedo_color = Color("9b8064") if hovered else (Color("a18a70") if selected else PAPER)
		(button["label"] as Label3D).modulate = ACCENT if selected else (INK if bool(button["enabled"]) else Color("8a7a63"))


func _hit_target(point: Vector2) -> String:
	if not is_instance_valid(camera) or not get_viewport().get_visible_rect().has_point(point):
		return ""
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := INF
	var target := ""
	for action: String in _buttons:
		var node := _buttons[action]["node"] as Node3D
		var normal := node.global_basis.z.normalized()
		if normal.dot(direction) >= -0.001:
			continue
		var hit: Variant = Plane(normal, node.global_position).intersects_ray(origin, direction)
		if hit == null:
			continue
		var local: Vector3 = node.to_local(hit)
		var size: Vector2 = _buttons[action]["size"]
		var distance := origin.distance_to(hit)
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5 and distance < nearest:
			nearest = distance
			target = action
	if not target.is_empty():
		return target
	# Pick against fixed positions on the paper so lifting a card cannot lose hover.
	var normal := _paper_contents.global_basis.z.normalized()
	if normal.dot(direction) >= -0.001:
		return ""
	var hit: Variant = Plane(normal, _paper_contents.to_global(Vector3(0, 0, 0.15))).intersects_ray(origin, direction)
	if hit == null:
		return ""
	var on_paper := _paper_contents.to_local(hit)
	var half_size := COLLECTION_CARD_SIZE * COLLECTION_CARD_SCALE * 0.5
	for index in range(_collection_cards.size()):
		if not is_instance_valid(_collection_cards[index]):
			continue
		var center := _collection_rest_transforms[index].origin
		if absf(on_paper.x - center.x) <= half_size.x and absf(on_paper.y - center.y) <= half_size.y:
			return "collection_card:%d" % index
	return ""


func _disable_card_input(node: Node) -> void:
	if node is CollisionObject3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)


func _exit_tree() -> void:
	_cancel_page_turn()
	if _motion_tween != null:
		_motion_tween.kill()
	if is_active() and is_instance_valid(camera):
		camera.global_transform = _saved_camera_pose
		camera.fov = _saved_fov
	if is_active():
		_restore_reading_environment()
