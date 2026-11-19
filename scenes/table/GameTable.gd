extends Node3D
class_name GameTable

signal loss_exit_started(music_fade_duration: float)
signal loss_shot_fired
signal win_shot_fired
signal loss_reveal_started(duration: float)
signal player_wakeup_started
signal loss_exit_finished
signal loss_exit_skipped
signal journal_interrupted

const HAND_SIZE: int = 5
const OFFLINE_RULES := preload("res://scripts/match/OfflineMatchRules.gd")
const OFFLINE_BOARD := preload("res://scripts/table/OfflineModeBoard.gd")
const EGG_HATCH_CHANCE := 0.25
const CHICK_GROWTH_TURNS := 10 # Five full rounds: one turn from each side.
const DIAGNOSTICS := preload("res://scripts/autoload/SessionDiagnostics.gd")
const EVENT_DECK_RULES := preload("res://scripts/events/EventDeck.gd")
const EVENT_HAND_UI := preload("res://scripts/ui/EventHandUI.gd")
const EVENT_PISS_SCENE := preload("res://scenes/effects/Piss.tscn")
const RANDOM_DAMAGE_COIN_SCENE := preload("res://scenes/effects/RandomDamageCoin.tscn")
const POISON_SYRINGE_SCENE := preload("res://scenes/effects/PoisonSyringe.tscn")
const CLEAVE_BRICK_SCENE := preload("res://scenes/effects/CleaveBrick.tscn")
const MAX_CLEAVE_BRICKS := 24
const DAMAGE_NUMBER_SCRIPT := preload("res://scripts/ui/DamageNumber3D.gd")
const MAX_DAMAGE_NUMBERS := 64
const SATAN_LAUGH_TEXTURE := preload("res://assets/characters/satan/satanLaught.png")
const SATAN_HOVER_TEXTURE := preload("res://assets/characters/satan/satanHover.png")
const SATAN_DEATH_TEXTURE := preload("res://assets/characters/satan/satanDeath.png")
const SATAN_PANIC_TEXTURE := preload("res://assets/characters/satan/satanPanic.png")
const SATAN_KILL_TEXTURE := preload("res://assets/characters/satan/satanKill.png")
const SATAN_PANIC_FPS := 8.0
const SATAN_KILL_FPS := 10.0
const SATAN_VOICE_CHAT_SCRIPT := preload("res://scripts/SatanVoiceChat.gd")
const SATAN_LAUGH_AUDIO_SCRIPT := preload("res://scripts/SatanLaughAudio.gd")
const THROW_MOTION := preload("res://scripts/table/TableThrowMotion.gd")
const SATAN_IDLE_FRAMES := 25
const SATAN_HOVER_FRAMES := 25
const SATAN_LAUGH_FRAMES := 2
const SATAN_DEATH_FRAMES := 2
const SATAN_IDLE_FPS := 15.0
const SATAN_HOVER_FPS := 15.0
const SATAN_LAUGH_FPS := 20.0
const SATAN_STREAM_LAUGH_FPS := 32.0
const SATAN_STREAM_LAUGH_PITCH_OFFSET := 7.0
const SATAN_DEATH_FPS := 20.0
const SATAN_HOVER_COLLISION_LAYER := 1 << 9
const ONLINE_VISUAL_SYNC_TIMEOUT_MSEC := 3000
const ONLINE_EXIT_REQUEST_TIMEOUT_MSEC := 5000
const ONLINE_EXIT_CINEMATIC_TIMEOUT_MSEC := 45000
const ONLINE_EXIT_FINALIZE_TIMEOUT_MSEC := 5000
const ONLINE_EXIT_CLIENT_WATCHDOG_MSEC := 20000

# Vertikaler Versatz zwischen zwei gestapelten Ruecken-Karten.
const STACK_LAYER_OFFSET: Vector3 = Vector3(0, 0.012, 0)
const SWITCH_EXCHANGE_DURATION := 0.60

@export var card_scene: PackedScene

@onready var player_slots_root: Node3D = $PlayerSlots
@onready var enemy_slots_root: Node3D = $EnemySlots
@onready var player_deck_marker: Marker3D = $PlayerDeck
@onready var enemy_deck_marker: Marker3D = $EnemyDeck
@onready var select_sfx: AudioStreamPlayer = $Audio/SelectSFX
@onready var damage_sfx: AudioStreamPlayer = $Audio/DamageSFX
@onready var kill_sfx: AudioStreamPlayer = $Audio/KillSFX
@onready var flash_sprite: Sprite3D = $dealer/flash
@onready var win_blood_sprite: Sprite3D = $blood
@onready var death_shot_sfx: AudioStreamPlayer = $Audio/DeathShotSFX
@onready var win_tinnitus_sfx: AudioStreamPlayer = $Audio/WinTinnitusSFX
@onready var win_shot_light: OmniLight3D = $WinShotLight
@onready var satan_motion_root: Node3D = $dealer/SatanMotionRoot
@onready var dealer_satan: Sprite3D = $dealer/SatanMotionRoot/satan
@onready var satan_hover_area: Area3D = $dealer/SatanMotionRoot/SatanHoverArea

@onready var dealer_gun: Sprite3D = $dealer/gun
@onready var pistol_start_marker: Marker3D = $dealer/PistolStart
@onready var pistol_end_marker: Marker3D = $dealer/PistolEnd
@onready var player_gun_mount: Control = $WinCinematicCanvas/PlayerGunMount
@onready var player_gun_back: TextureRect = $WinCinematicCanvas/PlayerGunMount/GunBack
@onready var player_muzzle_flash: TextureRect = (
	$WinCinematicCanvas/PlayerGunMount/MuzzleFlash
)

@export var pistol_raise_duration: float = 0.55
@export var pistol_aim_pause: float = 1.0

@export_group("Loss Exit Cinematic")
@export_range(0.1, 2.0, 0.05) var loss_player_view_return_duration := 0.55
@export_range(0.5, 8.0, 0.1) var loss_camera_approach_duration := 3.0
@export_range(0.5, 4.0, 0.05) var loss_camera_distance := 2.45
@export var loss_camera_focus_offset := Vector3(0.0, 0.12, 0.0)
@export_range(30.0, 70.0, 0.5) var loss_camera_fov := 55.0
@export_range(0.05, 0.6, 0.01) var loss_camera_return_duration := 0.18
@export_range(0.25, 5.0, 0.05) var loss_reveal_duration := 2.0

@export_group("Win Exit Cinematic")
@export_range(0.0, 30.0, 0.5) var win_blood_hold_duration := 8.0
@export_range(0.1, 20.0, 0.1) var win_blood_fade_duration := 6.0
@export_range(0.01, 0.2, 0.005) var win_shot_shake_strength := 0.08
@export_range(0.1, 0.5, 0.01) var win_shot_shake_duration := 0.22
@export_range(100.0, 800.0, 10.0) var win_gun_hidden_offset := 420.0
@export_range(0.1, 1.5, 0.05) var win_gun_raise_duration := 0.55
@export_range(0.05, 0.4, 0.01) var win_gun_recoil_duration := 0.08
@export_range(0.1, 1.5, 0.05) var win_gun_lower_duration := 0.45
@export_range(0.5, 8.0, 0.1) var win_satan_knockback_distance := 3.2
@export_range(0.0, 3.0, 0.05) var win_satan_knockback_lift := 0.55
@export_range(0.1, 2.0, 0.05) var win_satan_knockback_duration := 0.6
@export_range(0.1, 5.0, 0.05) var win_satan_absent_duration := 1.75
@export_range(0.5, 5.0, 0.1) var win_satan_rise_depth := 2.2
@export_range(0.2, 3.0, 0.05) var win_satan_return_duration := 1.15
@export_range(0.0, 2.0, 0.05) var win_satan_return_hold := 0.4

@export_group("Timing")
@export var enemy_turn_delay: float = 0.9
@export var draw_animation_duration: float = 0.35
@export_range(0.0, 1.0, 0.01) var replacement_draw_delay: float = 0.18

@export_group("Effects")
@export var blood_burst_scene: PackedScene
@export var blood_decal_scene: PackedScene
@export var heal_burst_scene: PackedScene
@export var poison_burst_scene: PackedScene

@export var blood_spawn_offset := Vector3(0, 0.16, 0)
# Table-local offset above the tabletop, independent of card animation height.
@export var blood_decal_offset := Vector3(0, 0.012, 0)

@export_group("Card Death Animation")
@export_range(1.0, 12.0, 0.1) var death_throw_speed := THROW_MOTION.THROW_SPEED
@export_range(0.5, 8.0, 0.1) var death_upward_speed := THROW_MOTION.UPWARD_SPEED
@export_range(1.0, 25.0, 0.1) var death_gravity := THROW_MOTION.GRAVITY
@export_range(0.5, 5.0, 0.1) var death_flight_duration := THROW_MOTION.FLIGHT_DURATION
@export_range(0.05, 2.4, 0.05) var death_dissolve_duration: float = 0.4

@export_group("Effect VFX")
@export var poison_vfx_scene: PackedScene
@export var shield_vfx_scene: PackedScene
@export var overview_scene: PackedScene
@export var regeneration_vfx_scene: PackedScene
@export var lifesteal_vfx_scene: PackedScene
@export var stun_vfx_scene: PackedScene
@export var curse_vfx_scene: PackedScene
@export var thorns_vfx_scene: PackedScene
@export var last_stand_vfx_scene: PackedScene
@export var effect_vfx_offset := Vector3(0, 0.25, 0)

@export_group("Match Camera")
@export var match_camera_marker: Marker3D
@export var match_camera_use_export_rotation := true
@export var match_camera_rotation := Vector3(-68.0, 0.0, 0.0)
@export var match_camera_duration: float = 0.65

@export_group("Camera Shake")
@export var impact_shake_strength := 0.035
@export var impact_shake_duration := 0.14
@export var impact_shake_rot_strength := 0.9



@export_group("Card Inspect Camera")
@export var inspect_camera_offset := Vector3(0, 1.65, 0.55)
@export var inspect_camera_duration := 0.35
@export var table_camera: Camera3D

@export_group("Match Settings")
@export_range(5, 100, 1) var deck_size: int = 20

enum TableState {
	MENU,
	DIFFICULTY_SELECT,
	ONLINE_LOBBY,
	PLAYING,
	GAME_OVER,
	STORY_SELECT,
	TRAINING_SETUP
}

enum MatchOutcome {
	NONE,
	WIN,
	LOSS,
	DRAW
}

var _table_state: TableState = TableState.MENU
var _selected_difficulty := "normal"
# Freeze reward tuning when the match starts; menu choices are not match state.
var _match_reward_difficulty := "normal"
var _local_mode := "legacy"
var _story_level := 0
var _training_player: Array[Dictionary] = []
var _training_enemy: Array[Dictionary] = []
var _offline_menu: Control
var _offline_board: Node3D
var _training_hud: Node3D
var _training_damage_log: Label3D
var _training_hits: Array[String] = []

@onready var menu_root: Node3D = $MenuRoot
@onready var mode_buttons: Node3D = $MenuRoot/ModeButtons
@onready var difficulty_buttons: Node3D = $MenuRoot/DifficultyButtons
@onready var end_buttons: Node3D = $MenuRoot/EndButtons
@onready var matchmaking_screen: Control = $OnlineCanvas/MatchmakingScreen
@onready var match_hud: MatchHUD = $OnlineCanvas/MatchHUD

var _camera_base_transform: Transform3D
var _camera_base_fov := 58.0
var _inspected_card: Card3D = null
var _camera_tween: Tween = null

# Pro Slot-Index die jeweilige Karteninstanz (oder null, wenn leer).
var _player_slots: Array[Card3D] = [null, null, null, null, null]
var _enemy_slots: Array[Card3D] = [null, null, null, null, null]

# Verbleibende Kartendaten (Dictionaries aus CardDatabase/Collection),
# die noch nicht auf dem Tisch liegen. Wird beim Nachziehen verkleinert.
var _player_deck: Array[Dictionary] = []
var _enemy_deck: Array[Dictionary] = []
var _event_deck: Array[Dictionary] = []
var _event_discard: Array[Dictionary] = []
var _player_event_hand: Array[Dictionary] = []
var _enemy_event_hand: Array[Dictionary] = []
var _starting_events_dealt := false
var _event_played_this_turn := false
var _selected_event_uid := ""
var _rearrange_first_card: Card3D
var _event_notice := ""
var _event_notice_source := ""
var _event_notice_arguments: Array = []
var _event_hand_ui: Control
var _event_pass_button: Button
var _event_resolution_tween: Tween
var _event_replacement_tween: Tween
var _event_moving_cards: Array[Card3D] = []
var _last_played_event: Dictionary = {}
var _last_event_side := ""
var _event_play_sequence := 0
var _event_presented_sequence := 0
var _event_reveal_deadline_msec := 0
var _piss_hidden_turns := {"player": 0, "enemy": 0}
var _event_piss_stream: Node3D
var _event_switch_tween: Tween
var _event_switch_cards: Array[Card3D] = []

var _player_slot_markers: Array[Marker3D] = []
var _enemy_slot_markers: Array[Marker3D] = []

# "player" oder "enemy" — wer gerade am Zug ist.
var _current_turn: String = "player"
var _shake_tween: Tween = null

# Vom Spieler bereits ausgewaehlte eigene Karte fuer das aktuelle Duell
# (null, solange noch keine gewaehlt wurde).
var _selected_player_card: Card3D = null

var _game_over: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _death_visual_rng := RandomNumberGenerator.new()
var _egg_hatch_rng := RandomNumberGenerator.new()
var _damage_numbers: Array[Node3D] = []
var _damage_number_lanes: Dictionary = {}

# Sichtbare Ruecken-Karten pro Stapel (nur Optik, keine Spieldaten).
var _player_stack_visuals: Array[Card3D] = []
var _enemy_stack_visuals: Array[Card3D] = []
var _effect_overview: CardEffectOverviewUI = null
var _effect_overview_layer: CanvasLayer = null

var _last_match_outcome: MatchOutcome = MatchOutcome.NONE
var _loss_exit_running := false
var _exit_skip_allowed := false
var _exit_skip_requested := false
var _dealer_gun_tween: Tween
var _black_fade_tween: Tween
var _hearing_volume_tween: Tween
var _hearing_filter_tween: Tween
var _black_layer: CanvasLayer = null
var _black_rect: ColorRect = null
var _satan_idle_texture: Texture2D = null
var _satan_motion_base_transform := Transform3D.IDENTITY
var _satan_base_modulate := Color.WHITE
var _satan_base_visible := true
var _satan_motion_tween: Tween = null
var _player_gun_tween: Tween = null
var _win_blood_tween: Tween = null
var _win_shot_tween: Tween = null
var _satan_hovered := false
var _satan_is_laughing := false
var _satan_stream_laughing := false
var _satan_stream_laugh_pitch := 0.0
var _satan_laugh_audio: AudioStreamPlayer3D = null
var _satan_is_dying := false
var _satan_story_reaction := 0
var _satan_voice_chat: Node = null
var _hearing_recovery_active := false
var _hearing_master_bus_index := -1
var _hearing_master_restore_db := 0.0
var _hearing_lowpass: AudioEffectLowPassFilter = null
var _hearing_lowpass_restore_cutoff := 20000.0
var _hearing_effect_was_enabled := false

# Online matches are host-authoritative. "player"/"enemy" remain the local
# visual sides on every machine; snapshots are mirrored for the client.
var _online_mode := false
var _online_is_host := false
var _online_is_spectator := false
var _online_character_data: Dictionary = {}
var _online_second_character_data: Dictionary = {}
var _online_character_retired := false
var multiplayer_character_customizer: CharacterCustomizer
var _character_creation_pending := false
var _character_creation_paused_tree := false
var _match_reward_text := ""
var _match_reward_data: Dictionary = {}
var _match_reward_outcome_source := ""
var _match_status_message := ""
var _match_status_source := ""
var _match_status_arguments: Array = []
var _match_status_is_reward := false
var _spectator_leave_button: Button
var _online_action_in_progress := false
var _match_reward_granted := false
var _online_disconnect_reason := ""
var _online_turn_sequence := 0
# The host stores selection in canonical board coordinates. On the client,
# canonical "enemy" maps to the local player side and vice versa.
var _online_selected_side := ""
var _online_selected_slot := -1
var _online_attack_sequence := 0
var _online_blood_sequence := 0
var _online_state_sync_sequence := 0
var _online_last_received_attack_sequence := 0
var _online_last_received_blood_sequence := 0
var _online_client_attack_phases: Dictionary = {}
var _online_queued_blood_events: Dictionary = {}
var _online_queued_impact_events: Dictionary = {}
var _online_applied_impact_sequences: Dictionary = {}
var _online_client_attack_contexts: Dictionary = {}
var _online_client_presentation_depth := 0
var _online_queued_snapshot: Dictionary = {}
var _online_has_applied_snapshot := false
var _online_pending_release_sequence := -1
var _online_pending_attack_acks: Dictionary = {}
var _online_pending_blood_acks: Dictionary = {}
var _online_pending_state_acks: Dictionary = {}
var _online_queued_replacement_state_sync_sequence := 0
var _online_queued_replacement_state_turn_sequence := -1
# Exit sequence numbers restart in each match; deferred work also needs this
# monotonic lifetime so an old sequence 1 cannot close a new session's sequence 1.
var _online_session_generation := 0
var _online_exit_sequence := 0
var _online_active_exit_sequence := 0
var _online_exit_requested := false
var _online_exit_local_finished := false
var _online_exit_remote_finished := false
var _online_exit_finalize_acknowledged := false
var _online_exit_finalize_received := false
var _online_exit_coordinator_running := false
var _online_exit_finalizing := false
var _online_exit_deadline_msec := 0
var _online_exit_canonical_winner := ""

# Offline actions use their own lock so a second click cannot start another
# duel while the first attack animation or the AI turn is still running.
var _local_action_in_progress := false
var _journal_input_blocked := false
# Every board reset invalidates timers/coroutines that still belong to the
# previous local match.
var _match_generation := 0
var _random_damage_coins: Array[Node3D] = []
var _poison_syringes: Array[Node3D] = []
# This legacy array also owns healing injections for shared death/exit cleanup.
var _cleave_bricks: Array[RigidBody3D] = []
var _cleave_brick_surface: StaticBody3D
var _card_death_sequence := 0
# Flight cleanup can outlive the short replacement barrier; use
# _has_pending_card_replacements() when deciding whether play may continue.
var _pending_card_deaths: Array[Dictionary] = []
var _chick_turn_eligible: Dictionary = {}
var _chick_growth_tweens: Array[Tween] = []


func _ready() -> void:
	_rng.randomize()
	_death_visual_rng.randomize()
	_egg_hatch_rng.randomize()
	_satan_idle_texture = dealer_satan.texture if dealer_satan != null else null
	if dealer_satan != null:
		_satan_laugh_audio = SATAN_LAUGH_AUDIO_SCRIPT.new()
		_satan_laugh_audio.name = "LaughSound"
		dealer_satan.add_child(_satan_laugh_audio)
	if satan_motion_root != null:
		_satan_motion_base_transform = satan_motion_root.transform
	if dealer_satan != null:
		_satan_base_modulate = dealer_satan.modulate
		_satan_base_visible = dealer_satan.visible
	_setup_satan_voice_chat.call_deferred()

	if table_camera == null:
		table_camera = $Camera3D

	_camera_base_transform = table_camera.global_transform
	_camera_base_fov = table_camera.fov
	_collect_slot_markers()
	_setup_offline_modes()
	_connect_menu_buttons()
	_connect_online_signals()
	_ensure_effect_overview()
	_setup_spectator_exit_button()
	_setup_event_presentation()
	Localization.locale_changed.connect(_on_locale_changed)
	SettingsManager.presentation_settings_changed.connect(_on_presentation_settings_changed)

	_reset_dealer_gun()
	win_tinnitus_sfx.stream = _create_win_tinnitus_stream()
	if win_blood_sprite.material_override is BaseMaterial3D:
		# Keep the blood's smooth alpha fade independent of the shared eye material.
		var blood_material := win_blood_sprite.material_override.duplicate() as BaseMaterial3D
		blood_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		win_blood_sprite.material_override = blood_material
	_reset_win_cinematic_visuals()
	_show_main_menu()

	# A Steam invite can be accepted while this scene is loading. In that case
	# immediately expose the already joined lobby instead of returning to KI.
	if NetworkManager.has_active_session():
		if NetworkManager.is_match_in_progress():
			_on_online_match_started.call_deferred()
		else:
			_show_multiplayer_menu()


func _set_event_notice(source: String, arguments: Array = []) -> void:
	_event_notice_source = source
	_event_notice_arguments = arguments.duplicate(true)
	_event_notice = Localization.format_text(source, arguments)


func _set_match_status(source: String, arguments: Array = []) -> void:
	_match_status_source = source
	_match_status_arguments = arguments.duplicate(true)
	_match_status_is_reward = false
	_match_status_message = Localization.format_text(source, arguments)


func _on_locale_changed() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	# Rebuild presentation from canonical sources, never replay a draw, duel,
	# reward grant or network action to obtain text in the new language.
	_event_notice = Localization.format_text(_event_notice_source, _event_notice_arguments)
	_match_reward_text = _format_match_rewards()
	_match_status_message = (
		_match_reward_text if _match_status_is_reward
		else Localization.format_text(_match_status_source, _match_status_arguments)
	)
	_refresh_event_hand()


func _process(_delta: float) -> void:
	_refresh_event_hand()
	_refresh_swarm_multipliers()
	_update_satan_pointer_hover()
	_sync_satan_voice_state()
	_spectator_leave_button.visible = _online_mode and _online_is_spectator
	if (
		_online_mode and _online_is_spectator and table_camera != null and not _journal_input_blocked
		and (_camera_tween == null or not _camera_tween.is_running())
	):
		# Compensate the hub's mouse tilt and keep both rows framed on resize.
		table_camera.global_transform = _get_spectator_camera_transform()


func set_journal_input_blocked(blocked: bool) -> void:
	_journal_input_blocked = blocked
	if blocked and _effect_overview != null:
		_effect_overview.hide_overview()
	_refresh_event_hand()


func is_journal_available() -> bool:
	# The book never pauses a running match. Authority/remote presentations
	# interrupt it before moving this same camera or resolving the next action.
	return (
		_table_state in [TableState.MENU, TableState.DIFFICULTY_SELECT, TableState.PLAYING]
		and not _game_over and not _loss_exit_running and not _is_online_match_exiting()
		and not _local_action_in_progress and not _online_action_in_progress
		and not _has_pending_card_replacements() and _online_client_presentation_depth == 0
		and not is_instance_valid(_inspected_card) and _selected_event_uid.is_empty()
		and (_camera_tween == null or not _camera_tween.is_running())
	)


func _interrupt_journal() -> void:
	if _journal_input_blocked:
		journal_interrupted.emit()


func _setup_spectator_exit_button() -> void:
	_spectator_leave_button = Button.new()
	_spectator_leave_button.name = "LeaveSpectatorButton"
	_spectator_leave_button.text = "Zuschauen beenden"
	_spectator_leave_button.position = Vector2(20.0, 20.0)
	_spectator_leave_button.pressed.connect(_leave_spectator_match)
	$OnlineCanvas.add_child(_spectator_leave_button)
	_spectator_leave_button.visible = _online_mode and _online_is_spectator


func _leave_spectator_match() -> void:
	if not _online_mode or not _online_is_spectator:
		return
	_online_mode = false
	_online_is_host = false
	_online_is_spectator = false
	_online_action_in_progress = false
	_reset_online_sync_tracking()
	if NetworkManager.has_active_session():
		NetworkManager.leave_lobby("Zuschauen beendet.")
	_show_main_menu()


func _setup_satan_voice_chat() -> void:
	if _satan_voice_chat != null or dealer_satan == null:
		return
	_satan_voice_chat = SATAN_VOICE_CHAT_SCRIPT.new()
	_satan_voice_chat.name = "SatanVoiceChat"
	_satan_voice_chat.call("configure", dealer_satan)
	add_child(_satan_voice_chat)
	if _satan_voice_chat.has_signal("remote_voice_activity_changed"):
		_satan_voice_chat.connect(
			"remote_voice_activity_changed",
			_on_remote_voice_activity_changed
		)
	if _satan_voice_chat.has_signal("remote_voice_level_changed"):
		_satan_voice_chat.connect(
			"remote_voice_level_changed",
			_on_remote_voice_level_changed
		)
	_sync_satan_voice_state()


func _sync_satan_voice_state() -> void:
	_sync_online_character()
	var should_be_active := (
		_table_state == TableState.PLAYING
		and _online_mode
		and not _online_is_spectator
		and NetworkManager.has_connected_opponent()
		and not _loss_exit_running
	)
	if match_hud != null and is_instance_valid(match_hud):
		match_hud.show_for_match(_online_mode and not _online_character_retired and _table_state in [TableState.PLAYING, TableState.GAME_OVER])
		match_hud.set_voice_chat_enabled(SettingsManager.satan_voice_enabled)
	if _satan_voice_chat == null or not is_instance_valid(_satan_voice_chat):
		return
	_satan_voice_chat.call("set_match_active", should_be_active)


func _sync_online_character() -> void:
	if not is_instance_valid(dealer_satan) or not is_instance_valid(match_hud):
		return
	# The exit epilogue belongs to the local hub even while the transport waits
	# for the other cinematic. Late roster updates must not dress Satan again.
	if _online_character_retired:
		return
	if not _online_mode:
		# Disconnected exits set local mode before playing their final shot. Keep
		# that opponent until the same hidden swap used by a connected exit.
		if _loss_exit_running:
			return
		if not _online_character_data.is_empty():
			dealer_satan.call("clear_player_appearance")
			match_hud.set_character_players()
			_online_character_data = {}
			_online_second_character_data = {}
		return
	var opponent: Dictionary = NetworkManager.remote_player_data
	var second: Dictionary = {}
	if _online_is_spectator:
		var fighters := NetworkManager.get_fighter_peer_ids()
		if fighters.size() == 2:
			# Overhead view preserves host sides: far-side guest, near-side host.
			opponent = NetworkManager.get_player_data_for_peer(fighters[1])
			second = NetworkManager.get_player_data_for_peer(fighters[0])
	# Keep the last accepted look if transport closes during a result/cinematic.
	if opponent.is_empty():
		return
	var character := {"name": opponent.get("name", ""), "appearance": CharacterAppearance.sanitize(opponent.get("appearance"))}
	var second_character := {"name": second.get("name", ""), "appearance": CharacterAppearance.sanitize(second.get("appearance"))} if not second.is_empty() else {}
	if character == _online_character_data and second_character == _online_second_character_data:
		return
	_online_character_data = character
	_online_second_character_data = second_character
	dealer_satan.call("set_player_appearance", character["appearance"])
	match_hud.set_character_players(character, second_character, _online_is_spectator)


func _restore_standard_satan_for_exit() -> void:
	if not _online_mode and _online_character_data.is_empty():
		return
	_online_character_retired = true
	if is_instance_valid(dealer_satan):
		dealer_satan.call("clear_player_appearance")
	_online_character_data = {}
	_online_second_character_data = {}
	if is_instance_valid(match_hud):
		match_hud.set_character_players()
		match_hud.show_for_match(false)


func _on_remote_voice_activity_changed(activity: int) -> void:
	if match_hud != null and is_instance_valid(match_hud):
		match_hud.set_remote_voice_activity(activity)
		if (
			_satan_voice_chat != null
			and is_instance_valid(_satan_voice_chat)
			and _satan_voice_chat.has_method("get_remote_voice_level")
		):
			match_hud.set_remote_voice_level(
				float(_satan_voice_chat.call("get_remote_voice_level"))
			)


func _on_remote_voice_level_changed(level: float) -> void:
	if match_hud != null and is_instance_valid(match_hud):
		match_hud.set_remote_voice_level(level)


func _collect_slot_markers() -> void:
	_player_slot_markers.clear()
	_enemy_slot_markers.clear()

	for i: int in range(HAND_SIZE):
		var p_marker: Marker3D = player_slots_root.get_node("Slot%d" % i) as Marker3D
		var e_marker: Marker3D = enemy_slots_root.get_node("Slot%d" % i) as Marker3D
		_player_slot_markers.append(p_marker)
		_enemy_slot_markers.append(e_marker)


# --- Match-Aufbau ---------------------------------------------------------

func _start_match() -> void:
	if _local_mode == "story" and not GameCurrency.is_story_level_unlocked(_story_level):
		return
	if _local_mode == "training" and (_training_player.size() != HAND_SIZE or _training_enemy.size() != HAND_SIZE):
		return
	# A KI match is entirely local and must never inherit a still-set online
	# presentation barrier from the previous session.
	_online_mode = false
	_match_reward_difficulty = _selected_difficulty
	_online_is_host = false
	_online_is_spectator = false
	_online_action_in_progress = false
	_local_action_in_progress = false
	_reset_online_sync_tracking()
	_last_match_outcome = MatchOutcome.NONE
	_match_reward_granted = false
	_reset_win_cinematic_visuals()

	if _local_mode != "training" and DeckManager.is_empty():
		_show_main_menu()
		return
	_table_state = TableState.PLAYING
	_clear_match()
	_move_camera_to_match_view()
	_game_over = false
	_current_turn = "player"
	_selected_player_card = null

	var player_pool: Array[Dictionary] = _training_player.duplicate(true) if _local_mode == "training" else _build_player_pool()
	var enemy_pool: Array[Dictionary]
	if _local_mode == "training":
		enemy_pool = _training_enemy.duplicate(true)
	elif _local_mode == "story":
		enemy_pool = OFFLINE_RULES.story_deck(_story_level, deck_size)
	else:
		enemy_pool = _build_enemy_pool()

	if player_pool.is_empty():
		push_error("Spieler hat keine Karten in der Sammlung — Kampf kann nicht starten.")
		_set_match_status("Keine Karten in deiner Sammlung!")
		return

	if enemy_pool.is_empty():
		push_error("Keine Karten deiner in der CardDatabase gefunden.")
		_set_match_status("Keine Kartendaten gefunden!")
		return

	if _local_mode == "training":
		# Preserve chosen slot order. Both five-card decks are exhausted by the
		# opening deal; no collection card or ordinary reserve is added later.
		player_pool.reverse()
		enemy_pool.reverse()
		_player_deck = player_pool
	else:
		enemy_pool.shuffle()
		enemy_pool = _limit_deck_size(enemy_pool, deck_size)
		_player_deck = DeckManager.prepare_match_deck(player_pool, DeckManager.get_starting_deck_indices(), CollectionManager.get_starting_hand_slot_count(), deck_size)
	_enemy_deck = enemy_pool
	_initialize_event_deck()
	_deal_starting_event_hands()

	for i: int in range(HAND_SIZE):
		_draw_to_slot("player", i, false)
		_draw_to_slot("enemy", i, false)

	_prepare_chick_turn()
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")

	_update_status_for_current_turn()
	_training_hud.visible = _local_mode == "training"


# Resolve each deck occurrence to its saved collection instance before applying
# the existing card-type upgrades. Drawing never rolls a new cosmetic variant.
func _build_player_pool() -> Array[Dictionary]:
	return DeckManager.get_deck_card_data()


func _build_enemy_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var all_cards: Array = CardDatabase.get_combat_cards()

	var rarity_weights := _get_enemy_rarity_weights(_selected_difficulty)

	for data: Dictionary in all_cards:
		var rarity := str(data.get("rarity", "common"))
		var weight := int(rarity_weights.get(rarity, 0))

		for i in range(weight):
			pool.append(
				CardData.merge_card_and_instance(
					data,
					CardData.create_instance(
						str(data.get("id", "")),
						1,
						EffectDatabase.roll_effects()
					)
				)
			)

	return pool

func _get_enemy_rarity_weights(difficulty: String) -> Dictionary:
	match difficulty:
		"easy":
			return {
				"common": 12,
				"uncommon": 3,
				"rare": 1,
				"epic": 0,
				"legendary": 0,
				"mythic": 0,
				"exotic": 0
			}

		"normal":
			return {
				"common": 8,
				"uncommon": 5,
				"rare": 3,
				"epic": 1,
				"legendary": 0,
				"mythic": 0,
				"exotic": 0
			}

		"hard":
			return {
				"common": 5,
				"uncommon": 5,
				"rare": 4,
				"epic": 3,
				"legendary": 1,
				"mythic": 0,
				"exotic": 0
			}

		"insane":
			return {
				"common": 1,
				"uncommon": 2,
				"rare": 5,
				"epic": 7,
				"legendary": 5,
				"mythic": 3,
				"exotic": 1
			}

		_:
			return {
				"common": 8,
				"uncommon": 5,
				"rare": 3,
				"epic": 1,
				"legendary": 0,
				"mythic": 0,
				"exotic": 0
			}
# --- Sichtbarer Kartenstapel (nur Optik) -----------------------------------
#
# Eine sichtbare Ruecken-Karte pro verbleibender Karte, auch bei grossen
# Decks. Vorhandene Instanzen bleiben bei Online-Snapshots erhalten.
func _rebuild_stack_visual(side: String) -> void:
	var visuals: Array[Card3D] = _player_stack_visuals if side == "player" else _enemy_stack_visuals
	var deck: Array[Dictionary] = _player_deck if side == "player" else _enemy_deck
	var deck_marker: Marker3D = player_deck_marker if side == "player" else enemy_deck_marker

	while visuals.size() > deck.size():
		var top: Card3D = visuals.pop_back()
		if is_instance_valid(top):
			top.visible = false
			top.queue_free()
	while visuals.size() < deck.size():
		var deco := _spawn_stack_decoration_card(
			deck_marker.global_position + STACK_LAYER_OFFSET * visuals.size()
		)
		visuals.append(deco)
	for i: int in range(visuals.size()):
		visuals[i].global_position = deck_marker.global_position + STACK_LAYER_OFFSET * i
		# One physical back is in flight from each pile during Switch. Keep
		# snapshots from restoring a duplicate top card while it travels.
		visuals[i].visible = _event_switch_cards.is_empty() or i < visuals.size() - 1


# Vor dem Entnehmen aufrufen, damit die Flugbahn an der obersten Karte
# beginnt. Online kann die Anzahl vor dem Ziehen explizit uebergeben werden.
func _get_stack_top_position(side: String, deck_count_override: int = -1) -> Vector3:
	var deck: Array[Dictionary] = _player_deck if side == "player" else _enemy_deck
	var deck_marker: Marker3D = player_deck_marker if side == "player" else enemy_deck_marker
	var count := deck.size() if deck_count_override < 0 else deck_count_override
	return deck_marker.global_position + STACK_LAYER_OFFSET * maxi(0, count - 1)


# Erzeugt eine einzelne, rein optische "verdeckte" Karte (Rueckseite
# zur Kamera) ohne Spieldaten/Klick-Interaktion/Shine-Effekt.
func _spawn_stack_decoration_card(target_global_pos: Vector3) -> Card3D:
	var card: Card3D = card_scene.instantiate() as Card3D
	card.is_stack_decoration = true
	add_child(card)
	# Stapel brauchen weder Label-Animationen noch Raycast-Ziele.
	card.process_mode = Node.PROCESS_MODE_DISABLED
	card.area.input_ray_pickable = false
	card.area.collision_layer = 0
	card.area.collision_mask = 0

	card.global_position = target_global_pos
	# Um die X-Achse um 180° gegenueber der normalen "liegenden"
	# Ausrichtung (-90, 0, 0) gedreht, damit die Vorderseite (Bild +
	# Labels) nach unten zum Tisch zeigt und die Rueckseite nach oben
	# zur Kamera.
	card.rotation_degrees = Vector3(90, 180, 0)

	return card


# Nach dem Entnehmen mit der verbleibenden Deckgroesse abgleichen.
func _pop_stack_visual(side: String) -> void:
	_rebuild_stack_visual(side)


# --- Karten ziehen ---------------------------------------------------------

# Event cards belong to the match. Opening hands and kill effects use this
# shared shuffled pile; normal combat replacements never grant an event.
func _initialize_event_deck() -> void:
	_event_deck = EVENT_DECK_RULES.create_shuffled(_rng)


func _deal_starting_event_hands() -> void:
	if _starting_events_dealt or _game_over or (_online_mode and not _online_is_host) or _online_is_spectator:
		return
	var hand_size := EVENT_DECK_RULES.STARTING_HAND_SIZE
	if _event_deck.size() < hand_size * 2:
		return
	_starting_events_dealt = true
	# Alternate recipients so both players draw from the same shuffled pool.
	# Opening cards are immediately available on the owner's first turn;
	# they must not display the next-turn notice used for kill rewards.
	for index in range(hand_size):
		for side: String in ["player", "enemy"]:
			_event_hand(side).append(EVENT_DECK_RULES.draw(_event_deck, _event_discard, _rng))


func _setup_event_presentation() -> void:
	_event_hand_ui = EVENT_HAND_UI.new()
	_event_hand_ui.name = "EventHand"
	$OnlineCanvas.add_child(_event_hand_ui)
	_event_hand_ui.event_selected.connect(_on_event_selected)
	_event_hand_ui.selection_cancelled.connect(_cancel_event_selection)
	_event_pass_button = Button.new()
	_event_pass_button.name = "PassBlockedTurn"
	_event_pass_button.text = "Alle Karten blockiert · Zug beenden"
	_event_pass_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_event_pass_button.offset_left = -180
	_event_pass_button.offset_right = 180
	_event_pass_button.offset_top = -108
	_event_pass_button.offset_bottom = -70
	_event_pass_button.pressed.connect(_request_event_pass)
	$OnlineCanvas.add_child(_event_pass_button)
	_event_pass_button.hide()


func _clear_event_match() -> void:
	_clear_switch_exchange()
	_clear_rearrange_target()
	_piss_hidden_turns = {"player": 0, "enemy": 0}
	_refresh_piss_visibility()
	if is_instance_valid(_event_piss_stream):
		_event_piss_stream.stop_pissing(true)
	if _event_resolution_tween != null and _event_resolution_tween.is_valid():
		_event_resolution_tween.kill()
	_event_resolution_tween = null
	if _event_replacement_tween != null and _event_replacement_tween.is_valid():
		_event_replacement_tween.kill()
	_event_replacement_tween = null
	for card in _event_moving_cards:
		if is_instance_valid(card):
			card.queue_free()
	_event_moving_cards.clear()
	_event_deck.clear()
	_event_discard.clear()
	_player_event_hand.clear()
	_enemy_event_hand.clear()
	_starting_events_dealt = false
	_event_played_this_turn = false
	_selected_event_uid = ""
	_set_event_notice("")
	_last_played_event.clear()
	_last_event_side = ""
	_event_play_sequence = 0
	_event_presented_sequence = 0
	_event_reveal_deadline_msec = 0
	if _event_hand_ui != null:
		if _event_hand_ui.has_method("clear_played_events"):
			_event_hand_ui.clear_played_events()
		_event_hand_ui.configure(_player_event_hand, false, "", "", false)
	if _event_pass_button != null:
		_event_pass_button.hide()


func _can_local_event_or_attack() -> bool:
	return (
		_table_state == TableState.PLAYING and not _game_over and not _loss_exit_running and not _journal_input_blocked
		and not _online_is_spectator and _current_turn == "player"
		and not (_online_action_in_progress if _online_mode else _local_action_in_progress)
		and not _is_online_match_exiting()
	)


func _refresh_event_hand() -> void:
	if _event_hand_ui == null:
		return
	var show_hand := _table_state == TableState.PLAYING and not _game_over and not _loss_exit_running and not _online_is_spectator and not _journal_input_blocked
	var can_act := _can_local_event_or_attack()
	var status := _event_notice
	if _current_turn != "player":
		status = "Gegner am Zug · Event-Karten bleiben auf deiner Hand"
	elif _event_played_this_turn:
		status = "Event gespielt · Wähle jetzt deine Karte zum Angriff"
	elif status.is_empty():
		status = "Optional: 1 Event vor deinem Angriff · Weitere Karten durch Kill-Effekte"
	if not _online_is_spectator and int(_piss_hidden_turns["player"]) > 0:
		status += "\n" + Localization.format_text("Piss · Kartenwerte verborgen: noch %d eigene Züge", [int(_piss_hidden_turns["player"])])
	_event_hand_ui.configure(_player_event_hand, can_act and not _event_played_this_turn, _selected_event_uid, status, show_hand)
	_event_pass_button.visible = show_hand and can_act and not _has_event_attack_card(_player_slots)


func _event_hand(side: String) -> Array[Dictionary]:
	return _player_event_hand if side == "player" else _enemy_event_hand


func _event_from_hand(side: String, uid: String) -> Dictionary:
	for event in _event_hand(side):
		if str(event.get("uid", "")) == uid and not uid.is_empty():
			return event
	return {}


func _draw_event_card(side: String) -> Dictionary:
	if side not in ["player", "enemy"] or _game_over or (_online_mode and not _online_is_host):
		return {}
	var event: Dictionary = EVENT_DECK_RULES.draw(_event_deck, _event_discard, _rng)
	if event.is_empty():
		return {}
	_event_hand(side).append(event)
	if side == "player":
		_set_event_notice("%s gezogen · Ab deinem nächsten Zug ausspielbar", [Localization.localized_arg(str(event.get("name", "Event")))])
	return event


func _award_event_for_death(victim: Card3D) -> void:
	if not is_instance_valid(victim) or not victim.is_dead() or (_online_mode and not _online_is_host):
		return
	_spread_eternal_suffering_on_death(victim)
	if not CardData.has_effect(victim.card_data, "draw_on_death") or victim.has_meta("event_death_awarded"):
		return
	var side := str(_find_slot_of(victim).get("side", ""))
	if side.is_empty():
		return
	victim.set_meta("event_death_awarded", true)
	_draw_event_card(side)


func _spread_eternal_suffering_on_death(victim: Card3D) -> void:
	if victim.eternal_suffering_damage <= 0 or victim.has_meta("eternal_suffering_spread"):
		return
	var info := _find_slot_of(victim)
	var index := int(info.get("index", -1))
	if index < 0:
		return
	# Mark before applying to either neighbor. Repeated damage/death cleanup
	# cannot refresh this poison or spread it to replacements drawn later.
	victim.set_meta("eternal_suffering_spread", true)
	var slots: Array[Card3D] = _player_slots if str(info.get("side", "")) == "player" else _enemy_slots
	for neighbor_index in [index - 1, index + 1]:
		if neighbor_index < 0 or neighbor_index >= slots.size():
			continue
		var neighbor := slots[neighbor_index]
		if not is_instance_valid(neighbor) or neighbor.is_dead():
			continue
		neighbor.apply_poison(victim.eternal_suffering_damage, 3)
		_spawn_effect_vfx(neighbor, poison_vfx_scene)


func _on_event_selected(uid: String) -> void:
	if not _can_local_event_or_attack() or _event_played_this_turn:
		return
	var event := _event_from_hand("player", uid)
	if event.is_empty():
		return
	# Instant events never enter target selection, including while an online
	# request is pending or when a draw pile is empty and the play is rejected.
	if str(event.get("target", "none")) == "none":
		_cancel_event_selection()
		_submit_event(uid, -1)
		return
	if _selected_event_uid == uid:
		_cancel_event_selection()
		return
	if is_instance_valid(_selected_player_card):
		_selected_player_card.clear_selected_immediate()
	_selected_player_card = null
	_clear_rearrange_target()
	_selected_event_uid = uid
	_set_event_notice(
		"%s · Choose one of your cards. Right-click/Esc: cancel" if event.get("target") == "ally"
		else "%s · Choose an opposing card. Right-click/Esc: cancel",
		[Localization.localized_arg(str(event.get("name", "Event")))]
	)


func _cancel_event_selection() -> void:
	_clear_rearrange_target()
	_selected_event_uid = ""
	_set_event_notice("")


func _on_event_target_clicked(side: String, slot: int) -> void:
	var event := _event_from_hand("player", _selected_event_uid)
	if event.is_empty() or str(event.get("target", "none")) == "none":
		_cancel_event_selection()
		return
	var target_side := "player" if event.get("target") == "ally" else "enemy"
	if side != target_side:
		_set_event_notice("Choose one of your cards for this event." if target_side == "player" else "Choose an opposing card for this event.")
		return
	if event.get("id") == "rearrange_event":
		var card := _get_card_from_slot(side, slot)
		if not is_instance_valid(card) or card.is_dead():
			return
		if not is_instance_valid(_rearrange_first_card):
			_rearrange_first_card = card
			card.set_selected(true)
			_set_event_notice("Rearrange · Wähle jetzt eine zweite eigene Karte. Rechtsklick/Esc: Abbrechen")
			return
		var first := _find_slot_of(_rearrange_first_card)
		if str(first.get("side", "")) != "player":
			_cancel_event_selection()
			return
		_submit_event(_selected_event_uid, int(first.get("index", -1)), slot)
		return
	_submit_event(_selected_event_uid, slot)


func _clear_rearrange_target() -> void:
	if is_instance_valid(_rearrange_first_card):
		_rearrange_first_card.clear_selected_immediate()
	_rearrange_first_card = null


func _event_target_error(side: String, event: Dictionary, target_slot: int, second_slot: int = -1) -> String:
	if event.is_empty() or side not in ["player", "enemy"]:
		return "Event nicht verfügbar."
	if event.get("id") == "rearrange_event":
		var first := _get_card_from_slot(side, target_slot)
		var second := _get_card_from_slot(side, second_slot)
		if target_slot == second_slot or not is_instance_valid(first) or not is_instance_valid(second):
			return "Wähle zwei verschiedene eigene Karten auf dem Tisch."
		return "Wähle zwei lebende eigene Karten." if first.is_dead() or second.is_dead() else ""
	if second_slot != -1:
		return "Dieses Event benötigt nur ein Ziel."
	if str(event.get("id", "")) == "piss_event":
		return "Piss wird direkt ohne Ziel ausgespielt." if target_slot != -1 else ""
	if str(event.get("id", "")) == "switch":
		if target_slot != -1:
			return "Switch wird direkt ohne Ziel ausgespielt."
		return "Switch benötigt eine Karte in beiden Kampf-Ziehstapeln." if _player_deck.is_empty() or _enemy_deck.is_empty() else ""
	var target_side := side if event.get("target") == "ally" else ("enemy" if side == "player" else "player")
	var target := _get_card_from_slot(target_side, target_slot)
	if not is_instance_valid(target) or target.is_dead():
		return "Wähle eine lebende Karte auf dem Tisch."
	if event.get("id") == "heal_event" and target.current_hp >= target.max_hp:
		return "Diese Karte ist bereits vollständig geheilt."
	return ""


func _try_play_event(side: String, uid: String, target_slot: int = -1, second_slot: int = -1) -> bool:
	if (
		_game_over or _table_state != TableState.PLAYING or _loss_exit_running
		or side != _current_turn or _event_played_this_turn or _is_online_match_exiting()
		or (_online_mode and (not _online_is_host or _online_action_in_progress))
		or (not _online_mode and side == "player" and _local_action_in_progress)
	):
		return false
	var event := _event_from_hand(side, uid)
	var error := _event_target_error(side, event, target_slot, second_slot)
	if not error.is_empty():
		_set_event_notice(error)
		return false
	var target_side := side if event.get("target") == "ally" else ("enemy" if side == "player" else "player")
	var target := _get_card_from_slot(target_side, target_slot)
	match str(event.get("id", "")):
		"rearrange_event":
			_clear_rearrange_target()
			_swap_event_slots(side, target_slot, second_slot)
		"heal_event":
			var missing_hp := maxi(target.max_hp - target.current_hp, 0)
			target.heal(missing_hp)
			_spawn_heal_from_card(target, missing_hp)
		"piss_event":
			_piss_hidden_turns[target_side] = maxi(int(_piss_hidden_turns[target_side]), int(event.get("hidden_turns", 2)))
			_refresh_piss_visibility()
		"switch":
			var player_index := _rng.randi_range(0, _player_deck.size() - 1)
			var enemy_index := _rng.randi_range(0, _enemy_deck.size() - 1)
			var swapped := _player_deck[player_index]
			_player_deck[player_index] = _enemy_deck[enemy_index]
			_enemy_deck[enemy_index] = swapped
		"block":
			target.apply_event_block(int(event.get("block_turns", 2)))
		"steel":
			_steal_event_target(side, target_side, target_slot, target)
		"strength_120", "strength_150", "strength_200":
			target.apply_event_strength(float(event.get("multiplier", 1.2)))
			_spawn_heal_from_card(target)
		_:
			return false
	_event_hand(side).erase(event)
	_event_discard.append(event)
	_event_played_this_turn = true
	_clear_rearrange_target()
	_selected_event_uid = ""
	_set_event_notice("%s spielt %s", [
		Localization.localized_arg("Du" if side == "player" else "Gegner"),
		Localization.localized_arg(str(event.get("name", "Event")))
	])
	_last_played_event = event.duplicate(true)
	_last_event_side = side
	_event_play_sequence += 1
	_present_played_event()
	if is_instance_valid(_selected_player_card):
		_selected_player_card.clear_selected_immediate()
	_selected_player_card = null
	return true


func _steal_event_target(side: String, target_side: String, slot: int, target: Card3D) -> void:
	var deck := _player_deck if side == "player" else _enemy_deck
	var slots := _player_slots if target_side == "player" else _enemy_slots
	deck.insert(_rng.randi_range(0, deck.size()), target.export_event_deck_card())
	slots[slot] = null
	if _inspected_card == target:
		_reset_camera()
	_on_effect_card_unhovered(target)
	target.clear_selected_immediate()
	target.area.input_ray_pickable = false
	target.area.collision_layer = 0
	target.area.collision_mask = 0
	target.set_process(false)
	_event_moving_cards.append(target)
	_rebuild_stack_visual(side)
	_event_resolution_tween = create_tween().set_parallel(true)
	_event_resolution_tween.tween_property(target, "global_position", _get_stack_top_position(side), draw_animation_duration)
	_event_resolution_tween.tween_property(target, "scale", Vector3.ONE * 0.1, draw_animation_duration)
	_event_resolution_tween.chain().tween_callback(func():
		_event_moving_cards.erase(target)
		if is_instance_valid(target):
			target.queue_free()
	)
	_event_replacement_tween = _draw_to_slot(target_side, slot, true)


func _submit_event(uid: String, target_slot: int, second_slot: int = -1) -> void:
	if not _can_local_event_or_attack():
		return
	var error := _event_target_error("player", _event_from_hand("player", uid), target_slot, second_slot)
	if not error.is_empty():
		_set_event_notice(error)
		return
	if _online_mode and not _online_is_host:
		_online_action_in_progress = true
		_clear_rearrange_target()
		_rpc_request_event.rpc_id(1, uid, target_slot, _online_turn_sequence, second_slot)
		return
	if not _try_play_event("player", uid, target_slot, second_slot):
		return
	await _complete_event_action()


func _complete_event_action() -> void:
	var generation := _match_generation
	var started_online := _online_mode
	var event_state_sync_sequence := 0
	if started_online:
		_online_action_in_progress = true
		_set_authoritative_online_selection("", -1)
		# Begin the public reveal on all peers together, inside the state barrier.
		event_state_sync_sequence = _sync_online_state(true)
	else:
		_local_action_in_progress = true
	# The played card lands on the table before another action is accepted.
	await get_tree().create_timer(0.85).timeout
	if not _is_current_match_flow(generation, started_online):
		return
	await _wait_for_tween(_event_resolution_tween, draw_animation_duration + 0.3)
	await _wait_for_tween(_event_replacement_tween, draw_animation_duration + 0.3)
	if not _is_current_match_flow(generation, started_online):
		return
	_event_resolution_tween = null
	_event_replacement_tween = null
	if _check_game_over():
		return
	if started_online:
		await _complete_online_state_barrier(_online_turn_sequence, event_state_sync_sequence)
	else:
		_local_action_in_progress = _current_turn == "enemy"


func _present_played_event() -> void:
	if _event_play_sequence <= _event_presented_sequence or _last_played_event.is_empty():
		return
	_event_presented_sequence = _event_play_sequence
	_event_reveal_deadline_msec = Time.get_ticks_msec() + 850
	var local_side := _canonical_side_to_local(_last_event_side) if _online_mode else _last_event_side
	if str(_last_played_event.get("id", "")) == "piss_event":
		_play_piss_stream(local_side)
	if str(_last_played_event.get("id", "")) == "switch":
		_play_switch_exchange()
	if _event_hand_ui != null and _event_hand_ui.has_method("play_event"):
		_event_hand_ui.play_event(_last_played_event, local_side == "enemy")


func _play_switch_exchange() -> void:
	_clear_switch_exchange()
	if _player_deck.is_empty() or _enemy_deck.is_empty():
		return
	var near := _get_stack_top_position("player")
	var far := _get_stack_top_position("enemy")
	# Only backs travel: the authority already exchanged the random complete
	# instances. No private card identities or draw order enter this effect.
	_event_switch_cards.append(_spawn_stack_decoration_card(near))
	_event_switch_cards.append(_spawn_stack_decoration_card(far))
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")
	_event_switch_tween = create_tween()
	_event_switch_tween.tween_method(_update_switch_exchange.bind(near, far), 0.0, 1.0, SWITCH_EXCHANGE_DURATION)
	_event_switch_tween.tween_callback(_finish_switch_exchange)


func _update_switch_exchange(progress: float, near: Vector3, far: Vector3) -> void:
	if _event_switch_cards.size() != 2:
		return
	var arc := sin(progress * PI)
	var travel := smoothstep(0.0, 1.0, progress)
	var lateral := (far - near).cross(Vector3.UP).normalized()
	for index in range(2):
		var card := _event_switch_cards[index]
		if not is_instance_valid(card):
			continue
		var start := near if index == 0 else far
		var finish := far if index == 0 else near
		# Separate lanes make both directions readable without intersecting.
		# Both arcs bend inward: the authored piles sit at the screen's edge.
		var lane := -1.70 if index == 0 else -0.65
		card.global_position = start.lerp(finish, travel) + (Vector3.UP * 0.32 + lateral * lane) * arc
		var tilt := -1.0 if index == 0 else 1.0
		card.rotation_degrees = Vector3(90.0 + 8.0 * arc, 180.0 + tilt * 16.0 * arc, 0.0)


func _finish_switch_exchange() -> void:
	_clear_switch_exchange()
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")


func _clear_switch_exchange() -> void:
	if _event_switch_tween != null and _event_switch_tween.is_valid():
		_event_switch_tween.kill()
	_event_switch_tween = null
	for card in _event_switch_cards:
		if is_instance_valid(card):
			card.hide()
			card.queue_free()
	_event_switch_cards.clear()
	for card in _player_stack_visuals + _enemy_stack_visuals:
		if is_instance_valid(card):
			card.show()


func _refresh_piss_visibility() -> void:
	var hidden := not _online_is_spectator and int(_piss_hidden_turns["player"]) > 0
	if hidden:
		_clear_damage_numbers()
		if is_instance_valid(_effect_overview):
			_effect_overview.hide_overview()
			_effect_overview.hide()
	for card: Card3D in _player_slots + _enemy_slots:
		if is_instance_valid(card):
			card.set_stats_hidden(hidden)


func _tick_piss_visibility(side: String) -> void:
	_piss_hidden_turns[side] = maxi(int(_piss_hidden_turns[side]) - 1, 0)
	_refresh_piss_visibility()


func _play_piss_stream(side: String) -> void:
	if not is_instance_valid(_event_piss_stream):
		_event_piss_stream = EVENT_PISS_SCENE.instantiate()
		_event_piss_stream.name = "EventPissStream"
		add_child(_event_piss_stream)
		_event_piss_stream.configure_table_event($table/Cube, func() -> bool:
			return _table_state == TableState.PLAYING and not _game_over and not _loss_exit_running
		)
	_event_piss_stream.stop_pissing(true)
	# A separate emitter preserves the authored hub interaction and its pose.
	var source := (player_slots_root if side == "player" else enemy_slots_root).global_position
	var toward_center := global_position - source
	toward_center.y = 0.0
	_event_piss_stream.global_position = source - toward_center.normalized() * 1.25 + Vector3.UP * 0.85
	_event_piss_stream.start_pissing()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_event(uid: String, target_slot: int, turn_sequence: int, second_slot: int = -1) -> void:
	if not _online_mode or not _online_is_host or _is_online_match_exiting():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender):
		return
	if turn_sequence != _online_turn_sequence or not _try_play_event("enemy", uid, target_slot, second_slot):
		_rpc_apply_online_state.rpc_id(sender, _build_online_snapshot(0, sender))
		return
	await _complete_event_action()


func _tick_event_blocks(side: String) -> void:
	var slots := _player_slots if side == "player" else _enemy_slots
	for card in slots:
		if is_instance_valid(card):
			card.tick_event_block()


func _has_event_attack_card(slots: Array[Card3D]) -> bool:
	for card in slots:
		if is_instance_valid(card) and not card.is_dead() and not card.is_event_blocked():
			return true
	return false


func _pick_random_attack_card(slots: Array[Card3D]) -> Card3D:
	var eligible: Array[Card3D] = []
	for card in slots:
		if is_instance_valid(card) and not card.is_dead() and not card.is_event_blocked():
			eligible.append(card)
	return _pick_random_living_card(eligible)


func _request_event_pass() -> void:
	if not _can_local_event_or_attack() or _has_event_attack_card(_player_slots):
		return
	if _online_mode:
		_online_action_in_progress = true
		if not _online_is_host:
			_rpc_request_event_pass.rpc_id(1, _online_turn_sequence)
			return
	else:
		_local_action_in_progress = true
	_end_turn_to("enemy")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_event_pass(turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host or not _is_online_opponent(multiplayer.get_remote_sender_id()):
		return
	if _game_over or _is_online_match_exiting() or _online_action_in_progress or _current_turn != "enemy" or turn_sequence != _online_turn_sequence or _has_event_attack_card(_enemy_slots):
		_sync_online_state()
		return
	_online_action_in_progress = true
	_end_turn_to("player")


func _play_enemy_event() -> void:
	for event in _enemy_event_hand.duplicate():
		if event.get("id") == "rearrange_event":
			for first in range(HAND_SIZE):
				for second in range(first + 1, HAND_SIZE):
					if _try_play_event("enemy", str(event.get("uid", "")), first, second):
						await _complete_event_action()
						return
			continue
		var target_side := "enemy" if event.get("target") == "ally" else "player"
		var candidates: Array = [-1] if event.get("target") == "none" else [0, 1, 2, 3, 4]
		candidates.shuffle()
		for slot in candidates:
			if slot >= 0:
				var target := _get_card_from_slot(target_side, slot)
				if not is_instance_valid(target) or (event.get("id") == "block" and target.is_event_blocked()):
					continue
			if _try_play_event("enemy", str(event.get("uid", "")), slot):
				await _complete_event_action()
				return

# Zieht die oberste Karte aus dem jeweiligen Deck und setzt sie in den
# angegebenen Slot. Wenn das Deck leer ist, bleibt der Slot leer (null).
# animated = true sorgt fuer einen kleinen Flug vom Stapel-Marker zum
# Slot, animated = false (Spielstart) platziert die Karte sofort.
func _draw_to_slot(side: String, slot_index: int, animated: bool) -> Tween:
	var deck: Array[Dictionary] = _player_deck if side == "player" else _enemy_deck
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
	var slot_marker: Marker3D = _get_slot_marker(side, slot_index)

	if deck.is_empty():
		slots[slot_index] = null
		return null

	var draw_origin := _get_stack_top_position(side)
	var data: Dictionary = deck.pop_back()
	# A short deck may reserve a later starting slot while having too few
	# unchosen copies to fill every earlier one. Consume that empty position.
	if data.is_empty():
		slots[slot_index] = null
		return null
	_pop_stack_visual(side)

	var card: Card3D = card_scene.instantiate() as Card3D
	add_child(card)
	card.setup(data)
	_play_card_draw_sound(card)

	var target_pos: Vector3 = slot_marker.global_position
	var target_rot: Vector3 = Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 180, 180)

	var draw_tween: Tween = null
	if animated:
		card.global_position = draw_origin
		card.rotation_degrees = target_rot
		card.scale = Vector3.ONE * 0.6

		draw_tween = create_tween().set_parallel(true)
		draw_tween.tween_property(card, "global_position", target_pos, draw_animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		draw_tween.tween_property(card, "scale", Vector3.ONE, draw_animation_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		card.global_position = target_pos
		card.rotation_degrees = target_rot

	card.died.connect(_on_card_died.bind(side, slot_index))
	_connect_card_input(card, side, slot_index)

	slots[slot_index] = card
	return draw_tween


func _get_slot_marker(side: String, slot_index: int) -> Marker3D:
	return _player_slot_markers[slot_index] if side == "player" else _enemy_slot_markers[slot_index]


func _swap_event_slots(side: String, first: int, second: int, animate: bool = true) -> Tween:
	var slots := _player_slots if side == "player" else _enemy_slots
	var a := slots[first]
	var b := slots[second]
	for entry: Array in [[a, first, second], [b, second, first]]:
		var card: Card3D = entry[0]
		card.clear_selected_immediate()
		# Its old selection anchor must not pull it back after the move.
		card._has_select_base_position = false
		var click := _on_card_clicked.bind(side, int(entry[1]))
		if card.area.input_event.is_connected(click):
			card.area.input_event.disconnect(click)
		var death := _on_card_died.bind(side, int(entry[1]))
		if card.died.is_connected(death):
			card.died.disconnect(death)
		_connect_card_input(card, side, int(entry[2]))
		card.died.connect(_on_card_died.bind(side, int(entry[2])))
	slots[first] = b
	slots[second] = a
	if not animate:
		a.global_position = _get_slot_marker(side, second).global_position
		b.global_position = _get_slot_marker(side, first).global_position
		return null
	_event_resolution_tween = create_tween().set_parallel(true)
	_event_resolution_tween.tween_property(a, "global_position", _get_slot_marker(side, second).global_position, 0.35).set_trans(Tween.TRANS_SINE)
	_event_resolution_tween.tween_property(b, "global_position", _get_slot_marker(side, first).global_position, 0.35).set_trans(Tween.TRANS_SINE)
	return _event_resolution_tween


func _connect_card_input(card: Card3D, side: String, slot_index: int) -> void:
	card.set_stats_hidden(not _online_is_spectator and int(_piss_hidden_turns["player"]) > 0)
	if card.area == null:
		return

	var card_clicked := _on_card_clicked.bind(side, slot_index)
	if not card.area.input_event.is_connected(card_clicked):
		card.area.input_event.connect(card_clicked)
	if not card.card_hovered.is_connected(_on_effect_card_hovered):
		card.card_hovered.connect(_on_effect_card_hovered)
	if not card.card_unhovered.is_connected(_on_effect_card_unhovered):
		card.card_unhovered.connect(_on_effect_card_unhovered)


func _ensure_effect_overview() -> void:
	if _effect_overview != null and is_instance_valid(_effect_overview):
		return
	if overview_scene == null:
		return
	if _effect_overview_layer == null or not is_instance_valid(_effect_overview_layer):
		_effect_overview_layer = CanvasLayer.new()
		_effect_overview_layer.name = "EffectOverviewLayer"
		add_child(_effect_overview_layer)
	_effect_overview = overview_scene.instantiate() as CardEffectOverviewUI
	_effect_overview_layer.add_child(_effect_overview)


func _on_effect_card_hovered(card: Card3D) -> void:
	if _loss_exit_running or _journal_input_blocked or is_offline_board_open():
		return
	if card.get_available_effects().is_empty():
		return
	_ensure_effect_overview()
	if _effect_overview != null:
		_effect_overview.show_for_card(card)


func _on_effect_card_unhovered(card: Card3D) -> void:
	if _effect_overview != null:
		_effect_overview.hide_overview(card)


# --- Klick-Handling ---------------------------------------------------------

func _on_card_clicked(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int,
	side: String,
	slot_index: int
) -> void:
	if _loss_exit_running or _journal_input_blocked or (_online_mode and _online_is_spectator):
		return
	if not (event is InputEventMouseButton and event.is_pressed()):
		return

	var mouse_event := event as InputEventMouseButton

	var card := _get_card_from_slot(side, slot_index)
	if card == null:
		return

	# Snapshot/animation barriers lock every card interaction, including
	# inspect. Otherwise the client can focus a card that is replaced as soon
	# as the synchronized snapshot is released.
	if (
		(_online_mode and _online_action_in_progress)
		or (not _online_mode and _local_action_in_progress)
	):
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_inspect_card(card)
		return

	if _game_over:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _current_turn != "player":
		return

	if not _selected_event_uid.is_empty():
		_on_event_target_clicked(side, slot_index)
		return

	if side == "player":
		_select_player_card(slot_index)
	else:
		_try_attack_enemy(slot_index)

func _select_player_card(slot_index: int) -> void:
	if _journal_input_blocked or (_online_mode and _online_is_spectator):
		return
	var card: Card3D = _player_slots[slot_index]
	if card == null or not is_instance_valid(card):
		return

	if card.is_event_blocked():
		_set_event_notice("Diese Karte ist noch für %d eigene Züge blockiert.", [card.event_block_turns])
		return

	if _online_mode:
		var should_select := _selected_player_card != card
		var canonical_side := "player" if _online_is_host else "enemy"
		var canonical_slot := slot_index if should_select else -1

		if _online_is_host:
			_set_authoritative_online_selection(
				canonical_side if should_select else "",
				canonical_slot
			)
		else:
			# Apply immediately for responsive input. The host validates the request
			# and echoes the authoritative value back to both views.
			_apply_online_selection_visual(
				canonical_side if should_select else "",
				canonical_slot
			)
			_rpc_request_card_selection.rpc_id(1, canonical_slot, _online_turn_sequence)

		if should_select:
			_play_sfx(select_sfx)
			_set_match_status("Wähle nun die gegnerische Karte zum Angriff")
		else:
			_set_match_status("Du bist am Zug — wähle deine Karte")
		return

	if _selected_player_card == card:
		# Erneuter Klick auf dieselbe Karte hebt die Auswahl wieder auf.
		card.set_selected(false)
		_selected_player_card = null
		_set_match_status("Du bist am Zug — wähle deine Karte")
		return

	if _selected_player_card != null and is_instance_valid(_selected_player_card):
		_selected_player_card.set_selected(false)

	_selected_player_card = card
	card.set_selected(true)
	_play_sfx(select_sfx)
	_set_match_status("Wähle nun die gegnerische Karte zum Angriff")


func _try_attack_enemy(slot_index: int) -> void:
	if _journal_input_blocked or (_online_mode and _online_is_spectator):
		return
	if _selected_player_card == null:
		_set_match_status("Wähle zuerst eine eigene Karte")
		return

	var enemy_card: Card3D = _enemy_slots[slot_index]
	if enemy_card == null or not is_instance_valid(enemy_card) or enemy_card.is_dead():
		return
	var attacker: Card3D = _selected_player_card
	if not is_instance_valid(attacker) or attacker.is_dead():
		_selected_player_card = null
		return
	if attacker.is_event_blocked() or not _can_local_event_or_attack():
		return
	if not _online_mode:
		# Set this before yielding in _resolve_duel. Input events arriving in a
		# later frame can no longer launch a concurrent local duel.
		_local_action_in_progress = true

	_selected_player_card = null
	attacker.clear_selected_immediate()

	if _online_mode:
		var attacker_info := _find_slot_of(attacker)
		var attacker_slot := int(attacker_info.get("index", -1))
		if attacker_slot < 0:
			return

		_online_action_in_progress = true
		if _online_is_host:
			_set_authoritative_online_selection("", -1)
			await _resolve_duel(attacker, enemy_card, "player")
		else:
			_set_match_status("Aktion wird an den Host gesendet...")
			_rpc_request_attack.rpc_id(1, attacker_slot, slot_index, _online_turn_sequence)
		return

	var flow_generation := _match_generation
	await _resolve_duel(attacker, enemy_card, "player")
	# All normal paths synchronously change the turn before returning. If an
	# unexpected invalid-card path returned early, avoid leaving local input
	# permanently locked on an otherwise valid player turn.
	if (
		_is_current_match_flow(flow_generation, false)
		and _current_turn == "player"
	):
		_local_action_in_progress = false


# --- Kampf-Ablauf -----------------------------------------------------------

func _play_random_damage_coin(multiplier: float, generation: int, started_online: bool) -> void:
	var coin := RANDOM_DAMAGE_COIN_SCENE.instantiate()
	_random_damage_coins = _random_damage_coins.filter(func(item) -> bool: return is_instance_valid(item))
	_random_damage_coins.append(coin)
	add_child(coin)
	# Slots sit 0.095m above the table. Account for coin half-thickness.
	var landing := (player_slots_root.position + enemy_slots_root.position) * 0.5
	landing.y -= 0.055
	coin.play_flip(multiplier, landing, Vector3(-3.7, 0.9, 0.35))
	while is_instance_valid(coin) and not coin.result_revealed:
		if not _is_current_match_flow(generation, started_online):
			coin.queue_free()
			return
		await get_tree().process_frame
	if is_instance_valid(coin) and _is_current_match_flow(generation, started_online):
		# The attack starts on return; fading never delays combat.
		coin.dissolve()


func _clear_random_damage_coins() -> void:
	for coin: Node3D in _random_damage_coins:
		if is_instance_valid(coin):
			coin.queue_free()
	_random_damage_coins.clear()


# Both cards deal their damage at contact, even if either dies. attacker_side
# owns the chosen attack and determines which side receives the next turn.
func _resolve_duel(attacker: Card3D, defender: Card3D, attacker_side: String) -> void:
	_interrupt_journal()
	var started_online := _online_mode
	var flow_generation := _match_generation
	if _game_over:
		return

	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	if attacker.is_event_blocked() or attacker.is_dead() or defender.is_dead():
		return
	_selected_event_uid = ""

	if attacker.consume_stun():
		_set_match_status("%s ist betäubt und setzt aus!", [Localization.localized_arg(str(attacker.card_data.get("name", "?")))])
		_spawn_effect_vfx(attacker, stun_vfx_scene)
		await get_tree().create_timer(0.5).timeout
		if not _is_current_match_flow(flow_generation, started_online):
			return
		_end_turn_to("enemy" if attacker_side == "player" else "player")
		return

	var attacker_name := str(attacker.card_data.get("name", "?"))
	var defender_name := str(defender.card_data.get("name", "?"))
	_set_match_status("%s kämpft gegen %s!", [Localization.localized_arg(attacker_name), Localization.localized_arg(defender_name)])

	var defender_slot_index := int(_find_slot_of(defender).get("index", -1))

	var total_damage_done := 0
	var defender_died := false
	var any_defender_died := false
	var attacker_died := false
	var poisoned_targets: Dictionary = {}
	var damaged_targets: Dictionary = {}
	# A connected attack keeps its status payload even if its source is freed
	# during the counterattack/death presentation before this action finishes.
	var stun := CardData.get_effect(attacker.card_data, "stun")
	var stun_chance := clampf(float(stun.get("chance", 1.0)), 0.0, 1.0)
	var curse := CardData.get_effect(attacker.card_data, "curse")
	var hit_count := CombatResolver.get_hit_count(attacker)
	var eternal_sacrifice := CardData.has_effect(attacker.card_data, "eternal_suffering")
	var lava_targets: Array[Card3D] = []
	if CardData.has_effect(attacker.card_data, "lava"):
		# Keep object identities for the entire attack. Cards drawn into an
		# emptied slot must never become targets of a later strike.
		var opposing_slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
		for target in opposing_slots:
			if is_instance_valid(target) and not target.is_dead():
				lava_targets.append(target)

	for hit_index in range(hit_count):
		if not lava_targets.is_empty() and (not is_instance_valid(defender) or defender.is_dead()):
			defender = null
			for target in lava_targets:
				if is_instance_valid(target) and not target.is_dead():
					defender = target
					break
		if (
			not is_instance_valid(attacker)
			or not is_instance_valid(defender)
			or attacker.is_dead()
			or defender.is_dead()
		):
			break

		# One authoritative roll per strike, shared by the face and actual damage.
		var attack_multiplier := CombatResolver.roll_attack_multiplier(attacker)
		var online_attack_sequence := 0
		if _online_mode and _online_is_host:
			online_attack_sequence = _broadcast_online_attack(attacker, defender, attack_multiplier)
		if CardData.has_effect(attacker.card_data, "random_damage"):
			await _play_random_damage_coin(attack_multiplier, flow_generation, started_online)
			if not _is_current_match_flow(flow_generation, started_online):
				return
			if not is_instance_valid(attacker) or not is_instance_valid(defender):
				return

		attacker.play_attack_animation(defender.global_position)
		await attacker.attack_impact
		if not _is_current_match_flow(flow_generation, started_online):
			return
		# Kontakt ist der gemeinsame Taktgeber: Ton und Kamerastoss starten
		# unmittelbar, bevor in demselben Frame Schaden/VFX ausgewertet werden.
		_play_sfx(damage_sfx)
		_shake_camera()

		if _game_over or not is_instance_valid(attacker) or not is_instance_valid(defender):
			return

		var attacker_impact_position := attacker.global_position
		var defender_impact_position := defender.global_position
		var damage := CombatResolver.get_attack_damage(
			attacker,
			_count_identical_on_board(str(attacker.card_data.get("id", attacker.card_data.get("card_id", "")))),
			attack_multiplier
		)

		var eligible_guards: Variant = lava_targets if not lava_targets.is_empty() else null
		var hit_result := _resolve_attack_target_hit(attacker, defender, damage, poisoned_targets, eligible_guards)
		var guard_hits: Array[Dictionary] = []
		guard_hits.append_array(hit_result.get("guard_hits", []))
		if int(hit_result.get("damage", 0)) > 0:
			damaged_targets[defender] = true
		var defender_damage_taken := int(hit_result.get("damage", 0))
		defender_died = bool(hit_result.get("died", false))
		var poison_applied_this_hit := bool(hit_result.get("poison_applied", false))
		var damage_intensity := float(hit_result.get("damage_intensity", 0.45))
		total_damage_done += defender_damage_taken
		any_defender_died = any_defender_died or defender_died
		var additional_hits: Array[Dictionary] = []
		# No await between targets: all HP, shields and hit visuals change in
		# the same contact frame, before any counterattack or replacement.
		for target in lava_targets:
			if target == defender or not is_instance_valid(target) or target.is_dead():
				continue
			var target_hit := _resolve_attack_target_hit(attacker, target, damage, poisoned_targets, eligible_guards)
			additional_hits.append(target_hit)
			guard_hits.append_array(target_hit.get("guard_hits", []))
			if int(target_hit.get("damage", 0)) > 0:
				damaged_targets[target] = true
			total_damage_done += int(target_hit.get("damage", 0))
			any_defender_died = any_defender_died or bool(target_hit.get("died", false))

		var attacker_damage_taken := 0
		var attacker_result: Dictionary = {
			"shield_blocked": false,
			"survival_effect": "",
			"healed": 0,
			"damage_hits": [],
		}
		var all_hits: Array[Dictionary] = [hit_result]
		if eternal_sacrifice:
			# Sacrifice bypasses shields, armor and death saves. Its transferred
			# status was already applied by the hit, including blocked hits.
			var sacrifice_damage := attacker.current_hp
			attacker.take_damage(sacrifice_damage)
			attacker_damage_taken += sacrifice_damage
			attacker_result["damage_hits"].append(sacrifice_damage)
			_spawn_damage_number(attacker, sacrifice_damage)
			_award_event_for_death(attacker)
		all_hits.append_array(additional_hits)
		for target_hit in all_hits:
			attacker_damage_taken += _apply_attack_target_thorns(attacker, target_hit, attacker_result)
		var thorns_triggered := bool(hit_result.get("thorns_triggered", false))

		# Double/Triple Strike beschreibt mehrere Angreifer-Treffer, aber nur
		# einen Gegenschlag. Dornen bleiben dagegen an jeden echten Treffer
		# gekoppelt und wurden deshalb oben pro Schleifendurchlauf ausgewertet.
		if hit_index == 0 and is_instance_valid(attacker) and not attacker.is_dead() and is_instance_valid(defender) and not defender.is_event_blocked():
			var counter_damage := defender.attack_value
			var hp_before_counter := attacker.current_hp
			var counter_result := _apply_guarded_damage(attacker, counter_damage, defender)
			attacker_result["healed"] += int(counter_result.get("healed", 0))
			_present_healing(attacker, int(counter_result.get("healed", 0)), false)
			guard_hits.append_array(counter_result.get("guard_hits", []))
			if hp_before_counter > 0 and bool(counter_result.get("died", false)):
				_award_event_for_death(attacker)
			var counter_damage_taken := mini(maxi(int(counter_result.get("damage", 0)), 0), maxi(hp_before_counter, 0))
			attacker_damage_taken += counter_damage_taken
			if hp_before_counter > 0:
				_spawn_damage_number(attacker, counter_damage_taken)
				attacker_result["damage_hits"].append(counter_damage_taken)
			attacker_result["shield_blocked"] = bool(counter_result.get("shield_blocked", false))
			if str(counter_result.get("survival_effect", "")) != "":
				attacker_result["survival_effect"] = str(counter_result.get("survival_effect", ""))

			if bool(counter_result.get("shield_blocked", false)):
				_spawn_effect_vfx(attacker, shield_vfx_scene)

			if str(counter_result.get("survival_effect", "")) == "last_stand":
				_spawn_effect_vfx(attacker, last_stand_vfx_scene)

		attacker_died = not is_instance_valid(attacker) or attacker.is_dead()
		# Redirection can also damage another original Lava target. Freeze all
		# final states only after the simultaneous hit/counter has resolved.
		defender_died = defender.is_dead()
		hit_result["died"] = defender_died
		any_defender_died = any_defender_died or defender_died
		for target_hit in additional_hits:
			var target := target_hit.get("card") as Card3D
			target_hit["state"] = target.get_network_state()
			target_hit["died"] = target.is_dead()
			any_defender_died = any_defender_died or target.is_dead()
		for guard_hit in guard_hits:
			var guard := guard_hit.get("card") as Card3D
			guard_hit["state"] = guard.get_network_state()
			guard_hit["died"] = guard.is_dead()
			_present_guard_hit(guard_hit)
			if str(guard_hit.get("side", "")) != attacker_side:
				total_damage_done += int(guard_hit.get("damage", 0))
				any_defender_died = any_defender_died or guard.is_dead()

		if is_instance_valid(attacker):
			if attacker_damage_taken > 0:
				var counter_intensity := clampf(
					float(attacker_damage_taken) / maxf(float(attacker.max_hp), 1.0),
					0.35,
					1.35
				)
				_spawn_blood_from_card(attacker, counter_intensity, false)
			if attacker_died:
				_spawn_blood_decal_under_card(attacker, true, false)

		# Der Primaertreffer wird als ein einziges autoritatives Paket
		# praesentiert. Separate Blood-RPCs wuerden auf dem Client doppeln.
		if online_attack_sequence > 0:
			_broadcast_online_impact(
				attacker,
				defender,
				online_attack_sequence,
				defender_damage_taken,
				defender_died,
				hit_result,
				attacker_damage_taken,
				attacker_died,
				attacker_result,
				damage_intensity,
				poison_applied_this_hit,
				thorns_triggered,
				additional_hits,
				guard_hits
			)

		# Eine tote Abwehrkarte fliegt bereits im Kontakt-Frame weg. Das
		# Nachziehen beginnt, sobald die Karte den Slot freigegeben hat;
		# ihr restlicher Flug bleibt ein unabhaengiger visueller Effekt.
		if defender_died and is_instance_valid(defender):
			_remove_dead_card(defender, false, attacker_impact_position)
		for target_hit in additional_hits:
			var target := target_hit.get("card") as Card3D
			if bool(target_hit.get("died", false)) and is_instance_valid(target):
				_remove_dead_card(target, false, attacker_impact_position)
		for guard_hit in guard_hits:
			var guard := guard_hit.get("card") as Card3D
			if guard != attacker and guard.is_dead() and int(_find_slot_of(guard).get("index", -1)) >= 0:
				_remove_dead_card(guard, false, attacker_impact_position)

		if is_instance_valid(attacker):
			await attacker.attack_finished
			if not _is_current_match_flow(flow_generation, started_online):
				return

		if attacker_died and is_instance_valid(attacker):
			# Cleave belongs to the landed attack. Resolve it while the source
			# still occupies its slot so its kill rewards keep the correct owner.
			var cleave_result := _apply_cleave(attacker, defender_slot_index, attacker_side)
			total_damage_done += int(cleave_result.get("damage", 0))
			any_defender_died = any_defender_died or bool(cleave_result.get("died", false))
			_remove_dead_card(attacker, false, defender_impact_position)

		await _wait_for_pending_card_deaths()
		if not _is_current_match_flow(flow_generation, started_online):
			return
		if online_attack_sequence > 0:
			await _wait_for_online_attack_ack(online_attack_sequence)
			if not _is_current_match_flow(flow_generation, started_online):
				return

		await _wait_for_pending_online_blood()
		if not _is_current_match_flow(flow_generation, started_online):
			return

		if attacker_died or (defender_died and lava_targets.is_empty()):
			break

	# Surviving targets retain the completed hit's effects independently of
	# the attacker's survival. Object identities exclude replacement cards.
	for target: Card3D in damaged_targets:
		if not is_instance_valid(target) or target.is_dead():
			continue
		if not stun.is_empty() and (stun_chance >= 1.0 or _rng.randf() < stun_chance):
			target.stun_next_attack()
			_spawn_effect_vfx(target, stun_vfx_scene)
		if not curse.is_empty():
			target.apply_curse(int(curse.get("value", 2)))
			_spawn_effect_vfx(target, curse_vfx_scene)

	# Healing and another attack still require a living source.
	if attacker_died or not is_instance_valid(attacker):
		if _check_game_over():
			return
		_end_turn_to("enemy" if attacker_side == "player" else "player")
		return

	if is_instance_valid(attacker):
		var cleave_result := _apply_cleave(attacker, defender_slot_index, attacker_side)
		total_damage_done += int(cleave_result.get("damage", 0))
		any_defender_died = any_defender_died or bool(cleave_result.get("died", false))
		await _wait_for_pending_card_deaths()
		await _wait_for_pending_online_blood()
		if not _is_current_match_flow(flow_generation, started_online):
			return
		var lifesteal_heal := CombatResolver.heal_from_lifesteal(attacker, total_damage_done)
		if lifesteal_heal > 0:
			_spawn_heal_from_card(attacker, lifesteal_heal)

	if any_defender_died and is_instance_valid(attacker):
		if CardData.has_effect(attacker.card_data, "chain_attack"):
			var target_slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
			var next_target := _pick_random_living_card(target_slots)

			if next_target != null and is_instance_valid(next_target):
				await get_tree().create_timer(0.25).timeout
				if not _is_current_match_flow(flow_generation, started_online):
					return

				if is_instance_valid(attacker) and is_instance_valid(next_target):
					await _resolve_duel(attacker, next_target, attacker_side)
					return

	if _check_game_over():
		return

	_end_turn_to("enemy" if attacker_side == "player" else "player")


func _resolve_attack_target_hit(
	attacker: Card3D,
	target: Card3D,
	damage: int,
	poisoned_targets: Dictionary,
	eligible_guards: Variant = null
) -> Dictionary:
	var hp_before := target.current_hp
	var result := _apply_guarded_damage(target, damage, attacker, eligible_guards)
	var damage_taken := mini(maxi(int(result.get("damage", 0)), 0), maxi(hp_before, 0))
	if bool(result.get("shield_blocked", false)):
		_spawn_effect_vfx(target, shield_vfx_scene)
	if str(result.get("survival_effect", "")) == "last_stand":
		_spawn_effect_vfx(target, last_stand_vfx_scene)

	var poison_applied := false
	var poison_effect := CardData.get_effect(attacker.card_data, "poison")
	if damage_taken > 0 and not poisoned_targets.has(target) and not poison_effect.is_empty() and not bool(result.get("died", false)):
		target.apply_poison(int(poison_effect.get("damage", 3)), int(poison_effect.get("turns", 3)))
		_present_poison_application(target)
		poisoned_targets[target] = true
		poison_applied = true

	if damage_taken > 0 and not target.is_dead() and str(result.get("survival_effect", "")).is_empty() and CardData.has_effect(attacker.card_data, "execute"):
		var threshold := clampf(float(CardData.get_effect(attacker.card_data, "execute").get("threshold", 0.25)), 0.0, 1.0)
		if float(target.current_hp) <= float(target.max_hp) * threshold:
			var execute_result := CombatResolver.apply_damage_with_survival(target, target.current_hp)
			result["died"] = bool(execute_result.get("died", false))
			result["survival_effect"] = str(execute_result.get("survival_effect", ""))
			damage_taken += int(execute_result.get("damage", 0))
			result["healed"] = int(execute_result.get("healed", 0))
			if str(result["survival_effect"]) == "last_stand":
				_spawn_effect_vfx(target, last_stand_vfx_scene)

	if not target.is_dead() and CardData.has_effect(attacker.card_data, "eternal_suffering"):
		target.apply_eternal_suffering()
	var intensity := clampf(float(damage_taken) / maxf(1.0, float(target.max_hp)), 0.45, 1.6)
	_present_healing(target, int(result.get("healed", 0)), false)
	_spawn_damage_number(target, damage_taken)
	var cleave_brick: RigidBody3D
	if _uses_cleave_bricks(attacker):
		cleave_brick = _present_cleave_brick(target)
	if damage_taken > 0:
		_spawn_blood_from_card(target, intensity, false, 0, -1, false, cleave_brick)
	if bool(result.get("died", false)):
		_spawn_blood_decal_under_card(target, true, false)
		_award_event_for_death(target)
	var slot_info := _find_slot_of(target)
	result.merge({
		"card": target,
		"side": str(slot_info.get("side", "")),
		"slot": int(slot_info.get("index", -1)),
		"state": target.get_network_state(),
		"damage": damage_taken,
		"damage_intensity": intensity,
		"poison_applied": poison_applied,
		"thorns_triggered": false,
	}, true)
	return result


func _apply_attack_target_thorns(attacker: Card3D, target_hit: Dictionary, attacker_result: Dictionary) -> int:
	var target := target_hit.get("card") as Card3D
	if not is_instance_valid(attacker) or attacker.is_dead() or not is_instance_valid(target):
		return 0
	var damage_taken := int(target_hit.get("damage", 0))
	if damage_taken <= 0 or CardData.get_effect(target.card_data, "thorns").is_empty():
		return 0
	target_hit["thorns_triggered"] = true
	_spawn_effect_vfx(target, thorns_vfx_scene)
	var thorns := CardData.get_effect(target.card_data, "thorns")
	var reflected := maxi(roundi(float(damage_taken) * float(thorns.get("percent", 0.25))), 0)
	var result := CombatResolver.apply_damage_with_survival(attacker, reflected)
	# Thorns bypass armor/shield, while retaining one-use survival effects.
	var survival_effect := str(result.get("survival_effect", ""))
	if not survival_effect.is_empty():
		attacker_result["survival_effect"] = survival_effect
		if survival_effect == "last_stand":
			_spawn_effect_vfx(attacker, last_stand_vfx_scene)
	var reflected_damage := int(result.get("damage", 0))
	var healed := int(result.get("healed", 0))
	attacker_result["healed"] = int(attacker_result.get("healed", 0)) + healed
	_present_healing(attacker, healed, false)
	_spawn_damage_number(attacker, reflected_damage)
	if not attacker_result.has("damage_hits"):
		attacker_result["damage_hits"] = []
	attacker_result["damage_hits"].append(reflected_damage)
	if attacker.is_dead():
		_award_event_for_death(attacker)
	return reflected_damage


func _count_identical_on_board(card_id: String) -> int:
	var count := 0
	for card in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card) and not card.is_dead() and str(card.card_data.get("id", card.card_data.get("card_id", ""))) == card_id:
			count += 1
	return max(count, 1)


func _refresh_swarm_multipliers() -> void:
	# Derive presentation from the same living-copy count as attack damage.
	# This also covers refills, hatching/growth and mirrored online snapshots;
	# Card3D only rebuilds its suffix when the factor or base attack changes.
	for card: Card3D in _player_slots + _enemy_slots:
		if not is_instance_valid(card) or card.is_dead():
			continue
		if CardData.has_effect(card.card_data, "swarm_power"):
			card.set_swarm_multiplier(_count_identical_on_board(str(card.card_data.get("id", card.card_data.get("card_id", "")))))


func _apply_guarded_damage(target: Card3D, damage: int, source: Card3D, eligible_guards: Variant = null) -> Dictionary:
	# One adjacent guard intercepts the raw hit. Both cards then use their own
	# defenses; never recurse into another guard or redirect poison/thorns.
	if damage <= 0 or target.is_dead():
		return CombatResolver.apply_incoming_damage(target, damage)
	if target.consume_first_hit_shield():
		return {"damage": 0, "died": false, "shield_blocked": true, "survival_effect": ""}
	var info := _find_slot_of(target)
	var slots: Array[Card3D] = _player_slots if str(info.get("side", "")) == "player" else _enemy_slots
	var index := int(info.get("index", -1))
	var guard_hits: Array[Dictionary] = []
	if index >= 0:
		for neighbor_index in [index - 1, index + 1]:
			if neighbor_index < 0 or neighbor_index >= slots.size():
				continue
			var guard := slots[neighbor_index]
			if not is_instance_valid(guard) or guard.is_dead():
				continue
			# A newly drawn guard must not bypass Lava's original-target rule
			# by intercepting a later strike of the same attack.
			if eligible_guards is Array and not eligible_guards.has(guard):
				continue
			var effect := CardData.get_effect(guard.card_data, "bodyguard")
			if effect.is_empty():
				continue
			var redirected := roundi(float(damage) * clampf(float(effect.get("percent", 0.5)), 0.0, 1.0))
			if redirected <= 0:
				continue
			damage -= redirected
			var guard_result := CombatResolver.apply_incoming_damage(guard, redirected)
			guard_result.merge({"card": guard, "side": str(info.get("side", "")), "slot": neighbor_index}, true)
			guard_hits.append(guard_result)
			if bool(guard_result.get("died", false)):
				_award_event_for_death(guard)
			break
	var result := CombatResolver.apply_damage_with_survival(target, CombatResolver.get_damage_after_armor(target, damage))
	result["guard_hits"] = guard_hits
	return result


func _present_guard_hit(hit: Dictionary, replicate_secondary: bool = false) -> void:
	var guard := hit.get("card") as Card3D
	if not is_instance_valid(guard):
		return
	var amount := int(hit.get("damage", 0))
	var intensity := clampf(float(amount) / maxf(float(guard.max_hp), 1.0), 0.25, 1.0)
	if replicate_secondary:
		_present_secondary_damage(guard, amount, intensity)
	else:
		_spawn_damage_number(guard, amount)
		if amount > 0:
			_spawn_blood_from_card(guard, intensity, false)
	if bool(hit.get("shield_blocked", false)):
		_spawn_effect_vfx(guard, shield_vfx_scene)
	if str(hit.get("survival_effect", "")) == "last_stand":
		_spawn_effect_vfx(guard, last_stand_vfx_scene)
	_present_healing(guard, int(hit.get("healed", 0)), replicate_secondary)


func _apply_cleave(attacker: Card3D, center_slot_index: int, attacker_side: String) -> Dictionary:
	var outcome := {"damage": 0, "died": false}
	if not CardData.has_effect(attacker.card_data, "cleave") or CardData.has_effect(attacker.card_data, "lava"):
		return outcome

	if center_slot_index == -1:
		return outcome

	var slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
	var center := center_slot_index

	if center == -1:
		return outcome

	var cleave := CardData.get_effect(attacker.card_data, "cleave")
	var side_damage := roundi(float(attacker.attack_value) * clampf(float(cleave.get("side_damage", 0.5)), 0.0, 1.0))
	var cleave_connected := false
	var guard_hits: Array[Dictionary] = []
	var victims: Array[Card3D] = []

	for idx in [center - 1, center + 1]:
		if idx < 0 or idx >= slots.size():
			continue

		var target := slots[idx]

		if target == null or not is_instance_valid(target) or target.is_dead():
			continue

		var hp_before := target.current_hp
		var result := _apply_guarded_damage(target, side_damage, attacker)
		guard_hits.append_array(result.get("guard_hits", []))
		var damage_taken := mini(maxi(int(result.get("damage", 0)), 0), maxi(hp_before, 0))
		outcome["damage"] += damage_taken
		if bool(result.get("shield_blocked", false)):
			_spawn_effect_vfx(target, shield_vfx_scene)
		if str(result.get("survival_effect", "")) == "last_stand":
			_spawn_effect_vfx(target, last_stand_vfx_scene)

		var cleave_intensity: float = clamp(
			float(damage_taken) / max(1.0, float(target.max_hp)),
			0.25,
			0.9
		)

		_present_secondary_damage(target, damage_taken, cleave_intensity, true)
		_present_healing(target, int(result.get("healed", 0)))
		if damage_taken > 0:
			cleave_connected = true
		if bool(result.get("died", false)):
			outcome["died"] = true
			_award_event_for_death(target)
			victims.append(target)
	for guard_hit in guard_hits:
		_present_guard_hit(guard_hit, true)
		outcome["damage"] += int(guard_hit.get("damage", 0))
		var guard := guard_hit.get("card") as Card3D
		if guard.is_dead():
			outcome["died"] = true
			if not victims.has(guard):
				victims.append(guard)
	for victim in victims:
		_spawn_blood_decal_under_card(victim, true, true, 0, attacker)
		_remove_dead_card(victim, false, attacker.global_position)

	if cleave_connected:
		_play_sfx(damage_sfx)
	return outcome


# Sucht Seite ("player"/"enemy") und Slot-Index der uebergebenen Karte.
# Gibt {"side": "", "index": -1} zurueck, wenn die Karte in keinem Slot
# (mehr) steckt.
func _find_slot_of(card: Card3D) -> Dictionary:
	for i: int in range(HAND_SIZE):
		if _player_slots[i] == card:
			return {"side": "player", "index": i}
		if _enemy_slots[i] == card:
			return {"side": "enemy", "index": i}
	return {"side": "", "index": -1}


# Entfernt eine gestorbene Karte sofort logisch aus ihrem Slot. Visuell
# fliegt sie weiter, waehrend kurz darauf eine Ersatzkarte nachrueckt.
# Sicher mehrfach aufrufbar.
func _remove_dead_card(
	card: Card3D,
	spawn_death_decal: bool = true,
	impact_origin: Vector3 = Vector3(INF, INF, INF),
	draw_replacement: bool = true
) -> void:
	_cancel_poison_syringes_for(card)
	var slot_info := _find_slot_of(card)
	var side: String = str(slot_info.get("side", ""))
	var slot_index: int = int(slot_info.get("index", -1))

	if slot_index == -1:
		return

	_award_event_for_death(card)

	# Only the authority creates replacements. Remote death presentations wait
	# for its snapshot, including hatches, instead of rolling another instance.
	draw_replacement = draw_replacement and (not _online_mode or _online_is_host)
	var replacement_data := _get_death_replacement_data(card) if draw_replacement else {}

	# Keep the canonical slot addressable until the host has replicated the
	# decal to the invited player's mirrored board.
	if spawn_death_decal and is_instance_valid(card):
		_spawn_blood_decal_under_card(card, true)

	if side == "player":
		_player_slots[slot_index] = null
	else:
		_enemy_slots[slot_index] = null

	_selected_player_card = null

	if is_instance_valid(card):
		if card.area != null:
			card.area.input_ray_pickable = false
		_play_sfx(kill_sfx)
		var death_tween := _animate_card_death(card, side, impact_origin)
		if death_tween != null:
			_card_death_sequence += 1
			var death_job := {
				"id": _card_death_sequence,
				"card": card,
				"tween": death_tween,
				"draw_tween": null,
				"blocks_presentation": true,
				"side": side,
				"slot_index": slot_index,
				"draw_replacement": draw_replacement,
				"replacement_data": replacement_data,
				"generation": _match_generation,
			}
			_pending_card_deaths.append(death_job)
			_complete_card_death_job(death_job)
			return

	if draw_replacement:
		_replace_dead_slot(side, slot_index, replacement_data)


func _get_death_replacement_data(card: Card3D) -> Dictionary:
	if _online_mode and not _online_is_host:
		return {}
	if not is_instance_valid(card) or not card.is_dead():
		return {}
	if str(card.card_data.get("id", card.card_data.get("card_id", ""))) != "eg":
		return {}
	# Resolve once while the dead egg still owns its slot. The pending death
	# job keeps this result; duplicate removals and peer snapshots never reroll.
	# A separate generator keeps cosmetic camera/blood randomness unrelated.
	if _egg_hatch_rng.randf() >= EGG_HATCH_CHANCE:
		return {}
	# A hatch is a fresh battle instance from the catalog. It neither requires
	# ownership nor grants a collection copy, and inherits none of the egg's state.
	return CardData.merge_card_and_instance(
		CardDatabase.get_card("chick"), CardData.create_instance("chick")
	)


func _replace_dead_slot(side: String, slot_index: int, replacement_data: Dictionary) -> Tween:
	if not replacement_data.is_empty():
		# Share the state-based spawner so authority and mirrored boards animate
		# the hatch in place instead of flying a card from the deck.
		return _spawn_card_from_network_state(side, slot_index, {
			"card_data": replacement_data, "spawn_kind": "egg_hatch",
		}, true)
	return _draw_to_slot(side, slot_index, true)


func _complete_card_death_job(death_job: Dictionary) -> void:
	var death_tween := death_job.get("tween") as Tween
	var expected_generation := int(death_job.get("generation", -1))
	while (
		expected_generation == _match_generation
		and death_tween != null
		and death_tween.is_valid()
		and death_tween.is_running()
		and death_tween.get_total_elapsed_time() < replacement_draw_delay
	):
		await get_tree().process_frame
	if expected_generation != _match_generation:
		_remove_card_death_job(int(death_job.get("id", -1)))
		return

	if expected_generation == _match_generation and bool(death_job.get("draw_replacement", false)):
		var side := str(death_job.get("side", ""))
		var slot_index := int(death_job.get("slot_index", -1))
		var replacement_state_sync_sequence := -1
		if side in ["player", "enemy"] and slot_index >= 0 and slot_index < HAND_SIZE:
			var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
			if slots[slot_index] == null:
				var draw_tween := _replace_dead_slot(side, slot_index, death_job.get("replacement_data", {}) as Dictionary)
				death_job["draw_tween"] = draw_tween
				# Send the snapshot as soon as the host starts drawing. The client
				# queues it until the attack clears the slot, then draws while the
				# cosmetic death flight continues on both machines.
				if _online_mode and _online_is_host:
					replacement_state_sync_sequence = _queue_online_replacement_state_sync()
				while (
					expected_generation == _match_generation
					and draw_tween != null
					and draw_tween.is_valid()
					and draw_tween.is_running()
				):
					await get_tree().process_frame
		if replacement_state_sync_sequence > 0:
			await _wait_for_online_state_ack(replacement_state_sync_sequence)

	# The turn/snapshot barrier only covers the short slot clearance and draw.
	# Keep tracking the remaining flight so reset/cinematics can clean it up.
	death_job["blocks_presentation"] = false
	while (
		expected_generation == _match_generation
		and death_tween != null
		and death_tween.is_valid()
		and death_tween.is_running()
	):
		await get_tree().process_frame
	_remove_card_death_job(int(death_job.get("id", -1)))


func _remove_card_death_job(job_id: int) -> void:
	for job_index in range(_pending_card_deaths.size() - 1, -1, -1):
		if int(_pending_card_deaths[job_index].get("id", -1)) == job_id:
			_pending_card_deaths.remove_at(job_index)
			return


func _wait_for_pending_card_deaths() -> void:
	var expected_generation := _match_generation
	while expected_generation == _match_generation and _has_pending_card_replacements():
		await get_tree().process_frame


func _has_pending_card_replacements() -> bool:
	for death_job: Dictionary in _pending_card_deaths:
		if bool(death_job.get("blocks_presentation", true)):
			return true
	return false

# Wird durch das "died"-Signal von Card3D ausgeloest. Die eigentliche
# Aufraeum-/Nachzieh-Logik passiert bereits synchron in _resolve_duel
# ueber _remove_dead_card, dieses Signal dient hier nur als zusaetzliche
# Absicherung/Erweiterungspunkt (z.B. fuer spaetere Death-Effekte) und
# loest selbst keine doppelte Verarbeitung aus.
func _on_card_died(_card: Card3D, _side: String, _slot_index: int) -> void:
	pass


# --- Zugwechsel & Gegner-KI --------------------------------------------------

func _prepare_chick_turn() -> void:
	_chick_turn_eligible.clear()
	if _online_mode and not _online_is_host:
		return
	# Only cards present at the start can survive this entire turn. A new
	# hatch or replacement must wait until the following turn to start aging.
	for card: Card3D in _player_slots + _enemy_slots:
		if is_instance_valid(card) and not card.is_dead() and str(card.card_data.get("id", "")) == "chick":
			_chick_turn_eligible[card.get_instance_id()] = true


func _advance_chick_growth() -> void:
	if _online_mode and not _online_is_host:
		return
	var eligible := _chick_turn_eligible.duplicate()
	_chick_turn_eligible.clear()
	var generation := _match_generation
	var growth_tweens: Array[Tween] = []
	for side: String in ["player", "enemy"]:
		var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
		for slot_index in range(HAND_SIZE):
			var card := slots[slot_index]
			if not is_instance_valid(card) or card.is_dead() or str(card.card_data.get("id", "")) != "chick":
				continue
			if not eligible.has(card.get_instance_id()):
				continue
			var survived := int(card.get_meta("chick_survived_turns", 0)) + 1
			card.set_meta("chick_survived_turns", survived)
			if survived < CHICK_GROWTH_TURNS:
				continue
			# Growth replaces a living card, so it never enters the death/kill
			# pipeline or consumes a draw. The Chicken has fresh authored stats.
			var data := CardData.merge_card_and_instance(CardDatabase.get_card("chicken"), CardData.create_instance("chicken"))
			if _inspected_card == card:
				_reset_camera()
			_on_effect_card_unhovered(card)
			if _selected_player_card == card:
				_selected_player_card = null
			card.clear_selected_immediate()
			card.hide()
			card.queue_free()
			var tween := _spawn_card_from_network_state(side, slot_index, {"card_data": data, "spawn_kind": "chick_growth"}, true)
			if tween != null:
				growth_tweens.append(tween)
				_chick_growth_tweens.append(tween)
	for tween: Tween in growth_tweens:
		while generation == _match_generation and tween.is_valid() and tween.is_running():
			await get_tree().process_frame
		_chick_growth_tweens.erase(tween)


func _end_turn_to(next_turn: String) -> void:
	var started_online := _online_mode
	var flow_generation := _match_generation
	await _advance_chick_growth()
	if not _is_current_match_flow(flow_generation, started_online):
		return
	_tick_event_blocks(_current_turn)
	_clear_rearrange_target()
	_tick_piss_visibility(_current_turn)
	_event_played_this_turn = false
	_selected_event_uid = ""
	if _online_mode and _online_is_host:
		_set_authoritative_online_selection("", -1)
	_current_turn = next_turn

	await _apply_start_turn_effects(next_turn)
	await _wait_for_pending_online_blood()
	if not _is_current_match_flow(flow_generation, started_online):
		return
	if _check_game_over():
		return

	_prepare_chick_turn()
	if _online_mode:
		if _online_is_host:
			_online_turn_sequence += 1
		_online_action_in_progress = true
		_update_status_for_current_turn()
		if _online_is_host:
			var state_sync_sequence := _sync_online_state(true)
			await _complete_online_state_barrier(
				_online_turn_sequence,
				state_sync_sequence
			)
		return

	if next_turn == "enemy":
		_local_action_in_progress = true
		_set_match_status("Gegner ist am Zug...")
		await get_tree().create_timer(enemy_turn_delay).timeout
		if not _is_current_match_flow(flow_generation, false) or _current_turn != "enemy":
			return
		_play_enemy_turn(flow_generation)
	else:
		_local_action_in_progress = false
		_update_status_for_current_turn()


func _update_status_for_current_turn() -> void:
	if _online_mode and _online_is_spectator:
		_set_match_status("Zuschauer · %s ist am Zug", [_get_fighter_name_argument(_current_turn)])
	elif _current_turn == "player":
		_set_match_status("Du bist am Zug — wähle deine Karte")
	else:
		_set_match_status("Gegner ist am Zug...")


func _is_current_match_flow(flow_generation: int, expected_online_mode: bool) -> bool:
	return (
		flow_generation == _match_generation
		and _online_mode == expected_online_mode
		and _table_state == TableState.PLAYING
		and not _game_over
	)


# Automatischer Gegner-Zug: waehlt zufaellig eine eigene lebende Karte
# und zufaellig eine Spieler-Karte als Ziel, komplett ohne Spieler-
# Interaktion.
func _play_enemy_turn(flow_generation: int = -1) -> void:
	if _game_over:
		return
	if flow_generation >= 0 and not _is_current_match_flow(flow_generation, false):
		return
	if not _online_mode and _current_turn != "enemy":
		return

	await _play_enemy_event()
	if _game_over or (flow_generation >= 0 and not _is_current_match_flow(flow_generation, false)):
		return
	var enemy_card: Card3D = _pick_random_attack_card(_enemy_slots)
	var target_card: Card3D = _pick_random_living_card(_player_slots)

	if enemy_card == null or target_card == null:
		# Sollte durch _check_game_over() eigentlich schon abgefangen
		# sein, aber zur Sicherheit hier nochmal pruefen.
		if not _check_game_over():
			_end_turn_to("player")
		return

	await _resolve_duel(enemy_card, target_card, "enemy")
	if (
		flow_generation >= 0
		and _is_current_match_flow(flow_generation, false)
		and _current_turn == "enemy"
	):
		_end_turn_to("player")


func _pick_random_living_card(slots: Array[Card3D]) -> Card3D:
	var candidates: Array[Card3D] = []
	for card: Card3D in slots:
		if card != null and is_instance_valid(card) and not card.is_dead():
			candidates.append(card)

	if candidates.is_empty():
		return null

	return candidates[_rng.randi_range(0, candidates.size() - 1)]


# --- Sieg-/Niederlage-Check --------------------------------------------------

# Eine Seite hat verloren, wenn sie weder Karten auf dem Tisch noch
# Karten im Deck hat. Gibt true zurueck, wenn das Spiel dadurch beendet
# wurde (damit der Aufrufer keine weitere Zug-Logik mehr ausfuehrt).
func _check_game_over() -> bool:
	if _game_over:
		return true

	var player_has_cards: bool = _has_any_card(_player_slots) or not _player_deck.is_empty()
	var enemy_has_cards: bool = _has_any_card(_enemy_slots) or not _enemy_deck.is_empty()

	if player_has_cards and enemy_has_cards:
		return false

	_game_over = true
	_table_state = TableState.GAME_OVER
	_local_action_in_progress = false

	if not player_has_cards and not enemy_has_cards:
		_last_match_outcome = MatchOutcome.DRAW
	elif not player_has_cards:
		_last_match_outcome = MatchOutcome.LOSS
	else:
		_last_match_outcome = MatchOutcome.WIN

	_set_satan_laughing(_last_match_outcome == MatchOutcome.LOSS)

	_grant_match_rewards()

	mode_buttons.visible = false
	difficulty_buttons.visible = false

	if _online_mode and _online_is_host:
		# Keep the final snapshot inside the existing presentation barrier. The
		# invited player confirms it before the shared exit protocol can begin, so
		# WIN/LOSS and the matching cinematic cannot get lost.
		_online_action_in_progress = true
		end_buttons.visible = false
		_finalize_online_game_over.call_deferred()
	else:
		_online_action_in_progress = false
		end_buttons.visible = true

	return true


func _finalize_online_game_over() -> void:
	if not _online_mode or not _online_is_host or not _game_over or _is_online_match_exiting():
		return
	var flow_generation := _match_generation
	var final_turn_sequence := _online_turn_sequence
	var state_sync_sequence := _sync_online_state(true)
	await _complete_online_state_barrier(final_turn_sequence, state_sync_sequence)

	if (
		flow_generation != _match_generation
		or not _online_mode
		or not _online_is_host
		or not _game_over
	):
		return

	_online_action_in_progress = false
	end_buttons.visible = true

func _has_any_card(slots: Array[Card3D]) -> bool:
	for card: Card3D in slots:
		if card != null and is_instance_valid(card):
			return true
	return false

func _get_card_from_slot(side: String, slot_index: int) -> Card3D:
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots

	if slot_index < 0 or slot_index >= slots.size():
		return null

	var card: Card3D = slots[slot_index]
	if card == null or not is_instance_valid(card):
		return null

	return card


func _toggle_inspect_card(card: Card3D) -> void:
	if _inspected_card == card:
		_reset_camera()
	else:
		_focus_camera_on_card(card)
		
func _focus_camera_on_card(card: Card3D) -> void:
	_interrupt_journal()
	if not is_instance_valid(card):
		return

	_inspected_card = card

	if _camera_tween != null:
		_camera_tween.kill()

	var target_pos := card.global_position + inspect_camera_offset
	var look_pos := card.global_position

	var target_transform := Transform3D(Basis(), target_pos)
	target_transform = target_transform.looking_at(look_pos, Vector3.UP)

	_camera_tween = create_tween()
	_camera_tween.tween_property(
		table_camera,
		"global_transform",
		target_transform,
		inspect_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
func _reset_camera() -> void:
	_interrupt_journal()
	_inspected_card = null

	if _camera_tween != null:
		_camera_tween.kill()

	var target: Transform3D = _camera_base_transform

	if _table_state == TableState.PLAYING or _table_state == TableState.GAME_OVER:
		target = _get_match_camera_transform()

	_camera_tween = create_tween()
	_camera_tween.tween_property(
		table_camera,
		"global_transform",
		target,
		inspect_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _setup_offline_modes() -> void:
	_offline_board = OFFLINE_BOARD.new()
	_offline_board.name = "OfflineBoard"
	_offline_board.camera = table_camera
	add_child(_offline_board)
	_offline_menu = _offline_board.menu
	_offline_menu.closed.connect(_show_main_menu)
	_offline_menu.story_requested.connect(_start_story_level)
	_offline_menu.training_requested.connect(_start_training_match)
	_training_hud = Node3D.new()
	_training_hud.name = "TrainingControls"
	add_child(_training_hud)
	_training_damage_log = Label3D.new()
	_training_damage_log.font = Localization.FONT
	_training_damage_log.font_size = 40
	_training_damage_log.pixel_size = 0.0016
	_training_damage_log.outline_size = 6
	_training_damage_log.modulate = Color("ffe2a1")
	_training_damage_log.position = Vector3(0, 0.26, 0)
	_training_damage_log.rotation_degrees.x = -90
	_training_hud.add_child(_training_damage_log)
	var button_scene := preload("res://scenes/Table3DButton.tscn")
	var entries := [["Training neu starten", _restart_training], ["Training verlassen", _show_main_menu]]
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var button := button_scene.instantiate() as Table3DButton
		button.name = "Restart" if index == 0 else "Leave"
		button.label_text = entry[0]
		button.scale = Vector3.ONE * 0.28
		button.position = Vector3(-0.55 if index == 0 else 0.55, 0.23, 0.50)
		button.pressed.connect(entry[1])
		_training_hud.add_child(button)
	_training_hud.hide()


func _leave_offline_modes() -> void:
	GameCurrency.set_training_session(self, false)
	_local_mode = "legacy"
	_story_level = 0
	_training_player.clear()
	_training_enemy.clear()
	if is_instance_valid(_offline_board):
		_offline_board.hide_board()
	if is_instance_valid(_training_hud):
		_training_hud.hide()


func _show_story_menu() -> void:
	if _online_mode or NetworkManager.has_active_session():
		return
	GameCurrency.set_training_session(self, false)
	_table_state = TableState.STORY_SELECT
	mode_buttons.hide()
	difficulty_buttons.hide()
	end_buttons.hide()
	_offline_menu.open_story()
	_open_offline_board()
	_set_match_status("Story")


func _show_training_menu() -> void:
	if _online_mode or NetworkManager.has_active_session():
		return
	_table_state = TableState.TRAINING_SETUP
	GameCurrency.set_training_session(self, true)
	mode_buttons.hide()
	difficulty_buttons.hide()
	end_buttons.hide()
	_offline_menu.open_training()
	_open_offline_board()
	_set_match_status("Training")


func _start_story_level(level: int) -> void:
	# Recheck at the start boundary as well as disabling the menu button.
	if _online_mode or NetworkManager.has_active_session() or _table_state != TableState.STORY_SELECT or not GameCurrency.is_story_level_unlocked(level) or DeckManager.is_empty():
		return
	_local_mode = "story"
	_story_level = level
	_offline_board.hide_board()
	_start_match()


func _start_training_match(indices: Array[int], enemies: Array[Dictionary]) -> void:
	if _online_mode or NetworkManager.has_active_session() or _table_state != TableState.TRAINING_SETUP:
		return
	var player := OFFLINE_RULES.training_player_deck(DeckManager.get_deck_card_data(), indices)
	var enemy := OFFLINE_RULES.training_enemy_deck(enemies)
	if player.size() != HAND_SIZE or enemy.size() != HAND_SIZE:
		return
	_local_mode = "training"
	_training_player = player
	_training_enemy = enemy
	GameCurrency.set_training_session(self, true)
	_offline_board.hide_board()
	_start_match()


func is_offline_board_open() -> bool:
	return is_instance_valid(_offline_board) and _offline_board.is_open()


func _open_offline_board() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
		_camera_tween = null
	_offline_board.show_board()
	# Standalone table scenes also work without the hub's focus controller.
	if not is_instance_valid(_offline_board.focus_controller):
		_camera_tween = create_tween().set_parallel(true)
		var pose: Transform3D = _offline_board.focus_marker.global_transform.orthonormalized()
		_camera_tween.tween_property(table_camera, "global_transform", pose, 0.30)
		_camera_tween.tween_property(table_camera, "fov", 49.0, 0.30)


func _restart_training() -> void:
	if _online_mode or _local_mode != "training":
		return
	end_buttons.hide()
	_start_match()


func _connect_menu_buttons() -> void:
	var ki_button: Table3DButton = mode_buttons.get_node("KIButton")
	var multiplayer_button: Table3DButton = mode_buttons.get_node("MultiplayerButton")

	ki_button.pressed.connect(_show_story_menu)
	mode_buttons.get_node("TrainingButton").pressed.connect(_show_training_menu)
	multiplayer_button.set_disabled(false)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)

	difficulty_buttons.get_node("EasyButton").pressed.connect(_on_difficulty_selected.bind("easy"))
	difficulty_buttons.get_node("NormalButton").pressed.connect(_on_difficulty_selected.bind("normal"))
	difficulty_buttons.get_node("HardButton").pressed.connect(_on_difficulty_selected.bind("hard"))
	difficulty_buttons.get_node("InsaneButton").pressed.connect(_on_difficulty_selected.bind("insane"))
	difficulty_buttons.get_node("BackButton").pressed.connect(_show_main_menu)

	end_buttons.get_node("ExitButton").pressed.connect(_on_exit_button_pressed)


func _connect_online_signals() -> void:
	if matchmaking_screen.has_signal("closed"):
		matchmaking_screen.connect("closed", _on_matchmaking_closed)

	if not NetworkManager.match_started.is_connected(_on_online_match_started):
		NetworkManager.match_started.connect(_on_online_match_started)
	if not NetworkManager.session_closing.is_connected(_on_online_session_closing):
		NetworkManager.session_closing.connect(_on_online_session_closing)
	if not NetworkManager.session_closed.is_connected(_on_online_session_closed):
		NetworkManager.session_closed.connect(_on_online_session_closed)
	if not NetworkManager.lobby_state_changed.is_connected(_on_online_lobby_state_changed):
		NetworkManager.lobby_state_changed.connect(_on_online_lobby_state_changed)


func _on_multiplayer_pressed() -> void:
	if _online_mode or _loss_exit_running or _character_creation_pending:
		return
	if SettingsManager.character_creation_completed:
		_show_multiplayer_menu()
		return
	if not is_instance_valid(multiplayer_character_customizer):
		multiplayer_character_customizer = CharacterCustomizer.new()
		multiplayer_character_customizer.name = "MultiplayerCharacterCustomizer"
		add_child(multiplayer_character_customizer)
		# Keep the editor above the hub's camera filters and online overlays.
		multiplayer_character_customizer.layer = 140
		multiplayer_character_customizer.closed.connect(_on_multiplayer_character_closed)
	_character_creation_pending = true
	_character_creation_paused_tree = not get_tree().paused and not NetworkManager.has_active_session()
	if _character_creation_paused_tree:
		get_tree().paused = true
	multiplayer_character_customizer.open()


func _on_multiplayer_character_closed() -> void:
	if not _character_creation_pending:
		return
	_character_creation_pending = false
	if _character_creation_paused_tree:
		get_tree().paused = false
		_character_creation_paused_tree = false
	if SettingsManager.character_creation_completed:
		_show_multiplayer_menu()


func _show_multiplayer_menu() -> void:
	if _online_mode:
		return
	var board_was_open := is_offline_board_open()
	_leave_offline_modes()
	if board_was_open:
		_move_camera_to_base_view()

	_table_state = TableState.ONLINE_LOBBY
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false
	_set_match_status("Steam-Lobby")

	if matchmaking_screen.has_method("open"):
		matchmaking_screen.call("open")
	else:
		matchmaking_screen.visible = true


func _on_matchmaking_closed() -> void:
	if _online_mode:
		return
	_show_main_menu()


func _on_online_lobby_state_changed() -> void:
	if _online_mode or NetworkManager.current_lobby_id <= 0:
		return
	if _table_state in [TableState.MENU, TableState.STORY_SELECT, TableState.TRAINING_SETUP]:
		_show_multiplayer_menu()


func _on_online_match_started() -> void:
	if _online_mode or _loss_exit_running:
		return
	if (
		not NetworkManager.is_match_in_progress()
		or not NetworkManager.has_active_session()
		or not (NetworkManager.has_connected_opponent() or NetworkManager.is_local_spectator())
		or _table_state not in [TableState.MENU, TableState.ONLINE_LOBBY]
	):
		return
	_online_mode = true
	_online_is_host = NetworkManager.is_host
	_online_is_spectator = NetworkManager.is_local_spectator()
	_online_action_in_progress = true
	_online_disconnect_reason = ""
	_online_turn_sequence = 0
	_online_selected_side = ""
	_online_selected_slot = -1
	_reset_online_sync_tracking()

	if matchmaking_screen.has_method("close_without_leaving"):
		matchmaking_screen.call("close_without_leaving")
	else:
		matchmaking_screen.visible = false

	_start_online_match()


func _start_online_match() -> void:
	_online_character_retired = false
	_online_character_data = {}
	_online_second_character_data = {}
	_leave_offline_modes()
	_table_state = TableState.PLAYING
	_match_reward_difficulty = "normal"
	_last_match_outcome = MatchOutcome.NONE
	_match_reward_granted = false
	_reset_win_cinematic_visuals()
	_clear_match()
	_move_camera_to_match_view()
	_game_over = false
	_current_turn = "player"
	_online_turn_sequence = 1
	_selected_player_card = null
	_online_selected_side = ""
	_online_selected_slot = -1

	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false

	if not _online_is_host:
		_set_match_status("Host bereitet das Match vor...")
		_rpc_request_online_state.rpc_id(1)
		return

	var player_pool := _build_online_draw_pile(NetworkManager.local_player_data)
	var enemy_pool := _build_online_draw_pile(NetworkManager.remote_player_data)
	if player_pool.is_empty() or enemy_pool.is_empty():
		_set_match_status("Online-Match konnte nicht gestartet werden: Deck fehlt.")
		_game_over = true
		_table_state = TableState.GAME_OVER
		end_buttons.visible = true
		return

	_player_deck = player_pool
	_enemy_deck = enemy_pool
	_initialize_event_deck()
	_deal_starting_event_hands()

	for i: int in range(HAND_SIZE):
		_draw_to_slot("player", i, false)
		_draw_to_slot("enemy", i, false)

	_prepare_chick_turn()
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")
	_update_status_for_current_turn()
	var state_sync_sequence := _sync_online_state(true)
	await _complete_online_state_barrier(_online_turn_sequence, state_sync_sequence)


func _deck_from_player_payload(payload: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_deck: Variant = payload.get("deck", [])
	if not (raw_deck is Array):
		return result

	for entry: Variant in raw_deck:
		if entry is Dictionary and not (entry as Dictionary).is_empty() and CardData.is_combat_card(entry as Dictionary):
			result.append((entry as Dictionary).duplicate(true))
	return result


func _build_online_draw_pile(payload: Dictionary) -> Array[Dictionary]:
	var validated := NetworkManager._sanitize_remote_deck_payload(payload)
	var cards := _deck_from_player_payload(validated)
	return DeckManager.prepare_match_deck(cards, validated["starting_deck_indices"], int(validated["starting_hand_slots"]), deck_size)


func _on_online_session_closing() -> void:
	if not _online_mode:
		return
	_trace_exit_stage("session_closing")
	# Stop battle continuations before NetworkManager detaches the transport,
	# including replacement jobs currently waiting on their animation delay.
	_retire_online_battle_presentation()
	_online_action_in_progress = true
	_set_loss_interactions_enabled(false)


func _on_online_session_closed(reason: String) -> void:
	if not _online_mode:
		return
	_trace_exit_stage("session_closed")
	if _online_active_exit_sequence > 0:
		# A peer that vanishes during the agreed exit must not interrupt or reset
		# the local cinematic. Finish it and clean up locally instead.
		if not _online_exit_finalizing:
			_finalize_online_exit_local.call_deferred(_online_active_exit_sequence, _online_session_generation)
		return
	if _table_state not in [TableState.PLAYING, TableState.GAME_OVER]:
		return
	var preserve_spectator_result := (
		_online_is_spectator and _game_over and _online_disconnect_reason.is_empty()
	)

	_retire_online_battle_presentation()
	_online_disconnect_reason = reason
	_online_action_in_progress = false
	_online_selected_side = ""
	_online_selected_slot = -1
	_clear_online_selection_visuals()
	_game_over = true
	_table_state = TableState.GAME_OVER
	if not preserve_spectator_result:
		_set_match_status(reason if reason != "" else "Online-Verbindung wurde beendet.")
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = true
	if not _loss_exit_running:
		_set_loss_interactions_enabled(true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_attack(attacker_slot: int, target_slot: int, turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host or _game_over or _is_online_match_exiting():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender_id):
		return
	if _online_action_in_progress or _current_turn != "enemy" or turn_sequence != _online_turn_sequence:
		_sync_online_state()
		return
	if attacker_slot < 0 or attacker_slot >= HAND_SIZE or target_slot < 0 or target_slot >= HAND_SIZE:
		_sync_online_state()
		return

	var attacker: Card3D = _enemy_slots[attacker_slot]
	var defender: Card3D = _player_slots[target_slot]
	if attacker == null or defender == null or not is_instance_valid(attacker) or not is_instance_valid(defender):
		_sync_online_state()
		return
	if attacker.is_event_blocked() or attacker.is_dead() or defender.is_dead():
		_sync_online_state()
		return

	_set_authoritative_online_selection("", -1)
	_online_action_in_progress = true
	await _resolve_duel(attacker, defender, "enemy")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_card_selection(slot_index: int, turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host or _game_over or _is_online_match_exiting():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender_id):
		return

	# A client can only select its own canonical "enemy" card during its
	# current turn. It never supplies a side, so it cannot highlight host cards.
	if (
		_online_action_in_progress
		or _current_turn != "enemy"
		or turn_sequence != _online_turn_sequence
		or slot_index < -1
		or slot_index >= HAND_SIZE
	):
		_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot(0, sender_id))
		return

	if slot_index == -1:
		_set_authoritative_online_selection("", -1)
		return

	var card := _enemy_slots[slot_index]
	if card == null or not is_instance_valid(card) or card.is_dead() or card.is_event_blocked():
		_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot(0, sender_id))
		return

	_set_authoritative_online_selection("enemy", slot_index)


func _set_authoritative_online_selection(canonical_side: String, slot_index: int) -> void:
	if not _online_mode or not _online_is_host:
		return

	if canonical_side == "" or slot_index < 0:
		canonical_side = ""
		slot_index = -1
	elif (
		canonical_side not in ["player", "enemy"]
		or canonical_side != _current_turn
		or slot_index >= HAND_SIZE
	):
		return
	else:
		var card := _get_card_from_slot(canonical_side, slot_index)
		if card == null or not is_instance_valid(card) or card.is_dead() or card.is_event_blocked():
			return

	_online_selected_side = canonical_side
	_online_selected_slot = slot_index
	_apply_online_selection_visual(canonical_side, slot_index)

	if NetworkManager.has_connected_opponent():
		_rpc_apply_online_selection.rpc(
			canonical_side,
			slot_index,
			_online_turn_sequence
		)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_online_selection(
	canonical_side: String,
	slot_index: int,
	turn_sequence: int
) -> void:
	if not _has_live_online_client_session() or _game_over:
		return
	if turn_sequence != _online_turn_sequence:
		_rpc_request_online_state.rpc_id(1)
		return
	if canonical_side == "":
		if slot_index != -1:
			_rpc_request_online_state.rpc_id(1)
			return
	elif canonical_side not in ["player", "enemy"] or slot_index < 0 or slot_index >= HAND_SIZE:
		_rpc_request_online_state.rpc_id(1)
		return

	_online_selected_side = canonical_side
	_online_selected_slot = slot_index
	_apply_online_selection_visual(canonical_side, slot_index)


func _apply_online_selection_visual(canonical_side: String, slot_index: int) -> void:
	_clear_online_selection_visuals()
	if canonical_side == "" or slot_index < 0 or slot_index >= HAND_SIZE:
		return

	var local_side := _canonical_side_to_local(canonical_side)
	var card := _get_card_from_slot(local_side, slot_index)
	if card == null or not is_instance_valid(card):
		return

	card.set_selected(true)
	if local_side == "player":
		_selected_player_card = card


func _clear_online_selection_visuals() -> void:
	for card: Card3D in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card):
			card.clear_selected_immediate()
	_selected_player_card = null


func _reset_online_sync_tracking() -> void:
	_online_session_generation += 1
	_online_attack_sequence = 0
	_online_blood_sequence = 0
	_online_state_sync_sequence = 0
	_online_last_received_attack_sequence = 0
	_online_last_received_blood_sequence = 0
	_online_client_attack_phases.clear()
	_online_queued_blood_events.clear()
	_online_queued_impact_events.clear()
	_online_applied_impact_sequences.clear()
	_online_client_attack_contexts.clear()
	_online_client_presentation_depth = 0
	_online_queued_snapshot.clear()
	_online_pending_release_sequence = -1
	_online_queued_replacement_state_sync_sequence = 0
	_online_queued_replacement_state_turn_sequence = -1
	_online_exit_sequence = 0
	_online_active_exit_sequence = 0
	_online_exit_requested = false
	_online_exit_local_finished = false
	_online_exit_remote_finished = false
	_online_exit_finalize_acknowledged = false
	_online_exit_finalize_received = false
	_online_exit_coordinator_running = false
	_online_exit_finalizing = false
	_online_exit_deadline_msec = 0
	_online_exit_canonical_winner = ""
	_clear_online_sync_waits()


func _clear_online_sync_waits() -> void:
	_online_pending_attack_acks.clear()
	_online_pending_blood_acks.clear()
	_online_pending_state_acks.clear()


func _broadcast_online_attack(attacker: Card3D, defender: Card3D, attack_multiplier: float = 1.0) -> int:
	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if not NetworkManager.is_connected_game_peer(opponent_peer_id):
		return 0

	var attacker_info := _find_slot_of(attacker)
	var defender_info := _find_slot_of(defender)
	var attacker_side := str(attacker_info.get("side", ""))
	var defender_side := str(defender_info.get("side", ""))
	var attacker_slot := int(attacker_info.get("index", -1))
	var defender_slot := int(defender_info.get("index", -1))
	if attacker_side == "" or defender_side == "" or attacker_slot < 0 or defender_slot < 0:
		return 0

	_online_attack_sequence += 1
	var attack_sequence := _online_attack_sequence
	_online_pending_attack_acks[attack_sequence] = true
	_rpc_play_online_attack.rpc(
		attacker_side,
		attacker_slot,
		defender_side,
		defender_slot,
		_online_turn_sequence,
		attack_sequence,
		attack_multiplier
	)
	return attack_sequence


func _broadcast_online_impact(
	attacker: Card3D,
	defender: Card3D,
	attack_sequence: int,
	defender_damage_taken: int,
	defender_died: bool,
	defender_result: Dictionary,
	attacker_damage_taken: int,
	attacker_died: bool,
	attacker_result: Dictionary,
	damage_intensity: float,
	poison_applied: bool,
	thorns_triggered: bool,
	additional_hits: Array[Dictionary] = [],
	guard_hits: Array[Dictionary] = []
) -> void:
	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if attack_sequence <= 0 or not NetworkManager.is_connected_game_peer(opponent_peer_id):
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var attacker_info := _find_slot_of(attacker)
	var defender_info := _find_slot_of(defender)
	if int(attacker_info.get("index", -1)) < 0 or int(defender_info.get("index", -1)) < 0:
		return
	var lava_hits: Array[Dictionary] = []
	for target_hit in additional_hits:
		var network_hit := target_hit.duplicate()
		network_hit.erase("card")
		network_hit.erase("guard_hits")
		lava_hits.append(network_hit)
	var bodyguard_hits: Array[Dictionary] = []
	for guard_hit in guard_hits:
		var network_hit := guard_hit.duplicate()
		network_hit.erase("card")
		bodyguard_hits.append(network_hit)

	_rpc_play_online_impact.rpc({
		"turn_sequence": _online_turn_sequence,
		"attack_sequence": attack_sequence,
		"attacker_side": str(attacker_info.get("side", "")),
		"attacker_slot": int(attacker_info.get("index", -1)),
		"defender_side": str(defender_info.get("side", "")),
		"defender_slot": int(defender_info.get("index", -1)),
		"attacker_state": attacker.get_network_state(),
		"defender_state": defender.get_network_state(),
		"defender_damage": defender_damage_taken,
		"defender_died": defender_died,
		"defender_shield_blocked": bool(defender_result.get("shield_blocked", false)),
		"defender_survival_effect": str(defender_result.get("survival_effect", "")),
		"defender_healed": int(defender_result.get("healed", 0)),
		"attacker_damage": attacker_damage_taken,
		"attacker_damage_hits": attacker_result.get("damage_hits", []).duplicate(),
		"attacker_died": attacker_died,
		"attacker_shield_blocked": bool(attacker_result.get("shield_blocked", false)),
		"attacker_survival_effect": str(attacker_result.get("survival_effect", "")),
		"attacker_healed": int(attacker_result.get("healed", 0)),
		"damage_intensity": clampf(damage_intensity, 0.1, 2.0),
		"poison_applied": poison_applied,
		"thorns_triggered": thorns_triggered,
		"lava_hits": lava_hits,
		"guard_hits": bodyguard_hits,
	})


@rpc("authority", "call_remote", "reliable")
func _rpc_play_online_attack(
	canonical_attacker_side: String,
	attacker_slot: int,
	canonical_defender_side: String,
	defender_slot: int,
	turn_sequence: int,
	attack_sequence: int,
	attack_multiplier: float = 1.0
) -> void:
	if (
		not _has_live_online_client_session()
		or _game_over
		or turn_sequence != _online_turn_sequence
		or attack_sequence <= 0
	):
		return
	var presentation_generation := _match_generation
	if attack_sequence <= _online_last_received_attack_sequence:
		_send_online_attack_ack(turn_sequence, attack_sequence)
		return
	_interrupt_journal()
	_online_last_received_attack_sequence = attack_sequence
	_online_client_attack_phases[attack_sequence] = 0
	_online_action_in_progress = true

	var local_attacker_side := _canonical_side_to_local(canonical_attacker_side)
	var local_defender_side := _canonical_side_to_local(canonical_defender_side)
	var attacker := _get_card_from_slot(local_attacker_side, attacker_slot)
	var defender := _get_card_from_slot(local_defender_side, defender_slot)
	if attacker == null or defender == null or not is_instance_valid(attacker) or not is_instance_valid(defender):
		_online_client_attack_phases[attack_sequence] = 2
		_flush_queued_online_blood_events(attack_sequence)
		_send_online_attack_ack(turn_sequence, attack_sequence)
		return

	_online_client_presentation_depth += 1
	_online_client_attack_contexts[attack_sequence] = {
		"attacker": attacker,
		"defender": defender,
		"canonical_attacker_side": canonical_attacker_side,
		"attacker_slot": attacker_slot,
		"canonical_defender_side": canonical_defender_side,
		"defender_slot": defender_slot,
		"attacker_died": false,
		"defender_impact_position": defender.global_position,
		"lava_targets": (_player_slots if local_defender_side == "player" else _enemy_slots).duplicate(),
		"board_targets": {"player": _player_slots.duplicate(), "enemy": _enemy_slots.duplicate()},
	}
	attacker.clear_selected_immediate()
	if CardData.has_effect(attacker.card_data, "random_damage"):
		await _play_random_damage_coin(attack_multiplier, presentation_generation, true)
		if not _is_current_match_flow(presentation_generation, true):
			return
		if not is_instance_valid(attacker) or not is_instance_valid(defender):
			_finish_online_client_presentation()
			return
	attacker.play_attack_animation(defender.global_position, true)
	_set_match_status("%s greift %s an...", [
		Localization.localized_arg(str(attacker.card_data.get("name", "?"))),
		Localization.localized_arg(str(defender.card_data.get("name", "?"))),
	])

	await attacker.attack_impact
	if presentation_generation != _match_generation or not _online_mode:
		return
	_online_client_attack_phases[attack_sequence] = 1
	_try_present_online_impact(attack_sequence)
	_flush_queued_online_blood_events(attack_sequence)

	var impact_deadline := Time.get_ticks_msec() + ONLINE_VISUAL_SYNC_TIMEOUT_MSEC
	while not _online_applied_impact_sequences.has(attack_sequence):
		if (
			Time.get_ticks_msec() >= impact_deadline
			or not _online_mode
			or _online_is_host
			or not is_instance_valid(attacker)
			or not NetworkManager.is_connected_game_peer(1)
		):
			# Mark the sequence as handled-without-presentation so a packet that
			# arrives during the return flight cannot suddenly fire late effects.
			_online_applied_impact_sequences[attack_sequence] = false
			if is_instance_valid(attacker):
				attacker.release_attack_after_impact()
			break
		await get_tree().process_frame

	if is_instance_valid(attacker):
		await attacker.attack_finished
	if presentation_generation != _match_generation or not _online_mode:
		return

	var attack_context := _online_client_attack_contexts.get(attack_sequence, {}) as Dictionary
	if bool(attack_context.get("attacker_died", false)) and is_instance_valid(attacker):
		_remove_dead_card(
			attacker,
			false,
			attack_context.get("defender_impact_position", Vector3(INF, INF, INF)) as Vector3,
			false
		)
	await _wait_for_pending_card_deaths()
	if presentation_generation != _match_generation or not _online_mode:
		return
	_online_client_attack_phases[attack_sequence] = 2
	_flush_queued_online_blood_events(attack_sequence)
	_send_online_attack_ack(turn_sequence, attack_sequence)
	_online_queued_impact_events.erase(attack_sequence)
	_online_applied_impact_sequences.erase(attack_sequence)
	_online_client_attack_contexts.erase(attack_sequence)
	_finish_online_client_presentation()


@rpc("authority", "call_remote", "reliable")
func _rpc_play_online_impact(impact: Dictionary) -> void:
	if not _has_live_online_client_session():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkManager.is_connected_game_peer(sender_id):
		return

	var turn_sequence := int(impact.get("turn_sequence", -1))
	var attack_sequence := int(impact.get("attack_sequence", -1))
	if (
		turn_sequence != _online_turn_sequence
		or attack_sequence <= 0
		or _online_applied_impact_sequences.has(attack_sequence)
		or int(_online_client_attack_phases.get(attack_sequence, -1)) >= 2
		or (
			attack_sequence <= _online_last_received_attack_sequence
			and not _online_client_attack_phases.has(attack_sequence)
		)
	):
		return

	_online_queued_impact_events[attack_sequence] = impact.duplicate(true)
	_try_present_online_impact(attack_sequence)


func _try_present_online_impact(attack_sequence: int) -> void:
	if (
		_is_online_match_exiting()
		or int(_online_client_attack_phases.get(attack_sequence, -1)) != 1
		or _online_applied_impact_sequences.has(attack_sequence)
		or not _online_queued_impact_events.has(attack_sequence)
		or not _online_client_attack_contexts.has(attack_sequence)
	):
		return

	var impact := _online_queued_impact_events[attack_sequence] as Dictionary
	var context := _online_client_attack_contexts[attack_sequence] as Dictionary
	var attacker := context.get("attacker") as Card3D
	var defender := context.get("defender") as Card3D
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		_online_applied_impact_sequences[attack_sequence] = false
		_online_queued_impact_events.erase(attack_sequence)
		if is_instance_valid(attacker):
			attacker.release_attack_after_impact()
		return
	if (
		str(impact.get("attacker_side", "")) != str(context.get("canonical_attacker_side", ""))
		or int(impact.get("attacker_slot", -1)) != int(context.get("attacker_slot", -1))
		or str(impact.get("defender_side", "")) != str(context.get("canonical_defender_side", ""))
		or int(impact.get("defender_slot", -1)) != int(context.get("defender_slot", -1))
	):
		_online_applied_impact_sequences[attack_sequence] = false
		_online_queued_impact_events.erase(attack_sequence)
		attacker.release_attack_after_impact()
		return

	var attacker_state := impact.get("attacker_state", {}) as Dictionary
	var defender_state := impact.get("defender_state", {}) as Dictionary
	if (
		attacker_state.is_empty()
		or defender_state.is_empty()
		or not _online_card_matches_state(attacker, attacker_state)
		or not _online_card_matches_state(defender, defender_state)
		or not _validate_online_lava_hits(impact, context)
		or not _validate_online_guard_hits(impact, context)
	):
		_online_applied_impact_sequences[attack_sequence] = false
		_online_queued_impact_events.erase(attack_sequence)
		attacker.release_attack_after_impact()
		return

	# Deduplizieren, bevor irgendein Effekt gestartet wird.
	_online_applied_impact_sequences[attack_sequence] = true
	_online_queued_impact_events.erase(attack_sequence)

	_play_sfx(damage_sfx)
	_shake_camera()

	attacker.apply_network_state(attacker_state)
	defender.apply_network_state(defender_state)
	_present_healing(attacker, int(impact.get("attacker_healed", 0)), false)
	_present_healing(defender, int(impact.get("defender_healed", 0)), false)
	_present_online_guard_hits(impact)
	_present_online_lava_hits(impact, attacker.global_position)

	if bool(impact.get("defender_shield_blocked", false)):
		_spawn_effect_vfx(defender, shield_vfx_scene)
	if str(impact.get("defender_survival_effect", "")) == "last_stand":
		_spawn_effect_vfx(defender, last_stand_vfx_scene)
	if bool(impact.get("attacker_shield_blocked", false)):
		_spawn_effect_vfx(attacker, shield_vfx_scene)
	if str(impact.get("attacker_survival_effect", "")) == "last_stand":
		_spawn_effect_vfx(attacker, last_stand_vfx_scene)
	if bool(impact.get("poison_applied", false)):
		_present_poison_application(defender)
	if bool(impact.get("thorns_triggered", false)):
		_spawn_effect_vfx(defender, thorns_vfx_scene)

	var defender_damage := maxi(int(impact.get("defender_damage", 0)), 0)
	_spawn_damage_number(defender, defender_damage)
	var cleave_brick: RigidBody3D
	if _uses_cleave_bricks(attacker):
		cleave_brick = _present_cleave_brick(defender)
	if defender_damage > 0:
		_spawn_blood_from_card(
			defender,
			float(impact.get("damage_intensity", 1.0)),
			false, 0, -1, false, cleave_brick
		)

	var defender_died := bool(impact.get("defender_died", false))
	if defender_died:
		_spawn_blood_decal_under_card(defender, true, false)
		_remove_dead_card(defender, false, attacker.global_position, false)

	var attacker_damage := maxi(int(impact.get("attacker_damage", 0)), 0)
	# New packets preserve each reflection/counter separately. Older packets
	# contain only the combined total and cannot identify zero-damage contacts.
	var damage_hits: Variant = impact.get("attacker_damage_hits", null)
	if damage_hits is Array:
		for amount: Variant in damage_hits:
			if amount is int and amount >= 0:
				_spawn_damage_number(attacker, amount)
	elif attacker_damage > 0 or bool(impact.get("attacker_shield_blocked", false)):
		_spawn_damage_number(attacker, attacker_damage)
	if attacker_damage > 0 and is_instance_valid(attacker):
		var counter_intensity := clampf(
			float(attacker_damage) / maxf(float(attacker.max_hp), 1.0),
			0.35,
			1.35
		)
		_spawn_blood_from_card(attacker, counter_intensity, false)

	var attacker_died := bool(impact.get("attacker_died", false))
	if attacker_died and is_instance_valid(attacker):
		_spawn_blood_decal_under_card(attacker, true, false)
	for hit: Dictionary in impact.get("guard_hits", []):
		var guard := _get_card_from_slot(_canonical_side_to_local(str(hit.get("side", ""))), int(hit.get("slot", -1)))
		if is_instance_valid(guard) and guard != attacker and guard.is_dead():
			_spawn_blood_decal_under_card(guard, true, false)
			_remove_dead_card(guard, false, attacker.global_position, false)

	context["attacker_died"] = attacker_died
	context["defender_impact_position"] = defender.global_position
	_online_client_attack_contexts[attack_sequence] = context
	attacker.release_attack_after_impact()


func _validate_online_guard_hits(impact: Dictionary, context: Dictionary) -> bool:
	var hits: Variant = impact.get("guard_hits", [])
	if not hits is Array or hits.size() > HAND_SIZE * 2:
		return false
	var board: Dictionary = context.get("board_targets", {})
	for hit: Variant in hits:
		if not hit is Dictionary:
			return false
		var canonical_side := str(hit.get("side", ""))
		if canonical_side not in ["player", "enemy"]:
			return false
		var side := _canonical_side_to_local(canonical_side)
		var slot := int(hit.get("slot", -1))
		var originals: Array = board.get(side, [])
		if slot < 0 or slot >= originals.size():
			return false
		var guard := _get_card_from_slot(side, slot)
		var state: Variant = hit.get("state", {})
		if not is_instance_valid(guard) or guard != originals[slot] or not state is Dictionary or state.is_empty():
			return false
		if not CardData.has_effect(guard.card_data, "bodyguard") or not _online_card_matches_state(guard, state):
			return false
	return true


func _present_online_guard_hits(impact: Dictionary) -> void:
	# All records carry the FINAL state of their original instance, even if
	# one guard intercepted multiple Lava targets in this contact frame.
	for hit: Dictionary in impact.get("guard_hits", []):
		var guard := _get_card_from_slot(_canonical_side_to_local(str(hit.get("side", ""))), int(hit.get("slot", -1)))
		guard.apply_network_state(hit.get("state", {}) as Dictionary)
		var local_hit := hit.duplicate()
		local_hit["card"] = guard
		_present_guard_hit(local_hit)


func _validate_online_lava_hits(impact: Dictionary, context: Dictionary) -> bool:
	var raw_hits: Variant = impact.get("lava_hits", [])
	if not raw_hits is Array:
		return false
	var hits: Array = raw_hits
	if hits.is_empty():
		return true
	var attacker := context.get("attacker") as Card3D
	if not is_instance_valid(attacker) or not CardData.has_effect(attacker.card_data, "lava"):
		return false
	var original_targets := context.get("lava_targets", []) as Array
	var seen_slots: Dictionary = {int(impact.get("defender_slot", -1)): true}
	for raw_hit in hits:
		if not raw_hit is Dictionary:
			return false
		var target_hit: Dictionary = raw_hit
		var slot := int(target_hit.get("slot", -1))
		var canonical_side := str(target_hit.get("side", ""))
		if (
			canonical_side != str(impact.get("defender_side", ""))
			or slot < 0 or slot >= original_targets.size()
			or seen_slots.has(slot)
		):
			return false
		seen_slots[slot] = true
		var target := _get_card_from_slot(_canonical_side_to_local(canonical_side), slot)
		var state := target_hit.get("state", {}) as Dictionary
		if not is_instance_valid(target) or target != original_targets[slot] or state.is_empty():
			return false
		if not _online_card_matches_state(target, state):
			return false
	return true


func _present_online_lava_hits(impact: Dictionary, impact_origin: Vector3) -> void:
	# This runs inside the primary impact's generation/identity/deduplication
	# guard. Extra targets share its contact frame and never send more RPCs.
	for target_hit: Dictionary in impact.get("lava_hits", []):
		var target := _get_card_from_slot(
			_canonical_side_to_local(str(target_hit.get("side", ""))),
			int(target_hit.get("slot", -1))
		)
		target.apply_network_state(target_hit.get("state", {}) as Dictionary)
		_present_healing(target, int(target_hit.get("healed", 0)), false)
		_spawn_damage_number(target, maxi(int(target_hit.get("damage", 0)), 0))
		if bool(target_hit.get("shield_blocked", false)):
			_spawn_effect_vfx(target, shield_vfx_scene)
		if str(target_hit.get("survival_effect", "")) == "last_stand":
			_spawn_effect_vfx(target, last_stand_vfx_scene)
		if bool(target_hit.get("poison_applied", false)):
			_present_poison_application(target)
		if bool(target_hit.get("thorns_triggered", false)):
			_spawn_effect_vfx(target, thorns_vfx_scene)
		if int(target_hit.get("damage", 0)) > 0:
			_spawn_blood_from_card(target, float(target_hit.get("damage_intensity", 1.0)), false)
		if bool(target_hit.get("died", false)):
			_spawn_blood_decal_under_card(target, true, false)
			_remove_dead_card(target, false, impact_origin, false)


func _finish_online_client_presentation() -> void:
	_online_client_presentation_depth = maxi(_online_client_presentation_depth - 1, 0)
	if _is_online_match_exiting() or _online_client_presentation_depth > 0 or _online_queued_snapshot.is_empty():
		return
	var queued_snapshot := _online_queued_snapshot.duplicate(true)
	_online_queued_snapshot.clear()
	_apply_online_state_now.call_deferred(queued_snapshot, _match_generation)


func _send_online_attack_ack(turn_sequence: int, attack_sequence: int) -> void:
	var host_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if not NetworkManager.is_connected_game_peer(host_peer_id):
		return
	_rpc_ack_online_attack.rpc_id(host_peer_id, turn_sequence, attack_sequence)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_online_attack(turn_sequence: int, attack_sequence: int) -> void:
	if not _online_mode or not _online_is_host or turn_sequence != _online_turn_sequence:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender_id):
		return
	_online_pending_attack_acks.erase(attack_sequence)


func _wait_for_online_attack_ack(attack_sequence: int) -> void:
	var deadline := Time.get_ticks_msec() + ONLINE_VISUAL_SYNC_TIMEOUT_MSEC
	while _online_pending_attack_acks.has(attack_sequence):
		if (
			Time.get_ticks_msec() >= deadline
			or not _online_mode
			or not _online_is_host
			or not NetworkManager.has_connected_opponent()
		):
			_online_pending_attack_acks.erase(attack_sequence)
			break
		await get_tree().process_frame


func _broadcast_online_blood(
	card: Card3D,
	effect_type: String,
	intensity: float,
	is_kill: bool,
	attack_sequence: int,
	impact_source: Card3D = null,
	damage_amount: int = -1
) -> void:
	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if not NetworkManager.is_connected_game_peer(opponent_peer_id):
		return
	var slot_info := _find_slot_of(card)
	var canonical_side := str(slot_info.get("side", ""))
	var slot_index := int(slot_info.get("index", -1))
	if canonical_side not in ["player", "enemy"] or slot_index < 0 or slot_index >= HAND_SIZE:
		return
	var source_side := ""
	var source_slot := -1
	if impact_source != null and is_instance_valid(impact_source):
		var source_info := _find_slot_of(impact_source)
		source_side = str(source_info.get("side", ""))
		source_slot = int(source_info.get("index", -1))

	_online_blood_sequence += 1
	var blood_sequence := _online_blood_sequence
	_online_pending_blood_acks[blood_sequence] = true
	_rpc_play_online_blood.rpc(
		_online_turn_sequence,
		blood_sequence,
		attack_sequence,
		canonical_side,
		slot_index,
		effect_type,
		clampf(intensity, 0.1, 2.0),
		is_kill,
		source_side,
		source_slot,
		damage_amount,
		str(card.card_data.get("instance_id", ""))
	)


@rpc("authority", "call_remote", "reliable")
func _rpc_play_online_blood(
	turn_sequence: int,
	blood_sequence: int,
	attack_sequence: int,
	canonical_side: String,
	slot_index: int,
	effect_type: String,
	intensity: float,
	is_kill: bool,
	impact_source_side: String,
	impact_source_slot: int,
	damage_amount: int = -1,
	instance_id: String = ""
) -> void:
	if (
		not _has_live_online_client_session()
		or _game_over
		or turn_sequence != _online_turn_sequence
		or blood_sequence <= 0
		or attack_sequence < 0
		or canonical_side not in ["player", "enemy"]
		or slot_index < 0
		or slot_index >= HAND_SIZE
		or effect_type not in ["burst", "decal", "damage", "heal", "cleave_burst", "cleave_damage"]
		or damage_amount < -1
		or (effect_type in ["damage", "cleave_damage"] and damage_amount < 0)
		or (effect_type == "heal" and damage_amount <= 0)
	):
		return
	if blood_sequence <= _online_last_received_blood_sequence:
		_send_online_blood_ack(turn_sequence, blood_sequence)
		return
	_online_last_received_blood_sequence = blood_sequence

	var blood_event := {
		"turn_sequence": turn_sequence,
		"blood_sequence": blood_sequence,
		"canonical_side": canonical_side,
		"slot_index": slot_index,
		"effect_type": effect_type,
		"intensity": clampf(intensity, 0.1, 2.0),
		"is_kill": is_kill,
		"impact_source_side": impact_source_side,
		"impact_source_slot": impact_source_slot,
		"damage_amount": damage_amount,
		"instance_id": instance_id,
	}
	if attack_sequence > 0 and int(_online_client_attack_phases.get(attack_sequence, -1)) < 1:
		var queued_events: Array = _online_queued_blood_events.get(attack_sequence, [])
		queued_events.append(blood_event)
		_online_queued_blood_events[attack_sequence] = queued_events
		return
	_apply_online_blood_event(blood_event)


func _flush_queued_online_blood_events(attack_sequence: int) -> void:
	if int(_online_client_attack_phases.get(attack_sequence, -1)) < 1:
		return
	var queued_events: Array = _online_queued_blood_events.get(attack_sequence, [])
	_online_queued_blood_events.erase(attack_sequence)
	for event_value: Variant in queued_events:
		if event_value is Dictionary:
			_apply_online_blood_event(event_value as Dictionary)


func _apply_online_blood_event(blood_event: Dictionary) -> void:
	if _is_online_match_exiting():
		return
	var canonical_side := str(blood_event.get("canonical_side", ""))
	var local_side := _canonical_side_to_local(canonical_side)
	var slot_index := int(blood_event.get("slot_index", -1))
	var card := _get_card_from_slot(local_side, slot_index)
	var expected_instance := str(blood_event.get("instance_id", ""))
	if is_instance_valid(card) and (expected_instance.is_empty() or str(card.card_data.get("instance_id", "")) == expected_instance):
		var impact_origin := Vector3(INF, INF, INF)
		var source_side := str(blood_event.get("impact_source_side", ""))
		var source_slot := int(blood_event.get("impact_source_slot", -1))
		if source_side in ["player", "enemy"] and source_slot >= 0 and source_slot < HAND_SIZE:
			var source_card := _get_card_from_slot(
				_canonical_side_to_local(source_side),
				source_slot
			)
			if source_card != null and is_instance_valid(source_card):
				impact_origin = source_card.global_position
		match str(blood_event.get("effect_type", "")):
			"heal":
				# The existing reliable effect channel carries the actual gain;
				# snapshots still own HP and never create an extra healing popup.
				_present_healing(card, int(blood_event.get("damage_amount", 0)), false)
			"burst", "cleave_burst":
				var cleave_brick: RigidBody3D
				if str(blood_event.get("effect_type", "")) == "cleave_burst":
					cleave_brick = _present_cleave_brick(card)
				var damage_amount := int(blood_event.get("damage_amount", -1))
				if damage_amount >= 0:
					_spawn_damage_number(card, damage_amount)
				_spawn_blood_from_card(
					card,
					float(blood_event.get("intensity", 1.0)),
					false, 0, -1, false, cleave_brick
				)
			"damage", "cleave_damage":
				if str(blood_event.get("effect_type", "")) == "cleave_damage":
					_present_cleave_brick(card)
				var damage_amount := int(blood_event.get("damage_amount", -1))
				if damage_amount >= 0:
					_spawn_damage_number(card, damage_amount)
			"decal":
				_spawn_blood_decal_under_card(
					card,
					bool(blood_event.get("is_kill", false)),
					false
				)
				if bool(blood_event.get("is_kill", false)):
					# Cleave/Gift nutzen weiterhin den generischen Blood-Kanal. Auch
					# dort bleibt der Snapshot nur bis zur Slot-Freigabe gesperrt.
					_online_client_presentation_depth += 1
					_remove_dead_card(
						card,
						false,
						impact_origin,
						false
					)
					_finish_online_blood_death_event(blood_event)
					return
	_send_online_blood_ack(
		int(blood_event.get("turn_sequence", -1)),
		int(blood_event.get("blood_sequence", -1))
	)


func _finish_online_blood_death_event(blood_event: Dictionary) -> void:
	var presentation_generation := _match_generation
	await _wait_for_pending_card_deaths()
	if presentation_generation != _match_generation or not _online_mode:
		return
	_send_online_blood_ack(
		int(blood_event.get("turn_sequence", -1)),
		int(blood_event.get("blood_sequence", -1))
	)
	_finish_online_client_presentation()


func _send_online_blood_ack(turn_sequence: int, blood_sequence: int) -> void:
	var host_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if not NetworkManager.is_connected_game_peer(host_peer_id):
		return
	_rpc_ack_online_blood.rpc_id(host_peer_id, turn_sequence, blood_sequence)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_online_blood(turn_sequence: int, blood_sequence: int) -> void:
	if not _online_mode or not _online_is_host or turn_sequence != _online_turn_sequence:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender_id):
		return
	_online_pending_blood_acks.erase(blood_sequence)


func _wait_for_pending_online_blood() -> void:
	if _online_pending_blood_acks.is_empty():
		return
	var deadline := Time.get_ticks_msec() + ONLINE_VISUAL_SYNC_TIMEOUT_MSEC
	while not _online_pending_blood_acks.is_empty():
		if (
			Time.get_ticks_msec() >= deadline
			or not _online_mode
			or not _online_is_host
			or not NetworkManager.has_connected_opponent()
		):
			_online_pending_blood_acks.clear()
			break
		await get_tree().process_frame


func _canonical_side_to_local(canonical_side: String) -> String:
	if _online_is_host or _online_is_spectator:
		return canonical_side
	return "enemy" if canonical_side == "player" else "player"


func _sync_online_state(require_ready_ack: bool = false) -> int:
	if not _online_mode or not _online_is_host or not NetworkManager.has_connected_opponent():
		return 0
	var state_sync_sequence := 0
	if require_ready_ack:
		_online_state_sync_sequence += 1
		state_sync_sequence = _online_state_sync_sequence
		_online_pending_state_acks[state_sync_sequence] = _online_turn_sequence
	_broadcast_online_snapshot(state_sync_sequence)
	return state_sync_sequence


func _queue_online_replacement_state_sync() -> int:
	if not _online_mode or not _online_is_host or not NetworkManager.has_connected_opponent():
		return 0
	if (
		_online_queued_replacement_state_sync_sequence > 0
		and _online_queued_replacement_state_turn_sequence == _online_turn_sequence
	):
		return _online_queued_replacement_state_sync_sequence

	_online_state_sync_sequence += 1
	var state_sync_sequence := _online_state_sync_sequence
	var turn_sequence := _online_turn_sequence
	_online_pending_state_acks[state_sync_sequence] = turn_sequence
	_online_queued_replacement_state_sync_sequence = state_sync_sequence
	_online_queued_replacement_state_turn_sequence = turn_sequence
	_flush_online_replacement_state_sync.call_deferred(
		state_sync_sequence,
		turn_sequence,
		_match_generation
	)
	return state_sync_sequence


func _flush_online_replacement_state_sync(
	state_sync_sequence: int,
	turn_sequence: int,
	expected_generation: int
) -> void:
	# All simultaneous death jobs finish on the same animation frame. Waiting
	# one frame coalesces their replacement cards into one atomic snapshot.
	await get_tree().process_frame
	if (
		expected_generation != _match_generation
		or not _online_mode
		or not _online_is_host
		or turn_sequence != _online_turn_sequence
		or state_sync_sequence != _online_queued_replacement_state_sync_sequence
		or not NetworkManager.has_connected_opponent()
	):
		_online_pending_state_acks.erase(state_sync_sequence)
		if state_sync_sequence == _online_queued_replacement_state_sync_sequence:
			_online_queued_replacement_state_sync_sequence = 0
			_online_queued_replacement_state_turn_sequence = -1
		return

	_online_queued_replacement_state_sync_sequence = 0
	_online_queued_replacement_state_turn_sequence = -1
	_broadcast_online_snapshot(state_sync_sequence)


func _complete_online_state_barrier(turn_sequence: int, state_sync_sequence: int) -> void:
	await _wait_for_online_state_ack(state_sync_sequence)

	if (
		not _online_mode
		or not _online_is_host
		or _game_over
		or turn_sequence != _online_turn_sequence
	):
		return
	_online_action_in_progress = false
	_update_status_for_current_turn()
	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if NetworkManager.is_connected_game_peer(opponent_peer_id):
		_rpc_release_online_turn.rpc(turn_sequence)


func _wait_for_online_state_ack(state_sync_sequence: int) -> void:
	if state_sync_sequence <= 0:
		return
	var deadline := Time.get_ticks_msec() + ONLINE_VISUAL_SYNC_TIMEOUT_MSEC
	while _online_pending_state_acks.has(state_sync_sequence):
		if (
			Time.get_ticks_msec() >= deadline
			or not _online_mode
			or not _online_is_host
			or not NetworkManager.has_connected_opponent()
		):
			_online_pending_state_acks.erase(state_sync_sequence)
			break
		await get_tree().process_frame


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_online_state_applied(turn_sequence: int, state_sync_sequence: int) -> void:
	if not _online_mode or not _online_is_host or turn_sequence != _online_turn_sequence:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_online_opponent(sender_id):
		return
	if int(_online_pending_state_acks.get(state_sync_sequence, -1)) != turn_sequence:
		return
	_online_pending_state_acks.erase(state_sync_sequence)


@rpc("authority", "call_remote", "reliable")
func _rpc_release_online_turn(turn_sequence: int) -> void:
	if (
		not _has_live_online_client_session()
		or _game_over
	):
		return
	if turn_sequence < _online_turn_sequence:
		return
	if _online_client_presentation_depth > 0 or turn_sequence > _online_turn_sequence:
		_online_pending_release_sequence = maxi(
			_online_pending_release_sequence,
			turn_sequence
		)
		return
	_online_action_in_progress = false
	_update_status_for_current_turn()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_online_state() -> void:
	if not _online_mode or not _online_is_host or _is_online_match_exiting() or not NetworkManager.has_connected_opponent():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkManager.is_connected_game_peer(sender_id):
		return
	_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot(0, sender_id))


func _broadcast_online_snapshot(state_sync_sequence: int = 0) -> void:
	for peer_id in multiplayer.get_peers():
		if NetworkManager.is_connected_game_peer(peer_id):
			_rpc_apply_online_state.rpc_id(peer_id, _build_online_snapshot(state_sync_sequence, peer_id))


func _build_online_snapshot(state_sync_sequence: int = 0, recipient_peer_id: int = 0) -> Dictionary:
	var snapshot := {
		"current_turn": _current_turn,
		"turn_sequence": _online_turn_sequence,
		"state_sync_sequence": state_sync_sequence,
		"selected_side": _online_selected_side,
		"selected_slot": _online_selected_slot,
		"action_in_progress": _online_action_in_progress,
		"game_over": _game_over,
		"winner": _get_canonical_winner(),
		# Hidden draw order/card data stays on the authority. Clients only need
		# counts to render the two face-down piles.
		"player_deck_count": _player_deck.size(),
		"enemy_deck_count": _enemy_deck.size(),
		"player_slots": _serialize_online_slots(_player_slots),
		"enemy_slots": _serialize_online_slots(_enemy_slots),
		"event_deck_count": _event_deck.size(),
		"player_event_hand_count": _player_event_hand.size(),
		"enemy_event_hand_count": _enemy_event_hand.size(),
		"event_played_this_turn": _event_played_this_turn,
		"player_piss_turns": int(_piss_hidden_turns["player"]),
		"enemy_piss_turns": int(_piss_hidden_turns["enemy"]),
		"last_played_event": _last_played_event.duplicate(true),
		"last_event_side": _last_event_side,
		"event_play_sequence": _event_play_sequence,
	}
	# Public state and spectators never include private hand contents or draw order.
	if recipient_peer_id > 0 and _is_online_opponent(recipient_peer_id) and not NetworkManager.is_spectator_peer(recipient_peer_id):
		snapshot["own_event_hand"] = _enemy_event_hand.duplicate(true)
	return snapshot


func _serialize_online_slots(slots: Array[Card3D]) -> Array:
	var result: Array = []
	for card: Card3D in slots:
		if card == null or not is_instance_valid(card) or card.is_dead():
			result.append(null)
		else:
			var state := card.get_network_state()
			if card.get_meta("spawn_kind", "") in ["egg_hatch", "chick_growth"]:
				state["spawn_kind"] = card.get_meta("spawn_kind")
			result.append(state)
	return result


func _get_canonical_winner() -> String:
	if not _game_over:
		return ""
	var player_has_cards := _has_any_card(_player_slots) or not _player_deck.is_empty()
	var enemy_has_cards := _has_any_card(_enemy_slots) or not _enemy_deck.is_empty()
	if player_has_cards == enemy_has_cards:
		return "draw"
	return "player" if player_has_cards else "enemy"


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_online_state(state: Dictionary) -> void:
	if not _has_live_online_client_session():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkManager.is_connected_game_peer(sender_id):
		return
	var incoming_turn_sequence := int(state.get("turn_sequence", -1))
	if incoming_turn_sequence < _online_turn_sequence:
		return
	if _online_client_presentation_depth > 0:
		var queued_turn_sequence := int(
			_online_queued_snapshot.get("turn_sequence", -1)
		)
		if incoming_turn_sequence >= queued_turn_sequence:
			# A newer authoritative snapshot subsumes the queued one. Acknowledge
			# the superseded barrier so the host does not wait for a snapshot the
			# client deliberately will not animate separately.
			if not _online_queued_snapshot.is_empty():
				_send_online_state_ack(
					queued_turn_sequence,
					int(_online_queued_snapshot.get("state_sync_sequence", 0))
				)
			_online_queued_snapshot = state.duplicate(true)
		return
	_apply_online_state_now(state)


func _apply_online_state_now(state: Dictionary, expected_generation: int = -1) -> void:
	if expected_generation >= 0 and expected_generation != _match_generation:
		return
	if not _has_live_online_client_session():
		return
	if int(state.get("turn_sequence", -1)) < _online_turn_sequence:
		return
	_interrupt_journal()

	_table_state = TableState.PLAYING
	_online_client_attack_phases.clear()
	_online_queued_blood_events.clear()
	_online_queued_impact_events.clear()
	_online_applied_impact_sequences.clear()
	_online_client_attack_contexts.clear()

	# The host's canonical "enemy" side belongs to the client. Mirror both
	# decks and slot arrays so each player always interacts with the near side.
	# Existing card nodes are reconciled in place; rebuilding the whole table
	# here made every snapshot visibly blink on the invited player's machine.
	var animate_new_cards := _online_has_applied_snapshot
	var near_side := "player" if _online_is_spectator else "enemy"
	var far_side := "enemy" if _online_is_spectator else "player"
	_piss_hidden_turns["player"] = clampi(int(state.get(near_side + "_piss_turns", 0)), 0, 2)
	_piss_hidden_turns["enemy"] = clampi(int(state.get(far_side + "_piss_turns", 0)), 0, 2)
	_refresh_piss_visibility()
	_player_deck = _network_placeholder_deck(int(state.get(near_side + "_deck_count", 0)))
	_enemy_deck = _network_placeholder_deck(int(state.get(far_side + "_deck_count", 0)))
	_event_deck.clear()
	for _index in range(clampi(int(state.get("event_deck_count", 0)), 0, EVENT_DECK_RULES.DECK_SIZE)):
		_event_deck.append({})
	_player_event_hand.clear()
	_enemy_event_hand.clear()
	if not _online_is_spectator:
		var own_hand: Variant = state.get("own_event_hand", [])
		if own_hand is Array:
			for event: Variant in own_hand:
				if event is Dictionary:
					_player_event_hand.append(event.duplicate(true))
	_event_played_this_turn = bool(state.get("event_played_this_turn", false))
	_last_played_event = (state.get("last_played_event", {}) as Dictionary).duplicate(true)
	_last_event_side = str(state.get("last_event_side", ""))
	_event_play_sequence = int(state.get("event_play_sequence", 0))
	_present_played_event()
	if _event_played_this_turn or _event_from_hand("player", _selected_event_uid).is_empty():
		_clear_rearrange_target()
		_selected_event_uid = ""
	var draw_tweens: Array[Tween] = []
	draw_tweens.append_array(_reconcile_online_slots(
		"player",
		state.get(near_side + "_slots", []),
		animate_new_cards
	))
	draw_tweens.append_array(_reconcile_online_slots(
		"enemy",
		state.get(far_side + "_slots", []),
		animate_new_cards
	))
	_online_has_applied_snapshot = true
	_refresh_piss_visibility()
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")

	var canonical_turn := str(state.get("current_turn", "player"))
	_current_turn = _canonical_side_to_local(canonical_turn)
	_online_turn_sequence = int(state.get("turn_sequence", _online_turn_sequence))
	_online_selected_side = str(state.get("selected_side", ""))
	_online_selected_slot = int(state.get("selected_slot", -1))
	_game_over = bool(state.get("game_over", false))
	var snapshot_action_in_progress := bool(state.get("action_in_progress", false))
	var state_sync_sequence := int(state.get("state_sync_sequence", 0))
	_online_action_in_progress = snapshot_action_in_progress or not draw_tweens.is_empty() or Time.get_ticks_msec() < _event_reveal_deadline_msec
	if _online_selected_side != canonical_turn:
		_online_selected_side = ""
		_online_selected_slot = -1
	_apply_online_selection_visual(_online_selected_side, _online_selected_slot)

	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = _game_over and not _online_action_in_progress
	if _game_over:
		_table_state = TableState.GAME_OVER
		_apply_online_result(str(state.get("winner", "draw")))
	else:
		if _online_action_in_progress:
			_set_match_status("Synchronisiere Spielstand...")
		else:
			_update_status_for_current_turn()

	_complete_online_state_application(
		draw_tweens,
		_online_turn_sequence,
		_match_generation,
		state_sync_sequence,
		snapshot_action_in_progress,
		_game_over
	)


func _complete_online_state_application(
	draw_tweens: Array[Tween],
	turn_sequence: int,
	expected_generation: int,
	state_sync_sequence: int,
	snapshot_action_in_progress: bool,
	snapshot_game_over: bool
) -> void:
	for draw_tween: Tween in draw_tweens:
		while (
			expected_generation == _match_generation
			and draw_tween != null
			and draw_tween.is_valid()
			and draw_tween.is_running()
		):
			await get_tree().process_frame
	while expected_generation == _match_generation and Time.get_ticks_msec() < _event_reveal_deadline_msec:
		await get_tree().process_frame

	if (
		expected_generation != _match_generation
		or not _has_live_online_client_session()
		or turn_sequence != _online_turn_sequence
	):
		return

	_send_online_state_ack(turn_sequence, state_sync_sequence)

	if snapshot_game_over:
		# Keep the multiplayer peer marked as an active match until the shared
		# exit cinematic has completed on both machines. Otherwise the guest can
		# no longer request the exit after acknowledging this final snapshot.
		_online_action_in_progress = false
		end_buttons.visible = true
		return

	if _online_pending_release_sequence < turn_sequence:
		_online_pending_release_sequence = -1
	elif _online_pending_release_sequence == turn_sequence:
		_online_pending_release_sequence = -1
		_online_action_in_progress = false
		_update_status_for_current_turn()
	elif not snapshot_action_in_progress:
		_online_action_in_progress = false
		_update_status_for_current_turn()


func _send_online_state_ack(turn_sequence: int, state_sync_sequence: int) -> void:
	if state_sync_sequence <= 0:
		return
	var host_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if NetworkManager.is_connected_game_peer(host_peer_id):
		_rpc_ack_online_state_applied.rpc_id(
			host_peer_id,
			turn_sequence,
			state_sync_sequence
		)


func _has_live_online_client_session() -> bool:
	return (
		_online_mode
		and not _online_is_host
		and not _is_online_match_exiting()
		and NetworkManager.is_match_in_progress()
		and NetworkManager.has_active_session()
		and NetworkManager.is_connected_game_peer(1)
	)


func _is_online_match_exiting() -> bool:
	return _online_active_exit_sequence > 0 or _online_exit_finalizing


func _retire_online_battle_presentation() -> void:
	# The cinematic clears the board before the native peer is detached. Retire
	# battle callbacks now: late snapshots/impacts must never rebuild or touch
	# those cards while the separate exit handshake is still exchanging RPCs.
	_trace_exit_stage("retire_battle_presentation")
	_match_generation += 1
	_clear_switch_exchange()
	_clear_random_damage_coins()
	_clear_poison_syringes()
	_clear_cleave_bricks()
	for context: Dictionary in _online_client_attack_contexts.values():
		var attacker: Variant = context.get("attacker")
		if is_instance_valid(attacker):
			attacker.release_attack_after_impact()
	_online_client_attack_contexts.clear()
	_online_client_attack_phases.clear()
	_online_queued_impact_events.clear()
	_online_applied_impact_sequences.clear()
	_online_queued_blood_events.clear()
	_online_queued_snapshot.clear()
	_online_client_presentation_depth = 0
	_online_pending_release_sequence = -1
	_clear_online_sync_waits()


func _is_online_opponent(peer_id: int) -> bool:
	# Only the other fighter may send commands or release animation barriers.
	# Spectators receive the same presentation but never participate in its ACKs.
	return (
		NetworkManager.is_connected_game_peer(peer_id)
		and peer_id == NetworkManager.get_connected_opponent_peer_id()
	)


func _network_placeholder_deck(card_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Steel can move every opposing combat card into one player's draw pile.
	for _index in range(clampi(card_count, 0, deck_size * 2)):
		result.append({})
	return result


func _reconcile_online_slots(side: String, value: Variant, animate_new: bool) -> Array[Tween]:
	var draw_tweens: Array[Tween] = []
	var states: Array = value as Array if value is Array else []
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
	var moved_cards: Array[Card3D] = []
	# A pure slot exchange keeps both existing nodes and their battle presentation.
	for first in range(mini(states.size(), HAND_SIZE)):
		if not states[first] is Dictionary or not is_instance_valid(slots[first]) or _online_card_matches_state(slots[first], states[first]):
			continue
		for second in range(first + 1, mini(states.size(), HAND_SIZE)):
			if states[second] is Dictionary and is_instance_valid(slots[second]) and _online_card_matches_state(slots[second], states[first]) and _online_card_matches_state(slots[first], states[second]):
				moved_cards.append_array([slots[first], slots[second]])
				var move := _swap_event_slots(side, first, second, animate_new)
				if move != null:
					draw_tweens.append(move)
				break
	var draw_origin_count := _player_deck.size() if side == "player" else _enemy_deck.size()
	if animate_new:
		# Snapshot deck counts already exclude the incoming cards. Reconstruct
		# the old top so simultaneous replacements leave successive pile layers.
		for slot_index in range(mini(states.size(), HAND_SIZE)):
			if not states[slot_index] is Dictionary or (states[slot_index] as Dictionary).is_empty():
				continue
			if str((states[slot_index] as Dictionary).get("spawn_kind", "")) in ["egg_hatch", "chick_growth"]:
				continue
			if not is_instance_valid(slots[slot_index]) or not _online_card_matches_state(slots[slot_index], states[slot_index]):
				draw_origin_count += 1

	for slot_index in range(HAND_SIZE):
		var state: Dictionary = {}
		if slot_index < states.size() and states[slot_index] is Dictionary:
			state = states[slot_index] as Dictionary

		var existing := slots[slot_index]
		if state.is_empty():
			if existing != null and is_instance_valid(existing):
				existing.queue_free()
			slots[slot_index] = null
			continue

		if existing != null and is_instance_valid(existing) and _online_card_matches_state(existing, state):
			existing.apply_network_state(state)
			if not moved_cards.has(existing):
				existing.global_position = _get_slot_marker(side, slot_index).global_position
			existing.rotation_degrees = Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 180, 180)
			existing.scale = Vector3.ONE
			continue

		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		slots[slot_index] = null
		var draw_tween := _spawn_card_from_network_state(side, slot_index, state, animate_new, draw_origin_count)
		if draw_tween != null:
			draw_tweens.append(draw_tween)
			if str(state.get("spawn_kind", "")) not in ["egg_hatch", "chick_growth"]:
				draw_origin_count -= 1

	return draw_tweens


func _online_card_matches_state(card: Card3D, state: Dictionary) -> bool:
	var incoming_data := state.get("card_data", {}) as Dictionary
	var current_instance_id := str(card.card_data.get("instance_id", ""))
	var incoming_instance_id := str(incoming_data.get("instance_id", ""))
	if current_instance_id != "" or incoming_instance_id != "":
		return current_instance_id == incoming_instance_id
	return (
		str(card.card_data.get("id", card.card_data.get("card_id", ""))) == str(
			incoming_data.get("id", incoming_data.get("card_id", ""))
		)
		and bool(card.card_data.get("is_holo", false)) == bool(incoming_data.get("is_holo", false))
	)


func _spawn_card_from_network_state(
	side: String,
	slot_index: int,
	state: Dictionary,
	animated: bool = false,
	draw_origin_count: int = -1
) -> Tween:
	var card := card_scene.instantiate() as Card3D
	add_child(card)
	card.apply_network_state(state)
	var spawn_kind := str(state.get("spawn_kind", ""))
	var spawns_in_place := spawn_kind in ["egg_hatch", "chick_growth"]
	if spawns_in_place:
		# Keep presentation metadata out of card_data: a stolen card drawn
		# later is an ordinary deck draw, not a repeated hatch or growth.
		card.set_meta("spawn_kind", spawn_kind)
	var target_position := _get_slot_marker(side, slot_index).global_position
	var target_rotation := Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 180, 180)
	var draw_tween: Tween = null
	if animated:
		if draw_origin_count < 0:
			draw_origin_count = (_player_deck.size() if side == "player" else _enemy_deck.size()) + 1
		card.global_position = target_position if spawns_in_place else _get_stack_top_position(side, draw_origin_count)
		card.rotation_degrees = target_rotation
		card.scale = Vector3.ONE * 0.6
		_play_card_draw_sound(card)
		draw_tween = create_tween().set_parallel(true)
		if not spawns_in_place:
			draw_tween.tween_property(card, "global_position", target_position, draw_animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		draw_tween.tween_property(card, "scale", Vector3.ONE, draw_animation_duration).set_trans(Tween.TRANS_CUBIC if spawns_in_place else Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		card.global_position = target_position
		card.rotation_degrees = target_rotation
	card.died.connect(_on_card_died.bind(side, slot_index))
	_connect_card_input(card, side, slot_index)

	if side == "player":
		_player_slots[slot_index] = card
	else:
		_enemy_slots[slot_index] = card
	return draw_tween


func _apply_online_result(canonical_winner: String) -> void:
	if _online_is_spectator:
		_last_match_outcome = MatchOutcome.NONE
		if canonical_winner == "draw":
			_set_match_status("Zuschauer · Unentschieden")
		else:
			_set_match_status("Zuschauer · %s gewinnt!", [_get_fighter_name_argument(canonical_winner)])
		_set_satan_laughing(false)
		return
	var local_canonical_side := "player" if _online_is_host else "enemy"
	if canonical_winner == "draw":
		_last_match_outcome = MatchOutcome.DRAW
	elif canonical_winner in ["player", "enemy"]:
		_last_match_outcome = (
			MatchOutcome.WIN
			if canonical_winner == local_canonical_side
			else MatchOutcome.LOSS
		)
	else:
		push_warning("Online-Ergebnis enthält ungültigen Gewinner: %s" % canonical_winner)
		_last_match_outcome = MatchOutcome.NONE
		_set_match_status("Online-Ergebnis konnte nicht ausgewertet werden.")
		_set_satan_laughing(false)
		return

	_set_satan_laughing(_last_match_outcome == MatchOutcome.LOSS)
	_grant_match_rewards()


func _get_fighter_name_argument(canonical_side: String) -> Variant:
	for peer_id: int in NetworkManager.get_fighter_peer_ids():
		if (peer_id == 1) == (canonical_side == "player"):
			var player_data: Dictionary = NetworkManager.get_player_data_for_peer(peer_id)
			# A persona may itself be called "Host" or "Spieler". Only the
			# authored fallback is translated, never an existing player's name.
			return str(player_data["name"]) if player_data.has("name") else Localization.localized_arg("Spieler")
	return Localization.localized_arg("Host" if canonical_side == "player" else "Gast")


func _grant_match_rewards() -> void:
	if _online_is_spectator or _last_match_outcome == MatchOutcome.NONE:
		return
	if not _online_mode and _local_mode == "training":
		_match_reward_granted = true
		_match_status_is_reward = true
		_match_reward_text = Localization.text("Training beendet - keine Belohnungen")
		_match_status_message = _match_reward_text
		return
	if _match_reward_granted:
		_match_status_is_reward = true
		_match_status_message = _match_reward_text
		return
	var reward_outcome := "draw"
	var outcome_text := "Unentschieden"
	match _last_match_outcome:
		MatchOutcome.WIN:
			reward_outcome = "win"
			outcome_text = "Sieg!"
		MatchOutcome.LOSS:
			reward_outcome = "loss"
			outcome_text = "Niederlage"
	# Lock before emitting currency signals; repeated results and exit packets
	# cannot grant the same match twice. Only starting a new match resets it.
	_match_reward_granted = true
	var reward_difficulty := "normal" if _online_mode else _match_reward_difficulty
	if not _online_mode and _local_mode == "story":
		if reward_outcome == "win":
			_match_reward_data = GameCurrency.award_story_win(_story_level).duplicate(true)
			if _match_reward_data.is_empty():
				_match_reward_granted = false
				_set_match_status("Speichern fehlgeschlagen. Zum erneuten Speichern auf Exit klicken.")
				return
		else:
			_match_reward_data = {"xp_awarded": 0, "coins_reward": 0}
	else:
		_match_reward_data = GameCurrency.award_match(reward_outcome, reward_difficulty).duplicate(true)
	_match_reward_outcome_source = outcome_text
	_match_reward_text = _format_match_rewards()
	_match_status_is_reward = true
	_match_status_message = _match_reward_text

	var upgrade_ui := get_tree().get_first_node_in_group("upgrade_ui") as UpgradeUI
	if upgrade_ui != null:
		upgrade_ui.refresh_balance()


func _format_match_rewards() -> String:
	if not _online_mode and _local_mode == "training" and _match_reward_granted:
		return Localization.text("Training beendet - keine Belohnungen")
	if _match_reward_data.is_empty():
		return ""
	var result := Localization.format_text("%s · +%d XP · +%s Soul Coins", [
		Localization.localized_arg(_match_reward_outcome_source),
		int(_match_reward_data["xp_awarded"]), GameCurrency.format_coins(float(_match_reward_data["coins_reward"]), true)
	])
	if int(_match_reward_data.get("levels_gained", 0)) > 0:
		result += Localization.format_text("\nLevel %d! +%s Soul Coins", [
			int(_match_reward_data["new_level"]), GameCurrency.format_coins(float(_match_reward_data["coins_bonus"]), true)
		])
	return result


func _show_main_menu(keep_lingering_effects: bool = false) -> void:
	_leave_offline_modes()
	_table_state = TableState.MENU
	_last_match_outcome = MatchOutcome.NONE
	_reset_win_cinematic_visuals(keep_lingering_effects)
	_clear_match()
	_move_camera_to_base_view()
	_reset_dealer_gun()

	mode_buttons.visible = true
	difficulty_buttons.visible = false
	end_buttons.visible = false

	_set_match_status("Wähle einen Spielmodus")


func _show_difficulty_menu() -> void:
	_show_story_menu()


func _on_difficulty_selected(difficulty: String) -> void:
	_local_mode = "legacy"
	_selected_difficulty = difficulty

	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false

	_start_match()


func _clear_match() -> void:
	_training_hits.clear()
	if is_instance_valid(_training_hud):
		_training_hud.hide()
		_training_damage_log.text = ""
	_interrupt_journal()
	if _online_mode or _loss_exit_running:
		_trace_exit_stage("clear_board_begin")
	_match_generation += 1
	_clear_random_damage_coins()
	_clear_poison_syringes()
	_clear_cleave_bricks()
	_chick_turn_eligible.clear()
	for tween: Tween in _chick_growth_tweens:
		if tween.is_valid():
			tween.kill()
	_chick_growth_tweens.clear()
	_clear_event_match()
	_clear_damage_numbers()
	_match_reward_text = ""
	_match_reward_data.clear()
	_match_reward_outcome_source = ""
	_match_status_is_reward = false
	_local_action_in_progress = false
	for death_job: Dictionary in _pending_card_deaths:
		var death_tween := death_job.get("tween") as Tween
		if death_tween != null and death_tween.is_valid():
			death_tween.kill()
		var draw_tween := death_job.get("draw_tween") as Tween
		if draw_tween != null and draw_tween.is_valid():
			draw_tween.kill()
		var dying_card: Variant = death_job.get("card")
		if is_instance_valid(dying_card):
			dying_card.queue_free()
	_pending_card_deaths.clear()
	for card in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card):
			card.clear_selected_immediate()
			card.queue_free()

	for card in _player_stack_visuals + _enemy_stack_visuals:
		if card != null and is_instance_valid(card):
			card.queue_free()

	_player_slots = [null, null, null, null, null]
	_enemy_slots = [null, null, null, null, null]

	_player_deck.clear()
	_enemy_deck.clear()
	_player_stack_visuals.clear()
	_enemy_stack_visuals.clear()

	_selected_player_card = null
	_online_selected_side = ""
	_online_selected_slot = -1
	_game_over = false
	_online_has_applied_snapshot = false
	if _effect_overview != null:
		_effect_overview.hide_overview()
	if _online_mode or _loss_exit_running:
		_trace_exit_stage("clear_board_queued")

func _limit_deck_size(pool: Array[Dictionary], size: int) -> Array[Dictionary]:
	var limited: Array[Dictionary] = []
	var max_count: int = min(pool.size(), size)

	for i: int in range(max_count):
		limited.append(pool[i])

	return limited


func _move_camera_to_match_view() -> void:
	_interrupt_journal()
	if table_camera == null:
		return

	_inspected_card = null

	if _camera_tween != null:
		_camera_tween.kill()

	var target: Transform3D = _get_match_camera_transform()

	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	# A board uses a narrower field of view. The regular battle framing must
	# restore the complete camera state, including that optical zoom.
	_camera_tween.tween_property(table_camera, "fov", _camera_base_fov, match_camera_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	_camera_tween.tween_property(
		table_camera,
		"global_position",
		target.origin,
		match_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	_camera_tween.tween_method(
		_set_camera_quaternion,
		table_camera.global_transform.basis.get_rotation_quaternion(),
		target.basis.get_rotation_quaternion(),
		match_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _set_camera_quaternion(q: Quaternion) -> void:
	if not is_instance_valid(table_camera):
		return
	var t := table_camera.global_transform
	t.basis = Basis(q.normalized())
	table_camera.global_transform = t

func _move_camera_to_base_view() -> void:
	_interrupt_journal()
	if table_camera == null:
		return

	_inspected_card = null

	if _camera_tween != null:
		_camera_tween.kill()

	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(table_camera, "fov", _camera_base_fov, match_camera_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(
		table_camera,
		"global_transform",
		_camera_base_transform,
		match_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _move_camera_to_loss_view() -> void:
	_interrupt_journal()
	if table_camera == null or not is_instance_valid(table_camera):
		return
	if dealer_satan == null or not is_instance_valid(dealer_satan):
		return

	_inspected_card = null
	if _camera_tween != null:
		_camera_tween.kill()
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null

	var focus_position := dealer_satan.global_position + loss_camera_focus_offset
	# Die Richtung bleibt unabhaengig von Karten-Inspect und Rest-Shakes. Der
	# Tween startet trotzdem weich an der jeweils aktuellen Kameraposition.
	var approach_direction := _camera_base_transform.origin - focus_position
	if approach_direction.length_squared() < 0.0001:
		approach_direction = Vector3(0.0, 0.25, 1.0)

	var target_position := focus_position + approach_direction.normalized() * loss_camera_distance
	var target_transform := Transform3D(Basis.IDENTITY, target_position)
	target_transform = target_transform.looking_at(focus_position, Vector3.UP)
	var duration := maxf(loss_camera_approach_duration, 0.01)

	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(
		table_camera,
		"global_position",
		target_transform.origin,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_method(
		_set_camera_quaternion,
		table_camera.global_transform.basis.get_rotation_quaternion(),
		target_transform.basis.get_rotation_quaternion(),
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(
		table_camera,
		"fov",
		loss_camera_fov,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await _wait_for_tween(_camera_tween, duration + 0.5)


func _return_camera_to_player_view() -> void:
	if table_camera == null or not is_instance_valid(table_camera):
		return

	_inspected_card = null
	if _camera_tween != null:
		_camera_tween.kill()
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null

	var target_transform := _camera_base_transform
	var duration := maxf(loss_player_view_return_duration, 0.01)
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(
		table_camera,
		"global_position",
		target_transform.origin,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_method(
		_set_camera_quaternion,
		table_camera.global_transform.basis.get_rotation_quaternion(),
		target_transform.basis.get_rotation_quaternion(),
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(
		table_camera,
		"fov",
		_camera_base_fov,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await _wait_for_tween(_camera_tween, duration + 0.5)


func _swing_camera_to_base_view() -> Tween:
	if table_camera == null or not is_instance_valid(table_camera):
		return null

	if _camera_tween != null:
		_camera_tween.kill()

	var duration := maxf(loss_camera_return_duration, 0.01)
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(
		table_camera,
		"global_position",
		_camera_base_transform.origin,
		duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_method(
		_set_camera_quaternion,
		table_camera.global_transform.basis.get_rotation_quaternion(),
		_camera_base_transform.basis.get_rotation_quaternion(),
		duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(
		table_camera,
		"fov",
		_camera_base_fov,
		duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return _camera_tween


func _wait_for_tween(tween: Tween, timeout: float) -> void:
	var elapsed := 0.0
	while tween != null and tween.is_valid() and tween.is_running():
		if _loss_exit_running and _exit_skip_requested:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed >= timeout:
			tween.kill()
			break


func leave_table_view() -> void:
	if _table_state == TableState.ONLINE_LOBBY or _online_mode:
		_reset_online_sync_tracking()
		_online_mode = false
		_online_is_host = false
		_online_action_in_progress = false
		if NetworkManager.has_active_session():
			NetworkManager.leave_lobby("Lobby verlassen.")
		if matchmaking_screen.has_method("close_without_leaving"):
			matchmaking_screen.call("close_without_leaving")

	_move_camera_to_base_view()

	if _table_state == TableState.PLAYING or _table_state == TableState.GAME_OVER or _table_state == TableState.ONLINE_LOBBY:
		_show_main_menu()

func _get_match_camera_transform() -> Transform3D:
	if _online_mode and _online_is_spectator:
		return _get_spectator_camera_transform()
	if match_camera_marker == null:
		return _camera_base_transform

	var target: Transform3D = match_camera_marker.global_transform

	if match_camera_use_export_rotation:
		target.basis = Basis.from_euler(Vector3(
			deg_to_rad(match_camera_rotation.x),
			deg_to_rad(match_camera_rotation.y),
			deg_to_rad(match_camera_rotation.z)
		))

	return target


func _get_spectator_camera_transform() -> Transform3D:
	# Include the whole table and both draw piles, also in narrow windows.
	var table_basis := global_transform.basis.orthonormalized()
	var table_scale := global_transform.basis.get_scale().abs()
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var half_width := 4.5 * table_scale.x
	var half_depth := 2.85 * table_scale.z
	var fov := table_camera.fov if table_camera != null else 58.0
	var half_span := maxf(half_depth, half_width / maxf(aspect, 0.1))
	if table_camera != null and table_camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_span = maxf(half_width, half_depth * aspect)
	var height := half_span / tan(deg_to_rad(fov * 0.5))
	var center := to_global(Vector3(0.0, 0.2, 0.0))
	var camera_basis := table_basis * Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0))
	return Transform3D(camera_basis, center + table_basis.y * height)

func is_match_active() -> bool:
	return (
		_table_state in [TableState.STORY_SELECT, TableState.TRAINING_SETUP, TableState.ONLINE_LOBBY]
		or _table_state == TableState.PLAYING
		or _table_state == TableState.GAME_OVER
		# Both cinematics call _show_main_menu() before the network barrier is
		# released. Keep Main's camera rotation locked until both peers finished.
		or (_online_mode and _online_active_exit_sequence > 0)
	)

func _animate_card_death(
	card: Card3D,
	side: String,
	impact_origin: Vector3 = Vector3(INF, INF, INF)
) -> Tween:
	if not is_instance_valid(card):
		return null

	var start_transform := card.global_transform
	# Cancel a selection tween without snapping the dying card back to its slot.
	card.clear_selected_immediate()
	card.global_transform = start_transform
	var start_pos := start_transform.origin
	var smash_dir := Vector3.ZERO
	if impact_origin.is_finite():
		smash_dir = start_pos - impact_origin
		smash_dir.y = 0.0
	if smash_dir.length_squared() < 0.0001:
		# Ohne konkreten Angreifer (z.B. Gift) gerade von der gegnerischen
		# Tischhaelfte weg, nicht schraeg zu einem gemeinsamen Mittelpunkt.
		smash_dir = Vector3.BACK if side == "player" else Vector3.FORWARD
	smash_dir = smash_dir.normalized().rotated(Vector3.UP, _death_visual_rng.randf_range(-0.2, 0.2))
	var velocity := smash_dir * death_throw_speed + Vector3.UP * death_upward_speed
	var spin_axis := Vector3.UP.cross(smash_dir).normalized()
	var spin_speed := _death_visual_rng.randf_range(THROW_MOTION.MIN_SPIN_SPEED, THROW_MOTION.MAX_SPIN_SPEED)
	var flight_duration := maxf(death_flight_duration, 0.001)
	# Most of the fast throw leaves the table camera early. Finish dissolving
	# during that visible departure while retaining the flight's cleanup timing.
	var dissolve_duration := minf(maxf(death_dissolve_duration, 0.001), flight_duration)
	card.begin_death_dissolve()
	var tween := create_tween()
	tween.tween_method(
		func(elapsed: float) -> void:
			if is_instance_valid(card):
				card.global_transform = THROW_MOTION.transform_at(
					start_transform, Vector3.ZERO, velocity, spin_axis,
					spin_speed, death_gravity, elapsed
				)
				# One timeline keeps the dissolve attached to the tumbling card
				# and pauses/cleans it up together with the existing death flight.
				card.set_death_dissolve_progress(elapsed / dissolve_duration),
		0.0, flight_duration, flight_duration
	).set_trans(Tween.TRANS_LINEAR)

	tween.finished.connect(func():
		if is_instance_valid(card):
			card.queue_free()
	)
	return tween

func _play_sfx(sfx: AudioStreamPlayer) -> void:
	if sfx == null:
		return

	if sfx.playing:
		sfx.stop()

	sfx.play()

func _spawn_damage_number(card: Card3D, amount: int) -> void:
	if not _online_mode and _local_mode == "training" and is_instance_valid(card) and card.card_data.get("training_dummy", false):
		var slot := int(card.card_data.get("training_slot", 1))
		_training_hits.append(Localization.format_text("Trainingskarte %d - Schaden: %d", [slot, amount]))
		while _training_hits.size() > 5:
			_training_hits.pop_front()
		_training_damage_log.text = "\n".join(_training_hits)
	_spawn_combat_number(card, amount, false)


func _spawn_healing_number(card: Card3D, amount: int) -> void:
	if amount > 0:
		_spawn_combat_number(card, amount, true)


func _spawn_combat_number(card: Card3D, amount: int, healing: bool) -> void:
	if not _online_is_spectator and int(_piss_hidden_turns["player"]) > 0:
		return
	var training_target: bool = not _online_mode and _local_mode == "training" and is_instance_valid(card) and card.card_data.get("training_dummy", false) == true
	if not SettingsManager.damage_numbers_enabled and not training_target:
		return
	if not is_instance_valid(card) or amount < 0 or not is_inside_tree() or is_queued_for_deletion():
		return
	while _damage_numbers.size() >= MAX_DAMAGE_NUMBERS:
		var oldest := _damage_numbers.pop_front() as Node3D
		if is_instance_valid(oldest):
			_damage_number_lanes.erase(oldest.get_instance_id())
			oldest.hide()
			oldest.set_process(false)
			oldest.queue_free()
	var origin := card.global_position
	var unit_scale := maxf(card.global_basis.get_scale().abs().x, 0.001)
	var occupied_lanes: Dictionary = {}
	# At contact the attacker and defender are close together. Assign lanes
	# across nearby active hits, rather than independently for each card.
	for active in _damage_numbers:
		if not is_instance_valid(active) or active.is_queued_for_deletion():
			continue
		var active_origin: Vector3 = active.get_meta("damage_origin", Vector3(INF, INF, INF))
		if active_origin.distance_to(origin) < maxf(unit_scale, float(active.get_meta("damage_unit_scale", 1.0))):
			occupied_lanes[int(_damage_number_lanes.get(active.get_instance_id(), 0))] = true
	var lane := 0
	while occupied_lanes.has(lane):
		lane += 1
	var number := DAMAGE_NUMBER_SCRIPT.new()
	number.set_meta("damage_origin", origin)
	number.set_meta("damage_unit_scale", unit_scale)
	_damage_number_lanes[number.get_instance_id()] = lane
	_damage_numbers.append(number)
	add_child(number)
	number.tree_exiting.connect(func():
		_damage_number_lanes.erase(number.get_instance_id())
		_damage_numbers.erase(number)
	)
	if healing:
		number.show_healing(amount, origin, table_camera, lane, unit_scale)
	else:
		number.show_damage(amount, origin, table_camera, lane, unit_scale)


func _on_presentation_settings_changed() -> void:
	if not SettingsManager.damage_numbers_enabled:
		_clear_damage_numbers()


func _clear_damage_numbers() -> void:
	for number in _damage_numbers.duplicate():
		if is_instance_valid(number):
			number.hide()
			number.set_process(false)
			number.queue_free()
	_damage_numbers.clear()
	_damage_number_lanes.clear()


func _present_secondary_damage(card: Card3D, amount: int, intensity: float, cleave_hit: bool = false) -> void:
	_spawn_damage_number(card, amount)
	var cleave_brick: RigidBody3D
	if cleave_hit:
		cleave_brick = _present_cleave_brick(card)
	if amount > 0:
		_spawn_blood_from_card(card, intensity, true, 0, amount, cleave_hit, cleave_brick)
	elif _online_mode and _online_is_host:
		# A shielded cleave/zero poison tick still has a number, but no blood.
		_broadcast_online_blood(card, "cleave_damage" if cleave_hit else "damage", 0.0, false, 0, null, 0)


func _spawn_blood_from_card(
	card: Card3D,
	intensity: float = 1.0,
	replicate_online: bool = true,
	attack_sequence: int = 0,
	damage_amount: int = -1,
	cleave_hit: bool = false,
	cleave_brick: RigidBody3D = null
) -> void:
	if card == null or not is_instance_valid(card) or intensity <= 0.0:
		return
	# One visual damage event drives both the flying blood and the stain on
	# the card. Snapshots only restore gameplay state, so they never refresh it.
	card.show_blood_hit(intensity)
	if replicate_online and _online_mode and _online_is_host:
		_broadcast_online_blood(card, "cleave_burst" if cleave_hit else "burst", intensity, false, attack_sequence, null, damage_amount)
	if blood_burst_scene == null:
		return
	if is_instance_valid(cleave_brick):
		_spawn_cleave_impact_blood(cleave_brick, card.global_position + blood_spawn_offset, intensity)
		return
	_spawn_blood_burst_at(card.global_position + blood_spawn_offset, intensity)


func _spawn_cleave_impact_blood(brick: RigidBody3D, impact_position: Vector3, intensity: float) -> void:
	var generation := _match_generation
	var deadline := Time.get_ticks_msec() + 250
	while is_instance_valid(brick) and not brick.landed and not brick.kicked and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if generation != _match_generation or _is_online_match_exiting():
			return
	if generation != _match_generation or not is_instance_valid(brick) or brick.is_queued_for_deletion():
		return
	# Capture the hit position, not a subsequently moved/replaced card. Local
	# physics contact owns only this burst's timing, never damage or deaths.
	_spawn_blood_burst_at(impact_position, intensity)


func _spawn_blood_burst_at(impact_position: Vector3, intensity: float) -> void:
	if blood_burst_scene == null:
		return

	var blood := blood_burst_scene.instantiate() as Node3D
	if blood.has_method("set_intensity"):
		blood.set_intensity(intensity)
	add_child(blood)

	blood.global_transform = Transform3D(
		Basis(),
		impact_position
	)

func _spawn_blood_decal_under_card(
	card: Card3D,
	is_kill: bool = false,
	replicate_online: bool = true,
	attack_sequence: int = 0,
	impact_source: Card3D = null
) -> void:
	if blood_decal_scene == null:
		return

	if card == null or not is_instance_valid(card):
		return
	if replicate_online and _online_mode and _online_is_host:
		_broadcast_online_blood(
			card,
			"decal",
			1.0,
			is_kill,
			attack_sequence,
			impact_source
		)

	var decal := blood_decal_scene.instantiate() as Node3D
	if decal.has_method("setup"):
		decal.setup(is_kill)
	add_child(decal)

	# Card attacks and death throws change height. Anchor stains to the table,
	# independently of the card's current animation pose and the stain's size.
	var decal_position := to_local(card.global_position)
	var surface := get_node("table/Cube") as MeshInstance3D
	var surface_bounds := (global_transform.affine_inverse() * surface.global_transform) * surface.get_aabb()
	decal_position.y = surface_bounds.end.y
	decal.position = decal_position + blood_decal_offset
	decal.rotation_degrees = Vector3.ZERO

	# Zufällige Drehung, damit es nicht immer gleich aussieht.
	decal.rotate_y(_rng.randf_range(0.0, TAU))

func _present_healing(card: Card3D, amount: int, replicate_online: bool = true) -> void:
	if not is_instance_valid(card) or amount <= 0:
		return
	_spawn_healing_number(card, amount)
	_present_card_injection(card)
	if replicate_online and _online_mode and _online_is_host:
		# Keep replication independent of this peer's local number preference.
		_broadcast_online_blood(card, "heal", 1.0, false, 0, null, amount)


func _spawn_heal_from_card(card: Card3D, amount: int = 0) -> void:
	_present_healing(card, amount)
	_spawn_card_particle_burst(heal_burst_scene, card)

func _spawn_poison_from_card(card: Card3D) -> void:
	_spawn_card_particle_burst(poison_burst_scene, card)

func _spawn_card_particle_burst(scene: PackedScene, card: Card3D) -> void:
	if scene == null:
		return

	if card == null or not is_instance_valid(card):
		return

	var burst := scene.instantiate() as Node3D
	add_child(burst)
	burst.global_transform = Transform3D(
		Basis(),
		card.global_position + blood_spawn_offset
	)

func _present_poison_application(card: Card3D) -> void:
	_present_card_injection(card)


func _present_card_injection(card: Card3D) -> void:
	if not is_instance_valid(card) or card.is_dead():
		return
	_poison_syringes = _poison_syringes.filter(func(item) -> bool: return is_instance_valid(item))
	var syringe := POISON_SYRINGE_SCENE.instantiate()
	_poison_syringes.append(syringe)
	add_child(syringe)
	syringe.play_on(card)


func _cancel_poison_syringes_for(card: Card3D) -> void:
	for syringe: Node3D in _poison_syringes:
		if is_instance_valid(syringe) and syringe.is_for(card):
			syringe.cancel()


func _clear_poison_syringes() -> void:
	for syringe: Node3D in _poison_syringes:
		if is_instance_valid(syringe):
			syringe.queue_free()
	_poison_syringes.clear()


func _uses_cleave_bricks(attacker: Card3D) -> bool:
	return is_instance_valid(attacker) and CardData.has_effect(attacker.card_data, "cleave") and not CardData.has_effect(attacker.card_data, "lava")


func _present_cleave_brick(card: Card3D) -> RigidBody3D:
	if not is_instance_valid(card):
		return null
	_ensure_cleave_brick_surface()
	_cleave_bricks = _cleave_bricks.filter(func(item) -> bool: return is_instance_valid(item) and not item.is_queued_for_deletion())
	while _cleave_bricks.size() >= MAX_CLEAVE_BRICKS:
		var oldest: RigidBody3D = _cleave_bricks.pop_front()
		oldest.hide()
		oldest.queue_free()
	var brick := CLEAVE_BRICK_SCENE.instantiate() as RigidBody3D
	add_child(brick)
	_cleave_bricks.append(brick)
	brick.drop_on(card.global_position)
	return brick


func _ensure_cleave_brick_surface() -> void:
	if is_instance_valid(_cleave_brick_surface):
		return
	_cleave_brick_surface = StaticBody3D.new()
	_cleave_brick_surface.name = "LocalCleaveBrickSurface"
	_cleave_brick_surface.collision_layer = 1 << 11
	_cleave_brick_surface.collision_mask = 1 << 12
	_cleave_brick_surface.input_ray_pickable = false
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# This surface belongs exclusively to local cosmetics. Its top matches
	# the card plane; it never blocks card input or participates in combat.
	shape.size = Vector3(8.0, 0.12, 5.0)
	collision.shape = shape
	collision.position.y = player_slots_root.position.y - 0.06
	_cleave_brick_surface.add_child(collision)
	add_child(_cleave_brick_surface)


func _clear_cleave_bricks() -> void:
	for brick: RigidBody3D in _cleave_bricks:
		if is_instance_valid(brick):
			brick.hide()
			brick.set_process_unhandled_input(false)
			brick.queue_free()
	_cleave_bricks.clear()
	if is_instance_valid(_cleave_brick_surface):
		_cleave_brick_surface.queue_free()
	_cleave_brick_surface = null


func _spawn_effect_vfx(card: Card3D, scene: PackedScene) -> void:
	if scene == null:
		return

	if card == null or not is_instance_valid(card):
		return

	var vfx := scene.instantiate() as Node3D
	add_child(vfx)
	vfx.global_position = card.global_position + effect_vfx_offset


func _apply_start_turn_effects(side: String) -> void:
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
	var poisoned_at_turn_start := {}
	for card: Card3D in slots:
		if is_instance_valid(card) and int(card.get_meta("poison_turns", 0)) > 0:
			poisoned_at_turn_start[card] = true

	# Healing precedes periodic damage regardless of the healer's slot.
	for healer: Card3D in slots:
		if is_instance_valid(healer) and not healer.is_dead():
			_apply_neighbor_heal(healer)

	for card: Card3D in slots:
		if card == null or not is_instance_valid(card) or card.is_dead():
			continue

		var regen := CardData.get_effect(card.card_data, "regeneration")
		if not regen.is_empty():
			var hp_before_regen := card.current_hp
			card.heal(int(regen.get("value", 3)))
			_present_healing(card, maxi(card.current_hp - hp_before_regen, 0))
			_spawn_effect_vfx(card, regeneration_vfx_scene)

		if card.eternal_suffering_damage > 0:
			var suffering_result := CombatResolver.apply_damage_with_survival(card, card.eternal_suffering_damage)
			_present_healing(card, int(suffering_result.get("healed", 0)))
			_present_secondary_damage(card, int(suffering_result.get("damage", 0)), 0.7)
			if str(suffering_result.get("survival_effect", "")) == "last_stand":
				_spawn_effect_vfx(card, last_stand_vfx_scene)
			if card.is_dead():
				_remove_dead_card(card)
				continue
			card.advance_eternal_suffering()

		if poisoned_at_turn_start.has(card) and card.has_meta("poison_turns"):
			var turns := int(card.get_meta("poison_turns"))
			var damage := int(card.get_meta("poison_damage"))

			if turns > 0:
				var poison_result := CombatResolver.apply_damage_with_survival(card, damage)
				var died := bool(poison_result.get("died", false))
				if str(poison_result.get("survival_effect", "")) == "last_stand":
					_spawn_effect_vfx(card, last_stand_vfx_scene)
				_spawn_effect_vfx(card, poison_vfx_scene)
				var poison_damage_taken := int(poison_result.get("damage", 0))
				_present_healing(card, int(poison_result.get("healed", 0)))
				_present_secondary_damage(card, poison_damage_taken, clampf(
					float(poison_damage_taken) / maxf(float(card.max_hp), 1.0),
					0.25, 0.85
				))
				card.tick_poison()

				if died:
					_remove_dead_card(card)

			else:
				card.apply_poison(0, 0)

	await _wait_for_pending_card_deaths()

func _apply_neighbor_heal(damaged_card: Card3D) -> void:
	var slot_info := _find_slot_of(damaged_card)
	var side := str(slot_info.get("side", ""))
	var index := int(slot_info.get("index", -1))

	if side == "" or index == -1:
		return

	var heal_effect := CardData.get_effect(damaged_card.card_data, "neighbor_heal")
	if heal_effect.is_empty():
		return

	var heal_amount := int(heal_effect.get("value", 2))
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots

	for neighbor_index in [index - 1, index + 1]:
		if neighbor_index < 0 or neighbor_index >= slots.size():
			continue

		var neighbor := slots[neighbor_index]
		if neighbor == null or not is_instance_valid(neighbor):
			continue

		var hp_before_heal := neighbor.current_hp
		neighbor.heal(heal_amount)
		if heal_amount > 0 and not neighbor.is_dead():
			neighbor.cleanse_eternal_suffering_from_neighbor()
		_spawn_heal_from_card(neighbor, maxi(neighbor.current_hp - hp_before_heal, 0))

func _shake_camera(strength: float = impact_shake_strength, duration: float = impact_shake_duration) -> void:
	if table_camera == null:
		return

	if _shake_tween != null:
		_shake_tween.kill()

	var original_transform := table_camera.global_transform
	var original_rotation := table_camera.rotation_degrees

	var shake_offset := Vector3(
		_rng.randf_range(-strength, strength),
		_rng.randf_range(-strength, strength),
		_rng.randf_range(-strength, strength)
	)

	var shake_rot := Vector3(
		_rng.randf_range(-impact_shake_rot_strength, impact_shake_rot_strength),
		_rng.randf_range(-impact_shake_rot_strength, impact_shake_rot_strength),
		_rng.randf_range(-impact_shake_rot_strength, impact_shake_rot_strength)
	)

	_shake_tween = create_tween()
	_shake_tween.set_parallel(true)
	_shake_tween.tween_property(table_camera, "global_position", original_transform.origin + shake_offset, duration * 0.35)
	_shake_tween.tween_property(table_camera, "rotation_degrees", original_rotation + shake_rot, duration * 0.35)

	_shake_tween.chain()
	_shake_tween.set_parallel(true)
	_shake_tween.tween_property(table_camera, "global_position", original_transform.origin, duration * 0.65)
	_shake_tween.tween_property(table_camera, "rotation_degrees", original_rotation, duration * 0.65)

func _reset_dealer_gun() -> void:
	if flash_sprite != null and is_instance_valid(flash_sprite):
		flash_sprite.visible = false
	if dealer_gun == null or not is_instance_valid(dealer_gun):
		return

	if pistol_start_marker == null or not is_instance_valid(pistol_start_marker):
		return

	dealer_gun.global_transform = pistol_start_marker.global_transform


func _reset_win_cinematic_visuals(keep_lingering_effects: bool = false) -> void:
	if not keep_lingering_effects:
		_reset_win_blood()
		win_tinnitus_sfx.stop()
	if _win_shot_tween != null:
		_win_shot_tween.kill()
		_win_shot_tween = null
	win_shot_light.hide()
	win_shot_light.light_energy = 0.0
	if _player_gun_tween != null:
		_player_gun_tween.kill()
		_player_gun_tween = null
	if _satan_motion_tween != null:
		_satan_motion_tween.kill()
		_satan_motion_tween = null

	if player_muzzle_flash != null and is_instance_valid(player_muzzle_flash):
		player_muzzle_flash.visible = false
	if player_gun_mount != null and is_instance_valid(player_gun_mount):
		player_gun_mount.rotation = 0.0
		player_gun_mount.scale = Vector2.ONE
		player_gun_mount.modulate = Color.WHITE
		_set_player_gun_vertical_offset(win_gun_hidden_offset)
		player_gun_mount.visible = false

	if satan_motion_root != null and is_instance_valid(satan_motion_root):
		satan_motion_root.transform = _satan_motion_base_transform
	if dealer_satan != null and is_instance_valid(dealer_satan):
		dealer_satan.visible = _satan_base_visible
		dealer_satan.modulate = _satan_base_modulate

	_satan_hovered = false
	_set_satan_dying(false)
	if satan_hover_area != null and is_instance_valid(satan_hover_area):
		satan_hover_area.input_ray_pickable = not _loss_exit_running


func _reset_win_blood() -> void:
	if _win_blood_tween != null:
		_win_blood_tween.kill()
		_win_blood_tween = null
	if is_instance_valid(win_blood_sprite):
		win_blood_sprite.hide()
		win_blood_sprite.modulate.a = 0.0


func _show_win_blood() -> void:
	_reset_win_blood()
	if not is_instance_valid(win_blood_sprite):
		return
	win_blood_sprite.modulate.a = 1.0
	win_blood_sprite.show()
	_win_blood_tween = create_tween()
	_win_blood_tween.tween_interval(maxf(win_blood_hold_duration, 0.0))
	_win_blood_tween.tween_property(
		win_blood_sprite, "modulate:a", 0.0, maxf(win_blood_fade_duration, 0.01)
	)
	_win_blood_tween.tween_callback(win_blood_sprite.hide)


func _set_player_gun_vertical_offset(vertical_offset: float) -> void:
	if player_gun_mount == null or not is_instance_valid(player_gun_mount):
		return
	player_gun_mount.offset_top = vertical_offset
	player_gun_mount.offset_bottom = vertical_offset


func _start_win_shot_effects() -> void:
	if _win_shot_tween != null:
		_win_shot_tween.kill()
	# Rotate around the actual barrel tip, keeping the bright core on the gun.
	player_muzzle_flash.pivot_offset = player_muzzle_flash.size * 0.5
	var muzzle_position := player_gun_back.position + player_gun_back.size * Vector2(0.5, 0.176)
	player_muzzle_flash.position = muzzle_position - player_muzzle_flash.pivot_offset
	player_muzzle_flash.rotation = _rng.randf_range(-0.25, 0.25)
	player_muzzle_flash.modulate = Color.WHITE
	player_muzzle_flash.show()
	win_shot_light.global_position = table_camera.global_transform * Vector3(0.0, -0.1, -0.7)
	win_shot_light.light_energy = 8.0
	win_shot_light.show()
	_win_shot_tween = create_tween().set_parallel(true)
	_win_shot_tween.tween_property(player_muzzle_flash, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_win_shot_tween.tween_property(win_shot_light, "light_energy", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_win_shot_tween.chain().tween_callback(player_muzzle_flash.hide)
	_win_shot_tween.parallel().tween_callback(win_shot_light.hide)
	win_tinnitus_sfx.play()
	_shake_win_shot_camera()


func _shake_win_shot_camera() -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	var rest := table_camera.transform
	_shake_tween = create_tween()
	# Four diminishing jolts, then return to the exact pre-shot camera pose.
	for kick: Vector3 in [Vector3(0.6, 1.0, 0.2), Vector3(-0.5, -0.6, -0.1), Vector3(0.3, 0.35, 0.0), Vector3(-0.12, -0.15, 0.0)]:
		var pose := rest
		pose.origin += rest.basis * kick * win_shot_shake_strength
		pose.basis = rest.basis * Basis.from_euler(Vector3(kick.y, kick.x, kick.x * 0.6) * deg_to_rad(1.8))
		_shake_tween.tween_property(table_camera, "transform", pose, win_shot_shake_duration * 0.16).set_trans(Tween.TRANS_SINE)
	_shake_tween.tween_property(table_camera, "transform", rest, win_shot_shake_duration * 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _create_win_tinnitus_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 6.0
	const HOLD_DURATION := 1.5
	var samples := int(SAMPLE_RATE * DURATION)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for index in range(samples):
		var time := float(index) / SAMPLE_RATE
		# Hold the quiet ringing, then let it gently fade all the way to silence.
		var fade := clampf((time - HOLD_DURATION) / (DURATION - HOLD_DURATION), 0.0, 1.0)
		var envelope := minf(time / 0.008, 1.0) * pow(1.0 - fade, 1.5)
		var tone := sin(TAU * 3000.0 * time) + 0.12 * sin(TAU * 3170.0 * time)
		pcm.encode_s16(index * 2, int(tone * envelope * 14000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream


func _raise_player_gun() -> void:
	if player_gun_mount == null or not is_instance_valid(player_gun_mount):
		return
	if _player_gun_tween != null:
		_player_gun_tween.kill()

	player_gun_mount.visible = true
	player_gun_mount.rotation = 0.0
	_set_player_gun_vertical_offset(win_gun_hidden_offset)
	_player_gun_tween = create_tween()
	_player_gun_tween.tween_method(
		_set_player_gun_vertical_offset,
		win_gun_hidden_offset,
		0.0,
		maxf(win_gun_raise_duration, 0.01)
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _wait_for_tween(_player_gun_tween, win_gun_raise_duration + 0.5)


func _start_player_gun_recoil() -> Tween:
	if player_gun_mount == null or not is_instance_valid(player_gun_mount):
		return null
	if _player_gun_tween != null:
		_player_gun_tween.kill()

	var kick_duration := maxf(win_gun_recoil_duration, 0.01)
	_player_gun_tween = create_tween()
	_player_gun_tween.set_parallel(true)
	_player_gun_tween.tween_method(
		_set_player_gun_vertical_offset,
		0.0,
		-24.0,
		kick_duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_player_gun_tween.tween_property(
		player_gun_mount,
		"rotation",
		deg_to_rad(-2.5),
		kick_duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_player_gun_tween.chain().tween_method(
		_set_player_gun_vertical_offset,
		-24.0,
		0.0,
		kick_duration * 1.8
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_player_gun_tween.parallel().tween_property(
		player_gun_mount,
		"rotation",
		0.0,
		kick_duration * 1.8
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return _player_gun_tween


func _lower_player_gun() -> Tween:
	if player_gun_mount == null or not is_instance_valid(player_gun_mount):
		return null
	if _player_gun_tween != null:
		_player_gun_tween.kill()

	var start_offset := player_gun_mount.offset_top
	_player_gun_tween = create_tween()
	_player_gun_tween.set_parallel(true)
	_player_gun_tween.tween_method(
		_set_player_gun_vertical_offset,
		start_offset,
		win_gun_hidden_offset,
		maxf(win_gun_lower_duration, 0.01)
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_player_gun_tween.tween_property(
		player_gun_mount,
		"rotation",
		0.0,
		maxf(win_gun_lower_duration, 0.01)
	)
	return _player_gun_tween


func _hide_match_cards_for_win_shot() -> void:
	# Der Schuss passiert in der Nahaufnahme auf Satan. Die Karten werden in
	# genau diesem Frame nur unsichtbar geschaltet und erst beim abschliessenden
	# Menue-Reset freigegeben, damit keine laufende Animation tote Nodes erhaelt.
	for card: Card3D in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card):
			card.clear_selected_immediate()
			card.visible = false

	for stack_card: Card3D in _player_stack_visuals + _enemy_stack_visuals:
		if stack_card != null and is_instance_valid(stack_card):
			stack_card.visible = false

	for death_job: Dictionary in _pending_card_deaths:
		var dying_card: Variant = death_job.get("card")
		if is_instance_valid(dying_card):
			dying_card.visible = false

	_selected_player_card = null


func _start_satan_knockback() -> Tween:
	if (
		satan_motion_root == null
		or not is_instance_valid(satan_motion_root)
		or dealer_satan == null
		or not is_instance_valid(dealer_satan)
		or table_camera == null
		or not is_instance_valid(table_camera)
	):
		return null
	if _satan_motion_tween != null:
		_satan_motion_tween.kill()

	var start_global_position := satan_motion_root.global_position
	var knockback_direction := start_global_position - table_camera.global_position
	if knockback_direction.length_squared() < 0.0001:
		knockback_direction = -table_camera.global_basis.z
	knockback_direction = knockback_direction.normalized()
	var target_global_position := (
		start_global_position
		+ knockback_direction * win_satan_knockback_distance
		+ Vector3.UP * win_satan_knockback_lift
	)
	var motion_parent := satan_motion_root.get_parent() as Node3D
	var target_local_position := target_global_position
	if motion_parent != null:
		target_local_position = motion_parent.to_local(target_global_position)

	var duration := maxf(win_satan_knockback_duration, 0.01)
	var base_scale := _satan_motion_base_transform.basis.get_scale()
	_satan_motion_tween = create_tween().set_parallel(true)
	_satan_motion_tween.tween_property(
		satan_motion_root,
		"position",
		target_local_position,
		duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_satan_motion_tween.tween_property(
		satan_motion_root,
		"rotation_degrees",
		satan_motion_root.rotation_degrees + Vector3(-18.0, 12.0, 26.0),
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_satan_motion_tween.tween_property(
		satan_motion_root,
		"scale",
		base_scale * 0.18,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_satan_motion_tween.tween_property(
		dealer_satan,
		"modulate:a",
		0.0,
		duration * 0.65
	).set_delay(duration * 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return _satan_motion_tween


func _return_satan_from_below() -> void:
	if (
		satan_motion_root == null
		or not is_instance_valid(satan_motion_root)
		or dealer_satan == null
		or not is_instance_valid(dealer_satan)
	):
		return
	if _satan_motion_tween != null:
		_satan_motion_tween.kill()

	satan_motion_root.transform = _satan_motion_base_transform
	satan_motion_root.position = (
		_satan_motion_base_transform.origin
		+ Vector3(0.0, -win_satan_rise_depth, 0.0)
	)
	var base_scale := _satan_motion_base_transform.basis.get_scale()
	satan_motion_root.scale = base_scale * 0.82
	# The defeated opponent is already gone and this replacement is below view.
	_restore_standard_satan_for_exit()
	_set_satan_dying(false)
	dealer_satan.visible = true
	var hidden_modulate := _satan_base_modulate
	hidden_modulate.a = 0.0
	dealer_satan.modulate = hidden_modulate

	var duration := maxf(win_satan_return_duration, 0.01)
	_satan_motion_tween = create_tween().set_parallel(true)
	_satan_motion_tween.tween_property(
		satan_motion_root,
		"position",
		_satan_motion_base_transform.origin,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_satan_motion_tween.tween_property(
		satan_motion_root,
		"scale",
		base_scale,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_satan_motion_tween.tween_property(
		dealer_satan,
		"modulate:a",
		_satan_base_modulate.a,
		minf(duration, 0.4)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _wait_for_tween(_satan_motion_tween, duration + 0.5)
	if _exit_skip_requested:
		return

	if satan_motion_root != null and is_instance_valid(satan_motion_root):
		satan_motion_root.transform = _satan_motion_base_transform
	if dealer_satan != null and is_instance_valid(dealer_satan):
		dealer_satan.visible = _satan_base_visible
		dealer_satan.modulate = _satan_base_modulate
	_satan_hovered = false
	_set_satan_laughing(false)


func _set_satan_dying(is_dying: bool) -> void:
	_satan_story_reaction = 0
	_satan_is_dying = is_dying
	_satan_hovered = false
	if is_dying:
		_satan_is_laughing = false
		_play_satan_sheet(SATAN_DEATH_TEXTURE, SATAN_DEATH_FRAMES, SATAN_DEATH_FPS, false)
	else:
		_set_satan_laughing(false)


func set_satan_stream_laughing(enabled: bool) -> void:
	if _satan_stream_laughing == enabled:
		return
	_satan_stream_laughing = enabled
	if enabled:
		if is_instance_valid(_satan_laugh_audio):
			_satan_stream_laugh_pitch = _satan_laugh_audio.pitch_offset_semitones
			_satan_laugh_audio.pitch_offset_semitones = _satan_stream_laugh_pitch + SATAN_STREAM_LAUGH_PITCH_OFFSET
		if not _satan_is_dying and not _satan_is_laughing:
			_play_satan_sheet(SATAN_LAUGH_TEXTURE, SATAN_LAUGH_FRAMES, SATAN_STREAM_LAUGH_FPS, false)
	else:
		if is_instance_valid(_satan_laugh_audio):
			_satan_laugh_audio.pitch_offset_semitones = _satan_stream_laugh_pitch
			_satan_laugh_audio.set_laughing(_loss_exit_running and _satan_is_laughing)
		if not _satan_is_dying and not _satan_is_laughing and dealer_satan.texture == SATAN_LAUGH_TEXTURE:
			_set_satan_laughing(false)


func _set_satan_laughing(is_laughing: bool) -> void:
	if dealer_satan == null or not is_instance_valid(dealer_satan):
		return
	if _satan_is_dying or _satan_story_reaction > 0:
		return

	_satan_is_laughing = is_laughing
	var use_hover_sheet := not is_laughing and _satan_hovered
	var target_texture: Texture2D = SATAN_LAUGH_TEXTURE if is_laughing else (
		SATAN_HOVER_TEXTURE if use_hover_sheet else _satan_idle_texture
	)
	if target_texture == null:
		return

	var target_frames := SATAN_LAUGH_FRAMES if is_laughing else (
		SATAN_HOVER_FRAMES if use_hover_sheet else SATAN_IDLE_FRAMES
	)
	var target_fps := SATAN_LAUGH_FPS if is_laughing else (
		SATAN_HOVER_FPS if use_hover_sheet else SATAN_IDLE_FPS
	)
	_play_satan_sheet(target_texture, target_frames, target_fps, false)


func _update_satan_pointer_hover() -> void:
	if (
		_loss_exit_running or _journal_input_blocked
		or dealer_satan == null
		or not is_instance_valid(dealer_satan)
		or not dealer_satan.visible
	):
		_set_satan_hovered(false)
		return
	if table_camera == null or not is_instance_valid(table_camera):
		_set_satan_hovered(false)
		return
	var viewport := table_camera.get_viewport()
	if viewport == null:
		_set_satan_hovered(false)
		return
	_set_satan_hovered(_is_satan_under_pointer(viewport.get_mouse_position()))


func _is_satan_under_pointer(pointer_position: Vector2) -> bool:
	if (
		table_camera == null
		or not is_instance_valid(table_camera)
		or satan_hover_area == null
		or not is_instance_valid(satan_hover_area)
		or not satan_hover_area.input_ray_pickable
	):
		return false

	var viewport := table_camera.get_viewport()
	if viewport == null:
		return false

	if not viewport.get_visible_rect().has_point(pointer_position):
		return false

	var ray_origin := table_camera.project_ray_origin(pointer_position)
	var ray_end := (
		ray_origin
		+ table_camera.project_ray_normal(pointer_position) * table_camera.far
	)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		SATAN_HOVER_COLLISION_LAYER
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := table_camera.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == satan_hover_area


func _set_satan_hovered(is_hovered: bool) -> void:
	if _satan_hovered == is_hovered:
		return
	_satan_hovered = is_hovered
	if _satan_is_laughing or _satan_is_dying or _satan_stream_laughing or _satan_story_reaction > 0:
		return

	_play_satan_sheet(
		SATAN_HOVER_TEXTURE if is_hovered else _satan_idle_texture,
		SATAN_HOVER_FRAMES if is_hovered else SATAN_IDLE_FRAMES,
		SATAN_HOVER_FPS if is_hovered else SATAN_IDLE_FPS,
		true
	)


func play_satan_story_reaction(shot_number: int) -> void:
	_satan_story_reaction = clampi(shot_number, 1, 2)
	_satan_is_laughing = false
	_satan_hovered = false
	var sheet := SATAN_PANIC_TEXTURE if shot_number == 1 else SATAN_KILL_TEXTURE
	# Both supplied sheets use the same square cells as Satan's other poses.
	var frames := maxi(1, sheet.get_width() / sheet.get_height())
	dealer_satan.play_sheet(sheet, frames, SATAN_PANIC_FPS if shot_number == 1 else SATAN_KILL_FPS, shot_number == 1)
	if is_instance_valid(_satan_laugh_audio):
		_satan_laugh_audio.set_laughing(false)


func _play_satan_sheet(
	target_texture: Texture2D,
	target_frames: int,
	target_fps: float,
	preserve_frame: bool
) -> void:
	if _satan_story_reaction > 0:
		return
	_sync_online_character()
	if target_texture == null:
		return
	if is_instance_valid(_satan_laugh_audio):
		# The result animation stays silent until Exit starts the cinematic.
		_satan_laugh_audio.set_laughing((_loss_exit_running or _satan_stream_laughing) and target_texture == SATAN_LAUGH_TEXTURE)

	if dealer_satan.has_method("play_sheet"):
		dealer_satan.call(
			"play_sheet",
			target_texture,
			target_frames,
			target_fps,
			true,
			preserve_frame
		)
		return

	# Fallback, falls der Sprite spaeter ohne SpriteAnim-Script verwendet wird.
	var previous_frame := dealer_satan.frame
	dealer_satan.texture = target_texture
	dealer_satan.hframes = target_frames
	dealer_satan.vframes = 1
	dealer_satan.frame = (
		clampi(previous_frame, 0, target_frames - 1) if preserve_frame else 0
	)


func _raise_dealer_gun() -> void:
	if dealer_gun == null or not is_instance_valid(dealer_gun):
		return

	if pistol_start_marker == null or not is_instance_valid(pistol_start_marker):
		return

	if pistol_end_marker == null or not is_instance_valid(pistol_end_marker):
		return

	dealer_gun.global_transform = pistol_start_marker.global_transform

	_dealer_gun_tween = create_tween()
	_dealer_gun_tween.tween_property(
		dealer_gun,
		"global_transform",
		pistol_end_marker.global_transform,
		pistol_raise_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await _wait_for_tween(_dealer_gun_tween, pistol_raise_duration + 0.5)


func _on_exit_button_pressed() -> void:
	if not _online_mode and _local_mode == "training":
		_show_main_menu()
		_show_training_menu()
		return
	if not _online_mode and _local_mode == "story" and _last_match_outcome == MatchOutcome.WIN and not _match_reward_granted:
		_grant_match_rewards()
		if not _match_reward_granted:
			return
	if _loss_exit_running:
		return
	if _online_mode and _online_is_spectator:
		_leave_spectator_match()
		return

	var match_outcome := _last_match_outcome
	var session_generation := _online_session_generation
	var disconnected_online_exit := false
	if _online_mode:
		if _online_active_exit_sequence > 0 or _online_exit_requested:
			return
		if (
			NetworkManager.has_active_session()
			and NetworkManager.has_connected_opponent()
		):
			_request_online_exit()
			return

		# If the connection was already lost, the remaining player still gets the
		# correct local result cinematic. Teardown stays deferred until it ends.
		disconnected_online_exit = true
		_online_mode = false
		_online_is_host = false
		_online_action_in_progress = false

	match match_outcome:
		MatchOutcome.WIN:
			await _play_win_exit_sequence(not disconnected_online_exit)
		MatchOutcome.LOSS:
			await _play_loss_exit_sequence(not disconnected_online_exit)
		_:
			_show_main_menu()

	if disconnected_online_exit:
		await get_tree().process_frame
		if session_generation != _online_session_generation or not is_inside_tree():
			return
		NetworkManager.end_match()
		if NetworkManager.has_active_session():
			NetworkManager.leave_lobby("Online-Match beendet.")


func _request_online_exit() -> void:
	if (
		not _online_mode
		or _last_match_outcome == MatchOutcome.NONE
		or _online_exit_requested
		or _online_active_exit_sequence > 0
	):
		return

	_online_exit_requested = true
	_online_action_in_progress = true
	end_buttons.visible = false
	_set_match_status("Beende Online-Match...")

	if _online_is_host:
		_begin_host_online_exit()
		return

	var host_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if not _is_connected_online_exit_peer(host_peer_id):
		_online_exit_requested = false
		_online_action_in_progress = false
		end_buttons.visible = true
		return

	_rpc_request_online_exit.rpc_id(host_peer_id, _online_turn_sequence)
	_wait_for_online_exit_response.call_deferred(_online_turn_sequence, _online_session_generation)


func _wait_for_online_exit_response(requested_turn_sequence: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	var deadline := Time.get_ticks_msec() + ONLINE_EXIT_REQUEST_TIMEOUT_MSEC
	while (
		session_generation == _online_session_generation
		and is_inside_tree()
		and _online_mode
		and not _online_is_host
		and _online_exit_requested
		and _online_active_exit_sequence == 0
		and requested_turn_sequence == _online_turn_sequence
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame

	if (
		session_generation != _online_session_generation
		or not is_inside_tree()
		or not _online_mode
		or _online_is_host
		or _online_active_exit_sequence > 0
		or requested_turn_sequence != _online_turn_sequence
	):
		return

	# The request may be retried without ever dropping the native peer from an
	# RPC callback. A real disconnect is handled through session_closed.
	_online_exit_requested = false
	_online_action_in_progress = false
	end_buttons.visible = true
	_set_match_status("Exit konnte nicht synchronisiert werden — erneut versuchen.")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_online_exit(requested_turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_connected_online_exit_peer(sender_id):
		return

	if _online_active_exit_sequence > 0:
		# A simultaneous/double click is idempotent. Re-send the authoritative
		# start packet in case the guest is still waiting for it.
		_rpc_begin_online_exit.rpc_id(
			sender_id,
			_online_active_exit_sequence,
			_online_exit_canonical_winner
		)
		return

	if (
		_last_match_outcome == MatchOutcome.NONE
		or requested_turn_sequence != _online_turn_sequence
	):
		return
	_begin_host_online_exit()


func _begin_host_online_exit() -> void:
	if (
		not _online_mode
		or not _online_is_host
		or _online_active_exit_sequence > 0
		or _last_match_outcome == MatchOutcome.NONE
	):
		return

	var canonical_winner := _get_canonical_winner()
	if canonical_winner not in ["player", "enemy", "draw"]:
		return

	_online_exit_sequence += 1
	_online_active_exit_sequence = _online_exit_sequence
	_online_exit_canonical_winner = canonical_winner
	_online_exit_requested = true
	_online_exit_local_finished = false
	_online_exit_remote_finished = false
	_online_exit_finalize_acknowledged = false
	_online_exit_finalize_received = false
	_online_exit_coordinator_running = false
	_online_exit_deadline_msec = (
		Time.get_ticks_msec() + ONLINE_EXIT_CINEMATIC_TIMEOUT_MSEC
	)
	_online_action_in_progress = true
	end_buttons.visible = false
	_retire_online_battle_presentation()

	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if _is_connected_online_exit_peer(opponent_peer_id):
		_rpc_begin_online_exit.rpc_id(
			opponent_peer_id,
			_online_active_exit_sequence,
			canonical_winner
		)
	for spectator_id: int in NetworkManager.get_spectator_peer_ids():
		_rpc_finish_spectator_match.rpc_id(spectator_id, canonical_winner)
	_start_online_exit_cinematic.call_deferred(_online_active_exit_sequence, _online_session_generation)


@rpc("authority", "call_remote", "reliable")
func _rpc_finish_spectator_match(canonical_winner: String) -> void:
	if (
		not _online_mode or not _online_is_spectator
		or not NetworkManager.is_connected_game_peer(multiplayer.get_remote_sender_id())
		or canonical_winner not in ["player", "enemy", "draw"]
	):
		return
	_apply_online_result(canonical_winner)
	# Keep the result visible until the spectator chooses to leave. Host loss
	# still disconnects the session cleanly after the fighters' exit cinematic.
	_online_action_in_progress = false
	_game_over = true
	_table_state = TableState.GAME_OVER
	end_buttons.visible = true


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_online_exit(exit_sequence: int, canonical_winner: String) -> void:
	if (
		not _online_mode
		or _online_is_host
		or exit_sequence <= 0
		or canonical_winner not in ["player", "enemy", "draw"]
	):
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 or not _is_connected_online_exit_peer(sender_id):
		return
	if exit_sequence < _online_active_exit_sequence:
		return
	if _online_active_exit_sequence > 0 and exit_sequence != _online_active_exit_sequence:
		return

	if exit_sequence == _online_active_exit_sequence:
		return

	_online_active_exit_sequence = exit_sequence
	_online_exit_canonical_winner = canonical_winner
	_online_exit_requested = true
	_online_exit_local_finished = false
	_online_exit_remote_finished = false
	_online_exit_finalize_received = false
	_online_exit_deadline_msec = (
		Time.get_ticks_msec() + ONLINE_EXIT_CINEMATIC_TIMEOUT_MSEC
	)
	_online_action_in_progress = true
	end_buttons.visible = false
	_apply_online_result(canonical_winner)
	_retire_online_battle_presentation()
	_start_online_exit_cinematic.call_deferred(exit_sequence, _online_session_generation)


func _start_online_exit_cinematic(exit_sequence: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	if (
		not _online_mode
		or not _is_current_online_exit(exit_sequence, session_generation)
		or _online_exit_local_finished
		or _loss_exit_running
	):
		return

	var match_outcome := _last_match_outcome
	NetworkManager.trace_session_event("exit cinematic started: %s" % MatchOutcome.keys()[match_outcome])
	match match_outcome:
		MatchOutcome.WIN:
			await _play_win_exit_sequence(false)
		MatchOutcome.LOSS:
			await _play_loss_exit_sequence(false)
		_:
			_show_main_menu()

	if not _online_mode or not _is_current_online_exit(exit_sequence, session_generation):
		return

	_online_exit_local_finished = true
	NetworkManager.trace_session_event("exit cinematic completed")
	_online_action_in_progress = true
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false
	_set_match_status("Warte auf Gegenspieler...")

	if _online_is_host:
		_coordinate_online_exit.call_deferred(exit_sequence, session_generation)
		return

	var host_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if _is_connected_online_exit_peer(host_peer_id):
		_rpc_ack_online_exit_cinematic.rpc_id(host_peer_id, exit_sequence)
	_wait_for_online_exit_finalize.call_deferred(exit_sequence, session_generation)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_online_exit_cinematic(exit_sequence: int) -> void:
	if (
		not _online_mode
		or not _online_is_host
		or exit_sequence != _online_active_exit_sequence
	):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_connected_online_exit_peer(sender_id):
		return
	_online_exit_remote_finished = true


func _coordinate_online_exit(exit_sequence: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	if (
		_online_exit_coordinator_running
		or not _online_is_host
		or not _is_current_online_exit(exit_sequence, session_generation)
	):
		return
	_online_exit_coordinator_running = true

	while (
		_online_mode
		and _is_current_online_exit(exit_sequence, session_generation)
		and not _online_exit_remote_finished
		and NetworkManager.has_active_session()
		and NetworkManager.has_connected_opponent()
		and Time.get_ticks_msec() < _online_exit_deadline_msec
	):
		await get_tree().process_frame

	if not _online_mode or not _is_current_online_exit(exit_sequence, session_generation):
		return

	var opponent_peer_id := NetworkManager.get_connected_opponent_peer_id()
	if _is_connected_online_exit_peer(opponent_peer_id):
		_online_exit_finalize_acknowledged = false
		_rpc_finalize_online_exit.rpc_id(opponent_peer_id, exit_sequence)
		await _wait_for_online_exit_client_departure(exit_sequence, opponent_peer_id, session_generation)

	_finalize_online_exit_local.call_deferred(exit_sequence, session_generation)


func _wait_for_online_exit_client_departure(exit_sequence: int, peer_id: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	# The ACK confirms delivery, not that the guest has detached its native peer.
	# Closing the host on that ACK races the guest's own Steam socket cleanup.
	# Let the guest leave first, then retire the host peer after its disconnect.
	# Keep the same bounded timeout for an unresponsive guest.
	var deadline := Time.get_ticks_msec() + ONLINE_EXIT_FINALIZE_TIMEOUT_MSEC
	while (
		_online_mode
		and _is_current_online_exit(exit_sequence, session_generation)
		and _is_connected_online_exit_peer(peer_id)
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame


@rpc("authority", "call_remote", "reliable")
func _rpc_finalize_online_exit(exit_sequence: int) -> void:
	if (
		not _online_mode
		or _online_is_host
		or exit_sequence != _online_active_exit_sequence
	):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 or not _is_connected_online_exit_peer(sender_id):
		return

	if not _online_exit_finalize_received:
		_online_exit_finalize_received = true
	_rpc_ack_online_exit_finalize.rpc_id(sender_id, exit_sequence)
	_finalize_online_exit_local.call_deferred(exit_sequence, _online_session_generation)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_online_exit_finalize(exit_sequence: int) -> void:
	if (
		not _online_mode
		or not _online_is_host
		or exit_sequence != _online_active_exit_sequence
	):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_connected_online_exit_peer(sender_id):
		return
	_online_exit_finalize_acknowledged = true


func _wait_for_online_exit_finalize(exit_sequence: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	var deadline := Time.get_ticks_msec() + ONLINE_EXIT_CLIENT_WATCHDOG_MSEC
	while (
		_online_mode
		and _is_current_online_exit(exit_sequence, session_generation)
		and not _online_exit_finalize_received
		and NetworkManager.has_active_session()
		and NetworkManager.has_connected_opponent()
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame

	if (
		_online_mode
		and _is_current_online_exit(exit_sequence, session_generation)
		and not _online_exit_finalize_received
	):
		_finalize_online_exit_local.call_deferred(exit_sequence, session_generation)


func _finalize_online_exit_local(exit_sequence: int, session_generation: int = -1) -> void:
	if session_generation < 0:
		session_generation = _online_session_generation
	if (
		_online_exit_finalizing
		or not _is_current_online_exit(exit_sequence, session_generation)
	):
		return
	_online_exit_finalizing = true
	NetworkManager.trace_session_event("local exit finalization started")

	# A disconnect/finalize packet may arrive while the cinematic coroutine is
	# still running. Never tear the peer or table out from underneath it.
	while _loss_exit_running and _is_current_online_exit(exit_sequence, session_generation):
		await get_tree().process_frame
	if not _is_current_online_exit(exit_sequence, session_generation):
		return
	await get_tree().process_frame

	if not _is_current_online_exit(exit_sequence, session_generation):
		return

	_online_mode = false
	_online_is_host = false
	_online_action_in_progress = false
	NetworkManager.end_match()
	if NetworkManager.has_active_session():
		NetworkManager.leave_lobby("Online-Match beendet.")
	_reset_online_sync_tracking()
	_show_main_menu(true)
	_set_loss_interactions_enabled(true)
	NetworkManager.trace_session_event("local exit returned to menu")


func _is_current_online_exit(exit_sequence: int, session_generation: int) -> bool:
	return (
		is_inside_tree()
		and session_generation == _online_session_generation
		and exit_sequence > 0
		and exit_sequence == _online_active_exit_sequence
	)


func _trace_exit_stage(stage: String) -> void:
	DIAGNOSTICS.record("online.exit.stage", {
		"stage": stage,
		"online": _online_mode,
		"host": _online_is_host,
		"spectator": _online_is_spectator,
		"state": TableState.keys()[_table_state],
		"session_generation": _online_session_generation,
		"match_generation": _match_generation,
		"exit_sequence": _online_active_exit_sequence,
		"is_cinematic_running": _loss_exit_running,
		"death_count": _pending_card_deaths.size(),
		"presentation_count": _online_client_presentation_depth,
	})


func _is_connected_online_exit_peer(peer_id: int) -> bool:
	return (
		peer_id > 0
		and NetworkManager.has_active_session()
		and NetworkManager.has_connected_opponent()
		and peer_id == NetworkManager.get_connected_opponent_peer_id()
	)


# Consume the request now; the serial animation coroutine unwinds at its next
# frame before cleanup. No timer or nested animation can resume after that cleanup.
func try_skip_offline_exit(event: InputEvent) -> bool:
	if not _loss_exit_running or not _exit_skip_allowed or _online_mode:
		return false
	if not event.is_pressed() or event.is_echo():
		return false
	var is_button := (
		event is InputEventKey or event is InputEventJoypadButton
		or event is InputEventScreenTouch
	)
	if event is InputEventMouseButton:
		is_button = event.button_index in [
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
			MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2,
		]
	if not is_button:
		return false
	_exit_skip_requested = true
	return true


func _wait_for_exit_delay(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration and not _exit_skip_requested:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _stop_exit_tweens() -> void:
	for tween: Tween in [
		_camera_tween, _shake_tween, _dealer_gun_tween,
		_black_fade_tween, _hearing_volume_tween, _hearing_filter_tween,
	]:
		if tween != null and tween.is_valid():
			tween.kill()
	_camera_tween = null
	_shake_tween = null
	_dealer_gun_tween = null
	_black_fade_tween = null
	_hearing_volume_tween = null
	_hearing_filter_tween = null


func _finish_exit_sequence() -> void:
	if _exit_skip_requested:
		_stop_exit_tweens()
		_restore_hearing_state()
		if death_shot_sfx != null:
			death_shot_sfx.stop()
		if _black_rect != null:
			_black_rect.visible = false
			_black_rect.modulate.a = 0.0
		# Rewards were settled when the match ended. This only resets presentation.
		_show_main_menu()
		if _camera_tween != null:
			_camera_tween.kill()
			_camera_tween = null
		if is_instance_valid(table_camera):
			table_camera.global_transform = _camera_base_transform
			table_camera.fov = _camera_base_fov
		loss_exit_skipped.emit()
		_trace_exit_stage("offline_skipped")
	_exit_skip_allowed = false
	_set_loss_interactions_enabled(true)
	_loss_exit_running = false
	loss_exit_finished.emit()


func _play_win_exit_sequence(allow_skip: bool = true) -> void:
	if _loss_exit_running:
		return
	_loss_exit_running = true
	_exit_skip_allowed = allow_skip and not _online_mode
	_exit_skip_requested = false
	await _run_win_exit_sequence()
	_finish_exit_sequence()
	_trace_exit_stage("win_finished")


func _run_win_exit_sequence() -> void:
	_interrupt_journal()
	_trace_exit_stage("win_begin")
	end_buttons.visible = false
	_set_loss_interactions_enabled(false)
	_reset_win_cinematic_visuals()
	if _effect_overview != null:
		_effect_overview.hide_overview()

	# Wie bei der Niederlage startet die Inszenierung aus einer stabilen
	# Spielersicht und fährt dann nah an Satan heran.
	var music_fade_duration := (
		loss_player_view_return_duration + loss_camera_approach_duration
	)
	loss_exit_started.emit(music_fade_duration)
	await _return_camera_to_player_view()
	if _exit_skip_requested:
		return
	await _move_camera_to_loss_view()
	if _exit_skip_requested:
		return

	# Das Back-Asset ist ein echtes First-Person-Viewmodel und fährt von unten
	# ins Bild, unabhängig von Tischskalierung oder Bildschirmauflösung.
	await _raise_player_gun()
	if _exit_skip_requested:
		return
	await _wait_for_exit_delay(maxf(pistol_aim_pause, 0.0))
	if _exit_skip_requested:
		return

	_start_win_shot_effects()
	_hide_match_cards_for_win_shot()
	_trace_exit_stage("win_shot")
	_set_satan_dying(true)
	_show_win_blood()
	if death_shot_sfx != null:
		death_shot_sfx.play()
	loss_shot_fired.emit()
	win_shot_fired.emit()
	_start_player_gun_recoil()
	var knockback_tween := _start_satan_knockback()

	await _wait_for_exit_delay(0.1)
	if _exit_skip_requested:
		return
	if player_muzzle_flash != null and is_instance_valid(player_muzzle_flash):
		player_muzzle_flash.visible = false
	await _wait_for_tween(knockback_tween, win_satan_knockback_duration + 0.5)
	if _exit_skip_requested:
		return

	if dealer_satan != null and is_instance_valid(dealer_satan):
		dealer_satan.visible = false
	await _wait_for_exit_delay(maxf(win_satan_absent_duration, 0.0))
	if _exit_skip_requested:
		return

	# Musik setzt ein, waehrend Satan von unterhalb seines exakten Startpunkts
	# wieder hochkommt. Erst danach werden Kamera und Viewmodel zurueckgesetzt.
	var reveal_duration := (
		win_satan_return_duration
		+ win_satan_return_hold
		+ maxf(loss_player_view_return_duration, win_gun_lower_duration)
	)
	loss_reveal_started.emit(reveal_duration)
	_trace_exit_stage("win_reveal_begin")
	await _return_satan_from_below()
	if _exit_skip_requested:
		return
	await _wait_for_exit_delay(maxf(win_satan_return_hold, 0.0))
	if _exit_skip_requested:
		return

	var gun_lower_tween := _lower_player_gun()
	await _return_camera_to_player_view()
	if _exit_skip_requested:
		return
	await _wait_for_tween(gun_lower_tween, win_gun_lower_duration + 0.5)
	if _exit_skip_requested:
		return

	# The wall stain and ringing outlive the camera/gun animation naturally.
	_show_main_menu(true)
	_trace_exit_stage("win_menu_reset")


func _play_loss_exit_sequence(allow_skip: bool = true) -> void:
	if _loss_exit_running:
		return
	_loss_exit_running = true
	_exit_skip_allowed = allow_skip and not _online_mode
	_exit_skip_requested = false
	await _run_loss_exit_sequence()
	_finish_exit_sequence()
	_trace_exit_stage("loss_finished")


func _run_loss_exit_sequence() -> void:
	_interrupt_journal()
	_set_satan_laughing(true)
	_trace_exit_stage("loss_begin")
	end_buttons.visible = false
	_set_loss_interactions_enabled(false)
	if _effect_overview != null:
		_effect_overview.hide_overview()

	# Erst aus Inspect-/Effektansichten sauber in die normale Spielersicht
	# zurueckkehren. Von dort beginnt erst die langsame Fahrt zu Satan.
	var music_fade_duration := (
		loss_player_view_return_duration + loss_camera_approach_duration
	)
	loss_exit_started.emit(music_fade_duration)
	await _return_camera_to_player_view()
	if _exit_skip_requested:
		return
	await _move_camera_to_loss_view()
	if _exit_skip_requested:
		return

	# Waffe nach oben bewegen.
	await _raise_dealer_gun()
	if _exit_skip_requested:
		return

	# Kurzer Moment mit erhobener Waffe, bevor der Schuss faellt.
	await _wait_for_exit_delay(maxf(pistol_aim_pause, 0.0))
	if _exit_skip_requested:
		return

	# Schuss und abrupter Rueckschwung passieren im selben Frame.
	if flash_sprite != null:
		flash_sprite.visible = true

	if death_shot_sfx != null:
		death_shot_sfx.play()
	loss_shot_fired.emit()
	_trace_exit_stage("loss_shot")
	var camera_return_tween := _swing_camera_to_base_view()

	await _wait_for_exit_delay(0.1)
	if _exit_skip_requested:
		return

	if flash_sprite != null:
		flash_sprite.visible = false
	await _wait_for_tween(camera_return_tween, loss_camera_return_duration + 0.5)
	if _exit_skip_requested:
		return

	# Bildschirm schwarz machen.
	_show_black_screen()
	_trace_exit_stage("loss_blackout")

	# Einen Frame warten, damit Schwarz garantiert gezeichnet wird.
	await get_tree().process_frame
	if _exit_skip_requested:
		return

	# Unsichtbar hinter dem Schwarz alles zurücksetzen.
	_restore_standard_satan_for_exit()
	_show_main_menu()
	_reset_dealer_gun()
	_trace_exit_stage("loss_menu_reset")

	# Gehör wiederherstellen.
	await _play_hearing_recovery()
	if _exit_skip_requested:
		return
	_trace_exit_stage("loss_hearing_restored")

	await _wait_for_exit_delay(1.0)
	if _exit_skip_requested:
		return

	# Bild und Musik kommen exakt gemeinsam zurueck.
	player_wakeup_started.emit()
	loss_reveal_started.emit(loss_reveal_duration)
	_trace_exit_stage("loss_reveal_begin")
	await _fade_black_screen_out(loss_reveal_duration)
	if _exit_skip_requested:
		return
	_trace_exit_stage("loss_reveal_finished")


func _set_loss_interactions_enabled(enabled: bool) -> void:
	for card in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card) and card.area != null:
			card.area.input_ray_pickable = enabled

	if satan_hover_area != null and is_instance_valid(satan_hover_area):
		satan_hover_area.input_ray_pickable = enabled
	if not enabled:
		_set_satan_hovered(false)

	_set_table_button_input_enabled(menu_root, enabled)


func _set_table_button_input_enabled(node: Node, enabled: bool) -> void:
	if node is Table3DButton:
		var button := node as Table3DButton
		if button.area != null:
			button.area.input_ray_pickable = enabled
	for child in node.get_children():
		_set_table_button_input_enabled(child, enabled)
	
func _show_black_screen() -> void:
	if _black_layer == null:
		_black_layer = CanvasLayer.new()
		_black_layer.name = "LossBlackLayer"
		add_child(_black_layer)

	if _black_rect == null:
		_black_rect = ColorRect.new()
		_black_rect.name = "BlackRect"
		_black_rect.color = Color.BLACK
		_black_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_black_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_black_layer.add_child(_black_rect)

	_black_rect.visible = true
	_black_rect.modulate.a = 1.0


func _fade_black_screen_out(duration: float) -> void:
	if _black_rect == null:
		return

	_black_fade_tween = create_tween()
	_black_fade_tween.tween_property(_black_rect, "modulate:a", 0.0, duration)
	await _wait_for_tween(_black_fade_tween, duration + 0.5)
	if _exit_skip_requested:
		return

	if _black_rect != null:
		_black_rect.visible = false


func _get_or_create_lowpass() -> AudioEffectLowPassFilter:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus == -1:
		return null

	var effect_index := 0

	if AudioServer.get_bus_effect_count(master_bus) <= effect_index:
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 20000.0
		lowpass.resonance = 0.35
		AudioServer.add_bus_effect(master_bus, lowpass, effect_index)

	return AudioServer.get_bus_effect(master_bus, effect_index) as AudioEffectLowPassFilter


func _play_hearing_recovery() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus == -1:
		return

	var lowpass := _get_or_create_lowpass()
	if lowpass == null:
		return

	_hearing_recovery_active = true
	_hearing_master_bus_index = master_bus
	_hearing_master_restore_db = AudioServer.get_bus_volume_db(master_bus)
	_hearing_lowpass = lowpass
	_hearing_lowpass_restore_cutoff = lowpass.cutoff_hz
	_hearing_effect_was_enabled = AudioServer.is_bus_effect_enabled(master_bus, 0)

	AudioServer.set_bus_effect_enabled(master_bus, 0, true)

	lowpass.cutoff_hz = 350.0
	AudioServer.set_bus_volume_db(master_bus, -80.0)

	await _wait_for_exit_delay(0.8)
	if _exit_skip_requested:
		return

	_hearing_volume_tween = create_tween()
	_hearing_volume_tween.tween_method(
		func(db: float) -> void:
			AudioServer.set_bus_volume_db(master_bus, db),
		-80.0,
		_hearing_master_restore_db,
		2.5
	)

	_hearing_filter_tween = create_tween()
	_hearing_filter_tween.tween_method(
		func(freq: float) -> void:
			lowpass.cutoff_hz = freq,
		350.0,
		20000.0,
		3.0
	)

	# Nur auf den längeren Tween warten.
	await _wait_for_tween(_hearing_filter_tween, 3.5)
	if _exit_skip_requested:
		return

	_restore_hearing_state()


func _restore_hearing_state() -> void:
	if not _hearing_recovery_active:
		return

	if _hearing_master_bus_index >= 0:
		AudioServer.set_bus_volume_db(_hearing_master_bus_index, _hearing_master_restore_db)
		if _hearing_lowpass != null:
			_hearing_lowpass.cutoff_hz = _hearing_lowpass_restore_cutoff
		AudioServer.set_bus_effect_enabled(
			_hearing_master_bus_index,
			0,
			_hearing_effect_was_enabled
		)

	_hearing_recovery_active = false
	_hearing_master_bus_index = -1
	_hearing_lowpass = null


func _exit_tree() -> void:
	if _character_creation_paused_tree:
		get_tree().paused = false
		_character_creation_paused_tree = false
	GameCurrency.set_training_session(self, false)
	_trace_exit_stage("table_exit_tree")
	_clear_damage_numbers()
	_online_session_generation += 1
	_match_generation += 1
	_stop_exit_tweens()
	_restore_hearing_state()
	_reset_win_cinematic_visuals()
	if _loss_exit_running:
		_loss_exit_running = false
		loss_exit_finished.emit()
	
func _play_card_draw_sound(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		return

	var card_id := str(card.card_data.get("id", card.card_data.get("card_id", "")))

	if card_id == "":
		return

	var sound_path := "res://assets/sounds/SFX/cards/" + card_id + ".ogg"

	if not ResourceLoader.exists(sound_path):
		return

	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = load(sound_path)
	add_child(player)
	player.global_position = card.global_position

	player.play()
	player.finished.connect(player.queue_free)
