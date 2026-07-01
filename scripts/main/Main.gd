extends Node3D
class_name MainScene

const SIDE_COUNT := 4
const SIDE_NAMES := [
	"Game Table",
	"Pack Opening",
	"Collection",
	"Leere Seite",
]
const SIDE_HINTS := [
	"Tisch-Seite: Kartenkampf spielen",
	"Pack-Seite: PackTop ziehen und Karten öffnen",
	"Collection-Seite: Sammlung ansehen",
	"Diese Seite bleibt frei",
]

@export_group("Rotation")
@export var rotation_step_degrees := 90.0
@export var rotation_duration := 0.32      ## Phase 1: Schwung raus zum überschossenen Zwischenziel
@export var settle_duration := 0.22        ## Phase 2: Einrasten auf den exakten Zielwert

@export_group("Tilt & Sway (statisch, an Drehrichtung gekoppelt)")
@export var sway_angle_degrees := 5.0      ## Y-Overshoot in Drehrichtung
@export var roll_angle_degrees := 6.0      ## Z-Roll (seitliches Kippen)
@export var pitch_dip_degrees := 1.6       ## X-Nicken nach unten während der Drehung

@export_group("Mouse Tilt")
@export var mouse_tilt_strength := 2.5 # Grad
@export var mouse_tilt_speed := 8.0

@export_group("Input")
@export var input_action_left := "left"
@export var input_action_right := "right"

@onready var scene_pivot: Node3D = $ScenePivot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var side_label: Label = %SideLabel
@onready var hint_label: Label = %HintLabel
@onready var camera_tilt: Node3D = $CameraPivot/CameraTilt

var _active_side := 0
var _base_x_rotation := 0.0


# ============================================================
# LOGISCHE SEITE vs. VISUELLE ANIMATION - STRIKT GETRENNT
# ============================================================
# Der eigentliche Bug war: der Zielwinkel einer neuen Drehung wurde aus der
# AKTUELLEN (visuellen, mitten in der Animation befindlichen) Kamerarotation
# berechnet. Wenn man während des Overshoots erneut drückte, addierte sich
# der neue 90°-Schritt auf eine Zwischenposition statt auf die "echte" Seite
# - das Ergebnis driftete mit jedem Tastendruck weiter weg von den 4 gültigen
# 0°/90°/180°/270°-Ausrichtungen. Genau das fühlte sich an wie "hängt
# zwischen zwei Seiten".
#
# Fix: _settle_target_y ist ab jetzt die EINZIGE Quelle der Wahrheit dafür,
# "welche Seite ist (Ziel-)aktiv". Jede neue Drehung rechnet IMMER von
# _settle_target_y aus weiter (nie von camera_pivot.rotation.y!). Die
# tatsächliche Kamera-Rotation (camera_pivot.rotation) ist rein visuell -
# sie darf während der Animation zwischen den Werten hin- und herspringen,
# ohne dass das jemals den nächsten Zielwert verfälscht.

enum Phase { IDLE, OVERSHOOT, SETTLE }
enum EaseKind { CUBIC_OUT, BACK_OUT }

var _phase: Phase = Phase.IDLE
var _elapsed := 0.0

var _phase_start: Vector3 = Vector3.ZERO
var _phase_end: Vector3 = Vector3.ZERO
var _phase_duration := 0.0
var _phase_ease_kind: EaseKind = EaseKind.CUBIC_OUT

# Die "Wahrheit": auf welchen Y-Winkel ist die aktuell gewählte Seite fest verankert.
# Wird NUR in _begin_turn verändert, niemals aus camera_pivot zurückgelesen.
var _settle_target_y := 0.0

var _pending_direction := 0


func _ready() -> void:
	_base_x_rotation = camera_pivot.rotation.x
	_settle_target_y = camera_pivot.rotation.y
	_disable_embedded_scene_controls()
	_connect_pack_collection_refresh()
	_update_labels()


func _process(delta: float) -> void:
	_read_input()

	if _pending_direction != 0:
		var dir := _pending_direction
		_pending_direction = 0
		_begin_turn(dir)

	_advance_phase(delta)
	_update_mouse_tilt(delta)


func _read_input() -> void:
	if _is_table_match_active():
		return

	if Input.is_action_just_pressed(input_action_left):
		_pending_direction = -1
	elif Input.is_action_just_pressed(input_action_right):
		_pending_direction = 1


func _advance_phase(delta: float) -> void:
	if _phase == Phase.IDLE:
		return

	_elapsed += delta
	var t := 1.0
	if _phase_duration > 0.0:
		t = clampf(_elapsed / _phase_duration, 0.0, 1.0)

	var eased_t := _ease(t, _phase_ease_kind)
	camera_pivot.rotation = _phase_start.lerp(_phase_end, eased_t)

	if t >= 1.0:
		camera_pivot.rotation = _phase_end
		_advance_to_next_phase()


func _advance_to_next_phase() -> void:
	match _phase:
		Phase.OVERSHOOT:
			# Phase 1 fertig -> Phase 2 (Einrasten) startet GENAU dort,
			# wo Phase 1 visuell aufgehört hat. Das Ziel ist immer
			# _settle_target_y - die geschützte, logische Wahrheit.
			_phase = Phase.SETTLE
			_elapsed = 0.0
			_phase_start = camera_pivot.rotation
			_phase_end = Vector3(_base_x_rotation, _settle_target_y, 0.0)
			_phase_duration = settle_duration
			_phase_ease_kind = EaseKind.BACK_OUT
		Phase.SETTLE:
			_phase = Phase.IDLE
			_elapsed = 0.0
			# Sicherheitsnetz: am Ende von SETTLE garantiert exakt auf der
			# Zielseite stehen, keine Restabweichung durch Float-Rundung.
			camera_pivot.rotation = Vector3(_base_x_rotation, _settle_target_y, 0.0)
		Phase.IDLE:
			pass


func _begin_turn(direction: int) -> void:
	# KERNFIX: der neue Zielwinkel wird von _settle_target_y aus berechnet -
	# der letzten GÜLTIGEN Seite - niemals von camera_pivot.rotation.y (das
	# wäre die fehlerhafte, visuelle Zwischenposition gewesen).
	var step := deg_to_rad(rotation_step_degrees) * float(direction)
	var new_target_y := _settle_target_y - step
	_settle_target_y = new_target_y

	_active_side = posmod(_active_side + direction, SIDE_COUNT)
	_update_labels()

	var sway_y := new_target_y + deg_to_rad(sway_angle_degrees) * float(direction) * -1.0
	var roll := deg_to_rad(roll_angle_degrees) * float(direction) * -1.0
	var dip := _base_x_rotation + deg_to_rad(pitch_dip_degrees)

	# Der visuelle Startpunkt der Animation ist die aktuelle Kamera-Rotation -
	# das ist rein kosmetisch (sorgt für nahtloses Umlenken beim Spammen)
	# und beeinflusst NICHT, welche Seite am Ende erreicht wird.
	_phase = Phase.OVERSHOOT
	_elapsed = 0.0
	_phase_start = camera_pivot.rotation
	_phase_end = Vector3(dip, sway_y, roll)
	_phase_duration = rotation_duration
	_phase_ease_kind = EaseKind.CUBIC_OUT


func _ease(t: float, kind: EaseKind) -> float:
	# Eigene, transparente Easing-Kurven (Standard Robert-Penner-Formeln).
	# Mathematisch verifiziert: t=0 -> 0.0, t=1 -> 1.0 exakt für beide Kurven.
	match kind:
		EaseKind.CUBIC_OUT:
			var inv := 1.0 - t
			return 1.0 - inv * inv * inv
		EaseKind.BACK_OUT:
			var c1 := 1.70158
			var c3 := c1 + 1.0
			var shifted := t - 1.0
			return 1.0 + c3 * shifted * shifted * shifted + c1 * shifted * shifted
		_:
			return t


func _update_labels() -> void:
	side_label.text = SIDE_NAMES[_active_side]
	hint_label.text = SIDE_HINTS[_active_side] + "  |  A/D drehen"


func _disable_embedded_scene_controls() -> void:
	for child in scene_pivot.get_children():
		_disable_embedded_scene_controls_recursive(child)


func _disable_embedded_scene_controls_recursive(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is AudioListener3D:
		(node as AudioListener3D).current = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	if node is MenuNavigation:
		(node as MenuNavigation).visible = false
		(node as MenuNavigation).process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_embedded_scene_controls_recursive(child)

func _is_table_match_active() -> bool:
	if _active_side != 0:
		return false

	var game_table := scene_pivot.get_node_or_null("GameTable")
	if game_table == null:
		return false

	if not game_table.has_method("is_match_active"):
		return false

	return game_table.is_match_active()
	

func _connect_pack_collection_refresh() -> void:
	var pack_opening_screen := scene_pivot.get_node_or_null("PackOpening")
	var collection_screen := scene_pivot.get_node_or_null("Collection")

	if pack_opening_screen == null:
		push_warning("PackOpening nicht gefunden")
		return

	if collection_screen == null:
		push_warning("Collection nicht gefunden")
		return

	if pack_opening_screen.has_signal("pack_cards_collected"):
		pack_opening_screen.pack_cards_collected.connect(
			func(_card_ids):
				if collection_screen.has_method("refresh_collection"):
					collection_screen.refresh_collection()
		)
		
func _update_mouse_tilt(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()

	var offset := (mouse - viewport_size * 0.5) / (viewport_size * 0.5)

	offset.x = clamp(offset.x, -1.0, 1.0)
	offset.y = clamp(offset.y, -1.0, 1.0)

	var target_x := deg_to_rad(-offset.y * mouse_tilt_strength)
	var target_z := deg_to_rad(-offset.x * mouse_tilt_strength)

	camera_tilt.rotation.x = lerp_angle(
		camera_tilt.rotation.x,
		target_x,
		delta * mouse_tilt_speed
	)

	camera_tilt.rotation.z = lerp_angle(
		camera_tilt.rotation.z,
		target_z,
		delta * mouse_tilt_speed
	)
