class_name PlayerTargeting
extends RefCounted
## The owner supplies knowledge and compatibility for the current seat, source and realm.

enum Kind { HOSTILE, CONTAINER, BARRICADE, PILLAR, CRYSTAL, MACHINERY, SEALED_CACHE, SECRET, PROTECTED, MECHANISM }

class Candidate:
	var id: StringName
	var kind: Kind
	var position: RealmSweep.Point
	var pick_radius: float
	var known: bool
	var compatible: bool
	var interactable: bool
	var precision: bool

var _selected: StringName
var _precision: StringName


func select(origin: RealmSweep.Point, cursor: RealmSweep.Point, attack_range: float,
		candidates: Array[Candidate]) -> StringName:
	_selected = _pick_point(origin, cursor, attack_range, candidates, false)
	return _selected


func interact(origin: RealmSweep.Point, cursor: RealmSweep.Point, reach: float,
		candidates: Array[Candidate]) -> StringName:
	var picked := _pick_point(origin, cursor, reach, candidates, true)
	for item: Candidate in candidates:
		if not picked.is_empty() and item.id == picked and item.kind == Kind.MECHANISM and item.precision:
			_precision = picked
			break
	return picked


## Revalidate selection with the current source and position. A rejected
## activation leaves the precision request available for a later opportunity.
func attack_target(origin: RealmSweep.Point, reach: float, candidates: Array[Candidate]) -> StringName:
	var deliberate: Candidate
	var hostile: Candidate
	var object: Candidate
	for item: Candidate in candidates:
		if not _in_range(origin, reach, item) or not item.compatible:
			continue
		if item.kind == Kind.MECHANISM and item.precision and item.id == _precision:
			return item.id
		if item.id == _selected and _deliberate(item.kind):
			deliberate = item
		elif item.kind == Kind.HOSTILE and _nearer(origin, item, hostile):
			hostile = item
		elif item.kind in [Kind.CONTAINER, Kind.BARRICADE, Kind.SEALED_CACHE] and _nearer(origin, item, object):
			object = item
	if deliberate != null:
		return deliberate.id
	if hostile != null:
		return hostile.id
	return object.id if object != null else &""


func commit_attack_target(id: StringName) -> void:
	if id == _precision:
		_precision = &""


static func _pick_point(origin: RealmSweep.Point, cursor: RealmSweep.Point, reach: float,
		candidates: Array[Candidate], interaction: bool) -> StringName:
	var picked: Candidate
	for item: Candidate in candidates:
		if not _in_range(origin, reach, item) or not _in_range(cursor, item.pick_radius, item):
			continue
		var eligible := item.interactable if interaction else item.compatible and _deliberate(item.kind)
		if eligible and _nearer(cursor, item, picked):
			picked = item
	return picked.id if picked != null else &""


static func _deliberate(kind: Kind) -> bool:
	return kind not in [Kind.SECRET, Kind.PROTECTED, Kind.MECHANISM]


static func _in_range(origin: RealmSweep.Point, reach: float, item: Candidate) -> bool:
	return (item != null and item.known and item.position != null and not item.id.is_empty()
		and is_finite(reach) and reach >= 0.0 and _distance(origin, item.position) <= reach)


static func _nearer(origin: RealmSweep.Point, first: Candidate, second: Candidate) -> bool:
	if second == null:
		return true
	var a := _distance(origin, first.position)
	var b := _distance(origin, second.position)
	return a < b or (a == b and String(first.id) < String(second.id))


static func _distance(a: RealmSweep.Point, b: RealmSweep.Point) -> float:
	var x := absf(a.x - b.x)
	var y := absf(a.y - b.y)
	var largest := maxf(x, y)
	if largest == 0.0 or not is_finite(largest):
		return largest
	var smaller := minf(x, y) / largest
	return largest * sqrt(1.0 + smaller * smaller)
