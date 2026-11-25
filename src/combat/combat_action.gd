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

var source: StringName
var source_life: int
var family: StringName
var origin: CombatOrigin
var components: Array[Component] = []
var activation_costs: Dictionary[StringName, Quantity] = {}
var cooldown: StringName
var cooldown_ticks: int


func is_valid() -> bool:
	if (source.is_empty() or source_life <= 0 or family.is_empty() or origin == null
			or origin.delivery_part != 0 or not origin.valid_for(origin.committed_at)
			or cooldown_ticks < 0 or (cooldown_ticks > 0 and cooldown.is_empty())):
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
	for component: Component in components:
		result.components.append(component.copy())
	return result
