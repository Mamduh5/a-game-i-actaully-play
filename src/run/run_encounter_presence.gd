class_name RunEncounterPresence
extends RefCounted
## The encounter owner samples closed poses while active, then locks local
## entitlement once. Shared XP still goes through PartyProgression.

const MARGIN := 200.0

var _party: RunParty
var _id: StringName
var _realm: StringName
var _center: RealmSweep.Point
var _radius: float
var _latest: CombatInstant
var _seen: Dictionary[StringName, bool] = {}
var _nearby: Array[StringName] = []
var _settled: bool

var id: StringName:
	get: return _id


static func start(party: RunParty, occurrence: StringName, realm: StringName, center: RealmSweep.Point,
		radius: float, now: CombatInstant) -> RunEncounterPresence:
	if (party == null or occurrence.is_empty() or realm.is_empty() or center == null
			or not is_finite(center.x) or not is_finite(center.y) or not is_finite(radius) or radius < 0.0 or now == null):
		return null
	var encounter := RunEncounterPresence.new()
	encounter._party = party
	encounter._id = occurrence
	encounter._realm = realm
	encounter._center = PlayerControlState.copy_point(center)
	encounter._radius = radius
	if not encounter.observe(now):
		return null
	return encounter


## Also sample after movement and before a lethal group can change a fresh
## arrival into a body at the closing instant.
func observe(now: CombatInstant) -> bool:
	if (_settled or now == null or (_latest != null and _latest.order_against(now)
			not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])):
		return false
	var seen := _seen.duplicate()
	var nearby: Array[StringName] = []
	var certifier := RealmCircleTime.new()
	for seat: StringName in _party.initialized_seats():
		var member := _party.view(seat, now)
		if member.realm != _realm or member.position == null:
			continue
		var overlap := certifier.measure(member.position, member.position, MARGIN, _center, _center, _radius)
		match overlap.outcome:
			RealmCircleTime.Result.UNRESOLVED: return false
			RealmCircleTime.Result.MISS: continue
		if member.alive and member.connected:
			seen[seat] = true
		if seen.has(seat) and (member.connected or member.within_grace):
			nearby.append(seat)
	_seen = seen
	_nearby = nearby
	_latest = now
	return true


func settle(now: CombatInstant) -> bool:
	if not observe(now):
		return false
	_settled = true
	return true


func recipients() -> Array[StringName]:
	return _nearby.duplicate() if _settled else []


func settlement_tick(run: StringName, epoch: int) -> int:
	return _latest.tick if _settled and _party.belongs_to(run, epoch) else -1
