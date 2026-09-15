extends RefCounted

const THROW_SPEED := 5.5
const UPWARD_SPEED := 3.0
const GRAVITY := 11.0
const FLIGHT_DURATION := 2.4
const MIN_SPIN_SPEED := 5.0
const MAX_SPIN_SPEED := 9.0


# Shared by clicked clutter and dying cards. Sample absolute flight time so
# frame rate cannot change the arc, spin or the object's original scale.
static func transform_at(
	start: Transform3D,
	center_local: Vector3,
	velocity: Vector3,
	spin_axis: Vector3,
	spin_speed: float,
	gravity: float,
	elapsed: float
) -> Transform3D:
	var center := start * center_local + velocity * elapsed
	center += Vector3.DOWN * gravity * elapsed * elapsed * 0.5
	var spun_basis := Basis(spin_axis, spin_speed * elapsed) * start.basis
	return Transform3D(spun_basis, center - spun_basis * center_local)
