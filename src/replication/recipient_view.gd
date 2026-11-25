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


## Only the approved party summary crosses realm boundaries. A warning carries
## its own cue ID and never requires the actor's row or private identity.
static func pack(scope: Scope, epoch: int, baseline: int, tick: int, shared_level: int, shared_xp: String,
		party: Dictionary[StringName, StringName], actors: Array[Actor], warnings: Array[Warning],
		exploration: WorldExploration) -> PackedByteArray:
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
	return bytes if bytes.size() <= ReplicationMessage.MAX_BODY else PackedByteArray()


static func _valid_xp(value: String) -> bool:
	if value.is_empty() or value.length() > NativeSessionFrame.MAX_PAYLOAD:
		return false
	for digit: int in value.to_ascii_buffer():
		if digit < 48 or digit > 57:
			return false
	return true


static func _valid_point(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
