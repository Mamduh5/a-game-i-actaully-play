class_name RunRealmTrial
extends RefCounted
## Optional activity lifecycle under PR11. The authored trial owns its
## interactions and receives RESET to discard incomplete mechanism progress.

enum Phase { DORMANT, ACTIVE, COMPLETED }
enum Observation { INVALID, RETAINED, RESET }

const COLLAPSE_TICK := 25 * 60 * RunParty.LOGICAL_HZ

var _party: RunParty
var _realm: StringName
var _center: RealmSweep.Point
var _radius: float
var _resettable: bool
var _corpses_relevant: bool
var _phase: Phase

var phase: Phase:
	get: return _phase


static func declare(party: RunParty, space: WorldExploration, center: RealmSweep.Point, radius: float,
		resettable: bool, corpses_relevant: bool) -> RunRealmTrial:
	if (party == null or space == null or space.geometry() == null or space.module_at(center).is_empty()
			or space.geometry().realm_id not in WorldTopology.OPTIONAL_REALMS
			or radius <= 0.0 or not is_finite(radius)):
		return null
	var trial := RunRealmTrial.new()
	trial._party = party
	trial._realm = space.geometry().realm_id
	trial._center = PlayerControlState.copy_point(center)
	trial._radius = radius
	trial._resettable = resettable
	trial._corpses_relevant = corpses_relevant
	return trial


## Called after an authored interaction has been accepted at the current
## clock. Proximity by itself never initiates a dormant optional trial.
func start(seat: StringName, now: CombatInstant) -> bool:
	if (not _at_party_boundary(now) or _phase != Phase.DORMANT or now.tick >= COLLAPSE_TICK
			or not _party.can_control(seat)):
		return false
	var entrant := _party.view(seat, now)
	if entrant == null or not entrant.alive or not entrant.connected or _location(entrant) != RealmCircleTime.Result.HIT:
		return false
	_phase = Phase.ACTIVE
	return true


func complete(now: CombatInstant) -> bool:
	if not _at_party_boundary(now) or _phase != Phase.ACTIVE:
		return false
	_phase = Phase.COMPLETED
	return true


func observe(now: CombatInstant) -> Observation:
	if not _at_party_boundary(now):
		return Observation.INVALID
	if _phase == Phase.ACTIVE and _resettable:
		for seat: StringName in _party.initialized_seats():
			var participant := _party.view(seat, now)
			if participant == null or (not participant.alive and not _corpses_relevant):
				continue
			match _location(participant):
				RealmCircleTime.Result.UNRESOLVED:
					return Observation.INVALID
				RealmCircleTime.Result.HIT:
					return Observation.RETAINED
		_phase = Phase.DORMANT
		return Observation.RESET
	return Observation.RETAINED


func _at_party_boundary(now: CombatInstant) -> bool:
	return (_party != null and now != null
		and now.order_against(CombatInstant.at_tick(_party.closed_tick)) == RealmCircleTime.Order.SAME)


func _location(participant: RunParty.View) -> RealmCircleTime.Result:
	if participant.realm != _realm or participant.position == null:
		return RealmCircleTime.Result.MISS
	var position := participant.position
	var result := RealmCircleTime.new().measure(position, position, 0.0, _center, _center, _radius)
	return result.outcome
