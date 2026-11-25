class_name CombatRootQueue
extends RefCounted
## Pending committed roots. This queue never spends claims or publishes a wave.

class Root:
	var origin: CombatOrigin
	var due: CombatInstant

class Wave:
	var due: CombatInstant
	var origins: Array[CombatOrigin] = []

enum Result { ACCEPTED, INVALID, REPEATED, CLOSED_INSTANT }

var _roots: Array[Root] = []
var _pending_keys: Dictionary[String, bool] = {}
var _closed: CombatInstant


## Admission receives an already verified commitment. New actions from dead
## actors and future work created by dead owners are distinguished by the caller.
func admit(origin: CombatOrigin, due: CombatInstant) -> Result:
	if origin == null or not origin.valid_for(due):
		return Result.INVALID
	if _closed != null and _closed.order_against(due) != RealmCircleTime.Order.BEFORE:
		return Result.CLOSED_INSTANT
	var key := origin.occurrence_key()
	if _pending_keys.has(key):
		return Result.REPEATED
	var entry := Root.new()
	entry.origin = origin.copy()
	entry.due = due
	_roots.append(entry)
	_pending_keys[key] = true
	return Result.ACCEPTED


## Null means no available certified wave. No entry is removed while ordering.
func earliest_wave() -> Wave:
	if _roots.is_empty():
		return null
	var first := _roots[0].due
	for root: Root in _roots:
		if root.due.order_against(first) == RealmCircleTime.Order.BEFORE:
			first = root.due
	var result := Wave.new()
	result.due = first
	for root: Root in _roots:
		match root.due.order_against(first):
			RealmCircleTime.Order.SAME:
				result.origins.append(root.origin.copy())
			RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.UNRESOLVED:
				return null
	result.origins.sort_custom(func(left: CombatOrigin, right: CombatOrigin) -> bool:
		return left.canonical_before(right))
	return result


func pending_count() -> int:
	return _roots.size()


## Call only after the whole group has closed. A stale or incomplete wave
## cannot advance the queue.
func close(wave: Wave) -> bool:
	var current := earliest_wave()
	if (wave == null or wave.due == null or current == null
			or wave.due.order_against(current.due) != RealmCircleTime.Order.SAME
			or wave.origins.size() != current.origins.size()):
		return false
	for index: int in current.origins.size():
		if wave.origins[index] == null or wave.origins[index].occurrence_key() != current.origins[index].occurrence_key():
			return false
	var future: Array[Root] = []
	for root: Root in _roots:
		if root.due.order_against(current.due) == RealmCircleTime.Order.SAME:
			_pending_keys.erase(root.origin.occurrence_key())
		else:
			future.append(root)
	_roots = future
	_closed = current.due
	return true
