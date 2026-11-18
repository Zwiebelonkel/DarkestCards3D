extends Node

const LOOK := {"face": "2", "hat": "angel", "mouth": "1", "eye_color": "22aaff"}
var failures := 0
var checks := 0
var main: MainScene
var table: GameTable
var standard_material: Material
var custom_texture: Texture2D
var finished := false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	print(("PASS " if condition else "FAIL ") + description)


func _wait_until(predicate: Callable, timeout_msec: int = 9000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Run with isolated player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	PlaytimeManager.complete_encounter()
	get_tree().root.size = Vector2i(1280, 720)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	# Test the actual table and cinematic paths without the unrelated camera filters.
	for path: String in ["CameraPivot/CameraTilt/Camera3D/CanvasLayer", "CameraPivot/CameraTilt/Camera3D/CanvasLayer2"]:
		(main.get_node(path) as CanvasLayer).hide()
	table = main.get_node("ScenePivot/GameTable") as GameTable
	standard_material = table.dealer_satan.material_override
	custom_texture = CharacterAppearance.resources(LOOK)["texture"]
	_configure_timings()
	for host: bool in [true, false]:
		await _check_exit(host, true)
		await _check_exit(host, false)
	# The same hidden handoff must work if the connection vanished before Exit.
	await _check_exit(true, true, true)
	await _check_exit(false, false, true)
	await _start_match(true)
	check(table.dealer_satan.texture == custom_texture, "a subsequent real match setup restores the custom opponent")
	await get_tree().create_timer(0.15).timeout
	table._online_mode = false
	table._show_main_menu()
	table._sync_satan_voice_state()
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	NetworkManager.local_player_data.clear()
	NetworkManager.remote_player_data.clear()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	main = null
	table = null
	standard_material = null
	custom_texture = null
	print("MULTIPLAYER_CHARACTER_EXIT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _configure_timings() -> void:
	table.deck_size = 5
	table.draw_animation_duration = 0.01
	table.match_camera_duration = 0.01
	table.loss_player_view_return_duration = 0.04
	table.loss_camera_approach_duration = 0.06
	table.loss_camera_return_duration = 0.04
	table.pistol_raise_duration = 0.06
	table.pistol_aim_pause = 0.03
	table.win_gun_raise_duration = 0.06
	table.win_gun_lower_duration = 0.04
	table.win_gun_recoil_duration = 0.03
	table.win_satan_knockback_duration = 0.25
	table.win_satan_absent_duration = 0.12
	table.win_satan_return_duration = 0.35
	table.win_satan_return_hold = 0.02
	table.loss_reveal_duration = 0.15


func _start_match(host: bool) -> void:
	var card: Dictionary = CardDatabase.get_combat_cards()[0].duplicate(true)
	NetworkManager.current_lobby_id = 99
	NetworkManager.is_host = true
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.clear()
	NetworkManager._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	NetworkManager.local_player_data = {"name": "Local", "deck": [card]}
	NetworkManager.remote_player_data = {"name": "Opponent", "appearance": LOOK, "deck": [card]}
	table._online_mode = true
	table._online_is_host = true
	table._online_is_spectator = false
	table._reset_online_sync_tracking()
	# Start through production match setup, with no RPC recipients in this fixture.
	await table._start_online_match()
	table._online_is_host = host
	NetworkManager.is_host = host
	table._sync_satan_voice_state()
	check(table.dealer_satan.texture == custom_texture and not table._online_character_retired, "new match binds the selected opponent after a previous exit")


func _play_exit(win: bool, disconnected: bool) -> void:
	if disconnected:
		await table._on_exit_button_pressed()
	elif win:
		await table._play_win_exit_sequence(false)
	else:
		await table._play_loss_exit_sequence(false)
	finished = true


func _is_standard_satan() -> bool:
	return table.dealer_satan._player_resources.is_empty() and table.dealer_satan.material_override == standard_material and table.dealer_satan.hframes == table.SATAN_IDLE_FRAMES and table.dealer_satan.texture in [table._satan_idle_texture, table.SATAN_HOVER_TEXTURE]


func _check_exit(host: bool, win: bool, disconnected: bool = false) -> void:
	await _start_match(host)
	var label := ("host" if host else "guest") + (" win" if win else " loss") + (" disconnected" if disconnected else "")
	table._game_over = true
	table._table_state = GameTable.TableState.GAME_OVER
	table._last_match_outcome = GameTable.MatchOutcome.WIN if win else GameTable.MatchOutcome.LOSS
	var observed := {"shot": false, "swapped": false, "hidden_swap": false, "woke": false}
	var shot_callback := func() -> void:
		observed["shot"] = true
		check(table.dealer_satan.texture == custom_texture, label + ": shot still uses the opponent avatar")
	var swap_callback := func() -> void:
		if not observed["shot"] or table.dealer_satan.texture == custom_texture or observed["swapped"]:
			return
		observed["swapped"] = true
		observed["hidden_swap"] = not table.dealer_satan.visible if win else is_instance_valid(table._black_rect) and table._black_rect.visible and table._black_rect.modulate.a >= 0.999
		check(observed["hidden_swap"], label + ": skin changes only while hidden or fully black")
	var wake_callback := func() -> void:
		observed["woke"] = true
		check(_is_standard_satan(), label + ": normal Satan is installed before wakeup/reveal")
	table.loss_shot_fired.connect(shot_callback)
	table.dealer_satan.texture_changed.connect(swap_callback)
	table.player_wakeup_started.connect(wake_callback)
	finished = false
	_play_exit(win, disconnected)
	check(await _wait_until(func() -> bool: return observed["shot"]), label + ": reaches the actual shot")
	if win:
		await get_tree().process_frame
		check(table.dealer_satan.texture == custom_texture and table.satan_motion_root.scale.length() > 0.0, label + ": defeated avatar survives its knockback")
	check(await _wait_until(func() -> bool: return observed["swapped"]), label + ": reaches the standard-Satan handoff")
	check(_is_standard_satan(), label + ": restores original texture, animation frames and material")
	if win:
		check(table.satan_motion_root.position.y < table._satan_motion_base_transform.origin.y, label + ": normal Satan rises from below")
	else:
		check(is_instance_valid(table._black_rect) and table._black_rect.visible and table._black_rect.modulate.a >= 0.999, label + ": replacement happens behind the opaque blackout")
	# Exercise the ordinary per-frame sync with changed roster data while the
	# connection can still be alive; it must never rebind the departed avatar.
	NetworkManager.remote_player_data["name"] = "Late roster update"
	for frame in range(8):
		table._sync_satan_voice_state()
		await get_tree().process_frame
	check(_is_standard_satan() and not table.match_hud.visible, label + ": late roster updates cannot restore the old avatar or portrait")
	if host and not disconnected:
		await _capture("winner-return.png" if win else "loser-blackout.png")
	check(await _wait_until(func() -> bool: return finished), label + ": cinematic completes")
	if not win:
		check(observed["woke"], label + ": reaches wakeup with the new skin")
	for frame in range(3):
		await get_tree().process_frame
	check(_is_standard_satan(), label + ": hub retains Satan after cinematic completion")
	if not disconnected:
		check(table._online_mode and NetworkManager.has_active_session(), label + ": handoff finishes before session teardown")
	table.loss_shot_fired.disconnect(shot_callback)
	table.dealer_satan.texture_changed.disconnect(swap_callback)
	table.player_wakeup_started.disconnect(wake_callback)


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in range(3):
		await RenderingServer.frame_post_draw
	var directory := "res://docs/validation/character-customization"
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_tree().root.get_texture().get_image().save_png(directory.path_join(filename)) == OK, "saved " + filename)
