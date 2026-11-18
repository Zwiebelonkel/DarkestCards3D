extends Node3D
class_name BasementCatEncounter
## One saved choice; the world actor and the shared camera are presentation only.

signal modal_changed(opened: bool)
signal encounter_finished(choice: String)

const LIVE_TEXTURE := preload("res://assets/characters/cat/cat.png")
const DEAD_TEXTURE := preload("res://assets/characters/cat/catDead.png")
const SPARE_TEXTURE := preload("res://assets/characters/cat/catSpare.png")
const PRESENTATION := preload("res://scripts/ui/CatChoicePresentation.gd")

@export var camera: Camera3D
@export var walk_start_position := Vector3(6.25, -1.87792, -7.2)
@export var walk_corner_position := Vector3(5.15, -1.87792, -3.6)
@export var walk_end_position := Vector3(5.8, -1.87792, 0)
@export_range(0.2, 8.0, 0.1) var walk_duration := 3.0
@export_range(0.1, 2.0, 0.05) var camera_focus_duration := 0.65
@export_range(0.1, 2.0, 0.05) var knockback_duration := 0.6
@export_range(0.5, 5.0, 0.1) var knockback_distance := 3.2

@onready var actor: Sprite3D = $Cat

var presentation: CatChoicePresentation
var state := "unseen"
var _context_enabled := false
var _suspended := false
var _choice_ready := false
var _committing := false
var _epoch := 0
var _walk_time := 0.0
var _motion_tween: Tween
var _camera_tween: Tween
var _shot_tween: Tween
var _camera_owned := false
var _camera_base_transform := Transform3D.IDENTITY
var _camera_aim_transform := Transform3D.IDENTITY
var _camera_base_fov := 58.0


func _ready() -> void:
	presentation = PRESENTATION.new()
	presentation.name = "CatChoicePresentation"
	add_child(presentation)
	presentation.choice_requested.connect(choose)
	presentation.shot_fired.connect(_on_shot_fired)
	GameCurrency.basement_cat_choice_changed.connect(_on_saved_choice_changed)
	GameCurrency.cat_clicker_changed.connect(_on_cat_clicker_changed)
	CollectionManager.collection_changed.connect(_on_collection_changed)
	_apply_saved_choice()


func _process(delta: float) -> void:
	if _suspended or state not in ["walking", "choice", "sparing", "spared"]:
		return
	_walk_time += delta
	actor.frame = int(_walk_time * (7.0 if state == "walking" else 2.0)) % 2


func is_busy() -> bool:
	return state in ["walking", "choice", "shooting", "sparing"]


func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	# Online PauseMenu is an overlay and deliberately does not pause the
	# SceneTree. Freeze our own presentation in either pause mode.
	for tween in [_motion_tween, _camera_tween, _shot_tween]:
		if tween != null and tween.is_valid():
			if suspended:
				tween.pause()
			else:
				tween.play()
	if is_instance_valid(presentation):
		presentation.set_suspended(suspended)


func set_context(enabled: bool) -> void:
	_context_enabled = enabled
	if enabled and state == "unseen" and not _suspended and is_instance_valid(camera):
		_start_encounter()
	elif not enabled and is_busy() and not _suspended:
		# A forced scene/room change safely ends presentation. Unchosen visits
		# can start again; a committed choice always restores from its save.
		_interrupt()


func _start_encounter() -> void:
	_epoch += 1
	var current_epoch := _epoch
	state = "walking"
	_choice_ready = false
	actor.texture = LIVE_TEXTURE
	actor.hframes = 2
	actor.frame = 0
	actor.rotation = Vector3.ZERO
	actor.position = walk_start_position
	actor.show()
	_walk_time = 0.0
	# Main releases hover focus and mouse tilt synchronously before we own
	# the camera's local pose. No new camera, HUD or alternate world is used.
	modal_changed.emit(true)
	_camera_base_transform = camera.transform
	_camera_base_fov = camera.fov
	_camera_owned = true
	var target := to_global(walk_end_position)
	var aimed := Transform3D(Basis.looking_at(target - camera.global_position, Vector3.UP), camera.global_position)
	_camera_aim_transform = (camera.get_parent() as Node3D).global_transform.affine_inverse() * aimed
	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "transform", _camera_aim_transform, camera_focus_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion_tween = create_tween()
	_motion_tween.tween_property(actor, "position", walk_corner_position, walk_duration * 0.5)
	_motion_tween.tween_property(actor, "position", walk_end_position, walk_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _motion_tween.finished
	if current_epoch != _epoch or state != "walking":
		return
	_motion_tween = null
	state = "choice"
	await presentation.show_choice(GameCurrency.BASEMENT_CAT_REWARD_COINS)
	if current_epoch == _epoch and state == "choice":
		_choice_ready = true


func choose(choice: String) -> Dictionary:
	if not _context_enabled or _suspended or get_tree().paused or state != "choice" or not _choice_ready or _committing:
		return {"ok": false, "reason": "busy"}
	_committing = true
	var result := GameCurrency.resolve_basement_cat_choice(choice)
	_committing = false
	if not bool(result.get("ok", false)):
		presentation.set_interaction_enabled(true)
		presentation.show_message(Localization.text("Die Entscheidung konnte nicht gespeichert werden. Bitte erneut versuchen."))
		return result
	_choice_ready = false
	state = "shooting" if choice == "shot" else "sparing"
	if choice == "spared":
		actor.texture = SPARE_TEXTURE
		actor.hframes = 2
		actor.frame = 0
		_walk_time = 0.0
	_resolve_presentation(choice, _epoch)
	return result


func _resolve_presentation(choice: String, current_epoch: int) -> void:
	if choice == "shot":
		await presentation.play_shot()
		if is_instance_valid(_shot_tween) and _shot_tween.is_running():
			await _shot_tween.finished
	else:
		await presentation.hide_choice()
	if current_epoch != _epoch or not is_inside_tree():
		return
	await _restore_camera()
	if current_epoch != _epoch or not is_inside_tree():
		return
	_apply_saved_choice()
	modal_changed.emit(false)
	encounter_finished.emit(choice)


func _on_shot_fired() -> void:
	if state != "shooting":
		return
	actor.hframes = 1
	actor.frame = 0
	actor.texture = DEAD_TEXTURE
	var direction := actor.global_position - camera.global_position
	direction.y = 0.0
	direction = direction.normalized()
	var start := actor.global_position
	_shot_tween = create_tween().set_parallel(true)
	_shot_tween.tween_property(actor, "global_position", start + direction * knockback_distance + Vector3.UP * 0.55, knockback_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shot_tween.tween_property(actor, "rotation:z", -0.85, knockback_duration)
	_shot_tween.chain().tween_callback(actor.hide)
	# Match the short impact beat without borrowing GameTable's battle state.
	if _camera_tween != null:
		_camera_tween.kill()
	_camera_tween = create_tween()
	var recoil := _camera_aim_transform
	recoil.basis = recoil.basis.rotated(Vector3.RIGHT, deg_to_rad(-1.2))
	_camera_tween.tween_property(camera, "transform", recoil, 0.055)
	_camera_tween.tween_property(camera, "transform", _camera_aim_transform, 0.17).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _restore_camera() -> void:
	if not _camera_owned or not is_instance_valid(camera):
		return
	if _camera_tween != null:
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "transform", _camera_base_transform, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _camera_tween.finished
	_camera_owned = false
	camera.fov = _camera_base_fov
	_camera_tween = null


func _on_saved_choice_changed(_choice: String) -> void:
	if not _committing:
		_interrupt()


func _apply_saved_choice() -> void:
	var saved := GameCurrency.get_basement_cat_choice()
	state = saved if not saved.is_empty() else "unseen"
	actor.texture = DEAD_TEXTURE if saved == "shot" else (SPARE_TEXTURE if saved == "spared" else LIVE_TEXTURE)
	actor.hframes = 1 if saved == "shot" else 2
	actor.frame = 0
	actor.rotation = Vector3.ZERO
	actor.position = walk_end_position if not saved.is_empty() else walk_start_position
	actor.visible = saved == "spared" and not GameCurrency.is_cat_clicker_active()
	_choice_ready = false


func _on_cat_clicker_changed(_active: bool) -> void:
	_on_collection_changed([])


func _on_collection_changed(_card_ids: Array[String]) -> void:
	if _committing or is_busy():
		return
	var saved := GameCurrency.get_basement_cat_choice()
	if state != (saved if not saved.is_empty() else "unseen"):
		_apply_saved_choice()
	elif state == "spared":
		actor.visible = not GameCurrency.is_cat_clicker_active()


func _interrupt() -> void:
	var was_busy := is_busy()
	_epoch += 1
	_stop_tweens()
	if is_instance_valid(presentation):
		presentation.reset_immediately()
	_restore_camera_immediately()
	_apply_saved_choice()
	if was_busy and is_inside_tree():
		modal_changed.emit(false)


func _stop_tweens() -> void:
	for tween in [_motion_tween, _camera_tween, _shot_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_motion_tween = null
	_camera_tween = null
	_shot_tween = null


func _restore_camera_immediately() -> void:
	if _camera_owned and is_instance_valid(camera):
		camera.transform = _camera_base_transform
		camera.fov = _camera_base_fov
	_camera_owned = false


func _exit_tree() -> void:
	_epoch += 1
	_stop_tweens()
	_restore_camera_immediately()
