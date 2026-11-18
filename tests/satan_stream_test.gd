extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var table: GameTable
var scare
var stream


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	failures += 0 if condition else 1
	print(("PASS " if condition else "FAIL ") + label)


func _click(button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	table.satan_hover_area.input_event.emit(main.main_camera, event, Vector3.ZERO, Vector3.ZERO, 0)


func _settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _reset() -> void:
	stream.stop_pissing(true)
	scare._click_times.clear()
	scare._cooldown_until = 0


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	AudioServer.set_bus_mute(0, true)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	scare = main._satan_jumpscare
	stream = main._satan_stream
	await _settle(0.5)
	check(not stream.active and not stream.particles.emitting and not stream.piss_sfx.playing, "the imported scene is idle on entry")
	check(stream.get_parent() == table.dealer_satan and table.dealer_satan.get_node("Piss") == stream,
		"Piss is an authored child of Satan inside GameTable.tscn")
	var authored_position: Vector3 = stream.position
	stream.position += Vector3(0.02, 0.03, 0.01)
	check(stream.get_child_count() == 2 and stream.particles.draw_pass_1 is RibbonTrailMesh
		and stream.particles.amount <= 420, "the supplied ribbon scene stays within its three-node, one-emitter budget")
	_click(MOUSE_BUTTON_RIGHT)
	_click(MOUSE_BUTTON_LEFT, false)
	_click()
	check(not stream.active, "right clicks, releases and a single click cannot start the stream")
	_click()
	check(stream.active and stream.particles.emitting and stream.piss_sfx.playing and not scare.active,
		"two of four clicks trigger only the stream")
	check(AchievementManager.is_unlocked(AchievementManager.SATAN_PISS),
		"the actual two-click stream unlocks the Piss achievement")
	check(table._satan_stream_laughing and table.dealer_satan.texture == table.SATAN_LAUGH_TEXTURE
		and table.dealer_satan.fps == 32.0 and table._satan_laugh_audio._laughing
		and table._satan_laugh_audio.pitch_offset_semitones > 0.0,
		"Satan immediately starts fast looping laughter with faster voice during the stream")
	table._set_satan_hovered(true)
	table._set_satan_hovered(false)
	check(table.dealer_satan.texture == table.SATAN_LAUGH_TEXTURE and table.dealer_satan.fps == 32.0,
		"pointer hover cannot replace the stream's fast laughing animation")
	check(stream.source_position.distance_to(stream.global_position) < 0.001
		and stream.position.is_equal_approx(authored_position + Vector3(0.02, 0.03, 0.01)),
		"moving the scene node changes the actual emission point without resetting the authored position")
	await _settle(0.15)
	var initial_target: Vector3 = stream.target_position
	var initial_source_pose: Transform3D = stream.transform
	await _settle(0.2)
	var forward := -main.main_camera.global_basis.z
	forward.y = 0.0
	var center: Vector3 = main.main_camera.global_position - Vector3.UP * stream.target_drop + forward.normalized() * 0.2
	check(stream.target_position.distance_to(initial_target) > 0.03
		and is_equal_approx(stream.target_position.distance_to(center), stream.circle_radius),
		"the aim moves in a small circle around the lower player target")
	check(stream.transform.is_equal_approx(initial_source_pose)
		and stream.trajectory_position(stream.flight_seconds).distance_to(stream.target_position) < 0.001,
		"circling preserves the authored source transform and ballistic landing")
	var elapsed: float = stream._elapsed
	_click()
	check(stream._elapsed >= elapsed, "the third click does not restart or stack the stream")
	check(main._can_turn() and main._can_open_journal() and not main.pause_menu._cinematic_locked,
		"the halfway effect leaves normal controls available")
	await _settle(stream.spray_seconds)
	check(not stream.particles.emitting and not stream.piss_sfx.playing, "the stream and looping sound stop after their bounded duration")
	check(not table._satan_stream_laughing and not table._satan_laugh_audio._laughing
		and table._satan_laugh_audio.pitch_offset_semitones == 0.0
		and table.dealer_satan.texture != table.SATAN_LAUGH_TEXTURE and table.dealer_satan.fps == 15.0,
		"fast laughter stops and the ordinary animation returns as emission ends, before particles finish draining")
	await _settle(stream.particles.lifetime + stream.particles.trail_lifetime + 0.1)
	check(not stream.active and not stream.particles.visible, "remaining particles drain and the effect returns to idle")
	_reset()
	scare.clicks_required = 5
	_click()
	_click()
	check(not stream.active, "an odd threshold waits until half the clicks are reached")
	_click()
	check(stream.active and not scare.active, "three of five clicks trigger the halfway effect")
	_reset()
	scare.clicks_required = 4
	_click()
	await _settle(scare.click_window_seconds + 0.1)
	_click()
	check(not stream.active and scare._click_times.size() == 1, "slow clicks expire without triggering the halfway effect")
	_reset()
	scare._cooldown_until = Time.get_ticks_msec() + 1000
	for index in range(8):
		_click()
	check(not stream.active, "jumpscare cooldown also suppresses the halfway stream")
	_reset()
	_click()
	_click()
	table._table_state = GameTable.TableState.PLAYING
	await _settle()
	check(not stream.active and not stream.particles.visible and not stream.piss_sfx.playing,
		"starting another table interaction immediately clears particles and audio")
	table._table_state = GameTable.TableState.MENU
	_reset()
	_click()
	_click()
	NetworkManager.current_lobby_id = 123
	NetworkManager.lobby_state_changed.emit()
	check(not stream.active and not stream.piss_sfx.playing, "an incoming lobby cancels a halfway stream before a jumpscare exists")
	check(not table._satan_stream_laughing and not table._satan_laugh_audio._laughing,
		"lobby cancellation also immediately ends the stream laughter")
	NetworkManager.current_lobby_id = 0
	main.queue_free()
	await _settle()
	print("SATAN_STREAM_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
