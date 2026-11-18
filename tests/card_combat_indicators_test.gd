extends Node3D

const CARD := preload("res://scenes/table/Card3D.tscn")
var checks := 0
var failures := 0
var cards: Array[Card3D] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner.")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	Localization.set_locale("en")
	_setup_view()
	var shield := _card("SHIELD", [{"type": "shield_first_hit"}, {"type": "regeneration"}], -1.05)
	var rebirth := _card("REBIRTH", [{"type": "grave_return"}, {"type": "armor"}], 0.0)
	var last_stand := _card("LAST STAND", [{"type": "last_stand"}, {"type": "armor"}], 1.05)
	var original_data := shield.card_data.duplicate(true)
	var base_scale := shield.effect_icon_1.scale
	var passive_material := shield.effect_icon_2.material_override
	CombatResolver.apply_incoming_damage(shield, 0)
	check(shield.get_available_effects().size() == 2 and shield.effect_icon_1.visible, "zero damage keeps the shield seal available")
	await _capture("battle-indicators-before")
	var overview := (load("res://scenes/CardEffectOverview.tscn") as PackedScene).instantiate() as CardEffectOverviewUI
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(overview)
	overview.show_for_card(shield)
	CombatResolver.apply_incoming_damage(shield, 10)
	CombatResolver.apply_damage_with_survival(rebirth, 1000)
	CombatResolver.apply_damage_with_survival(last_stand, 1000)
	rebirth.apply_poison(3, 3)
	rebirth.stun_next_attack()
	rebirth.apply_curse(2)
	check(shield.current_hp == shield.max_hp and shield.get_available_effects().size() == 1, "real shield absorption immediately consumes only its own effect")
	check(overview._count_label.text == Localization.format_text("%d effect", [1]).to_upper() and overview._effect_names[0].text == EffectPresentation.get_title({"type": "regeneration"}), "an already-open hover overview immediately removes the spent shield")
	overview.hide()
	check(last_stand.current_hp == 1 and rebirth.current_hp == rebirth.max_hp / 2, "the two lethal hits trigger the actual one-use survival paths")
	for card: Card3D in [shield, rebirth, last_stand]:
		var animation := card._combat_indicators._seal_tweens[0] as Tween
		animation.pause()
		animation.custom_step(0.16)
		check(card.effect_icon_1.visible and card.effect_icon_1.scale.x < base_scale.x, "consumed seal visibly shrinks before removal: " + str(card.card_data.name))
		var opacity := float((card.effect_icon_1.material_override as ShaderMaterial).get_shader_parameter("effect_opacity"))
		check(opacity > 0.0 and opacity < 1.0, "consumed seal fades during its shrink: " + str(card.card_data.name))
	var snapshot := shield.get_network_state()
	var old_animation := shield._combat_indicators._seal_tweens[0] as Tween
	var old_scale := shield.effect_icon_1.scale
	shield.apply_network_state(snapshot)
	shield.apply_network_state(snapshot)
	check(shield._combat_indicators._seal_tweens[0] == old_animation and shield.effect_icon_1.scale == old_scale, "duplicate online snapshots preserve the ongoing consumption animation")
	check(shield.effect_icon_2.material_override == passive_material and shield.effect_icon_2.scale == base_scale, "network refresh leaves the unused passive seal untouched")
	check(shield.card_data == original_data, "using a one-shot effect does not remove it from the owned card data")
	for type: String in ["poison", "stun", "curse"]:
		var badge := _badge(rebirth, type)
		var icon := badge.get_node("Icon") as MeshInstance3D
		check(badge.visible and badge.position.x > -0.1 and badge.position.y > 0.3, "active status sits in the card's upper-right row: " + type)
		check((icon.material_override as ShaderMaterial).get_shader_parameter("accent_color") == rebirth._combat_indicators.STATUS_COLORS[type], "status uses its distinct color: " + type)
	check((_badge(rebirth, "poison").get_node("Count") as Label3D).text == "3", "poison badge displays its remaining three turns")
	check((_badge(rebirth, "curse").get_node("Count") as Label3D).text == "-2", "curse badge displays the actual attack reduction")
	await _capture("battle-indicators-consuming")
	for card: Card3D in [shield, rebirth, last_stand]:
		(card._combat_indicators._seal_tweens[0] as Tween).play()
	await get_tree().create_timer(0.4).timeout
	for card: Card3D in [shield, rebirth, last_stand]:
		check(not card.effect_icon_1.visible and not card.effect_icon_area_1.visible and card.effect_icon_2.visible, "spent seal and its area disappear while the passive remains: " + str(card.card_data.name))
	await _capture("battle-indicators-after")
	await _check_status_lifecycle(rebirth)
	var both := _card("BOTH SAVES", [{"type": "last_stand"}, {"type": "grave_return"}], 100.0)
	overview.show_for_card(both)
	CombatResolver.apply_damage_with_survival(both, 1000)
	check(both.get_available_effects().size() == 1 and both.effect_icon_2.visible, "using the first of two one-shot saves preserves the second seal")
	CombatResolver.apply_damage_with_survival(both, 1000)
	check(both.get_available_effects().is_empty(), "the next lethal hit independently consumes the second survival seal")
	await get_tree().create_timer(0.4).timeout
	check(not both.effect_icon_1.visible and not both.effect_icon_2.visible and not overview.visible, "both spent seals and their open hover overview disappear completely")
	await _check_poison_integration()
	shield.setup(original_data)
	check(shield.effect_icon_1.visible and shield.effect_icon_1.scale == base_scale and shield.get_available_effects().size() == 2, "a fresh battle restores the intact seal at full size")
	shield.consume_first_hit_shield()
	shield.begin_death_dissolve()
	check(not shield.effect_icon_1.visible and shield.effect_icon_2.visible and not shield._combat_indicators.visible, "death during seal consumption cancels indicators without resurrecting the seal")
	for card in cards:
		card.queue_free()
	layer.queue_free()
	await get_tree().process_frame
	print("CARD_COMBAT_INDICATORS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_status_lifecycle(source: Card3D) -> void:
	var snapshot := source.get_network_state()
	var replica := _card("REPLICA", [], 100.0)
	replica.apply_network_state(snapshot)
	check(not replica.effect_icon_1.visible and replica.effect_icon_2.visible, "new online replicas immediately hide already-consumed seals without replay")
	check(replica._combat_indicators._seal_tweens.is_empty(), "joining with a consumed seal starts no consumption animation")
	for type: String in ["poison", "stun", "curse"]:
		check(_badge(replica, type).visible and _badge(replica, type).scale == Vector3.ONE, "new online replica restores active status without an entrance replay: " + type)
	var before_hit := snapshot.duplicate(true)
	before_hit["grave_return_available"] = true
	replica.apply_network_state(before_hit)
	replica.apply_network_state(snapshot)
	check(replica.effect_icon_1.visible and replica._combat_indicators._seal_tweens.has(0), "a live online transition from intact to spent starts its own seal exit")
	var remote_animation := replica._combat_indicators._seal_tweens[0] as Tween
	replica.apply_network_state(snapshot)
	check(replica._combat_indicators._seal_tweens[0] == remote_animation, "repeated remote impact state never restarts the seal exit")
	await get_tree().create_timer(0.4).timeout
	check(not replica.effect_icon_1.visible, "the remotely consumed seal finishes disappearing")
	var stolen := _card("STOLEN", [], 100.0)
	stolen.setup(source.export_event_deck_card())
	check(not stolen.effect_icon_1.visible and stolen.get_network_state() == snapshot, "stealing and redrawing preserves consumed seals and all status values")
	check(_badge(stolen, "poison").visible and _badge(stolen, "stun").visible and _badge(stolen, "curse").visible, "stolen cards retain all three status indicators")
	check(source.consume_stun() and not source.consume_stun(), "stun is consumed by exactly one selected attack")
	source.tick_poison()
	check((_badge(source, "poison").get_node("Count") as Label3D).text == "2", "the next poison tick updates the remaining-turn number")
	source.tick_poison()
	source.tick_poison()
	check(not source.has_meta("poison_turns") and not source.has_meta("poison_damage"), "the last poison tick clears both transient fields")
	# Reapplication during an exit must cancel the old hide callback.
	source.apply_poison(4, 5)
	source.stun_next_attack()
	await get_tree().create_timer(0.25).timeout
	check(_badge(source, "poison").visible and _badge(source, "stun").visible and (_badge(source, "poison").get_node("Count") as Label3D).text == "5", "reapplied poison and stun survive the previous exit animation")
	source.apply_poison(0, 0)
	source.consume_stun()
	await get_tree().create_timer(0.25).timeout
	check(not _badge(source, "poison").visible and not _badge(source, "stun").visible and _badge(source, "curse").visible, "expired poison and consumed stun disappear while permanent curse remains")
	replica.apply_network_state(source.get_network_state())
	await get_tree().create_timer(0.25).timeout
	check(not _badge(replica, "poison").visible and not _badge(replica, "stun").visible and _badge(replica, "curse").visible, "online updates remove ended statuses without losing permanent debuffs")
	var data := source.card_data.duplicate(true)
	source.setup(data)
	check(not _badge(source, "curse").visible and source.get_network_state().curse_penalty == 0, "a fresh battle clears the curse indicator and its transient penalty")


func _check_poison_integration() -> void:
	var table := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = get_viewport().get_camera_3d()
	add_child(table)
	table.hide()
	table.set_process(false)
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	table.poison_vfx_scene = null
	table.shield_vfx_scene = null
	var attacker := _card("POISON", [{"type": "poison", "damage": 3, "turns": 1}], 100.0)
	var target := _card("TARGET", [{"type": "shield_first_hit"}], 100.0)
	table._player_slots[0] = target
	table._enemy_slots[0] = attacker
	var blocked := table._resolve_attack_target_hit(attacker, target, 2, {})
	check(not blocked.poison_applied and _badge(target, "poison") == null, "the real shielded hit applies no poison and creates no poison badge")
	var hit := table._resolve_attack_target_hit(attacker, target, 2, {})
	check(hit.poison_applied and _badge(target, "poison").visible, "a real damaging poison hit immediately marks the target")
	var hp_before := target.current_hp
	await table._apply_start_turn_effects("player")
	await get_tree().create_timer(0.25).timeout
	check(target.current_hp == hp_before - 3 and not _badge(target, "poison").visible, "the production turn-start tick deals damage and removes a one-turn poison badge")
	table._player_slots[0] = null
	table._enemy_slots[0] = null
	table.queue_free()
	await get_tree().process_frame


func _card(title: String, effects: Array, x: float) -> Card3D:
	var card := CARD.instantiate() as Card3D
	add_child(card)
	var data := CardDatabase.get_card("corpse").duplicate(true)
	data.merge({"instance_id": "indicator-%d" % cards.size(), "name": title, "attack": 10, "defense": 30, "effects": effects, "active_effects": effects, "animated": false}, true)
	card.position.x = x
	card.setup(data)
	card.description_label.skip()
	cards.append(card)
	return card


func _badge(card: Card3D, type: String) -> Node3D:
	return card.get_node_or_null("CombatIndicators/" + type.capitalize()) as Node3D


func _setup_view() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("181319")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.9
	get_world_3d().environment = environment
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 0.05, 4)
	camera.look_at(Vector3(0, 0.05, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.make_current()


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://" + filename + ".png") == OK, "rendered " + filename)
