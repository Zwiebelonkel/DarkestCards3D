extends Node3D
class_name FusionWorkbench

signal fusion_completed(result: Dictionary)

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const MODEL_SCRIPT := preload("res://scripts/props/FusionWorkbenchModel.gd")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const CLICK_SOUND := preload("res://assets/sounds/SFX/button.mp3")
const FORGE_SOUND := preload("res://assets/sounds/SFX/rare.mp3")
const PAGE_SIZE := 12
const CARD_SIZE := Vector2(0.792, 1.14)
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic", "secret"]

@export var camera: Camera3D
@export_range(0, 3, 1) var view_side := 1

var selected_instance_ids: Array[String] = []
var rarity_filter := ""
var page_index := 0
var focus_area: Area3D
var _interaction_enabled := false
var _busy := false
var _result_mode := false
var _refresh_pending := false
var _candidates: Array = []
var _by_id: Dictionary = {}
var _filtered: Array = []
var _inventory_cards: Dictionary = {}
var _inventory_marks: Dictionary = {}
var _slot_cards: Array[Card3D] = []
var _buttons: Dictionary = {}
var _inventory_root: Node3D
var _slots_root: Node3D
var _slot_bases_root: Node3D
var _model: Node3D
var _title: Label3D
var _rarity_label: Label3D
var _page_label: Label3D
var _empty_label: Label3D
var _reward_card: Card3D
var _reward_data: Dictionary = {}
var _hover_target := ""
var _fusion_tween: Tween
var _click_audio: AudioStreamPlayer3D
var _forge_audio: AudioStreamPlayer3D


func _ready() -> void:
	Localization.locale_changed.connect(_queue_refresh)
	_build_workbench()
	CollectionManager.collection_changed.connect(_queue_refresh)
	refresh_collection()


func _process(_delta: float) -> void:
	if _refresh_pending and not _busy:
		refresh_collection()
	var target := _hit_target(get_viewport().get_mouse_position()) if _can_interact() else ""
	if target != _hover_target:
		_hover_target = target
		_update_highlights()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact() or not event is InputEventMouseButton or not event.pressed:
		return
	var target := _hit_target(event.position)
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if _pointer_over_workbench(event.position) and not _result_mode:
			change_page(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
		return
	if target.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if target.begins_with("card:"):
			select_instance(target.trim_prefix("card:"))
		elif target.begins_with("slot:"):
			remove_selected(int(target.trim_prefix("slot:")))
		elif target.begins_with("button:"):
			_press_button(target.trim_prefix("button:"))
	else:
		return
	get_viewport().set_input_as_handled()


func set_interaction_enabled(enabled: bool) -> void:
	if _interaction_enabled == enabled:
		return
	_interaction_enabled = enabled
	if is_instance_valid(focus_area):
		focus_area.input_ray_pickable = enabled
	if enabled:
		# Deck copies may have changed while looking at another station.
		_refresh_pending = true
	else:
		_hover_target = ""
		_update_highlights()


func is_busy() -> bool:
	return _busy


func _can_interact() -> bool:
	return _interaction_enabled and not _busy and is_visible_in_tree() and not get_tree().paused and is_instance_valid(camera) and get_viewport().get_camera_3d() == camera


func _queue_refresh(_ids: Array = []) -> void:
	_refresh_pending = true


func refresh_collection() -> void:
	_refresh_pending = false
	if not is_instance_valid(_inventory_root) or _busy:
		return
	_candidates.clear()
	for entry: Dictionary in CollectionManager.get_fusion_candidates():
		if str(entry["card_data"].get("category", "")).to_lower() == "special":
			continue
		_candidates.append(entry)
	_candidates.sort_custom(_sort_candidates)
	_by_id.clear()
	for entry: Dictionary in _candidates:
		_by_id[str(entry["instance_id"])] = entry
	var surviving: Array[String] = []
	for id: String in selected_instance_ids:
		if surviving.size() < CollectionManager.get_fusion_requirement() and _by_id.has(id) and bool(_by_id[id]["eligible"]):
			surviving.append(id)
	selected_instance_ids = surviving
	_filtered.clear()
	for entry: Dictionary in _candidates:
		if rarity_filter.is_empty() or str(entry["rarity"]) == rarity_filter:
			_filtered.append(entry)
	page_index = clampi(page_index, 0, maxi(ceili(_filtered.size() / float(PAGE_SIZE)) - 1, 0))
	_clear_children(_inventory_root)
	_inventory_cards.clear()
	_inventory_marks.clear()
	var first := page_index * PAGE_SIZE
	for index in range(first, mini(first + PAGE_SIZE, _filtered.size())):
		var entry: Dictionary = _filtered[index]
		var id := str(entry["instance_id"])
		var cell := index - first
		var position_in_grid := Vector3((cell % 6 - 2.5) * 0.98, 3.70 - (cell / 6) * 1.10, 0.09)
		var card := _create_card(entry["card_data"], _inventory_root)
		card.position = position_in_grid
		card.scale = Vector3.ONE * 0.72
		_inventory_cards[id] = card
		var mark := _box(_inventory_root, Vector3(0.62, 0.88, 0.025), position_in_grid - Vector3(0, 0, 0.025), Color("d59443"))
		_inventory_marks[id] = mark
		var instance: Dictionary = entry["instance"]
		var badge := Localization.format_text("ST.%d%s", [int(instance.get("level", 1)), " · HOLO" if CardData.is_holo(instance) else ""])
		if not bool(entry["eligible"]):
			badge = "GESCHÜTZT" if str(entry["rarity"]) != "exotic" else "MAXIMUM"
		var badge_label := _label(badge, position_in_grid + Vector3(0, -0.47, 0.03), 18, 0.0044)
		badge_label.modulate = Color("b2a392") if bool(entry["eligible"]) else Color("d99079")
		_inventory_root.add_child(badge_label)
	_empty_label.visible = _filtered.is_empty() and not _result_mode
	_empty_label.text = "NOCH KEINE KARTEN" if _candidates.is_empty() else "KEINE KARTEN DIESER SELTENHEIT"
	_rarity_label.text = "ALLE SELTENHEITEN" if rarity_filter.is_empty() else _rarity_name(rarity_filter)
	_page_label.text = "%d / %d" % [page_index + 1, maxi(ceili(_filtered.size() / float(PAGE_SIZE)), 1)]
	_rebuild_slots()
	_refresh_buttons()
	_update_highlights()


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var ar := RARITIES.find(str(a["rarity"]))
	var br := RARITIES.find(str(b["rarity"]))
	if ar != br:
		return ar < br
	var an := str(a["card_data"].get("name", a["card_id"]))
	var bn := str(b["card_data"].get("name", b["card_id"]))
	return str(a["instance_id"]) < str(b["instance_id"]) if an == bn else an.naturalnocasecmp_to(bn) < 0


func select_instance(id: String) -> bool:
	if not _can_interact() or _result_mode or not _by_id.has(id):
		return false
	var selected_index := selected_instance_ids.find(id)
	if selected_index >= 0:
		remove_selected(selected_index)
		return true
	var entry: Dictionary = _by_id[id]
	if not bool(entry["eligible"]):
		return false
	if selected_instance_ids.size() >= CollectionManager.get_fusion_requirement():
		return false
	if not selected_instance_ids.is_empty() and str(_by_id[selected_instance_ids[0]]["rarity"]) != str(entry["rarity"]):
		return false
	selected_instance_ids.append(id)
	_click_audio.play()
	if selected_instance_ids.size() == 1 and rarity_filter != str(entry["rarity"]):
		rarity_filter = str(entry["rarity"])
		page_index = 0
	refresh_collection()
	return true


func remove_selected(index: int) -> void:
	if not _can_interact() or index < 0 or index >= selected_instance_ids.size():
		return
	selected_instance_ids.remove_at(index)
	_click_audio.play()
	_rebuild_slots()
	_refresh_buttons()
	_update_highlights()


func change_page(direction: int) -> void:
	if not _can_interact() or _result_mode:
		return
	var next := clampi(page_index + signi(direction), 0, maxi(ceili(_filtered.size() / float(PAGE_SIZE)) - 1, 0))
	if next == page_index:
		return
	page_index = next
	_click_audio.play()
	refresh_collection()


func cycle_rarity(direction: int) -> void:
	if not _can_interact() or _result_mode:
		return
	var index := 0 if rarity_filter.is_empty() else RARITIES.find(rarity_filter) + 1
	index = posmod(index + signi(direction), RARITIES.size() + 1)
	rarity_filter = "" if index == 0 else RARITIES[index - 1]
	page_index = 0
	_click_audio.play()
	refresh_collection()


func _press_button(action: String) -> void:
	if not _buttons.has(action) or not bool(_buttons[action]["enabled"]):
		return
	match action:
		"page_prev": change_page(-1)
		"page_next": change_page(1)
		"rarity_prev": cycle_rarity(-1)
		"rarity_next": cycle_rarity(1)
		"clear":
			selected_instance_ids.clear()
			_click_audio.play()
			refresh_collection()
		"fuse":
			if _result_mode:
				dismiss_result()
			else:
				start_fusion()


func start_fusion() -> void:
	if not _can_interact() or _result_mode:
		return
	var validation := CollectionManager.validate_fusion(selected_instance_ids)
	if not bool(validation["ok"]):
		refresh_collection()
		return
	_busy = true
	# The reward is saved atomically before its animation: leaving the scene
	# can never destroy the inputs without delivering their new card.
	var result := CollectionManager.fuse_card_instances(selected_instance_ids.duplicate())
	if not bool(result["ok"]):
		_busy = false
		refresh_collection()
		_buttons["fuse"]["label"].text = "FEHLGESCHLAGEN"
		return
	_reward_data = (result["card_data"] as Dictionary).duplicate(true)
	fusion_completed.emit(result)
	selected_instance_ids.clear()
	_inventory_root.hide()
	_empty_label.hide()
	_title.text = "DIE SCHMIEDE ARBEITET"
	_model.set_forging(true)
	_forge_audio.play()
	_refresh_buttons()
	_fusion_tween = create_tween().set_parallel(true)
	for index in range(_slot_cards.size()):
		var card := _slot_cards[index]
		_fusion_tween.tween_property(card, "position", Vector3(0, 2.1, 0.85), 0.65).set_delay(index * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_fusion_tween.tween_property(card, "scale", Vector3.ONE * 0.015, 0.65).set_delay(index * 0.07)
	await _fusion_tween.finished
	_clear_children(_slots_root)
	_slot_cards.clear()
	_reward_card = _create_card(_reward_data, self)
	_reward_card.position = Vector3(0, 3.1, 0.9)
	_reward_card.scale = Vector3.ONE * 0.015
	_fusion_tween = create_tween()
	_fusion_tween.tween_property(_reward_card, "scale", Vector3.ONE * 1.45, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _fusion_tween.finished
	_fusion_tween = null
	_model.set_forging(false)
	_busy = false
	_result_mode = true
	_title.text = "NEU GESCHMIEDET"
	refresh_collection()
	_inventory_root.hide()


func dismiss_result() -> void:
	if not _can_interact() or not _result_mode:
		return
	if is_instance_valid(_reward_card):
		_reward_card.queue_free()
	_reward_card = null
	_reward_data.clear()
	_result_mode = false
	_title.text = "KARTENSCHMIEDE"
	_inventory_root.show()
	refresh_collection()


func _rebuild_slots() -> void:
	_clear_children(_slots_root)
	_clear_children(_slot_bases_root)
	_slot_cards.clear()
	var required := CollectionManager.get_fusion_requirement()
	for index in range(required):
		var x := (index - (required - 1) * 0.5) * 1.08
		_box(_slot_bases_root, Vector3(0.82, 0.07, 0.68), Vector3(x, 1.59, 1.36), Color("4e4437"))
		if index >= selected_instance_ids.size() or _result_mode:
			continue
		var id := selected_instance_ids[index]
		var card := _create_card(_by_id[id]["card_data"], _slots_root)
		card.position = Vector3(x, 1.95, 1.35)
		card.scale = Vector3.ONE * 0.58
		_slot_cards.append(card)


func _refresh_buttons() -> void:
	for action: String in _buttons:
		var enabled := not _busy and not _result_mode
		match action:
			"page_prev": enabled = enabled and page_index > 0
			"page_next": enabled = enabled and (page_index + 1) * PAGE_SIZE < _filtered.size()
			"clear": enabled = enabled and not selected_instance_ids.is_empty()
			"fuse":
				enabled = not _busy and (_result_mode or selected_instance_ids.size() == CollectionManager.get_fusion_requirement())
				_buttons[action]["label"].text = "WEITER" if _result_mode else Localization.format_text("FUSIONIEREN  %d / %d", [selected_instance_ids.size(), CollectionManager.get_fusion_requirement()])
		_buttons[action]["enabled"] = enabled
	_update_highlights()


func _update_highlights() -> void:
	for id: String in _inventory_marks:
		_inventory_marks[id].visible = selected_instance_ids.has(id) or _hover_target == "card:" + id
	for action: String in _buttons:
		var button: Dictionary = _buttons[action]
		var material := (button["node"] as MeshInstance3D).material_override as StandardMaterial3D
		var enabled := bool(button["enabled"])
		material.albedo_color = Color("83562c") if enabled else Color("292925")
		if enabled and _hover_target == "button:" + action:
			material.albedo_color = Color("be8748")
		button["label"].modulate = Color("fff0cc") if enabled else Color("807a70")


func _hit_target(point: Vector2) -> String:
	if not is_instance_valid(camera) or not is_visible_in_tree():
		return ""
	var nearest := INF
	var target := ""
	if not _result_mode:
		for id: String in _inventory_cards:
			var distance := _ray_distance(_inventory_cards[id], CARD_SIZE, point)
			if distance < nearest:
				nearest = distance
				target = "card:" + id
		for index in range(_slot_cards.size()):
			var distance := _ray_distance(_slot_cards[index], CARD_SIZE, point)
			if distance < nearest:
				nearest = distance
				target = "slot:%d" % index
	for action: String in _buttons:
		var distance := _ray_distance(_buttons[action]["node"], _buttons[action]["size"], point)
		if distance < nearest:
			nearest = distance
			target = "button:" + action
	return target


func _ray_distance(node: Node3D, dimensions: Vector2, point: Vector2) -> float:
	if not node.is_visible_in_tree() or camera.is_position_behind(node.global_position) or not get_viewport().get_visible_rect().has_point(point):
		return INF
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var normal := node.global_basis.z.normalized()
	if normal.dot(direction) >= -0.001:
		return INF
	var hit: Variant = Plane(normal, node.global_position).intersects_ray(origin, direction)
	if hit == null:
		return INF
	var local: Vector3 = node.to_local(hit)
	if absf(local.x) > dimensions.x * 0.5 or absf(local.y) > dimensions.y * 0.5:
		return INF
	return origin.distance_to(hit)


func _pointer_over_workbench(point: Vector2) -> bool:
	return is_finite(_ray_distance(focus_area, Vector2(6.8, 4.4), point))


func _create_card(data: Dictionary, parent: Node3D) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	parent.add_child(card)
	# Use the same type upgrades and copy metadata as the deck's battle cards.
	var card_id := str(data.get("card_id", data.get("id", "")))
	var upgraded := CardUpgradeManager.apply_upgrades(card_id, CardDatabase.get_card(card_id))
	card.setup(CardData.merge_card_and_instance(CardData.with_instance_metadata(upgraded, data)))
	card.description_label.skip()
	_disable_card_input(card)
	return card


func _disable_card_input(node: Node) -> void:
	if node is CollisionObject3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_card_input(child)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _rarity_name(rarity: String) -> String:
	return Localization.rarity_name(rarity, true)


func _build_workbench() -> void:
	_model = MODEL_SCRIPT.new()
	_model.name = "ForgedWorkbench"
	add_child(_model)
	focus_area = Area3D.new()
	focus_area.name = "FocusArea"
	focus_area.position = Vector3(0, 2.2, 0.7)
	focus_area.collision_layer = 0
	focus_area.collision_mask = 0
	focus_area.input_ray_pickable = false
	focus_area.set_meta("focus_distance", 6.6)
	add_child(focus_area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.8, 4.4, 2.8)
	shape.shape = box
	focus_area.add_child(shape)
	_inventory_root = Node3D.new()
	_inventory_root.name = "InventoryCards"
	add_child(_inventory_root)
	_slots_root = Node3D.new()
	_slots_root.name = "FusionInputs"
	add_child(_slots_root)
	_slot_bases_root = Node3D.new()
	_slot_bases_root.name = "FusionSlotBases"
	add_child(_slot_bases_root)
	_title = _label("KARTENSCHMIEDE", Vector3(0, 4.94, 0.03), 42, 0.006)
	add_child(_title)
	_rarity_label = _label("ALLE SELTENHEITEN", Vector3(-1.63, 4.35, 0.06), 21, 0.004)
	add_child(_rarity_label)
	_page_label = _label("1 / 1", Vector3(1.75, 4.35, 0.06), 22, 0.0043)
	add_child(_page_label)
	_make_button("rarity_prev", "<", Vector3(-2.92, 4.35, 0.08), Vector2(0.34, 0.3))
	_make_button("rarity_next", ">", Vector3(-0.34, 4.35, 0.08), Vector2(0.34, 0.3))
	_make_button("page_prev", "<", Vector3(1.0, 4.35, 0.08), Vector2(0.34, 0.3))
	_make_button("page_next", ">", Vector3(2.50, 4.35, 0.08), Vector2(0.34, 0.3))
	_make_button("fuse", "", Vector3(-0.45, 0.97, 2.04), Vector2(2.9, 0.42))
	_make_button("clear", "LEEREN", Vector3(2.15, 0.97, 2.04), Vector2(1.32, 0.42))
	_empty_label = _label("", Vector3(0, 3.18, 0.12), 26, 0.005)
	add_child(_empty_label)
	_click_audio = _make_audio(CLICK_SOUND, -13.0)
	_forge_audio = _make_audio(FORGE_SOUND, -12.0)


func _make_button(action: String, text: String, at: Vector3, size: Vector2) -> void:
	var node := _box(self, Vector3(size.x, size.y, 0.10), at, Color("83562c"))
	node.name = action.to_pascal_case()
	var label := _label(text, at + Vector3(0, 0, 0.065), 24, 0.0047)
	add_child(label)
	_buttons[action] = {"node": node, "size": size, "label": label, "enabled": false}


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _label(text: String, at: Vector3, size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = size
	label.pixel_size = pixel_size
	label.position = at
	label.modulate = Color("ecdec5")
	label.outline_size = 3
	label.shaded = false
	return label


func _make_audio(stream: AudioStream, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume
	player.unit_size = 5.0
	player.attenuation_filter_cutoff_hz = 20500.0
	player.attenuation_filter_db = 0.0
	player.position = Vector3(0, 2.0, 1.0)
	add_child(player)
	return player


func _exit_tree() -> void:
	if _fusion_tween != null:
		_fusion_tween.kill()
