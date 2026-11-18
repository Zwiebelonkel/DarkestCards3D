extends Node3D

const SHOP_SCENE := preload("res://scenes/UpgradeShop.tscn")

var checks := 0
var failures := 0
var shop: UpgradeMachine
var camera: Camera3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures += 1


func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run in an isolated test project.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	GameCurrency._rescued_npcs["angel"] = true
	GameCurrency.coins = 1000.0
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.clear_profile_state()
	for card_id in ["corpse", "corpse", "jd", "wanderer", "clicker", "slot_room_key"]:
		CollectionManager.add_card(card_id)
	DeckManager.add_card("corpse")
	DeckManager.add_card("corpse")
	DeckManager.add_card("jd")
	camera = Camera3D.new()
	add_child(camera)
	shop = SHOP_SCENE.instantiate() as UpgradeMachine
	add_child(shop)
	shop.upgrade_viewport.notify_mouse_entered()
	await settle()
	check(_ids() == ["corpse", "jd", "wanderer"], "initial list includes every owned combat type and excludes upgrades and keys")
	check(not shop.ui.deck_only and not shop.ui.card_filter_button.button_pressed, "YOUR CARDS starts in the full collection mode")
	shop._on_card_selected("wanderer")
	await _click_filter()
	check(shop.ui.deck_only and shop.ui.card_filter_button.button_pressed, "real 3D screen press toggles the YOUR CARDS button on")
	check(_ids() == ["corpse", "jd"], "deck filter shows current deck types once even for duplicate deck copies")
	check(shop.selected_card_id.is_empty() and shop.ui.selected_card_id.is_empty() and shop.preview_card == null and shop.ui.attack_button.disabled, "filtering out a card clears its preview and disables upgrades")
	check(shop.ui.card_count_label.text.contains("2"), "count matches the visible deck types")
	shop._on_card_selected("corpse")
	await _click_filter()
	check(not shop.ui.deck_only and _ids() == ["corpse", "jd", "wanderer"], "second physical screen click restores the full collection")
	check(shop.selected_card_id == "corpse" and shop.ui.selected_card_id == "corpse" and is_instance_valid(shop.preview_card), "a still-visible selection and its preview survive toggling")
	await _click_filter()
	CollectionManager.add_card("mailman")
	await settle()
	check(shop.ui.deck_only and _ids() == ["corpse", "jd"], "collection acquisitions keep the active filter and exclude cards outside the deck")
	DeckManager.add_card("mailman")
	await settle()
	check(_ids() == ["corpse", "jd", "mailman"], "editing the current deck refreshes the filtered machine without reopening it")
	DeckManager.remove_card("corpse")
	await settle()
	check(shop.ui.card_buttons.has("corpse") and shop.selected_card_id == "corpse", "removing one duplicate keeps that deck card type and current selection")
	DeckManager.remove_card("corpse")
	await settle()
	check(_ids() == ["jd", "mailman"] and shop.selected_card_id.is_empty() and shop.preview_card == null, "removing the last deck copy also clears its selection and preview")
	DeckManager.clear_profile_state()
	await settle()
	check(shop.ui.card_buttons.is_empty() and shop.ui.attack_button.disabled and shop.ui.card_count_label.text.contains("0"), "empty deck displays an empty filtered list rather than the collection")
	await _click_filter()
	check(_ids() == ["corpse", "jd", "mailman", "wanderer"], "turning filtering off after an empty deck reveals newly acquired cards immediately")
	DeckManager.add_card("corpse")
	await _click_filter()
	CollectionManager.add_card("corpse")
	await settle()
	check(_ids() == ["corpse"] and int(shop.ui.card_buttons["corpse"].get_meta("owned_amount")) == 3, "acquiring another deck-card copy refreshes the visible owned count")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(shop.upgrade_viewport.get_texture().get_image().save_png("res://test-user/upgrade-deck-filter.png") == OK, "saved the actual filtered upgrade screen")
	shop.queue_free()
	await settle()
	print("UPGRADE_DECK_FILTER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _ids() -> Array:
	var ids := shop.ui.card_buttons.keys()
	ids.sort()
	return ids


func _click_filter() -> void:
	var target := shop.ui.card_filter_button.get_global_rect().get_center()
	var uv := target / Vector2(shop.upgrade_viewport.size)
	var mesh := shop.screen_mesh
	var quad := mesh.mesh as QuadMesh
	# Derive the 3D hit from the visible screen, exercising the production
	# ScreenArea signal and SubViewport coordinate forwarding end to end.
	var hit := mesh.to_global(Vector3((uv.x - 0.5) * quad.size.x, (0.5 - uv.y) * quad.size.y, 0.0))
	var area := shop.get_node("ScreenArea") as Area3D
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(137, 81)
	motion.global_position = motion.position
	area.input_event.emit(camera, motion, hit, Vector3.FORWARD, 0)
	check(shop.upgrade_viewport.gui_get_hovered_control() == shop.ui.card_filter_button, "screen ray hovers the clickable title")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		area.input_event.emit(camera, event, hit, Vector3.FORWARD, 0)
	await settle()
