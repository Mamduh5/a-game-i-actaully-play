class_name CombatChillLedger
extends RefCounted
## Separate owned Chill footprints, combined only as a strongest effective slow.

class Chill:
	var origin: CombatOrigin
	var begins: CombatInstant
	var latest: CombatInstant
	var expiry: CombatInstant
	var potency: Quantity

var _target: StringName
var _life: int
var _owned: Dictionary[String, Chill] = {}


static func create(target: StringName, life: int) -> CombatChillLedger:
	if target.is_empty() or life <= 0:
		return null
	var result := CombatChillLedger.new()
	result._target = target
	result._life = life
	return result


func apply(hit: CombatKernel.Hit, now: CombatInstant, potency: Quantity, duration: int) -> bool:
	if (hit == null or not hit.accepted or hit.eliminated or hit.target != _target or hit.target_life != _life
			or hit.origin == null or not hit.origin.valid_for(now) or potency == null or potency.sign_value <= 0
			or potency.compare(Quantity.from_count(1)) > 0 or duration <= 0):
		return false
	var expiry := now.after_ticks(duration)
	if expiry == null:
		return false
	var key := _key(hit.origin)
	var prior: Chill = _owned.get(key)
	if prior != null:
		if prior.latest.order_against(now) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
			return false
		match prior.expiry.order_against(now):
			RealmCircleTime.Order.UNRESOLVED: return false
			RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER:
				var extension := prior.expiry.order_against(expiry)
				if extension == RealmCircleTime.Order.UNRESOLVED:
					return false
				if extension == RealmCircleTime.Order.BEFORE:
					prior.expiry = expiry
				prior.latest = now
				return true
	var chill := Chill.new()
	chill.origin = hit.origin.copy()
	chill.begins = now
	chill.latest = now
	chill.expiry = expiry
	chill.potency = potency
	_owned[key] = chill
	return true


func owned_at(origin: CombatOrigin, at: CombatInstant) -> bool:
	return origin != null and _active(_owned.get(_key(origin)), at)


func strongest_at(at: CombatInstant, resistance: Quantity) -> Quantity:
	var one := Quantity.from_count(1)
	if at == null or resistance == null or resistance.sign_value < 0 or resistance.compare(one) > 0:
		return null
	var strongest := Quantity.from_count(0)
	for chill: Chill in _owned.values():
		if (chill.begins.order_against(at) == RealmCircleTime.Order.UNRESOLVED
				or at.order_against(chill.expiry) == RealmCircleTime.Order.UNRESOLVED):
			return null
		if _active(chill, at) and chill.potency.compare(strongest) > 0:
			strongest = chill.potency
	return strongest.multiply(one.subtract(resistance))


static func _active(chill: Chill, at: CombatInstant) -> bool:
	return (chill != null and at != null and chill.begins.order_against(at) in [
		RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
		and at.order_against(chill.expiry) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


static func _key(origin: CombatOrigin) -> String:
	return "%d/%s" % [origin.provenance, origin.owner]
