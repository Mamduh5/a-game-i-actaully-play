class_name CombatantState
extends RefCounted
## Fixed-step combat state. Life IDs distinguish repeated encounters with the
## same actor. Barrier order is supplied by the survival rule owner.

class Barrier:
	var id: StringName
	var mask: int
	var pool: QuantityLayerLedger.Pool

	func copy() -> Barrier:
		var result := Barrier.new()
		result.id = id
		result.mask = mask
		result.pool = QuantityLayerLedger.Pool.new(pool.amount, pool.error)
		return result

class Defense:
	var rating := Quantity.from_count(0)
	var reduction := Quantity.from_count(0)
	var vulnerability := Quantity.from_count(1)
	var immune: bool

	func is_valid() -> bool:
		return (rating != null and rating.sign_value >= 0 and reduction != null and reduction.sign_value >= 0
			and vulnerability != null and vulnerability.sign_value >= 0)

	func copy() -> Defense:
		var result := Defense.new()
		result.rating = rating
		result.reduction = reduction
		result.vulnerability = vulnerability
		result.immune = immune
		return result

var id: StringName
var realm: StringName
var life: int
var owner: StringName
var provenance: CombatOrigin.Provenance
var hp: QuantityLayerLedger.Pool
var barriers: Array[Barrier] = []
var physical := Defense.new()
var magical := Defense.new()
var prevents_hit: bool
var statuses: Dictionary[StringName, int] = {}
var _rates: Dictionary[int, QuantityRateCursor] = {}


func is_valid() -> bool:
	if (id.is_empty() or realm.is_empty() or life <= 0 or owner.is_empty()
			or provenance not in [CombatOrigin.Provenance.SEAT, CombatOrigin.Provenance.SPAWN]
			or not _valid_pool(hp) or physical == null or not physical.is_valid()
			or magical == null or not magical.is_valid()):
		return false
	var zero := QuantityFraction.from_amount(Quantity.from_count(0))
	var expected := QuantityErrorBounds.Sign.ABOVE if is_alive() else QuantityErrorBounds.Sign.EQUAL
	if hp.error.certify_after(hp.amount, zero) != expected:
		return false
	var layers: Dictionary[StringName, bool] = {}
	for barrier: Barrier in barriers:
		if (barrier == null or barrier.id.is_empty() or layers.has(barrier.id) or barrier.mask <= 0
				or barrier.mask > (CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL)
				or not _valid_pool(barrier.pool) or barrier.pool.amount.sign_value == 0):
			return false
		layers[barrier.id] = true
	return true


func is_alive() -> bool:
	return hp.amount.sign_value > 0


func copy() -> CombatantState:
	var result := CombatantState.new()
	result.id = id
	result.realm = realm
	result.life = life
	result.owner = owner
	result.provenance = provenance
	result.hp = QuantityLayerLedger.Pool.new(hp.amount, hp.error)
	result.physical = physical.copy()
	result.magical = magical.copy()
	result.prevents_hit = prevents_hit
	result.statuses = statuses.duplicate()
	for barrier: Barrier in barriers:
		result.barriers.append(barrier.copy())
	for kind: int in _rates:
		result._rates[kind] = _rates[kind].copy()
	return result


func post_rate(kind: CombatAction.Damage, raw: QuantityFraction) -> Quantity:
	if raw.numerator.sign_value == 0:
		_rates.erase(kind)
		return raw.numerator
	var rate: QuantityRateCursor = _rates.get(kind)
	if rate == null or not rate.matches_rate(raw.numerator, raw.divisor):
		rate = QuantityRateCursor.create(raw.numerator, raw.divisor)
		if rate == null:
			return null
		_rates[kind] = rate
	return rate.next_debit()


func end_rates(mask: int) -> void:
	for kind: int in _rates.keys():
		if mask & kind:
			_rates.erase(kind)


static func _valid_pool(pool: QuantityLayerLedger.Pool) -> bool:
	return pool != null and pool.amount != null and pool.amount.sign_value >= 0 and pool.error != null
