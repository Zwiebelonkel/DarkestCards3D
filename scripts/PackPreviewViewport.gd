extends PanelContainer
class_name PackPreviewViewport

signal pressed(pack_id: String)

const SURFACE_COLOR := Color(0.0784314, 0.0666667, 0.0941176, 1.0)
const SURFACE_ACTIVE_COLOR := Color(0.113725, 0.0901961, 0.121569, 1.0)
const SURFACE_LOCKED_COLOR := Color(0.0588235, 0.054902, 0.0705882, 1.0)
const BORDER_COLOR := Color(0.25098, 0.188235, 0.207843, 1.0)
const TEXT_COLOR := Color(0.952941, 0.905882, 0.894118, 1.0)
const MUTED_COLOR := Color(0.658824, 0.556863, 0.568627, 1.0)
const UNAFFORDABLE_COLOR := Color(0.835294, 0.388235, 0.423529, 1.0)

@export var pack_id := ""
@export var pack_name := ""
@export var pack_cost := 0
@export var pack_card_count := 0
@export var pack_scene: PackedScene
@export var accent_color := Color(0.501961, 0.4, 0.909804, 1.0)
@export var rotation_speed := 0.55
@export var viewport_fps := 12.0

@onready var accent_line: ColorRect = $Margin/Content/AccentLine
@onready var name_label: Label = $Margin/Content/NameLabel
@onready var cards_label: Label = $Margin/Content/MetaRow/CardsLabel
@onready var price_label: Label = $Margin/Content/MetaRow/PriceLabel
@onready var state_label: Label = $Margin/Content/StateLabel
@onready var viewport: SubViewport = $Margin/Content/PreviewPanel/PreviewMargin/ViewportContainer/SubViewport
@onready var camera: Camera3D = $Margin/Content/PreviewPanel/PreviewMargin/ViewportContainer/SubViewport/World/Camera3D
@onready var model_root: Node3D = $Margin/Content/PreviewPanel/PreviewMargin/ViewportContainer/SubViewport/World/ModelRoot
@onready var light: DirectionalLight3D = $Margin/Content/PreviewPanel/PreviewMargin/ViewportContainer/SubViewport/World/DirectionalLight3D

var pack_model: Node3D = null
var _viewport_timer := 0.0
var _selected := false
var _locked := false
var _affordable := true
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_setup_viewport()
	_setup_camera()
	_setup_light()
	_spawn_pack_model()
	_refresh_labels()
	_refresh_visual_state()

	await get_tree().process_frame
	await _force_viewport_refresh()


func _setup_viewport() -> void:
	viewport.disable_3d = false
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = false


func _setup_camera() -> void:
	camera.current = true
	camera.fov = 34.0
	camera.position = Vector3(0.0, 0.62, 3.2)
	camera.look_at(Vector3(0.0, 0.24, 0.0), Vector3.UP)


func _setup_light() -> void:
	light.rotation_degrees = Vector3(-28.0, -24.0, 0.0)
	light.light_energy = 1.4


func _spawn_pack_model() -> void:
	for child in model_root.get_children():
		child.queue_free()

	if pack_scene == null:
		return

	pack_model = pack_scene.instantiate() as Node3D
	model_root.add_child(pack_model)
	pack_model.position = Vector3.ZERO
	pack_model.rotation_degrees = Vector3.ZERO
	pack_model.scale = Vector3.ONE * 0.78


func _refresh_labels() -> void:
	name_label.text = pack_name
	cards_label.text = "%d KARTEN" % pack_card_count
	price_label.text = "%d COINS" % pack_cost


func _force_viewport_refresh() -> void:
	# Keep the isolated world intact and wait for the GPU draw before throttling
	# updates again. Recreating World3D here can briefly detach the camera and
	# produces black frames (or a null rendering scenario) on some renderers.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_viewport_timer += delta
	if viewport_fps <= 0.0 or _viewport_timer < 1.0 / viewport_fps:
		return

	var elapsed := _viewport_timer
	_viewport_timer = 0.0

	if pack_model:
		var speed_multiplier := 1.35 if _hovered or _selected else 1.0
		pack_model.rotate_y(rotation_speed * speed_multiplier * elapsed)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _gui_input(event: InputEvent) -> void:
	if _locked:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			pressed.emit(pack_id)
			accept_event()


func set_selected(value: bool) -> void:
	_selected = value
	if is_node_ready():
		_refresh_visual_state()


func set_locked(value: bool) -> void:
	_locked = value
	if is_node_ready():
		_refresh_visual_state()


func set_affordable(value: bool) -> void:
	_affordable = value
	if is_node_ready():
		_refresh_visual_state()


func _on_mouse_entered() -> void:
	_hovered = true
	if not _locked:
		_refresh_visual_state()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_visual_state()


func _refresh_visual_state() -> void:
	var background := SURFACE_COLOR
	var border := BORDER_COLOR
	var border_width := 1

	if _locked:
		background = SURFACE_LOCKED_COLOR
	elif _selected:
		background = SURFACE_ACTIVE_COLOR
		border = accent_color
		border_width = 3
	elif _hovered:
		background = SURFACE_ACTIVE_COLOR
		border = accent_color.darkened(0.18)
		border_width = 2

	add_theme_stylebox_override("panel", _make_card_style(background, border, border_width))
	accent_line.color = accent_color if not _locked else accent_color.darkened(0.55)
	name_label.add_theme_color_override("font_color", accent_color if _selected and not _locked else TEXT_COLOR)
	price_label.add_theme_color_override("font_color", accent_color if _affordable and not _locked else UNAFFORDABLE_COLOR)

	if _locked:
		state_label.text = "ÖFFNUNG LÄUFT"
		state_label.add_theme_color_override("font_color", MUTED_COLOR)
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif not _affordable:
		state_label.text = "ZU WENIG COINS"
		state_label.add_theme_color_override("font_color", UNAFFORDABLE_COLOR)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif _selected:
		state_label.text = "AUSGEWÄHLT"
		state_label.add_theme_color_override("font_color", accent_color)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif _hovered:
		state_label.text = "AUSWÄHLEN"
		state_label.add_theme_color_override("font_color", TEXT_COLOR)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		state_label.text = "PACK ANSEHEN"
		state_label.add_theme_color_override("font_color", MUTED_COLOR)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _make_card_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 4 if border_width > 1 else 2
	return style
