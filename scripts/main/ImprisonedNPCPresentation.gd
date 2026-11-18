extends Node
## Owns only the four authored table sprites, independently of saved rewards.

signal presentation_changed

const ACTOR_NAMES := {"angel": "angelImprisoned", "dealer": "DealerImprisoned", "jester": "jesterImprisoned", "prisoner": "PrisonerImprisoned"}
enum State { HIDDEN, ENTERING, PRESENT, DEPARTING }

var reveal_duration := 1.6
var departure_duration := 1.15
var rise_distance := 1.1
var departure_distance := 3.5
var actors: Dictionary = {}
var origins: Dictionary = {}
var states: Dictionary = {}
var held_for_shot: Dictionary = {}
var _eligible: Array[String] = []
var _tweens: Dictionary = {}
var _main: Node3D
var _table: GameTable


func configure(main: Node3D, table: GameTable) -> void:
	_main = main
	_table = table
	for npc_id: String in ACTOR_NAMES:
		var actor := table.get_node(ACTOR_NAMES[npc_id]) as Sprite3D
		actors[npc_id] = actor
		origins[npc_id] = actor.position
		# Alpha scissoring would turn a gradual fade into a sudden cut. These
		# materials are private to the imprisoned copies, including eye glow.
		var material := actor.material_override.duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		actor.material_override = material
		actor.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_hide(npc_id)


func sync_waiting(waiting: Array[String], wait_for_shot: bool) -> void:
	for npc_id: String in actors:
		if held_for_shot.has(npc_id) and not GameCurrency.is_npc_rescued(npc_id):
			held_for_shot.erase(npc_id)
			_hide(npc_id)
		if _eligible.has(npc_id) and not waiting.has(npc_id) and wait_for_shot:
			held_for_shot[npc_id] = true
		if not waiting.has(npc_id) and not held_for_shot.has(npc_id):
			_hide(npc_id)
	_eligible.assign(waiting)


func is_awaiting_departure(npc_id: String) -> bool:
	return held_for_shot.has(npc_id)


func _can_reveal() -> bool:
	if not is_instance_valid(_main) or not is_instance_valid(_table) or get_tree().paused:
		return false
	if _main._active_room != 0 or _main._active_side != 0 or _main._phase != 0:
		return false
	if _main._room_transition_active or _main._door_key_view_active or _main._loss_cinematic_active or _main._greeting_active or _main._jumpscare_active or _main._npc_rescue_intro_active:
		return false
	if _main.pause_menu.visible or _main.pause_menu.settings_menu.visible or not _main.main_camera.is_current():
		return false
	var direction: Vector3 = (_table.dealer_satan.global_position - _main.main_camera.global_position).normalized()
	return (-_main.main_camera.global_basis.z).dot(direction) > 0.65


func _process(_delta: float) -> void:
	if not _can_reveal() or not held_for_shot.is_empty():
		return
	var delay := 0.0
	for npc_id in _eligible:
		if states[npc_id] == State.HIDDEN:
			_reveal(npc_id, delay)
			delay += 0.12


func _stop_tween(npc_id: String) -> void:
	var tween := _tweens.get(npc_id) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens.erase(npc_id)


func _hide(npc_id: String) -> void:
	_stop_tween(npc_id)
	var actor := actors[npc_id] as Sprite3D
	actor.visible = false
	actor.position = origins[npc_id]
	actor.transparency = 1.0
	states[npc_id] = State.HIDDEN


func _reveal(npc_id: String, delay: float) -> void:
	_stop_tween(npc_id)
	var actor := actors[npc_id] as Sprite3D
	actor.position = origins[npc_id] + Vector3(0, -rise_distance, -0.35)
	actor.transparency = 1.0
	actor.visible = true
	states[npc_id] = State.ENTERING
	var tween := create_tween().set_parallel(true)
	_tweens[npc_id] = tween
	tween.tween_property(actor, "position", origins[npc_id], reveal_duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor, "transparency", 0.0, reveal_duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_callback(_finish_reveal.bind(npc_id))


func _finish_reveal(npc_id: String) -> void:
	_tweens.erase(npc_id)
	states[npc_id] = State.PRESENT
	var actor := actors[npc_id] as Sprite3D
	actor.position = origins[npc_id]
	actor.transparency = 0.0


func depart_on_shot() -> void:
	for npc_id: String in held_for_shot.keys():
		if states[npc_id] == State.DEPARTING:
			continue
		var actor := actors[npc_id] as Sprite3D
		if not actor.visible:
			_finish_departure(npc_id)
			continue
		_stop_tween(npc_id)
		states[npc_id] = State.DEPARTING
		var satan_x := _table.to_local(_table.dealer_satan.global_position).x
		var direction := -1.0 if (origins[npc_id] as Vector3).x < satan_x else 1.0
		var destination: Vector3 = actor.position + Vector3(direction * departure_distance, 0.12, 0.0)
		var tween := create_tween().set_parallel(true)
		_tweens[npc_id] = tween
		tween.tween_property(actor, "position", destination, departure_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var fade_delay := departure_duration * 0.22
		tween.tween_property(actor, "transparency", 1.0, departure_duration - fade_delay).set_delay(fade_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(_finish_departure.bind(npc_id))


func _finish_departure(npc_id: String) -> void:
	held_for_shot.erase(npc_id)
	_hide(npc_id)
	presentation_changed.emit()


func finish_victory() -> void:
	# Skipping the film also skips its visual departure, without undoing the
	# already committed rescue or leaving a half-transparent actor behind.
	for npc_id: String in held_for_shot.keys():
		_hide(npc_id)
	held_for_shot.clear()
	presentation_changed.emit()


func _exit_tree() -> void:
	for npc_id: String in _tweens.keys():
		_stop_tween(npc_id)
