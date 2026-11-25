class_name RealmGeometry
extends RefCounted
## Realm-local canonical geometry for circle and segment occurrences.
## Sweep results retain candidate times for the authoritative time comparator.

class Shape:
	var center: RealmSweep.Point
	var motion_end: RealmSweep.Point
	var radius: float
	var edge: RealmOutline.Edge
	var category: int
	var fixed: bool

class Contact:
	var entity: StringName
	var shape: int
	var time: float
	var proof: RealmCircleTime.Contact

class SweepCandidates:
	var revision: int
	var contacts: Array[Contact] = []
	var unresolved: Array[Contact] = []

class Displacement:
	var start: RealmSweep.Point
	var finish: RealmSweep.Point
	var revision: int
	var stopped_by: Array[Contact] = []

var realm_id: StringName:
	get: return _index.realm_id
var revision: int:
	get: return _revision

var _index: RealmSpatialIndex
var _shapes: Dictionary[StringName, Shape] = {}
var _revision := 0


func _init(id: StringName) -> void:
	_index = RealmSpatialIndex.new(id)


func add_circle(entity: StringName, slot: int, center: RealmSweep.Point, radius: float,
		category: int) -> bool:
	if center == null or category <= 0:
		return false
	var bounds := RealmBounds.from_sweep(center.x, center.y, center.x, center.y, radius)
	if not _index.register(entity, slot, bounds):
		return false
	var shape := Shape.new()
	shape.center = RealmSweep.Point.new(center.x, center.y)
	shape.radius = radius
	shape.category = category
	_shapes[RealmSpatialIndex.shape_key(entity, slot)] = shape
	_revision += 1
	return true


func add_segment(entity: StringName, slot: int, edge: RealmOutline.Edge, category: int,
		fixed: bool) -> bool:
	if edge == null or edge.first == null or edge.last == null or category <= 0:
		return false
	var bounds := RealmBounds.from_sweep(edge.first.x, edge.first.y, edge.last.x, edge.last.y, 0.0)
	if not _index.register(entity, slot, bounds):
		return false
	var shape := Shape.new()
	shape.edge = RealmOutline.Edge.new()
	shape.edge.first = RealmSweep.Point.new(edge.first.x, edge.first.y)
	shape.edge.last = RealmSweep.Point.new(edge.last.x, edge.last.y)
	shape.edge.bounds = bounds
	shape.category = category
	shape.fixed = fixed
	_shapes[RealmSpatialIndex.shape_key(entity, slot)] = shape
	_revision += 1
	return true


## Apply a resolved pose. A later query in the same group sees this revision.
func commit_circle_pose(entity: StringName, slot: int, center: RealmSweep.Point) -> bool:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or shape.center == null or center == null:
		return false
	var bounds := RealmBounds.from_sweep(center.x, center.y, center.x, center.y, shape.radius)
	if not _index.move(entity, slot, bounds):
		return false
	shape.center = RealmSweep.Point.new(center.x, center.y)
	shape.motion_end = null
	_revision += 1
	return true


## Index a resolved interval trajectory without advancing its canonical start pose.
## A synchronous displacement may replace that trajectory through commit_circle_pose.
func stage_circle_motion(entity: StringName, slot: int, finish: RealmSweep.Point) -> bool:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or shape.center == null or finish == null:
		return false
	var bounds := RealmBounds.from_sweep(shape.center.x, shape.center.y, finish.x, finish.y, shape.radius)
	if not _index.move(entity, slot, bounds):
		return false
	shape.motion_end = RealmSweep.Point.new(finish.x, finish.y)
	_revision += 1
	return true


func commit_circle_motion(entity: StringName, slot: int) -> bool:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	return shape != null and shape.motion_end != null and commit_circle_pose(entity, slot, shape.motion_end)


func remove_mutable(entity: StringName, slot: int) -> bool:
	var key := RealmSpatialIndex.shape_key(entity, slot)
	var shape: Shape = _shapes.get(key)
	if shape == null or shape.fixed or not _index.remove(entity, slot):
		return false
	_shapes.erase(key)
	_revision += 1
	return true


func circle_center(entity: StringName, slot: int) -> RealmSweep.Point:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or shape.center == null:
		return null
	return RealmSweep.Point.new(shape.center.x, shape.center.y)


func sweep_circle(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	return _sweep(realm, start, finish, radius, compatible, except_entity, null, false)


## Report each contact proof and every unresolved relevant shape. Consumers
## must refine unresolved candidates before committing a consequential result.
func certify_circle_sweep(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	return _sweep(realm, start, finish, radius, compatible, except_entity, RealmCircleTime.new(), false)


## Commit forced motion against the current geometry revision. A null draft
## leaves every pose unchanged. Positive-time blockers retain their proofs.
func displace_circle(entity: StringName, slot: int, requested: RealmSweep.Point, blockers: int) -> Displacement:
	var mover: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if mover == null or mover.center == null or requested == null:
		return null
	var start := mover.center
	var certifier := RealmCircleTime.new()
	var path := _sweep(realm_id, start, requested, mover.radius, blockers, entity, certifier, true)
	if path == null or not path.unresolved.is_empty():
		return null
	var result := Displacement.new()
	result.start = RealmSweep.Point.new(start.x, start.y)
	result.finish = RealmSweep.Point.new(requested.x, requested.y)
	if not path.contacts.is_empty():
		var first := _first_blocker(path.contacts)
		if first == null:
			return null
		for contact: Contact in path.contacts:
			if first.proof.order_against(contact.proof) == RealmCircleTime.Order.SAME or first == contact:
				result.stopped_by.append(contact)
		result.stopped_by.sort_custom(_compare_shape_ids)
		result.finish = _verify_clipped_pose(start, requested, first.proof.earliest, mover.radius,
			blockers, entity, certifier)
		if result.finish == null:
			return null
	if start.x != result.finish.x or start.y != result.finish.y:
		if not commit_circle_pose(entity, slot, result.finish):
			return null
	result.revision = revision
	return result


static func _compare_shape_ids(left: Contact, right: Contact) -> bool:
	if left.entity == right.entity:
		return left.shape < right.shape
	return String(left.entity) < String(right.entity)


static func _first_blocker(contacts: Array[Contact]) -> Contact:
	var first := contacts[0]
	for contact: Contact in contacts:
		if contact.proof.earliest < first.proof.earliest:
			first = contact
	for contact: Contact in contacts:
		if first != contact and first.proof.order_against(contact.proof) == RealmCircleTime.Order.AFTER:
			first = contact
	for contact: Contact in contacts:
		if first == contact:
			continue
		var order := first.proof.order_against(contact.proof)
		if order != RealmCircleTime.Order.BEFORE and order != RealmCircleTime.Order.SAME:
			return null
	return first


func _verify_clipped_pose(start: RealmSweep.Point, requested: RealmSweep.Point, time: float, radius: float,
		blockers: int, entity: StringName, certifier: RealmCircleTime) -> RealmSweep.Point:
	if time <= 0.0:
		return RealmSweep.Point.new(start.x, start.y)
	var scratch := PackedByteArray()
	scratch.resize(8)
	var limit := RealmBounds.adjacent(time, false, scratch)
	var point := RealmSweep.Point.new(lerpf(start.x, requested.x, limit), lerpf(start.y, requested.y, limit))
	# Interpolation at a far coordinate can round back onto the blocker.
	# Recheck the actual representable path before committing it.
	for _attempt: int in 4:
		if point.x == start.x and point.y == start.y:
			return point
		var prefix := _sweep(realm_id, start, point, radius, blockers, entity, certifier, true)
		if prefix != null and prefix.contacts.is_empty() and prefix.unresolved.is_empty():
			return point
		if point.x != start.x:
			point.x = RealmBounds.adjacent(point.x, point.x < start.x, scratch)
		if point.y != start.y:
			point.y = RealmBounds.adjacent(point.y, point.y < start.y, scratch)
	return null


func _sweep(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName, certifier: RealmCircleTime, frozen_blockers: bool) -> SweepCandidates:
	if realm != realm_id or start == null or finish == null or compatible <= 0:
		return null
	var broad := _index.query(RealmBounds.from_sweep(start.x, start.y, finish.x, finish.y, radius))
	if broad == null:
		return null
	var result := SweepCandidates.new()
	result.revision = _revision
	for proxy: RealmSpatialIndex.Proxy in broad.proxies:
		var shape: Shape = _shapes[RealmSpatialIndex.shape_key(proxy.entity, proxy.shape)]
		if proxy.entity == except_entity or (shape.category & compatible) == 0:
			continue
		var time: float
		var proof: RealmCircleTime.Contact
		if shape.edge == null:
			var target_end := shape.center if frozen_blockers or shape.motion_end == null else shape.motion_end
			if certifier != null:
				proof = certifier.measure(start, finish, radius, shape.center, target_end, shape.radius)
			else:
				time = RealmSweep.moving_circles(start, finish, radius, shape.center, target_end, shape.radius)
		elif certifier != null:
			proof = certifier.measure_segment(start, finish, radius, shape.edge.first, shape.edge.last)
		else:
			time = RealmSweep.circle_segment(start, finish, radius, shape.edge.first, shape.edge.last)
		if proof != null:
			time = RealmSweep.MISS if proof.outcome == RealmCircleTime.Result.MISS else proof.earliest
			if frozen_blockers and proof.outcome == RealmCircleTime.Result.HIT and proof.latest == 0.0:
				var departs := certifier.departs_circle(start, finish, shape.center) if shape.edge == null else (
					certifier.departs_segment(start, finish, shape.edge.first, shape.edge.last))
				if departs:
					continue
		if not is_finite(time):
			return null
		if time == RealmSweep.MISS:
			continue
		var contact := Contact.new()
		contact.entity = proxy.entity
		contact.shape = proxy.shape
		contact.time = time
		contact.proof = proof
		if proof != null and proof.outcome == RealmCircleTime.Result.UNRESOLVED:
			result.unresolved.append(contact)
		else:
			result.contacts.append(contact)
	return result
