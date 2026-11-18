extends "res://tests/crucifix_return_test.gd"


func _run() -> void:
	outside_area_id = "basement"
	outside_room = 3
	expected_return_side = 1
	success_marker = "BASEMENT_ITEM_RETURN_TESTS"
	await super._run()
