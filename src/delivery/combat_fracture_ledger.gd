class_name CombatFractureLedger
extends RefCounted
## Owned Fracture stacks with one shared defense-reduction limit.

class Rule:
	var capacity: int
	var duration: int
	var reduction_per_stack: Quantity
	var exposure_at_capacity: Quantity

class Owned:
	var stacks: int
	var rule: Rule
	var begins: CombatInstant
	var applied: CombatInstant
	var expiry: CombatInstant
	var _applications: Dictionary[String, bool] = {}

class Effective:
	var reduction: Quantity
	var exposure: Quantity

var _target: StringName
var _life: int
var _limit: Quantity
var _owners: Dictionary[String, Owned] = {}


static func create(target: StringName, life: int, limit: Quantity) -> CombatFractureLedger:
	if target.is_empty() or life <= 0 or limit == null or limit.sign_value <= 0 or limit.compare(Quantity.from_count(1)) > 0:
		return null
	var result := CombatFractureLedger.new()
	result._target = target
	result._life = life
	result._limit = limit
	return result


func apply(hit: CombatKernel.Hit, at: CombatInstant, rule: Rule) -> bool:
	if (hit == null or not hit.accepted or hit.eliminated or hit.target != _target or hit.target_life != _life
			or hit.origin == null or not hit.origin.valid_for(at) or rule == null or rule.capacity <= 0
			or rule.duration <= 0 or rule.reduction_per_stack == null or rule.reduction_per_stack.sign_value <= 0
			or rule.exposure_at_capacity == null or rule.exposure_at_capacity.sign_value < 0):
		return false
	var expiry := at.after_ticks(rule.duration)
	if expiry == null:
		return false
	var key := _key(hit.origin)
	var occurrence := hit.origin.occurrence_key()
	var prior: Owned = _owners.get(key)
	if prior != null:
		var order := prior.applied.order_against(at)
		if (order not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
				or (order == RealmCircleTime.Order.SAME and prior._applications.has(occurrence))):
			return false
		var expiration := prior.expiry.order_against(at)
		if expiration == RealmCircleTime.Order.UNRESOLVED:
			return false
		if expiration != RealmCircleTime.Order.BEFORE:
			var extension := prior.expiry.order_against(expiry)
			if extension == RealmCircleTime.Order.UNRESOLVED:
				return false
			if prior.stacks < prior.rule.capacity:
				prior.stacks += 1
			if extension == RealmCircleTime.Order.BEFORE:
				prior.expiry = expiry
			if order == RealmCircleTime.Order.BEFORE:
				prior._applications.clear()
			prior._applications[occurrence] = true
			prior.applied = at
			return true
	var entry := Owned.new()
	entry.stacks = 1
	entry.begins = at
	entry.applied = at
	entry.expiry = expiry
	entry._applications[occurrence] = true
	entry.rule = Rule.new()
	entry.rule.capacity = rule.capacity
	entry.rule.duration = rule.duration
	entry.rule.reduction_per_stack = rule.reduction_per_stack
	entry.rule.exposure_at_capacity = rule.exposure_at_capacity
	_owners[key] = entry
	return true


func stacks_for(origin: CombatOrigin, at: CombatInstant) -> int:
	if origin == null or at == null:
		return 0
	var owned: Owned = _owners.get(_key(origin))
	return owned.stacks if owned != null and _present(owned, at) else 0


func effective_at(at: CombatInstant) -> Effective:
	if at == null:
		return null
	var remaining := _limit
	var result := Effective.new()
	result.exposure = Quantity.from_count(0)
	var owners := _owners.keys()
	owners.sort()
	for id: String in owners:
		var owned := _owners[id]
		if (owned.begins.order_against(at) == RealmCircleTime.Order.UNRESOLVED
				or at.order_against(owned.expiry) == RealmCircleTime.Order.UNRESOLVED):
			return null
		if not _present(owned, at):
			continue
		if owned.stacks == owned.rule.capacity and owned.rule.exposure_at_capacity.compare(result.exposure) > 0:
			result.exposure = owned.rule.exposure_at_capacity
		if remaining.sign_value > 0:
			var reduction := owned.rule.reduction_per_stack.multiply(Quantity.from_count(owned.stacks))
			if reduction == null:
				return null
			remaining = Quantity.from_count(0) if reduction.compare(remaining) >= 0 else remaining.subtract(reduction)
			if remaining == null:
				return null
	result.reduction = _limit.subtract(remaining)
	return result if result.reduction != null else null


static func _present(owned: Owned, at: CombatInstant) -> bool:
	return (owned.begins.order_against(at) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
		and at.order_against(owned.expiry) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


static func _key(origin: CombatOrigin) -> String:
	return "%d/%s" % [origin.provenance, origin.owner]
