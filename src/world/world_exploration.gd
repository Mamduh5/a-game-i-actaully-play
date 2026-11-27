class_name WorldExploration
extends RefCounted
## Shared fog and mutable module state within one realm.

const EXPLORATION_CELL := 32
const BLOCKER := 1
const STARTER_RADIUS := 14.0

class SolidMotion:
	var motion: RealmGeometry.Displacement
	var route_limited: bool
	var impacts: Array[SolidImpact] = []

class SolidImpact:
	var contact: RealmGeometry.Contact
	var impact: WorldMomentum.Impact
	var transferred: bool

class SolidDamage:
	var solid: StringName
	var paid: Quantity
	var remaining: Quantity
	var destroyed: bool
	var origin: CombatOrigin
	var neutral_cause: StringName

var _layout: WorldTopology
var _geometry: RealmGeometry
var _seats: Array[StringName]
var _explored: Dictionary[Vector2i, bool] = {}
var _present: Dictionary[StringName, Vector2i] = {}
var _shortcut_open := false
var _routes: WorldRouteGraph
var _enemy_routes: Dictionary[float, WorldRouteGraph] = {}
var _route_solids: Dictionary[StringName, float] = {}
var _durability: Dictionary[StringName, Quantity] = {}


static func create(layout: WorldTopology, seats: Array[StringName]) -> WorldExploration:
	if layout == null or seats.is_empty() or &"" in seats:
		return null
	var result := WorldExploration.new()
	result._layout = layout
	result._seats = seats.duplicate()
	result._geometry = layout.realize(BLOCKER)
	return result if layout.has_clearance(result._geometry, BLOCKER, STARTER_RADIUS) else null


## Pass a committed living seat pose from the fixed-step owner. Other actors
## have no accepted seat and realm changes clear local visibility.
func observe_seat(seat: StringName, realm: StringName, point: RealmSweep.Point) -> bool:
	if seat not in _seats:
		return false
	if realm != _layout.realm or point == null:
		_present.erase(seat)
		return false
	if not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > 1000000 or absf(point.y) > 1000000:
		return false
	var cell := Vector2i(floori(point.x / EXPLORATION_CELL), floori(point.y / EXPLORATION_CELL))
	if not _contains(cell):
		_present.erase(seat)
		return false
	_explored[cell] = true
	_present[seat] = cell
	return true


func view(seat: StringName) -> Dictionary:
	if seat not in _seats:
		return {}
	var visible: Array[Vector2i] = []
	if _present.has(seat):
		visible.append(_present[seat])
	return {"visible": visible, "explored": _explored_cells()}


func geometry() -> RealmGeometry:
	return _geometry


func module_at(point: RealmSweep.Point) -> StringName:
	return _layout.module_at(point)


func module_center(id: StringName) -> RealmSweep.Point:
	return _layout.center(id)


func early_observatory_center() -> RealmSweep.Point:
	return _layout.center(WorldTopology.OBSERVATORY) if _layout.has_early_observatory() else null


func layout_seed() -> int:
	return _layout.seed


func route(origin: StringName, destination: StringName) -> Array[StringName]:
	return _layout.route(origin, destination, _shortcut_open)


func physical_route(origin: StringName, destination: StringName) -> Array[RealmSweep.Point]:
	if not _ensure_routes():
		return []
	return _routes.route(_geometry, origin, destination)


## Enemy footprints need clearance to their actual destination. Larger
## creatures can still use the portion of the map that admits their shape.
func enemy_waypoint(origin: RealmSweep.Point, destination: RealmSweep.Point, radius: float) -> RealmSweep.Point:
	if module_at(origin).is_empty() or module_at(destination).is_empty() or radius <= 0.0 or not is_finite(radius):
		return null
	var direct := _geometry.certify_frozen_path(_layout.realm, origin, destination, radius, BLOCKER)
	if direct != null and direct.contacts.is_empty() and direct.unresolved.is_empty():
		return RealmSweep.Point.new(destination.x, destination.y)
	var navigation: WorldRouteGraph = _enemy_routes.get(radius)
	if navigation == null:
		navigation = WorldRouteGraph.create(_layout, _geometry, BLOCKER, radius, false)
		if navigation == null:
			return null
		_enemy_routes[radius] = navigation
	return navigation.waypoint(_geometry, origin, destination)


## The run reserves reachable occupied or rescue positions by stable ID.
func reserve_route_approach(id: StringName, point: RealmSweep.Point, exclusive: bool = false) -> bool:
	return _ensure_routes() and _routes.reserve_approach(_geometry, id, point, exclusive)


func release_route_approach(id: StringName) -> bool:
	return _routes != null and _routes.release_approach(id)


func can_escape_warning(warning: WorldPressureHazard.Warning, actor: StringName, slot: int,
		travel_budget: float) -> bool:
	return (warning != null and _ensure_routes() and _routes.can_escape(_geometry,
		_geometry.circle_center(actor, slot), warning.center, warning.radius, travel_budget))


## A gameplay placement owns its footprint; ordinary actor shapes do not
## participate unless included in the realm's navigation blocker mask.
func place_route_solid(id: StringName, center: RealmSweep.Point, radius: float, durability: Quantity = null) -> bool:
	if (id.is_empty() or _route_solids.has(id) or center == null or not is_finite(radius) or radius <= 0.0
			or not is_finite(center.x) or not is_finite(center.y)
			or absf(center.x) > 1000000.0 or absf(center.y) > 1000000.0
			or (durability != null and durability.sign_value <= 0) or not _ensure_routes()):
		return false
	var cell := Vector2i(floori(center.x / WorldTopology.MODULE_SIZE), floori(center.y / WorldTopology.MODULE_SIZE))
	if not _layout.contains_cell(cell):
		return false
	var placement := _geometry.certify_circle_snapshot(_layout.realm, center, radius, BLOCKER)
	if placement == null or not placement.contacts.is_empty() or not placement.unresolved.is_empty():
		return false
	var footprint := RealmBounds.from_sweep(center.x, center.y, center.x, center.y, radius)
	var draft := _geometry.fork()
	if not draft.add_circle(id, 0, center, radius, BLOCKER) or not _routes.settle(_geometry, draft, footprint):
		return false
	_route_solids[id] = radius
	if durability != null:
		_durability[id] = durability
	return true


func remove_route_solid(id: StringName) -> bool:
	if not _route_solids.has(id) or not _ensure_routes():
		return false
	var center := _geometry.circle_center(id, 0)
	if center == null:
		return false
	var footprint := RealmBounds.from_sweep(center.x, center.y, center.x, center.y, _route_solids[id])
	var draft := _geometry.fork()
	if not draft.remove_mutable(id, 0) or not _routes.settle(_geometry, draft, footprint):
		return false
	_route_solids.erase(id)
	_durability.erase(id)
	return true


## Apply an authored durability debit. Only a destructive debit changes the
## colliders. Secondary reactions can use the same causal receipt.
func damage_route_solid(id: StringName, damage: Quantity, origin: CombatOrigin, neutral_cause: StringName = &"") -> SolidDamage:
	var current: Quantity = _durability.get(id)
	if (current == null or damage == null or damage.sign_value <= 0
			or (origin == null and neutral_cause.is_empty())
			or (origin != null and (not neutral_cause.is_empty() or not origin.valid_for(origin.committed_at)))):
		return null
	var receipt := SolidDamage.new()
	receipt.solid = id
	receipt.origin = origin.copy() if origin != null else null
	receipt.neutral_cause = neutral_cause
	receipt.destroyed = damage.compare(current) >= 0
	if receipt.destroyed:
		if not remove_route_solid(id):
			return null
		receipt.paid = current
		receipt.remaining = Quantity.from_count(0)
	else:
		receipt.remaining = current.subtract(damage)
		if receipt.remaining == null:
			return null
		_durability[id] = receipt.remaining
		receipt.paid = damage
	return receipt


func move_route_solid(id: StringName, requested: RealmSweep.Point) -> SolidMotion:
	if not _route_solids.has(id) or requested == null or not _ensure_routes():
		return null
	var draft := _geometry.fork()
	var displaced := draft.displace_circle(id, 0, requested, BLOCKER)
	if displaced == null:
		return null
	var radius := _route_solids[id]
	var finish := _routes.limit_motion(_geometry, displaced.start, displaced.finish, radius)
	if finish == null:
		return null
	var result := SolidMotion.new()
	result.motion = displaced
	if finish.x != displaced.finish.x or finish.y != displaced.finish.y:
		if not draft.commit_circle_pose(id, 0, finish):
			return null
		result.route_limited = true
		displaced.finish = finish
		displaced.stopped_by.clear()
	if displaced.start.x != displaced.finish.x or displaced.start.y != displaced.finish.y:
		var footprint := RealmBounds.from_sweep(displaced.start.x, displaced.start.y, finish.x, finish.y, radius)
		if not _routes.settle(_geometry, draft, footprint):
			return null
	displaced.revision = _geometry.revision
	return result


## Advance authored momentum through the normal clearance and physical
## collision path. A positive separation distance defines a new episode.
func push_route_solid(id: StringName, momentum: WorldMomentum, seconds: float,
		minimum_approach: float, separation_distance: float,
		recipients: Dictionary[StringName, WorldMomentum] = {}, restitution: float = 0.0) -> SolidMotion:
	if (not _route_solids.has(id) or momentum == null or not is_finite(seconds) or seconds <= 0.0
			or not is_finite(minimum_approach) or minimum_approach <= 0.0
			or not is_finite(separation_distance) or separation_distance <= 0.0
			or not is_finite(restitution) or restitution < 0.0 or restitution > 1.0):
		return null
	var start := _geometry.circle_center(id, 0)
	var velocity := momentum.velocity()
	if start == null or velocity == null:
		return null
	var probe := _geometry.certify_circle_snapshot(_layout.realm, start,
		_route_solids[id] + separation_distance, BLOCKER, id)
	if probe == null:
		return null
	var requested := RealmSweep.Point.new(start.x + velocity.x * seconds, start.y + velocity.y * seconds)
	var settled := move_route_solid(id, requested)
	if settled == null:
		return null
	momentum.refresh_contacts(probe)
	for hit: RealmGeometry.Contact in settled.motion.stopped_by:
		if hit.proof.latest == 0.0:
			continue
		var at := hit.proof.earliest
		var center := RealmSweep.Point.new(lerpf(start.x, requested.x, at), lerpf(start.y, requested.y, at))
		var normal := _geometry.blocker_direction(hit.entity, hit.shape, center)
		var impulse := momentum.contact(hit.entity, hit.shape, normal, minimum_approach, recipients.get(hit.entity))
		if impulse != null:
			var impact := SolidImpact.new()
			impact.contact = hit
			impact.impact = impulse
			settled.impacts.append(impact)
	if settled.impacts.size() == 1 and settled.motion.stopped_by.size() == 1:
		var impact := settled.impacts[0]
		impact.transferred = momentum.transfer(impact.impact, id, 0, restitution)
	return settled


func _ensure_routes() -> bool:
	if _routes == null:
		_routes = WorldRouteGraph.create(_layout, _geometry, BLOCKER, STARTER_RADIUS)
	return _routes != null


## The module interaction rule owns eligibility. Commit the local obstruction
## and persistent flag together so the next world query sees them both.
func open_shortcut() -> bool:
	if _shortcut_open or not _geometry.remove_mutable(WorldTopology.SHORTCUT_DOOR, 0):
		return false
	_shortcut_open = true
	return true


## Gameplay uses the admitted interact command and the actor's settled pose.
## The caller owns liveness and input authorization.
func interact_shortcut(command: PlayerCommand, realm: StringName, actor: StringName, slot: int, reach: float) -> bool:
	if (_shortcut_open or command == null or not command.valid() or command.action != PlayerCommand.INTERACT
			or realm != _layout.realm or not is_finite(reach) or reach <= 0.0):
		return false
	var ends: Array[StringName] = _layout.manifest()["shortcut"]
	var start := _geometry.circle_center(actor, slot)
	if start == null or ends.size() != 2:
		return false
	var first := _layout.center(ends[0])
	var last := _layout.center(ends[1])
	var handle := RealmSweep.Point.new((first.x + last.x) * 0.5, (first.y + last.y) * 0.5)
	var dx := handle.x - start.x
	var dy := handle.y - start.y
	if dx * dx + dy * dy > reach * reach:
		return false
	var sight := _geometry.certify_frozen_path(realm, start, handle, 0.0, BLOCKER, actor)
	if sight == null or not sight.unresolved.is_empty():
		return false
	for contact: RealmGeometry.Contact in sight.contacts:
		if contact.entity != WorldTopology.SHORTCUT_DOOR:
			return false
	return open_shortcut()


func checkpoint() -> Dictionary:
	var result := {"layout": _layout.manifest(), "explored": _explored_cells(), "shortcut_open": _shortcut_open}
	if not _route_solids.is_empty():
		var ids := _route_solids.keys()
		ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
		var solids: Array[Dictionary] = []
		for id: StringName in ids:
			var center := _geometry.circle_center(id, 0)
			if center == null:
				return {}
			var solid := {"id": id, "x": center.x, "y": center.y, "radius": _route_solids[id]}
			if _durability.has(id):
				solid["durability"] = QuantityCodec.encode(_durability[id])
			solids.append(solid)
		result["solids"] = solids
	return result


static func restore(saved: Dictionary, seats: Array[StringName]) -> WorldExploration:
	if not saved.get("layout") is Dictionary or not saved.get("explored") is Array or not saved.get("shortcut_open") is bool:
		return null
	var layout := WorldTopology.restore(saved["layout"])
	var reopened := create(layout, seats)
	if reopened == null:
		return null
	for cell: Variant in saved["explored"]:
		if not cell is Vector2i or reopened._explored.has(cell) or not reopened._contains(cell):
			return null
		reopened._explored[cell] = true
	if saved["shortcut_open"] and not reopened.open_shortcut():
		return null
	var solids: Variant = saved.get("solids", [])
	if not solids is Array:
		return null
	for solid: Variant in solids:
		if (not solid is Dictionary or not solid.get("id") is StringName or not solid.get("x") is float
				or not solid.get("y") is float or not solid.get("radius") is float):
			return null
		var center := RealmSweep.Point.new(solid["x"], solid["y"])
		var durability: Quantity
		if solid.has("durability"):
			if not solid["durability"] is PackedByteArray:
				return null
			durability = QuantityCodec.decode(solid["durability"])
			if durability == null:
				return null
		if not reopened.place_route_solid(solid["id"], center, solid["radius"], durability):
			return null
	return reopened


func _contains(cell: Vector2i) -> bool:
	const MODULE_CELLS := float(WorldTopology.MODULE_SIZE) / EXPLORATION_CELL
	return _layout.contains_cell(Vector2i(floori(cell.x / MODULE_CELLS), floori(cell.y / MODULE_CELLS)))


func _explored_cells() -> Array[Vector2i]:
	var result := _explored.keys()
	result.sort()
	return result
