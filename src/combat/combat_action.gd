class_name CombatAction
extends RefCounted
## The fixed-step owner supplies authored placement and other eligibility facts.
## The kernel verifies liveness, pays this activation and freezes offense.

enum Damage { PHYSICAL = 1, MAGICAL = 2 }

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

	func is_valid() -> bool:
		return not id.is_empty() and mask > 0 and mask <= (Damage.PHYSICAL | Damage.MAGICAL) and capacity != null and capacity.sign_value > 0

	func copy() -> BarrierGrant:
		var result := BarrierGrant.new()
		result.id = id
		result.mask = mask
		result.capacity = capacity
		return result

var source: StringName
var source_life: int
var family: StringName
var origin: CombatOrigin
var components: Array[Component] = []
var activation_costs: Dictionary[StringName, Quantity] = {}
var cooldown: StringName
var cooldown_ticks: int
var add_status: StringName
var status_units: int
var consume_status: StringName
var displacement: RealmSweep.Point
var restore_source: Quantity
var barrier_for_source: BarrierGrant


func is_valid() -> bool:
	if (source.is_empty() or source_life <= 0 or family.is_empty() or origin == null
			or origin.delivery_part != 0 or not origin.valid_for(origin.committed_at)
			or cooldown_ticks < 0 or (cooldown_ticks > 0 and cooldown.is_empty())
			or (add_status.is_empty() and status_units != 0) or (not add_status.is_empty() and status_units <= 0)
			or (displacement != null and (not is_finite(displacement.x) or not is_finite(displacement.y)))
			or (restore_source != null and restore_source.sign_value <= 0)
			or (barrier_for_source != null and not barrier_for_source.is_valid())):
		return false
	for resource: StringName in activation_costs:
		var cost := activation_costs[resource]
		if resource.is_empty() or cost == null or cost.sign_value < 0:
			return false
	for component: Component in components:
		if component == null or not component.is_valid():
			return false
	return true


func copy() -> CombatAction:
	var result := CombatAction.new()
	result.source = source
	result.source_life = source_life
	result.family = family
	result.origin = origin.copy()
	result.activation_costs = activation_costs.duplicate()
	result.cooldown = cooldown
	result.cooldown_ticks = cooldown_ticks
	result.add_status = add_status
	result.status_units = status_units
	result.consume_status = consume_status
	result.restore_source = restore_source
	if barrier_for_source != null:
		result.barrier_for_source = barrier_for_source.copy()
	if displacement != null:
		result.displacement = RealmSweep.Point.new(displacement.x, displacement.y)
	for component: Component in components:
		result.components.append(component.copy())
	return result
