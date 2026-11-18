extends Node

var failures := 0
var checks := 0
const HOST_LOOK := {"face": "2", "hat": "angel", "mouth": "1", "eye_color": "22aaff"}
const GUEST_LOOK := {"face": "4", "hat": "jester", "mouth": "2", "eye_color": "ff3377"}


class WireNetwork:
	extends "res://scripts/autoload/NetworkManager.gd"

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _exit_tree() -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Run in an isolated project to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	# The isolated fixture may be reused after other suites have reached the
	# short playtime encounter timer. Keep that unrelated modal out of this UI.
	PlaytimeManager.complete_encounter()
	_check_catalogue_discovery()
	_check_compositing()
	_check_mouth_compositing()
	await _check_menu()
	await _check_microphone_avatar()
	await _check_network_roster()
	await _check_table()
	print("CHARACTER_CUSTOMIZATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_catalogue_discovery() -> void:
	var face_files := Array(ResourceLoader.list_directory(CharacterAppearance.FACE_DIRECTORY)).filter(func(filename: String) -> bool: return filename.get_extension() == "png")
	var hat_files := Array(ResourceLoader.list_directory(CharacterAppearance.HAT_DIRECTORY)).filter(func(filename: String) -> bool: return filename.get_extension() == "png")
	var mouth_files := Array(ResourceLoader.list_directory(CharacterAppearance.MOUTH_DIRECTORY)).filter(func(filename: String) -> bool: return filename.get_extension() == "png")
	check(CharacterAppearance.FACES.size() == face_files.size() and CharacterAppearance.HATS.size() == hat_files.size() and CharacterAppearance.MOUTHS.size() == mouth_files.size(), "all face, hat and mouth images are discovered without editing a count")
	var folder := "res://test-user/catalogue-probe"
	DirAccess.make_dir_recursive_absolute(folder)
	var texture := ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	for filename: String in ["10.res", "2.res", "1.res"]:
		check(ResourceSaver.save(texture, folder.path_join(filename)) == OK, "created dynamic catalogue fixture " + filename)
	var catalogue := CharacterAppearance.load_catalogue(folder)
	check(catalogue.keys() == ["1", "2", "10"], "catalogue sorts numbers naturally and uses stable filenames as IDs")
	ResourceSaver.save(texture, folder.path_join("11.res"))
	var expanded := CharacterAppearance.load_catalogue(folder)
	check(expanded.size() == catalogue.size() + 1 and expanded.has("11"), "another folder image appears on the next scan without an explicit count")
	for filename: String in ["1.res", "2.res", "10.res", "11.res"]:
		DirAccess.remove_absolute(folder.path_join(filename))
	var saved_faces: Dictionary = CharacterAppearance.FACES
	var saved_hats: Dictionary = CharacterAppearance.HATS
	var saved_mouths: Dictionary = CharacterAppearance.MOUTHS
	CharacterAppearance.FACES = {}
	CharacterAppearance.HATS = {}
	CharacterAppearance.MOUTHS = {}
	check(CharacterAppearance.compose_image({}).get_size() == Vector2i(64, 64), "empty folders do not crash the editor or a peer")
	CharacterAppearance.FACES = saved_faces
	CharacterAppearance.HATS = saved_hats
	CharacterAppearance.MOUTHS = saved_mouths


func _check_compositing() -> void:
	check(CharacterAppearance.sanitize(null) == CharacterAppearance.DEFAULT, "missing appearance has a compatible default")
	check(CharacterAppearance.sanitize({"hat": ""})["hat"] == "", "explicit no-hat selection survives save and network sanitization")
	var bare := CharacterAppearance.compose_image({"hat": ""})
	var face_only: Image = CharacterAppearance.FACES[CharacterAppearance.DEFAULT["face"]].get_image()
	check(bare.get_data() == face_only.get_data(), "no hat renders only the face without an overlay")
	check(CharacterAppearance.sanitize({"face": "../satan", "hat": 1, "eye_color": "ffffff00", "file": "res://x"}) == CharacterAppearance.DEFAULT, "invalid IDs, alpha, types and paths cannot enter an appearance")
	check(CharacterAppearance.sanitize({"eye_color": "Aa22FF"})["eye_color"] == "aa22ff", "RGB hex is normalized")
	check(CharacterAppearance.sanitize({"eye_color": "gggggg"})["eye_color"] == "ffffff", "invalid hex has a safe default")
	check(CharacterAppearance.DEFAULT["mouth"] == "", "new players start without a mouth")
	var legacy := HOST_LOOK.duplicate()
	legacy.erase("mouth")
	check(CharacterAppearance.sanitize(legacy)["mouth"] == "", "old saves and network payloads without a mouth keep no mouth")
	for invalid_mouth: Variant in ["../mouth", "missing-mouth", 12, {}, null, ""]:
		check(CharacterAppearance.sanitize({"mouth": invalid_mouth})["mouth"] == "", "missing, removed or malformed mouth IDs fall back to no mouth")
	for face_id: String in CharacterAppearance.FACES:
		var source: Image = CharacterAppearance.FACES[face_id].get_image()
		for hat_id: String in CharacterAppearance.HATS:
			var hat: Image = CharacterAppearance.HATS[hat_id].get_image()
			var composite := CharacterAppearance.compose_image({"face": face_id, "hat": hat_id, "eye_color": "22aaff"})
			check(composite.get_size() == Vector2i(64, 64), "64x64 canvas retained for " + face_id + "/" + hat_id)
			var aligned := true
			var eye_count := 0
			for y in range(64):
				for x in range(64):
					var expected := source.get_pixel(x, y)
					if expected.a > 0.0 and expected.r > 0.9:
						expected = Color.html("22aaff")
						if hat.get_pixel(x, y).a == 0.0:
							eye_count += 1
					if hat.get_pixel(x, y).a > 0.0:
						expected = hat.get_pixel(x, y)
					var actual := composite.get_pixel(x, y)
					if not (actual.a == 0.0 and expected.a == 0.0) and not actual.is_equal_approx(expected):
						aligned = false
			check(aligned and eye_count > 0, "every pixel aligns; only eyes recolor for " + face_id + "/" + hat_id)
		var unchanged := true
		var reread: Image = CharacterAppearance.FACES[face_id].get_image()
		for y in range(64):
			for x in range(64):
				var pixel := reread.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.r > 0.0 and pixel != Color.WHITE:
					unchanged = false
		check(unchanged, "source face remains white: " + face_id)
	for index in range(24):
		CharacterAppearance.resources({"eye_color": "%06x" % index})
	check(CharacterAppearance._cache.size() <= CharacterAppearance.CACHE_LIMIT, "color-picker texture cache is bounded")
	var composite := CharacterAppearance.compose_image(GUEST_LOOK)
	var emission: Image = CharacterAppearance.resources(GUEST_LOOK)["emission"].get_image()
	var black_stays_black := true
	for y in range(64):
		for x in range(64):
			var source := composite.get_pixel(x, y)
			if source.a == 0.0 or source == Color.BLACK:
				var glow := emission.get_pixel(x, y)
				black_stays_black = black_stays_black and glow.r == 0.0 and glow.g == 0.0 and glow.b == 0.0
	check(black_stays_black, "emission mask has black RGB for bodies and transparent pixels, independent of alpha")


func _check_mouth_compositing() -> void:
	var original_mouth_bytes := {}
	for mouth_id: String in CharacterAppearance.MOUTHS:
		var source: Image = CharacterAppearance.MOUTHS[mouth_id].get_image()
		original_mouth_bytes[mouth_id] = source.get_data()
	for face_id: String in CharacterAppearance.FACES:
		var face: Image = CharacterAppearance.FACES[face_id].get_image()
		for hat_id: String in CharacterAppearance.HATS:
			var hat: Image = CharacterAppearance.HATS[hat_id].get_image()
			for mouth_id: String in CharacterAppearance.MOUTHS:
				var mouth: Image = CharacterAppearance.MOUTHS[mouth_id].get_image()
				for color_hex: String in ["22aaff", "ff3377"]:
					var color := Color.html(color_hex)
					var composed := CharacterAppearance.compose_image({"face": face_id, "hat": hat_id, "mouth": mouth_id, "eye_color": color_hex})
					var aligned := true
					for y in range(64):
						for x in range(64):
							var expected := face.get_pixel(x, y)
							if expected.a > 0.0 and expected.r > 0.9:
								expected = color
							var mouth_pixel := mouth.get_pixel(x, y)
							if mouth_pixel.a > 0.0:
								expected = color if mouth_pixel.r > 0.9 else mouth_pixel
							if hat.get_pixel(x, y).a > 0.0:
								expected = hat.get_pixel(x, y)
							var actual := composed.get_pixel(x, y)
							if not (actual.a == 0.0 and expected.a == 0.0) and not actual.is_equal_approx(expected):
								aligned = false
					check(aligned, "mouth and eyes share RGB without moving pixels: %s/%s/%s/%s" % [face_id, hat_id, mouth_id, color_hex])
	for mouth_id: String in CharacterAppearance.MOUTHS:
		var source: Image = CharacterAppearance.MOUTHS[mouth_id].get_image()
		check(source.get_data() == original_mouth_bytes[mouth_id], "source mouth remains unchanged: " + mouth_id)
	var no_mouth := HOST_LOOK.duplicate()
	no_mouth["mouth"] = ""
	check(CharacterAppearance.resources(no_mouth)["texture"] != CharacterAppearance.resources(HOST_LOOK)["texture"], "mouth selection has its own texture cache entry")
	var legacy := no_mouth.duplicate()
	legacy.erase("mouth")
	check(CharacterAppearance.compose_image(legacy).get_data() == CharacterAppearance.compose_image(no_mouth).get_data(), "no mouth exactly preserves the legacy composite")


func _check_menu() -> void:
	SettingsManager.set_character_appearance(CharacterAppearance.DEFAULT)
	var root := get_tree().root
	root.size = Vector2i(1280, 720)
	var menu := (load("res://scenes/main/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await get_tree().process_frame
	menu.character_button.pressed.emit()
	var customizer: CharacterCustomizer = menu.character_customizer
	check(customizer.visible, "main-menu button opens the character editor")
	check(customizer._draft["mouth"] == "" and customizer.mouth_label.text == Localization.text("No Mouth"), "mouth selector starts at No Mouth")
	await _capture("customizer-no-mouth.png")
	check(customizer.hat_next.position.y < customizer.face_next.position.y, "hat arrows are above the face arrows")
	var original := SettingsManager.get_character_appearance()
	for index in range(CharacterAppearance.MOUTHS.size() + 1):
		customizer.mouth_next.pressed.emit()
	check(customizer._draft == original, "mouth selector wraps through all folder mouths and No Mouth independently")
	customizer.mouth_previous.pressed.emit()
	check(customizer._draft["mouth"] == CharacterAppearance.MOUTHS.keys().back(), "previous mouth wraps from No Mouth to the last mouth")
	customizer.mouth_next.pressed.emit()
	check(customizer._draft["mouth"] == "", "next mouth returns to No Mouth")
	for index in range(CharacterAppearance.HATS.size() + 1):
		customizer.hat_next.pressed.emit()
	check(customizer._draft == original, "hat selector wraps the full folder independently")
	customizer.hat_previous.pressed.emit()
	customizer.hat_next.pressed.emit()
	check(customizer._draft == original, "hat arrows work in both directions")
	for index in range(CharacterAppearance.FACES.size()):
		customizer.face_previous.pressed.emit()
	check(customizer._draft == original, "face selector wraps the full folder independently")
	customizer.face_next.pressed.emit()
	customizer.eye_picker.color_changed.emit(Color.html("22aaff"))
	check(customizer._draft["eye_color"] == "22aaff", "color picker updates the live preview")
	customizer.cancel_button.pressed.emit()
	check(not customizer.visible and SettingsManager.get_character_appearance() == original, "Back discards the draft")
	customizer.open()
	customizer._draft = HOST_LOOK.duplicate()
	customizer._refresh()
	await _capture("customizer-1280x720.png")
	customizer.apply_button.pressed.emit()
	check(SettingsManager.get_character_appearance() == HOST_LOOK, "Apply persists the chosen appearance")
	SettingsManager._character_appearance = CharacterAppearance.DEFAULT.duplicate()
	SettingsManager.load_settings()
	check(SettingsManager.get_character_appearance() == HOST_LOOK, "appearance survives settings reload")
	var config := ConfigFile.new()
	config.load(SettingsManager.CONFIG_PATH)
	var legacy := HOST_LOOK.duplicate()
	legacy.erase("mouth")
	config.set_value(SettingsManager.SECTION, "character_appearance", legacy)
	config.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	var migrated := HOST_LOOK.duplicate()
	migrated["mouth"] = ""
	check(SettingsManager.get_character_appearance() == migrated, "legacy settings migrate to no mouth without changing face, hat or eye color")
	SettingsManager.set_character_appearance(HOST_LOOK)
	SaveSlots.select_slot(2)
	check(SettingsManager.get_character_appearance() == HOST_LOOK, "changing save slots keeps the player's appearance")
	customizer.open()
	for resolution: Vector2i in [Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		check(root.get_visible_rect().encloses(customizer._panel.get_global_rect()), "editor panel fits " + str(resolution))
		check(customizer._panel.get_global_rect().encloses(customizer.apply_button.get_global_rect()), "Apply stays visible at " + str(resolution))
		await _capture("customizer-%dx%d.png" % [resolution.x, resolution.y])
	customizer.close()
	root.size = Vector2i(1280, 720)
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check_microphone_avatar() -> void:
	SettingsManager.set_character_appearance(HOST_LOOK)
	NetworkManager.remote_player_data = {"name": "Other player", "appearance": GUEST_LOOK}
	var menu := (load("res://scenes/ui/SettingsMenu.tscn") as PackedScene).instantiate() as SettingsMenu
	add_child(menu)
	menu.open()
	# Supply deterministic voice levels without opening a real microphone.
	menu.set_process(false)
	menu._microphone_test.set_process(false)
	var portrait := menu.mic_test_satan_portrait
	portrait.set_process(false)
	var own_texture: Texture2D = CharacterAppearance.resources(HOST_LOOK)["texture"]
	check(portrait.portrait.texture == own_texture and portrait.has_character_appearance(), "microphone test shows the saved local avatar, including its mouth and color")
	check(portrait.portrait.texture != CharacterAppearance.resources(GUEST_LOOK)["texture"], "microphone test never substitutes the remote player's avatar")
	for state: int in [MicrophoneTestController.TestState.LISTENING, MicrophoneTestController.TestState.MONITORING]:
		menu._microphone_test.test_state = state
		for activity: int in [MicrophoneTestController.InputVoiceActivity.SILENT, MicrophoneTestController.InputVoiceActivity.SPEAKING, MicrophoneTestController.InputVoiceActivity.LOUD]:
			menu._microphone_test.input_voice_activity = activity
			menu._microphone_test.input_voice_level = 0.85 if activity != MicrophoneTestController.InputVoiceActivity.SILENT else 0.0
			menu._refresh_microphone_test_ui()
			for frame in range(12):
				portrait._process(1.0 / 60.0)
			check(portrait.portrait.texture == own_texture and not portrait.portrait.texture is AtlasTexture, "microphone avatar stays on its single composite for state %d, activity %d" % [state, activity])
			if activity != MicrophoneTestController.InputVoiceActivity.SILENT:
				check(portrait.satan_shake_root.position.length() > 0.0, "microphone avatar still shakes with voice level in state %d, activity %d" % [state, activity])
	SettingsManager.set_character_appearance(GUEST_LOOK)
	check(portrait.portrait.texture == CharacterAppearance.resources(GUEST_LOOK)["texture"], "saving a new local avatar refreshes an existing microphone preview")
	SettingsManager.set_character_appearance(HOST_LOOK)
	menu._microphone_test.test_state = MicrophoneTestController.TestState.IDLE
	menu._refresh_microphone_test_ui()
	check(portrait.portrait.texture == own_texture and portrait.satan_shake_root.position == Vector2.ZERO and portrait.satan_shake_root.rotation == 0.0, "stopping the microphone preserves the local avatar and stops its shake")
	var scroll := menu.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.ensure_control_visible(menu.get_node("%MicTestSatanPortrait"))
	await get_tree().process_frame
	check(scroll.get_global_rect().encloses(portrait.get_global_rect()), "microphone avatar is visible in the scrolled settings panel")
	await _capture("microphone-own-avatar.png")
	menu.close()
	menu.queue_free()
	NetworkManager.remote_player_data.clear()
	await get_tree().process_frame


func _check_network_roster() -> void:
	var branches: Array[Node] = []
	var networks: Array[Node] = []
	var apis: Array[SceneMultiplayer] = []
	var peers: Array[ENetMultiplayerPeer] = []
	var port := 38000 + int(Time.get_ticks_msec() % 10000)
	for index in range(3):
		var branch := Node.new()
		branch.name = "AppearancePeer%d" % index
		add_child(branch)
		branches.append(branch)
		var api := SceneMultiplayer.new()
		get_tree().set_multiplayer(api, branch.get_path())
		apis.append(api)
		var network := WireNetwork.new()
		network.name = "Network"
		branch.add_child(network)
		network.current_lobby_id = 99
		networks.append(network)
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_server(port, 2) if index == 0 else peer.create_client("127.0.0.1", port)
		check(error == OK, "local appearance transport starts for peer %d" % index)
		api.multiplayer_peer = peer
		peers.append(peer)
	var deadline := Time.get_ticks_msec() + 4000
	while apis[0].get_peers().size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(apis[0].get_peers().size() == 2, "host, guest and spectator connect over separate local peers")
	if apis[0].get_peers().size() == 2:
		var host = networks[0]
		host.is_host = true
		var guest_id := apis[1].get_unique_id()
		var viewer_id := apis[2].get_unique_id()
		host._connected_peer_ids.assign([guest_id, viewer_id])
		var card: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
		host._participants = {1: {"role": "player", "name": "Host", "appearance": HOST_LOOK, "deck": [card]}}
		var payload := {"version": host.PROTOCOL_VERSION, "name": "Guest", "appearance": GUEST_LOOK, "deck": [card]}
		var accepted: Dictionary = host._sanitize_remote_player_data(payload, 0)
		check(accepted.get("appearance") == GUEST_LOOK, "production handshake sanitizer retains the guest's appearance")
		check(host._register_participant(guest_id, accepted, "player").is_empty(), "production admission retains the guest look")
		check(host.remote_player_data.get("appearance") == GUEST_LOOK, "host receives the guest's full look")
		check(host._register_participant(viewer_id, {"name": "Viewer"}, "spectator").is_empty(), "spectator admission remains independent")
		var roster: Dictionary = host._build_public_roster()
		check(not roster[1].has("deck") and not roster[guest_id].has("deck"), "appearance sharing never reveals hidden decks")
		host._publish_participants()
		deadline = Time.get_ticks_msec() + 4000
		while networks[2].get_participant_peer_ids().size() < 3 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(networks[1].remote_player_data.get("appearance") == HOST_LOOK, "guest receives host appearance via production roster RPC")
		check(networks[2].get_player_data_for_peer(guest_id).get("appearance") == GUEST_LOOK, "spectator receives guest appearance via production roster RPC")
		check(networks[2].get_player_data_for_peer(1).get("appearance") == HOST_LOOK, "spectator receives host appearance via production roster RPC")
		var sanitized: Dictionary = host._sanitize_remote_player_data({"version": host.PROTOCOL_VERSION, "appearance": ["bad"]}, 0)
		check(sanitized["appearance"] == CharacterAppearance.DEFAULT, "malformed network appearance safely falls back")
	for index in range(3):
		peers[index].close()
		apis[index].multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().set_multiplayer(null, branches[index].get_path())
		branches[index].queue_free()
	await get_tree().process_frame


func _check_table() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	# Captures review the character and UI without the two full-screen filters.
	# Their normal behavior is covered separately by the startup/settings suite.
	if DisplayServer.get_name() != "headless":
		for overlay: String in ["CameraPivot/CameraTilt/Camera3D/CanvasLayer", "CameraPivot/CameraTilt/Camera3D/CanvasLayer2"]:
			(main.get_node(overlay) as CanvasLayer).hide()
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	var original_material: Material = table.dealer_satan.material_override
	var original_texture: Texture2D = table._satan_idle_texture
	NetworkManager.current_lobby_id = 99
	NetworkManager.remote_player_data = {"name": "Guest", "appearance": GUEST_LOOK}
	table._online_mode = true
	table._table_state = GameTable.TableState.PLAYING
	table._sync_satan_voice_state()
	var custom_texture: Texture2D = CharacterAppearance.resources(GUEST_LOOK)["texture"]
	check(table.dealer_satan.texture == custom_texture and table.dealer_satan.hframes == 1, "opponent at the table displays the selected composite without cropping")
	check(table.match_hud.portrait.texture == custom_texture, "voice portrait displays the same composite")
	check(table.match_hud.visible, "character is visible with voice chat disabled")
	for state: String in ["hover", "laugh", "death", "reset"]:
		match state:
			"hover": table._set_satan_hovered(true)
			"laugh": table._set_satan_laughing(true)
			"death": table._set_satan_dying(true)
			"reset": table._reset_win_cinematic_visuals()
		check(table.dealer_satan.texture == custom_texture and table.dealer_satan.hframes == 1, "custom character survives " + state)
	var material := table.dealer_satan.material_override as StandardMaterial3D
	check(material != original_material and material.emission_texture != null, "custom glow material is isolated from the original NPC")
	table.match_hud.set_voice_chat_enabled(true)
	for activity in [MatchHUD.VoiceActivity.SILENT, MatchHUD.VoiceActivity.SPEAKING, MatchHUD.VoiceActivity.LOUD]:
		table.match_hud.set_remote_voice_activity(activity)
		check(table.match_hud.portrait.texture == custom_texture, "all voice states retain the custom character")
	table._table_state = GameTable.TableState.GAME_OVER
	table._sync_satan_voice_state()
	check(table.match_hud.visible, "character remains visible on the multiplayer result")
	NetworkManager.remote_player_data = {}
	table._sync_online_character()
	check(table.dealer_satan.texture == custom_texture, "disconnect during results retains the accepted look")
	NetworkManager._participants = {1: {"role": "player", "name": "Host", "appearance": HOST_LOOK}, 2: {"role": "player", "name": "Guest", "appearance": GUEST_LOOK}}
	table._online_is_spectator = true
	table._sync_online_character()
	check(table.match_hud._second_fighter_panel.visible, "spectators see both fighters' custom portraits")
	table._online_is_spectator = false
	NetworkManager.remote_player_data = {"name": "Guest", "appearance": GUEST_LOOK}
	table._sync_online_character()
	main.get_node("ScenePivot/GameTable/OnlineCanvas/MatchmakingScreen").open()
	await _capture("lobby-characters.png")
	main.get_node("ScenePivot/GameTable/OnlineCanvas/MatchmakingScreen").close_without_leaving()
	table._table_state = GameTable.TableState.PLAYING
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.9).timeout
	await _capture("multiplayer-character.png")
	table._online_mode = false
	table._sync_online_character()
	check(table.dealer_satan.texture == original_texture and table.dealer_satan.material_override == original_material, "leaving multiplayer restores the original NPC and material")
	NetworkManager.current_lobby_id = 0
	NetworkManager._participants.clear()
	NetworkManager.remote_player_data.clear()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for index in range(4):
		await RenderingServer.frame_post_draw
	var directory := "res://docs/validation/character-customization"
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_tree().root.get_texture().get_image().save_png(directory.path_join(filename)) == OK, "saved " + filename)
