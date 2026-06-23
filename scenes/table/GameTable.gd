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

@export_group("Timing")
@export var enemy_turn_delay: float = 0.9
@export var draw_animation_duration: float = 0.35

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
	_collect_slot_markers()
	_start_match()


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
	var owned: Dictionary = CollectionManager.get_owned_cards()

	for card_id: Variant in owned.keys():
		var data: Dictionary = CardDatabase.get_card(card_id)
		if data.is_empty():
			continue

		var amount: int = 1
		if CollectionManager.has_method("get_amount"):
			amount = int(max(int(CollectionManager.get_amount(card_id)), 1))

		for i: int in range(amount):
			pool.append(data)

	return pool


func _build_enemy_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var all_cards: Array = CardDatabase.get_all_cards()

	for data: Dictionary in all_cards:
		pool.append(data)

	return pool


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
	card.rotation_degrees = Vector3(90, 0, 0)

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
	var target_rot: Vector3 = Vector3(-90, 0, 0) if side == "player" else Vector3(-90, 0, 180)

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

func _on_card_clicked(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, side: String, slot_index: int) -> void:
	if _game_over:
		return

	if not (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.is_pressed()):
		return

	# Waehrend der Gegner-Zug laeuft, nimmt das Spiel keine Klicks an.
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

	var attacker_name: String = str(attacker.card_data.get("name", "?"))
	var defender_name: String = str(defender.card_data.get("name", "?"))
	status_label.text = "%s kämpft gegen %s!" % [attacker_name, defender_name]

	# Angriffsanimation: Karte fliegt zum Ziel, stupst es an, kehrt
	# zurueck. Der eigentliche Schaden wird erst danach angewendet,
	# damit der "Einschlag" optisch mit dem HP-Verlust zusammenfaellt.
	await attacker.play_attack_animation(defender.global_position)

	if _game_over or not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var attacker_damage: int = attacker.attack_value
	var defender_damage: int = defender.attack_value

	var defender_died: bool = defender.take_damage(attacker_damage)
	var attacker_died: bool = attacker.take_damage(defender_damage)

	# Kurze Pause, damit der Spieler die HP-Aenderung sehen kann, bevor
	# ggf. Karten verschwinden und neue nachgezogen werden.
	await get_tree().create_timer(0.5).timeout

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

	if is_instance_valid(card):
		card.queue_free()

	if side == "player":
		_player_slots[slot_index] = null
	else:
		_enemy_slots[slot_index] = null

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

	if not player_has_cards and not enemy_has_cards:
		status_label.text = "Unentschieden — beide Seiten ohne Karten!"
	elif not player_has_cards:
		status_label.text = "Niederlage — du hast keine Karten mehr."
	else:
		status_label.text = "Sieg! Der Gegner hat keine Karten mehr."

	return true


func _has_any_card(slots: Array[Card3D]) -> bool:
	for card: Card3D in slots:
		if card != null and is_instance_valid(card):
			return true
	return false
