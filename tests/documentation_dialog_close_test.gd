extends Node

func _ready() -> void:
	GameCurrency.set_process(false)
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	var actor := Sprite3D.new()
	actor.texture = load("res://assets/characters/angel/angel.png")
	actor.hframes = 18
	actor.position.z = -5
	viewport.add_child(actor)
	var dialog := AngelDialogue.new()
	dialog.camera = camera
	dialog.actor = actor
	viewport.add_child(dialog)
	dialog.set_interaction_enabled(true)
	if not dialog.open_dialog():
		push_error("Could not open production dialog")
		get_tree().quit(1)
		return
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	viewport.push_input(key, true)
	var started_closing := dialog._closing and dialog.is_dialog_open()
	await get_tree().create_timer(0.35).timeout
	var closed_after_animation := not dialog.is_dialog_open() and not dialog._closing
	var reopened := dialog.open_dialog()
	dialog.close_dialog()
	await get_tree().create_timer(0.35).timeout
	if not started_closing or not closed_after_animation or not reopened or dialog.is_dialog_open():
		push_error("Production animated close did not restore the dialog lifecycle")
		get_tree().quit(1)
		return
	viewport.queue_free()
	await get_tree().process_frame
	print("DOCUMENTATION_DIALOG_CLOSE_TESTS: PASS (4 checks)")
	get_tree().quit()
