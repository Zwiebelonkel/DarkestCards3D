extends Node3D
class_name AccessKeyTray
const UI_AUDIO := preload("res://scripts/ui/InterfaceSounds.gd")
const EYE_PREVIEW := preload("res://scripts/ui/JesterEyePreview.gd")

## A physical key tray mounted on the lower edge of the exploration camera.
signal key_requested(card_id: String)

const PANEL_WIDTH := 7.8
const PANEL_HEIGHT := 1.7
const STOWED_ANGLE := -200.0
const FULLSCREEN_EDGE_TOLERANCE := 2.0
const TILE_WIDTH := 1.64
const TILE_HEIGHT := 1.04
const TILE_COLOR := Color(0.13, 0.115, 0.087)
const TILE_HOVER_COLOR := Color(0.32, 0.235, 0.12)
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@export_range(4.0, 32.0, 1.0) var activation_edge_pixels := 12.0
@export_range(0.2, 0.4, 0.01) var screen_height_fraction := 0.32
@export_range(0.3, 0.48, 0.01) var release_height_fraction := 0.38

@onready var hinge: Node3D = $Hinge
@onready var frame: MeshInstance3D = $Hinge/Frame
@onready var title_label: Label3D = $Hinge/TitleLabel
@onready var empty_label: Label3D = $Hinge/EmptyLabel
@onready var hint_label: Label3D = $Hinge/HintLabel
@onready var keys_root: Node3D = $Hinge/Keys

var context_available: Callable
var key_available: Callable
var _camera: Camera3D
var _enabled := true
var _expanded := false
var _pointer_in_window := true
var _window_focused := true
var _hinge_tween: Tween
var _refresh_pending := false
var _key_tiles: Dictionary = {}
var _key_art: Dictionary = {}
var _hovered_id := ""
var _owns_cursor := false
var _animation_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = get_parent() as Camera3D
	hinge.rotation_degrees.x = STOWED_ANGLE
	CollectionManager.collection_changed.connect(_queue_refresh)
	Localization.locale_changed.connect(_refresh_localized_text)
	refresh_keys()
	_update_camera_layout()


func _exit_tree() -> void:
	_release_cursor()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_EXIT:
			_pointer_in_window = false
		NOTIFICATION_WM_MOUSE_ENTER:
			_pointer_in_window = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false
			_stow_immediately()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true


func _process(delta: float) -> void:
	_update_camera_layout()
	if _refresh_pending:
		refresh_keys()
	if not _can_display():
		_suspend_model_previews()
		_stow_immediately()
		return
	var pointer := get_viewport().get_mouse_position()
	set_pointer_position(pointer)
	_set_hover(_key_at_pointer(pointer) if _can_click() else "")
	if _expanded:
		_refresh_action_hint()
		_animation_time += delta
		for card_id: String in _key_art:
			var art: Sprite3D = _key_art[card_id]
			if card_id in ["jester_eye", "toilet_paper"]:
				art.follow_pointer(pointer, _camera, delta)
				continue
			var data := CardDatabase.get_card(card_id)
			var frame_count := clampi(int(data.get("frame_count", 1)), 1, art.hframes * art.vframes)
			art.frame = int(_animation_time * maxf(float(data.get("frame_fps", 0.0)), 0.0)) % frame_count
	else:
		_suspend_model_previews()


func _suspend_model_previews() -> void:
	for card_id: String in ["jester_eye", "toilet_paper"]:
		if _key_art.has(card_id):
			_key_art[card_id].suspend()


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not _can_display():
		return
	# Keep the tray in charge of its own surface while it is folding too.
	# In the opening animation reserve its final footprint, so a fast second
	# click cannot select a world object before the panel has arrived.
	var moving := absf(hinge.rotation_degrees.x - STOWED_ANGLE) > 0.1
	if not (_expanded or moving) or not _pointer_over_panel(event.position):
		return
	get_viewport().set_input_as_handled()
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed or not _can_click():
		return
	var card_id := _key_at_pointer(event.position)
	if not card_id.is_empty() and _key_can_be_used(card_id) and CollectionManager.get_unused_access_key_ids().has(card_id):
		key_requested.emit(card_id)


func _key_can_be_used(card_id: String) -> bool:
	if key_available.is_valid():
		return bool(key_available.call(card_id))
	return not CollectionManager.get_access_key_area_id(card_id).is_empty()


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_stow_immediately()


func is_expanded() -> bool:
	return _expanded


func set_pointer_position(pointer: Vector2) -> void:
	if not is_node_ready() or not _can_display():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var inside := Rect2(Vector2.ZERO, viewport_size).has_point(pointer)
	var fullscreen_edge := _is_fullscreen_bottom_edge(pointer, viewport_size)
	if not (inside and _pointer_in_window) and not fullscreen_edge:
		set_expanded(false)
	elif _expanded:
		if pointer.y < viewport_size.y - maxf(72.0, viewport_size.y * release_height_fraction):
			set_expanded(false)
	elif pointer.y >= viewport_size.y - activation_edge_pixels:
		set_expanded(true)


func set_expanded(value: bool) -> void:
	if not is_node_ready() or (value and not _can_display()) or _expanded == value:
		return
	_expanded = value
	if value:
		UI_AUDIO.play_panel_flip(self)
	if not value:
		_set_hover("")
	if _hinge_tween != null and _hinge_tween.is_valid():
		_hinge_tween.kill()
	_hinge_tween = create_tween()
	_hinge_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if value:
		_hinge_tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_hinge_tween.tween_property(hinge, "rotation_degrees:x", STOWED_ANGLE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func refresh_keys() -> void:
	_refresh_pending = false
	_set_hover("")
	for child in keys_root.get_children():
		keys_root.remove_child(child)
		child.queue_free()
	_key_tiles.clear()
	_key_art.clear()
	var all_keys_used := true
	for data: Dictionary in CardDatabase.get_all_cards():
		if CardData.is_access_key(data) and not CollectionManager.is_access_key_used(str(data.get("id", ""))):
			# A collectible key without a destination should only keep the tray
			# visible once actually owned, not advertise an undiscovered reward.
			var card_id := str(data.get("id", ""))
			if CollectionManager.get_access_key_area_id(card_id).is_empty() and CollectionManager.get_amount(card_id) <= 0:
				continue
			all_keys_used = false
			break
	visible = not all_keys_used
	if all_keys_used:
		_stow_immediately()
	var ids: Array[String] = CollectionManager.get_unused_access_key_ids()
	var spacing := minf(1.8, (PANEL_WIDTH - 0.65) / maxf(float(ids.size()), 1.0))
	for index in range(ids.size()):
		var card_id := ids[index]
		var data := CardDatabase.get_card(card_id)
		var tile := MeshInstance3D.new()
		tile.name = "Key_" + card_id
		var mesh := BoxMesh.new()
		mesh.size = Vector3(minf(TILE_WIDTH, spacing - 0.08), TILE_HEIGHT, 0.035)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.disable_fog = true
		material.render_priority = 86
		material.albedo_color = TILE_COLOR
		mesh.material = material
		tile.mesh = mesh
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.position = Vector3((index - (ids.size() - 1) * 0.5) * spacing, 0.79, 0.105)
		keys_root.add_child(tile)
		_key_tiles[card_id] = tile
		var image_path := str(data.get("image", ""))
		if card_id in ["jester_eye", "toilet_paper"]:
			var eye_art := EYE_PREVIEW.new()
			if card_id == "toilet_paper":
				eye_art.model_scene = preload("res://assets/environments/props/toiletpaper/toiletpaper.glb")
				eye_art.normalize_model = true
			eye_art.name = "Art"
			eye_art.position = Vector3(0, 0.10, 0.034)
			eye_art.pixel_size = minf(0.86, mesh.size.x - 0.12) / 256.0
			tile.add_child(eye_art)
			_key_art[card_id] = eye_art
		elif not image_path.is_empty() and ResourceLoader.exists(image_path):
			var art := Sprite3D.new()
			art.name = "Art"
			art.texture = load(image_path) as Texture2D
			art.hframes = maxi(int(data.get("frame_columns", 1)), 1)
			art.vframes = maxi(int(data.get("frame_rows", 1)), 1)
			var frame_size := art.texture.get_size() / Vector2(art.hframes, art.vframes)
			art.pixel_size = minf(0.63 / frame_size.y, (mesh.size.x - 0.18) / frame_size.x)
			art.position = Vector3(0, 0.10, 0.034)
			art.no_depth_test = true
			art.render_priority = 88
			art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			tile.add_child(art)
			_key_art[card_id] = art
		var label := Label3D.new()
		label.name = "NameLabel"
		label.font = FONT
		label.font_size = 32
		label.pixel_size = 0.0033
		label.outline_size = 3
		label.no_depth_test = true
		label.render_priority = 100
		label.modulate = Color(0.94, 0.82, 0.60)
		label.position = Vector3(0, -0.34, 0.04)
		tile.add_child(label)
	empty_label.visible = ids.is_empty()
	hint_label.visible = not ids.is_empty()
	_refresh_localized_text()


func _queue_refresh(_card_ids: Array = []) -> void:
	_refresh_pending = true


func _refresh_localized_text() -> void:
	title_label.text = Localization.text("SCHLÜSSEL")
	empty_label.text = Localization.text("Keine unbenutzten Schlüssel")
	hint_label.text = Localization.text("Schlüssel anklicken, um den Zugang zu öffnen")
	var has_usable_key := false
	for card_id: String in _key_tiles:
		has_usable_key = has_usable_key or not CollectionManager.get_access_key_area_id(card_id).is_empty()
	if not _key_tiles.is_empty() and not has_usable_key:
		_refresh_action_hint()
	Localization.fit_text_3d(title_label, PANEL_WIDTH - 0.7, 0.22)
	Localization.fit_text_3d(empty_label, PANEL_WIDTH - 0.9, 0.3)
	Localization.fit_text_3d(hint_label, PANEL_WIDTH - 0.9, 0.16)
	for card_id: String in _key_tiles:
		var tile: MeshInstance3D = _key_tiles[card_id]
		var label: Label3D = tile.get_node("NameLabel")
		label.text = Localization.text(str(CardDatabase.get_card(card_id).get("name", card_id)))
		Localization.fit_text_3d(label, tile.mesh.get_aabb().size.x - 0.15, 0.2)


func _refresh_action_hint() -> void:
	var source := "Schlüssel anklicken, um den Zugang zu öffnen"
	if _key_tiles.has(CollectionManager.BOILER_REWARD_CARD_ID) and (not _key_tiles.has(CollectionManager.PUMP_REWARD_CARD_ID) or _key_can_be_used(CollectionManager.BOILER_REWARD_CARD_ID)):
		source = "Jester-Auge beim Jester verwenden."
	elif _key_tiles.has(CollectionManager.PUMP_REWARD_CARD_ID):
		source = "Klopapier beim Gefangenen verwenden."
	elif not _key_tiles.is_empty():
		var has_door_key := false
		for card_id: String in _key_tiles:
			has_door_key = has_door_key or not CollectionManager.get_access_key_area_id(card_id).is_empty()
		if not has_door_key:
			source = "Dieser Schlüssel wird vorerst nur gesammelt."
	var text := Localization.text(source)
	if hint_label.text != text:
		hint_label.text = text
		Localization.fit_text_3d(hint_label, PANEL_WIDTH - 0.9, 0.16)


func _can_display() -> bool:
	return (
		_enabled
		and _window_focused
		and is_inside_tree()
		and is_visible_in_tree()
		and not get_tree().paused
		and is_instance_valid(_camera)
		and get_viewport().get_camera_3d() == _camera
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN
		and (not context_available.is_valid() or bool(context_available.call()))
	)


func _can_click() -> bool:
	return _can_display() and is_visible_in_tree() and _expanded and absf(hinge.rotation_degrees.x) < 5.0


func _key_at_pointer(pointer: Vector2) -> String:
	for card_id: String in _key_tiles:
		if _pointer_hits_mesh(pointer, _key_tiles[card_id]):
			return card_id
	return ""


func _pointer_hits_mesh(pointer: Vector2, mesh: MeshInstance3D) -> bool:
	if not mesh.is_visible_in_tree() or not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var inverse := mesh.global_transform.affine_inverse()
	var ray_origin := inverse * _camera.project_ray_origin(pointer)
	var ray_direction := inverse.basis * _camera.project_ray_normal(pointer)
	return mesh.get_aabb().intersects_ray(ray_origin, ray_direction) != null


func _pointer_over_panel(pointer: Vector2) -> bool:
	if _pointer_hits_mesh(pointer, frame):
		return true
	if not _expanded:
		return false
	var upper_left := _camera.unproject_position(to_global(Vector3(-PANEL_WIDTH * 0.5, PANEL_HEIGHT, 0)))
	var lower_right := _camera.unproject_position(to_global(Vector3(PANEL_WIDTH * 0.5, 0, 0)))
	return Rect2(upper_left, lower_right - upper_left).has_point(pointer)


func _set_hover(card_id: String) -> void:
	if _hovered_id == card_id:
		return
	_hovered_id = card_id
	for key_id: String in _key_tiles:
		var tile: MeshInstance3D = _key_tiles[key_id]
		var material := tile.get_active_material(0) as StandardMaterial3D
		material.albedo_color = TILE_HOVER_COLOR if key_id == card_id else TILE_COLOR
	if card_id.is_empty():
		_release_cursor()
	else:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		_owns_cursor = true


func _release_cursor() -> void:
	if _owns_cursor:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_owns_cursor = false


func _is_fullscreen_bottom_edge(pointer: Vector2, viewport_size: Vector2) -> bool:
	return (
		get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
		and pointer.x >= -FULLSCREEN_EDGE_TOLERANCE
		and pointer.x <= viewport_size.x + FULLSCREEN_EDGE_TOLERANCE
		and pointer.y >= viewport_size.y - activation_edge_pixels
		and pointer.y <= viewport_size.y + FULLSCREEN_EDGE_TOLERANCE
	)


func _stow_immediately() -> void:
	_expanded = false
	_set_hover("")
	if _hinge_tween != null and _hinge_tween.is_valid():
		_hinge_tween.kill()
	if is_instance_valid(hinge):
		hinge.rotation_degrees.x = STOWED_ANGLE


func _update_camera_layout() -> void:
	if not is_instance_valid(_camera):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var distance := maxf(1.0, _camera.near * 5.0)
	var top_left := _camera.to_local(_camera.project_position(Vector2.ZERO, distance))
	var bottom_right := _camera.to_local(_camera.project_position(viewport_size, distance))
	var visible_width := absf(bottom_right.x - top_left.x)
	var visible_height := absf(top_left.y - bottom_right.y)
	var unit_scale := minf(visible_height * screen_height_fraction / PANEL_HEIGHT, visible_width * 0.85 / PANEL_WIDTH)
	position = Vector3((top_left.x + bottom_right.x) * 0.5, bottom_right.y, -distance)
	scale = Vector3.ONE * unit_scale
