class_name CombatInstant
extends RefCounted
## A logical tick boundary plus a certified time within the following tick.

var tick: int:
	get: return _tick
var _tick: int
var _time: RealmCircleTime.Contact


static func at_tick(logical_tick: int) -> CombatInstant:
	if logical_tick < 0 or logical_tick > RunAuthority.MAX_TICK:
		return null
	var instant := CombatInstant.new()
	instant._tick = logical_tick
	instant._time = RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT)
	return instant


## The owner passes the retained result of its certified spatial query.
static func at_contact(start_tick: int, proof: RealmCircleTime.Contact) -> CombatInstant:
	if (proof == null or proof.outcome != RealmCircleTime.Result.HIT or not is_finite(proof.earliest)
			or not is_finite(proof.latest) or proof.earliest < 0.0 or proof.latest > 1.0
			or proof.earliest > proof.latest or start_tick < 0 or start_tick >= RunAuthority.MAX_TICK):
		return null
	var end := RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT, 1.0, 1.0)
	match proof.order_against(end):
		RealmCircleTime.Order.SAME:
			return at_tick(start_tick + 1)
		RealmCircleTime.Order.UNRESOLVED:
			return null
	var instant := CombatInstant.new()
	instant._tick = start_tick
	instant._time = proof.copy()
	return instant


func order_against(other: CombatInstant) -> RealmCircleTime.Order:
	if _time == null or other == null or other._time == null:
		return RealmCircleTime.Order.UNRESOLVED
	if _tick < other.tick:
		return RealmCircleTime.Order.BEFORE
	if _tick > other.tick:
		return RealmCircleTime.Order.AFTER
	return _time.order_against(other._time)
