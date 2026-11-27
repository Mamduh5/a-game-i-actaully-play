class_name CombatAction
extends RefCounted
## The fixed-step owner supplies authored placement and other eligibility facts.
## The kernel verifies liveness, pays this activation and freezes offense.

enum Damage { PHYSICAL = 1, MAGICAL = 2 }
enum BarrierRule { KEEP, STRONGEST, ACCUMULATE }
enum Continuation { COMMITTED, LIVE_CONTROLLER }

class Component:
	var kind: Damage = Damage.PHYSICAL
	var base: Quantity
	var penetration := Quantity.from_count(0)
	var categories: Array[QuantityFormula.BonusCategory] = []

	func is_valid() -> bool:
		if (kind not in [Damage.PHYSICAL, Damage.MAGICAL] or base == null or base.sign_value < 0
				or penetration == null or penetration.sign_value < 0):
			return false
		for category: QuantityFormula.BonusCategory in categories:
			if category == null or null in category.values:
				return false
		return true

	func copy() -> Component:
		var result := Component.new()
		result.kind = kind
		result.base = base
		result.penetration = penetration
		for category: QuantityFormula.BonusCategory in categories:
			var captured := QuantityFormula.BonusCategory.new()
			captured.values = category.values.duplicate()
			result.categories.append(captured)
		return result

class BarrierGrant:
	var id: StringName
	var mask: int
	var capacity: Quantity
	var duration_ticks: int
	var rule: BarrierRule
	var cap: Quantity
	var refresh_lifetime: bool

	func is_valid() -> bool:
		if (id.is_empty() or mask <= 0 or mask > (Damage.PHYSICAL | Damage.MAGICAL)
				or capacity == null or capacity.sign_value <= 0 or duration_ticks < 0
				or rule not in BarrierRule.values()):
			return false
		if rule == BarrierRule.ACCUMULATE:
			return cap != null and cap.sign_value > 0 and (not refresh_lifetime or duration_ticks > 0)
		return cap == null and not refresh_lifetime

	func copy() -> BarrierGrant:
		var result := BarrierGrant.new()
		result.id = id
		result.mask = mask
		result.capacity = capacity
		result.duration_ticks = duration_ticks
		result.rule = rule
		result.cap = cap
		result.refresh_lifetime = refresh_lifetime
		return result

class BarrierConversion:
	## One grant from an activation's simultaneous hostile HP debits.
	var grant: BarrierGrant
	var rate: Quantity

	func is_valid() -> bool:
		return (grant != null and grant.is_valid() and grant.rule == BarrierRule.STRONGEST
			and rate != null and rate.sign_value > 0)

	func copy() -> BarrierConversion:
		var result := BarrierConversion.new()
		result.grant = grant.copy()
		result.rate = rate
		return result

class DamageRecovery:
	var id: StringName
	var rate: QuantityFraction
	var limit: Quantity
	var amplification: QuantityFraction
	var admits_excess: bool

	func is_valid() -> bool:
		return (not id.is_empty() and rate != null and rate.numerator.sign_value > 0
			and limit != null and limit.sign_value > 0
			and amplification != null and amplification.numerator.sign_value > 0)

	func copy() -> DamageRecovery:
		var result := DamageRecovery.new()
		result.id = id
		result.rate = rate
		result.limit = limit
		result.amplification = amplification
		result.admits_excess = admits_excess
		return result

var source: StringName
var source_life: int
var family: StringName
var origin: CombatOrigin
var continuation: Continuation
var components: Array[Component] = []
var activation_costs: Dictionary[StringName, Quantity] = {}
var hp_cost: Quantity
var automatic_hp_cost: bool
var cooldown: StringName
var cooldown_ticks: int
var add_status: StringName
var status_units: int
var consume_status: StringName
var displacement: RealmSweep.Point
var push_center: RealmSweep.Point
var radial_distance: float
var lightning_reach: float
var lightning_targets: int
var lightning_damage: Quantity
var storm_relay: bool
var rupture_per_stack: int
var echo_delay: int
var ascending_pierce: bool
var resonant_interval: int
var echo_radius: float
var echo_targets: int
var wake_targets: int
var wake_radius: float
var wake_period: int
var wake_duration: int
var wake_damage: int
var bleed: CombatBleedLedger.Application
var restore_source: Quantity
var damage_recovery: Array[DamageRecovery] = []
var barrier_for_source: BarrierGrant
var converted_barrier: BarrierConversion


func is_valid() -> bool:
	if (source.is_empty() or source_life <= 0 or family.is_empty() or origin == null
			or origin.delivery_part != 0 or not origin.valid_for(origin.committed_at)
			or continuation not in Continuation.values()
			or cooldown_ticks < 0 or (cooldown_ticks > 0 and cooldown.is_empty())
			or (add_status.is_empty() and status_units != 0) or (not add_status.is_empty() and status_units <= 0)
			or (hp_cost != null and hp_cost.sign_value <= 0) or (automatic_hp_cost and hp_cost == null)
			or (displacement != null and (not is_finite(displacement.x) or not is_finite(displacement.y)))
			or not is_finite(radial_distance) or radial_distance < 0.0
			or (push_center == null) != (radial_distance == 0.0)
			or (push_center != null and (displacement != null or not is_finite(push_center.x) or not is_finite(push_center.y)))
			or not is_finite(lightning_reach) or lightning_reach < 0.0 or lightning_targets < 0
			or (lightning_damage == null) != (lightning_reach == 0.0)
			or (lightning_damage == null) != (lightning_targets == 0)
			or (lightning_damage != null and lightning_damage.sign_value <= 0)
			or (storm_relay and lightning_damage == null)
			or rupture_per_stack < 0
			or resonant_interval < 0
			or echo_delay < 0 or echo_targets < 0 or not is_finite(echo_radius) or echo_radius < 0.0
			or (echo_delay > 0) != (echo_targets > 0) or (echo_delay > 0) != (echo_radius > 0.0)
			or wake_targets < 0 or (wake_targets > 0 and (not is_finite(wake_radius) or wake_radius <= 0.0
				or wake_period <= 0 or wake_duration < wake_period or wake_damage <= 0))
			or (bleed != null and not bleed.is_valid())
			or (restore_source != null and restore_source.sign_value <= 0)
			or (barrier_for_source != null and not barrier_for_source.is_valid())
			or (converted_barrier != null and not converted_barrier.is_valid())):
		return false
	for resource: StringName in activation_costs:
		var cost := activation_costs[resource]
		if resource.is_empty() or cost == null or cost.sign_value < 0:
			return false
	for component: Component in components:
		if component == null or not component.is_valid():
			return false
	if not valid_recovery(damage_recovery):
		return false
	return true


static func valid_recovery(rules: Array[DamageRecovery]) -> bool:
	var seen: Dictionary[StringName, bool] = {}
	for rule: DamageRecovery in rules:
		if rule == null or not rule.is_valid() or seen.has(rule.id):
			return false
		seen[rule.id] = true
	return true


func copy() -> CombatAction:
	var result := CombatAction.new()
	result.source = source
	result.source_life = source_life
	result.family = family
	result.origin = origin.copy()
	result.continuation = continuation
	result.activation_costs = activation_costs.duplicate()
	result.hp_cost = hp_cost
	result.automatic_hp_cost = automatic_hp_cost
	result.cooldown = cooldown
	result.cooldown_ticks = cooldown_ticks
	result.add_status = add_status
	result.status_units = status_units
	result.consume_status = consume_status
	result.lightning_reach = lightning_reach
	result.lightning_targets = lightning_targets
	result.lightning_damage = lightning_damage
	result.storm_relay = storm_relay
	result.rupture_per_stack = rupture_per_stack
	result.echo_delay = echo_delay
	result.ascending_pierce = ascending_pierce
	result.resonant_interval = resonant_interval
	result.echo_radius = echo_radius
	result.echo_targets = echo_targets
	result.wake_targets = wake_targets
	result.wake_radius = wake_radius
	result.wake_period = wake_period
	result.wake_duration = wake_duration
	result.wake_damage = wake_damage
	result.bleed = bleed.copy() if bleed != null else null
	result.restore_source = restore_source
	for rule: DamageRecovery in damage_recovery:
		result.damage_recovery.append(rule.copy())
	if barrier_for_source != null:
		result.barrier_for_source = barrier_for_source.copy()
	if converted_barrier != null:
		result.converted_barrier = converted_barrier.copy()
	if displacement != null:
		result.displacement = RealmSweep.Point.new(displacement.x, displacement.y)
	if push_center != null:
		result.push_center = RealmSweep.Point.new(push_center.x, push_center.y)
		result.radial_distance = radial_distance
	for component: Component in components:
		result.components.append(component.copy())
	return result
