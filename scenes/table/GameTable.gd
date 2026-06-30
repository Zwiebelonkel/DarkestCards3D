extends Node3D
class_name GameTable

const HAND_SIZE: int = 5

# Wie viele sichtbare Ruecken-Karten der Stapel maximal gleichzeitig
# zeigt. Bei sehr grossen Decks wuerde 1:1-Stapeln unnoetig viele
# Meshes erzeugen, daher wird die sichtbare Stapelhoehe auf diesen Wert
# gecappt — sieht trotzdem nach "vollem Stapel" aus.
const MAX_VISIBLE_STACK_CARDS: int = 10

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

@export_group("Timing")
@export var enemy_turn_delay: float = 0.9
@export var draw_animation_duration: float = 0.35

@export_group("Match Camera")
@export var match_camera_marker: Marker3D
@export var match_camera_use_export_rotation := true
@export var match_camera_rotation := Vector3(-68.0, 0.0, 0.0)
@export var match_camera_duration: float = 0.65



@export_group("Card Inspect Camera")
@export var inspect_camera_offset := Vector3(0, 1.65, 0.55)
@export var inspect_camera_duration := 0.35
@export var table_camera: Camera3D

@export_group("Match Settings")
@export_range(5, 100, 1) var deck_size: int = 20

enum TableState {
	MENU,
	DIFFICULTY_SELECT,
	PLAYING,
	GAME_OVER
}

var _table_state: TableState = TableState.MENU
var _selected_difficulty := "normal"

@onready var menu_root: Node3D = $MenuRoot
@onready var mode_buttons: Node3D = $MenuRoot/ModeButtons
@onready var difficulty_buttons: Node3D = $MenuRoot/DifficultyButtons
@onready var end_buttons: Node3D = $MenuRoot/EndButtons

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

# Vom Spieler bereits ausgewaehlte eigene Karte fuer das aktuelle Duell
# (null, solange noch keine gewaehlt wurde).
var _selected_player_card: Card3D = null

var _game_over: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Sichtbare Ruecken-Karten pro Stapel (nur Optik, keine Spieldaten).
var _player_stack_visuals: Array[Card3D] = []
var _enemy_stack_visuals: Array[Card3D] = []


func _ready() -> void:
	_rng.randomize()

	if table_camera == null:
		table_camera = $Camera3D

	_camera_base_transform = table_camera.global_transform
	_collect_slot_markers()
	_connect_menu_buttons()
	_show_main_menu()


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
		push_error("Keine Karten in der CardDatabase gefunden.")
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
		var weight := int(rarity_weights.get(rarity, 1))

		for i in range(weight):
			pool.append(
				CardData.merge_card_and_instance(
					data,
					CardData.create_instance(
						str(data.get("id", "")),
						1,
						PerkDatabase.roll_perks()
					)
				)
			)

	return pool

func _get_enemy_rarity_weights(difficulty: String) -> Dictionary:
	match difficulty:
		"easy":
			return {
				"common": 8,
				"rare": 3,
				"epic": 1,
				"legendary": 0
			}

		"normal":
			return {
				"common": 5,
				"rare": 4,
				"epic": 2,
				"legendary": 1
			}

		"hard":
			return {
				"common": 2,
				"rare": 4,
				"epic": 4,
				"legendary": 2
			}

		"insane":
			return {
				"common": 1,
				"rare": 2,
				"epic": 5,
				"legendary": 4
			}

		_:
			return {
				"common": 5,
				"rare": 4,
				"epic": 2,
				"legendary": 1
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

	if not card.area.input_event.is_connected(_on_card_clicked):
		card.area.input_event.connect(_on_card_clicked.bind(side, slot_index))


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
	attacker.set_selected(false)

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

	if attacker.consume_stun():
		status_label.text = "%s ist betäubt und setzt aus!" % str(attacker.card_data.get("name", "?"))
		await get_tree().create_timer(0.5).timeout
		_end_turn_to("enemy" if attacker_side == "player" else "player")
		return

	var attacker_name: String = str(attacker.card_data.get("name", "?"))
	var defender_name: String = str(defender.card_data.get("name", "?"))
	status_label.text = "%s kämpft gegen %s!" % [attacker_name, defender_name]

	var total_damage_done := 0
	var defender_died := false
	var attacker_died := false
	var hit_count := CombatResolver.get_hit_count(attacker)

	for hit_index in range(hit_count):
		if not is_instance_valid(attacker) or not is_instance_valid(defender) or defender.is_dead():
			break
		await attacker.play_attack_animation(defender.global_position)
		if _game_over or not is_instance_valid(attacker) or not is_instance_valid(defender):
			return
		var damage := CombatResolver.get_attack_damage(attacker, _count_identical_on_board(str(attacker.card_data.get("id", attacker.card_data.get("card_id", "")))))
		var hit_result := CombatResolver.apply_incoming_damage(defender, damage)
		total_damage_done += int(hit_result.get("damage", 0))
		defender_died = bool(hit_result.get("died", false))
		if CardData.has_effect(attacker.card_data, "execute") and float(defender.current_hp) <= float(defender.max_hp) * float(CardData.get_effect(attacker.card_data, "execute").get("threshold", 0.25)):
			defender_died = defender.take_damage(defender.current_hp)
		if defender_died:
			break

	CombatResolver.heal_from_lifesteal(attacker, total_damage_done)
	attacker_died = CombatResolver.apply_thorns(defender, attacker, total_damage_done)

	if is_instance_valid(attacker) and is_instance_valid(defender):
		var counter_damage := defender.attack_value
		var counter_result := CombatResolver.apply_incoming_damage(attacker, defender.attack_value)
		attacker_died = attacker_died or bool(counter_result.get("died", false))

	if CardData.has_effect(attacker.card_data, "stun") and is_instance_valid(defender):
		defender.stun_next_attack()
	var curse := CardData.get_effect(attacker.card_data, "curse")
	if not curse.is_empty() and is_instance_valid(defender):
		defender.apply_curse(int(curse.get("value", 2)))

	_apply_cleave(attacker, defender, attacker_side)

	if attacker_died:
		_remove_dead_card(attacker)
	if defender_died:
		_remove_dead_card(defender)

	if _check_game_over():
		return

	if attacker_side == "player":
		_end_turn_to("enemy")
	else:
		_end_turn_to("player")


func _count_identical_on_board(card_id: String) -> int:
	var count := 0
	for card in _player_slots + _enemy_slots:
		if card != null and is_instance_valid(card) and str(card.card_data.get("id", card.card_data.get("card_id", ""))) == card_id:
			count += 1
	return max(count, 1)


func _apply_cleave(attacker: Card3D, defender: Card3D, attacker_side: String) -> void:
	if not CardData.has_effect(attacker.card_data, "cleave"):
		return
	var slots: Array[Card3D] = _enemy_slots if attacker_side == "player" else _player_slots
	var center := slots.find(defender)
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
		if bool(result.get("died", false)):
			_remove_dead_card(target)


# Entfernt eine gestorbene Karte aus ihrem Slot und zieht sofort eine
# neue Karte vom zugehoerigen Deck an genau diese Slot-Position nach
# (falls das Deck noch Karten hat).
func _remove_dead_card(card: Card3D) -> void:
	var side: String = ""
	var slot_index: int = -1

	for i: int in range(HAND_SIZE):
		if _player_slots[i] == card:
			side = "player"
			slot_index = i
			break
		if _enemy_slots[i] == card:
			side = "enemy"
			slot_index = i
			break

	if slot_index == -1:
		return

	if side == "player":
		_player_slots[slot_index] = null
	else:
		_enemy_slots[slot_index] = null

	_selected_player_card = null

	if is_instance_valid(card):
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
	_current_turn = next_turn

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
	elif not player_has_cards:
		status_label.text = "Niederlage — du erhältst 2 Soul Coins."
		reward = 2
	else:
		status_label.text = "Sieg! Du erhältst 10 Soul Coins."
		reward = 10

	GameCurrency.add_coins(reward)
	var upgrade_ui := get_tree().get_first_node_in_group("upgrade_ui") as UpgradeUI
	if upgrade_ui != null:
		upgrade_ui.refresh_balance()

	end_buttons.visible = true
	mode_buttons.visible = false
	difficulty_buttons.visible = false

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
	multiplayer_button.set_disabled(true)

	difficulty_buttons.get_node("EasyButton").pressed.connect(_on_difficulty_selected.bind("easy"))
	difficulty_buttons.get_node("NormalButton").pressed.connect(_on_difficulty_selected.bind("normal"))
	difficulty_buttons.get_node("HardButton").pressed.connect(_on_difficulty_selected.bind("hard"))
	difficulty_buttons.get_node("InsaneButton").pressed.connect(_on_difficulty_selected.bind("insane"))

	end_buttons.get_node("ExitButton").pressed.connect(_show_main_menu)


func _show_main_menu() -> void:
	_table_state = TableState.MENU
	_clear_match()
	_move_camera_to_base_view()

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
	_game_over = false

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
	_move_camera_to_base_view()

	if _table_state == TableState.PLAYING or _table_state == TableState.GAME_OVER:
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
	return _table_state == TableState.PLAYING or _table_state == TableState.GAME_OVER

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
