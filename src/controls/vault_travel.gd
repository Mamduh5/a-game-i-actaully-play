class_name VaultTravel
extends RefCounted
## A committed translation advances on the authority's fixed clock. A leap
## crosses a low obstacle only when it can settle beyond it on the same path.

var _actor: StringName
var _start: RealmSweep.Point
var _destination: RealmSweep.Point
var _last_pose: RealmSweep.Point
var _steps: int
var _sample: int


static func plan(floor: RealmGeometry, actor: StringName, pointer: RealmSweep.Point,
		distance: float, steps: int) -> VaultTravel:
	if floor == null:
		return null
	var start := floor.circle_center(actor, 0)
	if start == null or pointer == null or distance <= 0.0 or not is_finite(distance) or steps < 1:
		return null
	var heading := PlayerControlState.direction(start, pointer, RealmSweep.Point.new(0, 0))
	if heading.x == 0.0 and heading.y == 0.0:
		return null
	var requested := RealmSweep.Point.new(start.x + heading.x * distance, start.y + heading.y * distance)
	var draft := floor.fork()
	var swept := draft.displace_body(actor, 0, requested, WorldExploration.SEALED_BLOCKER)
	if swept == null or _same(swept.finish, start) or not _clear_to_land(draft, actor):
		return null
	var travel := VaultTravel.new()
	travel._actor = actor
	travel._start = start
	travel._destination = swept.finish
	travel._last_pose = start
	travel._steps = steps
	return travel


func airborne() -> bool:
	return _sample < _steps


func advance(floor: RealmGeometry) -> bool:
	if floor == null or not airborne():
		return false
	var at := floor.circle_center(_actor, 0)
	if at == null:
		return false
	if not _same(at, _last_pose):
		# A certified forced relocation replaces the committed voluntary path.
		_sample = _steps
		return true
	var draft := floor.fork()
	for index: int in range(_sample + 1, _steps + 1):
		var portion := float(index) / float(_steps)
		var goal := _destination if index == _steps else RealmSweep.Point.new(
			lerpf(_start.x, _destination.x, portion), lerpf(_start.y, _destination.y, portion))
		var swept := draft.displace_body(_actor, 0, goal, WorldExploration.SEALED_BLOCKER)
		if swept == null:
			return false
		var clipped := not _same(swept.finish, goal)
		if _clear_to_land(draft, _actor):
			floor.adopt(draft)
			_last_pose = swept.finish
			_sample = _steps if clipped else index
			return true
		if clipped:
			break
	# A newly obstructed crossing leaves the last clear pose available.
	_sample = _steps
	return true


static func _clear_to_land(floor: RealmGeometry, actor: StringName) -> bool:
	for slot: int in floor.circle_slots(actor):
		var at := floor.circle_center(actor, slot)
		var proof := floor.certify_circle_snapshot(floor.realm_id, at,
			floor.circle_radius(actor, slot), WorldExploration.BLOCKER, actor)
		if proof == null or not proof.contacts.is_empty() or not proof.unresolved.is_empty():
			return false
	return true


static func _same(left: RealmSweep.Point, right: RealmSweep.Point) -> bool:
	return left.x == right.x and left.y == right.y
