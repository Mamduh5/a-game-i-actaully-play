class_name CombatantState
extends RefCounted
## Fixed-step combat state. Life IDs distinguish repeated encounters with the
## same actor. Barrier insertion order is their acquisition age.

class Barrier:
	var id: StringName
	var mask: int
	var pool: QuantityLayerLedger.Pool
	var expires: CombatInstant
	var generation := 1

	func copy() -> Barrier:
		var result := Barrier.new()
		result.id = id
		result.mask = mask
		result.pool = QuantityLayerLedger.Pool.new(pool.amount, pool.error)
		result.expires = expires
		result.generation = generation
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
var realm_visit: int
var life: int
var owner: StringName
var controller: StringName
var provenance: CombatOrigin.Provenance
var hp: QuantityLayerLedger.Pool
var max_hp: Quantity
var barriers: Array[Barrier] = []
var barrier_on_elimination: CombatAction.BarrierGrant
var physical := Defense.new()
var magical := Defense.new()
var prevents_hit: bool
var displacement_resistance: float = 0.0
var accepts_new_actions := true
var revival_protected_until: CombatInstant
var statuses: Dictionary[StringName, int] = {}
var resources: Dictionary[StringName, Quantity] = {}
var follow_ups: Array[CombatFollowUp] = []
var _rates: Dictionary[int, QuantityRateCursor] = {}
var _ready_at: Dictionary[StringName, CombatInstant] = {}
var _barrier_generations: Dictionary[StringName, int] = {}


func is_valid() -> bool:
	if (id.is_empty() or realm.is_empty() or realm_visit < 0 or life <= 0 or owner.is_empty() or controller == id
			or provenance not in [CombatOrigin.Provenance.SEAT, CombatOrigin.Provenance.SPAWN]
			or not _valid_pool(hp) or physical == null or not physical.is_valid()
			or not is_finite(displacement_resistance) or displacement_resistance < 0.0 or displacement_resistance > 1.0
			or magical == null or not magical.is_valid()
			or (barrier_on_elimination != null and not barrier_on_elimination.is_valid())):
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
		if (barrier == null or barrier.id.is_empty() or layers.has(barrier.id) or barrier.mask <= 0 or barrier.generation < 1
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
	result.realm_visit = realm_visit
	result.life = life
	result.owner = owner
	result.controller = controller
	result.provenance = provenance
	result.hp = QuantityLayerLedger.Pool.new(hp.amount, hp.error)
	result.max_hp = max_hp
	result.physical = physical.copy()
	result.magical = magical.copy()
	result.prevents_hit = prevents_hit
	result.displacement_resistance = displacement_resistance
	result.accepts_new_actions = accepts_new_actions
	result.revival_protected_until = revival_protected_until
	if barrier_on_elimination != null:
		result.barrier_on_elimination = barrier_on_elimination.copy()
	result.statuses = statuses.duplicate()
	result.resources = resources.duplicate()
	for follow_up: CombatFollowUp in follow_ups:
		result.follow_ups.append(follow_up.copy())
	result._ready_at = _ready_at.duplicate()
	result._barrier_generations = _barrier_generations.duplicate()
	for barrier: Barrier in barriers:
		result.barriers.append(barrier.copy())
		result._barrier_generations[barrier.id] = maxi(int(result._barrier_generations.get(barrier.id, 0)), barrier.generation)
	for kind: int in _rates:
		result._rates[kind] = _rates[kind].copy()
	return result


## Changing a cap preserves exact current HP unless that HP must be clamped.
func change_max_hp(maximum: Quantity) -> bool:
	if maximum == null or maximum.sign_value <= 0:
		return false
	var limited := cap_pool(hp, maximum)
	if limited == null:
		return false
	hp = limited
	max_hp = maximum
	return true


func grant_barrier(grant: CombatAction.BarrierGrant, now: CombatInstant) -> Barrier:
	if grant == null or not grant.is_valid() or now == null:
		return null
	var previous: Barrier
	for layer: Barrier in barriers:
		if layer.id == grant.id:
			previous = layer
			break
	var expiry := now.after_ticks(grant.duration_ticks) if grant.duration_ticks > 0 else null
	if grant.duration_ticks > 0 and expiry == null:
		return null
	var incoming := Barrier.new()
	incoming.id = grant.id
	incoming.mask = grant.mask
	incoming.expires = expiry
	incoming.pool = QuantityLayerLedger.Pool.new(grant.capacity, QuantityErrorBounds.new())
	if grant.rule == CombatAction.BarrierRule.ACCUMULATE:
		var base := previous.pool if previous != null else QuantityLayerLedger.Pool.new(Quantity.from_count(0), QuantityErrorBounds.new())
		if previous != null and (previous.mask != grant.mask or (previous.expires == null) != (expiry == null)):
			return null
		var sum := base.amount.add(grant.capacity)
		if sum == null:
			return null
		incoming.pool = cap_pool(QuantityLayerLedger.Pool.new(sum, base.error), grant.cap)
		if incoming.pool == null:
			return null
		if previous != null:
			var order := previous.expires.order_against(expiry) if grant.refresh_lifetime else RealmCircleTime.Order.SAME
			if order == RealmCircleTime.Order.UNRESOLVED:
				return null
			previous.pool = incoming.pool
			if order == RealmCircleTime.Order.BEFORE:
				previous.expires = expiry
			return previous
	if previous != null:
		match grant.rule:
			CombatAction.BarrierRule.KEEP:
				return previous
			CombatAction.BarrierRule.STRONGEST:
				var strength := previous.pool.error.certify_after(previous.pool.amount, QuantityFraction.from_amount(grant.capacity))
				if strength == QuantityErrorBounds.Sign.UNKNOWN:
					return null
				if strength == QuantityErrorBounds.Sign.ABOVE:
					return previous
				if strength == QuantityErrorBounds.Sign.EQUAL:
					if previous.expires == null:
						return previous
					if expiry != null:
						var order := previous.expires.order_against(expiry)
						if order == RealmCircleTime.Order.UNRESOLVED:
							return null
						if order != RealmCircleTime.Order.BEFORE:
							return previous
	var sequence: int = _barrier_generations.get(grant.id, 0)
	if previous != null:
		sequence = maxi(sequence, previous.generation)
	if sequence == Quantity.INT_MAX:
		return null
	incoming.generation = sequence + 1
	_barrier_generations[grant.id] = incoming.generation
	if previous != null:
		barriers.erase(previous)
		end_rates(previous.mask | incoming.mask)
	barriers.append(incoming)
	return incoming


static func cap_pool(pool: QuantityLayerLedger.Pool, maximum: Quantity) -> QuantityLayerLedger.Pool:
	match pool.error.certify_after(pool.amount, QuantityFraction.from_amount(maximum)):
		QuantityErrorBounds.Sign.ABOVE, QuantityErrorBounds.Sign.EQUAL:
			return QuantityLayerLedger.Pool.new(maximum, QuantityErrorBounds.new())
		QuantityErrorBounds.Sign.BELOW:
			if pool.amount.compare(maximum) <= 0:
				return pool
			var error := pool.error.after_change(QuantityFraction.from_amount(pool.amount), maximum)
			return QuantityLayerLedger.Pool.new(maximum, error) if error != null else null
	return null


## All resource costs and cooldown readiness settle together. A rejected
## draft leaves the exact represented resources and next-ready time intact.
func pay_activation(action: CombatAction) -> bool:
	if action.activation_costs.is_empty() and action.cooldown.is_empty():
		return true
	var now := action.origin.committed_at
	if not cooldown_ready(action.cooldown, now):
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


func cooldown_ready(id: StringName, now: CombatInstant) -> bool:
	var last_ready: CombatInstant = _ready_at.get(id)
	return now != null and (last_ready == null or last_ready.order_against(now) in [
		RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME])


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


func rate_phases() -> Dictionary[int, String]:
	var phases: Dictionary[int, String] = {}
	for kind: int in _rates:
		var phase := _rates[kind].continuation_phase()
		if not phase.is_empty():
			phases[kind] = phase.hex_encode()
	return phases


static func _valid_pool(pool: QuantityLayerLedger.Pool) -> bool:
	return pool != null and pool.amount != null and pool.amount.sign_value >= 0 and pool.error != null
