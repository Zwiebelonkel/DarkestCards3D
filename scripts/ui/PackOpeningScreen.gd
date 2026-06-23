extends Node3D
class_name PackOpeningScreen

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")

@export var card_count := 5

@export_group("Pack Opening")
@export var pack_body_open_position := Vector3(0, -0.18, 0)
@export var pack_top_fly_position := Vector3(0, 3.5, -2.6)
@export var pack_top_fly_rotation := Vector3(-180, 35, 90)

@export_group("Cards In Pack")
@export var stack_base_position := Vector3(0, 0.62, -0.55)
@export var stack_position_offset := Vector3(0, 0.025, -0.018)
@export var stack_face_down_rotation := Vector3(-8, 180, 0)
@export var stack_card_scale := 0.82

@export_group("Reveal")
# FIX: Vorher war dies ein fixer Weltpunkt (0, 1.45, -1.45), zu dem JEDE
# Karte hinflog — egal wo sie im Pack-Stapel lag. Dadurch sah es so aus,
# als wuerde die Karte "nach hinten" zu einem Sammelpunkt schiessen statt
# sich einfach an Ort und Stelle zu zeigen.
# Jetzt: nur noch eine relative Anhebung in Y, ausgehend von der
# tatsaechlichen aktuellen Position der jeweiligen Karte.
@export var shoot_height_offset := 0.45

# Stapel der bereits gezogenen Karten
@export var revealed_stack_position := Vector3(1.0, 0.62, -0.55)
@export var revealed_stack_offset := Vector3(0.015, 0.02, -0.01)

@export var revealed_scale := 0.72
@export var revealed_rotation := Vector3(-8, 0, 0)

# Hover-Effekt: Karte im revealed_stack schiebt sich beim Hovern nach
# links aus dem Stapel heraus und dreht sich leicht, damit man sie
# besser sehen kann.
@export var revealed_hover_offset := Vector3(-0.25, 0, 0)
@export var revealed_hover_rotation_offset := Vector3(0, -25, 0)
@export var revealed_hover_duration := 0.18

@onready var pack: Node3D = $Pack
@onready var pack_mesh: MeshInstance3D = $Pack/PackMesh
@onready var pack_top: MeshInstance3D = $Pack/PackTop
@onready var pack_top_area: Area3D = $Pack/PackTop/PackTopArea
@onready var cards_root: Node3D = $Cards
@onready var info_label: Label3D = $InfoLabel

var _hovering_pack := false
var _opened := false
var _card_stack: Array[Card3D] = []
var _revealed_cards: Array[Card3D] = []

# Speichert pro Karte im revealed_stack deren Ruheposition (ohne Hover-
# Offset), damit beim Hover-Exit immer korrekt dorthin zurueckgetweent
# werden kann, unabhaengig davon wie oft rein/raus gehovert wurde.
var _revealed_rest_positions: Dictionary = {}

# Die zuletzt abgelegte Karte im revealed_stack ist absichtlich NICHT
# hoverable (z.B. weil sie ggf. noch ihre Animation abschliesst, oder
# weil die oberste Karte im Stapel optisch nicht herausragen soll).
# Sobald eine neue Karte abgelegt wird, wird der Hover der vorherigen
# obersten Karte (falls vorhanden) nachtraeglich aktiviert.
var _top_revealed_card: Card3D = null


func _ready() -> void:
	randomize()

	if pack_top_area:
		pack_top_area.mouse_entered.connect(func(): _hovering_pack = true)
		pack_top_area.mouse_exited.connect(func(): _hovering_pack = false)
		pack_top_area.input_event.connect(_on_pack_top_input)

	info_label.text = "PackTop anklicken/abziehen"


func _process(delta: float) -> void:
	if _opened or _hovering_pack:
		return

	pack.rotation.y += sin(Time.get_ticks_msec() * 0.002) * delta * 0.45
	pack.rotation.x = sin(Time.get_ticks_msec() * 0.0015) * 0.08


func _on_pack_top_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _opened:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_pack()


func _open_pack() -> void:
	_opened = true
	_hovering_pack = false
	info_label.text = "Pack wird geöffnet..."

	if pack_top_area:
		pack_top_area.monitoring = false

	var top_tween := create_tween().set_parallel(true)
	top_tween.tween_property(pack_top, "position", pack_top_fly_position, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_top, "rotation_degrees", pack_top_fly_rotation, 0.55)
	top_tween.tween_property(pack_top, "scale", Vector3.ZERO, 0.45)

	var body_tween := create_tween().set_parallel(true)
	body_tween.tween_property(pack, "position", pack_body_open_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	body_tween.tween_property(pack, "rotation_degrees", Vector3.ZERO, 0.25)

	await get_tree().create_timer(0.55).timeout
	pack_top.visible = false

	_spawn_cards_inside_pack()


func _spawn_cards_inside_pack() -> void:
	_clear_old_cards()

	var cards := CardDatabase.get_all_cards()
	if cards.is_empty():
		info_label.text = "Keine Karten gefunden"
		return

	cards.shuffle()

	for i in range(card_count):
		var data: Dictionary = CardDatabase.get_random_card_weighted()

		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.setup(data)

		card.position = Vector3(0, 0.15, -1.1)
		card.rotation_degrees = stack_face_down_rotation
		card.scale = Vector3.ONE * 0.01

		_card_stack.append(card)

		var final_pos := _get_stack_position(i)
		var final_rot := stack_face_down_rotation

		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", final_pos, 0.35 + i * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", final_rot, 0.35 + i * 0.05)
		tween.tween_property(card, "scale", Vector3.ONE * stack_card_scale, 0.25 + i * 0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.7).timeout

	_connect_top_card()
	info_label.text = "Oberste Karte anklicken"


func _get_stack_position(index: int) -> Vector3:
	return stack_base_position + stack_position_offset * index


# FIX: Vorher wurde "(_revealed_cards.size() - 1 - index)" verwendet.
# Da reveal_index in _reveal_top_card() bereits dem Index der NEU
# hinzugefuegten Karte entsprach (also immer "size() - 1" NACH dem append),
# kuerzte sich die Formel rechnerisch IMMER zu "* 0" weg.
# Ergebnis: jede neue Karte landete exakt auf revealed_stack_position,
# alle Karten lagen also ineinander statt versetzt zu stapeln.
#
# Jetzt: einfache, lineare Versetzung pro Index.
# index = 0 -> erste gezogene Karte (liegt unten im Stapel)
# index = (size-1) -> zuletzt gezogene Karte (liegt oben/zuoberst)
func _get_revealed_position(index: int) -> Vector3:
	return revealed_stack_position + revealed_stack_offset * index


func _get_top_card() -> Card3D:
	if _card_stack.is_empty():
		return null

	# Wichtig:
	# Vorher war vermutlich die letzte Karte im Array "top".
	# Für deinen sichtbaren Stapel ist aber die erste Karte die vorderste.
	return _card_stack[0]


func _connect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and not top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.connect(_on_top_card_input)

	print("Top Card klickbar: ", top_card.card_data.get("name", "Unknown"))


func _disconnect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.disconnect(_on_top_card_input)


func _on_top_card_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# FIX: _can_click_card existiert nicht mehr als Sperre fuer Spam-Klicks.
	# Stattdessen wird direkt geprueft, ob ueberhaupt noch eine Karte da ist,
	# der eigentliche Klick-Handler haengt ohnehin nur an der jeweils
	# aktuellen Top-Karte, die nach jedem Reveal sofort neu verbunden wird.
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var top_card := _get_top_card()
	if top_card == null:
		return

	_reveal_top_card(top_card)


# FIX: Diese Funktion ist jetzt NICHT mehr async/blockierend für den
# restlichen Spielablauf. Alles, was den Zustand betrifft (Karte aus
# _card_stack entfernen, naechste Karte verbinden, Stapel neu ausrichten),
# passiert SOFORT und synchron. Die Tweens (Flug-/Flip-Animation) laufen
# danach komplett unabhaengig im Hintergrund weiter — es wird nirgendwo
# mehr auf sie gewartet. Dadurch koennen beliebig viele Karten gleichzeitig
# in der Luft sein, wenn man schnell hintereinander klickt ("spammen").
func _reveal_top_card(card: Card3D) -> void:
	_disconnect_top_card()

	var card_id := str(card.card_data.get("id", ""))
	var card_name := str(card.card_data.get("name", card_id))

	if card_id != "":
		CollectionManager.add_card(card_id)

	info_label.text = card_name + " gezogen"

	_card_stack.erase(card)
	_revealed_cards.append(card)
	var reveal_index := _revealed_cards.size() - 1
	var final_pos := _get_revealed_position(reveal_index)

	# Sofort die naechste Karte (falls vorhanden) klickbar machen und
	# den verbleibenden Stapel an die richtigen Positionen ruecken —
	# unabhaengig davon, ob die gerade gezogene Karte ihre Animation
	# schon fertig hat.
	if _card_stack.is_empty():
		info_label.text = "Pack vollständig geöffnet"
	else:
		_realign_stack_in_pack()
		_connect_top_card()
		info_label.text = "Nächste Karte anklicken"

	# Die bisherige oberste Karte im revealed_stack wird jetzt von einer
	# neuen Karte "ueberholt" — sie darf jetzt ganz normal hoverable sein.
	var previous_top_card := _top_revealed_card
	if is_instance_valid(previous_top_card):
		_connect_revealed_hover(previous_top_card)

	_top_revealed_card = card

	_animate_revealed_card(card, final_pos)


# Reine Optik, komplett entkoppelt vom Spielablauf. Mehrere Aufrufe
# koennen parallel/ueberlappend laufen, da jede Karte ihren eigenen
# Tween bekommt und nichts auf ein await dieser Funktion wartet.
#
# FIX: Phase 1 ("Shoot") bewegt die Karte jetzt NUR noch nach oben,
# ausgehend von ihrer eigenen aktuellen X/Z-Position (statt zu einem
# fixen Weltpunkt zu fliegen, der bei jeder Karte woanders im Pack-
# Stapel ein "nach hinten" wirken liess). Erst Phase 2 ("Flip") gleitet
# die Karte seitlich zur finalen Position im revealed_stack.
#
# FIX: Vorher wurde nach Phase 1 mit einem fest verdrahteten Timer
# (0.22s) weitergemacht und nach Phase 2 GAR NICHT mehr gewartet,
# bevor der Hover-Effekt aktiviert wurde. Die Hover-Area der Karte
# war dadurch schon aktiv, WAEHREND die Karte noch mitten im Flug zum
# Stapel war — ein zufaelliges Hover-Event mitten in der Bewegung hat
# den laufenden Positions-Tween gekapert und die Animation sichtbar
# "abgeschnitten". Jetzt wird explizit auf das Ende JEDES Tweens
# gewartet (tween.finished), bevor die naechste Phase startet bzw.
# bevor ueberhaupt irgendein Hover moeglich ist.
func _animate_revealed_card(card: Card3D, final_pos: Vector3) -> void:
	var lift_position := card.position + Vector3(0, shoot_height_offset, 0)

	var shoot_tween := create_tween().set_parallel(true)
	shoot_tween.tween_property(card, "position", lift_position, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	shoot_tween.tween_property(card, "scale", Vector3.ONE * 1.05, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await shoot_tween.finished

	if not is_instance_valid(card):
		return

	var flip_tween := create_tween().set_parallel(true)
	flip_tween.tween_property(card, "rotation_degrees", revealed_rotation, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "position", final_pos, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "scale", Vector3.ONE * revealed_scale, 0.32)

	await flip_tween.finished

	if not is_instance_valid(card):
		return

	# Endgueltige Werte exakt setzen, damit keine Tween-Rundungsfehler
	# als Ruheposition/-rotation gespeichert werden.
	card.position = final_pos
	card.rotation_degrees = revealed_rotation

	_revealed_rest_positions[card] = final_pos
	# Hover wird hier bewusst NICHT aktiviert — das passiert erst, wenn
	# diese Karte durch eine neue oberste Karte "ueberholt" wird
	# (siehe _reveal_top_card).


# Aktiviert den Hover-Effekt fuer eine Karte im revealed_stack: beim
# Hovern schiebt sie sich per Tween nach links aus dem Stapel heraus
# und dreht sich leicht, beim Verlassen gleitet/dreht sie zurueck an
# ihre gespeicherte Ruheposition/-rotation.
func _connect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if not card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.connect(_on_revealed_card_hover_start.bind(card))
	if not card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.connect(_on_revealed_card_hover_end.bind(card))


# Deaktiviert den Hover-Effekt wieder (z.B. fuer die oberste Karte,
# die nicht hoverable sein soll) und tweent sie sicherheitshalber an
# ihre Ruheposition zurueck, falls sie gerade gehovert wurde.
func _disconnect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.disconnect(_on_revealed_card_hover_start)
	if card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.disconnect(_on_revealed_card_hover_end)


func _on_revealed_card_hover_start(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	# Die oberste (zuletzt abgelegte) Karte ist nie hoverable.
	if card == _top_revealed_card:
		return

	var rest_pos: Vector3 = _revealed_rest_positions[card]
	var hover_pos := rest_pos + revealed_hover_offset
	var hover_rot := revealed_rotation + revealed_hover_rotation_offset

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", hover_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rot, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_revealed_card_hover_end(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	var rest_pos: Vector3 = _revealed_rest_positions[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", rest_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", revealed_rotation, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _realign_stack_in_pack() -> void:
	for i in range(_card_stack.size()):
		var card := _card_stack[i]
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", _get_stack_position(i), 0.18)
		tween.tween_property(card, "rotation_degrees", stack_face_down_rotation, 0.18)


func _clear_old_cards() -> void:
	for card in _card_stack:
		if is_instance_valid(card):
			card.queue_free()

	for card in _revealed_cards:
		if is_instance_valid(card):
			card.queue_free()

	_card_stack.clear()
	_revealed_cards.clear()
	_revealed_rest_positions.clear()
	_top_revealed_card = null
