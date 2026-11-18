extends Node3D

## A cosmetic injection. Combat and poison state never wait for this animation.
const ENTRY_DURATION := 0.30
const PRESS_DURATION := 0.40
const EXIT_DURATION := 0.30
const DURATION := ENTRY_DURATION + PRESS_DURATION + EXIT_DURATION
const PLUNGER_TRAVEL := Vector3(0, 0, 1.10)
const ENTRY_OFFSET := Vector3(0, 1.35, -0.15)
const EXIT_OFFSET := Vector3(-0.15, 1.80, -0.30)
const TIP_OFFSET := Vector3(0, -0.025, 0)

@onready var pivot: Node3D = $InjectionPivot
@onready var plunger: Node3D = $InjectionPivot/Model/kolben
@onready var sound: AudioStreamPlayer3D = $Sound

var animation_finished := false
var _target: WeakRef
var _plunger_start := Vector3.ZERO
var _elapsed := 0.0
var _started := false
var _sound_started := false


func _ready() -> void:
	_plunger_start = plunger.position
	sound.finished.connect(_on_sound_finished)
	set_process(false)


func play_on(card: Card3D) -> void:
	_target = weakref(card)
	card.tree_exiting.connect(cancel)
	_started = true
	set_process(true)
	_apply_pose(0.0)


func _process(delta: float) -> void:
	if not _started or animation_finished:
		return
	var card := _target.get_ref() as Card3D
	if not is_instance_valid(card) or card.is_queued_for_deletion() or card.is_dead():
		cancel()
		return
	_elapsed += delta
	_apply_pose(_elapsed)
	if _elapsed >= ENTRY_DURATION and not _sound_started:
		_sound_started = true
		sound.play()
	if _elapsed >= DURATION:
		animation_finished = true
		pivot.hide()
		_target = null
		set_process(false)
		# Let the existing poison sound finish after the model has zipped away.
		if not sound.playing:
			queue_free()


func is_for(card: Card3D) -> bool:
	return _target != null and _target.get_ref() == card


func cancel() -> void:
	# Hide synchronously, before a dying card can start its death flight.
	animation_finished = true
	pivot.hide()
	sound.stop()
	_target = null
	set_process(false)
	queue_free()


func _on_sound_finished() -> void:
	if animation_finished:
		queue_free()


func _apply_pose(elapsed: float) -> void:
	var card := _target.get_ref() as Card3D if _target != null else null
	if is_instance_valid(card):
		position = (get_parent() as Node3D).to_local(card.global_position) + TIP_OFFSET
	if elapsed < ENTRY_DURATION:
		var t := clampf(elapsed / ENTRY_DURATION, 0.0, 1.0)
		pivot.position = ENTRY_OFFSET * pow(1.0 - t, 2.0)
		plunger.position = _plunger_start
	elif elapsed < ENTRY_DURATION + PRESS_DURATION:
		var t := clampf((elapsed - ENTRY_DURATION) / PRESS_DURATION, 0.0, 1.0)
		pivot.position = Vector3.ZERO
		plunger.position = _plunger_start + PLUNGER_TRAVEL * (1.0 - pow(1.0 - t, 2.0))
	else:
		var t := clampf((elapsed - ENTRY_DURATION - PRESS_DURATION) / EXIT_DURATION, 0.0, 1.0)
		pivot.position = EXIT_OFFSET * t * t
		plunger.position = _plunger_start + PLUNGER_TRAVEL
