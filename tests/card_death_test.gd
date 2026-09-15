extends Node

const THROW_MOTION := preload("res://scripts/table/TableThrowMotion.gd")

var failures := 0
var checks := 0
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run card_death_test with the isolated match-feature runner.")
		get_tree().quit(1)
		return
	_check_ballistic_motion()
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/main/Main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await get_tree().process_frame
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	var card_data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	await _check_death_animation(table, card_data)
	await _check_pause(table, card_data)
	await _check_replacement_order(table, card_data)
	await _check_remote_death_and_reset(table, card_data)
	await _check_draw_origins(table, card_data)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("CARD_DEATH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_ballistic_motion() -> void:
	# Offset geometry and a non-uniform starting scale also cover imported props.
	var start := Transform3D(
		Basis.from_euler(Vector3(0.4, -0.6, 0.2)).scaled(Vector3(0.5, 1.2, 0.8)),
		Vector3(2.0, 4.0, -3.0)
	)
	var center_local := Vector3(0.2, -0.1, 0.4)
	var velocity := Vector3(5.5, 3.0, 0.0)
	var start_center := start * center_local
	var at_start: Transform3D = THROW_MOTION.transform_at(
		start, center_local, velocity, Vector3.FORWARD, 7.0, 11.0, 0.0
	)
	check(at_start.is_equal_approx(start), "throw starts at the existing transform")
	var rising: Transform3D = THROW_MOTION.transform_at(
		start, center_local, velocity, Vector3.FORWARD, 7.0, 11.0, 0.2
	)
	var falling: Transform3D = THROW_MOTION.transform_at(
		start, center_local, velocity, Vector3.FORWARD, 7.0, 11.0, 1.0
	)
	check((rising * center_local).y > start_center.y, "ballistic throw rises first")
	check((falling * center_local).y < start_center.y, "gravity carries the throw below its starting height")
	check((falling * center_local).is_equal_approx(start_center + Vector3(5.5, -2.5, 0.0)), "offset mesh center follows the throw trajectory")
	check(falling.basis.get_scale().is_equal_approx(start.basis.get_scale()), "tumbling preserves object scale")
	check(not falling.basis.is_equal_approx(start.basis), "throw rotates around its spin axis")


func _check_death_animation(table: GameTable, card_data: Dictionary) -> void:
	table._player_deck.append(card_data.duplicate(true))
	table._player_deck.append(card_data.duplicate(true))
	table._draw_to_slot("player", 0, false)
	table._draw_to_slot("player", 1, false)
	var card := table._player_slots[0]
	var living_card := table._player_slots[1]
	var living_materials := _material_state(living_card)
	card.set_selected(true)
	await get_tree().create_timer(0.06).timeout
	card.show_blood_hit(0.6)
	var blood_at_death := card.get_blood_intensity()
	var start := card.global_transform
	var battle_rng_state := table._rng.state
	seed(803751)
	var expected_random := randi()
	seed(803751)
	var tween := table._animate_card_death(card, "player", start.origin + Vector3.FORWARD)
	tween.pause()
	check(randi() == expected_random, "death motion and dissolve leave the global reward RNG untouched")
	check(card.global_transform.is_equal_approx(start), "death preserves a partially raised selected card's starting transform")
	check(is_zero_approx(card.get_death_dissolve_progress()) and _death_surfaces_match(card, 0.0), "death installs the complete body and artwork dissolve at frame zero with no delayed start")
	check(is_equal_approx(card.get_blood_intensity(), blood_at_death) and card.card_image.material_overlay == null, "death retains blood state while removing the separate overlay that could outlive dissolved artwork")
	check(table._rng.state == battle_rng_state, "cosmetic death motion leaves battle randomness unchanged")
	check(card._select_tween == null or not card._select_tween.is_running(), "selection tween cannot compete with death motion")
	tween.custom_step(0.2)
	var first_progress := card.get_death_dissolve_progress()
	check(first_progress > 0.0 and first_progress < 1.0 and is_equal_approx(first_progress, 0.2 / minf(table.death_dissolve_duration, table.death_flight_duration)) and _death_surfaces_match(card, first_progress), "the same initial upward flight step already dissolves every card surface")
	var first_materials := _material_state(card)
	card.begin_death_dissolve()
	card.set_death_dissolve_progress(0.0)
	check(is_equal_approx(card.get_death_dissolve_progress(), first_progress) and _material_state(card) == first_materials, "repeated initialization and stale progress cannot reset or stack an ongoing death dissolve")
	check(card.global_position.y > start.origin.y, "dying card launches upward")
	check(card.global_position.z > start.origin.z, "dying card flies away from the impact source")
	check(card.global_basis.get_scale().is_equal_approx(start.basis.get_scale()), "dying card keeps its size while airborne")
	tween.custom_step(0.8)
	check(is_equal_approx(card.get_death_dissolve_progress(), 1.0) and _death_surfaces_match(card, 1.0), "every surface finishes dissolving during the existing tumble and fall")
	check(card.global_position.y < start.origin.y, "dying card falls under gravity instead of stopping midair")
	check(not card.global_basis.is_equal_approx(start.basis), "dying card tumbles in flight")
	tween.custom_step(1.2)
	check(is_instance_valid(card) and not card.is_queued_for_deletion() and is_equal_approx(card.get_death_dissolve_progress(), 1.0), "fully dissolved card remains allocated until the original flight cleanup deadline")
	check(_material_state(living_card) == living_materials and is_zero_approx(living_card.get_death_dissolve_progress()), "a neighboring living card retains its original materials and presentation")
	tween.custom_step(table.death_flight_duration)
	check(is_equal_approx(card.get_death_dissolve_progress(), 1.0) and _death_surfaces_match(card, 1.0) and card.is_queued_for_deletion(), "the final flight step dissolves all card surfaces completely and queues normal cleanup")
	await get_tree().process_frame
	check(not is_instance_valid(card) and is_instance_valid(living_card), "normal flight completion frees only the dead card")
	table._clear_match()
	await get_tree().process_frame


func _check_pause(table: GameTable, card_data: Dictionary) -> void:
	table._player_deck.append(card_data.duplicate(true))
	table._draw_to_slot("player", 0, false)
	var card := table._player_slots[0]
	var tween := table._animate_card_death(card, "player")
	await get_tree().create_timer(0.12).timeout
	var paused_pose := card.global_transform
	var paused_progress := card.get_death_dissolve_progress()
	get_tree().paused = true
	await get_tree().create_timer(0.15, true).timeout
	check(card.global_transform.is_equal_approx(paused_pose) and is_equal_approx(card.get_death_dissolve_progress(), paused_progress), "SceneTree pause freezes the death flight and dissolve on the same frame")
	get_tree().paused = false
	await get_tree().create_timer(0.12).timeout
	check(not card.global_transform.is_equal_approx(paused_pose) and card.get_death_dissolve_progress() > paused_progress, "unpausing resumes both motion and dissolve together")
	tween.kill()
	table._clear_match()
	await get_tree().process_frame
	check(not is_instance_valid(card), "an interrupted death can be cleared without leaving a dissolving card behind")


func _check_replacement_order(table: GameTable, card_data: Dictionary) -> void:
	table._player_deck.append(card_data.duplicate(true))
	table._player_deck.append(card_data.duplicate(true))
	table._draw_to_slot("player", 0, false)
	var card := table._player_slots[0]
	table._remove_dead_card(card, false)
	table._remove_dead_card(card, false)
	check(table._player_slots[0] == null, "dead card leaves its playable slot immediately")
	check(not card.area.input_ray_pickable, "flying dead card cannot be clicked")
	check(table._pending_card_deaths.size() == 1, "duplicate death notification creates one flight and one replacement")
	await get_tree().create_timer(0.05).timeout
	check(is_instance_valid(card) and table._player_slots[0] == null, "replacement gives the dying card a brief slot-clearance interval")
	var before_duplicate := card.get_death_dissolve_progress()
	var death_materials := _material_state(card)
	table._remove_dead_card(card, false)
	check(before_duplicate > 0.0 and is_equal_approx(card.get_death_dissolve_progress(), before_duplicate) and _material_state(card) == death_materials, "duplicate death delivery cannot restart or stack the active dissolve")
	await get_tree().create_timer(table.replacement_draw_delay).timeout
	check(is_instance_valid(table._player_slots[0]) and card.get_death_dissolve_progress() > 0.0 and card.get_death_dissolve_progress() < 1.0, "replacement draw starts while the original card is still visibly dissolving")
	await get_tree().create_timer(table.replacement_draw_delay + table.draw_animation_duration + 0.15).timeout
	var replacement := table._player_slots[0]
	check(is_instance_valid(card) and not card.is_queued_for_deletion(), "full death flight continues while the replacement arrives")
	check(card.get_death_dissolve_progress() > 0.0, "replacement arrival preserves the ongoing death presentation instead of resetting it")
	check(is_instance_valid(replacement), "replacement reaches the empty slot within a fraction of a second")
	check(not table._has_pending_card_replacements(), "remaining cosmetic flight no longer blocks the next action")
	check(table._player_deck.is_empty(), "replacement consumes one card from the deck")
	if is_instance_valid(replacement):
		check(replacement.global_position.is_equal_approx(table._player_slot_markers[0].global_position), "replacement finishes at its slot")
		check(is_zero_approx(replacement.get_death_dissolve_progress()) and not _death_surfaces_match(replacement, 0.0), "a replacement starts with normal living-card materials")
	var deadline := Time.get_ticks_msec() + 5000
	while not table._pending_card_deaths.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(table._pending_card_deaths.is_empty(), "death and replacement finish without a stalled action barrier")
	check(not is_instance_valid(card), "dead card is freed after its flight")
	check(is_instance_valid(replacement) and table._player_slots[0] == replacement, "flight cleanup cannot remove the replacement card")
	table._clear_match()
	await get_tree().process_frame


func _check_remote_death_and_reset(table: GameTable, card_data: Dictionary) -> void:
	table._enemy_deck.append(card_data.duplicate(true))
	table._enemy_deck.append(card_data.duplicate(true))
	table._draw_to_slot("enemy", 0, false)
	var card := table._enemy_slots[0]
	# Remote clients/spectators wait for the host snapshot to supply replacement.
	table._remove_dead_card(card, false, Vector3(INF, INF, INF), false)
	await get_tree().create_timer(table.replacement_draw_delay + 0.1).timeout
	check(not table._has_pending_card_replacements() and is_instance_valid(card), "remote death releases the snapshot barrier before its cosmetic flight ends")
	check(card.get_death_dissolve_progress() > 0.0 and _death_surfaces_match(card, card.get_death_dissolve_progress()), "remote death uses the same in-flight dissolve without granting local replacements")
	check(table._enemy_slots[0] == null and table._enemy_deck.size() == 1, "remote death leaves replacement to the authoritative snapshot")
	table._draw_to_slot("enemy", 0, false)
	var interrupted_card := table._enemy_slots[0]
	table._enemy_deck.append(card_data.duplicate(true))
	var original_draw_duration := table.draw_animation_duration
	table.draw_animation_duration = 1.0
	table._remove_dead_card(interrupted_card, false)
	await get_tree().create_timer(table.replacement_draw_delay + 0.1).timeout
	var interrupted_job: Dictionary = table._pending_card_deaths.back()
	var interrupted_tween := interrupted_job.get("tween") as Tween
	var interrupted_draw := interrupted_job.get("draw_tween") as Tween
	check(interrupted_draw != null and interrupted_draw.is_running(), "reset fixture interrupts an active replacement draw")
	check(interrupted_card.get_death_dissolve_progress() > 0.0, "reset interrupts a card whose death dissolve is already advancing")
	table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not interrupted_tween.is_valid(), "match reset kills the in-flight death tween")
	check(interrupted_draw == null or not interrupted_draw.is_valid(), "match reset also kills the replacement tween")
	check(not is_instance_valid(interrupted_card) and table._pending_card_deaths.is_empty(), "match reset frees flying cards and clears death jobs")
	check(table._enemy_slots[0] == null, "cancelled death cannot refill a reset board")
	table.draw_animation_duration = original_draw_duration


func _check_draw_origins(table: GameTable, card_data: Dictionary) -> void:
	for index in range(8):
		table._player_deck.append(card_data.duplicate(true))
	table._rebuild_stack_visual("player")
	var top_position: Vector3 = table._player_stack_visuals.back().global_position
	var draw := table._draw_to_slot("player", 0, true)
	draw.pause()
	check(table._player_slots[0].global_position.is_equal_approx(top_position), "local draw starts at the pre-draw pile top")
	draw.kill()
	var dead_card := table._player_slots[0]
	dead_card.current_hp = 0
	check(table._serialize_online_slots(table._player_slots)[0] == null, "replacement snapshots cannot respawn a dead card still finishing its attack")
	table._clear_match()
	await get_tree().process_frame
	table._enemy_deck = table._network_placeholder_deck(3)
	var states: Array = []
	for index in range(2):
		var data := card_data.duplicate(true)
		data["instance_id"] = "incoming-%d" % index
		states.append({"card_data": data})
	var draws := table._reconcile_online_slots("enemy", states, true)
	for tween: Tween in draws:
		tween.pause()
	check(table._enemy_slots[0].global_position.is_equal_approx(table._get_stack_top_position("enemy", 5)), "first simultaneous remote draw starts at the previous top")
	check(table._enemy_slots[1].global_position.is_equal_approx(table._get_stack_top_position("enemy", 4)), "second simultaneous remote draw starts one layer lower")
	for tween: Tween in draws:
		tween.kill()
	table._clear_match()
	await get_tree().process_frame


func _death_surfaces_match(card: Card3D, progress: float) -> bool:
	var body := card.card_model.get_node("Cube") as MeshInstance3D
	for mesh: MeshInstance3D in [body, card.card_image]:
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material == null or material.shader == null or material.shader.resource_path != "res://assets/shader/dissolve.gdshader":
				return false
			if not is_equal_approx(float(material.get_shader_parameter("dissolve_progress")), progress) or material.get_shader_parameter("use_local_space") != true:
				return false
	return true


func _material_state(card: Card3D) -> Array:
	var state: Array = []
	for node in card.find_children("*", "GeometryInstance3D", true, false):
		state.append([node, node.visible])
		if node is MeshInstance3D and node.mesh != null:
			state.append([node.material_override, node.material_overlay])
			for surface in range(node.mesh.get_surface_count()):
				var material: Material = node.get_active_material(surface)
				state.append([material, material.next_pass if material != null else null])
	return state
