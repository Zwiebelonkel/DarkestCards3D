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
	reward_card_id = "silver_bullet"
	dialogue_node_name = "SatanSilverBulletDialogue"
	seen_flag = "silver_bullet_return_dialogue_seen"
	expected_sentence_count = 3
	expected_laugh_index = 2
	success_marker = "SILVER_BULLET_RETURN_TESTS"
	await super._run()


func _test_return_gate() -> void:
	var manager := ControlledCollection.new()
	add_child(manager)
	check(not manager.claim_silver_bullet_return_dialogue(), "without the Silver Bullet there is no return conversation")
	manager.add_card("holy_water")
	manager.add_card("crucifix")
	check(not manager.claim_silver_bullet_return_dialogue(), "other story items cannot trigger the bullet conversation")
	manager.add_card("silver_bullet")
	GameCurrency.set_training_session(self, true)
	check(not manager.claim_silver_bullet_return_dialogue(), "training cannot consume the pending bullet conversation")
	GameCurrency.set_training_session(self, false)
	manager.reject_save = true
	var before := manager.collection.duplicate(true)
	check(not manager.claim_silver_bullet_return_dialogue() and manager.collection == before, "a failed save preserves the pending conversation for a later return")
	manager.reject_save = false
	check(manager.claim_silver_bullet_return_dialogue(), "retry durably claims the Silver Bullet return")
	check(not manager.claim_silver_bullet_return_dialogue(), "the bullet conversation can only be claimed once")
	check(manager.claim_holy_water_return_dialogue() and manager.claim_crucifix_return_dialogue(), "bullet, Holy Water and Crucifix conversations have independent one-time flags")
	manager.clear_profile_state()
	check(not manager.claim_silver_bullet_return_dialogue(), "a new profile has no inherited bullet conversation")
	manager.free()
	var script := load("res://scripts/main/SatanSilverBulletDialogue.gd")
	var conversation: Node = script.new()
	check(conversation._get_story_sentences() == ["Was willst du mit dieser Kugel?", "Hä?", "Für deinen Arsch?"], "the dialogue contains exactly the requested three lines in order")
	conversation.free()
