extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const OVERVIEW_SCENE := preload("res://scenes/CardEffectOverview.tscn")

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures.append(description)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run eimer_card_test with the isolated match feature test runner.")
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1280, 720)
	var eimer := CardDatabase.get_card("piss")
	_expect(not eimer.is_empty() and eimer.get("name") == "Pisse-Eimer", "Pisse-Eimer is registered under a unique card ID")
	var matching_ids := 0
	for data: Dictionary in CardDatabase.get_all_cards():
		if data.get("id") == "piss":
			matching_ids += 1
	_expect(matching_ids == 1, "Card database contains exactly one Eimer definition")
	_expect(int(eimer.get("attack", 0)) == 1 and int(eimer.get("defense", 0)) == 5, "Pisse-Eimer has 1 attack and 5 health")
	_expect(eimer.get("rarity") == "epic", "Eimer uses epic rarity for its low base values and area attack")
	_expect(CardData.is_combat_card(eimer) and CardDatabase.get_combat_cards().has(eimer), "Pisse-Eimer is available to combat decks and the AI card pool")
	_expect(CardDatabase.get_cards_by_rarity("epic").has(eimer), "Pisse-Eimer is in the epic pack pool")
	_expect(CardData.has_effect(eimer, "lava") and CardData.get_active_effects(eimer).size() == 1, "Eimer carries Lava as its single innate effect")
	var lava := EffectDatabase.get_effect("lava")
	_expect(not lava.is_empty() and lava.get("name") == "Lava", "Lava is registered in the shared effect catalog")
	var presentation := EffectPresentation.build({"type": "lava"}, "epic")
	_expect(presentation.get("title") == "Lava" and presentation.get("badge") == "ALLE GEGNER", "Type-only Lava resolves to a readable title and all-enemies badge")
	_expect(str(presentation.get("description", "")).contains("gleichzeitig"), "Lava tooltip describes its simultaneous attack")
	_expect(presentation.get("icon_path") == "res://assets/effects/lava.svg" and presentation.get("icon") is Texture2D, "Lava loads its dedicated SVG icon instead of the placeholder")

	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	CardUpgradeManager.upgrades.clear()
	var all_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	CardDatabase.cards = [eimer]
	CardDatabase.set_pack_rarity_weights({"epic": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "piss", "Pack reward selection can award Eimer")
	CardDatabase.cards = all_cards
	CardDatabase.set_pack_rarity_weights({})
	var instance := CollectionManager.add_card("piss")
	CollectionManager.add_card("piss")
	_expect(not instance.is_empty() and CollectionManager.get_amount("piss") == 2, "Eimer can be collected more than once as a normal combat card")
	CollectionManager.load_collection()
	_expect(CollectionManager.get_amount("piss") == 2 and CollectionManager.get_instances_for_card("piss").size() == 2, "Eimer ownership and instances survive save and reload")
	_expect(DeckManager.add_card("piss") and DeckManager.add_card("piss"), "Owned Eimer copies can both enter the battle deck")
	DeckManager.load_deck()
	_expect(DeckManager.get_deck_cards() == ["piss", "piss"], "Deck persistence preserves Eimer copies")
	var merged := CardData.merge_card_and_instance(eimer, instance)
	_expect(CardData.has_effect(merged, "lava") and merged.get("instance_id") == instance.get("instance_id"), "Random instance effects preserve innate Lava and instance identity")
	CardUpgradeManager.add_attack("piss", 2)
	CardUpgradeManager.add_health("piss", 1)
	_expect(CardUpgradeManager.add_effect("piss", {"type": "lifesteal", "percent": 0.25}), "Eimer retains one extra purchasable effect slot")
	CardUpgradeManager.load_upgrades()
	var upgraded := CardUpgradeManager.apply_upgrades("piss", eimer)
	_expect(int(upgraded.get("attack")) == 3 and int(upgraded.get("defense")) == 6 and CardData.has_effect(upgraded, "lava") and CardData.has_effect(upgraded, "lifesteal"), "Saved stat and effect upgrades preserve Lava")
	var payload := CardData.merge_card_and_instance(upgraded)
	_expect(CardData.has_effect(payload, "lava") and CardData.get_active_effects(payload).size() == 2, "Prepared battle card data retains Lava alongside its upgrade")
	_expect(CardData.has_effect(NetworkManager._sanitize_remote_card(payload), "lava"), "Remote deck validation accepts the new registered card and Lava")
	await _render_card(eimer)
	if _failures.is_empty():
		print("EIMER_CARD_TESTS: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _render_card(eimer: Dictionary) -> void:
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
	camera.size = 1.85
	camera.make_current()
	var card := CARD_SCENE.instantiate() as Card3D
	add_child(card)
	card.position.x = -0.75
	card.setup(eimer)
	card.description_label.skip()
	_expect(card.attack_value == 1 and card.max_hp == 5 and card.current_hp == 5, "Real Card3D initializes the requested combat values")
	_expect(card.attack_label.visible and card.defense_label.visible and card.attack_label.text == "1" and card.defense_label.text == "5", "Real card displays both attack and health")
	_expect(card.rarity_label.text == Localization.text("EPIC"), "Real card displays its assigned rarity")
	var art := card.card_image.material_override as StandardMaterial3D
	_expect(art != null and art.albedo_texture != null and art.albedo_texture.resource_path == str(eimer.get("image")), "Generated bucket artwork loads into the actual card material")
	_expect(card.effect_icon_1.visible and card.effect_icon_1.texture != null and card.effect_icon_1.texture.resource_path == "res://assets/effects/lava.svg", "Real card effect slot displays the Lava icon")
	var icon_image := card.effect_icon_1.texture.get_image()
	_expect(icon_image.get_pixel(4, 4).a < 0.01 and icon_image.get_pixel(32, 48).a > 0.99, "Lava icon has a transparent background and an opaque flame for the alpha-only card hologram")
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var overview := OVERVIEW_SCENE.instantiate() as CardEffectOverviewUI
	canvas.add_child(overview)
	overview.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overview.offset_left = 685
	overview.offset_right = 1240
	overview.offset_top = 255
	overview.offset_bottom = 490
	overview._rest_offset_left = overview.offset_left
	overview._rest_offset_right = overview.offset_right
	overview.show_for_card(card)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	_expect(overview.visible and overview._effect_names[0].text == "Lava" and overview._badge_labels[0].text == "ALLE GEGNER", "Actual effect overview presents Lava and its target badge")
	_expect(overview._icons[0].texture != null and overview._icons[0].texture.resource_path == "res://assets/effects/lava.svg" and not overview._row_panels[1].visible, "Overview loads the dedicated icon and shows exactly one effect")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png("res://eimer-card-lava.png") == OK, "Eimer card and Lava tooltip render saves for visual review")
