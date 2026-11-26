class_name CombatChillLedger
extends RefCounted
## Separate owned Chill footprints, combined only as a strongest effective slow.

class Chill:
	var begins: CombatInstant
	var expiry: CombatInstant
	var potency: Quantity

class OwnerChill:
	var latest: CombatInstant
	var effects: Array[Chill] = []

var _target: StringName
var _life: int
var _owned: Dictionary[String, OwnerChill] = {}


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
	var prior: OwnerChill = _owned.get(key)
	var begins := now
	var updated := OwnerChill.new()
	updated.latest = now
	if prior != null:
		if prior.latest.order_against(now) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
			return false
		for effect: Chill in prior.effects:
			match effect.expiry.order_against(now):
				RealmCircleTime.Order.UNRESOLVED: return false
				RealmCircleTime.Order.BEFORE: continue
			if effect.potency.compare(potency) != 0:
				updated.effects.append(effect)
				continue
			match effect.expiry.order_against(expiry):
				RealmCircleTime.Order.UNRESOLVED: return false
				RealmCircleTime.Order.AFTER: expiry = effect.expiry
			begins = effect.begins
	var chill := Chill.new()
	chill.begins = begins
	chill.expiry = expiry
	chill.potency = potency
	updated.effects.append(chill)
	_owned[key] = updated
	return true


func owned_at(origin: CombatOrigin, at: CombatInstant) -> bool:
	if origin == null or at == null:
		return false
	var owned: OwnerChill = _owned.get(_key(origin))
	if owned != null:
		for effect: Chill in owned.effects:
			if _active(effect, at):
				return true
	return false


func strongest_at(at: CombatInstant, resistance: Quantity) -> Quantity:
	var one := Quantity.from_count(1)
	if at == null or resistance == null or resistance.sign_value < 0 or resistance.compare(one) > 0:
		return null
	var strongest := Quantity.from_count(0)
	for owner: OwnerChill in _owned.values():
		for chill: Chill in owner.effects:
			var begins := chill.begins.order_against(at)
			var ends := at.order_against(chill.expiry)
			if begins == RealmCircleTime.Order.UNRESOLVED or ends == RealmCircleTime.Order.UNRESOLVED:
				return null
			if begins != RealmCircleTime.Order.AFTER and ends != RealmCircleTime.Order.AFTER and chill.potency.compare(strongest) > 0:
				strongest = chill.potency
	return strongest.multiply(one.subtract(resistance))


static func _active(chill: Chill, at: CombatInstant) -> bool:
	return (chill.begins.order_against(at) in [
		RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
		and at.order_against(chill.expiry) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


static func _key(origin: CombatOrigin) -> String:
	return "%d/%s" % [origin.provenance, origin.owner]
