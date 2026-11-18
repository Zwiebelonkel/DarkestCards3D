extends RefCounted

## Camera-relative, unrestricted rotation shared by both collection details.
## Rotation stays transient; closing a detail restores its authored transform.
var dragging := false
var has_rotated := false
var orientation := Quaternion.IDENTITY
var radians_per_pixel := 0.008


func reset() -> void:
	dragging = false
	has_rotated = false
	orientation = Quaternion.IDENTITY


func stop() -> void:
	dragging = false


func begin(card: Node3D, camera: Camera3D, pointer: Vector2) -> bool:
	if not contains_pointer(card, camera, pointer):
		return false
	dragging = true
	return true


func drag(card: Node3D, camera: Camera3D, event: InputEventMouseMotion) -> void:
	if not dragging:
		return
	if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		stop()
		return
	if event.relative.is_zero_approx():
		return
	var frame := camera.global_basis.orthonormalized()
	var turn := Basis(frame.y, event.relative.x * radians_per_pixel) * Basis(frame.x, event.relative.y * radians_per_pixel)
	var rotated := (turn * card.global_basis.orthonormalized()).orthonormalized()
	orientation = (frame.inverse() * rotated).get_rotation_quaternion().normalized()
	has_rotated = true
	apply(card, camera)


func apply(card: Node3D, camera: Camera3D) -> void:
	if has_rotated:
		card.global_basis = (camera.global_basis.orthonormalized() * Basis(orientation)).scaled(card.global_basis.get_scale())


func contains_pointer(card: Node3D, camera: Camera3D, pointer: Vector2) -> bool:
	if not is_instance_valid(card) or not is_instance_valid(camera) or not card.is_visible_in_tree() or camera.is_position_behind(card.global_position):
		return false
	var collision := card.get_node_or_null("Area3D/CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return false
	# Test the oriented box directly: back faces and thin edge-on cards remain
	# grabbable even in the wall collection, where physics picking is disabled.
	var inverse := collision.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(pointer)
	var direction := inverse.basis * camera.project_ray_normal(pointer)
	var size := (collision.shape as BoxShape3D).size
	return AABB(-size * 0.5, size).intersects_ray(origin, direction) != null
