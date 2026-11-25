class_name RecipientView
extends RefCounted
## Host-only projection. The visibility owner supplies the approved viewpoint
## and the identifiers visible or warnable from that viewpoint.

const VERSION := 1
const PARTY_STATUS := [&"living", &"down", &"disconnected"]

class Scope:
	var seat: StringName
	var realm: StringName
	var actors: Dictionary[StringName, bool] = {}
	var warnings: Dictionary[StringName, bool] = {}

class Actor:
	var id: StringName
	var realm: StringName
	var position: RealmSweep.Point

class Warning:
	var id: StringName
	var realm: StringName
	var origin: RealmSweep.Point
	var end: RealmSweep.Point
	var radius: float
	var activation: int
	var impact: int

class Snapshot:
	var epoch: int
	var baseline: int
	var tick: int
	var realm: String
	var level: int
	var xp: String
	var party: Dictionary[String, String] = {}
	var actors: Dictionary[String, RealmSweep.Point] = {}
	var warnings: Dictionary[String, Warning] = {}
	var explored: Array[Vector2i] = []


## Only the approved party summary crosses realm boundaries. A warning carries
## its own cue ID and never requires the actor's row or private identity.
static func pack(scope: Scope, epoch: int, baseline: int, tick: int, shared_level: int, shared_xp: String,
		party: Dictionary[StringName, StringName], actors: Array[Actor], warnings: Array[Warning],
		exploration: WorldExploration, limit: int = ReplicationMessage.MAX_BODY) -> PackedByteArray:
	if (scope == null or scope.seat.is_empty() or scope.realm.is_empty() or epoch <= 0 or baseline <= 0
			or tick < 0 or tick > RunAuthority.MAX_TICK or shared_level < 0 or not _valid_xp(shared_xp)):
		return PackedByteArray()
	var visible: Dictionary[String, Array] = {}
	for actor: Actor in actors:
		if actor == null or actor.realm != scope.realm or not scope.actors.get(actor.id, false):
			continue
		if actor.id.is_empty() or not _valid_point(actor.position) or visible.has(String(actor.id)):
			return PackedByteArray()
		visible[String(actor.id)] = [actor.position.x, actor.position.y]
	var cues: Dictionary[String, Array] = {}
	for warning: Warning in warnings:
		if warning == null or warning.realm != scope.realm or warning.impact < tick or not scope.warnings.get(warning.id, false):
			continue
		if (warning.id.is_empty() or cues.has(String(warning.id)) or not _valid_point(warning.origin)
				or not _valid_point(warning.end) or not is_finite(warning.radius) or warning.radius <= 0.0
				or warning.activation < 0 or warning.impact < warning.activation or warning.impact > RunAuthority.MAX_TICK):
			return PackedByteArray()
		cues[String(warning.id)] = [warning.origin.x, warning.origin.y, warning.end.x, warning.end.y,
			warning.radius, str(warning.activation), str(warning.impact)]
	var statuses: Dictionary[String, String] = {}
	for seat: StringName in party:
		if seat.is_empty() or party[seat] not in PARTY_STATUS:
			return PackedByteArray()
		statuses[String(seat)] = String(party[seat])
	var cells: Array[Array] = []
	if exploration != null and exploration.geometry().realm_id == scope.realm:
		var map := exploration.view(scope.seat)
		for cell: Vector2i in map.get("explored", []):
			cells.append([cell.x, cell.y])
	var permitted := {"v": VERSION, "epoch": str(epoch), "baseline": str(baseline), "tick": str(tick),
		"realm": String(scope.realm), "level": str(shared_level), "xp": shared_xp, "party": statuses,
		"actors": visible, "warnings": cues, "explored": cells}
	var bytes := JSON.stringify(permitted, "", true, true).to_utf8_buffer()
	return bytes if bytes.size() <= mini(limit, ReplicationChunks.MAX_ASSEMBLED) else PackedByteArray()


static func read(bytes: PackedByteArray) -> Snapshot:
	if bytes.is_empty() or bytes.size() > ReplicationChunks.MAX_ASSEMBLED:
		return null
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not decoded is Dictionary or decoded.size() != 11 or not _number(decoded.get("v")) or decoded["v"] != VERSION:
		return null
	var snapshot := Snapshot.new()
	snapshot.epoch = _unsigned(decoded.get("epoch"))
	snapshot.baseline = _unsigned(decoded.get("baseline"))
	snapshot.tick = _unsigned(decoded.get("tick"), RunAuthority.MAX_TICK)
	snapshot.level = _unsigned(decoded.get("level"))
	var realm: Variant = decoded.get("realm")
	var xp: Variant = decoded.get("xp")
	if (snapshot.epoch <= 0 or snapshot.baseline <= 0 or snapshot.tick < 0 or snapshot.level < 0
			or not realm is String or realm.is_empty() or not xp is String or not _valid_xp(xp)):
		return null
	snapshot.realm = realm
	snapshot.xp = xp
	if not _read_actors(snapshot, decoded.get("actors")) or not _read_warnings(snapshot, decoded.get("warnings")):
		return null
	var party: Variant = decoded.get("party")
	var explored: Variant = decoded.get("explored")
	if not party is Dictionary or not explored is Array:
		return null
	for seat: String in party:
		if seat.is_empty() or not party[seat] is String or not party[seat] in PARTY_STATUS:
			return null
		snapshot.party[seat] = party[seat]
	for cell: Variant in explored:
		if not cell is Array or cell.size() != 2 or not _cell_coord(cell[0]) or not _cell_coord(cell[1]):
			return null
		snapshot.explored.append(Vector2i(int(cell[0]), int(cell[1])))
	return snapshot


static func _read_actors(snapshot: Snapshot, rows: Variant) -> bool:
	if not rows is Dictionary:
		return false
	for id: String in rows:
		var row: Variant = rows[id]
		if id.is_empty() or not row is Array or row.size() != 2:
			return false
		var point := _read_point(row[0], row[1])
		if point == null:
			return false
		snapshot.actors[id] = point
	return true


static func _read_warnings(snapshot: Snapshot, rows: Variant) -> bool:
	if not rows is Dictionary:
		return false
	for id: String in rows:
		var row: Variant = rows[id]
		if id.is_empty() or not row is Array or row.size() != 7 or not _number(row[4]):
			return false
		var warning := Warning.new()
		warning.origin = _read_point(row[0], row[1])
		warning.end = _read_point(row[2], row[3])
		warning.radius = float(row[4])
		warning.activation = _unsigned(row[5], RunAuthority.MAX_TICK)
		warning.impact = _unsigned(row[6], RunAuthority.MAX_TICK)
		if (warning.origin == null or warning.end == null or warning.radius <= 0.0 or warning.activation < 0
				or warning.impact < maxi(snapshot.tick, warning.activation)):
			return false
		warning.id = StringName(id)
		warning.realm = StringName(snapshot.realm)
		snapshot.warnings[id] = warning
	return true


static func _unsigned(value: Variant, maximum: int = 9223372036854775807) -> int:
	if not value is String or value.length() > 19 or not _valid_xp(value):
		return -1
	var ceiling := str(maximum)
	if value.length() > ceiling.length() or (value.length() == ceiling.length() and value > ceiling):
		return -1
	var number: int = value.to_int()
	return number if str(number) == value else -1


static func _read_point(x: Variant, y: Variant) -> RealmSweep.Point:
	if not _number(x) or not _number(y):
		return null
	return RealmSweep.Point.new(float(x), float(y))


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _cell_coord(value: Variant) -> bool:
	return _number(value) and value >= -2147483648 and value <= 2147483647 and value == floorf(value)


static func _valid_xp(value: String) -> bool:
	if value.is_empty() or value.length() > NativeSessionFrame.MAX_PAYLOAD:
		return false
	for digit: int in value.to_ascii_buffer():
		if digit < 48 or digit > 57:
			return false
	return true


static func _valid_point(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
