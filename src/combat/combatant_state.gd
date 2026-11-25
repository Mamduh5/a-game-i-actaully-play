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
var max_hp: Quantity
var barriers: Array[Barrier] = []
var physical := Defense.new()
var magical := Defense.new()
var prevents_hit: bool
var statuses: Dictionary[StringName, int] = {}
var resources: Dictionary[StringName, Quantity] = {}
var follow_ups: Array[CombatFollowUp] = []
var _rates: Dictionary[int, QuantityRateCursor] = {}
var _ready_at: Dictionary[StringName, CombatInstant] = {}


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
	if max_hp != null and (max_hp.sign_value <= 0 or hp.amount.compare(max_hp) > 0):
		return false
	for status: StringName in statuses:
		if status.is_empty() or statuses[status] <= 0:
			return false
	var rules: Dictionary[StringName, bool] = {}
	for follow_up: CombatFollowUp in follow_ups:
		if follow_up == null or not follow_up.is_valid() or rules.has(follow_up.id):
			return false
		rules[follow_up.id] = true
	for resource: StringName in resources:
		var value := resources[resource]
		if resource.is_empty() or value == null or value.sign_value < 0:
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
	result.max_hp = max_hp
	result.physical = physical.copy()
	result.magical = magical.copy()
	result.prevents_hit = prevents_hit
	result.statuses = statuses.duplicate()
	result.resources = resources.duplicate()
	for follow_up: CombatFollowUp in follow_ups:
		result.follow_ups.append(follow_up.copy())
	result._ready_at = _ready_at.duplicate()
	for barrier: Barrier in barriers:
		result.barriers.append(barrier.copy())
	for kind: int in _rates:
		result._rates[kind] = _rates[kind].copy()
	return result


## Conservative exact cap check against the existing physical HP posting error.
func recover_hp(amount: Quantity) -> bool:
	if not is_alive() or max_hp == null:
		return true
	var next := hp.amount.add(amount)
	if next == null:
		return false
	match hp.error.certify_after(next, QuantityFraction.from_amount(max_hp)):
		QuantityErrorBounds.Sign.ABOVE, QuantityErrorBounds.Sign.EQUAL:
			hp = QuantityLayerLedger.Pool.new(max_hp, QuantityErrorBounds.new())
		QuantityErrorBounds.Sign.BELOW:
			var represented := next if next.compare(max_hp) <= 0 else max_hp
			var error := hp.error.after_change(QuantityFraction.from_amount(next), represented)
			if error == null:
				return false
			hp = QuantityLayerLedger.Pool.new(represented, error)
		_:
			return false
	return true


## All resource costs and cooldown readiness settle together. A rejected
## draft leaves the exact represented resources and next-ready time intact.
func pay_activation(action: CombatAction) -> bool:
	if action.activation_costs.is_empty() and action.cooldown.is_empty():
		return true
	var now := action.origin.committed_at
	var last_ready: CombatInstant = _ready_at.get(action.cooldown)
	if last_ready != null:
		var order := last_ready.order_against(now)
		if order not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
			return false
	var next_ready := now.after_ticks(action.cooldown_ticks)
	if next_ready == null:
		return false
	var remainder := resources.duplicate()
	for resource: StringName in action.activation_costs:
		var cost := action.activation_costs[resource]
		if cost.sign_value == 0:
			continue
		var available: Quantity = remainder.get(resource)
		if available == null or available.compare(cost) < 0:
			return false
		var after := available.subtract(cost)
		if after == null:
			return false
		remainder[resource] = after
	resources = remainder
	if not action.cooldown.is_empty():
		_ready_at[action.cooldown] = next_ready
	return true


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
