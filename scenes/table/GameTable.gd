extends Node3D

@export var card_scene: PackedScene

@export var starting_hand_size := 5
@export var player_deck_stack_size := 15
@export var enemy_deck_stack_size := 15
@export var visible_deck_cards := 8

@onready var info_label: Label3D = $InfoLabel
@onready var graveyard_pile: Marker3D = $GraveyardPile
@onready var player_deck_pile: Marker3D = $PlayerDeckPile
@onready var enemy_deck_pile: Marker3D = $EnemyDeckPile

var player_slots: Array[Marker3D] = []
var enemy_slots: Array[Marker3D] = []

var player_hand: Array[Card3D] = []
var enemy_hand: Array[Card3D] = []

var player_deck: Array[Dictionary] = []
var enemy_deck: Array[Dictionary] = []

var player_deck_visuals: Array[Card3D] = []
var enemy_deck_visuals: Array[Card3D] = []

var selected_player_card: Card3D = null
var player_turn := true
var battle_running := false


func _ready() -> void:
	randomize()
	_collect_markers()
	_start_battle()


func _collect_markers() -> void:
	player_slots = [
		$PlayerHand/PlayerSlot0,
		$PlayerHand/PlayerSlot1,
		$PlayerHand/PlayerSlot2,
		$PlayerHand/PlayerSlot3,
		$PlayerHand/PlayerSlot4
	]

	enemy_slots = [
		$EnemyHand/EnemySlot0,
		$EnemyHand/EnemySlot1,
		$EnemyHand/EnemySlot2,
		$EnemyHand/EnemySlot3,
		$EnemyHand/EnemySlot4
	]


func _start_battle() -> void:
	player_deck = _build_player_deck()
	enemy_deck = _build_enemy_deck()

	player_hand.clear()
	enemy_hand.clear()

	var draw_count: int = min(starting_hand_size, player_slots.size(), enemy_slots.size())

	for i in range(draw_count):
		player_hand.append(_draw_card_to_slot(player_deck, player_slots[i], true))
		enemy_hand.append(_draw_card_to_slot(enemy_deck, enemy_slots[i], false))

	_refresh_deck_visuals()

	player_turn = true
	battle_running = false
	selected_player_card = null
	info_label.text = "Dein Zug: eigene Karte wählen"


func _build_player_deck() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	var owned: Dictionary = CollectionManager.get_owned_cards()

	for raw_card_id in owned.keys():
		var card_id: String = str(raw_card_id)
		var amount: int = CollectionManager.get_amount(card_id)
		var data: Dictionary = CardDatabase.get_card(card_id)

		if data.is_empty():
			continue

		for i in range(amount):
			result.append(data)

	if result.is_empty():
		result = CardDatabase.get_all_cards()

	result.shuffle()

	var total_needed: int = player_deck_stack_size + starting_hand_size
	return result.slice(0, min(total_needed, result.size()))


func _build_enemy_deck() -> Array[Dictionary]:
	var result: Array[Dictionary] = CardDatabase.get_all_cards()
	result.shuffle()

	var total_needed: int = enemy_deck_stack_size + starting_hand_size
	return result.slice(0, min(total_needed, result.size()))


func _draw_card_to_slot(deck: Array[Dictionary], slot: Marker3D, is_player: bool) -> Card3D:
	if deck.is_empty():
		return null

	var data: Dictionary = deck.pop_front()

	var card := card_scene.instantiate() as Card3D
	add_child(card)

	card.setup(data)
	card.position = slot.position
	card.rotation_degrees = Vector3(-90, 0, 0)
	card.scale = Vector3.ONE

	card.set_meta("current_hp", int(data.get("defense", 1)))
	card.set_meta("is_player", is_player)

	if card.area:
		card.area.input_event.connect(_on_card_clicked.bind(card))

	return card


func _on_card_clicked(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int,
	card: Card3D
) -> void:
	if battle_running:
		return

	if not player_turn:
		return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var is_player_card: bool = bool(card.get_meta("is_player", false))

	if is_player_card:
		selected_player_card = card
		info_label.text = "Zielkarte des Gegners wählen"
		_highlight_card(card)
		return

	if selected_player_card != null and not is_player_card:
		await _resolve_duel(selected_player_card, card)
		selected_player_card = null
		_check_game_over()

		if not battle_running:
			await _enemy_turn()


func _highlight_card(card: Card3D) -> void:
	_unhighlight_all()

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position:y", card.position.y + 0.15, 0.12)
	tween.tween_property(card, "scale", Vector3.ONE * 1.08, 0.12)


func _unhighlight_all() -> void:
	for card in player_hand:
		if card != null and is_instance_valid(card):
			card.scale = Vector3.ONE


func _resolve_duel(attacker: Card3D, defender: Card3D) -> void:
	battle_running = true
	_unhighlight_all()

	var attacker_attack: int = int(attacker.card_data.get("attack", 0))
	var defender_attack: int = int(defender.card_data.get("attack", 0))

	var attacker_hp: int = int(attacker.get_meta("current_hp", attacker.card_data.get("defense", 1)))
	var defender_hp: int = int(defender.get_meta("current_hp", defender.card_data.get("defense", 1)))

	defender_hp -= attacker_attack
	attacker_hp -= defender_attack

	attacker.set_meta("current_hp", attacker_hp)
	defender.set_meta("current_hp", defender_hp)

	info_label.text = str(attacker.card_data.get("name", "")) + " vs " + str(defender.card_data.get("name", ""))

	await _duel_animation(attacker, defender)

	if attacker_hp <= 0:
		_destroy_and_replace(attacker)

	if defender_hp <= 0:
		_destroy_and_replace(defender)

	await get_tree().create_timer(0.25).timeout

	player_turn = not player_turn
	battle_running = false

	if player_turn:
		info_label.text = "Dein Zug: eigene Karte wählen"
	else:
		info_label.text = "Gegner ist am Zug"


func _duel_animation(a: Card3D, b: Card3D) -> void:
	var a_start: Vector3 = a.position
	var b_start: Vector3 = b.position
	var center: Vector3 = (a_start + b_start) * 0.5

	var tween := create_tween().set_parallel(true)
	tween.tween_property(a, "position", center + Vector3(-0.15, 0.12, 0), 0.18)
	tween.tween_property(b, "position", center + Vector3(0.15, 0.12, 0), 0.18)

	await get_tree().create_timer(0.2).timeout

	var back := create_tween().set_parallel(true)
	back.tween_property(a, "position", a_start, 0.18)
	back.tween_property(b, "position", b_start, 0.18)

	await get_tree().create_timer(0.2).timeout


func _destroy_and_replace(card: Card3D) -> void:
	var is_player_card: bool = bool(card.get_meta("is_player", false))
	var hand: Array[Card3D] = player_hand if is_player_card else enemy_hand
	var deck: Array[Dictionary] = player_deck if is_player_card else enemy_deck
	var slots: Array[Marker3D] = player_slots if is_player_card else enemy_slots

	var index: int = hand.find(card)
	if index == -1:
		return

	var death_pos: Vector3 = graveyard_pile.position

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", death_pos, 0.25)
	tween.tween_property(card, "scale", Vector3.ZERO, 0.25)

	await get_tree().create_timer(0.25).timeout

	card.queue_free()
	hand[index] = null

	if not deck.is_empty():
		var new_card: Card3D = _draw_card_to_slot(deck, slots[index], is_player_card)
		hand[index] = new_card

	_refresh_deck_visuals()


func _enemy_turn() -> void:
	await get_tree().create_timer(0.75).timeout

	if _is_game_over():
		return

	var enemy_cards: Array[Card3D] = _get_alive_cards(enemy_hand)
	var player_cards: Array[Card3D] = _get_alive_cards(player_hand)

	if enemy_cards.is_empty() or player_cards.is_empty():
		_check_game_over()
		return

	var attacker: Card3D = enemy_cards.pick_random()
	var defender: Card3D = player_cards.pick_random()

	info_label.text = "Gegner greift an..."

	await get_tree().create_timer(0.45).timeout
	await _resolve_duel(attacker, defender)
	_check_game_over()


func _get_alive_cards(hand: Array[Card3D]) -> Array[Card3D]:
	var result: Array[Card3D] = []

	for card in hand:
		if card != null and is_instance_valid(card):
			result.append(card)

	return result


func _check_game_over() -> void:
	if not _is_game_over():
		return

	battle_running = true

	var player_lost: bool = _get_alive_cards(player_hand).is_empty() and player_deck.is_empty()
	var enemy_lost: bool = _get_alive_cards(enemy_hand).is_empty() and enemy_deck.is_empty()

	if player_lost and enemy_lost:
		info_label.text = "Unentschieden"
	elif player_lost:
		info_label.text = "Du hast verloren"
	elif enemy_lost:
		info_label.text = "Du hast gewonnen"


func _is_game_over() -> bool:
	var player_empty: bool = _get_alive_cards(player_hand).is_empty() and player_deck.is_empty()
	var enemy_empty: bool = _get_alive_cards(enemy_hand).is_empty() and enemy_deck.is_empty()

	return player_empty or enemy_empty


func _refresh_deck_visuals() -> void:
	_clear_deck_visuals(player_deck_visuals)
	_clear_deck_visuals(enemy_deck_visuals)

	_create_deck_visuals(player_deck, player_deck_pile, player_deck_visuals)
	_create_deck_visuals(enemy_deck, enemy_deck_pile, enemy_deck_visuals)


func _clear_deck_visuals(visuals: Array[Card3D]) -> void:
	for card in visuals:
		if is_instance_valid(card):
			card.queue_free()

	visuals.clear()


func _create_deck_visuals(deck: Array[Dictionary], pile_marker: Marker3D, visuals: Array[Card3D]) -> void:
	var visible_count: int = min(deck.size(), visible_deck_cards)

	for i in range(visible_count):
		var data: Dictionary = deck[i]

		var card := card_scene.instantiate() as Card3D
		add_child(card)
		card.setup(data)

		card.position = pile_marker.position + Vector3(0, i * 0.015, -i * 0.01)
		card.rotation_degrees = Vector3(90, 0, 180)
		card.scale = Vector3.ONE * 0.82

		if card.area:
			card.area.monitoring = false

		visuals.append(card)
