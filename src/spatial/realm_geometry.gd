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
	var category: int
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
var _circle_slots: Dictionary[StringName, Array] = {}
var _revision := 0
var _category_revisions: Dictionary[int, int] = {}


func _init(id: StringName) -> void:
	_index = RealmSpatialIndex.new(id)


## Build an isolated working image for a transaction spanning several waves.
func fork() -> RealmGeometry:
	var draft := RealmGeometry.new(realm_id)
	draft._index = _index.fork()
	draft._revision = _revision
	draft._category_revisions = _category_revisions.duplicate()
	draft._circle_slots = _circle_slots.duplicate(true)
	for key: StringName in _shapes:
		var original := _shapes[key]
		var shape := Shape.new()
		shape.center = original.center
		shape.motion_end = original.motion_end
		shape.radius = original.radius
		shape.edge = original.edge
		shape.category = original.category
		shape.fixed = original.fixed
		draft._shapes[key] = shape
	return draft


## The owner transfers the draft after checking all participating revisions.
func adopt(draft: RealmGeometry) -> void:
	_index = draft._index
	_shapes = draft._shapes
	_circle_slots = draft._circle_slots
	_revision = draft._revision
	_category_revisions = draft._category_revisions


func compatible_revision(mask: int) -> int:
	var last := 0
	for category: int in _category_revisions:
		if category & mask:
			last = maxi(last, _category_revisions[category])
	return last


func _mark_changed(category: int) -> void:
	_revision += 1
	_category_revisions[category] = _revision


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
	var slots: Array = _circle_slots.get_or_add(entity, [])
	slots.append(slot)
	_shapes[RealmSpatialIndex.shape_key(entity, slot)] = shape
	_mark_changed(category)
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
	_mark_changed(category)
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
	_mark_changed(shape.category)
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
	_mark_changed(shape.category)
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
	if shape.center != null:
		_circle_slots[entity].erase(slot)
		if _circle_slots[entity].is_empty():
			_circle_slots.erase(entity)
	_mark_changed(shape.category)
	return true


func circle_center(entity: StringName, slot: int) -> RealmSweep.Point:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or shape.center == null:
		return null
	return RealmSweep.Point.new(shape.center.x, shape.center.y)


func circle_slots(entity: StringName) -> Array[int]:
	var slots: Array[int] = []
	slots.assign(_circle_slots.get(entity, []))
	slots.sort()
	return slots


func circle_radius(entity: StringName, slot: int) -> float:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	return shape.radius if shape != null and shape.center != null else -1.0


func circle_category(entity: StringName, slot: int) -> int:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	return shape.category if shape != null and shape.center != null else 0


func change_category(entity: StringName, slot: int, category: int) -> bool:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or shape.fixed or category <= 0:
		return false
	if shape.category != category:
		var previous := shape.category
		shape.category = category
		_mark_changed(previous | category)
	return true


## Vector from the given mover center toward the blocker at contact. The
## receiver normalizes it after ruling out a degenerate overlap.
func blocker_direction(entity: StringName, slot: int, mover: RealmSweep.Point) -> RealmSweep.Point:
	var shape: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if shape == null or mover == null:
		return null
	if shape.edge == null:
		return RealmSweep.Point.new(shape.center.x - mover.x, shape.center.y - mover.y)
	var first := shape.edge.first
	var last := shape.edge.last
	var dx := last.x - first.x
	var dy := last.y - first.y
	var norm := dx * dx + dy * dy
	var nearest := 0.0
	if norm > 0.0:
		nearest = clampf(((mover.x - first.x) * dx + (mover.y - first.y) * dy) / norm, 0.0, 1.0)
	return RealmSweep.Point.new(first.x + dx * nearest - mover.x, first.y + dy * nearest - mover.y)


func sweep_circle(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	return _sweep(realm, start, finish, radius, compatible, except_entity, null, false)


## Report each contact proof and every unresolved relevant shape. Consumers
## must refine unresolved candidates before committing a consequential result.
func certify_circle_sweep(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	return _sweep(realm, start, finish, radius, compatible, except_entity, RealmCircleTime.new(), false)


## A stationary area pulse samples settled positions at its due instant.
func certify_circle_snapshot(realm: StringName, center: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	return certify_frozen_path(realm, center, center, radius, compatible, except_entity)


## An instantaneous area at a certified time inside the staged movement
## interval. The index includes every staged path's complete swept bounds.
func certify_disk_at(realm: StringName, center: RealmSweep.Point, radius: float,
		instant: RealmCircleTime.Contact, compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	if realm != realm_id or center == null or instant == null or instant.outcome != RealmCircleTime.Result.HIT or compatible <= 0:
		return null
	var broad := _index.query(RealmBounds.from_sweep(center.x, center.y, center.x, center.y, radius))
	if broad == null:
		return null
	var result := SweepCandidates.new()
	result.revision = revision
	var certifier := RealmCircleTime.new()
	for proxy: RealmSpatialIndex.Proxy in broad.proxies:
		var shape := _shapes[RealmSpatialIndex.shape_key(proxy.entity, proxy.shape)]
		if proxy.entity == except_entity or (shape.category & compatible) == 0:
			continue
		var outcome: RealmCircleTime.Result
		if shape.edge != null:
			outcome = certifier.measure_segment(center, center, radius, shape.edge.first, shape.edge.last).outcome
		else:
			var finish := shape.motion_end if shape.motion_end != null else shape.center
			outcome = instant.disk_overlap(center, radius, shape.center, finish, shape.radius)
		if outcome == RealmCircleTime.Result.MISS:
			continue
		var contact := Contact.new()
		contact.entity = proxy.entity
		contact.shape = proxy.shape
		contact.category = shape.category
		contact.proof = instant.copy()
		contact.time = instant.earliest
		if outcome == RealmCircleTime.Result.HIT:
			result.contacts.append(contact)
		else:
			result.unresolved.append(contact)
	result.contacts.sort_custom(_compare_shape_ids)
	return result


## Enumerate settled contacts in stable entity and shape order. Each proof
## retains its path time for callers that compare moving impacts.
func certify_frozen_path(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName = &"") -> SweepCandidates:
	var result := _sweep(realm, start, finish, radius, compatible, except_entity, RealmCircleTime.new(), true)
	if result != null and result.contacts.size() > 1:
		result.contacts.sort_custom(_compare_shape_ids)
	return result


## Use the same blocker motion as the certified delivery, restricted to the
## tested prefix so rounding is checked at the correct elapsed time.
func clipped_sweep_finish(start: RealmSweep.Point, requested: RealmSweep.Point, contact: Contact,
		radius: float, blockers: int, except_entity: StringName) -> RealmSweep.Point:
	return _verify_clipped_pose(start, requested, contact.proof.earliest, radius, blockers,
		except_entity, RealmCircleTime.new(), false)


## Commit forced motion against the current geometry revision. A null draft
## leaves every pose unchanged. Positive-time blockers retain their proofs.
func displace_circle(entity: StringName, slot: int, requested: RealmSweep.Point, blockers: int) -> Displacement:
	var mover: Shape = _shapes.get(RealmSpatialIndex.shape_key(entity, slot))
	if mover == null or mover.center == null or requested == null:
		return null
	var start := mover.center
	var certifier := RealmCircleTime.new()
	var path := _sweep(realm_id, start, requested, mover.radius, blockers, entity, certifier, true, true)
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


## Force translates a body's circles together. The earliest obstacle for any
## member limits the entire move, including when it misses the contacted slot.
func displace_body(entity: StringName, slot: int, requested: RealmSweep.Point, blockers: int) -> Displacement:
	var slots: Array = _circle_slots.get(entity, [])
	if slots.size() <= 1:
		return displace_circle(entity, slot, requested, blockers)
	var start := circle_center(entity, slot)
	if start == null or requested == null:
		return null
	var dx := requested.x - start.x
	var dy := requested.y - start.y
	var contacts: Array[Contact] = []
	var certifier := RealmCircleTime.new()
	for member: int in slots:
		var center := circle_center(entity, member)
		var finish := RealmSweep.Point.new(center.x + dx, center.y + dy)
		var path := _sweep(realm_id, center, finish, circle_radius(entity, member), blockers, entity, certifier, true, true)
		if path == null or not path.unresolved.is_empty():
			return null
		contacts.append_array(path.contacts)
	var result := Displacement.new()
	result.start = start
	result.finish = start
	var limit := 1.0
	var retreat := 0.0
	if not contacts.is_empty():
		var first := _first_blocker(contacts)
		if first == null:
			return null
		var recorded: Dictionary[StringName, bool] = {}
		for contact: Contact in contacts:
			var key := RealmSpatialIndex.shape_key(contact.entity, contact.shape)
			if not recorded.has(key) and (first == contact or first.proof.order_against(contact.proof) == RealmCircleTime.Order.SAME):
				recorded[key] = true
				result.stopped_by.append(contact)
		result.stopped_by.sort_custom(_compare_shape_ids)
		limit = first.proof.earliest
		var scratch := PackedByteArray()
		scratch.resize(8)
		retreat = limit - RealmBounds.adjacent(limit, false, scratch)
	for attempt: int in 55:
		var fraction := maxf(0.0, limit - retreat)
		var draft := fork()
		var clear := true
		for member: int in slots:
			var center := circle_center(entity, member)
			var finish := RealmSweep.Point.new(center.x + dx * fraction, center.y + dy * fraction)
			if finish.x == center.x and finish.y == center.y:
				continue
			var prefix := _sweep(realm_id, center, finish, circle_radius(entity, member), blockers, entity, certifier, true, true)
			if prefix == null or not prefix.unresolved.is_empty() or not prefix.contacts.is_empty():
				clear = false
				break
			if not draft.commit_circle_pose(entity, member, finish):
				return null
		if clear:
			adopt(draft)
			result.finish = circle_center(entity, slot)
			result.revision = revision
			return result
		retreat *= 2.0
	return null


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
		blockers: int, entity: StringName, certifier: RealmCircleTime, frozen: bool = true) -> RealmSweep.Point:
	if time <= 0.0:
		return RealmSweep.Point.new(start.x, start.y)
	var scratch := PackedByteArray()
	scratch.resize(8)
	var retreat := time - RealmBounds.adjacent(time, false, scratch)
	# Rounding the two interpolated coordinates can turn a tangent prefix
	# into a hit. Back off in path time and verify the actual stored pose.
	for _attempt: int in 55:
		var limit := maxf(0.0, time - retreat)
		var point := RealmSweep.Point.new(lerpf(start.x, requested.x, limit), lerpf(start.y, requested.y, limit))
		if point.x == start.x and point.y == start.y:
			return point
		var prefix := _sweep(realm_id, start, point, radius, blockers, entity, certifier, frozen, frozen, limit)
		if prefix != null and prefix.contacts.is_empty() and prefix.unresolved.is_empty():
			return point
		retreat *= 2.0
	return null


func _sweep(realm: StringName, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		compatible: int, except_entity: StringName, certifier: RealmCircleTime, frozen_blockers: bool,
		allow_departure: bool = false, motion_fraction: float = 1.0) -> SweepCandidates:
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
			if target_end != shape.center and motion_fraction < 1.0:
				target_end = RealmSweep.Point.new(lerpf(shape.center.x, target_end.x, motion_fraction),
					lerpf(shape.center.y, target_end.y, motion_fraction))
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
			if allow_departure and proof.outcome == RealmCircleTime.Result.HIT and proof.latest == 0.0:
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
		contact.category = shape.category
		contact.time = time
		contact.proof = proof
		if proof != null and proof.outcome == RealmCircleTime.Result.UNRESOLVED:
			result.unresolved.append(contact)
		else:
			result.contacts.append(contact)
	return result
