class_name CombatDelivery
extends RefCounted
## One paid commitment and its certified contacts. Target cadence belongs to
## the delivery, so leaving a field or refreshing it cannot reset the clock.

enum Result { ADMITTED, CADENCE, CLOSED, INVALID, UNRESOLVED }
enum PulseResult { INVALID, PAID, DECLINED }

class SweepPlan:
	var revision: int
	var blocker: RealmGeometry.Contact
	var contacts: Array[RealmGeometry.Contact] = []
	var finish: RealmSweep.Point

class PulseStart:
	var result: PulseResult
	var delivery: CombatDelivery

var _kernel: CombatKernel
var _commitment: String
var _realm: StringName
var _source: StringName
var _target_interval: int
var _once_per_target: bool
var _last_contact: Dictionary[String, CombatInstant] = {}
var _next_part := 1


static func activate(kernel: CombatKernel, action: CombatAction, realm: StringName,
		target_interval: int = 0, once_per_target: bool = false) -> CombatDelivery:
	if kernel == null or action == null or action.hp_cost != null or realm.is_empty() or target_interval < 0:
		return null
	var actor := kernel.actor_snapshot(action.source)
	if actor == null or actor.realm != realm:
		return null
	return _commit_delivery(kernel, action, realm, target_interval, once_per_target)


static func _commit_delivery(kernel: CombatKernel, action: CombatAction, realm: StringName,
		target_interval: int, once_per_target: bool) -> CombatDelivery:
	var key := kernel.commit(action)
	if key.is_empty():
		return null
	var result := CombatDelivery.new()
	result._kernel = kernel
	result._realm = realm
	result._source = action.source
	result._commitment = key
	result._target_interval = target_interval
	result._once_per_target = once_per_target
	return result


## Called at the run's open payment boundary for a separate priced interval.
## Contacts from earlier paid intervals survive a later payment refusal.
static func activate_pulse(schedule: CombatDeliverySchedule, due: CombatDeliverySchedule.Due,
		kernel: CombatKernel, action: CombatAction, realm: StringName) -> PulseStart:
	var started := PulseStart.new()
	if (schedule == null or not schedule.awaits(due) or due.kind != CombatDeliverySchedule.Kind.TICK
			or kernel == null or action == null or action.hp_cost != null or not action.is_valid() or realm.is_empty()
			or due.instant.order_against(action.origin.committed_at) != RealmCircleTime.Order.SAME):
		return started
	var source := kernel.actor_snapshot(action.source)
	if (source == null or source.realm != realm or source.life != action.source_life
			or source.owner != action.origin.owner or source.provenance != action.origin.provenance):
		return started
	started.delivery = _commit_delivery(kernel, action, realm, 0, false)
	if started.delivery == null:
		schedule.end_early(CombatDeliverySchedule.End.PAYMENT_DECLINED)
		started.result = PulseResult.DECLINED
	else:
		schedule.settle(due)
		started.result = PulseResult.PAID
	return started


## Authoritative delivery submits a separate sweep for each realized interval.
## Interception wins an equal-time contact and unresolved shape order fails
## before any contact or target cadence is posted.
func plan_sweep(geometry: RealmGeometry, start: RealmSweep.Point, finish: RealmSweep.Point,
		radius: float, target_mask: int, blocker_mask: int = 0, clip_to_blocker: bool = false) -> SweepPlan:
	if (_commitment.is_empty() or geometry == null or geometry.realm_id != _realm
			or target_mask <= 0 or blocker_mask < 0):
		return null
	var plan := SweepPlan.new()
	plan.revision = geometry.revision
	plan.finish = finish
	if blocker_mask > 0:
		var blockers := geometry.certify_circle_sweep(_realm, start, finish, radius, blocker_mask, _source)
		if blockers == null or not blockers.unresolved.is_empty():
			return null
		for candidate: RealmGeometry.Contact in blockers.contacts:
			if plan.blocker == null:
				plan.blocker = candidate
				continue
			match _contact_order(candidate, plan.blocker):
				RealmCircleTime.Order.BEFORE: plan.blocker = candidate
				RealmCircleTime.Order.UNRESOLVED: return null
		if clip_to_blocker and plan.blocker != null:
			plan.finish = geometry.clipped_sweep_finish(start, finish, plan.blocker, radius, blocker_mask, _source)
			if plan.finish == null:
				return null
	var targets := geometry.certify_circle_sweep(_realm, start, finish, radius, target_mask, _source)
	if targets == null or not targets.unresolved.is_empty():
		return null
	for target: RealmGeometry.Contact in targets.contacts:
		if plan.blocker != null:
			match target.proof.order_against(plan.blocker.proof):
				RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER: continue
				RealmCircleTime.Order.UNRESOLVED: return null
		if not _insert_contact(plan.contacts, target):
			return null
	return plan


func admit(start_tick: int, contact: RealmGeometry.Contact, target_life: int, hostile: bool,
		phase: int = 0, position: RealmSweep.Point = null) -> Result:
	if _commitment.is_empty():
		return Result.CLOSED
	if contact == null or contact.entity.is_empty() or target_life <= 0 or phase < 0 or _next_part == Quantity.INT_MAX:
		return Result.INVALID
	var due := CombatInstant.at_contact(start_tick, contact.proof)
	if due == null:
		return Result.UNRESOLVED
	var key := "%d:%s/%d/%d" % [contact.entity.length(), contact.entity, target_life, phase]
	var prior: CombatInstant = _last_contact.get(key)
	if prior != null:
		var order := prior.order_against(due)
		if order == RealmCircleTime.Order.UNRESOLVED:
			return Result.UNRESOLVED
		if _once_per_target or order != RealmCircleTime.Order.BEFORE:
			return Result.CADENCE
		if _target_interval > 0:
			var ready := prior.after_ticks(_target_interval)
			if ready == null:
				return Result.CADENCE
			match ready.order_against(due):
				RealmCircleTime.Order.AFTER: return Result.CADENCE
				RealmCircleTime.Order.UNRESOLVED: return Result.UNRESOLVED
	match _kernel.admit_contact(_commitment, _next_part, _realm, start_tick, contact, target_life, hostile, position):
		CombatRootQueue.Result.ACCEPTED:
			_next_part += 1
			_last_contact[key] = due
			return Result.ADMITTED
		CombatRootQueue.Result.CLOSED_INSTANT:
			return Result.CLOSED
		_:
			return Result.INVALID


func finish() -> bool:
	if _commitment.is_empty() or not _kernel.finish_delivery(_commitment):
		return false
	_commitment = ""
	return true


static func _insert_contact(ordered: Array[RealmGeometry.Contact], candidate: RealmGeometry.Contact) -> bool:
	var lower := 0
	var upper := ordered.size()
	while lower < upper:
		var middle := (lower + upper) >> 1
		match _contact_order(candidate, ordered[middle]):
			RealmCircleTime.Order.BEFORE: upper = middle
			RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER: lower = middle + 1
			RealmCircleTime.Order.UNRESOLVED: return false
	ordered.insert(lower, candidate)
	return true


static func _contact_order(left: RealmGeometry.Contact, right: RealmGeometry.Contact) -> RealmCircleTime.Order:
	var order := left.proof.order_against(right.proof)
	if order != RealmCircleTime.Order.SAME:
		return order
	if left.entity != right.entity:
		return RealmCircleTime.Order.BEFORE if String(left.entity) < String(right.entity) else RealmCircleTime.Order.AFTER
	if left.shape != right.shape:
		return RealmCircleTime.Order.BEFORE if left.shape < right.shape else RealmCircleTime.Order.AFTER
	return RealmCircleTime.Order.SAME
