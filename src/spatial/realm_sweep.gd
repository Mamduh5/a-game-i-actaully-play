class_name RealmSweep
extends RefCounted
## Analytical scalar-double circle sweeps. Callers must resolve compatibility
## and use reviewed sub-tick ordering before publishing consequential contacts.

const MISS := -1.0

class Point:
	var x: float
	var y: float

	func _init(px: float, py: float) -> void:
		x = px
		y = py


## Time in [0,1] for two linearly moving circles, or MISS. Both paths are in one realm.
static func moving_circles(start: Point, finish: Point, radius: float,
		target_start: Point, target_finish: Point, target_radius: float) -> float:
	if (not _point_valid(start) or not _point_valid(finish) or not _point_valid(target_start)
			or not _point_valid(target_finish) or not _radius_valid(radius) or not _radius_valid(target_radius)):
		return NAN
	return _circle(start.x - target_start.x, start.y - target_start.y,
		(finish.x - start.x) - (target_finish.x - target_start.x),
		(finish.y - start.y) - (target_finish.y - target_start.y), radius + target_radius)


## Time against the closed segment, including endpoint and initial contacts.
static func circle_segment(start: Point, finish: Point, radius: float, a: Point, b: Point) -> float:
	if (not _point_valid(start) or not _point_valid(finish) or not _point_valid(a)
			or not _point_valid(b) or not _radius_valid(radius)):
		return NAN
	var from_x := start.x - a.x
	var from_y := start.y - a.y
	var delta_x := finish.x - start.x
	var delta_y := finish.y - start.y
	var edge_x := b.x - a.x
	var edge_y := b.y - a.y
	var first := _circle(from_x, from_y, delta_x, delta_y, radius)
	if edge_x == 0.0 and edge_y == 0.0:
		return first
	var last := _circle(start.x - b.x, start.y - b.y, delta_x, delta_y, radius)
	if not is_finite(first) or not is_finite(last):
		return NAN
	var length := sqrt(edge_x * edge_x + edge_y * edge_y)
	if length == 0.0 or not is_finite(length):
		return NAN
	var ux := edge_x / length
	var uy := edge_y / length
	var along := from_x * ux + from_y * uy
	var lateral := from_y * ux - from_x * uy
	if along >= 0.0 and along <= length and absf(lateral) <= radius:
		return 0.0
	var side := MISS
	var lateral_speed := delta_y * ux - delta_x * uy
	if absf(lateral) > radius and lateral * lateral_speed < 0.0:
		var time := (signf(lateral) * radius - lateral) / lateral_speed
		var contact_along := along + (delta_x * ux + delta_y * uy) * time
		if time <= 1.0 and contact_along >= 0.0 and contact_along <= length:
			side = time
	return _earliest(_earliest(first, last), side)


static func _circle(x: float, y: float, dx: float, dy: float, radius: float) -> float:
	var radius_squared := radius * radius
	var separation := x * x + y * y - radius_squared
	if not is_finite(separation):
		return NAN
	if separation <= 0.0:
		return 0.0
	var speed := sqrt(dx * dx + dy * dy)
	if not is_finite(speed):
		return NAN
	if speed == 0.0:
		return MISS
	var ux := dx / speed
	var uy := dy / speed
	var projected := x * ux + y * uy
	if projected >= 0.0:
		return MISS
	var perpendicular := x * uy - y * ux
	var clearance := radius_squared - perpendicular * perpendicular
	if clearance < 0.0:
		return MISS
	# The other quadratic root permits division instead of subtracting near-equal terms.
	var time := (separation / (-projected + sqrt(clearance))) / speed
	return time if time <= 1.0 else MISS


static func _earliest(left: float, right: float) -> float:
	if left < 0.0:
		return right
	return minf(left, right) if right >= 0.0 else left


static func _point_valid(point: Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)


static func _radius_valid(radius: float) -> bool:
	return is_finite(radius) and radius >= 0.0
