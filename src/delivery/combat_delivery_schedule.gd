class_name CombatDeliverySchedule
extends RefCounted
## One persistent effect's exact due instants, independent of render frames.

enum Kind { TICK, NATURAL_EXPIRY }
enum End { ACTIVE, NATURAL, DESTROYED, REPLACED, REALM_CLEANUP, PAYMENT_DECLINED, CONSUMED }

class Due:
	var kind: Kind
	var instant: CombatInstant
	var ordinal: int
	var _schedule: CombatDeliverySchedule

var _period: int
var _next_tick: CombatInstant
var _start: CombatInstant
var _expiry: CombatInstant
var _latest: CombatInstant
var _ordinal := 1
var _end: End

var end_reason: End:
	get: return _end

## The cadence instant before applying the current expiry.
var next_tick: CombatInstant:
	get: return _next_tick

func next_event() -> Due:
	return due_through(_expiry)


func copy() -> CombatDeliverySchedule:
	var result := CombatDeliverySchedule.new()
	result._period = _period
	result._next_tick = _next_tick
	result._start = _start
	result._expiry = _expiry
	result._latest = _latest
	result._ordinal = _ordinal
	result._end = _end
	return result


static func create(start: CombatInstant, duration: int, period: int, immediate_tick: bool = false) -> CombatDeliverySchedule:
	if start == null or duration <= 0 or period <= 0:
		return null
	var expiry := start.after_ticks(duration)
	if expiry == null:
		return null
	var result := CombatDeliverySchedule.new()
	result._latest = start
	result._start = start
	result._period = period
	result._expiry = expiry
	result._next_tick = start if immediate_tick else start.after_ticks(period)
	return result


func active_at(now: CombatInstant) -> bool:
	return (_end == End.ACTIVE and now != null
		and _start.order_against(now) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
		and now.order_against(_expiry) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


## A normal refresh extends the current lifetime and preserves tick phase.
## The effect remains refreshable through its last tick until expiry settles.
func refresh(now: CombatInstant, duration: int) -> bool:
	return _change_lifetime(now, duration, false)


func replace_remaining(now: CombatInstant, duration: int) -> bool:
	return _change_lifetime(now, duration, true)


func _change_lifetime(now: CombatInstant, duration: int, replace: bool) -> bool:
	if (_end != End.ACTIVE or now == null or duration <= 0
			or _latest.order_against(now) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
			or now.order_against(_expiry) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]):
		return false
	if _next_tick != null and _next_tick.order_against(now) not in [RealmCircleTime.Order.AFTER, RealmCircleTime.Order.SAME]:
		return false
	var proposed := now.after_ticks(duration)
	if proposed == null:
		return false
	var order := _expiry.order_against(proposed)
	if order == RealmCircleTime.Order.UNRESOLVED:
		return false
	if replace or order == RealmCircleTime.Order.BEFORE:
		_expiry = proposed
	_latest = now
	return true


## The run consumes a due entry only after it has settled its delivery.
## A miss still advances a scheduled tick.
func due_through(through: CombatInstant) -> Due:
	if _end != End.ACTIVE or through == null:
		return null
	var result := Due.new()
	result._schedule = self
	result.ordinal = _ordinal
	result.instant = _expiry
	result.kind = Kind.NATURAL_EXPIRY
	if _next_tick != null:
		match _next_tick.order_against(_expiry):
			RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME:
				result.instant = _next_tick
				result.kind = Kind.TICK
			RealmCircleTime.Order.UNRESOLVED:
				return null
	if result.instant.order_against(through) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
		return null
	return result


func settle(event: Due) -> bool:
	if not awaits(event):
		return false
	if event.kind == Kind.NATURAL_EXPIRY:
		_end = End.NATURAL
	else:
		_next_tick = _next_tick.after_ticks(_period)
		if _latest.order_against(event.instant) == RealmCircleTime.Order.BEFORE:
			_latest = event.instant
	if _ordinal < Quantity.INT_MAX:
		_ordinal += 1
	return true


func awaits(event: Due) -> bool:
	if event == null or event._schedule != self or event.instant == null or event.ordinal != _ordinal:
		return false
	var expected := due_through(event.instant)
	return (expected != null and event.kind == expected.kind
		and event.instant.order_against(expected.instant) == RealmCircleTime.Order.SAME)


func end_early(reason: End) -> bool:
	if (_end != End.ACTIVE or reason not in [End.DESTROYED, End.REPLACED, End.REALM_CLEANUP,
			End.PAYMENT_DECLINED, End.CONSUMED]):
		return false
	_end = reason
	return true
