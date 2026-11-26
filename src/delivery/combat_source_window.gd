class_name CombatSourceWindow
extends RefCounted
## A two-source window scoped to one target life and each causal owner.

class Match:
	var target: StringName
	var life: int
	var first: CombatOrigin
	var second: CombatOrigin
	var first_family: StringName
	var second_family: StringName
	var third: CombatOrigin
	var third_family: StringName

	func copy() -> Match:
		var result := Match.new()
		result.target = target
		result.life = life
		result.first = first.copy()
		result.second = second.copy()
		result.first_family = first_family
		result.second_family = second_family
		result.third = third.copy() if third != null else null
		result.third_family = third_family
		return result

class Owner:
	var family: StringName
	var origin: CombatOrigin
	var deadline: CombatInstant
	var ready: CombatInstant
	var latest: CombatInstant
	var third_deadline: CombatInstant
	var pending_third: Match

var _target: StringName
var _life: int
var _window_ticks: int
var _cooldown_ticks: int
var _third_ticks: int
var _owners: Dictionary[String, Owner] = {}


static func create(target: StringName, life: int, window_ticks: int, cooldown_ticks: int,
		third_window_ticks: int = 0) -> CombatSourceWindow:
	if target.is_empty() or life <= 0 or window_ticks <= 0 or cooldown_ticks <= 0 or third_window_ticks < 0:
		return null
	var result := CombatSourceWindow.new()
	result._target = target
	result._life = life
	result._window_ticks = window_ticks
	result._cooldown_ticks = cooldown_ticks
	result._third_ticks = third_window_ticks
	return result


## The caller declares family eligibility, including secondary effects.
## Each successful match resets that owner's pair and starts its cooldown.
func observe(group: CombatKernel.WaveResult, hit: CombatKernel.Hit, eligible: bool) -> Match:
	if (not eligible or hit == null or not hit.accepted or hit.target != _target or hit.target_life != _life
			or hit.family.is_empty() or hit.origin == null or group == null or group.result != CombatKernel.Result.CLOSED
			or hit not in group.hits or not hit.origin.valid_for(group.due) or not _dealt_damage(hit)):
		return null
	var now := group.due
	var key := "%d/%s" % [hit.origin.provenance, hit.origin.owner]
	var owned: Owner = _owners.get(key)
	if owned == null:
		owned = Owner.new()
		_owners[key] = owned
	if owned.latest != null and not _at_or_before(owned.latest, now):
		return null
	if owned.pending_third != null:
		var third_order := now.order_against(owned.third_deadline)
		if third_order == RealmCircleTime.Order.UNRESOLVED:
			return null
		if third_order == RealmCircleTime.Order.AFTER:
			owned.pending_third = null
		elif hit.family != owned.pending_third.first_family and hit.family != owned.pending_third.second_family:
			var extended := owned.pending_third
			extended.third = hit.origin.copy()
			extended.third_family = hit.family
			owned.pending_third = null
			owned.latest = now
			return extended
	if owned.ready != null and not _at_or_before(owned.ready, now):
		return null
	if owned.origin != null:
		var order := now.order_against(owned.deadline)
		if order == RealmCircleTime.Order.UNRESOLVED:
			return null
		if owned.family != hit.family and order != RealmCircleTime.Order.AFTER:
			var ready := now.after_ticks(_cooldown_ticks)
			if ready == null:
				return null
			var paired := Match.new()
			paired.target = hit.target
			paired.life = hit.target_life
			paired.first = owned.origin.copy()
			paired.second = hit.origin.copy()
			paired.first_family = owned.family
			paired.second_family = hit.family
			owned.latest = now
			owned.ready = ready
			owned.origin = null
			owned.third_deadline = now.after_ticks(_third_ticks) if _third_ticks > 0 else null
			owned.pending_third = paired.copy() if owned.third_deadline != null else null
			return paired
	var deadline := now.after_ticks(_window_ticks)
	if deadline == null:
		return null
	owned.family = hit.family
	owned.origin = hit.origin.copy()
	owned.deadline = deadline
	owned.latest = now
	return null


static func _at_or_before(first: CombatInstant, second: CombatInstant) -> bool:
	return first.order_against(second) in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]


static func _dealt_damage(hit: CombatKernel.Hit) -> bool:
	for component: CombatKernel.ComponentReceipt in hit.components:
		if component.hostile_hp_removed.sign_value > 0:
			return true
		for layer: CombatKernel.LayerReceipt in component.barriers:
			if layer.absorbed.sign_value > 0:
				return true
	return false
