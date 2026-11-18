extends RefCounted

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")


static func play(parent: Node, instance: Dictionary, camera: Camera3D, origin: Vector3, follow_camera: bool = false) -> Card3D:
	if not is_instance_valid(camera) or not parent.is_inside_tree():
		return null
	var card := CARD_SCENE.instantiate() as Card3D
	card.name = "DiscoveredUsbSecret" if instance.get("card_id") == "usb_stick" else "DiscoveredPropSecret"
	card.top_level = not follow_camera
	var reveal_parent: Node = camera if follow_camera else parent
	reveal_parent.add_child(card)
	card.setup(CardData.merge_card_and_instance(CardDatabase.get_card(str(instance["card_id"])), instance))
	card.description_label.skip()
	_disable_picking(card)
	# A station can refocus as its item tray closes. Keep these optional
	# camera-relative reveals visible throughout that camera movement.
	var facing := Basis.IDENTITY if follow_camera else camera.global_basis.orthonormalized()
	var destination := Vector3(0, -0.08, -1.6) if follow_camera else camera.global_position - facing.z * 1.6 - facing.y * 0.08
	var transform_property := "transform" if follow_camera else "global_transform"
	card.set(transform_property, Transform3D(facing.scaled(Vector3.ONE * 0.15), camera.to_local(origin) if follow_camera else origin))
	var reveal := card.create_tween()
	reveal.tween_property(card, transform_property, Transform3D(facing, destination), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for angle in [-18.0, 18.0, 0.0]:
		var pose := Transform3D(facing * Basis(Vector3.UP, deg_to_rad(angle)), destination)
		reveal.tween_property(card, transform_property, pose, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(card, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	reveal.tween_callback(card.queue_free)
	return card


static func _disable_picking(node: Node) -> void:
	if node is Area3D:
		node.input_ray_pickable = false
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_meta("keep_input_ray_pickable_disabled", true)
	for child in node.get_children():
		_disable_picking(child)
