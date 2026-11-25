class_name CombatFollowUp
extends RefCounted
## An authored immediate reaction tied to a realized hit or elimination.

enum Cause { PAID_HIT, OWN_DEATH, KILL, HOSTILE_HP, HOSTILE_LAYER, SOLID_IMPACT }

var id: StringName
var cause: Cause
var family: StringName
var priority: int
var layer: StringName
var resource: StringName
var cost: Quantity
var component: CombatAction.Component
var restore_source: Quantity
var consume_status: StringName
var inherit_parent_statuses: bool
var fresh_target: StringName
var reach: float
var collision_mask: int


func is_valid() -> bool:
	return (not id.is_empty() and not family.is_empty() and cause in Cause.values()
		and component != null and component.is_valid()
		and (cause != Cause.HOSTILE_LAYER or not layer.is_empty())
		and (cause != Cause.PAID_HIT or not resource.is_empty())
		and (cause != Cause.KILL or not fresh_target.is_empty())
		and (restore_source == null or restore_source.sign_value > 0)
		and ((fresh_target.is_empty() and reach == 0.0 and collision_mask == 0)
			or (not fresh_target.is_empty() and is_finite(reach) and reach > 0.0 and collision_mask > 0))
		and ((resource.is_empty() and cost == null)
			or (not resource.is_empty() and cost != null and cost.sign_value > 0)))


func copy() -> CombatFollowUp:
	var result := CombatFollowUp.new()
	result.id = id
	result.cause = cause
	result.family = family
	result.priority = priority
	result.layer = layer
	result.resource = resource
	result.cost = cost
	result.component = component.copy()
	result.restore_source = restore_source
	result.consume_status = consume_status
	result.inherit_parent_statuses = inherit_parent_statuses
	result.fresh_target = fresh_target
	result.reach = reach
	result.collision_mask = collision_mask
	return result
