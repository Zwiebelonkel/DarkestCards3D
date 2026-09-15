extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
var failures := 0
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _card_data(identity: String, effects: Array = []) -> Dictionary:
	var data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	data["instance_id"] = identity
	data["attack"] = 2
	data["defense"] = 20
	data["animated"] = false
	data["effects"] = effects
	data["active_effects"] = effects
	return data


func _new_card(data: Dictionary) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	add_child(card)
	card.setup(data)
	return card


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _check_card_lifecycle()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await get_tree().process_frame
	main.visible = false
	main.set_process(false)
	main.set_physics_process(false)
	for canvas in main.find_children("*", "CanvasLayer", true, false):
		canvas.visible = false
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	# Surface stains and their network presentation must work without particles.
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	await _check_damage_routes(table)
	await _check_remote_routes(table)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_visuals()
	print("CARD_BLOOD_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_card_lifecycle() -> void:
	var first := _new_card(_card_data("blood-first"))
	var second := _new_card(_card_data("blood-second"))
	first.set_process(false)
	second.set_process(false)
	first.blood_fade_duration = 1.0
	second.blood_fade_duration = 1.0
	check(first.get_blood_intensity() == 0.0 and second.get_blood_intensity() == 0.0, "freshly spawned cards start clean")
	first.show_blood_hit(0.7)
	check(first.get_blood_intensity() > 0.0 and second.get_blood_intensity() == 0.0, "a hit stains only its own card")
	second.show_blood_hit(0.4)
	check(first._blood_materials.size() == 2 and second._blood_materials.size() == 2, "both card body and artwork receive bloodMix overlays")
	if first._blood_materials.size() == 2 and second._blood_materials.size() == 2:
		check(first._blood_materials[0] != second._blood_materials[0] and first._blood_materials[1] != second._blood_materials[1], "cards do not share mutable blood shader materials")
	var initial := first.get_blood_intensity()
	first._process(0.25)
	var partial := first.get_blood_intensity()
	check(partial > 0.0 and partial < initial, "blood fades on static card artwork")
	var state := first.get_network_state()
	state["current_hp"] = 13
	first.apply_network_state(state)
	check(is_equal_approx(first.get_blood_intensity(), partial), "same-card snapshot preserves the current stain")
	first._process(0.75)
	check(first.get_blood_intensity() == 0.0, "snapshot does not restart the blood fade deadline")
	check(first.card_image.material_overlay == null, "fully faded artwork removes its overlay")
	first.show_blood_hit(0.5)
	first._process(0.8)
	var before_repeat := first.get_blood_intensity()
	first.show_blood_hit(0.5)
	check(first.get_blood_intensity() > before_repeat, "a subsequent hit refreshes the visible blood")
	first._process(0.3)
	check(first.get_blood_intensity() > 0.0, "refreshed blood remains after the original hit would expire")
	first._process(1.0)
	check(first.get_blood_intensity() == 0.0, "refreshed blood eventually disappears completely")
	first.show_blood_hit()
	first.setup(_card_data("different-owned-copy"))
	check(first.get_blood_intensity() == 0.0, "another owned copy of the same card starts clean when a node is reused")
	var decoration := CARD_SCENE.instantiate() as Card3D
	decoration.is_stack_decoration = true
	add_child(decoration)
	decoration.setup(_card_data("decoration"))
	decoration.show_blood_hit()
	check(decoration.get_blood_intensity() == 0.0, "deck stack decorations cannot be stained")
	first.show_blood_hit(0.0)
	check(first.get_blood_intensity() == 0.0, "zero-strength effect does not create a stain")
	first.queue_free()
	second.queue_free()
	decoration.queue_free()
	await get_tree().process_frame


func _duel_pair(table: GameTable, attacker_effects: Array = [], defender_effects: Array = []) -> Array[Card3D]:
	table._clear_match()
	table._online_mode = false
	table._table_state = GameTable.TableState.PLAYING
	table._enemy_deck.append(_card_data("duel-attacker", attacker_effects))
	table._player_deck.append(_card_data("duel-defender", defender_effects))
	table._draw_to_slot("enemy", 0, false)
	table._draw_to_slot("player", 0, false)
	return [table._enemy_slots[0], table._player_slots[0]]


func _check_damage_routes(table: GameTable) -> void:
	var pair := _duel_pair(table)
	var original_materials := [pair[0].card_image.get_active_material(0), pair[1].card_image.get_active_material(0)]
	await table._resolve_duel(pair[0], pair[1], "enemy")
	check(pair[0].get_blood_intensity() > 0.0 and pair[1].get_blood_intensity() > 0.0, "real attack and counter stain both cards even without particle scenes")
	check(pair[0].current_hp > 0 and pair[1].current_hp > 0 and is_zero_approx(pair[0].get_death_dissolve_progress()) and is_zero_approx(pair[1].get_death_dissolve_progress()) and pair[0].card_image.get_active_material(0) == original_materials[0] and pair[1].card_image.get_active_material(0) == original_materials[1], "surviving a real attack and counter keeps both original card materials without starting a death dissolve")
	pair = _duel_pair(table, [{"type": "shield_first_hit"}], [{"type": "shield_first_hit"}])
	await table._resolve_duel(pair[0], pair[1], "enemy")
	check(pair[0].get_blood_intensity() == 0.0 and pair[1].get_blood_intensity() == 0.0, "shield-blocked hits leave both cards clean")
	pair = _duel_pair(table, [{"type": "last_stand"}])
	pair[0].current_hp = 1
	await table._resolve_duel(pair[0], pair[1], "enemy")
	check(pair[0].current_hp == 1 and pair[0].get_blood_intensity() > 0.0, "last-stand counter hit stains the attacker despite unchanged final HP")
	check(is_zero_approx(pair[0].get_death_dissolve_progress()) and pair[0].card_image.get_active_material(0) is BaseMaterial3D, "last stand prevents a lethal-looking counter from dissolving the surviving card")
	pair = _duel_pair(table, [{"type": "last_stand"}], [{"type": "thorns", "percent": 0.5}])
	pair[0].current_hp = 1
	pair[1].attack_value = 0
	await table._resolve_duel(pair[0], pair[1], "enemy")
	check(pair[0].current_hp == 1 and pair[0].get_blood_intensity() > 0.0, "last-stand thorns hit stains the attacker before HP restoration")
	pair = _duel_pair(table)
	pair[0].set_meta("poison_damage", 2)
	pair[0].set_meta("poison_turns", 1)
	await table._apply_start_turn_effects("enemy")
	check(pair[0].get_blood_intensity() > 0.0 and pair[1].get_blood_intensity() == 0.0, "poison stains only the damaged card")
	table._clear_match()
	await get_tree().process_frame


func _check_remote_routes(table: GameTable) -> void:
	var pair := _duel_pair(table)
	for card in pair:
		card.set_process(false)
		card.blood_fade_duration = 1.0
	# Exercise the same presentation function fed by the authoritative impact RPC.
	var impact := {
		"attacker_side": "enemy", "attacker_slot": 0,
		"defender_side": "player", "defender_slot": 0,
		"attacker_state": pair[0].get_network_state(),
		"defender_state": pair[1].get_network_state(),
		"defender_damage": 2, "attacker_damage": 0, "damage_intensity": 0.6,
	}
	table._online_client_attack_phases[1] = 1
	table._online_client_attack_contexts[1] = {
		"attacker": pair[0], "defender": pair[1],
		"canonical_attacker_side": "enemy", "attacker_slot": 0,
		"canonical_defender_side": "player", "defender_slot": 0,
	}
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	check(pair[1].get_blood_intensity() > 0.0 and pair[0].get_blood_intensity() == 0.0, "authoritative impact presentation stains only the remotely damaged card")
	pair[1]._process(0.25)
	var before_duplicate := pair[1].get_blood_intensity()
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	check(is_equal_approx(pair[1].get_blood_intensity(), before_duplicate), "duplicate impact cannot refresh a fading stain")
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = true
	table._online_turn_sequence = 3
	# Generic RPCs now require an active session, even in the transport-free
	# fixture. Keep connected peers empty so spectator effects send no ACK.
	NetworkManager.current_lobby_id = 123
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {1: {"role": "player"}}
	table._rpc_play_online_blood(3, 1, 0, "enemy", 0, "burst", 0.5, false, "", -1)
	check(pair[0].get_blood_intensity() > 0.0, "spectator receives generic poison and cleave surface blood")
	pair[0]._process(0.25)
	before_duplicate = pair[0].get_blood_intensity()
	table._rpc_play_online_blood(3, 1, 0, "enemy", 0, "burst", 0.5, false, "", -1)
	check(is_equal_approx(pair[0].get_blood_intensity(), before_duplicate), "duplicate generic blood packet cannot refresh a fading stain")
	table._online_mode = false
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	table._clear_match()
	await get_tree().process_frame


func _capture_visuals() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.06, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	get_world_3d().environment = environment
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-25, -20, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 0, 3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.7
	camera.make_current()
	var left := _new_card(_card_data("visual-blood"))
	var right := _new_card(_card_data("visual-control"))
	left.position.x = -0.55
	right.position.x = 0.55
	left.blood_fade_duration = 1.8
	await get_tree().process_frame
	await _screenshot("blood-clean")
	left.show_blood_hit()
	await get_tree().create_timer(0.06).timeout
	await _screenshot("blood-hit")
	await get_tree().create_timer(0.85).timeout
	check(left.get_blood_intensity() > 0.0 and left.get_blood_intensity() < 0.75, "real process frames progressively fade the rendered stain")
	await _screenshot("blood-fading")
	await get_tree().create_timer(1.0).timeout
	check(left.get_blood_intensity() == 0.0 and right.get_blood_intensity() == 0.0, "rendered stain expires while the unhit neighbor stays clean")
	await _screenshot("blood-faded")
	left.queue_free()
	right.queue_free()


func _screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://" + filename + ".png")
