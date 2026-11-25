class_name WorldExploration
extends RefCounted
## Shared fog and mutable module state within one realm.

const EXPLORATION_CELL := 32
const BLOCKER := 1
const STARTER_RADIUS := 14.0

var _layout: WorldTopology
var _geometry: RealmGeometry
var _seats: Array[StringName]
var _explored: Dictionary[Vector2i, bool] = {}
var _present: Dictionary[StringName, Vector2i] = {}
var _shortcut_open := false


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


func route(origin: StringName, destination: StringName) -> Array[StringName]:
	return _layout.route(origin, destination, _shortcut_open)


## The module interaction rule owns eligibility. Commit the local obstruction
## and persistent flag together so the next world query sees them both.
func open_shortcut() -> bool:
	if _shortcut_open or not _geometry.remove_mutable(WorldTopology.SHORTCUT_DOOR, 0):
		return false
	_shortcut_open = true
	return true


func checkpoint() -> Dictionary:
	return {"layout": _layout.manifest(), "explored": _explored_cells(), "shortcut_open": _shortcut_open}


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
	return reopened


func _contains(cell: Vector2i) -> bool:
	const MODULE_CELLS := float(WorldTopology.MODULE_SIZE) / EXPLORATION_CELL
	return _layout.contains_cell(Vector2i(floori(cell.x / MODULE_CELLS), floori(cell.y / MODULE_CELLS)))


func _explored_cells() -> Array[Vector2i]:
	var result := _explored.keys()
	result.sort()
	return result
