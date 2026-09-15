extends Node3D

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run only with isolated test saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CollectionManager.add_card("corpse")
	var screen := (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D")
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.detail_duration = 0.01
	screen.detail_mouse_tilt_strength = 0.0
	add_child(screen)
	await get_tree().create_timer(0.05).timeout
	check(screen.cards_root.get_node_or_null("RarityLabel_secret") == null and screen._row_cards.secret.is_empty(), "an ordinary collection has no Secret label before its first Secret")
	var ordinary: Card3D = screen._row_cards.common[0]
	await screen._open_detail_card(ordinary)
	var detail_pose := ordinary.global_transform
	var random := RandomNumberGenerator.new()
	for count in range(49):
		CollectionManager.discover_prop_secret("usb_stick", random)
	await _settle()
	check(screen.cards_root.get_node_or_null("RarityLabel_secret") == null and screen._row_cards.secret.is_empty(), "49 USB throws neither reveal the row nor add a card")
	var earned := CollectionManager.discover_prop_secret("usb_stick", random)
	await _settle()
	check(not earned.is_empty() and screen._row_cards.secret.size() == 1, "the 50th throw adds its Secret to the live collection by the next frame")
	check(screen.cards_root.get_node_or_null("RarityLabel_secret") != null, "the first awarded Secret reveals its label immediately")
	check(screen._detail_card == ordinary and ordinary.global_transform.is_equal_approx(detail_pose), "an active ordinary detail remains open and unmoved during the grant")
	var secret: Card3D = screen._row_cards.secret[0]
	check(secret.scale == screen._base_scales[secret] and secret.position == screen._base_positions[secret] and secret.get("_diorama_art") != null, "the new Secret is full-sized and already renders its live room without the full collection entrance delay")
	var changed_ids: Array[String] = ["usb_stick"]
	CollectionManager.collection_changed.emit(changed_ids)
	CollectionManager.add_card("usb_stick")
	await _settle()
	check(screen._row_cards.secret.size() == 1 and secret.get_node("AmountLabel").text == "x2", "repeated notifications and duplicate copies update one visible card's quantity")
	CollectionManager.add_card("cigarettes")
	await _settle()
	check(screen._row_cards.secret.size() == 2 and screen._detail_card == ordinary, "another reward source updates the same live row without closing details")
	await screen._close_detail_card()
	DeckManager.add_card("usb_stick")
	DeckManager.add_card("usb_stick")
	screen._refresh_collection_amount_labels()
	await screen._open_detail_card(secret)
	check(screen._deck_button.label_text == "MAX OWNED", "the currently owned Secret copies are exhausted in the deck")
	CollectionManager.add_card_instance(CardData.create_instance("usb_stick", 1, [], true))
	await _settle()
	check(screen._detail_card == secret and screen._deck_button.label_text != "MAX OWNED" and not screen._deck_button.disabled, "a new Secret copy immediately reenables the open detail's deck button")
	check(CardData.is_holo(secret.card_data) and secret.get_node("AmountLabel").text == "x1" and secret.get_node("AmountLabel").modulate == Color.WHITE, "a new Holo copy refreshes the existing artwork and available-copy styling")
	await screen._close_detail_card()
	DeckManager.clear_profile_state()
	CollectionManager.collection.cards.clear()
	CollectionManager.collection.instances.clear()
	CollectionManager.save_collection()
	screen.refresh_collection()
	await _settle()
	check(screen._row_cards.secret.is_empty() and screen.cards_root.get_node_or_null("RarityLabel_secret") != null, "having received a Secret keeps the label unlocked even after losing its last copy")
	screen.queue_free()
	await _settle()
	CollectionManager.clear_profile_state()
	CollectionManager.add_card("corpse")
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D")
	add_child(screen)
	check(screen.cards_root.get_node_or_null("RarityLabel_secret") == null, "a fresh profile does not inherit the previous profile's Secret label")
	screen.queue_free()
	await _settle()
	print("SECRET_COLLECTION_REFRESH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
