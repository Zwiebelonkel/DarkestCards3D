extends Node3D
## The ritual reward follows the clicker's hinge until explicitly equipped.

const GUN_SCENE := preload("res://scenes/props/StoryShotgun.tscn")
const DIALOGUE := preload("res://scripts/main/SatanShotgunDialogue.gd")

var main: MainScene
var table: GameTable
var gun: Node3D
var held := false
var shots_fired := 0
var _busy := false
var _blocked_until_frame := -1
var _animation: Tween
var _hand_pose := Transform3D.IDENTITY
var _focus_resume: Dictionary = {}
var dialogue: AngelDialogue


func configure(owner_main: MainScene, owner_table: GameTable) -> void:
	main = owner_main
	table = owner_table
	gun = GUN_SCENE.instantiate()
	main.level_progress.shotgun_socket.add_child(gun)
	main.level_progress.shotgun = gun
	main.level_progress.shotgun_requested.connect(equip)
	# Only these HUD instances bypass depth/fog; the shrine retains its lighting.
	for mesh: Node in gun.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var material := instance.get_active_material(0).duplicate() as StandardMaterial3D
		material.no_depth_test = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog = true
		material.render_priority = 105
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	CollectionManager.collection_changed.connect(_on_collection_changed)
	_sync_ownership()


func is_busy() -> bool:
	return _busy


func blocks_satan_interactions() -> bool:
	return held or shots_fired > 0 or _busy


func _on_collection_changed(_ids: Array[String]) -> void:
	_sync_ownership()


func _sync_ownership() -> void:
	var owned: bool = CollectionManager.get_vault_ritual_state().shotgun_collected
	if not owned and held:
		stow()
	gun.visible = owned
	main.level_progress.shotgun_rack.visible = owned


func _process(_delta: float) -> void:
	if held:
		gun.visible = CollectionManager.get_vault_ritual_state().shotgun_collected and (_busy or _equipment_context_is_safe())
	# Match cinematics own Satan again; a later hub visit starts a new encounter.
	if shots_fired > 0 and table._satan_story_reaction == 0 and not _busy:
		shots_fired = 0


func _equipment_context_is_safe() -> bool:
	return (is_instance_valid(main) and main._can_turn(false)
		and not NetworkManager.has_active_session() and not NetworkManager.is_lobby_operation_pending()
		and not GameCurrency.is_training_session() and not table.is_offline_board_open()
		and table._table_state == GameTable.TableState.MENU)


func equip() -> void:
	if held or _busy or not CollectionManager.get_vault_ritual_state().shotgun_collected or not _equipment_context_is_safe():
		return
	held = true
	main._satan_jumpscare._stop_click_recoil()
	main._satan_stream.stop_pissing(true)
	gun.reparent(main.main_camera)
	# Imported barrels point along +Z, so turn them toward the camera's -Z.
	_hand_pose = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.85), Vector3(0.28, -0.28, -0.85))
	_animation = create_tween()
	_animation.tween_property(gun, "transform", _hand_pose, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_blocked_until_frame = Engine.get_process_frames() + 1
	main.level_progress.set_expanded(false)


func stow() -> void:
	if not held:
		return
	if _animation != null and _animation.is_valid():
		_animation.kill()
	held = false
	gun.reparent(main.level_progress.shotgun_socket, false)
	gun.transform = Transform3D.IDENTITY
	gun.show()
	_blocked_until_frame = Engine.get_process_frames() + 1


func handle_input(event: InputEvent) -> bool:
	if _busy:
		return event is InputEventMouseButton or event is InputEventKey
	if not held or not _equipment_context_is_safe() or Engine.get_process_frames() <= _blocked_until_frame:
		return false
	if not event is InputEventMouseButton or not event.pressed:
		return false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		stow()
		return true
	if (event.button_index != MOUSE_BUTTON_LEFT or main._active_room != 0 or main._active_side != 0
		or shots_fired >= 2 or not table.dealer_satan.is_visible_in_tree()
		or not table._is_satan_under_pointer(event.position)):
		return false
	_fire()
	return true


func _fire() -> void:
	_busy = true
	shots_fired += 1
	_focus_resume = main.screen_camera_focus.suspend_for_cinematic()
	main._pending_direction = 0
	main._set_journal_input_blocked(true)
	main.level_progress.set_enabled(false)
	main.access_key_tray.set_enabled(false)
	main.turn_arrows.refresh()
	if _animation != null and _animation.is_valid():
		_animation.kill()
	gun.transform = _hand_pose
	gun.get_node("ShotSound").play()
	gun.get_node("Muzzle/Flash").show()
	gun.get_node("Muzzle/Light").show()
	table.play_satan_story_reaction(shots_fired)
	var kick := _hand_pose
	kick.origin += Vector3(0, 0.045, 0.09)
	kick.basis = _hand_pose.basis * Basis(Vector3.RIGHT, deg_to_rad(-7))
	_animation = create_tween()
	_animation.tween_property(gun, "transform", kick, 0.06)
	_animation.tween_callback(func() -> void:
		gun.get_node("Muzzle/Flash").hide()
		gun.get_node("Muzzle/Light").hide()
	)
	_animation.tween_property(gun, "transform", _hand_pose, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _animation.finished
	if shots_fired == 1:
		dialogue = DIALOGUE.new()
		dialogue.name = "SatanShotgunDialogue"
		dialogue.actor = table.dealer_satan
		dialogue.camera = main.main_camera
		add_child(dialogue)
		dialogue.interaction_enabled = true
		if dialogue.open_dialog():
			await dialogue.modal_changed
		dialogue.queue_free()
		dialogue = null
	else:
		# Let every authored Kill frame play once and hold the final frame.
		while table.dealer_satan.is_processing() and table.dealer_satan.texture == table.SATAN_KILL_TEXTURE:
			await get_tree().process_frame
	_busy = false
	_blocked_until_frame = Engine.get_process_frames() + 1
	main._cinematic_input_block_frame = Engine.get_process_frames() + 1
	main._set_journal_input_blocked(false)
	main.screen_camera_focus.resume_after_cinematic(_focus_resume)
	main.turn_arrows.refresh()
