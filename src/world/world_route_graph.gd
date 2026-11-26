class_name WorldRouteGraph
extends RefCounted
## Realm-local waypoints certified against the authoritative blocker revision.

const CELLS_PER_MODULE := 8
const SPACING := float(WorldTopology.MODULE_SIZE) / CELLS_PER_MODULE
const MID := CELLS_PER_MODULE >> 1
const STEP := [Vector2i.RIGHT, Vector2i.DOWN]

class Link:
	var start: Vector2i
	var finish: Vector2i
	var bounds: RealmBounds

class Motion:
	var start: RealmSweep.Point
	var finish: RealmSweep.Point
	var combined_radius: float
	var certifier := RealmCircleTime.new()

	func clears(first: RealmSweep.Point, last: RealmSweep.Point) -> bool:
		var proof := certifier.measure_segment(start, finish, combined_radius, first, last)
		return proof != null and proof.outcome == RealmCircleTime.Result.MISS

var _realm: StringName
var _radius: float
var _mask: int
var _revision := -1
var _centers: Dictionary[StringName, Vector2i] = {}
var _points: Dictionary[Vector2i, RealmSweep.Point] = {}
var _outgoing: Dictionary[Vector2i, Array] = {}
var _links: Array[Link] = []
var _clear: Dictionary[int, bool] = {}
var _critical: Array[StringName] = []
var _approaches: Dictionary[StringName, RealmSweep.Point] = {}


static func create(layout: WorldTopology, geometry: RealmGeometry, mask: int, radius: float) -> WorldRouteGraph:
	if layout == null or geometry == null or geometry.realm_id != layout.realm or mask <= 0 or not is_finite(radius) or radius <= 0:
		return null
	var graph := WorldRouteGraph.new()
	graph._realm = layout.realm
	graph._radius = radius
	graph._mask = mask
	var modules: Array[Dictionary] = layout.manifest()["modules"]
	for module: Dictionary in modules:
		graph._add_module(module["id"], module["cell"])
	for module: Dictionary in modules:
		var id: StringName = module["id"]
		for neighbor: StringName in module["neighbors"]:
			if String(id) < String(neighbor):
				graph._add_seam(id, neighbor)
	if layout.realm == WorldTopology.OVERWORLD:
		graph._critical.assign(WorldTopology.ANCHORS)
		graph._critical.append(WorldTopology.GATEWAY)
	else:
		graph._critical = [WorldTopology.ENTRY, WorldTopology.RETURN_EXIT]
	graph._refresh(geometry)
	return graph if graph._connected(geometry, graph._clear) else null


func route(geometry: RealmGeometry, origin: StringName, destination: StringName) -> Array[RealmSweep.Point]:
	if geometry == null or geometry.realm_id != _realm or not _centers.has(origin) or not _centers.has(destination):
		return []
	if _revision != geometry.revision:
		_refresh(geometry)
	var start := _centers[origin]
	var finish := _centers[destination]
	if start == finish and not _sweep_clear(geometry, _points[start], _points[start]):
		return []
	var previous := _flood(start, _clear, finish)
	if not previous.has(finish):
		return []
	var result: Array[RealmSweep.Point] = []
	var cell := finish
	while cell != start:
		result.append(_point_copy(cell))
		cell = previous[cell]
	result.append(_point_copy(start))
	result.reverse()
	return result


func reserve_approach(geometry: RealmGeometry, id: StringName, point: RealmSweep.Point) -> bool:
	if (geometry == null or geometry.realm_id != _realm or id.is_empty() or point == null
			or not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > 1000000 or absf(point.y) > 1000000):
		return false
	if _revision != geometry.revision:
		_refresh(geometry)
	var reached := _flood(_centers[_critical[0]], _clear)
	if not _approachable(geometry, reached, point):
		return false
	_approaches[id] = RealmSweep.Point.new(point.x, point.y)
	return true


func release_approach(id: StringName) -> bool:
	return _approaches.erase(id)


## Keep a certified route throughout the swept motion. The swept footprint
## grows monotonically with the prefix, so refinement can only shorten it.
func limit_motion(geometry: RealmGeometry, start: RealmSweep.Point, finish: RealmSweep.Point, radius: float) -> RealmSweep.Point:
	if _revision != geometry.revision:
		_refresh(geometry)
	var full := RealmBounds.from_sweep(start.x, start.y, finish.x, finish.y, radius)
	if full == null:
		return null
	var changed: Array[int] = []
	for index: int in _links.size():
		if _clear[index] and _links[index].bounds.overlaps(full):
			changed.append(index)
	var scratch := PackedByteArray()
	scratch.resize(8)
	var motion := Motion.new()
	motion.start = start
	motion.finish = finish
	motion.combined_radius = RealmBounds.adjacent(radius + _radius, true, scratch)
	if _motion_connected(geometry, motion, changed):
		return finish
	motion.finish = start
	if not _motion_connected(geometry, motion, changed):
		return null
	var last := start
	var lower := 0.0
	var upper := 1.0
	for step: int in 24:
		var fraction := (lower + upper) * 0.5
		motion.finish = RealmSweep.Point.new(lerpf(start.x, finish.x, fraction), lerpf(start.y, finish.y, fraction))
		if _motion_connected(geometry, motion, changed):
			last = motion.finish
			lower = fraction
		else:
			upper = fraction
	return last


func _motion_connected(geometry: RealmGeometry, motion: Motion, changed: Array[int]) -> bool:
	var clear := _clear.duplicate()
	for index: int in changed:
		var link := _links[index]
		if not motion.clears(_points[link.start], _points[link.finish]):
			clear[index] = false
	return _connected(geometry, clear, motion)


## The draft changes one obstacle footprint. Unaffected links retain their
## proofs. Geometry and routes publish together only if the draft passes.
func settle(geometry: RealmGeometry, draft: RealmGeometry, footprint: RealmBounds) -> bool:
	if (geometry == null or draft == null or footprint == null or geometry.realm_id != _realm
			or draft.realm_id != _realm or draft.revision <= geometry.revision):
		return false
	if _revision != geometry.revision:
		_refresh(geometry)
	var clear := _clear.duplicate()
	for index: int in _links.size():
		var link := _links[index]
		if link.bounds.overlaps(footprint):
			clear[index] = _sweep_clear(draft, _points[link.start], _points[link.finish])
	if not _connected(draft, clear):
		return false
	geometry.adopt(draft)
	_clear = clear
	_revision = geometry.revision
	return true


func _add_module(id: StringName, tile: Vector2i) -> void:
	var base := tile * CELLS_PER_MODULE
	_centers[id] = base + Vector2i(MID, MID)
	for y: int in range(1, CELLS_PER_MODULE):
		for x: int in range(1, CELLS_PER_MODULE):
			var cell := base + Vector2i(x, y)
			_points[cell] = RealmSweep.Point.new(cell.x * SPACING, cell.y * SPACING)
			_outgoing[cell] = []
	for y: int in range(1, CELLS_PER_MODULE):
		for x: int in range(1, CELLS_PER_MODULE):
			for direction: Vector2i in STEP:
				var next := Vector2i(x, y) + direction
				if next.x < CELLS_PER_MODULE and next.y < CELLS_PER_MODULE:
					_add_link(base + Vector2i(x, y), base + next)


func _add_seam(first: StringName, second: StringName) -> void:
	var origin := _centers[first]
	var destination := _centers[second]
	var axis := (destination - origin).sign()
	_add_link(origin + axis * (MID - 1), destination - axis * (MID - 1))


func _add_link(start: Vector2i, finish: Vector2i) -> void:
	var link := Link.new()
	link.start = start
	link.finish = finish
	var first := _points[start]
	var last := _points[finish]
	link.bounds = RealmBounds.from_sweep(first.x, first.y, last.x, last.y, _radius)
	_outgoing[start].append(_links.size())
	_outgoing[finish].append(_links.size())
	_links.append(link)


func _refresh(geometry: RealmGeometry) -> void:
	for index: int in _links.size():
		var link := _links[index]
		_clear[index] = _sweep_clear(geometry, _points[link.start], _points[link.finish])
	_revision = geometry.revision


func _sweep_clear(geometry: RealmGeometry, start: RealmSweep.Point, finish: RealmSweep.Point) -> bool:
	var proof := geometry.certify_circle_sweep(_realm, start, finish, _radius, _mask)
	return proof != null and proof.unresolved.is_empty() and proof.contacts.is_empty()


func _connected(geometry: RealmGeometry, clear: Dictionary[int, bool], motion: Motion = null) -> bool:
	var visited := _flood(_centers[_critical[0]], clear)
	for id: StringName in _critical:
		if not visited.has(_centers[id]):
			return false
	for point: RealmSweep.Point in _approaches.values():
		if not _approachable(geometry, visited, point, motion):
			return false
	return true


func _approachable(geometry: RealmGeometry, reached: Dictionary[Vector2i, Vector2i],
		point: RealmSweep.Point, motion: Motion = null) -> bool:
	var tile := Vector2i(floori(point.x / WorldTopology.MODULE_SIZE), floori(point.y / WorldTopology.MODULE_SIZE))
	var base := tile * CELLS_PER_MODULE
	for y: int in range(1, CELLS_PER_MODULE):
		for x: int in range(1, CELLS_PER_MODULE):
			var cell := base + Vector2i(x, y)
			if (reached.has(cell) and (motion == null or motion.clears(_points[cell], point))
					and _sweep_clear(geometry, _points[cell], point)):
				return true
	return false


func _flood(start: Vector2i, clear: Dictionary[int, bool], finish: Vector2i = Vector2i(0, 0)) -> Dictionary[Vector2i, Vector2i]:
	var previous: Dictionary[Vector2i, Vector2i] = {start: start}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size() and not previous.has(finish):
		var current := queue[index]
		index += 1
		for candidate: int in _outgoing[current]:
			if not clear[candidate]:
				continue
			var link := _links[candidate]
			var next := link.finish if link.start == current else link.start
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	return previous


func _point_copy(cell: Vector2i) -> RealmSweep.Point:
	var point := _points[cell]
	return RealmSweep.Point.new(point.x, point.y)
