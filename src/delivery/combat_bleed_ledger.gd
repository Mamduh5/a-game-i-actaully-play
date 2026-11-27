class_name CombatBleedLedger
extends RefCounted
## Owned status state for one target life. Only an accepted application can
## create a stack. A reapplication keeps existing snapshots and tick phase.

class Stack:
	var source: StringName
	var source_life: int
	var origin: CombatOrigin
	var offense: CombatAction.Component
	var id: String

	func copy() -> Stack:
		var result := Stack.new()
		result.id = id
		result.source = source
		result.source_life = source_life
		result.origin = origin.copy()
		result.offense = offense.copy()
		return result

class Application:
	var duration: int
	var period: int
	var capacity: int
	var offense: CombatAction.Component

	func is_valid() -> bool:
		return (duration > 0 and period > 0 and capacity > 0 and offense != null
			and offense.is_valid() and offense.kind == CombatAction.Damage.PHYSICAL)

	func copy() -> Application:
		var result := Application.new()
		result.duration = duration
		result.period = period
		result.capacity = capacity
		result.offense = offense.copy()
		return result

class Owner:
	var cadence: CombatDeliverySchedule
	var stacks: Array[Stack] = []

class Prestate:
	var _target: CombatBleedLedger
	var _instant: CombatInstant
	var _stacks: Dictionary[String, Dictionary] = {}

	func has_owner(origin: CombatOrigin) -> bool:
		return _stacks.has(CombatBleedLedger._owner_key(origin))

class Tick:
	var _cadence: CombatDeliverySchedule
	var _owner: String
	var event: CombatDeliverySchedule.Due
	var stacks: Array[Stack] = []

var _target: StringName
var _life: int
var _owners: Dictionary[String, Owner] = {}
var _latest_application: CombatInstant
var _applied_at_instant: Dictionary[String, bool] = {}


func copy() -> CombatBleedLedger:
	var result := create(_target, _life)
	result._latest_application = _latest_application
	result._applied_at_instant = _applied_at_instant.duplicate()
	for key: String in _owners:
		var entry := Owner.new()
		entry.cadence = _owners[key].cadence.copy()
		entry.stacks = _owners[key].stacks.duplicate()
		result._owners[key] = entry
	return result


func deadlines() -> Array[CombatInstant]:
	var result: Array[CombatInstant] = []
	for entry: Owner in _owners.values():
		var next := entry.cadence.next_event()
		result.append(next.instant if next != null else null)
	return result


func owners() -> Array[String]:
	return _owners.keys()


func compress_owner(provenance: CombatOrigin.Provenance, owner: StringName, tick: int) -> void:
	var entry: Owner = _owners.get("%d/%s" % [provenance, owner])
	if entry != null:
		entry.cadence.compress_step(tick)


func stack_count() -> int:
	var count := 0
	for entry: Owner in _owners.values():
		count += entry.stacks.size()
	return count


static func create(target: StringName, life: int) -> CombatBleedLedger:
	if target.is_empty() or life <= 0:
		return null
	var ledger := CombatBleedLedger.new()
	ledger._target = target
	ledger._life = life
	return ledger


func apply(hit: CombatKernel.Hit, now: CombatInstant, definition: Application) -> bool:
	if (hit == null or not hit.accepted or hit.eliminated or hit.target != _target or hit.target_life != _life
			or hit.origin == null or not hit.origin.valid_for(now) or definition == null or not definition.is_valid()):
		return false
	var order := _latest_application.order_against(now) if _latest_application != null else RealmCircleTime.Order.BEFORE
	var occurrence := hit.origin.occurrence_key()
	if (order not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
			or (order == RealmCircleTime.Order.SAME and _applied_at_instant.has(occurrence))):
		return false
	var owner := _owner_key(hit.origin)
	var entry: Owner = _owners.get(owner)
	if entry == null:
		entry = Owner.new()
		entry.cadence = CombatDeliverySchedule.create(now, definition.duration, definition.period)
		if entry.cadence == null:
			return false
		_owners[owner] = entry
	elif not entry.cadence.refresh(now, definition.duration):
		return false
	if entry.stacks.size() < definition.capacity:
		var stack := Stack.new()
		stack.id = occurrence
		stack.source = hit.source
		stack.source_life = hit.source_life
		stack.origin = hit.origin.copy()
		stack.offense = definition.offense.copy()
		entry.stacks.append(stack)
	if order == RealmCircleTime.Order.BEFORE:
		_applied_at_instant.clear()
		_latest_application = now
	_applied_at_instant[occurrence] = true
	return true


func capture(now: CombatInstant) -> Prestate:
	var result := Prestate.new()
	result._target = self
	result._instant = now
	for owner: String in _owners:
		var entry := _owners[owner]
		if entry.cadence.active_at(now):
			var visible: Dictionary[String, bool] = {}
			for stack: Stack in entry.stacks:
				visible[stack.id] = true
			result._stacks[owner] = visible
	return result


## PR10 rechecks the owner's finite stacks in the captured pre-impact set.
func consume(origin: CombatOrigin, captured: Prestate, now: CombatInstant, maximum: int) -> Array[Stack]:
	var claimed: Array[Stack] = []
	if (origin == null or not origin.valid_for(now) or captured == null or captured._target != self
			or captured._instant == null or maximum <= 0 or captured._instant.order_against(now) not in [
				RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]):
		return claimed
	var owner := _owner_key(origin)
	var entry: Owner = _owners.get(owner)
	if entry == null or not entry.cadence.active_at(now) or not captured._stacks.has(owner):
		return claimed
	var visible: Dictionary = captured._stacks[owner]
	var kept: Array[Stack] = []
	for stack: Stack in entry.stacks:
		if claimed.size() < maximum and stack.id in visible:
			claimed.append(stack.copy())
		else:
			kept.append(stack)
	entry.stacks = kept
	if entry.stacks.is_empty():
		entry.cadence.end_early(CombatDeliverySchedule.End.CONSUMED)
		_owners.erase(owner)
	return claimed


func due_for(origin: CombatOrigin, through: CombatInstant) -> Tick:
	if origin == null:
		return null
	return due_for_owner(_owner_key(origin), through)


func due_for_owner(owner: String, through: CombatInstant) -> Tick:
	var entry: Owner = _owners.get(owner)
	if entry == null:
		return null
	var event := entry.cadence.due_through(through)
	if event == null:
		return null
	var result := Tick.new()
	result._owner = owner
	result._cadence = entry.cadence
	result.event = event
	if event.kind == CombatDeliverySchedule.Kind.TICK:
		for stack: Stack in entry.stacks:
			result.stacks.append(stack.copy())
	return result


func settle(tick: Tick) -> bool:
	if tick == null:
		return false
	var entry: Owner = _owners.get(tick._owner)
	if entry == null or entry.cadence != tick._cadence or not entry.cadence.settle(tick.event):
		return false
	if entry.cadence.end_reason == CombatDeliverySchedule.End.NATURAL:
		_owners.erase(tick._owner)
	return true


static func _owner_key(origin: CombatOrigin) -> String:
	return "%d/%s" % [origin.provenance, origin.owner]
