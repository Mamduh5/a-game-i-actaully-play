class_name RealmSpatialIndex
extends RefCounted
## One realm's complete broad phase. Queries deduplicate bucket occurrences by proxy.

const CELL_SIZE := 128.0
const MAX_GRID_CELLS := 256
const MAX_EXACT_CELL := 4503599627370495.0

class Proxy:
	var entity: StringName:
		get: return _entity
	var shape: int:
		get: return _shape
	var bounds: RealmBounds:
		get: return _bounds
	var _entity: StringName
	var _shape: int
	var _bounds: RealmBounds
	var _cells: CellWindow

class CandidateSet:
	var proxies: Array[Proxy] = []

class CellWindow:
	var x0: int
	var y0: int
	var x1: int
	var y1: int

	func is_large() -> bool:
		var width := x1 - x0 + 1
		var height := y1 - y0 + 1
		return width > MAX_GRID_CELLS or height > MAX_GRID_CELLS or width * height > MAX_GRID_CELLS


var realm_id: StringName:
	get: return _realm_id

var _realm_id: StringName
var _proxies: Dictionary[StringName, Proxy] = {}
var _rows: Dictionary[int, Dictionary] = {}
var _large: Dictionary[StringName, Proxy] = {}


func _init(id: StringName) -> void:
	_realm_id = id


func register(entity: StringName, shape: int, bounds: RealmBounds) -> bool:
	var id := _key(entity, shape)
	if _proxies.has(id):
		return false
	var proxy := _create_proxy(entity, shape, bounds)
	if proxy == null:
		return false
	_insert(id, proxy)
	return true


## Commits the new broad-phase bounds before returning to the calling group.
func move(entity: StringName, shape: int, bounds: RealmBounds) -> bool:
	var id := _key(entity, shape)
	var previous: Proxy = _proxies.get(id)
	if previous == null:
		return false
	var next := _create_proxy(entity, shape, bounds)
	if next == null:
		return false
	_remove(id, previous)
	_insert(id, next)
	return true


func remove(entity: StringName, shape: int) -> bool:
	var id := _key(entity, shape)
	var proxy: Proxy = _proxies.get(id)
	if proxy == null:
		return false
	_remove(id, proxy)
	return true


## Null is an unsupported coordinate input. An empty valid result is a genuine miss.
## Returned candidates have no gameplay tie-breaking order.
func query(area: RealmBounds) -> CandidateSet:
	var window := _cells_for(area)
	if window == null:
		return null
	var result := CandidateSet.new()
	var seen: Dictionary[StringName, bool] = {}
	if window.is_large():
		_collect(_proxies, area, result, seen)
		return result
	_collect(_large, area, result, seen)
	for y: int in range(window.y0, window.y1 + 1):
		var row: Dictionary = _rows.get(y, {})
		for x: int in range(window.x0, window.x1 + 1):
			if row.has(x):
				_collect(row[x], area, result, seen)
	return result


func _create_proxy(entity: StringName, shape: int, bounds: RealmBounds) -> Proxy:
	var cells := _cells_for(bounds)
	if entity.is_empty() or shape < 0 or cells == null:
		return null
	var proxy := Proxy.new()
	proxy._entity = entity
	proxy._shape = shape
	proxy._bounds = bounds
	proxy._cells = cells
	return proxy


func _insert(id: StringName, proxy: Proxy) -> void:
	_proxies[id] = proxy
	var window := proxy._cells
	if window.is_large():
		_large[id] = proxy
		return
	for y: int in range(window.y0, window.y1 + 1):
		if not _rows.has(y):
			_rows[y] = {}
		var row: Dictionary = _rows[y]
		for x: int in range(window.x0, window.x1 + 1):
			if not row.has(x):
				row[x] = {}
			row[x][id] = proxy


func _remove(id: StringName, proxy: Proxy) -> void:
	_proxies.erase(id)
	var window := proxy._cells
	if window.is_large():
		_large.erase(id)
		return
	for y: int in range(window.y0, window.y1 + 1):
		var row: Dictionary = _rows[y]
		for x: int in range(window.x0, window.x1 + 1):
			var bucket: Dictionary = row[x]
			bucket.erase(id)
			if bucket.is_empty():
				row.erase(x)
		if row.is_empty():
			_rows.erase(y)


static func _collect(source: Dictionary, area: RealmBounds, output: CandidateSet,
		seen: Dictionary[StringName, bool]) -> void:
	for id: StringName in source:
		if seen.has(id):
			continue
		seen[id] = true
		var proxy: Proxy = source[id]
		if area.overlaps(proxy.bounds):
			output.proxies.append(proxy)


static func _cells_for(bounds: RealmBounds) -> CellWindow:
	if bounds == null:
		return null
	var x0 := bounds.west / CELL_SIZE
	var y0 := bounds.north / CELL_SIZE
	var x1 := bounds.east / CELL_SIZE
	var y1 := bounds.south / CELL_SIZE
	if x0 < -MAX_EXACT_CELL or y0 < -MAX_EXACT_CELL or x1 > MAX_EXACT_CELL or y1 > MAX_EXACT_CELL:
		return null
	var window := CellWindow.new()
	window.x0 = floori(x0)
	window.y0 = floori(y0)
	window.x1 = floori(x1)
	window.y1 = floori(y1)
	return window


static func _key(entity: StringName, shape: int) -> StringName:
	return StringName("%s/%d" % [entity, shape])
