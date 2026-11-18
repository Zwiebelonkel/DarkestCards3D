extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	# Keep the timed Satan encounter from pausing cosmetic fade checks.
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	for scene_path in ["res://scenes/table/GameTable.tscn", "res://scenes/main/Main.tscn"]:
		var scene := (load(scene_path) as PackedScene).instantiate()
		if scene is GameTable:
			var fixture_camera := Camera3D.new()
			scene.add_child(fixture_camera)
			scene.table_camera = fixture_camera
		add_child(scene)
		await get_tree().process_frame
		var table := scene as GameTable if scene is GameTable else scene.get_node("ScenePivot/GameTable") as GameTable
		table._clear_match()
		var surface := table.get_node("table/Cube") as MeshInstance3D
		var bounds := (table.global_transform.affine_inverse() * surface.global_transform) * surface.get_aabb()
		var card := CARD_SCENE.instantiate() as Card3D
		table.add_child(card)
		var data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
		card.setup(data)
		card.set_process(false)
		for is_kill in [false, true]:
			var expected_scale: Vector3
			for height in [-0.2, 0.2, 1.0]:
				card.position = Vector3(0.6, height, 1.2)
				var previous_count := table.get_child_count()
				table._spawn_blood_decal_under_card(card, is_kill, false)
				check(table.get_child_count() == previous_count + 1, "hit spawns a table stain")
				var decal := table.get_child(-1) as BloodDecal3D
				expected_scale = decal.kill_scale if is_kill else decal.normal_scale
				check(decal.scale.is_equal_approx(expected_scale), "hit and kill retain their authored stain sizes")
				var corners_clear := true
				var mesh := decal.decal_mesh
				for corner in [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0)]:
					var local_corner := table.to_local(mesh.to_global(corner))
					corners_clear = corners_clear and is_equal_approx(local_corner.y, bounds.end.y + table.blood_decal_offset.y)
				check(corners_clear, "every stain corner stays above the table at card height " + str(height))
				check(is_equal_approx(decal.position.x, card.position.x) and is_equal_approx(decal.position.z, card.position.z), "stain remains directly below the impact")
				decal.free()
		card.position = Vector3(0, 0.2, 1.2)
		table._spawn_blood_decal_under_card(card, true, false)
		var fading := table.get_child(-1) as BloodDecal3D
		if DisplayServer.get_name() != "headless":
			card.hide()
			for canvas in scene.find_children("*", "CanvasLayer", true, false):
				canvas.hide()
			var camera := Camera3D.new()
			add_child(camera)
			camera.global_position = table.to_global(Vector3(0, 2.8, 4.5))
			camera.look_at(table.to_global(Vector3(0, bounds.end.y, 0)))
			camera.make_current()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://blood-decal-" + scene.name + ".png")
			camera.queue_free()
		# Existing fade tween should still clean up the anchored stain.
		await get_tree().create_timer(3.6).timeout
		check(not is_instance_valid(fading), "anchored stain fades and frees normally")
		for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
			audio.stop()
		for audio in scene.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		scene.queue_free()
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("BLOOD_DECAL_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
