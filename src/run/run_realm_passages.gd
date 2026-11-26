class_name RunRealmPassages
extends RefCounted
## Authority-owned routes discovered by the world. Both ends require a
## reachable, intentional interaction on the current admitted realm.

class Passage:
	var id: StringName
	var local: WorldExploration
	var handle: RealmSweep.Point
	var remote: WorldExploration
	var arrival: RealmSweep.Point
	var pick_radius: float
	var reach: float

var _passages: Dictionary[StringName, Passage] = {}
var _authority: RunAuthority
var _party: RunParty


func _init(authority: RunAuthority, party: RunParty) -> void:
	_authority = authority
	_party = party


func register_optional(id: StringName, origin: WorldExploration, at: RealmSweep.Point,
		optional: WorldExploration, reach: float, pick_radius: float) -> bool:
	var return_id := StringName(String(id) + "/return")
	if (id.is_empty() or _passages.has(id) or _passages.has(return_id) or origin == null or optional == null
			or origin.geometry() == null or optional.geometry() == null
			or origin.geometry().realm_id == optional.geometry().realm_id
			or optional.geometry().realm_id not in WorldTopology.OPTIONAL_REALMS
			or origin.module_at(at).is_empty() or reach <= 0.0 or not is_finite(reach)
			or pick_radius <= 0.0 or not is_finite(pick_radius)):
		return false
	var arrival := optional.module_center(WorldTopology.ENTRY)
	var exit := optional.module_center(WorldTopology.RETURN_EXIT)
	if arrival == null or exit == null:
		return false
	var reserve := StringName("passage/%s" % id)
	var entry_key := StringName(String(reserve) + "/arrival")
	var exit_key := StringName(String(reserve) + "/exit")
	if not origin.reserve_route_approach(reserve, at):
		return false
	if not optional.reserve_route_approach(entry_key, arrival):
		origin.release_route_approach(reserve)
		return false
	if not optional.reserve_route_approach(exit_key, exit):
		optional.release_route_approach(entry_key)
		origin.release_route_approach(reserve)
		return false
	_passages[id] = _passage(id, origin, at, optional, arrival, reach, pick_radius)
	_passages[return_id] = _passage(return_id, optional, exit, origin, at, reach, pick_radius)
	return true


## The host handles this from the accepted interaction. The peer never
## supplies a destination realm, knowledge state or arrival pose.
func interact(intent: RunIntent) -> bool:
	if (_authority == null or _party == null or intent == null
			or intent.action != PlayerCommand.INTERACT or not intent.valid_payload()):
		return false
	var current := _party.view(intent.seat_id, CombatInstant.at_tick(intent.tick))
	if (current == null or current.position == null or not current.alive or not current.connected
			or current.realm != intent.realm_id):
		return false
	var cursor := RealmSweep.Point.new(intent.command.x, intent.command.y)
	var candidates: Array[PlayerTargeting.Candidate] = []
	var targeting := PlayerTargeting.new()
	var reach := 0.0
	for passage: Passage in _passages.values():
		if passage.local.geometry().realm_id != current.realm or passage.remote.view(intent.seat_id).is_empty():
			continue
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = passage.id
		candidate.kind = PlayerTargeting.Kind.MECHANISM
		candidate.position = passage.handle
		candidate.pick_radius = passage.pick_radius
		candidate.known = true
		candidate.interactable = true
		if targeting.interact(current.position, cursor, passage.reach, [candidate]) != &"":
			var sight := passage.local.geometry().certify_frozen_path(current.realm,
				current.position, passage.handle, 0.0, WorldExploration.BLOCKER)
			if sight != null and sight.contacts.is_empty() and sight.unresolved.is_empty():
				candidates.append(candidate)
				reach = maxf(reach, passage.reach)
	var chosen := targeting.interact(current.position, cursor, reach, candidates)
	if chosen.is_empty():
		return false
	var selected := _passages[chosen]
	if not _authority.transfer_seat(intent, _party, selected.local.geometry(), selected.remote.geometry(), selected.arrival):
		return false
	var reached := selected.remote.geometry().realm_id
	selected.local.observe_seat(intent.seat_id, reached, null)
	selected.remote.observe_seat(intent.seat_id, reached, selected.arrival)
	return true


static func _passage(id: StringName, local: WorldExploration, handle: RealmSweep.Point,
		remote: WorldExploration, arrival: RealmSweep.Point, reach: float, pick_radius: float) -> Passage:
	var route := Passage.new()
	route.id = id
	route.local = local
	route.handle = PlayerControlState.copy_point(handle)
	route.remote = remote
	route.arrival = PlayerControlState.copy_point(arrival)
	route.reach = reach
	route.pick_radius = pick_radius
	return route
