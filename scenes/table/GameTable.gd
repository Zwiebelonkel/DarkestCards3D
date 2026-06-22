extends Node3D

@export var card_scene: PackedScene


func _ready() -> void:
	var data := CardDatabase.get_card("wanderer")

	if data.is_empty():
		push_error("Keine Karten gefunden.")
		return

	var card = card_scene.instantiate()
	add_child(card)

	card.position = $CardSpawn.position
	card.rotation_degrees.x = -90

	card.setup(data)
