extends Node3D
class_name LevelProgress

## A camera-mounted, physical progress visor. Instantiate LevelProgress.tscn
## directly beneath a Camera3D; the hinge and lettering are editable 3D nodes.
const PANEL_WIDTH := 3.8
const PANEL_HEIGHT := 1.08
const BAR_WIDTH := 3.12
const STOWED_ANGLE := 200.0
const FULLSCREEN_EDGE_TOLERANCE := 2.0
const COIN_BUTTON_COLOR := Color(0.48, 0.32, 0.12)
const COIN_BUTTON_HOVER_COLOR := Color(0.75, 0.52, 0.21)
const COIN_BUTTON_LOCKED_COLOR := Color(0.19, 0.19, 0.19)

@export_range(4.0, 32.0, 1.0) var activation_edge_pixels := 12.0
@export_range(0.15, 0.27, 0.01) var screen_height_fraction := 0.23
@export_range(0.25, 0.4, 0.01) var release_height_fraction := 0.29

@onready var hinge: Node3D = $Hinge
@onready var level_label: Label3D = $Hinge/LevelLabel
@onready var xp_label: Label3D = $Hinge/XPLabel
@onready var xp_fill: MeshInstance3D = $Hinge/XPFill
@onready var bonus_label: Label3D = $Hinge/BonusLabel
@onready var coin_label: Label3D = $Hinge/CoinLabel
@onready var coin_button: MeshInstance3D = $Hinge/CoinButton
@onready var coin_button_label: Label3D = $Hinge/CoinButton/Label3D
@onready var cat_clicker_sprite: Sprite3D = $Hinge/CoinButton/CatClick
@onready var coin_click_sound: AudioStreamPlayer = $CoinClickSound
@onready var frame: MeshInstance3D = $Hinge/Frame

var _camera: Camera3D
var _enabled := true
var _expanded := false
var _pointer_in_window := true
var _window_focused := true
var _xp_ratio := 0.0
var _hinge_tween: Tween
var _coin_press_tween: Tween
var _coin_button_material: StandardMaterial3D
var _coin_button_rest_z := 0.0
var coins_per_click := 0.0


func _ready() -> void:
	Localization.locale_changed.connect(_refresh_localized_text)
	# Keep the hinge mounted and laid out even when the panel cannot open.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = get_parent() as Camera3D
	visible = true
	hinge.rotation_degrees.x = STOWED_ANGLE
	_coin_button_material = coin_button.get_active_material(0).duplicate() as StandardMaterial3D
	coin_button.material_override = _coin_button_material
	_coin_button_rest_z = coin_button.position.z
	CollectionManager.collection_changed.connect(_on_collection_changed)
	_on_collection_changed([])
	GameCurrency.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameCurrency.get_coins())
	GameCurrency.progression_changed.connect(_on_progression_changed)
	_on_progression_changed(GameCurrency.get_level(), GameCurrency.get_xp(), GameCurrency.get_xp_required())
	GameCurrency.cat_clicker_changed.connect(_on_cat_clicker_changed)
	GameCurrency.cat_clicker_frame_changed.connect(_on_cat_clicker_frame_changed)
	GameCurrency.cat_clicker_clicked.connect(_on_cat_clicker_clicked)
	_sync_cat_clicker()
	_update_camera_layout()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_EXIT:
			_pointer_in_window = false
			# Resolve this against the pointer next frame. Fullscreen can report
			# an exit at the very top pixel even though the pointer is still there.
		NOTIFICATION_WM_MOUSE_ENTER:
			_pointer_in_window = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false
			_stow_immediately()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true


func _process(_delta: float) -> void:
	_update_camera_layout()
	if not _can_display():
		_stow_immediately()
		return
	set_pointer_position(get_viewport().get_mouse_position())
	_set_coin_hover(_can_click() and _pointer_hits_mesh(get_viewport().get_mouse_position(), coin_button))


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not _can_click():
		return
	var on_button := _pointer_hits_mesh(event.position, coin_button)
	if not on_button and not _pointer_hits_mesh(event.position, frame):
		return
	# The camera-mounted visor takes priority over the world beneath it,
	# including collection background clicks. Modal screens disable the visor.
	get_viewport().set_input_as_handled()
	if on_button and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Read ownership again at the click, including inventory resets and new
		# copies acquired since the panel opened. An upgrade alone cannot unlock it.
		_on_collection_changed([])
		if coins_per_click <= 0:
			return
		GameCurrency.award_manual_click()
		_set_coin_hover(true)
		_play_coin_press()


func _play_coin_press() -> void:
	if _coin_press_tween != null and _coin_press_tween.is_valid():
		_coin_press_tween.kill()
	coin_button.position.z = _coin_button_rest_z - 0.025
	_coin_press_tween = create_tween()
	_coin_press_tween.tween_property(coin_button, "position:z", _coin_button_rest_z, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin_click_sound.stop()
	coin_click_sound.play()


func _sync_cat_clicker() -> void:
	cat_clicker_sprite.visible = GameCurrency.is_cat_clicker_active()
	cat_clicker_sprite.frame = GameCurrency.get_cat_clicker_frame()


func _on_cat_clicker_changed(_active: bool) -> void:
	_sync_cat_clicker()


func _on_cat_clicker_frame_changed(frame_index: int) -> void:
	cat_clicker_sprite.frame = frame_index


func _on_cat_clicker_clicked() -> void:
	# Income and the animation clock belong to the wallet, so folded panels
	# and additional HUD instances cannot stop or duplicate the cat's clicks.
	if GameCurrency.is_cat_clicker_active() and _can_click():
		_play_coin_press()


func _can_click() -> bool:
	return _can_display() and is_visible_in_tree() and _expanded and absf(hinge.rotation_degrees.x) < 5.0


func _pointer_hits_mesh(pointer: Vector2, mesh: MeshInstance3D) -> bool:
	if not mesh.is_visible_in_tree() or not get_viewport().get_visible_rect().has_point(pointer):
		return false
	# Picking in mesh space follows camera movement, viewport sizing and the
	# hinge transform without a separate screen rectangle or physics collider.
	var inverse := mesh.global_transform.affine_inverse()
	var ray_origin := inverse * _camera.project_ray_origin(pointer)
	var ray_direction := inverse.basis * _camera.project_ray_normal(pointer)
	return mesh.get_aabb().intersects_ray(ray_origin, ray_direction) != null


func _set_coin_hover(active: bool) -> void:
	if _coin_button_material != null:
		_coin_button_material.albedo_color = (
			COIN_BUTTON_LOCKED_COLOR if coins_per_click <= 0
			else COIN_BUTTON_HOVER_COLOR if active else COIN_BUTTON_COLOR
		)


func _on_collection_changed(_card_ids: Array[String]) -> void:
	coins_per_click = GameCurrency.get_manual_click_reward()
	_sync_cat_clicker()
	coin_button_label.text = Localization.format_text("+%s Münzen", [GameCurrency.format_coins(coins_per_click)]) if coins_per_click > 0 else "Gesperrt\nClicker-Karte nötig"
	Localization.fit_text_3d(coin_button_label, 1.0, 0.22)
	coin_button_label.font_size = 34 if coins_per_click > 0 else 26
	coin_button_label.modulate = Color(1, 0.92, 0.73) if coins_per_click > 0 else Color(0.58, 0.58, 0.58)
	_set_coin_hover(false)
	_on_progression_changed(GameCurrency.get_level(), GameCurrency.get_xp(), GameCurrency.get_xp_required())


func _on_coins_changed(coins: float) -> void:
	coin_label.text = Localization.format_text("%s Soul Coins", [GameCurrency.format_coins(coins)])
	Localization.fit_text_3d(coin_label, 1.91, 0.23)


func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		_stow_immediately()


func is_expanded() -> bool:
	return _expanded


func set_pointer_position(pointer: Vector2) -> void:
	if not is_node_ready() or not _can_display():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var inside := Rect2(Vector2.ZERO, viewport_size).has_point(pointer)
	# Allow the physical top edge and a small rounding margin in fullscreen.
	# This also overrides an erroneous window-exit notification at that edge.
	var fullscreen_edge := _is_fullscreen_top_edge(pointer, viewport_size)
	if not (inside and _pointer_in_window) and not fullscreen_edge:
		set_expanded(false)
	elif _expanded:
		# A wider exit zone lets the pointer move down over the revealed visor.
		if pointer.y > maxf(72.0, viewport_size.y * release_height_fraction):
			set_expanded(false)
	elif pointer.y <= activation_edge_pixels:
		set_expanded(true)


func _is_fullscreen_top_edge(pointer: Vector2, viewport_size: Vector2) -> bool:
	return (
		_is_fullscreen()
		and pointer.x >= -FULLSCREEN_EDGE_TOLERANCE
		and pointer.x <= viewport_size.x + FULLSCREEN_EDGE_TOLERANCE
		and pointer.y >= -FULLSCREEN_EDGE_TOLERANCE
		and pointer.y <= activation_edge_pixels
	)


func _is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func set_expanded(value: bool) -> void:
	if not is_node_ready() or (value and not _enabled) or _expanded == value:
		return
	_expanded = value
	if _hinge_tween != null and _hinge_tween.is_valid():
		_hinge_tween.kill()
	_hinge_tween = create_tween()
	_hinge_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _expanded:
		_hinge_tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_hinge_tween.tween_property(hinge, "rotation_degrees:x", STOWED_ANGLE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _can_display() -> bool:
	return (
		_enabled
		and _window_focused
		and not get_tree().paused
		and is_instance_valid(_camera)
		and get_viewport().get_camera_3d() == _camera
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN
	)


func _stow_immediately() -> void:
	_expanded = false
	_set_coin_hover(false)
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
	# Projecting viewport corners also handles FOV changes, orthographic
	# cameras and either keep_aspect setting without hard-coded aspect ratios.
	var top_left := _camera.to_local(_camera.project_position(Vector2.ZERO, distance))
	var bottom_right := _camera.to_local(_camera.project_position(viewport_size, distance))
	var visible_width := absf(bottom_right.x - top_left.x)
	var visible_height := absf(top_left.y - bottom_right.y)
	var unit_scale := minf(visible_height * screen_height_fraction / PANEL_HEIGHT, visible_width * 0.88 / PANEL_WIDTH)
	# Mount the axle on the upper edge: its lower half stays visible, while
	# the fully folded panel projects above the screen, including its thickness.
	position = Vector3((top_left.x + bottom_right.x) * 0.5, top_left.y, -distance)
	scale = Vector3.ONE * unit_scale


func _on_progression_changed(level: int, xp: int, xp_required: int) -> void:
	level_label.text = Localization.format_text("LEVEL %d", [level])
	xp_label.text = Localization.format_text("%d / %d XP", [xp, xp_required])
	bonus_label.text = Localization.format_text("Nächstes Level: +%s Soul Coins", [GameCurrency.format_coins(GameCurrency.get_level_bonus_reward(), true)])
	Localization.fit_text_3d(level_label, 1.48, 0.28)
	Localization.fit_text_3d(xp_label, 1.48, 0.28)
	Localization.fit_text_3d(bonus_label, BAR_WIDTH, 0.20)
	_xp_ratio = clampf(float(xp) / float(maxi(1, xp_required)), 0.0, 1.0)
	xp_fill.visible = _xp_ratio > 0.0
	xp_fill.scale.x = maxf(_xp_ratio, 0.0001)
	# Keep the growing fill anchored at the left end of the physical trough.
	xp_fill.position.x = -BAR_WIDTH * 0.5 + BAR_WIDTH * _xp_ratio * 0.5

func _refresh_localized_text() -> void:
	_on_collection_changed([])
	_on_coins_changed(GameCurrency.get_coins())
	_on_progression_changed(GameCurrency.get_level(), GameCurrency.get_xp(), GameCurrency.get_xp_required())
