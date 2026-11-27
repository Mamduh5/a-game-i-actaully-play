class_name CombatMineCharge
extends RefCounted
## One placed mine's authored charge curve and one-shot lifecycle.

enum End { LIVE, DETONATED, EXPIRED, REMOVED }

var _armed: CombatInstant
var _expiry: CombatInstant
var _base: Quantity
var _gain_per_tick: Quantity
var _cap: Quantity
var _end: End
var _last_compressed: int = -1

func armed_at(at: CombatInstant) -> bool:
	return (_end == End.LIVE and at != null and _armed.order_against(at) in [
		RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


## Placement is tick-bound. Compression advances arming, preserving its
## original expiry and the real elapsed waiting time after it actually arms.
func compress_arming(tick: int) -> void:
	if _end == End.LIVE and tick > _last_compressed and tick < _armed.tick and _armed.proof_snapshot().latest == 0.0:
		_armed = CombatInstant.at_tick(_armed.tick - 1)
		_last_compressed = tick

var end_reason: End:
	get: return _end


static func create(placed: CombatInstant, arm_delay: int, lifetime: int,
		base: Quantity, gain_per_tick: Quantity, cap: Quantity) -> CombatMineCharge:
	if (placed == null or arm_delay < 0 or lifetime <= arm_delay or base == null or base.sign_value < 0
			or gain_per_tick == null or gain_per_tick.sign_value < 0 or cap == null or cap.compare(base) < 0):
		return null
	var armed := placed.after_ticks(arm_delay)
	var expiry := placed.after_ticks(lifetime)
	if armed == null or expiry == null:
		return null
	var result := CombatMineCharge.new()
	result._armed = armed
	result._expiry = expiry
	result._base = base
	result._gain_per_tick = gain_per_tick
	result._cap = cap
	return result


## The delivery owner submits the certified trigger instant. An armed mine
## has no extra minimum wait to reach a given charge.
func detonate(at: CombatInstant) -> Quantity:
	var charged := potency_at(at)
	if charged != null:
		_end = End.DETONATED
	return charged


func potency_at(at: CombatInstant) -> Quantity:
	if (_end != End.LIVE or at == null
			or _armed.order_against(at) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
			or at.order_against(_expiry) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]):
		return null
	var elapsed := at.completed_ticks_since(_armed)
	if elapsed < 0:
		return null
	var addition := _gain_per_tick.multiply(Quantity.from_count(elapsed))
	if addition == null:
		return null
	var room := _cap.subtract(_base)
	if room == null:
		return null
	return _cap if addition.compare(room) >= 0 else _base.add(addition)


## Run after delivery through the deadline, including a valid deadline trigger.
func expire(through: CombatInstant) -> bool:
	if (_end != End.LIVE or through == null
			or _expiry.order_against(through) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]):
		return false
	_end = End.EXPIRED
	return true


func remove() -> bool:
	if _end != End.LIVE:
		return false
	_end = End.REMOVED
	return true
