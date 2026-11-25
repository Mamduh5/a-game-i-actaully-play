class_name PlayerControlState
extends RefCounted
## Voluntary movement and aim are independent. A fixed-step owner applies admitted commands.

const REFERENCE_SPEED := 100.0

var _axis := RealmSweep.Point.new(0.0, 0.0)
var _destination: RealmSweep.Point
var _aim: RealmSweep.Point


func apply(command: PlayerCommand) -> void:
	if command == null or not command.valid():
		return
	match command.action:
		PlayerCommand.MOVE_AXES:
			_axis = RealmSweep.Point.new(command.x, command.y)
			_destination = null
		PlayerCommand.MOVE_TO:
			_axis = RealmSweep.Point.new(0.0, 0.0)
			_destination = RealmSweep.Point.new(command.x, command.y)
		PlayerCommand.AIM:
			_aim = RealmSweep.Point.new(command.x, command.y)


func aim_from(origin: RealmSweep.Point, prior: RealmSweep.Point) -> RealmSweep.Point:
	if _aim == null:
		return copy_point(prior)
	return direction(origin, _aim, prior)


func step(geometry: RealmGeometry, actor: StringName, slot: int, blockers: int,
		speed: float, seconds: float) -> RealmSweep.Point:
	var start := geometry.circle_center(actor, slot)
	if start == null or speed < 0.0 or seconds < 0.0:
		return null
	var distance := speed * seconds
	if not is_finite(distance):
		return null
	var requested := _requested_pose(start, distance)
	if requested == null:
		return null
	if requested.x == start.x and requested.y == start.y:
		return start
	var movement := geometry.displace_circle(actor, slot, requested, blockers)
	return movement.finish if movement != null else null


func _requested_pose(start: RealmSweep.Point, distance: float) -> RealmSweep.Point:
	var dx := _axis.x
	var dy := _axis.y
	if _destination != null:
		dx = _destination.x - start.x
		dy = _destination.y - start.y
	var largest := maxf(absf(dx), absf(dy))
	if largest == 0.0 or distance == 0.0:
		return start
	if not is_finite(largest):
		return null
	var ux := dx / largest
	var uy := dy / largest
	var norm := sqrt(ux * ux + uy * uy)
	if _destination != null and largest <= distance / norm:
		return copy_point(_destination)
	# Keyboard magnitudes are one on each admitted axis. Under both input
	# styles, travel by at most the same distance at diagonals and cardinals.
	return RealmSweep.Point.new(start.x + ux / norm * distance, start.y + uy / norm * distance)


static func direction(start: RealmSweep.Point, finish: RealmSweep.Point,
		fallback: RealmSweep.Point) -> RealmSweep.Point:
	var dx := finish.x - start.x
	var dy := finish.y - start.y
	var largest := maxf(absf(dx), absf(dy))
	if largest == 0.0 or not is_finite(largest):
		return copy_point(fallback)
	dx /= largest
	dy /= largest
	var norm := sqrt(dx * dx + dy * dy)
	return RealmSweep.Point.new(dx / norm, dy / norm)


static func copy_point(point: RealmSweep.Point) -> RealmSweep.Point:
	return RealmSweep.Point.new(point.x, point.y)
