class_name WorldTopology
extends RefCounted
## Revisioned realm topology and its realized module seams.

const REVISION := 1
const OVERWORLD := &"overworld"
const OPTIONAL_REALMS := [&"inverted_archive", &"silent_garden", &"fractured_beyond", &"hall_of_echoes"]
const GATEWAY := &"final_gateway"
const ENTRY := &"entry"
const RETURN_EXIT := &"return_exit"
const SHORTCUT_DOOR := &"central_shortcut_door"
const MODULE_SIZE := 256
const SEAM_HALF_WIDTH := 44
const REGIONS := [&"primeval_wilds", &"runic_expanse", &"forgotten_lands"]
const ANCHORS := [&"ancient_worldtree", &"ancient_foundry", &"fallen_citadel"]
const OPTIONAL := [
	[&"beasts_den", &"overgrown_sanctuary", &"whispering_falls"],
	[&"runic_archive", &"silent_observatory", &"sealed_vault"],
	[&"endless_catacombs", &"abandoned_village", &"veiled_shrine"],
]
const RING := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(2, 1), Vector2i(1, 1), Vector2i(0, 1)]
const CARDINAL := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

class Module:
	var id: StringName
	var cell: Vector2i
	var regions: Array[StringName] = []
	var landmark: StringName
	var neighbors: Array[StringName] = []

var seed: int:
	get: return _seed
var realm: StringName:
	get: return _realm
var _seed: int
var _realm := OVERWORLD
var _modules: Dictionary[StringName, Module] = {}
var _cells: Dictionary[Vector2i, StringName] = {}
var _shortcut: Array[StringName] = []


static func generate(run_seed: int) -> WorldTopology:
	var layout := WorldTopology.new()
	layout._seed = run_seed
	var rng := RunRandom.new(run_seed)
	var region_order: Array[int] = [0, 1, 2]
	for index: int in range(region_order.size() - 1, 0, -1):
		var swap_index := rng.draw(&"topology_v1_regions") % (index + 1)
		var prior := region_order[index]
		region_order[index] = region_order[swap_index]
		region_order[swap_index] = prior
	var ring: Array[Module] = []
	for index: int in region_order.size():
		var region := region_order[index]
		var adjacent := region_order[(index + 1) % region_order.size()]
		ring.append(layout._place(ANCHORS[region], RING[2 * index], [REGIONS[region]], ANCHORS[region]))
		var connector := StringName("transition_%d" % index)
		ring.append(layout._place(connector, RING[2 * index + 1], [REGIONS[region], REGIONS[adjacent]]))
	for index: int in ring.size():
		layout._link(ring[index], ring[(index + 1) % ring.size()])
	layout._link(ring[1], ring[4])
	layout._shortcut.assign([ring[1].id, ring[4].id])
	var gateway_parent := ring[2 * (rng.draw(&"topology_v1_gateway") % region_order.size()) + 1]
	layout._attach(gateway_parent, GATEWAY, rng.draw(&"topology_v1_gateway"))
	for index: int in region_order.size():
		var region := region_order[index]
		var parent := ring[2 * index]
		for landmark: StringName in OPTIONAL[region]:
			if rng.draw(&"topology_v1_sites") % 2 == 0:
				continue
			var placed := layout._attach(parent, landmark, rng.draw(&"topology_v1_sites"), landmark)
			if placed != null:
				parent = placed
	return layout


## Reserve a connected interior and independent return geometry. WP25 owns
## when the party can transfer through a particular authored entrance.
static func generate_optional(run_seed: int, realm_id: StringName) -> WorldTopology:
	if realm_id not in OPTIONAL_REALMS:
		return null
	var layout := WorldTopology.new()
	layout._seed = run_seed
	layout._realm = realm_id
	var rng := RunRandom.new(run_seed)
	var entrance := rng.draw(StringName("topology_v1_entry/%s" % realm_id)) % RING.size()
	var ring: Array[Module] = []
	for index: int in RING.size():
		var id := StringName("interior_%d" % index)
		if index == 0:
			id = ENTRY
		elif index == 3:
			id = RETURN_EXIT
		ring.append(layout._place(id, RING[(index + entrance) % RING.size()], []))
	for index: int in ring.size():
		layout._link(ring[index], ring[(index + 1) % ring.size()])
	return layout


func _place(id: StringName, cell: Vector2i, regions: Array[StringName], landmark: StringName = &"") -> Module:
	var item := Module.new()
	item.id = id
	item.cell = cell
	item.regions = regions.duplicate()
	item.landmark = landmark
	_modules[id] = item
	_cells[cell] = id
	return item


func _attach(parent: Module, id: StringName, choice: int, landmark: StringName = &"") -> Module:
	for index: int in CARDINAL.size():
		var offset: Vector2i = CARDINAL[(index + choice) % CARDINAL.size()]
		var cell := parent.cell + offset
		if not _cells.has(cell):
			var placed := _place(id, cell, parent.regions, landmark)
			_link(parent, placed)
			return placed
	return null


static func _link(first: Module, second: Module) -> void:
	first.neighbors.append(second.id)
	second.neighbors.append(first.id)


func manifest() -> Dictionary:
	var result: Array[Dictionary] = []
	for id: StringName in _module_ids():
		var item := _modules[id]
		result.append({"id": id, "cell": item.cell, "regions": item.regions.duplicate(),
			"landmark": item.landmark, "neighbors": item.neighbors.duplicate()})
	return {"revision": REVISION, "realm": _realm, "seed": _seed,
		"modules": result, "shortcut": _shortcut.duplicate()}


## A local checkpoint names its original generation. The current revision
## rejects a mismatched module or link before world state can use it.
static func restore(saved: Dictionary) -> WorldTopology:
	if (saved.get("revision") != REVISION or not saved.get("seed") is int
			or not saved.get("realm") is StringName or not saved.get("modules") is Array):
		return null
	var realm_id: StringName = saved["realm"]
	var layout := generate(saved["seed"]) if realm_id == OVERWORLD else generate_optional(saved["seed"], realm_id)
	if layout == null:
		return null
	# The original checkpoint accepted the engine's StringName iteration
	# order. Compare by stable names while retaining all recorded module facts.
	var ordered: Array[Dictionary] = []
	for row: Variant in saved["modules"]:
		if not row is Dictionary or not row.get("id") is StringName:
			return null
		ordered.append(row)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left["id"]) < String(right["id"]))
	var canonical := saved.duplicate()
	canonical["modules"] = ordered
	return layout if layout.manifest() == canonical else null


func route(origin: StringName, destination: StringName, shortcut_open: bool = false) -> Array[StringName]:
	if not _modules.has(origin) or not _modules.has(destination):
		return []
	var previous: Dictionary[StringName, StringName] = {origin: &""}
	var visited: Array[StringName] = [origin]
	var index := 0
	while index < visited.size() and not previous.has(destination):
		var current := visited[index]
		index += 1
		for next: StringName in _modules[current].neighbors:
			if not previous.has(next) and (shortcut_open or not _is_shortcut(current, next)):
				previous[next] = current
				visited.append(next)
	if not previous.has(destination):
		return []
	var path: Array[StringName] = []
	var current := destination
	while not current.is_empty():
		path.append(current)
		current = previous[current]
	path.reverse()
	return path


func contains_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func center(id: StringName) -> RealmSweep.Point:
	var item: Module = _modules.get(id)
	if item == null:
		return null
	return RealmSweep.Point.new((item.cell.x + 0.5) * MODULE_SIZE, (item.cell.y + 0.5) * MODULE_SIZE)


func realize(blocker_mask: int, shortcut_open: bool = false) -> RealmGeometry:
	var geometry := RealmGeometry.new(_realm)
	for id: StringName in _module_ids():
		var item := _modules[id]
		for side: int in CARDINAL.size():
			var normal: Vector2i = CARDINAL[side]
			var neighbor: StringName = _cells.get(item.cell + normal, &"")
			# Each shared edge has a single owner. Closed and open sides
			# use the same tile coordinate and authored clearance.
			if not neighbor.is_empty() and String(neighbor) < String(id):
				continue
			if not _solid_side(geometry, item, side, neighbor, blocker_mask, shortcut_open):
				return null
	return geometry


## A module connection must have room for a starter circle in the realized
## geometry. The route test covers every open edge before a realm admits play.
func has_clearance(geometry: RealmGeometry, blocker_mask: int, radius: float,
		shortcut_open: bool = false) -> bool:
	if geometry == null or geometry.realm_id != _realm:
		return false
	var start: StringName = ANCHORS[0] if _realm == OVERWORLD else ENTRY
	for id: StringName in _module_ids():
		if route(start, id, shortcut_open).is_empty():
			return false
		for neighbor: StringName in _modules[id].neighbors:
			if String(id) >= String(neighbor) or (not shortcut_open and _is_shortcut(id, neighbor)):
				continue
			var proof := geometry.certify_circle_sweep(_realm, center(id), center(neighbor), radius, blocker_mask)
			if proof == null or not proof.unresolved.is_empty() or not proof.contacts.is_empty():
				return false
	return true


func _module_ids() -> Array[StringName]:
	var ids := _modules.keys()
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	return ids


func _solid_side(geometry: RealmGeometry, item: Module, side: int, neighbor: StringName,
		blocker_mask: int, shortcut_open: bool) -> bool:
	var normal: Vector2i = CARDINAL[side]
	var tangent := Vector2i(-normal.y, normal.x)
	var half_size := MODULE_SIZE * 0.5
	var x := (item.cell.x + 0.5) * MODULE_SIZE + normal.x * half_size
	var y := (item.cell.y + 0.5) * MODULE_SIZE + normal.y * half_size
	var slot := side * 2
	if neighbor not in item.neighbors:
		return _add_wall(geometry, item.id, slot, x, y, tangent, -half_size, half_size, blocker_mask, true)
	if not _add_wall(geometry, item.id, slot, x, y, tangent, -half_size, -SEAM_HALF_WIDTH, blocker_mask, true):
		return false
	if not _add_wall(geometry, item.id, slot + 1, x, y, tangent, SEAM_HALF_WIDTH, half_size, blocker_mask, true):
		return false
	if not shortcut_open and _is_shortcut(item.id, neighbor):
		return _add_wall(geometry, SHORTCUT_DOOR, 0, x, y, tangent, -SEAM_HALF_WIDTH, SEAM_HALF_WIDTH,
			blocker_mask, false)
	return true


func _is_shortcut(first: StringName, second: StringName) -> bool:
	return first in _shortcut and second in _shortcut and first != second


static func _add_wall(geometry: RealmGeometry, id: StringName, slot: int, x: float, y: float,
		tangent: Vector2i, low: float, high: float, mask: int, fixed: bool) -> bool:
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(x + tangent.x * low, y + tangent.y * low)
	edge.last = RealmSweep.Point.new(x + tangent.x * high, y + tangent.y * high)
	return geometry.add_segment(id, slot, edge, mask, fixed)
