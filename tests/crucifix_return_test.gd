extends "res://tests/holy_water_return_test.gd"


class ControlledCollection:
	extends "res://scripts/autoload/CollectionManager.gd"
	var reject_save := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return not reject_save


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	_test_return_gate()
	reward_card_id = "crucifix"
	dialogue_node_name = "SatanCrucifixDialogue"
	seen_flag = "crucifix_return_dialogue_seen"
	if success_marker == "HOLY_WATER_RETURN_TESTS":
		success_marker = "CRUCIFIX_RETURN_TESTS"
	await super._run()


func _test_return_gate() -> void:
	var manager := ControlledCollection.new()
	add_child(manager)
	check(not manager.claim_crucifix_return_dialogue(), "no Crucifix discovery means no return sequence")
	manager.add_card("jester_eye")
	check(not manager.claim_crucifix_return_dialogue(), "the eye alone cannot start the cross conversation")
	GameCurrency._rescued_npcs["jester"] = true
	check(not manager.exchange_jester_eye().is_empty(), "trading the eye acquires the Crucifix")
	GameCurrency.set_training_session(self, true)
	check(not manager.claim_crucifix_return_dialogue(), "training cannot consume the return sequence")
	GameCurrency.set_training_session(self, false)
	var before := manager.collection.duplicate(true)
	manager.reject_save = true
	check(not manager.claim_crucifix_return_dialogue() and manager.collection == before, "a failed save preserves the pending sequence")
	manager.reject_save = false
	check(manager.claim_crucifix_return_dialogue(), "retry durably claims the Crucifix return sequence")
	check(not manager.claim_crucifix_return_dialogue(), "the Crucifix return is one-time")
	manager.add_card("holy_water")
	check(manager.claim_holy_water_return_dialogue(), "the Crucifix return does not consume the separate Holy Water sequence")
	manager.clear_profile_state()
	manager.add_card("holy_water")
	check(manager.claim_holy_water_return_dialogue(), "the Holy Water sequence can happen first")
	manager.add_card("jester_eye")
	check(not manager.exchange_jester_eye().is_empty(), "fixture trades the eye before returning home")
	check(manager.get_amount("jester_eye") == 0 and manager.claim_crucifix_return_dialogue(), "the cross conversation triggers after the eye was consumed, independently of Holy Water")
	manager.clear_profile_state()
	check(not manager.claim_crucifix_return_dialogue(), "a fresh profile has independent sequence state")
	manager.free()
