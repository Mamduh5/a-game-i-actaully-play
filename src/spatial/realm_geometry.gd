class_name RealmGeometry
extends RefCounted
## Realm-local canonical geometry for circle and segment occurrences.
## Sweep results retain candidate times for the authoritative time comparator.

class Shape:
	var center: RealmSweep.Point
	var radius: float
	var edge: RealmOutline.Edge
	var category: int
	var fixed: bool

class Contact:
	var entity: StringName
	var shape: int
	var time: float

class SweepCandidates:
	var revision: int
	var contacts: Array[Contact] = []

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
	_revision += 1
	return true


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
		if shape.edge == null:
			time = RealmSweep.moving_circles(start, finish, radius, shape.center, shape.center, shape.radius)
		else:
			time = RealmSweep.circle_segment(start, finish, radius, shape.edge.first, shape.edge.last)
		if not is_finite(time):
			return null
		if time == RealmSweep.MISS:
			continue
		var contact := Contact.new()
		contact.entity = proxy.entity
		contact.shape = proxy.shape
		contact.time = time
		result.contacts.append(contact)
	return result
