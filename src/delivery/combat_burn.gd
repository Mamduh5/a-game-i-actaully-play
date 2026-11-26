class_name CombatBurn
extends RefCounted
## One owner's continuous Burn on one target life. Potency and tick phase
## persist across ordinary refresh. Only a stronger transfer can replace it.

class Tick:
	var _burn: CombatBurn
	var _revision: int
	var due: CombatDeliverySchedule.Due
	var unmitigated: Quantity
	var origin: CombatOrigin

var _target: StringName
var _life: int
var _origin: CombatOrigin
var _clock: CombatDeliverySchedule
var _ignition: CombatInstant
var _potency: Quantity
var _potency_intensity: Quantity
var _growth: Quantity
var _maximum: Quantity
var _revision: int


static func ignite(hit: CombatKernel.Hit, now: CombatInstant, potency: Quantity,
		duration: int, period: int, intensity_per_tick: Quantity, maximum_intensity: Quantity) -> CombatBurn:
	if (not _accepted(hit, now) or potency == null or potency.sign_value <= 0
			or intensity_per_tick == null or intensity_per_tick.sign_value < 0 or maximum_intensity == null
			or maximum_intensity.compare(Quantity.from_count(1)) < 0):
		return null
	var clock := CombatDeliverySchedule.create(now, duration, period)
	if clock == null:
		return null
	var result := CombatBurn.new()
	result._clock = clock
	result._ignition = now
	result._target = hit.target
	result._life = hit.target_life
	result._origin = hit.origin.copy()
	result._potency = potency
	result._growth = intensity_per_tick
	result._maximum = maximum_intensity
	return result


func active_for(owner: CombatOrigin, at: CombatInstant) -> bool:
	return (owner != null and owner.owner == _origin.owner and owner.provenance == _origin.provenance
		and _clock.active_at(at))


func refresh(hit: CombatKernel.Hit, now: CombatInstant, duration: int) -> bool:
	return (_accepted(hit, now) and hit.target == _target and hit.target_life == _life
		and active_for(hit.origin, now) and _clock.refresh(now, duration))


## The amount is the donor's bounded, already intensity-adjusted tick.
## Anchor it to the receiver's next cadence instant and retain later growth.
func transfer(cause: CombatOrigin, now: CombatInstant, duration: int, next_unmitigated: Quantity) -> bool:
	if not active_for(cause, now) or not cause.valid_for(now) or next_unmitigated == null:
		return false
	var intensity := _intensity_at(_clock.next_tick)
	var current := _tick_amount(intensity)
	if current == null or next_unmitigated.compare(current) <= 0:
		return false
	if not _clock.replace_remaining(now, duration):
		return false
	_potency = next_unmitigated
	_potency_intensity = intensity
	_revision += 1
	return true


func due_through(through: CombatInstant) -> Tick:
	var event := _clock.due_through(through)
	if event == null:
		return null
	var result := Tick.new()
	result._burn = self
	result._revision = _revision
	result.due = event
	result.origin = _origin.copy()
	if event.kind == CombatDeliverySchedule.Kind.TICK:
		result.unmitigated = _tick_amount(_intensity_at(event.instant))
		if result.unmitigated == null:
			return null
	return result


func settle(tick: Tick) -> bool:
	return tick != null and tick._burn == self and tick._revision == _revision and _clock.settle(tick.due)


func _intensity_at(instant: CombatInstant) -> Quantity:
	if instant == null:
		return null
	var age := instant.completed_ticks_since(_ignition)
	if age < 0:
		return null
	var growth := _growth.multiply(Quantity.from_count(age))
	var intensity := Quantity.from_count(1).add(growth) if growth != null else null
	if intensity != null and intensity.compare(_maximum) > 0:
		return _maximum
	return intensity


func _tick_amount(intensity: Quantity) -> Quantity:
	if intensity == null:
		return null
	if _potency_intensity == null:
		return _potency.multiply(intensity)
	if intensity.compare(_potency_intensity) == 0:
		return _potency
	return Quantity.quantize_ratio(_potency.multiply(intensity), _potency_intensity)


static func _accepted(hit: CombatKernel.Hit, now: CombatInstant) -> bool:
	return (hit != null and hit.accepted and not hit.eliminated and not hit.target.is_empty() and hit.target_life > 0
		and hit.origin != null and hit.origin.valid_for(now))
