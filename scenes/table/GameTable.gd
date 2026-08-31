extends Node3D
class_name GameTable

const HAND_SIZE: int = 5
const SATAN_LAUGH_TEXTURE := preload("res://assets/characters/satanLaught.png")
const SATAN_IDLE_FRAMES := 25
const SATAN_LAUGH_FRAMES := 2
const SATAN_IDLE_FPS := 15.0
const SATAN_LAUGH_FPS := 20.0

# Wie viele sichtbare Ruecken-Karten der Stapel maximal gleichzeitig
# zeigt. Bei sehr grossen Decks wuerde 1:1-Stapeln unnoetig viele
# Meshes erzeugen, daher wird die sichtbare Stapelhoehe auf diesen Wert
# gecappt — sieht trotzdem nach "vollem Stapel" aus.
const MAX_VISIBLE_STACK_CARDS: int = 20

# Vertikaler Versatz zwischen zwei gestapelten Ruecken-Karten.
const STACK_LAYER_OFFSET: Vector3 = Vector3(0, 0.012, 0)

@export var card_scene: PackedScene

@onready var player_slots_root: Node3D = $PlayerSlots
@onready var enemy_slots_root: Node3D = $EnemySlots
@onready var player_deck_marker: Marker3D = $PlayerDeck
@onready var enemy_deck_marker: Marker3D = $EnemyDeck
@onready var status_label: Label3D = $StatusLabel
@onready var player_death_marker: Marker3D = $PlayerSlots/death
@onready var enemy_death_marker: Marker3D = $EnemySlots/death
@onready var select_sfx: AudioStreamPlayer = $Audio/SelectSFX
@onready var damage_sfx: AudioStreamPlayer = $Audio/DamageSFX
@onready var kill_sfx: AudioStreamPlayer = $Audio/KillSFX
@onready var flash_sprite: Sprite3D = $dealer/flash
@onready var death_shot_sfx: AudioStreamPlayer = $Audio/DeathShotSFX
@onready var dealer_satan: Sprite3D = $dealer/satan

@onready var dealer_gun: Sprite3D = $dealer/gun
@onready var pistol_start_marker: Marker3D = $dealer/PistolStart
@onready var pistol_end_marker: Marker3D = $dealer/PistolEnd

@export var pistol_raise_duration: float = 0.55
@export var pistol_aim_pause: float = 0.15

@export_group("Timing")
@export var enemy_turn_delay: float = 0.9
@export var draw_animation_duration: float = 0.35

@export_group("Effects")
@export var blood_burst_scene: PackedScene
@export var blood_decal_scene: PackedScene
@export var heal_burst_scene: PackedScene
@export var poison_burst_scene: PackedScene

@export var blood_spawn_offset := Vector3(0, 0.16, 0)
@export var blood_decal_offset := Vector3(0, 0.012, 0)

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
	GAME_OVER
}

var _table_state: TableState = TableState.MENU
var _selected_difficulty := "normal"

@onready var menu_root: Node3D = $MenuRoot
@onready var mode_buttons: Node3D = $MenuRoot/ModeButtons
@onready var difficulty_buttons: Node3D = $MenuRoot/DifficultyButtons
@onready var end_buttons: Node3D = $MenuRoot/EndButtons
@onready var matchmaking_screen: Control = $OnlineCanvas/MatchmakingScreen

var _camera_base_transform: Transform3D
var _inspected_card: Card3D = null
var _camera_tween: Tween = null

# Pro Slot-Index die jeweilige Karteninstanz (oder null, wenn leer).
var _player_slots: Array[Card3D] = [null, null, null, null, null]
var _enemy_slots: Array[Card3D] = [null, null, null, null, null]

# Verbleibende Kartendaten (Dictionaries aus CardDatabase/Collection),
# die noch nicht auf dem Tisch liegen. Wird beim Nachziehen verkleinert.
var _player_deck: Array[Dictionary] = []
var _enemy_deck: Array[Dictionary] = []

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

# Sichtbare Ruecken-Karten pro Stapel (nur Optik, keine Spieldaten).
var _player_stack_visuals: Array[Card3D] = []
var _enemy_stack_visuals: Array[Card3D] = []
var _effect_overview: CardEffectOverviewUI = null
var _effect_overview_layer: CanvasLayer = null

var _last_match_was_loss := false
var _loss_exit_running := false
var _black_layer: CanvasLayer = null
var _black_rect: ColorRect = null
var _satan_idle_texture: Texture2D = null

# Online matches are host-authoritative. "player"/"enemy" remain the local
# visual sides on every machine; snapshots are mirrored for the client.
var _online_mode := false
var _online_is_host := false
var _online_action_in_progress := false
var _online_reward_granted := false
var _online_disconnect_reason := ""
var _online_turn_sequence := 0
# The host stores selection in canonical board coordinates. On the client,
# canonical "enemy" maps to the local player side and vice versa.
var _online_selected_side := ""
var _online_selected_slot := -1


func _ready() -> void:
	_rng.randomize()
	_satan_idle_texture = dealer_satan.texture if dealer_satan != null else null

	if table_camera == null:
		table_camera = $Camera3D

	_camera_base_transform = table_camera.global_transform
	_collect_slot_markers()
	_connect_menu_buttons()
	_connect_online_signals()
	_ensure_effect_overview()

	_reset_dealer_gun()
	_show_main_menu()

	# A Steam invite can be accepted while this scene is loading. In that case
	# immediately expose the already joined lobby instead of returning to KI.
	if NetworkManager.has_active_session():
		if NetworkManager.is_match_in_progress():
			_on_online_match_started.call_deferred()
		else:
			_show_multiplayer_menu()


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
	if DeckManager.is_empty():
		_show_main_menu()
		return
	_table_state = TableState.PLAYING
	_clear_match()
	_move_camera_to_match_view()
	_game_over = false
	_current_turn = "player"
	_selected_player_card = null

	var player_pool: Array[Dictionary] = _build_player_pool()
	var enemy_pool: Array[Dictionary] = _build_enemy_pool()

	if player_pool.is_empty():
		push_error("Spieler hat keine Karten in der Sammlung — Kampf kann nicht starten.")
		status_label.text = "Keine Karten in deiner Sammlung!"
		return

	if enemy_pool.is_empty():
		push_error("Keine Karten deiner in der CardDatabase gefunden.")
		status_label.text = "Keine Kartendaten gefunden!"
		return

	player_pool.shuffle()
	enemy_pool.shuffle()
	player_pool = _limit_deck_size(player_pool, deck_size)
	enemy_pool = _limit_deck_size(enemy_pool, deck_size)

	_player_deck = player_pool
	_enemy_deck = enemy_pool

	for i: int in range(HAND_SIZE):
		_draw_to_slot("player", i, false)
		_draw_to_slot("enemy", i, false)

	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")

	_update_status_for_current_turn()


# Baut den Ziehstapel des Spielers aus seiner Sammlung. Jede besessene
# card_id wird entsprechend ihrer Anzahl (get_amount) mehrfach in den
# Pool gelegt, damit Karten, die man oft hat, auch oefter vorkommen
# koennen — falls CollectionManager das nicht unterstuetzt, faellt das
# einfach auf "einmal pro besessener Karte" zurueck.
func _build_player_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []

	var deck_cards := DeckManager.get_deck_cards()

	for card_id in deck_cards:
		var data: Dictionary = CardDatabase.get_card(str(card_id))
		if data.is_empty():
			continue
		var upgraded_data := CardUpgradeManager.apply_upgrades(str(card_id), data)
		pool.append(CardData.merge_card_and_instance(upgraded_data))

	return pool


func _build_enemy_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var all_cards: Array = CardDatabase.get_all_cards()

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
# Baut den sichtbaren Ruecken-Stapel fuer eine Seite komplett neu auf,
# basierend auf der aktuellen Deckgroesse (gecappt auf
# MAX_VISIBLE_STACK_CARDS). Wird einmal beim Matchstart aufgerufen.
func _rebuild_stack_visual(side: String) -> void:
	var visuals: Array[Card3D] = _player_stack_visuals if side == "player" else _enemy_stack_visuals
	var deck: Array[Dictionary] = _player_deck if side == "player" else _enemy_deck
	var deck_marker: Marker3D = player_deck_marker if side == "player" else enemy_deck_marker

	for old_card: Card3D in visuals:
		if is_instance_valid(old_card):
			old_card.queue_free()
	visuals.clear()

	var visible_count: int = int(min(deck.size(), MAX_VISIBLE_STACK_CARDS))

	for i: int in range(visible_count):
		var deco: Card3D = _spawn_stack_decoration_card(deck_marker.global_position + STACK_LAYER_OFFSET * i)
		visuals.append(deco)


# Erzeugt eine einzelne, rein optische "verdeckte" Karte (Rueckseite
# zur Kamera) ohne Spieldaten/Klick-Interaktion/Shine-Effekt.
func _spawn_stack_decoration_card(target_global_pos: Vector3) -> Card3D:
	var card: Card3D = card_scene.instantiate() as Card3D
	card.is_stack_decoration = true
	add_child(card)

	card.global_position = target_global_pos
	# Um die X-Achse um 180° gegenueber der normalen "liegenden"
	# Ausrichtung (-90, 0, 0) gedreht, damit die Vorderseite (Bild +
	# Labels) nach unten zum Tisch zeigt und die Rueckseite nach oben
	# zur Kamera.
	card.rotation_degrees = Vector3(90, 180, 0)

	return card


# Entfernt die oberste sichtbare Ruecken-Karte eines Stapels (falls
# vorhanden) — wird aufgerufen, wann immer eine echte Karte vom Deck
# gezogen wird, damit der sichtbare Stapel synchron mit der tatsaechlich
# verbleibenden Deckgroesse kleiner wird.
func _pop_stack_visual(side: String) -> void:
	var visuals: Array[Card3D] = _player_stack_visuals if side == "player" else _enemy_stack_visuals

	if visuals.is_empty():
		return

	var top: Card3D = visuals.pop_back()
	if is_instance_valid(top):
		top.queue_free()


# --- Karten ziehen ---------------------------------------------------------

# Zieht die oberste Karte aus dem jeweiligen Deck und setzt sie in den
# angegebenen Slot. Wenn das Deck leer ist, bleibt der Slot leer (null).
# animated = true sorgt fuer einen kleinen Flug vom Stapel-Marker zum
# Slot, animated = false (Spielstart) platziert die Karte sofort.
func _draw_to_slot(side: String, slot_index: int, animated: bool) -> void:
	var deck: Array[Dictionary] = _player_deck if side == "player" else _enemy_deck
	var slots: Array[Card3D] = _player_slots if side == "player" else _enemy_slots
	var slot_marker: Marker3D = _get_slot_marker(side, slot_index)
	var deck_marker: Marker3D = player_deck_marker if side == "player" else enemy_deck_marker

	if deck.is_empty():
		slots[slot_index] = null
		return

	var data: Dictionary = deck.pop_back()
	_pop_stack_visual(side)

	var card: Card3D = card_scene.instantiate() as Card3D
	add_child(card)
	card.setup(data)
	_play_card_draw_sound(card)

	var target_pos: Vector3 = slot_marker.global_position
	var target_rot: Vector3 = Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 180, 180)

	if animated:
		card.global_position = deck_marker.global_position
		card.rotation_degrees = target_rot
		card.scale = Vector3.ONE * 0.6

		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(card, "global_position", target_pos, draw_animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector3.ONE, draw_animation_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		card.global_position = target_pos
		card.rotation_degrees = target_rot

	card.died.connect(_on_card_died.bind(side, slot_index))
	_connect_card_input(card, side, slot_index)

	slots[slot_index] = card


func _get_slot_marker(side: String, slot_index: int) -> Marker3D:
	return _player_slot_markers[slot_index] if side == "player" else _enemy_slot_markers[slot_index]


func _connect_card_input(card: Card3D, side: String, slot_index: int) -> void:
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
	if CardData.get_active_effects(card.card_data).is_empty():
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
	if not (event is InputEventMouseButton and event.is_pressed()):
		return

	var mouse_event := event as InputEventMouseButton

	var card := _get_card_from_slot(side, slot_index)
	if card == null:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_inspect_card(card)
		return

	if _game_over:
		return
	if _online_action_in_progress:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _current_turn != "player":
		return

	if side == "player":
		_select_player_card(slot_index)
	else:
		_try_attack_enemy(slot_index)

func _select_player_card(slot_index: int) -> void:
	var card: Card3D = _player_slots[slot_index]
	if card == null or not is_instance_valid(card):
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
			status_label.text = "Wähle nun die gegnerische Karte zum Angriff"
		else:
			status_label.text = "Du bist am Zug — wähle deine Karte"
		return

	if _selected_player_card == card:
		# Erneuter Klick auf dieselbe Karte hebt die Auswahl wieder auf.
		card.set_selected(false)
		_selected_player_card = null
		status_label.text = "Du bist am Zug — wähle deine Karte"
		return

	if _selected_player_card != null and is_instance_valid(_selected_player_card):
		_selected_player_card.set_selected(false)

	_selected_player_card = card
	card.set_selected(true)
	_play_sfx(select_sfx)
	status_label.text = "Wähle nun die gegnerische Karte zum Angriff"


func _try_attack_enemy(slot_index: int) -> void:
	if _selected_player_card == null:
		status_label.text = "Wähle zuerst eine eigene Karte"
		return

	var enemy_card: Card3D = _enemy_slots[slot_index]
	if enemy_card == null or not is_instance_valid(enemy_card):
		return

	var attacker: Card3D = _selected_player_card
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
			status_label.text = "Aktion wird an den Host gesendet..."
			_rpc_request_attack.rpc_id(1, attacker_slot, slot_index, _online_turn_sequence)
		return

	await _resolve_duel(attacker, enemy_card, "player")


# --- Kampf-Ablauf -----------------------------------------------------------

# Fuehrt ein Duell zwischen attacker und defender aus: beide Karten
# fuegen sich gegenseitig Schaden in Hoehe ihres Angriffswerts zu,
# unabhaengig davon ob die jeweils andere Karte dabei stirbt (beide
# Treffer gelten gleichzeitig). attacker_side bestimmt, wessen Zug das
# war, damit danach korrekt der naechste Zug eingeleitet wird.
func _resolve_duel(attacker: Card3D, defender: Card3D, attacker_side: String) -> void:
	if _game_over:
		return

	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	if attacker.consume_stun():
		status_label.text = "%s ist betäubt und setzt aus!" % str(attacker.card_data.get("name", "?"))
		_spawn_effect_vfx(attacker, stun_vfx_scene)
		await get_tree().create_timer(0.5).timeout
		_end_turn_to("enemy" if attacker_side == "player" else "player")
		return

	if _online_mode and _online_is_host:
		_broadcast_online_attack(attacker, defender)

	var attacker_name := str(attacker.card_data.get("name", "?"))
	var defender_name := str(defender.card_data.get("name", "?"))
	status_label.text = "%s kämpft gegen %s!" % [attacker_name, defender_name]

	var defender_slot_index := int(_find_slot_of(defender).get("index", -1))

	var total_damage_done := 0
	var defender_died := false
	var attacker_died := false
	var hit_count := CombatResolver.get_hit_count(attacker)

	for hit_index in range(hit_count):
		if not is_instance_valid(attacker) or not is_instance_valid(defender) or defender.is_dead():
			break

		attacker.play_attack_animation(defender.global_position)
		await attacker.attack_impact
		_shake_camera()

		if _game_over or not is_instance_valid(attacker) or not is_instance_valid(defender):
			return

		var damage := CombatResolver.get_attack_damage(
			attacker,
			_count_identical_on_board(str(attacker.card_data.get("id", attacker.card_data.get("card_id", ""))))
		)

		var hit_result := CombatResolver.apply_incoming_damage(defender, damage)

		if bool(hit_result.get("shield_blocked", false)):
			_spawn_effect_vfx(defender, shield_vfx_scene)

		if str(hit_result.get("survival_effect", "")) == "last_stand":
			_spawn_effect_vfx(defender, last_stand_vfx_scene)

		total_damage_done += int(hit_result.get("damage", 0))
		defender_died = bool(hit_result.get("died", false))

		var poison_effect := CardData.get_effect(attacker.card_data, "poison")
		if not poison_effect.is_empty() and is_instance_valid(defender) and not defender_died:
			defender.set_meta("poison_damage", int(poison_effect.get("damage", 3)))
			defender.set_meta("poison_turns", int(poison_effect.get("turns", 3)))
			_spawn_effect_vfx(defender, poison_vfx_scene)

		if CardData.has_effect(attacker.card_data, "execute") and is_instance_valid(defender):
			var threshold := float(CardData.get_effect(attacker.card_data, "execute").get("threshold", 0.25))
			if float(defender.current_hp) <= float(defender.max_hp) * threshold:
				defender_died = defender.take_damage(defender.current_hp)

		var damage_intensity : float = clamp(
			float(damage) / max(1.0, float(defender.max_hp)),
			0.45,
			1.6
		)

		if defender_died and is_instance_valid(defender):
			_spawn_blood_from_card(defender, damage_intensity)
			_spawn_blood_decal_under_card(defender, true)

		if is_instance_valid(attacker) and is_instance_valid(defender):
			var thorns_damage_taken := int(hit_result.get("damage", 0))
			var thorns_killed_attacker := CombatResolver.apply_thorns(defender, attacker, thorns_damage_taken)

			if thorns_damage_taken > 0 and not CardData.get_effect(defender.card_data, "thorns").is_empty():
				_spawn_effect_vfx(defender, thorns_vfx_scene)

			attacker_died = attacker_died or thorns_killed_attacker

		if is_instance_valid(attacker) and is_instance_valid(defender):
			var counter_damage := defender.attack_value
			var counter_result := CombatResolver.apply_incoming_damage(attacker, counter_damage)

			if bool(counter_result.get("shield_blocked", false)):
				_spawn_effect_vfx(attacker, shield_vfx_scene)

			if str(counter_result.get("survival_effect", "")) == "last_stand":
				_spawn_effect_vfx(attacker, last_stand_vfx_scene)

			attacker_died = attacker_died or bool(counter_result.get("died", false))

		_play_sfx(damage_sfx)

		if defender_died and is_instance_valid(defender):
			_remove_dead_card(defender)

		if attacker_died and is_instance_valid(attacker):
			_remove_dead_card(attacker)

		if is_instance_valid(attacker):
			await attacker.attack_finished

		if defender_died or attacker_died:
			break

	if not is_instance_valid(attacker):
		if _check_game_over():
			return
		_end_turn_to("enemy" if attacker_side == "player" else "player")
		return

	var lifesteal_heal := CombatResolver.heal_from_lifesteal(attacker, total_damage_done)
	if lifesteal_heal > 0:
		_spawn_heal_from_card(attacker)

	var poison := CardData.get_effect(attacker.card_data, "poison")
	if not poison.is_empty() and is_instance_valid(defender):
		_spawn_poison_from_card(defender)

	if CardData.has_effect(attacker.card_data, "stun") and is_instance_valid(defender) and not defender_died:
		defender.stun_next_attack()
		_spawn_effect_vfx(defender, stun_vfx_scene)

	var curse := CardData.get_effect(attacker.card_data, "curse")
	if not curse.is_empty() and is_instance_valid(defender) and not defender_died:
		defender.apply_curse(int(curse.get("value", 2)))
		_spawn_effect_vfx(defender, curse_vfx_scene)

	if is_instance_valid(attacker):
		_apply_cleave(attacker, defender_slot_index, attacker_side)

	if defender_died and is_instance_valid(attacker):
		if CardData.has_effect(attacker.card_data, "draw_on_kill"):
			var attacker_slot_info := _find_slot_of(attacker)
			var attacker_side_now := str(attacker_slot_info.get("side", ""))
			var attacker_slot_index := int(attacker_slot_info.get("index", -1))

			if attacker_side_now != "" and attacker_slot_index != -1:
				var slots: Array[Card3D] = _player_slots if attacker_side_now == "player" else _enemy_slots
				for i in range(slots.size()):
					if slots[i] == null:
						_draw_to_slot(attacker_side_now, i, true)
						break

		if CardData.has_effect(attacker.card_data, "chain_attack"):
			var target_slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
			var next_target := _pick_random_living_card(target_slots)

			if next_target != null and is_instance_valid(next_target):
				await get_tree().create_timer(0.25).timeout

				if is_instance_valid(attacker) and is_instance_valid(next_target):
					await _resolve_duel(attacker, next_target, attacker_side)
					return

	if attacker_died and is_instance_valid(attacker):
		_remove_dead_card(attacker)

	if _check_game_over():
		return

	_end_turn_to("enemy" if attacker_side == "player" else "player")
	
func _count_identical_on_board(card_id: String) -> int:
	var count := 0
	for card in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card) and str(card.card_data.get("id", card.card_data.get("card_id", ""))) == card_id:
			count += 1
	return max(count, 1)


func _apply_cleave(attacker: Card3D, center_slot_index: int, attacker_side: String) -> void:
	if not CardData.has_effect(attacker.card_data, "cleave"):
		return

	if center_slot_index == -1:
		return

	var slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
	var center := center_slot_index

	if center == -1:
		return

	var side_damage := int(round(float(attacker.attack_value) * 0.5))

	for idx in [center - 1, center + 1]:
		if idx < 0 or idx >= slots.size():
			continue

		var target := slots[idx]

		if target == null or not is_instance_valid(target):
			continue

		var result := CombatResolver.apply_incoming_damage(target, side_damage)
		if bool(result.get("shield_blocked", false)):
			_spawn_effect_vfx(target, shield_vfx_scene)
		if str(result.get("survival_effect", "")) == "last_stand":
			_spawn_effect_vfx(target, last_stand_vfx_scene)

		var cleave_intensity: float = clamp(
			float(side_damage) / max(1.0, float(target.max_hp)),
			0.25,
			0.9
		)

		if bool(result.get("died", false)):
			_spawn_blood_from_card(target, cleave_intensity)
			_spawn_blood_decal_under_card(target, true)
		_play_sfx(damage_sfx)

		if bool(result.get("died", false)):
			_remove_dead_card(target)


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


# Entfernt eine gestorbene Karte aus ihrem Slot und zieht sofort eine
# neue Karte vom zugehoerigen Deck an genau diese Slot-Position nach
# (falls das Deck noch Karten hat). Sicher mehrfach aufrufbar — steht
# die Karte bereits in keinem Slot mehr, passiert einfach nichts.
func _remove_dead_card(card: Card3D) -> void:
	var slot_info := _find_slot_of(card)
	var side: String = str(slot_info.get("side", ""))
	var slot_index: int = int(slot_info.get("index", -1))

	if slot_index == -1:
		return

	if side == "player":
		_player_slots[slot_index] = null
	else:
		_enemy_slots[slot_index] = null

	_selected_player_card = null

	if is_instance_valid(card):
		_play_sfx(kill_sfx)
		_spawn_blood_decal_under_card(card, true)
		_animate_card_death(card, side)

	_draw_to_slot(side, slot_index, true)

# Wird durch das "died"-Signal von Card3D ausgeloest. Die eigentliche
# Aufraeum-/Nachzieh-Logik passiert bereits synchron in _resolve_duel
# ueber _remove_dead_card, dieses Signal dient hier nur als zusaetzliche
# Absicherung/Erweiterungspunkt (z.B. fuer spaetere Death-Effekte) und
# loest selbst keine doppelte Verarbeitung aus.
func _on_card_died(_card: Card3D, _side: String, _slot_index: int) -> void:
	pass


# --- Zugwechsel & Gegner-KI --------------------------------------------------

func _end_turn_to(next_turn: String) -> void:
	if _online_mode and _online_is_host:
		_set_authoritative_online_selection("", -1)
	_current_turn = next_turn
	
	await _apply_start_turn_effects(next_turn)
	if _check_game_over():
		return

	if _online_mode:
		if _online_is_host:
			_online_turn_sequence += 1
		_online_action_in_progress = false
		_update_status_for_current_turn()
		if _online_is_host:
			_sync_online_state()
		return

	if next_turn == "enemy":
		status_label.text = "Gegner ist am Zug..."
		await get_tree().create_timer(enemy_turn_delay).timeout
		_play_enemy_turn()
	else:
		_update_status_for_current_turn()


func _update_status_for_current_turn() -> void:
	if _current_turn == "player":
		status_label.text = "Du bist am Zug — wähle deine Karte"
	else:
		status_label.text = "Gegner ist am Zug..."


# Automatischer Gegner-Zug: waehlt zufaellig eine eigene lebende Karte
# und zufaellig eine Spieler-Karte als Ziel, komplett ohne Spieler-
# Interaktion.
func _play_enemy_turn() -> void:
	if _game_over:
		return

	var enemy_card: Card3D = _pick_random_living_card(_enemy_slots)
	var target_card: Card3D = _pick_random_living_card(_player_slots)

	if enemy_card == null or target_card == null:
		# Sollte durch _check_game_over() eigentlich schon abgefangen
		# sein, aber zur Sicherheit hier nochmal pruefen.
		_check_game_over()
		return

	await _resolve_duel(enemy_card, target_card, "enemy")


func _pick_random_living_card(slots: Array[Card3D]) -> Card3D:
	var candidates: Array[Card3D] = []
	for card: Card3D in slots:
		if card != null and is_instance_valid(card):
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

	var reward := 0

	if not player_has_cards and not enemy_has_cards:
		status_label.text = "Unentschieden — du erhältst 5 Soul Coins."
		reward = 5
		_last_match_was_loss = false
	elif not player_has_cards:
		status_label.text = "Niederlage — du erhältst 2 Soul Coins."
		reward = 2
		_last_match_was_loss = true
	else:
		status_label.text = "Sieg! Du erhältst 10 Soul Coins."
		reward = 10
		_last_match_was_loss = false

	_set_satan_laughing(_last_match_was_loss)

	GameCurrency.add_coins(reward)
	var upgrade_ui := get_tree().get_first_node_in_group("upgrade_ui") as UpgradeUI
	if upgrade_ui != null:
		upgrade_ui.refresh_balance()

	end_buttons.visible = true
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	_online_action_in_progress = false

	if _online_mode and _online_is_host:
		_sync_online_state()

	return true

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


func _connect_menu_buttons() -> void:
	var ki_button: Table3DButton = mode_buttons.get_node("KIButton")
	var multiplayer_button: Table3DButton = mode_buttons.get_node("MultiplayerButton")

	ki_button.pressed.connect(_show_difficulty_menu)
	multiplayer_button.set_disabled(false)
	multiplayer_button.pressed.connect(_show_multiplayer_menu)

	difficulty_buttons.get_node("EasyButton").pressed.connect(_on_difficulty_selected.bind("easy"))
	difficulty_buttons.get_node("NormalButton").pressed.connect(_on_difficulty_selected.bind("normal"))
	difficulty_buttons.get_node("HardButton").pressed.connect(_on_difficulty_selected.bind("hard"))
	difficulty_buttons.get_node("InsaneButton").pressed.connect(_on_difficulty_selected.bind("insane"))

	end_buttons.get_node("ExitButton").pressed.connect(_on_exit_button_pressed)


func _connect_online_signals() -> void:
	if matchmaking_screen.has_signal("closed"):
		matchmaking_screen.connect("closed", _on_matchmaking_closed)

	if not NetworkManager.match_started.is_connected(_on_online_match_started):
		NetworkManager.match_started.connect(_on_online_match_started)
	if not NetworkManager.session_closed.is_connected(_on_online_session_closed):
		NetworkManager.session_closed.connect(_on_online_session_closed)
	if not NetworkManager.lobby_state_changed.is_connected(_on_online_lobby_state_changed):
		NetworkManager.lobby_state_changed.connect(_on_online_lobby_state_changed)


func _show_multiplayer_menu() -> void:
	if _online_mode:
		return

	_table_state = TableState.ONLINE_LOBBY
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false
	status_label.text = "Steam-Lobby"

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
	if _table_state == TableState.MENU:
		_show_multiplayer_menu()


func _on_online_match_started() -> void:
	if _online_mode:
		return
	_online_mode = true
	_online_is_host = NetworkManager.is_host
	_online_action_in_progress = false
	_online_reward_granted = false
	_online_disconnect_reason = ""
	_online_turn_sequence = 0
	_online_selected_side = ""
	_online_selected_slot = -1

	if matchmaking_screen.has_method("close_without_leaving"):
		matchmaking_screen.call("close_without_leaving")
	else:
		matchmaking_screen.visible = false

	_start_online_match()


func _start_online_match() -> void:
	_table_state = TableState.PLAYING
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
		status_label.text = "Host bereitet das Match vor..."
		_rpc_request_online_state.rpc_id(1)
		return

	var player_pool := _deck_from_player_payload(NetworkManager.local_player_data)
	var enemy_pool := _deck_from_player_payload(NetworkManager.remote_player_data)
	if player_pool.is_empty() or enemy_pool.is_empty():
		status_label.text = "Online-Match konnte nicht gestartet werden: Deck fehlt."
		_game_over = true
		_table_state = TableState.GAME_OVER
		end_buttons.visible = true
		return

	player_pool.shuffle()
	enemy_pool.shuffle()
	_player_deck = _limit_deck_size(player_pool, deck_size)
	_enemy_deck = _limit_deck_size(enemy_pool, deck_size)

	for i: int in range(HAND_SIZE):
		_draw_to_slot("player", i, false)
		_draw_to_slot("enemy", i, false)

	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")
	_update_status_for_current_turn()
	_sync_online_state()


func _deck_from_player_payload(payload: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_deck: Variant = payload.get("deck", [])
	if not (raw_deck is Array):
		return result

	for entry: Variant in raw_deck:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _on_online_session_closed(reason: String) -> void:
	if not _online_mode or _table_state != TableState.PLAYING:
		return

	_online_disconnect_reason = reason
	_online_action_in_progress = false
	_online_selected_side = ""
	_online_selected_slot = -1
	_clear_online_selection_visuals()
	_game_over = true
	_table_state = TableState.GAME_OVER
	status_label.text = reason if reason != "" else "Online-Verbindung wurde beendet."
	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_attack(attacker_slot: int, target_slot: int, turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host or _game_over:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkManager.is_connected_game_peer(sender_id):
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

	_set_authoritative_online_selection("", -1)
	_online_action_in_progress = true
	await _resolve_duel(attacker, defender, "enemy")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_card_selection(slot_index: int, turn_sequence: int) -> void:
	if not _online_mode or not _online_is_host or _game_over:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not NetworkManager.is_connected_game_peer(sender_id):
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
		_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot())
		return

	if slot_index == -1:
		_set_authoritative_online_selection("", -1)
		return

	var card := _enemy_slots[slot_index]
	if card == null or not is_instance_valid(card) or card.is_dead():
		_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot())
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
		if card == null or not is_instance_valid(card) or card.is_dead():
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
	if not _online_mode or _online_is_host or _game_over:
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


func _broadcast_online_attack(attacker: Card3D, defender: Card3D) -> void:
	if not NetworkManager.has_connected_opponent():
		return

	var attacker_info := _find_slot_of(attacker)
	var defender_info := _find_slot_of(defender)
	var attacker_side := str(attacker_info.get("side", ""))
	var defender_side := str(defender_info.get("side", ""))
	var attacker_slot := int(attacker_info.get("index", -1))
	var defender_slot := int(defender_info.get("index", -1))
	if attacker_side == "" or defender_side == "" or attacker_slot < 0 or defender_slot < 0:
		return

	_rpc_play_online_attack.rpc(attacker_side, attacker_slot, defender_side, defender_slot)


@rpc("authority", "call_remote", "reliable")
func _rpc_play_online_attack(
	canonical_attacker_side: String,
	attacker_slot: int,
	canonical_defender_side: String,
	defender_slot: int
) -> void:
	if not _online_mode or _online_is_host or _game_over:
		return

	var local_attacker_side := _canonical_side_to_local(canonical_attacker_side)
	var local_defender_side := _canonical_side_to_local(canonical_defender_side)
	var attacker := _get_card_from_slot(local_attacker_side, attacker_slot)
	var defender := _get_card_from_slot(local_defender_side, defender_slot)
	if attacker == null or defender == null or not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	attacker.clear_selected_immediate()
	attacker.play_attack_animation(defender.global_position)
	status_label.text = "%s greift %s an..." % [
		str(attacker.card_data.get("name", "?")),
		str(defender.card_data.get("name", "?")),
	]


func _canonical_side_to_local(canonical_side: String) -> String:
	if _online_is_host:
		return canonical_side
	return "enemy" if canonical_side == "player" else "player"


func _sync_online_state() -> void:
	if not _online_mode or not _online_is_host or not NetworkManager.has_connected_opponent():
		return
	_rpc_apply_online_state.rpc(_build_online_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_online_state() -> void:
	if not _online_mode or not _online_is_host or not NetworkManager.has_connected_opponent():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return
	_rpc_apply_online_state.rpc_id(sender_id, _build_online_snapshot())


func _build_online_snapshot() -> Dictionary:
	return {
		"current_turn": _current_turn,
		"turn_sequence": _online_turn_sequence,
		"selected_side": _online_selected_side,
		"selected_slot": _online_selected_slot,
		"game_over": _game_over,
		"winner": _get_canonical_winner(),
		# Hidden draw order/card data stays on the authority. Clients only need
		# counts to render the two face-down piles.
		"player_deck_count": _player_deck.size(),
		"enemy_deck_count": _enemy_deck.size(),
		"player_slots": _serialize_online_slots(_player_slots),
		"enemy_slots": _serialize_online_slots(_enemy_slots),
	}


func _serialize_online_slots(slots: Array[Card3D]) -> Array:
	var result: Array = []
	for card: Card3D in slots:
		if card == null or not is_instance_valid(card):
			result.append(null)
		else:
			result.append(card.get_network_state())
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
	if _online_is_host:
		return

	if not _online_mode:
		_online_mode = true
		_online_is_host = false
		_online_reward_granted = false
		if matchmaking_screen.has_method("close_without_leaving"):
			matchmaking_screen.call("close_without_leaving")
		else:
			matchmaking_screen.visible = false
		_move_camera_to_match_view()

	_table_state = TableState.PLAYING
	_clear_match()

	# The host's canonical "enemy" side belongs to the client. Mirror both
	# decks and slot arrays so each player always interacts with the near side.
	_player_deck = _network_placeholder_deck(int(state.get("enemy_deck_count", 0)))
	_enemy_deck = _network_placeholder_deck(int(state.get("player_deck_count", 0)))
	_restore_online_slots("player", state.get("enemy_slots", []))
	_restore_online_slots("enemy", state.get("player_slots", []))
	_rebuild_stack_visual("player")
	_rebuild_stack_visual("enemy")

	var canonical_turn := str(state.get("current_turn", "player"))
	_current_turn = _canonical_side_to_local(canonical_turn)
	_online_turn_sequence = int(state.get("turn_sequence", _online_turn_sequence))
	_online_selected_side = str(state.get("selected_side", ""))
	_online_selected_slot = int(state.get("selected_slot", -1))
	_game_over = bool(state.get("game_over", false))
	_online_action_in_progress = false
	if _online_selected_side != canonical_turn:
		_online_selected_side = ""
		_online_selected_slot = -1
	_apply_online_selection_visual(_online_selected_side, _online_selected_slot)

	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = _game_over

	if _game_over:
		_table_state = TableState.GAME_OVER
		_apply_online_result(str(state.get("winner", "draw")))
	else:
		_update_status_for_current_turn()


func _network_placeholder_deck(card_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _index in range(clampi(card_count, 0, deck_size)):
		result.append({})
	return result


func _restore_online_slots(side: String, value: Variant) -> void:
	if not (value is Array):
		return
	var states := value as Array
	for slot_index in range(mini(states.size(), HAND_SIZE)):
		var state: Variant = states[slot_index]
		if state is Dictionary and not (state as Dictionary).is_empty():
			_spawn_card_from_network_state(side, slot_index, state as Dictionary)


func _spawn_card_from_network_state(side: String, slot_index: int, state: Dictionary) -> void:
	var card := card_scene.instantiate() as Card3D
	add_child(card)
	card.apply_network_state(state)
	card.global_position = _get_slot_marker(side, slot_index).global_position
	card.rotation_degrees = Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 180, 180)
	card.died.connect(_on_card_died.bind(side, slot_index))
	_connect_card_input(card, side, slot_index)

	if side == "player":
		_player_slots[slot_index] = card
	else:
		_enemy_slots[slot_index] = card


func _apply_online_result(canonical_winner: String) -> void:
	var reward := 0
	match canonical_winner:
		"enemy":
			status_label.text = "Sieg! Du erhältst 10 Soul Coins."
			reward = 10
			_last_match_was_loss = false
		"player":
			status_label.text = "Niederlage — du erhältst 2 Soul Coins."
			reward = 2
			_last_match_was_loss = true
		_:
			status_label.text = "Unentschieden — du erhältst 5 Soul Coins."
			reward = 5
			_last_match_was_loss = false

	_set_satan_laughing(_last_match_was_loss)

	if _online_reward_granted:
		return
	_online_reward_granted = true
	GameCurrency.add_coins(reward)
	var upgrade_ui := get_tree().get_first_node_in_group("upgrade_ui") as UpgradeUI
	if upgrade_ui != null:
		upgrade_ui.refresh_balance()


func _show_main_menu() -> void:
	_table_state = TableState.MENU
	_set_satan_laughing(false)
	_clear_match()
	_move_camera_to_base_view()
	_reset_dealer_gun()

	mode_buttons.visible = true
	difficulty_buttons.visible = false
	end_buttons.visible = false

	status_label.text = "Wähle einen Spielmodus"


func _show_difficulty_menu() -> void:
	_table_state = TableState.DIFFICULTY_SELECT

	mode_buttons.visible = false
	difficulty_buttons.visible = true
	end_buttons.visible = false

	status_label.text = "Wähle eine KI-Schwierigkeit"


func _on_difficulty_selected(difficulty: String) -> void:
	_selected_difficulty = difficulty

	mode_buttons.visible = false
	difficulty_buttons.visible = false
	end_buttons.visible = false

	_start_match()


func _clear_match() -> void:
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
	if _effect_overview != null:
		_effect_overview.hide_overview()

func _limit_deck_size(pool: Array[Dictionary], size: int) -> Array[Dictionary]:
	var limited: Array[Dictionary] = []
	var max_count: int = min(pool.size(), size)

	for i: int in range(max_count):
		limited.append(pool[i])

	return limited


func _move_camera_to_match_view() -> void:
	if table_camera == null:
		return

	_inspected_card = null

	if _camera_tween != null:
		_camera_tween.kill()

	var target: Transform3D = _get_match_camera_transform()

	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)

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
	if table_camera == null:
		return

	_inspected_card = null

	if _camera_tween != null:
		_camera_tween.kill()

	_camera_tween = create_tween()
	_camera_tween.tween_property(
		table_camera,
		"global_transform",
		_camera_base_transform,
		match_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func leave_table_view() -> void:
	if _table_state == TableState.ONLINE_LOBBY or _online_mode:
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

func is_match_active() -> bool:
	return (
		_table_state == TableState.ONLINE_LOBBY
		or _table_state == TableState.PLAYING
		or _table_state == TableState.GAME_OVER
	)

func _animate_card_death(card: Card3D, side: String) -> void:
	if not is_instance_valid(card):
		return

	var death_marker: Marker3D = player_death_marker if side == "player" else enemy_death_marker
	var start_pos := card.global_position
	var end_pos := death_marker.global_position

	var smash_dir := (end_pos - start_pos).normalized()
	var side_dir := Vector3(-smash_dir.z, 0, smash_dir.x).normalized()

	var random_side := side_dir * _rng.randf_range(-0.45, 0.45)
	var launch_pos := end_pos + random_side
	launch_pos.y += _rng.randf_range(0.25, 0.55)

	card.set_selected(false)

	var tween := create_tween().set_parallel(true)

	tween.tween_property(card, "global_position", launch_pos, 0.22)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(card, "rotation_degrees", card.rotation_degrees + Vector3(
		_rng.randf_range(360, 720),
		_rng.randf_range(-240, 240),
		_rng.randf_range(540, 1080)
	), 0.22)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(card, "scale", Vector3.ZERO, 0.28)\
		.set_delay(0.06)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN)

	tween.finished.connect(func():
		if is_instance_valid(card):
			card.queue_free()
	)

func _play_sfx(sfx: AudioStreamPlayer) -> void:
	if sfx == null:
		return

	if sfx.playing:
		sfx.stop()

	sfx.play()

func _spawn_blood_from_card(card: Card3D, intensity: float = 1.0) -> void:
	if blood_burst_scene == null:
		return

	if card == null or not is_instance_valid(card):
		return

	var blood := blood_burst_scene.instantiate() as Node3D
	add_child(blood)

	blood.global_transform = Transform3D(
		Basis(),
		card.global_position + blood_spawn_offset
	)

	if blood.has_method("set_intensity"):
		blood.set_intensity(intensity)

func _spawn_blood_decal_under_card(card: Card3D, is_kill: bool = false) -> void:
	if blood_decal_scene == null:
		return

	if card == null or not is_instance_valid(card):
		return

	var decal := blood_decal_scene.instantiate() as Node3D
	add_child(decal)

	decal.global_position = card.global_position + blood_decal_offset
	decal.rotation_degrees = Vector3.ZERO

	# Zufällige Drehung, damit es nicht immer gleich aussieht.
	decal.rotate_y(_rng.randf_range(0.0, TAU))

	if decal.has_method("setup"):
		decal.setup(is_kill)

func _spawn_heal_from_card(card: Card3D) -> void:
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

	for card: Card3D in slots:
		if card == null or not is_instance_valid(card):
			continue

		var regen := CardData.get_effect(card.card_data, "regeneration")
		if not regen.is_empty():
			card.heal(int(regen.get("value", 3)))
			_spawn_effect_vfx(card, regeneration_vfx_scene)
			
		_apply_neighbor_heal(card)

		if card.has_meta("poison_turns"):
			var turns := int(card.get_meta("poison_turns"))
			var damage := int(card.get_meta("poison_damage"))

			if turns > 0:
				var died := card.take_damage(damage)
				_spawn_effect_vfx(card, poison_vfx_scene)
				card.set_meta("poison_turns", turns - 1)

				if died:
					_remove_dead_card(card)

			if turns - 1 <= 0:
				card.remove_meta("poison_turns")
				card.remove_meta("poison_damage")

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

		neighbor.heal(heal_amount)
		_spawn_heal_from_card(neighbor)

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
	if dealer_gun == null or not is_instance_valid(dealer_gun):
		return

	if pistol_start_marker == null or not is_instance_valid(pistol_start_marker):
		return

	dealer_gun.global_transform = pistol_start_marker.global_transform


func _set_satan_laughing(is_laughing: bool) -> void:
	if dealer_satan == null or not is_instance_valid(dealer_satan):
		return

	var target_texture: Texture2D = SATAN_LAUGH_TEXTURE if is_laughing else _satan_idle_texture
	if target_texture == null:
		return

	var target_frames := SATAN_LAUGH_FRAMES if is_laughing else SATAN_IDLE_FRAMES
	var target_fps := SATAN_LAUGH_FPS if is_laughing else SATAN_IDLE_FPS
	if dealer_satan.has_method("play_sheet"):
		dealer_satan.call("play_sheet", target_texture, target_frames, target_fps, true)
		return

	# Fallback, falls der Sprite spaeter ohne SpriteAnim-Script verwendet wird.
	dealer_satan.texture = target_texture
	dealer_satan.hframes = target_frames
	dealer_satan.vframes = 1
	dealer_satan.frame = 0


func _raise_dealer_gun() -> void:
	if dealer_gun == null or not is_instance_valid(dealer_gun):
		return

	if pistol_start_marker == null or not is_instance_valid(pistol_start_marker):
		return

	if pistol_end_marker == null or not is_instance_valid(pistol_end_marker):
		return

	dealer_gun.global_transform = pistol_start_marker.global_transform

	var tween := create_tween()
	tween.tween_property(
		dealer_gun,
		"global_transform",
		pistol_end_marker.global_transform,
		pistol_raise_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished


func _on_exit_button_pressed() -> void:
	if _loss_exit_running:
		return
	if _online_mode:
		_online_mode = false
		_online_is_host = false
		_online_action_in_progress = false
		if NetworkManager.has_active_session():
			NetworkManager.leave_lobby("Online-Match verlassen.")
		_show_main_menu()
		return

	if _last_match_was_loss:
		await _play_loss_exit_sequence()
	else:
		_show_main_menu()


func _play_loss_exit_sequence() -> void:
	_loss_exit_running = true
	end_buttons.visible = false

	# Kamera zurückfahren.
	_move_camera_to_base_view()
	await get_tree().create_timer(match_camera_duration + 0.15).timeout

	# Waffe nach oben bewegen.
	await _raise_dealer_gun()

	# Eine Sekunde mit erhobener Waffe warten.
	await get_tree().create_timer(1.0).timeout

	# Schuss.
	if flash_sprite != null:
		flash_sprite.visible = true

	if death_shot_sfx != null:
		death_shot_sfx.play()

	await get_tree().create_timer(0.1).timeout

	if flash_sprite != null:
		flash_sprite.visible = false

	# Bildschirm schwarz machen.
	_show_black_screen()

	# Einen Frame warten, damit Schwarz garantiert gezeichnet wird.
	await get_tree().process_frame

	# Unsichtbar hinter dem Schwarz alles zurücksetzen.
	_show_main_menu()
	_reset_dealer_gun()

	# Gehör wiederherstellen.
	await _play_hearing_recovery()

	await get_tree().create_timer(1.0).timeout

	# Schwarz wieder ausblenden.
	await _fade_black_screen_out(2.0)

	_loss_exit_running = false
	
func _show_black_screen() -> void:
	if _black_layer == null:
		_black_layer = CanvasLayer.new()
		_black_layer.name = "LossBlackLayer"
		add_child(_black_layer)

	if _black_rect == null:
		_black_rect = ColorRect.new()
		_black_rect.name = "BlackRect"
		_black_rect.color = Color.BLACK
		_black_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_black_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_black_layer.add_child(_black_rect)

	_black_rect.visible = true
	_black_rect.modulate.a = 1.0


func _fade_black_screen_out(duration: float) -> void:
	if _black_rect == null:
		return

	var tween := create_tween()
	tween.tween_property(_black_rect, "modulate:a", 0.0, duration)
	await tween.finished

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

	var configured_master_db := AudioServer.get_bus_volume_db(master_bus)

	AudioServer.set_bus_effect_enabled(master_bus, 0, true)

	lowpass.cutoff_hz = 350.0
	AudioServer.set_bus_volume_db(master_bus, -80.0)

	await get_tree().create_timer(0.8).timeout

	var volume_tween := create_tween()
	volume_tween.tween_method(
		func(db: float) -> void:
			AudioServer.set_bus_volume_db(master_bus, db),
		-80.0,
		configured_master_db,
		2.5
	)

	var filter_tween := create_tween()
	filter_tween.tween_method(
		func(freq: float) -> void:
			lowpass.cutoff_hz = freq,
		350.0,
		20000.0,
		3.0
	)

	# Nur auf den längeren Tween warten.
	await filter_tween.finished

	AudioServer.set_bus_volume_db(master_bus, configured_master_db)
	lowpass.cutoff_hz = 20000.0
	AudioServer.set_bus_effect_enabled(master_bus, 0, false)
	
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
	player.global_position = card.global_position
	add_child(player)

	player.play()
	player.finished.connect(player.queue_free)
