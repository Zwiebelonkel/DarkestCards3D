extends Node3D
class_name MainScene

signal room_changed(room_index: int)
signal _npc_rescue_step_finished

const SIDE_COUNT := 4
const TURN_SOUND := preload("res://assets/sounds/SFX/turn.mp3")
const STEP_SOUND := preload("res://assets/sounds/SFX/step.mp3")
const WAKEUP_BLUR_START := 5.0
const WAKEUP_BLUR_END := 0.265
const DIAGNOSTICS := preload("res://scripts/autoload/SessionDiagnostics.gd")
const UPGRADE_COLLECTION_SCENE := preload("res://scenes/props/UpgradeWallCollection.tscn")
const FUSION_WORKBENCH_SCENE := preload("res://scenes/props/FusionWorkbench.tscn")
const JOURNAL_SCENE := preload("res://scenes/props/Journal3D.tscn")
const TURN_ARROWS_SCRIPT := preload("res://scripts/ui/TurnArrows.gd")
const GREETING_SCRIPT := preload("res://scripts/main/SatanGreeting.gd")
const JUMPSCARE_SCRIPT := preload("res://scripts/main/SatanJumpscare.gd")
const CRYPT_GATE_SCRIPT := preload("res://scripts/rooms/CryptGate.gd")
const PRISONER_DIALOGUE_SCRIPT := preload("res://scripts/rooms/PrisonerDialogue.gd")
const BED_SEATING_SCRIPT := preload("res://scripts/props/BedSeating.gd")
const AMBIENT_SCREAMS_SCRIPT := preload("res://scripts/main/AmbientScreams.gd")
const IMPRISONED_NPC_SCRIPT := preload("res://scripts/main/ImprisonedNPCPresentation.gd")
const NPC_RESCUE_FACE_UVS := {
	"angel": Vector2(0.5, 26.0 / 64.0),
	"Dealer": Vector2(31.0 / 64.0, 27.0 / 64.0),
	"jester": Vector2(27.0 / 64.0, 26.0 / 64.0),
	"Prisoner": Vector2(32.6 / 64.0, 18.2 / 64.0),
}
const ROOM_AMBIENCE := {
	2: preload("res://assets/sounds/atmoGraveyard.mp3"),
	3: preload("res://assets/sounds/atmoBasement.mp3"),
}
const SIDE_NAMES := [
	"Game Table",
	"Pack Shop",
	"Collection",
	"Upgrade Shop",
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

@export_group("Room Travel")
@export_range(0.1, 10.0, 0.1) var room_travel_duration := 3.2
@export_range(0.1, 5.0, 0.1) var door_key_look_duration := 1.4

@export_group("Walking Camera")
@export_range(0.0, 0.1, 0.001) var walking_bob_height := 0.025
@export_range(0.0, 3.0, 0.05) var walking_pitch_degrees := 0.6
@export_range(0.2, 1.0, 0.01) var walking_step_interval := 0.38
@export_range(0.01, 1.0, 0.01) var walking_fade_duration := 0.2

@export_group("Room Music")
# All rooms outside the hub share the slot room's music treatment.
@export_range(-30.0, 0.0, 0.5) var slot_room_music_attenuation_db := -12.0
@export_range(200.0, 8000.0, 50.0) var slot_room_music_cutoff_hz := 1100.0

@export_group("Aufwachen")
@export_range(0.1, 15.0, 0.1) var wakeup_blur_duration := 5.0
@export var greeting_enabled := true

@export_group("NPC Rescue Introductions")
@export_range(0.1, 5.0, 0.1) var npc_intro_approach_duration := 1.5
@export_range(0.1, 5.0, 0.1) var npc_intro_return_duration := 1.3

@export_group("Imprisoned NPC Animation")
@export_range(0.1, 5.0, 0.1) var imprisoned_reveal_duration := 1.6
@export_range(0.1, 5.0, 0.1) var imprisoned_departure_duration := 1.15

@export_group("Debug")
@export var debug_interaction_clicks := true
@export var debug_interaction_ray_length := 100.0

@onready var scene_pivot: Node3D = $ScenePivot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var side_label: Label = %SideLabel
@onready var hint_label: Label = %HintLabel
@onready var camera_tilt: Node3D = $CameraPivot/CameraTilt
@onready var main_camera: Camera3D = $CameraPivot/CameraTilt/Camera3D
@onready var level_progress: Node3D = $CameraPivot/CameraTilt/Camera3D/LevelProgress
@onready var access_key_tray: AccessKeyTray = $CameraPivot/CameraTilt/Camera3D/AccessKeyTray
@onready var table_lobby: Control = $ScenePivot/GameTable/OnlineCanvas/MatchmakingScreen
@onready var screen_camera_focus: ScreenCameraFocus = $ScreenCameraFocus
@onready var music: AudioStreamPlayer = $Music
@onready var atmo: AudioStreamPlayer = $Atmo
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var hub_door: HospitalDoor = $HubDoor
@onready var empty_room: Node3D = $EmptyRoom
@onready var return_door: HospitalDoor = $EmptyRoom/ReturnDoor
@onready var room_camera_anchor: Marker3D = $EmptyRoom/CameraAnchor
@onready var slot_machine: SoulSlotMachine = $EmptyRoom/SlotMachine
@onready var secret_wall_input: Node3D = $EmptyRoom/SecretWallInput
@onready var graveyard_jester: GraveyardJester = $GraveyardRoom
@onready var black_market_board: BlackMarketBoard = $BlackMarketRoom/OfferBoard
@onready var dealer_dialogue: DealerDialogue = $BlackMarketRoom/DealerDialogue
@onready var basement_cat: BasementCatEncounter = $BasementRoom/BasementCatEncounter
@onready var basement_pump_control: BasementPumpControl = $BasementRoom/PumpStation
@onready var dirty_lens: ColorRect = $CameraPivot/CameraTilt/Camera3D/CanvasLayer/DirtyLensRect
@onready var blood_overlay = $CameraPivot/CameraTilt/Camera3D/BloodOverlay
@onready var weed_pickup = $ScenePivot/GameTable/WeedPickup

var _wakeup_blur_material: ShaderMaterial
var _wakeup_blur_tween: Tween
var upgrade_collection: UpgradeWallCollection
var fusion_workbench: FusionWorkbench
var journal: Journal3D
var turn_arrows: TurnArrows
var progression_areas: Array[ProgressionArea] = []
var connected_rooms: Dictionary = {}
var basement_boilers: Array[BasementBoiler] = []
var _last_checked_boiler_settings := ""
var crypt_gate: CRYPT_GATE_SCRIPT
var prisoner_dialogue: PRISONER_DIALOGUE_SCRIPT
var bed_seating: BED_SEATING_SCRIPT

var _active_room := 0
var _room_transition_active := false
var _crypt_gate_close := false
var _crypt_return_pivot := Transform3D.IDENTITY
var _crypt_camera_base_transform := Transform3D.IDENTITY
var _room_travel_tween: Tween = null
var _room_music_tween: Tween = null
var _room_music_bus: StringName = &""
var _room_music_source_bus: StringName = &"Music"
var _room_music_filter: AudioEffectLowPassFilter = null
var _room_music_mix := 0.0
var _room_ambience_players: Dictionary = {}
var _room_ambience_tween: Tween
var _room_ambience_volume_db := 0.0
var _door_key_tween: Tween = null
var _door_key_view_active := false
var _key_reveal_door: HospitalDoor
var _hub_camera_base_transform := Transform3D.IDENTITY
var _hub_camera_base_fov := 58.0
var _hub_return_pivot_transform := Transform3D.IDENTITY
var _hub_return_step_index := 0
var _hub_return_active_side := 0
var _hub_settle_origin_y := 0.0

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
var _settle_origin_y := 0.0
var _settle_step_index := 0

# Node3D normalisiert Euler-Winkel beim Zurücklesen. Besonders beim schnellen
# Unterbrechen rund um +/-180 Grad kann derselbe Basiswinkel dadurch in einer
# anderen Euler-Darstellung erscheinen. Die Animation behält deshalb ihren
# eigenen, kontinuierlichen visuellen Winkel und liest Zwischenstände nie aus
# CameraPivot zurück.
var _visual_pivot_rotation := Vector3.ZERO

# GameTable und Main teilen sich dieselbe Camera3D. Der Child-Node ist vor Main
# ready und startet beim Aufbau des Hub-Menüs einen (inhaltlich leeren)
# Global-Transform-Tween. Wird in diesen ersten Frames gedreht, schreibt dieser
# Tween gegen den Pivot und hinterlässt eine lokale Gegenrotation in der Kamera.
var _hub_camera_base_basis := Basis.IDENTITY

var _pending_direction := 0
var _turn_sound: AudioStreamPlayer
var _step_sound: AudioStreamPlayer
var _step_random := RandomNumberGenerator.new()
var _walking_steps_active := false
var _walking_duration := 0.0
var _walking_camera_base_transform := Transform3D.IDENTITY
var _step_countdown := 0.0
var _step_previous_position := Vector3.ZERO
var _pack_opening_blocks_screen_focus := false
var _loss_cinematic_active := false
var _npc_rescue_intro_active := false
var _npc_rescue_intro_id := ""
var _npc_rescue_intro_tween: Tween
var _npc_rescue_intro_aborted := false
var imprisoned_npcs: IMPRISONED_NPC_SCRIPT
var _greeting_active := false
var _playtime_encounter: Node3D
var _greeting: Node3D
var _satan_jumpscare: JUMPSCARE_SCRIPT
var _satan_stream: Node3D
var _jumpscare_active := false
var _cinematic_input_block_frame := -1
var _loss_music_tween: Tween = null
var _loss_music_restore_db := 0.0
var _loss_music_restore_pending := false


func _ready() -> void:
	_setup_localized_neon_signs()
	_setup_room_music()
	_setup_room_ambience()
	var ambient_screams := AMBIENT_SCREAMS_SCRIPT.new()
	ambient_screams.name = "AmbientScreams"
	add_child(ambient_screams)
	_start_wakeup_blur()
	_base_x_rotation = camera_pivot.rotation.x
	_settle_origin_y = camera_pivot.rotation.y
	_settle_target_y = _settle_origin_y
	_settle_step_index = 0
	_visual_pivot_rotation = Vector3(
		_base_x_rotation,
		_settle_target_y,
		0.0
	)
	camera_pivot.rotation = _visual_pivot_rotation
	if main_camera != null:
		_hub_camera_base_basis = main_camera.transform.basis
		_hub_camera_base_transform = main_camera.transform
		_hub_camera_base_fov = main_camera.fov
	_hub_settle_origin_y = _settle_origin_y
	_setup_upgrade_collection()
	bed_seating = BED_SEATING_SCRIPT.new()
	bed_seating.name = "BedSeating"
	add_child(bed_seating)
	bed_seating.configure(self, empty_room)
	_setup_fusion_workbench()
	_setup_journal()
	_setup_crypt_gate()
	_setup_prisoner_dialogue()
	_setup_progression_areas()
	access_key_tray.context_available = _access_key_context_is_safe
	access_key_tray.key_available = _can_use_access_key
	access_key_tray.key_requested.connect(_on_access_key_requested)
	black_market_board.camera = main_camera
	black_market_board.card_purchased.connect(_on_fusion_completed)
	dealer_dialogue.camera = main_camera
	dealer_dialogue.context_available = _dealer_context_is_safe
	dealer_dialogue.modal_changed.connect(_on_dealer_modal_changed)
	basement_cat.camera = main_camera
	basement_cat.modal_changed.connect(_on_basement_cat_modal_changed)
	_setup_basement_boilers()
	basement_pump_control.camera = main_camera
	basement_pump_control.context_available = _pump_control_context_is_safe
	_setup_turn_arrows()
	_claim_shared_camera_for_hub_rotation(true)
	_setup_screen_camera_focus()
	graveyard_jester.camera = main_camera
	graveyard_jester.modal_changed.connect(_on_jester_modal_changed)
	_connect_pack_opening_focus_state()
	_connect_loss_exit_cinematic()
	_disable_embedded_scene_controls()
	_connect_pack_collection_refresh()
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null:
		collection.angel_presence_available = _npc_has_reached_station.bind("angel")
		collection.slot_room_key_requested.connect(_on_slot_room_key_requested)
		collection.angel_dialog_changed.connect(_on_angel_dialog_changed)
		pause_menu.visibility_changed.connect(func() -> void:
			collection.suspend_deck_input(pause_menu.visible or _is_journal_active())
		)
	_update_active_scene_interaction()
	_update_labels()
	Localization.locale_changed.connect(_update_labels)
	_update_screen_camera_focus_context()
	hub_door.activated.connect(_on_room_door_activated)
	return_door.activated.connect(_on_room_door_activated)
	_update_room_door_interaction()
	# Loading the hub also leaves the previous basement scene behind.
	GameCurrency.npc_rescue_changed.connect(_refresh_npc_rescue_state)
	CollectionManager.collection_changed.connect(_on_npc_rescue_collection_changed)
	imprisoned_npcs = IMPRISONED_NPC_SCRIPT.new()
	imprisoned_npcs.name = "ImprisonedNPCPresentation"
	imprisoned_npcs.reveal_duration = imprisoned_reveal_duration
	imprisoned_npcs.departure_duration = imprisoned_departure_duration
	add_child(imprisoned_npcs)
	imprisoned_npcs.configure(self, scene_pivot.get_node("GameTable") as GameTable)
	imprisoned_npcs.presentation_changed.connect(_refresh_npc_rescue_state)
	_refresh_npc_rescue_state()
	_setup_satan_jumpscare()
	weed_pickup.configure(self, $Hint1, $EmptyRoom/hint2)
	GameCurrency.mark_basement_cat_left()
	PlaytimeManager.timer_reset.connect(_on_playtime_timer_reset)
	NetworkManager.lobby_state_changed.connect(_on_greeting_lobby_changed)
	if _start_greeting_if_needed():
		return
	music.play()
	if CollectionManager.get_meta("slot_room_key_focus_requested", false):
		CollectionManager.remove_meta("slot_room_key_focus_requested")
		_on_slot_room_key_requested.call_deferred(true)


func _on_npc_rescue_collection_changed(_ids: Array[String]) -> void:
	_refresh_npc_rescue_state()


func _refresh_npc_rescue_state() -> void:
	var waiting := GameCurrency.get_imprisoned_npc_ids()
	var table := scene_pivot.get_node("GameTable") as GameTable
	if is_instance_valid(imprisoned_npcs):
		var story_victory := not table._online_mode and table._local_mode == "story" and table._table_state == GameTable.TableState.GAME_OVER and table._last_match_outcome == GameTable.MatchOutcome.WIN
		imprisoned_npcs.sync_waiting(waiting, story_victory)
	$ScenePivot/Collection/angel.visible = _npc_has_reached_station("angel")
	$BlackMarketRoom/Kiosk/Dealer.visible = _npc_has_reached_station("dealer")
	$GraveyardRoom/jester.visible = _npc_has_reached_station("jester")
	$GraveyardRoom/Crypt/Prisoner.visible = _npc_has_reached_station("prisoner")
	_update_active_scene_interaction()
	_update_room_door_interaction()


func _npc_has_reached_station(npc_id: String) -> bool:
	return GameCurrency.is_npc_rescued(npc_id) and (not is_instance_valid(imprisoned_npcs) or not imprisoned_npcs.is_awaiting_departure(npc_id))


func _try_start_npc_rescue_intro() -> bool:
	if _npc_rescue_intro_active or not _can_turn(false) or _door_key_view_active or access_key_tray.is_expanded():
		return false
	if not main_camera.is_current() or NetworkManager.has_active_session() or NetworkManager.is_lobby_operation_pending():
		return false
	var npc_id := ""
	var actor: Sprite3D
	if _active_room == 0 and _active_side == 2:
		npc_id = "angel"
		actor = $ScenePivot/Collection/angel
	elif _active_room == 4 and _active_side == black_market_board.view_side:
		npc_id = "dealer"
		actor = $BlackMarketRoom/Kiosk/Dealer
	elif _active_room == 2 and not _crypt_gate_close and _active_side == graveyard_jester.view_side:
		npc_id = "jester"
		actor = $GraveyardRoom/jester
	elif _active_room == 2 and _crypt_gate_close and _active_side == 0:
		npc_id = "prisoner"
		actor = $GraveyardRoom/Crypt/Prisoner
	if npc_id.is_empty() or not GameCurrency.is_npc_rescue_intro_pending(npc_id) or not actor.is_visible_in_tree():
		return false
	_play_npc_rescue_intro(npc_id, actor)
	return true


func _npc_rescue_face_position(actor: Sprite3D) -> Vector3:
	var height := actor.texture.get_height() * actor.pixel_size * actor.global_basis.get_scale().y / maxi(actor.vframes, 1)
	var width := actor.texture.get_width() * actor.pixel_size * actor.global_basis.get_scale().x / maxi(actor.hframes, 1)
	var uv: Vector2 = NPC_RESCUE_FACE_UVS.get(str(actor.name), Vector2(0.5, 0.4))
	var up := actor.global_basis.y.normalized() if actor.billboard == BaseMaterial3D.BILLBOARD_DISABLED else Vector3.UP
	var right := actor.global_basis.x.normalized() if actor.billboard == BaseMaterial3D.BILLBOARD_DISABLED else main_camera.global_basis.x.normalized()
	return actor.global_position + up * height * (0.5 - uv.y) + right * width * (uv.x - 0.5)


func _npc_rescue_camera_pose(actor: Sprite3D) -> Transform3D:
	var face := _npc_rescue_face_position(actor)
	var height := actor.texture.get_height() * actor.pixel_size * actor.global_basis.get_scale().y / maxi(actor.vframes, 1)
	var outward := main_camera.global_position - face
	outward.y = 0.0
	outward = outward.normalized()
	var eye := face + outward * maxf(height * 0.95, 0.8)
	if str(actor.name) == "Prisoner":
		# Look through the rightmost gap in the grille, staying in front of it.
		# Moving straight toward the leaning sprite hides its face behind a post.
		var crypt := actor.get_parent() as Node3D
		var local_face := crypt.to_local(face)
		var gate_z := crypt.to_local(crypt_gate.gate_area.global_position).z
		eye = crypt.to_global(Vector3(-0.28, local_face.y, gate_z + 1.4))
	return Transform3D(Basis.looking_at(face - eye, Vector3.UP), eye)


func _play_npc_rescue_intro(npc_id: String, actor: Sprite3D) -> void:
	_npc_rescue_intro_active = true
	_npc_rescue_intro_aborted = false
	_npc_rescue_intro_id = npc_id
	_room_transition_active = true
	_pending_direction = 0
	# Hand over the visible camera pose without snapping out of a hover zoom.
	var return_pose := main_camera.transform
	var return_fov := main_camera.fov
	var focus_resume := screen_camera_focus.suspend_for_cinematic()
	_claim_shared_camera_for_hub_rotation(false)
	main_camera.transform = return_pose
	pause_menu.set_cinematic_locked(true)
	_set_journal_input_blocked(true)
	level_progress.set_enabled(false)
	access_key_tray.set_enabled(false)
	_update_active_scene_interaction()
	_update_room_door_interaction()
	turn_arrows.refresh()
	var focused_pose := _npc_rescue_camera_pose(actor)
	var focused_fov := minf(return_fov, 44.0)
	_npc_rescue_intro_tween = create_tween().set_parallel(true)
	_npc_rescue_intro_tween.tween_property(main_camera, "global_transform", focused_pose, npc_intro_approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_npc_rescue_intro_tween.tween_property(main_camera, "fov", focused_fov, npc_intro_approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_npc_rescue_intro_tween.finished.connect(_npc_rescue_step_finished.emit, CONNECT_ONE_SHOT)
	await _npc_rescue_step_finished
	if _npc_rescue_intro_aborted:
		return
	_npc_rescue_intro_tween = null
	var dialogue := preload("res://scripts/main/NPCRescueDialogue.gd").new()
	dialogue.name = "NPCRescueDialogue"
	dialogue.npc_id = npc_id
	dialogue.actor = actor
	dialogue.camera = main_camera
	add_child(dialogue)
	dialogue.interaction_enabled = true
	var completed := false
	if dialogue.open_dialog():
		dialogue.modal_changed.connect(func(opened: bool):
			if not opened:
				_npc_rescue_step_finished.emit()
		)
		await _npc_rescue_step_finished
		if _npc_rescue_intro_aborted:
			return
		completed = true
	dialogue.queue_free()
	# The rig and its side/room heading never move. Restore the exact lens
	# transform and FOV, including the Crypt's authored downward view.
	_npc_rescue_intro_tween = create_tween().set_parallel(true)
	_npc_rescue_intro_tween.tween_property(main_camera, "transform", return_pose, npc_intro_return_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_npc_rescue_intro_tween.tween_property(main_camera, "fov", return_fov, npc_intro_return_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_npc_rescue_intro_tween.finished.connect(_npc_rescue_step_finished.emit, CONNECT_ONE_SHOT)
	await _npc_rescue_step_finished
	if _npc_rescue_intro_aborted:
		return
	_npc_rescue_intro_tween = null
	main_camera.transform = return_pose
	main_camera.fov = return_fov
	if completed:
		GameCurrency.complete_npc_rescue_intro(npc_id)
	_room_transition_active = false
	_npc_rescue_intro_active = false
	_npc_rescue_intro_id = ""
	_cinematic_input_block_frame = Engine.get_process_frames() + 1
	pause_menu.set_cinematic_locked(false)
	_set_journal_input_blocked(false)
	_update_labels()
	_refresh_npc_rescue_state()
	_update_screen_camera_focus_context()
	screen_camera_focus.resume_after_cinematic(focus_resume)
	turn_arrows.refresh()


func _on_playtime_timer_reset() -> void:
	if is_instance_valid(_playtime_encounter):
		_playtime_encounter.cancel()


func _try_start_playtime_encounter() -> bool:
	if is_instance_valid(_playtime_encounter):
		return true
	if not PlaytimeManager.is_encounter_pending() or _active_room != 0:
		return false
	if not _can_turn(false) or _npc_rescue_intro_active or _door_key_view_active or access_key_tray.is_expanded():
		return false
	if not main_camera.is_current() or NetworkManager.has_active_session() or NetworkManager.is_lobby_operation_pending():
		return false
	var table := scene_pivot.get_node("GameTable") as GameTable
	if table._table_state != GameTable.TableState.MENU or table.is_offline_board_open() or table._satan_is_dying:
		return false
	# Hand over the currently visible pose, including a shop's hover framing.
	var return_pose := main_camera.transform
	var return_fov := main_camera.fov
	var focus_resume := screen_camera_focus.suspend_for_cinematic()
	_claim_shared_camera_for_hub_rotation(false)
	main_camera.transform = return_pose
	main_camera.fov = return_fov
	_playtime_encounter = preload("res://scripts/main/SatanPlaytimeEncounter.gd").new()
	_playtime_encounter.name = "SatanPlaytimeEncounter"
	_playtime_encounter.camera = main_camera
	_playtime_encounter.actor = table.dealer_satan
	_pending_direction = 0
	pause_menu.set_cinematic_locked(true)
	_set_journal_input_blocked(true)
	level_progress.set_enabled(false)
	access_key_tray.set_enabled(false)
	turn_arrows.refresh()
	add_child(_playtime_encounter)
	_playtime_encounter.finished.connect(func():
		_playtime_encounter = null
		_cinematic_input_block_frame = Engine.get_process_frames() + 1
		pause_menu.set_cinematic_locked(false)
		_set_journal_input_blocked(false)
		_update_screen_camera_focus_context()
		screen_camera_focus.resume_after_cinematic(focus_resume)
		turn_arrows.refresh()
	)
	_playtime_encounter.start(table)
	return true


func _start_greeting_if_needed() -> bool:
	if not greeting_enabled or GameCurrency.greeting_completed or _greeting_active:
		return false
	# Steam invites and active matches keep their existing entry path.
	if NetworkManager.has_active_session() or NetworkManager.is_lobby_operation_pending():
		return false
	_greeting_active = true
	_pending_direction = 0
	pause_menu.set_cinematic_locked(true)
	screen_camera_focus.set_context(_active_side, false)
	screen_camera_focus.restore_immediately()
	_claim_shared_camera_for_hub_rotation(true)
	if _wakeup_blur_tween != null:
		_wakeup_blur_tween.kill()
		_wakeup_blur_tween = null
	if _wakeup_blur_material != null:
		_wakeup_blur_material.set_shader_parameter("blur_strength", WAKEUP_BLUR_END)
	_set_journal_input_blocked(true)
	level_progress.set_enabled(false)
	access_key_tray.set_enabled(false)
	turn_arrows.refresh()
	_greeting = GREETING_SCRIPT.new()
	_greeting.name = "SatanGreeting"
	add_child(_greeting)
	_greeting.finished.connect(_on_greeting_finished)
	var table := scene_pivot.get_node("GameTable") as GameTable
	_greeting.start(self, main_camera, table.dealer_satan)
	return true


func _on_greeting_finished() -> void:
	music.play()
	_greeting_active = false
	_greeting = null
	_pending_direction = 0
	_cinematic_input_block_frame = Engine.get_process_frames() + 1
	pause_menu.set_cinematic_locked(false)
	_set_journal_input_blocked(false)
	turn_arrows.refresh()
	if CollectionManager.get_meta("slot_room_key_focus_requested", false):
		CollectionManager.remove_meta("slot_room_key_focus_requested")
		_on_slot_room_key_requested.call_deferred(false)


func _on_greeting_lobby_changed() -> void:
	if is_instance_valid(_playtime_encounter) and NetworkManager.has_active_session():
		_playtime_encounter.cancel()
	if is_instance_valid(_satan_stream) and NetworkManager.has_active_session():
		_satan_stream.stop_pissing(true)
	if _jumpscare_active and NetworkManager.has_active_session():
		_satan_jumpscare.cancel()
	if _greeting_active and NetworkManager.has_active_session() and is_instance_valid(_greeting):
		_greeting.cancel()


func _setup_satan_jumpscare() -> void:
	var table := scene_pivot.get_node("GameTable") as GameTable
	_satan_jumpscare = JUMPSCARE_SCRIPT.new()
	_satan_jumpscare.name = "SatanJumpscare"
	add_child(_satan_jumpscare)
	_satan_jumpscare.configure(main_camera, table.dealer_satan, table.satan_hover_area,
		_satan_jumpscare_context_is_safe, ($hospitalRoom as Node3D).global_position.y)
	_satan_jumpscare.started.connect(_on_satan_jumpscare_started)
	_satan_jumpscare.recovery_started.connect(_on_satan_jumpscare_recovery_started)
	_satan_jumpscare.cancelled.connect(func() -> void: blood_overlay.clear())
	_satan_jumpscare.finished.connect(_on_satan_jumpscare_finished)
	_satan_stream = table.get_node("dealer/SatanMotionRoot/satan/Piss")
	_satan_stream.configure(main_camera, table.dealer_satan, table.get_node("table/Cube"), _satan_jumpscare_context_is_safe)
	_satan_stream.emitting_changed.connect(table.set_satan_stream_laughing)
	_satan_stream.emitting_changed.connect(AchievementManager.record_satan_stream)
	_satan_jumpscare.started.connect(AchievementManager.record_satan_jumpscare)
	_satan_jumpscare.halfway_clicked.connect(_satan_stream.start_pissing)


func _satan_jumpscare_context_is_safe() -> bool:
	if _jumpscare_active or not _can_turn(false) or _active_room != 0 or _active_side != 0:
		return false
	if NetworkManager.has_active_session() or NetworkManager.is_lobby_operation_pending():
		return false
	var table := scene_pivot.get_node("GameTable") as GameTable
	return (table._table_state == GameTable.TableState.MENU and not table.is_offline_board_open()
		and not table._journal_input_blocked and not table._satan_is_dying and not table._satan_is_laughing
		and table.dealer_satan.is_visible_in_tree() and table.satan_hover_area.input_ray_pickable
		and get_viewport().get_camera_3d() == main_camera)


func _on_satan_jumpscare_started() -> void:
	_satan_stream.stop_pissing(true)
	_jumpscare_active = true
	_pending_direction = 0
	pause_menu.set_cinematic_locked(true)
	screen_camera_focus.set_context(_active_side, false)
	screen_camera_focus.restore_immediately()
	_claim_shared_camera_for_hub_rotation(true)
	_set_journal_input_blocked(true)
	# Clear the ordinary hover before the scare records and replaces the sheet.
	# A delayed mouse-exit must not restore idle artwork over the close-up.
	(scene_pivot.get_node("GameTable") as GameTable)._set_satan_hovered(false)
	level_progress.set_enabled(false)
	access_key_tray.set_enabled(false)
	turn_arrows.refresh()


func _on_satan_jumpscare_recovery_started() -> void:
	blood_overlay.play()


func _on_satan_jumpscare_finished() -> void:
	_jumpscare_active = false
	_pending_direction = 0
	_cinematic_input_block_frame = Engine.get_process_frames() + 1
	pause_menu.set_cinematic_locked(false)
	_set_journal_input_blocked(false)
	turn_arrows.refresh()


func _setup_localized_neon_signs() -> void:
	for entry in [["collection", "COLLECTION"], ["shop", "SHOP"], ["upgrade", "UPGRADE"]]:
		LocalizedModelText.attach_neon(get_node_or_null(entry[0]) as Node3D, entry[1])


func _start_wakeup_blur(duration: float = -1.0) -> void:
	# Set the first value before Main can render, without changing the scene's
	# shared lens material or the separate main-menu lens.
	if _wakeup_blur_tween != null and _wakeup_blur_tween.is_valid():
		_wakeup_blur_tween.kill()
	if _wakeup_blur_material == null:
		_wakeup_blur_material = dirty_lens.material.duplicate() as ShaderMaterial
		dirty_lens.material = _wakeup_blur_material
	_wakeup_blur_material.set_shader_parameter("blur_strength", WAKEUP_BLUR_START)
	_wakeup_blur_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_wakeup_blur_tween.tween_property(
		_wakeup_blur_material, "shader_parameter/blur_strength", WAKEUP_BLUR_END,
		maxf(wakeup_blur_duration if duration < 0.0 else duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _exit_tree() -> void:
	_npc_rescue_intro_aborted = true
	if _npc_rescue_intro_tween != null and _npc_rescue_intro_tween.is_valid():
		_npc_rescue_intro_tween.kill()
	_npc_rescue_intro_tween = null
	if _npc_rescue_intro_active:
		# A killed Tween never emits finished. Wake the owned coroutine before
		# its scene disappears, preserving the pending greeting for next time.
		_npc_rescue_step_finished.emit()
	_cleanup_room_music()
	if _room_ambience_tween != null:
		_room_ambience_tween.kill()
	if _door_key_tween != null and _door_key_tween.is_valid():
		_door_key_tween.kill()
	if _wakeup_blur_tween != null and _wakeup_blur_tween.is_valid():
		_wakeup_blur_tween.kill()


func _input(event: InputEvent) -> void:
	if _npc_rescue_intro_active:
		return
	if _greeting_active or _jumpscare_active:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(bed_seating) and bed_seating.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if secret_wall_input.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if (
		(game_table != null and game_table.try_skip_offline_exit(event))
		or Engine.get_process_frames() <= _cinematic_input_block_frame
	):
		get_viewport().set_input_as_handled()
		return
	if _is_progression_area_open() or _is_angel_busy() or _is_basement_cat_busy() or _is_prisoner_busy():
		return
	if event.is_action_pressed("journal") and not event.is_echo():
		_toggle_journal()
		get_viewport().set_input_as_handled()
		return
	if _is_journal_active():
		return
	if _crypt_gate_close and _can_travel_between_rooms() and not pause_menu.settings_menu.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			get_viewport().set_input_as_handled()
			_travel_to_crypt_gate(false)
			return
	_debug_interaction_click(event)
	if event is InputEventKey \
	and event.pressed \
	and not event.echo \
	and event.ctrl_pressed \
	and event.keycode == KEY_A:

		CollectionManager.unlock_all_cards()
		_refresh_collection_screen()


func _debug_interaction_click(event: InputEvent) -> void:
	if not debug_interaction_clicks:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		print("[InteractionDebug] Click: keine aktive Camera3D gefunden. active_side=", _active_side, " (", SIDE_NAMES[_active_side], ")")
		return

	var mouse_position := mouse_event.position
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_position) * debug_interaction_ray_length
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		print("[InteractionDebug] Click: kein 3D-Treffer. active_side=", _active_side, " (", SIDE_NAMES[_active_side], ") mouse=", mouse_position)
		return

	var collider := hit.get("collider") as Object
	var collider_node := collider as Node
	var collider_path := "<kein Node>"
	var pickable := "n/a"
	if collider_node != null:
		collider_path = str(collider_node.get_path())
		if collider_node is Area3D:
			pickable = str((collider_node as Area3D).input_ray_pickable)

	print(
		"[InteractionDebug] Click: active_side=", _active_side, " (", SIDE_NAMES[_active_side], ")",
		" mouse=", mouse_position,
		" hit=", collider_path,
		" pickable=", pickable,
		" position=", hit.get("position"),
		" normal=", hit.get("normal")
	)

func _process(delta: float) -> void:
	if _try_start_playtime_encounter():
		return
	if _greeting_active or _jumpscare_active or _npc_rescue_intro_active:
		return
	if _try_start_npc_rescue_intro():
		return
	_update_walking_steps(delta)
	if _is_journal_active() and not _journal_context_is_safe():
		journal.close_journal(true)
	access_key_tray.set_enabled(_access_key_context_is_safe())
	level_progress.set_enabled(
		not _loss_cinematic_active
		and not _is_bed_busy()
		and not _room_transition_active
		and not _pack_opening_blocks_screen_focus
		and not _is_upgrade_collection_detail_open()
		and not _is_fusion_workbench_busy()
		and not _is_jester_busy()
		and not _is_prisoner_busy()
		and not _is_dealer_busy()
		and not _is_angel_busy()
		and not _is_basement_cat_busy()
		and not _is_boiler_dragging()
		and not _is_journal_active()
		and not _is_progression_area_open()
		and not (pause_menu != null and pause_menu.visible)
		and not table_lobby.visible
	)
	_update_room_door_interaction()
	if _room_transition_active or _is_journal_active() or _is_progression_area_open():
		return
	_read_input()

	if _pending_direction != 0:
		var dir := _pending_direction
		_pending_direction = 0
		_request_turn(dir)

	_advance_phase(delta)
	if not _loss_cinematic_active and not _is_bed_busy() and not _is_angel_busy() and not _is_dealer_busy() and not _is_basement_cat_busy() and not _is_prisoner_busy() and not _is_boiler_dragging():
		_update_mouse_tilt(delta)
	_update_screen_camera_focus_context()


func _read_input() -> void:
	if not _can_turn():
		return

	if Input.is_action_just_pressed(input_action_left):
		_pending_direction = -1
	elif Input.is_action_just_pressed(input_action_right):
		_pending_direction = 1


func _setup_turn_arrows() -> void:
	turn_arrows = TURN_ARROWS_SCRIPT.new()
	turn_arrows.name = "TurnArrows"
	add_child(turn_arrows)
	turn_arrows.configure(_can_turn.bind(false))
	turn_arrows.turn_requested.connect(func(direction: int): _request_turn(direction, false))
	pause_menu.visibility_changed.connect(turn_arrows.refresh)


func _can_turn(allow_interrupt: bool = true) -> bool:
	if is_instance_valid(_playtime_encounter):
		return false
	if _is_bed_busy():
		return false
	if is_instance_valid(secret_wall_input) and secret_wall_input.is_busy():
		return false
	if _greeting_active or _jumpscare_active or _is_boiler_dragging():
		return false
	if Engine.get_process_frames() <= _cinematic_input_block_frame:
		return false
	if not is_inside_tree() or get_tree().paused or _loss_cinematic_active or _room_transition_active:
		return false
	if not allow_interrupt and _phase != Phase.IDLE:
		return false
	if pause_menu.visible or pause_menu.settings_menu.visible or table_lobby.visible or _pack_opening_blocks_screen_focus:
		return false
	if _is_upgrade_collection_detail_open() or _is_fusion_workbench_busy() or _is_jester_busy() or _is_prisoner_busy() or _is_angel_busy() or _is_dealer_busy() or _is_basement_cat_busy() or _is_journal_active() or _is_progression_area_open():
		return false
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if game_table != null and game_table.is_match_active():
		return false
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null and (
		collection._detail_card != null or collection._detail_tween_running
		or collection._deck_fan_open or collection._deck_fan_tween_running
		or collection._dragged_fan_card != null or collection._slot_room_key_request_pending
	):
		return false
	return true


func _request_turn(direction: int, allow_interrupt: bool = true) -> bool:
	if direction == 0 or not _can_turn(allow_interrupt):
		return false
	_pending_direction = 0
	_begin_turn(direction)
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()
	return true


func _advance_phase(delta: float) -> void:
	if _phase == Phase.IDLE:
		return

	_elapsed += delta
	var t := 1.0
	if _phase_duration > 0.0:
		t = clampf(_elapsed / _phase_duration, 0.0, 1.0)

	var eased_t := _ease(t, _phase_ease_kind)
	_visual_pivot_rotation = _phase_start.lerp(_phase_end, eased_t)
	camera_pivot.rotation = _visual_pivot_rotation

	if t >= 1.0:
		_visual_pivot_rotation = _phase_end
		camera_pivot.rotation = _visual_pivot_rotation
		_advance_to_next_phase()


func _advance_to_next_phase() -> void:
	match _phase:
		Phase.OVERSHOOT:
			# Phase 1 fertig -> Phase 2 (Einrasten) startet GENAU dort,
			# wo Phase 1 visuell aufgehört hat. Das Ziel ist immer
			# _settle_target_y - die geschützte, logische Wahrheit.
			_phase = Phase.SETTLE
			_elapsed = 0.0
			_phase_start = _visual_pivot_rotation
			_phase_end = Vector3(_base_x_rotation, _settle_target_y, 0.0)
			_phase_duration = settle_duration
			_phase_ease_kind = EaseKind.BACK_OUT
		Phase.SETTLE:
			_phase = Phase.IDLE
			_elapsed = 0.0
			_snap_camera_pivot_to_cardinal_target()
		Phase.IDLE:
			pass


func _begin_turn(direction: int) -> void:
	if not _can_turn():
		return
	var turn_direction := signi(direction)
	if turn_direction == 0:
		return
	if not is_instance_valid(_turn_sound):
		_turn_sound = AudioStreamPlayer.new()
		_turn_sound.name = "TurnSound"
		_turn_sound.stream = TURN_SOUND
		_turn_sound.bus = &"SFX"
		_turn_sound.max_polyphony = 4
		add_child(_turn_sound)
	_turn_sound.play()
	if _door_key_view_active:
		_door_key_view_active = false
		if is_instance_valid(_key_reveal_door):
			_key_reveal_door.set_travel_open(false)
		_key_reveal_door = null
	access_key_tray.set_enabled(false)

	# Falls GameTable nach einem Szenenaufbau oder Cinematic noch seinen
	# Rückkehr-Tween auf der gemeinsam genutzten Kamera besitzt, übernimmt der
	# Hub ihn vor der ersten Drehung. Sonst kann der Global-Tween eine lokale
	# Gegenrotation genau in dem Moment einfrieren, in dem der Pivot passiert.
	if _phase == Phase.IDLE:
		_claim_shared_camera_for_hub_rotation(false)

	# Ein eventuell aktiver Bildschirmfokus fährt zurück, bevor sich die
	# übergeordnete Kamerabasis dreht. Position/FOV bleiben so unabhängig
	# von der Seitenanimation.
	if screen_camera_focus != null:
		screen_camera_focus.set_context(_active_side, false)

	# KERNFIX: der neue Zielwinkel wird von _settle_target_y aus berechnet -
	# der letzten GÜLTIGEN Seite - niemals von camera_pivot.rotation.y (das
	# wäre die fehlerhafte, visuelle Zwischenposition gewesen).
	var step := deg_to_rad(rotation_step_degrees)
	_settle_step_index -= turn_direction
	var new_target_y := (
		_settle_origin_y
		+ step * float(_settle_step_index)
	)
	_settle_target_y = new_target_y

	# Die Kamera rotiert visuell in die Gegenrichtung der logischen Seitenfolge:
	# direction=-1 schaut zur linken Szene (Pack Shop), direction=+1 zur rechten
	# Szene (Upgrade Shop). Deshalb muss der aktive Seitenindex gegenläufig
	# zur Eingaberichtung laufen, sonst werden PackShop/Upgrade vertauscht
	# aktiviert und der sichtbare Screen bleibt nicht-pickable.
	_active_side = posmod(_active_side - turn_direction, SIDE_COUNT)
	_update_active_scene_interaction()
	_update_labels()

	var sway_y := new_target_y + deg_to_rad(sway_angle_degrees) * float(turn_direction) * -1.0
	var roll := deg_to_rad(roll_angle_degrees) * float(turn_direction) * -1.0
	var dip := _base_x_rotation + deg_to_rad(pitch_dip_degrees)

	# Der visuelle Startpunkt der Animation ist die aktuelle Kamera-Rotation -
	# das ist rein kosmetisch (sorgt für nahtloses Umlenken beim Spammen)
	# und beeinflusst NICHT, welche Seite am Ende erreicht wird.
	_phase = Phase.OVERSHOOT
	_elapsed = 0.0
	_phase_start = _visual_pivot_rotation
	_phase_end = Vector3(dip, sway_y, roll)
	_phase_duration = rotation_duration
	_phase_ease_kind = EaseKind.CUBIC_OUT
	_update_room_door_interaction()


func _snap_camera_pivot_to_cardinal_target() -> void:
	# Neu aus dem ganzzahligen Schrittindex berechnen, nicht aus einem bereits
	# interpolierten Float. Damit endet jede akzeptierte Eingabe exakt auf ihrem
	# 90-Grad-Rasterpunkt, auch nach vielen oder unterbrochenen Drehungen.
	_settle_target_y = (
		_settle_origin_y
		+ deg_to_rad(rotation_step_degrees) * float(_settle_step_index)
	)
	_visual_pivot_rotation = Vector3(
		_base_x_rotation,
		_settle_target_y,
		0.0
	)
	camera_pivot.rotation = _visual_pivot_rotation


func _claim_shared_camera_for_hub_rotation(force_startup_claim: bool) -> void:
	if main_camera == null or not is_instance_valid(main_camera):
		return

	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	var may_claim := force_startup_claim
	if game_table != null and game_table.table_camera == main_camera:
		# Im Parent-_ready ist dies garantiert der redundante Start-Menü-Tween.
		# Später darf Main nur im inaktiven Tisch-Menü übernehmen; Match- und
		# Cinematic-Kamerafahrten bleiben vollständig Eigentum von GameTable.
		may_claim = force_startup_claim or not game_table.is_match_active()
		if may_claim and game_table._camera_tween != null:
			if game_table._camera_tween.is_valid():
				game_table._camera_tween.kill()
			game_table._camera_tween = null
	if not may_claim:
		return

	# Nur die lokale Basis neutralisieren. Position und FOV gehören weiterhin
	# ScreenCameraFocus, sodass dessen weiche Rückfahrt beim Drehen erhalten bleibt.
	var camera_transform := main_camera.transform
	camera_transform.basis = _crypt_camera_base_transform.basis if _crypt_gate_close else _hub_camera_base_basis
	main_camera.transform = camera_transform


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


func _can_travel_between_rooms() -> bool:
	if _is_bed_busy():
		return false
	if _greeting_active or _jumpscare_active or _is_boiler_dragging():
		return false
	if _room_transition_active or _phase != Phase.IDLE or _loss_cinematic_active or get_tree().paused or _is_progression_area_open():
		return false
	if _is_upgrade_collection_detail_open() or _is_fusion_workbench_busy() or _is_jester_busy() or _is_prisoner_busy() or _is_angel_busy() or _is_dealer_busy() or _is_basement_cat_busy() or _is_journal_active():
		return false
	if _pack_opening_blocks_screen_focus or pause_menu.visible or table_lobby.visible:
		return false
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if game_table != null and game_table.is_match_active():
		return false
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null and (
		collection._detail_card != null or collection._detail_tween_running
		or collection._deck_fan_open or collection._deck_fan_tween_running
	):
		return false
	return true


func _update_room_door_interaction() -> void:
	var allowed := _can_travel_between_rooms()
	hub_door.set_locked(not CollectionManager.is_slot_room_unlocked())
	hub_door.set_interaction_enabled(allowed and _active_room == 0)
	return_door.set_interaction_enabled(allowed and _active_room == 1 and not secret_wall_input.is_busy())
	secret_wall_input.set_interaction_enabled(allowed and _active_room == 1 and _active_side == secret_wall_input.VIEW_SIDE)
	for area in progression_areas:
		area.set_interaction_enabled(allowed and _active_room == 0 and (not _door_key_view_active or area.door == _key_reveal_door))
	for room_index: int in connected_rooms:
		var room_return := connected_rooms[room_index].get_node("ReturnDoor") as HospitalDoor
		room_return.set_interaction_enabled(allowed and _active_room == room_index and not _crypt_gate_close)
		if connected_rooms[room_index] is BasementDiscovery:
			(connected_rooms[room_index] as BasementDiscovery).set_interaction_enabled(allowed and _active_room == room_index)
	slot_machine.set_interaction_enabled(allowed and _active_room == 1 and _active_side == 0 and not get_tree().paused)
	_update_upgrade_collection_interaction()
	_update_fusion_workbench_interaction()
	_update_jester_interaction()
	_update_angel_interaction()
	_update_black_market_interaction()
	_update_basement_cat_context()
	_update_basement_boiler_interaction()
	basement_pump_control.set_interaction_enabled(_pump_control_context_is_safe())
	crypt_gate.set_interaction_enabled(_crypt_gate_context_is_safe())
	crypt_gate.refresh_return_beacon()
	if is_instance_valid(prisoner_dialogue):
		prisoner_dialogue.set_interaction_enabled(_prisoner_context_is_safe())


func _crypt_gate_context_is_safe() -> bool:
	return (
		_active_room == 2 and _active_side == 0 and not _crypt_gate_close
		and _can_travel_between_rooms() and not _door_key_view_active
		and not pause_menu.settings_menu.visible
	)


func _setup_crypt_gate() -> void:
	crypt_gate = CRYPT_GATE_SCRIPT.new()
	crypt_gate.name = "CryptGateInteraction"
	crypt_gate.camera = main_camera
	crypt_gate.context_available = _crypt_gate_context_is_safe
	crypt_gate.return_available = _crypt_return_context_is_safe
	crypt_gate.activated.connect(_on_crypt_gate_activated)
	crypt_gate.return_requested.connect(func():
		if _crypt_return_context_is_safe():
			_travel_to_crypt_gate(false)
	)
	$GraveyardRoom/Crypt.add_child(crypt_gate)


func _on_crypt_gate_activated() -> void:
	if _crypt_gate_context_is_safe():
		_travel_to_crypt_gate(true)


func _crypt_return_context_is_safe() -> bool:
	return (
		_active_room == 2 and _crypt_gate_close and _can_travel_between_rooms()
		and not _door_key_view_active and not pause_menu.settings_menu.visible
	)


func _setup_prisoner_dialogue() -> void:
	prisoner_dialogue = PRISONER_DIALOGUE_SCRIPT.new()
	prisoner_dialogue.name = "PrisonerDialogue"
	prisoner_dialogue.actor = $GraveyardRoom/Crypt/Prisoner
	prisoner_dialogue.camera = main_camera
	prisoner_dialogue.context_available = _prisoner_context_is_safe
	prisoner_dialogue.modal_changed.connect(_on_prisoner_modal_changed)
	$GraveyardRoom/Crypt.add_child(prisoner_dialogue)


func _prisoner_context_is_safe() -> bool:
	# Keep its own active conversation enabled while it locks navigation.
	return (
		GameCurrency.is_npc_rescued("prisoner") and _active_room == 2 and _crypt_gate_close and _active_side == 0
		and _phase == Phase.IDLE and not _room_transition_active
		and not _greeting_active and not _jumpscare_active and not _loss_cinematic_active
		and not _door_key_view_active and not pause_menu.visible
		and not pause_menu.settings_menu.visible and not get_tree().paused
		and not table_lobby.visible and not _pack_opening_blocks_screen_focus
		and not _is_table_match_active() and not _is_journal_active()
		and not _is_progression_area_open()
	)


func _is_prisoner_busy() -> bool:
	return is_instance_valid(prisoner_dialogue) and prisoner_dialogue.is_busy()


func _on_prisoner_modal_changed(opened: bool) -> void:
	_pending_direction = 0
	if opened:
		level_progress.set_enabled(false)
	_update_room_door_interaction()
	_update_screen_camera_focus_context()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _travel_to_crypt_gate(approach: bool) -> void:
	if _room_transition_active:
		return
	if approach:
		_crypt_return_pivot = camera_pivot.global_transform
	var visible_pose := main_camera.global_transform
	_room_transition_active = true
	_crypt_gate_close = approach
	_pending_direction = 0
	pause_menu.set_cinematic_locked(true)
	screen_camera_focus.set_context(_active_side, false)
	screen_camera_focus.restore_immediately()
	_claim_shared_camera_for_hub_rotation(false)
	camera_tilt.rotation = Vector3.ZERO
	main_camera.transform = _hub_camera_base_transform
	var camera_to_pivot := _hub_camera_base_transform.affine_inverse()
	var start := visible_pose * camera_to_pivot
	var target: Transform3D = crypt_gate.get_approach_camera_pose() * camera_to_pivot if approach else _crypt_return_pivot
	if not approach:
		# Walk back to the crossing while keeping the direction the player
		# currently faces; returning must not turn them toward the crypt.
		target.basis = camera_pivot.global_basis
	var resting_pivot := target
	if approach:
		# Keep the turning rig upright at the new position. The close view's
		# downward look belongs to the camera, so A/D rotates in place.
		var eye_pose: Transform3D = crypt_gate.get_approach_camera_pose()
		resting_pivot.basis = _crypt_return_pivot.basis
		resting_pivot.origin = eye_pose.origin - resting_pivot.basis * _hub_camera_base_transform.origin
		_crypt_camera_base_transform = _hub_camera_base_transform
		_crypt_camera_base_transform.basis = resting_pivot.basis.inverse() * eye_pose.basis
	camera_pivot.global_transform = start
	level_progress.set_enabled(false)
	_update_room_door_interaction()
	turn_arrows.refresh()
	_start_walking_sequence(maxf(room_travel_duration, 0.01))
	_room_travel_tween = create_tween()
	_room_travel_tween.tween_method(_apply_room_travel_pose.bind(start, target), 0.0, 1.0, maxf(room_travel_duration, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _room_travel_tween.finished
	_stop_walking_sequence()
	_room_travel_tween = null
	camera_pivot.global_transform = resting_pivot
	main_camera.transform = _crypt_camera_base_transform if approach else _hub_camera_base_transform
	if not approach:
		_snap_camera_pivot_to_cardinal_target()
	_room_transition_active = false
	pause_menu.set_cinematic_locked(false)
	_update_room_door_interaction()
	_update_screen_camera_focus_context()
	_update_labels()
	turn_arrows.refresh()


func _setup_upgrade_collection() -> void:
	upgrade_collection = UPGRADE_COLLECTION_SCENE.instantiate() as UpgradeWallCollection
	upgrade_collection.name = "UpgradeCollection"
	upgrade_collection.camera = main_camera
	empty_room.add_child(upgrade_collection)
	upgrade_collection.set_interaction_enabled(false)
	upgrade_collection.detail_open_changed.connect(_on_upgrade_collection_detail_changed)
	pause_menu.visibility_changed.connect(_on_upgrade_collection_pause_changed)


func _setup_journal() -> void:
	journal = JOURNAL_SCENE.instantiate() as Journal3D
	journal.name = "Journal"
	add_child(journal)
	journal.closed.connect(_on_journal_closed)
	journal.close_requested.connect(_on_journal_close_requested)
	var game_table := scene_pivot.get_node("GameTable") as GameTable
	game_table.journal_interrupted.connect(_interrupt_journal)


func _setup_progression_areas() -> void:
	connected_rooms = {2: $GraveyardRoom, 3: $BasementRoom, 4: $BlackMarketRoom}
	# Apply the same gates immediately when pausing; _process then stops.
	pause_menu.visibility_changed.connect(_update_room_door_interaction)
	for child in $ProgressionAreas.get_children():
		if child is ProgressionArea:
			progression_areas.append(child)
			child.screen_open_changed.connect(_on_progression_area_screen_changed)
			child.travel_requested.connect(_on_room_door_activated)
	for room_index: int in connected_rooms:
		var room_return := connected_rooms[room_index].get_node("ReturnDoor") as HospitalDoor
		room_return.activated.connect(_on_room_door_activated)
		room_return.set_interaction_enabled(false)


func _is_progression_area_open() -> bool:
	for area in progression_areas:
		if area.is_open():
			return true
	return false


func _on_progression_area_screen_changed(_opened: bool) -> void:
	_pending_direction = 0
	if _is_progression_area_open() and screen_camera_focus != null:
		screen_camera_focus.set_context(_active_side, false)
		screen_camera_focus.restore_immediately()
	_set_journal_input_blocked(_is_journal_active() or _is_progression_area_open())
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _is_journal_active() -> bool:
	return is_instance_valid(journal) and journal.is_active()


func _journal_context_is_safe() -> bool:
	if _is_bed_busy():
		return false
	if _greeting_active or _jumpscare_active or _is_boiler_dragging():
		return false
	if _room_transition_active or _phase != Phase.IDLE or _loss_cinematic_active or _is_progression_area_open():
		return false
	if pause_menu.visible or get_tree().paused or table_lobby.visible or _pack_opening_blocks_screen_focus:
		return false
	if _is_fusion_workbench_busy() or _is_upgrade_collection_detail_open() or _is_jester_busy() or _is_prisoner_busy() or _is_angel_busy() or _is_dealer_busy() or _is_basement_cat_busy():
		return false
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null and (
		collection._detail_card != null or collection._detail_tween_running
		or collection._deck_fan_open or collection._deck_fan_tween_running
		or collection._dragged_fan_card != null or collection._slot_room_key_request_pending
	):
		return false
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	return game_table != null and game_table.is_journal_available()


func _can_open_journal() -> bool:
	return not _is_journal_active() and _journal_context_is_safe()


func _toggle_journal() -> void:
	if _is_journal_active():
		journal.close_journal()
		return
	if not _can_open_journal():
		return
	_pending_direction = 0
	if screen_camera_focus != null:
		# A focused shop returns before the book records its resting pose. The
		# battle camera owns a different pose and must never be reset to the hub.
		var had_screen_focus := screen_camera_focus.is_focused() or screen_camera_focus._camera_tween != null
		screen_camera_focus.set_context(_active_side, false)
		if had_screen_focus:
			screen_camera_focus.restore_immediately()
	if journal.open_journal(main_camera):
		_set_journal_input_blocked(true)
	else:
		_update_screen_camera_focus_context()


func _set_journal_input_blocked(blocked: bool) -> void:
	blocked = blocked or is_instance_valid(_playtime_encounter) or _greeting_active or _jumpscare_active or _is_progression_area_open()
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if game_table != null:
		game_table.set_journal_input_blocked(blocked)
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null:
		collection.suspend_deck_input(blocked or pause_menu.visible)
	_update_active_scene_interaction()
	_update_room_door_interaction()
	_update_screen_camera_focus_context()


func _on_journal_closed() -> void:
	_set_journal_input_blocked(false)


func _on_journal_close_requested() -> void:
	if _is_journal_active():
		journal.close_journal()


func _interrupt_journal() -> void:
	if _is_journal_active():
		journal.close_journal(true)


func _is_bed_busy() -> bool:
	return is_instance_valid(bed_seating) and bed_seating.is_busy()


func _is_upgrade_collection_detail_open() -> bool:
	return is_instance_valid(upgrade_collection) and upgrade_collection.is_detail_open()


func _setup_fusion_workbench() -> void:
	fusion_workbench = FUSION_WORKBENCH_SCENE.instantiate() as FusionWorkbench
	fusion_workbench.name = "FusionWorkbench"
	fusion_workbench.camera = main_camera
	empty_room.add_child(fusion_workbench)
	fusion_workbench.set_interaction_enabled(false)
	fusion_workbench.fusion_completed.connect(_on_fusion_completed)


func _on_fusion_completed(_result: Dictionary) -> void:
	_refresh_collection_screen.call_deferred()


func _is_fusion_workbench_busy() -> bool:
	return is_instance_valid(fusion_workbench) and fusion_workbench.is_busy()


func _is_jester_busy() -> bool:
	return is_instance_valid(graveyard_jester) and graveyard_jester.is_busy()


func _is_basement_cat_busy() -> bool:
	return is_instance_valid(basement_cat) and basement_cat.is_busy()


func _setup_basement_boilers() -> void:
	# Authored child order is 2, 1, 4, 3. The puzzle uses the actual boiler numbers.
	for number in range(1, 5):
		var boiler := $BasementRoom/BoilerEquipment.get_node("MainBoiler_%d" % number) as BasementBoiler
		basement_boilers.append(boiler)
		boiler.camera = main_camera
		boiler.context_available = _boiler_context_is_safe
		boiler.dragging_changed.connect(_on_boiler_dragging_changed)


func _is_boiler_dragging() -> bool:
	for boiler in basement_boilers:
		if boiler.is_dragging():
			return true
	return false


func _boiler_context_is_safe() -> bool:
	return (
		_active_room == 3 and _active_side in [0, 2] and _phase == Phase.IDLE
		and not _room_transition_active and not _loss_cinematic_active
		and not _door_key_view_active and not pause_menu.visible
		and not pause_menu.settings_menu.visible and not get_tree().paused
		and not table_lobby.visible and not _pack_opening_blocks_screen_focus
		and not _is_journal_active() and not _is_progression_area_open()
		and not _is_basement_cat_busy()
	)


func _update_basement_boiler_interaction() -> void:
	var enabled := _boiler_context_is_safe()
	var newly_enabled := false
	for boiler in basement_boilers:
		var active := enabled and _active_side == boiler.view_side
		newly_enabled = newly_enabled or (active and not boiler.interaction_enabled)
		boiler.set_interaction_enabled(active)
	# Observe the settled settings as well as release signals. A temporarily
	# blocked callback must not leave a correctly displayed solution unclaimed.
	if not enabled or _is_boiler_dragging():
		return
	var settings := "%s:%s" % [GameCurrency.cocaine_consumed, GameCurrency.is_training_session()]
	for boiler in basement_boilers:
		settings += ":%.1f" % boiler.pressure
	if newly_enabled or settings != _last_checked_boiler_settings:
		_last_checked_boiler_settings = settings
		_try_claim_boiler_reward.call_deferred()


func _try_claim_boiler_reward() -> void:
	if not _boiler_context_is_safe() or _is_boiler_dragging():
		return
	var pressures: Array[float] = []
	for boiler in basement_boilers:
		pressures.append(boiler.pressure)
	var reward := CollectionManager.claim_boiler_puzzle_reward(pressures)
	if reward.is_empty():
		return
	var origin := basement_boilers[0].focus_area.global_position
	for boiler in basement_boilers:
		if boiler.view_side == _active_side:
			origin = boiler.focus_area.global_position
			if screen_camera_focus._focused_screen == boiler.focus_area:
				break
	var card := preload("res://scripts/ui/SecretCardReveal.gd").play(self, reward, main_camera, origin, true)
	if card != null:
		card.name = "BoilerPuzzleRewardReveal"


func _on_boiler_dragging_changed(_dragging: bool) -> void:
	_pending_direction = 0
	if _is_boiler_dragging():
		level_progress.set_enabled(false)
	else:
		_try_claim_boiler_reward.call_deferred()
	_update_screen_camera_focus_context()
	_update_room_door_interaction()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _pump_control_context_is_safe() -> bool:
	return (
		_active_room == 3 and _active_side == basement_pump_control.view_side
		and _can_travel_between_rooms() and not _door_key_view_active
		and not pause_menu.settings_menu.visible and not _is_table_match_active()
	)


func _update_basement_cat_context() -> void:
	if not is_instance_valid(basement_cat):
		return
	basement_cat.set_suspended(pause_menu.visible or get_tree().paused)
	# The encounter's own busy state locks doors and turns, but must not
	# disable its choice or interrupt the cat's walk on the following frame.
	basement_cat.set_context(
		_active_room == 3 and _active_side == 3 and _phase == Phase.IDLE
		and not _room_transition_active and not _loss_cinematic_active
		and not _door_key_view_active and not pause_menu.visible
		and not pause_menu.settings_menu.visible and not get_tree().paused
		and not table_lobby.visible and not _pack_opening_blocks_screen_focus
		and not _is_table_match_active() and not _is_journal_active()
		and not _is_progression_area_open()
	)


func _on_basement_cat_modal_changed(opened: bool) -> void:
	_pending_direction = 0
	if opened:
		level_progress.set_enabled(false)
		screen_camera_focus.set_context(_active_side, false)
		screen_camera_focus.restore_immediately()
		camera_tilt.rotation = Vector3.ZERO
	_update_room_door_interaction()
	_update_screen_camera_focus_context()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _is_angel_busy() -> bool:
	if not is_instance_valid(scene_pivot):
		return false
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	return collection != null and collection.is_angel_dialog_open()


func _angel_context_is_safe() -> bool:
	# Keep the current dialog enabled while its own modal state locks the hub.
	return (
		GameCurrency.is_npc_rescued("angel") and _active_room == 0 and _active_side == 2
		and _phase == Phase.IDLE and not _room_transition_active
		and not _loss_cinematic_active and not _door_key_view_active
		and not pause_menu.visible and not pause_menu.settings_menu.visible
		and not table_lobby.visible and not get_tree().paused
		and not _pack_opening_blocks_screen_focus and not _is_table_match_active()
		and not _is_journal_active() and not _is_progression_area_open()
	)


func _update_angel_interaction() -> void:
	var collection := scene_pivot.get_node_or_null("Collection") as CollectionScreen
	if collection != null:
		collection.set_angel_context_enabled(_angel_context_is_safe())
		collection.get_node("angel").visible = _npc_has_reached_station("angel")


func _on_angel_dialog_changed(opened: bool) -> void:
	_pending_direction = 0
	if opened:
		level_progress.set_enabled(false)
	_update_screen_camera_focus_context()
	_update_room_door_interaction()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _jester_context_is_safe() -> bool:
	# An open dialog holds its camera and remains interactive. Its own busy
	# state only locks the room, book and turn controls, not the dialog itself.
	return (
		is_instance_valid(graveyard_jester)
		and GameCurrency.is_npc_rescued("jester")
		and _active_room == 2 and not _crypt_gate_close and _active_side == graveyard_jester.view_side
		and _phase == Phase.IDLE and not _room_transition_active
		and not _loss_cinematic_active and not _door_key_view_active
		and not pause_menu.visible and not pause_menu.settings_menu.visible
		and not table_lobby.visible and not get_tree().paused
		and not _pack_opening_blocks_screen_focus and not _is_table_match_active()
		and not _is_journal_active() and not _is_progression_area_open()
	)


func _update_jester_interaction() -> void:
	if is_instance_valid(graveyard_jester):
		graveyard_jester.set_interaction_enabled(_jester_context_is_safe())


func _black_market_context_is_safe() -> bool:
	return (
		is_instance_valid(black_market_board)
		and GameCurrency.is_npc_rescued("dealer")
		and _active_room == 4 and _active_side == black_market_board.view_side
		and _can_travel_between_rooms() and not _door_key_view_active
		and not pause_menu.settings_menu.visible
	)


func _update_black_market_interaction() -> void:
	if is_instance_valid(black_market_board):
		black_market_board.set_interaction_enabled(_black_market_context_is_safe())
	if is_instance_valid(dealer_dialogue):
		dealer_dialogue.set_interaction_enabled(_dealer_context_is_safe())


func _is_dealer_busy() -> bool:
	return is_instance_valid(dealer_dialogue) and dealer_dialogue.is_busy()


func _dealer_context_is_safe() -> bool:
	# Its own modal locks shopping and navigation without dismissing itself.
	return (
		is_instance_valid(black_market_board)
		and GameCurrency.is_npc_rescued("dealer")
		and _active_room == 4 and _active_side == black_market_board.view_side
		and _phase == Phase.IDLE and not _room_transition_active
		and not _loss_cinematic_active and not _door_key_view_active
		and not pause_menu.visible and not pause_menu.settings_menu.visible
		and not table_lobby.visible and not get_tree().paused
		and not _pack_opening_blocks_screen_focus and not _is_table_match_active()
		and not _is_journal_active() and not _is_progression_area_open()
	)


func _on_dealer_modal_changed(opened: bool) -> void:
	_pending_direction = 0
	if opened:
		level_progress.set_enabled(false)
	_update_screen_camera_focus_context()
	_update_room_door_interaction()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _on_jester_modal_changed(_opened: bool) -> void:
	_pending_direction = 0
	_update_screen_camera_focus_context()
	_update_room_door_interaction()
	if is_instance_valid(turn_arrows):
		turn_arrows.refresh()


func _update_fusion_workbench_interaction() -> void:
	if not is_instance_valid(fusion_workbench):
		return
	fusion_workbench.set_interaction_enabled(
		_active_room == 1 and _active_side == fusion_workbench.view_side
		and _phase == Phase.IDLE and not _room_transition_active
		and not _loss_cinematic_active and not pause_menu.visible
		and not table_lobby.visible and not get_tree().paused
		and not _is_table_match_active() and not _is_upgrade_collection_detail_open()
		and not _is_journal_active()
	)


func _update_upgrade_collection_interaction() -> void:
	if not is_instance_valid(upgrade_collection):
		return
	upgrade_collection.set_interaction_enabled(
		_active_room == 1 and _active_side == upgrade_collection.view_side
		and _phase == Phase.IDLE and not _room_transition_active
		and not _loss_cinematic_active and not pause_menu.visible
		and not table_lobby.visible and not get_tree().paused
		and not _is_journal_active()
	)


func _on_upgrade_collection_pause_changed() -> void:
	if pause_menu.visible:
		_interrupt_journal()
		for area in progression_areas:
			area.close()
	if pause_menu.visible and is_instance_valid(upgrade_collection):
		upgrade_collection.close_detail(true)
	_update_upgrade_collection_interaction()
	_update_fusion_workbench_interaction()
	_update_jester_interaction()
	_update_angel_interaction()
	_update_black_market_interaction()
	_update_screen_camera_focus_context()
	if pause_menu.visible and _active_room in [1, 2, 3, 4] and screen_camera_focus != null:
		# PauseMenu pauses the tree after this signal, so finish the return now.
		screen_camera_focus.restore_immediately()


func _on_upgrade_collection_detail_changed(_opened: bool) -> void:
	_update_labels()
	_update_screen_camera_focus_context()


func _on_slot_room_key_requested(wait_for_wakeup: bool = false) -> void:
	await _on_access_key_requested(CollectionManager.SLOT_ROOM_KEY_ID, wait_for_wakeup)


func _access_key_context_is_safe() -> bool:
	return ((_active_room == 0 and _can_turn(false))
		or _can_use_access_key(CollectionManager.PUMP_REWARD_CARD_ID)
		or _can_use_access_key(CollectionManager.BOILER_REWARD_CARD_ID))


func _can_use_access_key(card_id: String) -> bool:
	if CollectionManager.get_amount(card_id) <= 0:
		return false
	if card_id == CollectionManager.PUMP_REWARD_CARD_ID:
		return (_prisoner_context_is_safe() and _can_turn(false) and not _is_prisoner_busy()
			and main_camera.is_current() and is_instance_valid(prisoner_dialogue)
			and prisoner_dialogue.actor.is_visible_in_tree()
			and not main_camera.is_position_behind(prisoner_dialogue.actor.global_position)
			and not CollectionManager.has_discovered_card(CollectionManager.PRISONER_REWARD_CARD_ID))
	if card_id == CollectionManager.BOILER_REWARD_CARD_ID:
		return (_jester_context_is_safe() and _can_turn(false) and not _is_jester_busy()
			and main_camera.is_current() and graveyard_jester.is_visible_in_tree()
			and $GraveyardRoom/jester.is_visible_in_tree()
			and not main_camera.is_position_behind($GraveyardRoom/jester.global_position)
			and not CollectionManager.has_discovered_card(CollectionManager.JESTER_STORY_REWARD_CARD_ID))
	return _active_room == 0 and not CollectionManager.get_access_key_area_id(card_id).is_empty()


func _show_prisoner_trade_reward(instance: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(main_camera):
		return
	var card := preload("res://scripts/ui/SecretCardReveal.gd").play(self, instance, main_camera, prisoner_dialogue.actor.global_position)
	if card != null:
		card.name = "PrisonerHolyWaterReveal"


func _show_jester_trade_reward(instance: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(main_camera):
		return
	var card := preload("res://scripts/ui/SecretCardReveal.gd").play(self, instance, main_camera, $GraveyardRoom/jester.global_position, true)
	if card != null:
		card.name = "JesterCrucifixReveal"


func _on_access_key_requested(card_id: String, wait_for_wakeup: bool = false) -> void:
	if card_id == CollectionManager.BOILER_REWARD_CARD_ID:
		if not _can_use_access_key(card_id):
			return
		var reward := CollectionManager.exchange_jester_eye()
		if not reward.is_empty():
			access_key_tray.set_expanded(false)
			_show_jester_trade_reward.call_deferred(reward)
		return
	if card_id == CollectionManager.PUMP_REWARD_CARD_ID:
		if not _can_use_access_key(card_id):
			return
		var reward := CollectionManager.exchange_prisoner_toilet_paper()
		if not reward.is_empty():
			access_key_tray.set_expanded(false)
			_show_prisoner_trade_reward.call_deferred(reward)
		return
	var collection := scene_pivot.get_node("Collection") as CollectionScreen
	var area_id := CollectionManager.get_access_key_area_id(card_id)
	if _active_room != 0 or area_id.is_empty() or not _can_travel_between_rooms() or pause_menu.settings_menu.visible or CollectionManager.get_amount(card_id) == 0 or CollectionManager.is_access_key_used(card_id):
		collection.finish_slot_room_key_request()
		return
	var target_door: HospitalDoor = hub_door if area_id == "slot_room" else null
	for area in progression_areas:
		if area.area_id == area_id:
			target_door = area.door
			break
	if target_door == null:
		collection.finish_slot_room_key_request()
		return
	if is_instance_valid(_key_reveal_door) and _key_reveal_door != target_door:
		_key_reveal_door.set_travel_open(false)
	_key_reveal_door = target_door
	_room_transition_active = true
	_pending_direction = 0
	_door_key_view_active = true
	access_key_tray.set_enabled(false)
	level_progress.set_enabled(false)
	pause_menu.set_cinematic_locked(true)
	screen_camera_focus.set_context(_active_side, false)
	screen_camera_focus.restore_immediately()
	_claim_shared_camera_for_hub_rotation(false)
	camera_tilt.rotation = Vector3.ZERO
	_update_active_scene_interaction()
	_update_room_door_interaction()
	if wait_for_wakeup and _wakeup_blur_tween != null and _wakeup_blur_tween.is_running():
		await _wakeup_blur_tween.finished
	# Keep the normal turning center and lens, aiming toward the real doorway.
	# The next A/D turn starts at this visible angle and returns to the usual grid.
	var direction := target_door.doorway_area.global_position - main_camera.global_position
	var target_y := atan2(-direction.x, -direction.z)
	var start_rotation := camera_pivot.rotation
	target_y = start_rotation.y + wrapf(target_y - start_rotation.y, -PI, PI)
	var target_rotation := Vector3(_base_x_rotation, target_y, 0.0)
	_door_key_tween = create_tween()
	_door_key_tween.tween_property(camera_pivot, "rotation", target_rotation, door_key_look_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _door_key_tween.finished
	_visual_pivot_rotation = target_rotation
	_settle_step_index = roundi((target_y - _settle_origin_y) / deg_to_rad(rotation_step_degrees))
	_settle_target_y = _settle_origin_y + deg_to_rad(rotation_step_degrees) * _settle_step_index
	_active_side = posmod(_settle_step_index, SIDE_COUNT)
	# Grant access only after the player is looking, so the opening is visible.
	if CollectionManager.use_access_key(card_id):
		target_door.set_locked(false)
		target_door.set_travel_open(true)
		_door_key_tween = create_tween()
		_door_key_tween.tween_interval(target_door.travel_duration + 0.35)
		await _door_key_tween.finished
	else:
		_door_key_view_active = false
		_key_reveal_door = null
		_snap_camera_pivot_to_cardinal_target()
	_door_key_tween = null
	_room_transition_active = false
	collection.finish_slot_room_key_request()
	pause_menu.set_cinematic_locked(false)
	_update_labels()
	_update_active_scene_interaction()
	_update_screen_camera_focus_context()
	_update_room_door_interaction()


func _prepare_hub_return_facing(door: HospitalDoor) -> void:
	# Face from the entrance toward the hub turning center, snapped to its
	# cardinal sides: basement -> pack shop, graveyard -> table.
	var parent_basis := (camera_pivot.get_parent() as Node3D).global_basis
	var inward := parent_basis.inverse() * (_hub_return_pivot_transform.origin - door.global_position)
	var heading := atan2(-inward.x, -inward.z)
	var step := deg_to_rad(rotation_step_degrees)
	var target_index := roundi((heading - _hub_settle_origin_y) / step)
	target_index += roundi(float(_hub_return_step_index - target_index) / float(SIDE_COUNT)) * SIDE_COUNT
	_hub_return_step_index = target_index
	_hub_return_active_side = posmod(target_index, SIDE_COUNT)
	_hub_return_pivot_transform.basis = parent_basis * Basis.from_euler(
		Vector3(_base_x_rotation, _hub_settle_origin_y + step * float(target_index), 0.0)
	)


func _on_room_door_activated(door: HospitalDoor) -> void:
	if not _can_travel_between_rooms():
		return
	var source_door := door
	var destination_door: HospitalDoor
	var destination_anchor: Marker3D
	var destination_room := 0
	var entering_room := _active_room == 0
	if entering_room:
		if door == hub_door:
			if not CollectionManager.is_slot_room_unlocked():
				return
			destination_room = 1
			destination_door = return_door
			destination_anchor = room_camera_anchor
		else:
			for area in progression_areas:
				if area.door == door and connected_rooms.has(area.room_index) and CollectionManager.has_area_access(area.area_id):
					destination_room = area.room_index
					var room := connected_rooms[destination_room] as Node3D
					destination_door = room.get_node("ReturnDoor") as HospitalDoor
					destination_anchor = room.get_node("CameraAnchor") as Marker3D
					break
			if destination_room == 0:
				return
	else:
		if _active_room == 1:
			if door != return_door:
				return
			destination_door = hub_door
		else:
			if not connected_rooms.has(_active_room) or door != connected_rooms[_active_room].get_node("ReturnDoor"):
				return
			for area in progression_areas:
				if area.room_index == _active_room:
					destination_door = area.door
					break
			if destination_door == null:
				return
	var source_room := _active_room
	_transition_room_music(destination_room != 0)
	_transition_room_ambience(destination_room)
	var visible_camera_pose := main_camera.global_transform
	var visible_camera_fov := main_camera.fov
	if entering_room:
		_hub_return_pivot_transform = camera_pivot.global_transform
		if _door_key_view_active:
			_hub_return_pivot_transform.basis = Basis.from_euler(Vector3(_base_x_rotation, _settle_target_y, 0.0))
		_hub_return_step_index = _settle_step_index
		_hub_return_active_side = _active_side
	else:
		_prepare_hub_return_facing(destination_door)
	_door_key_view_active = false
	if is_instance_valid(_key_reveal_door) and _key_reveal_door != source_door:
		_key_reveal_door.set_travel_open(false)
	_key_reveal_door = null

	_room_transition_active = true
	_pending_direction = 0
	# Keep the hub visible through the doorway during the return flight.
	scene_pivot.show()
	# The camera rig owns the entire flight. Cancel the two existing camera
	# controllers, then preserve the visible pose while neutralizing mouse tilt.
	screen_camera_focus.set_context(_active_side, false)
	screen_camera_focus.restore_immediately()
	_claim_shared_camera_for_hub_rotation(false)
	camera_tilt.rotation = Vector3.ZERO
	main_camera.transform = _hub_camera_base_transform
	main_camera.fov = visible_camera_fov
	var camera_to_pivot := _hub_camera_base_transform.affine_inverse()
	camera_pivot.global_transform = visible_camera_pose * camera_to_pivot
	pause_menu.set_cinematic_locked(true)
	_update_active_scene_interaction()
	_update_room_door_interaction()
	source_door.set_travel_open(true)
	destination_door.set_return_passage_open(not entering_room)
	destination_door.set_travel_open(true)

	var destination_pivot := destination_anchor.global_transform if entering_room else _hub_return_pivot_transform
	# Room instances may be scaled; the shared camera always keeps its lens
	# offset and unit scale, just like in the original slot room.
	destination_pivot.basis = destination_pivot.basis.orthonormalized()
	var destination_camera := destination_pivot * _hub_camera_base_transform
	var travel_direction := (destination_door.global_position - source_door.global_position).normalized()
	var through_basis := Basis.looking_at(travel_direction, Vector3.UP)
	var source_eye := source_door.global_position
	source_eye.y = lerpf(visible_camera_pose.origin.y, destination_camera.origin.y, 0.5)
	var destination_eye := destination_door.global_position
	destination_eye.y = source_eye.y
	# Approach the opening before crossing either threshold. The last leg
	# settles at the room's normal turning center, with the same camera lens.
	var camera_poses: Array[Transform3D] = [
		visible_camera_pose,
		Transform3D(through_basis, source_eye - travel_direction * 1.6),
		Transform3D(through_basis, source_eye + travel_direction * 0.35),
		Transform3D(through_basis, destination_eye + travel_direction * 1.6),
		destination_camera,
	]
	if (destination_room if entering_room else _active_room) != 1:
		# Each threshold retains its own floor height. The basement's middle
		# leg follows the stairs, while both doors are crossed horizontally.
		travel_direction.y = 0.0
		travel_direction = travel_direction.normalized()
		through_basis = Basis.looking_at(travel_direction, Vector3.UP)
		source_eye.y = visible_camera_pose.origin.y
		destination_eye.y = destination_camera.origin.y
		var corridor_start := source_eye + travel_direction * 0.8
		var corridor_end := destination_eye - travel_direction * 0.8
		var corridor_basis := Basis.looking_at(corridor_end - corridor_start, Vector3.UP)
		camera_poses = [
			visible_camera_pose,
			Transform3D(through_basis, source_eye - travel_direction * 1.6),
			Transform3D(corridor_basis, corridor_start),
			Transform3D(corridor_basis, corridor_end),
			Transform3D(through_basis, destination_eye + travel_direction * 1.6),
			destination_camera,
		]
	var total_distance := 0.0
	for index in range(1, camera_poses.size()):
		total_distance += camera_poses[index - 1].origin.distance_to(camera_poses[index].origin)
	var walking_duration := 0.0
	_room_travel_tween = create_tween()
	for index in range(1, camera_poses.size()):
		var start_pose := camera_poses[index - 1] * camera_to_pivot
		var end_pose := camera_poses[index] * camera_to_pivot
		var distance := camera_poses[index - 1].origin.distance_to(camera_poses[index].origin)
		var duration := maxf(room_travel_duration * distance / maxf(total_distance, 0.001), 0.01)
		walking_duration += duration
		var leg := _room_travel_tween.tween_method(
			_apply_room_travel_pose.bind(start_pose, end_pose), 0.0, 1.0, duration
		)
		if index == 1:
			leg.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_room_travel_tween.parallel().tween_property(
				main_camera, "fov", _hub_camera_base_fov, duration
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		elif index == camera_poses.size() - 1:
			leg.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_start_walking_sequence(walking_duration)
	await _room_travel_tween.finished
	_stop_walking_sequence()
	_room_travel_tween = null
	camera_pivot.global_transform = destination_pivot
	_active_room = destination_room
	if source_room == 3 and destination_room != 3:
		GameCurrency.mark_basement_cat_left()
	if _room_music_tween != null:
		_room_music_tween.kill()
		_room_music_tween = null
	_apply_room_music_mix(1.0 if _active_room != 0 else 0.0)
	_finish_room_ambience(_active_room)
	scene_pivot.visible = _active_room != 1
	_settle_origin_y = camera_pivot.rotation.y if entering_room else _hub_settle_origin_y
	_settle_step_index = 0 if entering_room else _hub_return_step_index
	_active_side = 0 if entering_room else _hub_return_active_side
	_snap_camera_pivot_to_cardinal_target()
	source_door.set_travel_open(false)
	destination_door.set_travel_open(false)
	destination_door.set_return_passage_open(false)
	if destination_room == 0:
		if CollectionManager.claim_crucifix_return_dialogue():
			await _play_crucifix_return_dialogue()
		if CollectionManager.claim_holy_water_return_dialogue():
			await _play_holy_water_return_dialogue()
	_room_transition_active = false
	pause_menu.set_cinematic_locked(false)
	_update_labels()
	_update_active_scene_interaction()
	_update_screen_camera_focus_context()
	_update_room_door_interaction()
	room_changed.emit(_active_room)


func _play_holy_water_return_dialogue() -> void:
	await _play_story_item_return_dialogue(preload("res://scripts/main/SatanHolyWaterDialogue.gd"), "SatanHolyWaterDialogue")


func _play_crucifix_return_dialogue() -> void:
	await _play_story_item_return_dialogue(preload("res://scripts/main/SatanCrucifixDialogue.gd"), "SatanCrucifixDialogue")


func _play_story_item_return_dialogue(dialogue_script: Script, dialogue_name: String) -> void:
	var table := scene_pivot.get_node("GameTable") as GameTable
	var music_was_paused := music.stream_paused
	music.stream_paused = true
	# Return to the inward-facing arrival view after speaking with Satan.
	var return_step_index := _settle_step_index
	var return_pose := camera_pivot.global_transform
	var saved_fov := main_camera.fov
	var eye := main_camera.global_position
	var target := table.dealer_satan.global_position + Vector3.UP * table.dealer_satan.pixel_size * 6.0 * table.dealer_satan.global_basis.get_scale().y
	var face_direction := (target - eye).normalized()
	var approach_distance := minf(0.45, eye.distance_to(target) * 0.08)
	var focused_camera := Transform3D(Basis.looking_at(face_direction, Vector3.UP), eye + face_direction * approach_distance)
	var focused_pivot := focused_camera * main_camera.transform.affine_inverse()
	var swing := create_tween().set_parallel(true)
	swing.tween_property(camera_pivot, "global_transform", focused_pivot, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing.tween_property(main_camera, "fov", saved_fov * 0.88, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await swing.finished
	var dialogue := dialogue_script.new() as AngelDialogue
	dialogue.name = dialogue_name
	dialogue.actor = table.dealer_satan
	dialogue.camera = main_camera
	dialogue.connect("laughing_changed", table._set_satan_laughing)
	add_child(dialogue)
	dialogue.interaction_enabled = true
	if dialogue.open_dialog():
		await dialogue.modal_changed
	dialogue.queue_free()
	swing = create_tween().set_parallel(true)
	swing.tween_property(camera_pivot, "global_transform", return_pose, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing.tween_property(main_camera, "fov", saved_fov, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await swing.finished
	camera_pivot.global_transform = return_pose
	_settle_origin_y = _hub_settle_origin_y
	_settle_step_index = return_step_index
	_active_side = posmod(return_step_index, SIDE_COUNT)
	_snap_camera_pivot_to_cardinal_target()
	main_camera.fov = saved_fov
	music.stream_paused = music_was_paused
	_cinematic_input_block_frame = Engine.get_process_frames() + 1


func _apply_room_travel_pose(weight: float, start: Transform3D, target: Transform3D) -> void:
	camera_pivot.global_transform = start.interpolate_with(target, weight)
	if not _walking_steps_active or _room_travel_tween == null:
		return
	# One continuous rhythm across every doorway/stair leg. Always compose
	# from the clean lens pose so neither bobbing nor pitch can accumulate.
	var elapsed := _room_travel_tween.get_total_elapsed_time()
	var fade := minf(walking_fade_duration, _walking_duration * 0.5)
	var envelope := smoothstep(0.0, fade, elapsed) * smoothstep(0.0, fade, _walking_duration - elapsed)
	var phase := elapsed * TAU / walking_step_interval
	var pose := _walking_camera_base_transform
	pose.origin.y += sin(phase) * walking_bob_height * envelope
	pose.basis = pose.basis * Basis(Vector3.RIGHT, sin(phase - PI * 0.35) * deg_to_rad(walking_pitch_degrees) * envelope)
	main_camera.transform = pose


func _start_walking_sequence(duration: float) -> void:
	_walking_steps_active = true
	_walking_duration = duration
	_walking_camera_base_transform = main_camera.transform
	_step_countdown = 0.12
	_step_previous_position = camera_pivot.global_position


func _stop_walking_sequence() -> void:
	_walking_steps_active = false
	main_camera.transform = _walking_camera_base_transform


func _update_walking_steps(delta: float) -> void:
	if not _walking_steps_active:
		return
	# Footsteps follow the route, never the cosmetic lens movement itself.
	var position_now := camera_pivot.global_position
	var moving := position_now.distance_squared_to(_step_previous_position) > 0.000001
	_step_previous_position = position_now
	if not moving:
		return
	_step_countdown -= delta
	if _step_countdown > 0.0:
		return
	if not is_instance_valid(_step_sound):
		_step_random.randomize()
		_step_sound = AudioStreamPlayer.new()
		_step_sound.name = "WalkingSteps"
		_step_sound.stream = STEP_SOUND
		_step_sound.bus = &"SFX"
		_step_sound.max_polyphony = 3
		add_child(_step_sound)
	# About one semitone either side keeps the same footstep believable.
	# Use separate cosmetic randomness so walking never changes card rolls.
	_step_sound.pitch_scale = _step_random.randf_range(0.94, 1.06)
	_step_sound.play()
	_step_countdown = walking_step_interval * _step_random.randf_range(0.92, 1.08)


func _setup_room_ambience() -> void:
	_room_ambience_volume_db = atmo.volume_db
	_room_ambience_players[0] = atmo
	for room_index in ROOM_AMBIENCE:
		var player := AudioStreamPlayer.new()
		player.name = "GraveyardAtmo" if room_index == 2 else "BasementAtmo"
		var stream := ROOM_AMBIENCE[room_index].duplicate() as AudioStreamMP3
		stream.loop = true
		player.stream = stream
		player.bus = atmo.bus
		player.volume_db = -80.0
		add_child(player)
		_room_ambience_players[room_index] = player
	_finish_room_ambience(_active_room)


func _transition_room_ambience(destination_room: int) -> void:
	if _room_ambience_tween != null:
		_room_ambience_tween.kill()
	var target_room := destination_room if _room_ambience_players.has(destination_room) else 0
	_room_ambience_tween = create_tween().set_parallel(true)
	_room_ambience_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for room_index in _room_ambience_players:
		var player := _room_ambience_players[room_index] as AudioStreamPlayer
		var active: bool = room_index == target_room
		if active and not player.playing:
			player.play()
		# Fade amplitudes so the ambience remains audible through the passage.
		_room_ambience_tween.tween_method(
			_apply_room_ambience_gain.bind(player), db_to_linear(player.volume_db),
			db_to_linear(_room_ambience_volume_db) if active else 0.0,
			maxf(room_travel_duration, 0.01)
		)


func _apply_room_ambience_gain(gain: float, player: AudioStreamPlayer) -> void:
	player.volume_db = linear_to_db(maxf(gain, 0.0001))


func _finish_room_ambience(room: int) -> void:
	if _room_ambience_tween != null:
		_room_ambience_tween.kill()
		_room_ambience_tween = null
	var target_room := room if _room_ambience_players.has(room) else 0
	for room_index in _room_ambience_players:
		var player := _room_ambience_players[room_index] as AudioStreamPlayer
		if room_index == target_room:
			player.volume_db = _room_ambience_volume_db
			if not player.playing:
				player.play()
		else:
			player.stop()
			player.volume_db = -80.0


func _setup_room_music() -> void:
	if music == null:
		return
	_room_music_source_bus = music.bus
	# This scene owns its filter. Music settings and cinematic player fades
	# remain independent, and the main menu cannot inherit a muffled bus.
	_room_music_bus = StringName("RoomMusic_%d" % get_instance_id())
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, _room_music_bus)
	AudioServer.set_bus_send(bus_index, _room_music_source_bus)
	_room_music_filter = AudioEffectLowPassFilter.new()
	_room_music_filter.db = AudioEffectFilter.FILTER_24DB
	_room_music_filter.resonance = 0.5
	AudioServer.add_bus_effect(bus_index, _room_music_filter)
	music.bus = _room_music_bus
	_apply_room_music_mix(1.0 if _active_room != 0 else 0.0)


func _transition_room_music(outside_hub: bool) -> void:
	if _room_music_tween != null:
		_room_music_tween.kill()
	_room_music_tween = create_tween()
	_room_music_tween.tween_method(
		_apply_room_music_mix, _room_music_mix,
		1.0 if outside_hub else 0.0, maxf(room_travel_duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_room_music_mix(weight: float) -> void:
	_room_music_mix = clampf(weight, 0.0, 1.0)
	var bus_index := AudioServer.get_bus_index(_room_music_bus)
	if bus_index < 0 or _room_music_filter == null:
		return
	AudioServer.set_bus_volume_db(bus_index, slot_room_music_attenuation_db * _room_music_mix)
	# A logarithmic sweep makes the perceived treble change gradual.
	_room_music_filter.cutoff_hz = exp(lerpf(log(20000.0), log(slot_room_music_cutoff_hz), _room_music_mix))
	AudioServer.set_bus_effect_enabled(bus_index, 0, _room_music_mix > 0.0)


func _cleanup_room_music() -> void:
	if _room_music_tween != null:
		_room_music_tween.kill()
		_room_music_tween = null
	if is_instance_valid(music):
		music.bus = _room_music_source_bus
	var bus_index := AudioServer.get_bus_index(_room_music_bus)
	if bus_index >= 0:
		AudioServer.remove_bus(bus_index)
	_room_music_bus = &""
	_room_music_filter = null


func _update_labels() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if _is_bed_busy():
		side_label.text = ""
		hint_label.text = ""
		return
	if _active_room == 2 or _active_room == 3:
		side_label.text = ""
		hint_label.text = ""
		return
	if _active_room == 1:
		if is_instance_valid(fusion_workbench) and _active_side == fusion_workbench.view_side:
			side_label.text = Localization.text("Kartenschmiede")
			hint_label.text = ""
			return
		if is_instance_valid(upgrade_collection) and _active_side == upgrade_collection.view_side:
			side_label.text = Localization.text("Upgrade-Sammlung")
			hint_label.text = Localization.text("Esc: Detail schließen" if _is_upgrade_collection_detail_open() else "Karte anklicken: Details ansehen")
			return
		side_label.text = Localization.text("Soul Slots")
		hint_label.text = Localization.text("+/− Einsatz wählen  |  BET bestätigen  |  SPIN spielen")
		return
	side_label.text = Localization.text(SIDE_NAMES[_active_side])
	hint_label.text = ""


func _disable_embedded_scene_controls() -> void:
	for child in scene_pivot.get_children():
		_disable_embedded_scene_controls_recursive(child)


func _update_active_scene_interaction() -> void:
	var interactive_roots: Array[Array] = [
		["GameTable"],
		["PackShopMachine"],
		["Collection"],
		["UpgradeMachine"],
	]

	for side_index in range(interactive_roots.size()):
		var active := not is_instance_valid(_playtime_encounter) and not _greeting_active and not _jumpscare_active and _active_room == 0 and not _room_transition_active and not _door_key_view_active and not _is_journal_active() and not _is_progression_area_open() and side_index == _active_side
		if side_index == 3:
			active = active and GameCurrency.is_npc_rescued("angel")
		for root_name in interactive_roots[side_index]:
			var root := scene_pivot.get_node_or_null(str(root_name))
			if root != null:
				_set_scene_interaction_enabled(root, active)


func _setup_screen_camera_focus() -> void:
	if screen_camera_focus == null:
		return
	secret_wall_input.camera = main_camera
	secret_wall_input.focus_controller = screen_camera_focus
	screen_camera_focus.register_screen(secret_wall_input.focus_area, secret_wall_input.VIEW_SIDE, 1)
	var table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if is_instance_valid(table) and is_instance_valid(table._offline_board):
		table._offline_board.set_focus_controller(screen_camera_focus)

	var pack_screen := scene_pivot.get_node_or_null("PackShopMachine/ScreenArea") as Area3D
	var upgrade_screen := scene_pivot.get_node_or_null("UpgradeMachine/ScreenArea") as Area3D

	if pack_screen != null:
		screen_camera_focus.register_screen(pack_screen, 1, 0)
	else:
		push_warning("ScreenCameraFocus: PackShop-ScreenArea fehlt.")

	if upgrade_screen != null:
		screen_camera_focus.register_screen(upgrade_screen, 3, 0)
	else:
		push_warning("ScreenCameraFocus: Upgrade-ScreenArea fehlt.")
	if is_instance_valid(upgrade_collection) and is_instance_valid(upgrade_collection.focus_area):
		screen_camera_focus.register_screen(upgrade_collection.focus_area, upgrade_collection.view_side, 1)
	if is_instance_valid(fusion_workbench) and is_instance_valid(fusion_workbench.focus_area):
		screen_camera_focus.register_screen(fusion_workbench.focus_area, fusion_workbench.view_side, 1)
	if is_instance_valid(graveyard_jester) and is_instance_valid(graveyard_jester.focus_area):
		screen_camera_focus.register_screen(graveyard_jester.focus_area, graveyard_jester.view_side, 2)
	if is_instance_valid(black_market_board) and is_instance_valid(black_market_board.focus_area):
		screen_camera_focus.register_screen(black_market_board.focus_area, black_market_board.view_side, 4)
	for boiler in basement_boilers:
		screen_camera_focus.register_screen(boiler.focus_area, boiler.view_side, 3)
	screen_camera_focus.register_screen(basement_pump_control.focus_area, basement_pump_control.view_side, 3)


func _update_screen_camera_focus_context() -> void:
	if screen_camera_focus == null:
		return
	if _greeting_active or _jumpscare_active:
		screen_camera_focus.set_context(_active_side, false)
		return

	var hub_screen_active := _active_room == 0 and (_active_side == 1 or (_active_side == 3 and GameCurrency.is_npc_rescued("angel")))
	var table := scene_pivot.get_node_or_null("GameTable") as GameTable
	var board_active := is_instance_valid(table) and table.is_offline_board_open() and _active_room == 0 and _active_side == 0
	var wall_screen_active := (
		_active_room == 1 and is_instance_valid(upgrade_collection)
		and _active_side == upgrade_collection.view_side
	)
	var forge_screen_active := (
		_active_room == 1 and is_instance_valid(fusion_workbench)
		and _active_side == fusion_workbench.view_side
	)
	var secret_input_active: bool = _active_room == 1 and _active_side == secret_wall_input.VIEW_SIDE
	var focus_allowed := (
		(board_active or hub_screen_active or wall_screen_active or forge_screen_active or secret_input_active or _jester_context_is_safe() or _black_market_context_is_safe() or _dealer_context_is_safe() or _boiler_context_is_safe() or _pump_control_context_is_safe())
		and not _is_bed_busy()
		and not _is_progression_area_open()
		and not _room_transition_active
		and not _door_key_view_active
		and not access_key_tray.is_expanded()
		and not _loss_cinematic_active
		and not pause_menu.visible
		and _phase == Phase.IDLE
		and (board_active or not _is_table_match_active())
		and not _pack_opening_blocks_screen_focus
		and not _is_journal_active()
	)
	screen_camera_focus.set_hover_suspended(board_active or secret_wall_input.is_busy() or _is_upgrade_collection_detail_open() or _is_fusion_workbench_busy() or _is_jester_busy() or _is_angel_busy() or _is_dealer_busy() or _is_boiler_dragging() or (is_instance_valid(turn_arrows) and turn_arrows.is_pointer_over_arrow()))
	screen_camera_focus.set_context(_active_side, focus_allowed, _active_room)
	if board_active and focus_allowed and not screen_camera_focus.is_focused():
		screen_camera_focus.focus_screen(table._offline_board.focus_area)


func _connect_pack_opening_focus_state() -> void:
	var pack_opening_screen := scene_pivot.get_node_or_null("PackShopMachine/PackOpeningScreen")
	if pack_opening_screen == null:
		push_warning("ScreenCameraFocus: PackOpeningScreen fehlt.")
		return

	if pack_opening_screen.has_signal("pack_opening_started"):
		pack_opening_screen.pack_opening_started.connect(_on_pack_opening_started)
	if pack_opening_screen.has_signal("pack_ready_for_next_purchase"):
		pack_opening_screen.pack_ready_for_next_purchase.connect(_on_pack_opening_finished)


func _on_pack_opening_started() -> void:
	_interrupt_journal()
	_pack_opening_blocks_screen_focus = true
	_update_screen_camera_focus_context()


func _on_pack_opening_finished() -> void:
	_pack_opening_blocks_screen_focus = false
	_update_screen_camera_focus_context()


func _connect_loss_exit_cinematic() -> void:
	var game_table := scene_pivot.get_node_or_null("GameTable") as GameTable
	if game_table == null:
		push_warning("Loss-Cinematic: GameTable fehlt.")
		return

	if not game_table.loss_exit_started.is_connected(_on_loss_exit_started):
		game_table.loss_exit_started.connect(_on_loss_exit_started)
	if not game_table.loss_shot_fired.is_connected(_on_loss_shot_fired):
		game_table.loss_shot_fired.connect(_on_loss_shot_fired)
	if not game_table.win_shot_fired.is_connected(_on_win_shot_fired):
		game_table.win_shot_fired.connect(_on_win_shot_fired)
	if not game_table.loss_reveal_started.is_connected(_on_loss_reveal_started):
		game_table.loss_reveal_started.connect(_on_loss_reveal_started)
	if not game_table.player_wakeup_started.is_connected(_on_player_wakeup_started):
		game_table.player_wakeup_started.connect(_on_player_wakeup_started)
	if not game_table.loss_exit_skipped.is_connected(_on_loss_exit_skipped):
		game_table.loss_exit_skipped.connect(_on_loss_exit_skipped)
	if not game_table.loss_exit_finished.is_connected(_on_loss_exit_finished):
		game_table.loss_exit_finished.connect(_on_loss_exit_finished)


func _on_loss_exit_started(music_fade_duration: float) -> void:
	_interrupt_journal()
	_loss_cinematic_active = true
	# The visor receives input before Main, so close it before the next event.
	level_progress.set_enabled(false)
	_pending_direction = 0
	if screen_camera_focus != null:
		screen_camera_focus.set_context(_active_side, false)
	if pause_menu != null:
		pause_menu.set_cinematic_locked(true)
	if main_camera != null:
		# Mouse-Tilt neutralisieren, ohne die sichtbare Kamerapose beim Klick
		# springen zu lassen. So startet und endet die Cinematic auf einer
		# stabilen lokalen Basis.
		var preserved_camera_transform := main_camera.global_transform
		camera_tilt.rotation = Vector3.ZERO
		main_camera.global_transform = preserved_camera_transform

	if music == null:
		return
	if _loss_music_tween != null:
		_loss_music_tween.kill()

	_loss_music_restore_db = music.volume_db
	_loss_music_restore_pending = true
	_loss_music_tween = create_tween()
	_loss_music_tween.tween_property(
		music,
		"volume_db",
		-80.0,
		maxf(music_fade_duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_win_shot_fired() -> void:
	if is_instance_valid(imprisoned_npcs):
		imprisoned_npcs.depart_on_shot()


func _on_loss_shot_fired() -> void:
	if music == null:
		return
	if _loss_music_tween != null:
		_loss_music_tween.kill()
		_loss_music_tween = null
	music.volume_db = -80.0


func _on_player_wakeup_started() -> void:
	_start_wakeup_blur(wakeup_blur_duration * 0.5)
	blood_overlay.play()


func _on_loss_reveal_started(duration: float) -> void:
	if music == null or not _loss_music_restore_pending:
		return
	if _loss_music_tween != null:
		_loss_music_tween.kill()

	music.volume_db = -80.0
	_loss_music_tween = create_tween()
	_loss_music_tween.tween_property(
		music,
		"volume_db",
		_loss_music_restore_db,
		maxf(duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_loss_exit_skipped() -> void:
	imprisoned_npcs.finish_victory()
	blood_overlay.clear()
	# A skip key can also be a turn/journal/pause key. Keep its input frame local
	# to the cinematic, including actions polled by _process instead of _input.
	_cinematic_input_block_frame = Engine.get_process_frames() + 1
	_pending_direction = 0
	if _wakeup_blur_tween != null:
		_wakeup_blur_tween.kill()
		_wakeup_blur_tween = null
	if _wakeup_blur_material != null:
		_wakeup_blur_material.set_shader_parameter("blur_strength", WAKEUP_BLUR_END)


func _on_loss_exit_finished() -> void:
	DIAGNOSTICS.record("main.cinematic.restore_begin", {"in_tree": is_inside_tree()})
	if _loss_music_tween != null:
		_loss_music_tween.kill()
		_loss_music_tween = null
	if music != null and _loss_music_restore_pending:
		music.volume_db = _loss_music_restore_db

	_loss_music_restore_pending = false
	_loss_cinematic_active = false
	imprisoned_npcs.finish_victory()
	if pause_menu != null:
		pause_menu.set_cinematic_locked(false)
	_update_screen_camera_focus_context()
	DIAGNOSTICS.record("main.cinematic.restore_finished", {"in_tree": is_inside_tree()})


func _set_scene_interaction_enabled(node: Node, enabled: bool) -> void:
	if node is Area3D:
		var area := node as Area3D
		if area.get_meta("keep_input_ray_pickable_disabled", false):
			area.input_ray_pickable = false
		else:
			area.input_ray_pickable = enabled
	if node is Control:
		var control := node as Control
		if not control.has_meta("original_mouse_filter"):
			control.set_meta("original_mouse_filter", control.mouse_filter)
		control.mouse_filter = int(control.get_meta("original_mouse_filter")) if enabled else Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_scene_interaction_enabled(child, enabled)


func _disable_embedded_scene_controls_recursive(node: Node) -> void:
	# Only take over cameras/listeners/environment nodes that share Main's
	# viewport. Preview renderers live in their own SubViewports and need their
	# cameras to remain current; disabling them leaves a valid but black texture.
	var shares_main_viewport := node.get_viewport() == get_viewport()
	if node is Camera3D and shares_main_viewport:
		(node as Camera3D).current = false
	if node is AudioListener3D and shares_main_viewport:
		(node as AudioListener3D).current = false
	if node is WorldEnvironment and shares_main_viewport:
		(node as WorldEnvironment).environment = null
	if node is MenuNavigation:
		(node as MenuNavigation).visible = false
		(node as MenuNavigation).process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_embedded_scene_controls_recursive(child)

func _is_table_match_active() -> bool:
	if _active_room != 0 or _active_side != 0:
		return false

	var game_table := scene_pivot.get_node_or_null("GameTable")
	if game_table == null:
		return false

	if not game_table.has_method("is_match_active"):
		return false

	return game_table.is_match_active()
	

func _connect_pack_collection_refresh() -> void:
	var pack_opening_screen := scene_pivot.get_node_or_null("PackShopMachine/PackOpeningScreen")
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

func _refresh_collection_screen() -> void:
	var collection_screen := scene_pivot.get_node_or_null("Collection")

	if collection_screen == null:
		return

	if collection_screen.has_method("refresh_collection"):
		collection_screen.refresh_collection()
