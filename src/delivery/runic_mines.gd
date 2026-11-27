class_name RunicMines
extends RefCounted
## Automatic P03 placements for one seat and realm. Both mines in a Twin
## Runes cycle commit independently and retain their rank at placement.

const FAMILY := &"P03"
const PERIOD := 90
const ARM_DELAY := 12
const LIFETIME := 150
const CAPACITY := 4
const TRIGGER_RADIUS := 12.0
const BLAST_RADIUS := 36.0

class Mine:
	var center: RealmSweep.Point
	var placed: int
	var delivery: CombatDelivery
	var charge: CombatMineCharge

var _owner: StringName
var _kernel: CombatKernel
var _geometry: RealmGeometry
var _targets: int
var _blockers: int
var _rewards: RunRewardQueue
var _combat: StarterCombat
var _next_cycle: int
var _last_tick := -1
var _mines: Array[Mine] = []


static func create(owner: StringName, rewards: RunRewardQueue, kernel: CombatKernel, geometry: RealmGeometry,
		targets: int, blockers: int, combat: StarterCombat = null) -> RunicMines:
	if rewards == null or rewards.bound_seat != owner or kernel == null or geometry == null or targets <= 0 or blockers <= 0:
		return null
	var source := kernel.actor_snapshot(owner)
	if source == null or source.owner != owner or source.realm != geometry.realm_id:
		return null
	var result := RunicMines.new()
	result._owner = owner
	result._rewards = rewards
	result._kernel = kernel
	result._geometry = geometry
	result._targets = targets
	result._blockers = blockers
	result._combat = combat
	return result


func positions() -> Array[RealmSweep.Point]:
	var result: Array[RealmSweep.Point] = []
	for mine: Mine in _mines:
		if mine.charge.end_reason == CombatMineCharge.End.LIVE:
			result.append(PlayerControlState.copy_point(mine.center))
	return result


func advance(tick: int) -> bool:
	if tick <= 0 or tick > RunAuthority.MAX_TICK - LIFETIME or (_last_tick >= 0 and tick != _last_tick + 1):
		return false
	var source := _kernel.actor_snapshot(_owner)
	if (tick >= _next_cycle and source != null and source.is_alive() and source.accepts_new_actions
			and source.realm == _geometry.realm_id and _rewards.active_form(FAMILY) == FAMILY):
		if not _place_cycle(source, tick, _rewards.ranks()[FAMILY]):
			return false
		_next_cycle = tick + PERIOD
	var now := CombatInstant.at_tick(tick)
	for index: int in range(_mines.size() - 1, -1, -1):
		var mine := _mines[index]
		if tick > mine.placed and _combat != null and _combat.compresses_at(_owner, _geometry.realm_id, tick, mine.center):
			mine.charge.compress_arming(tick)
		if mine.charge.armed_at(now) and not _check_trigger(mine, tick):
			return false
		if tick > mine.placed + LIFETIME:
			mine.charge.expire(now)
		if mine.charge.end_reason != CombatMineCharge.End.LIVE:
			if not mine.delivery.finish():
				return false
			_mines.remove_at(index)
	_last_tick = tick
	return true


func _place_cycle(source: CombatantState, tick: int, rank: int) -> bool:
	var owner_position := _geometry.circle_center(_owner, 0)
	if owner_position == null:
		return false
	var offsets: Array[Vector2] = [Vector2.ZERO]
	if rank >= 3:
		offsets.assign([Vector2(-16, 0), Vector2(16, 0), Vector2(0, -16), Vector2(0, 16), Vector2.ZERO])
	var placed := 0
	for offset: Vector2 in offsets:
		if _mines.size() >= CAPACITY or placed >= (2 if rank >= 3 else 1):
			break
		var point := RealmSweep.Point.new(owner_position.x + offset.x, owner_position.y + offset.y)
		var clear := _geometry.certify_frozen_path(_geometry.realm_id, owner_position, point, 2.0, _blockers, _owner)
		if clear == null or not clear.unresolved.is_empty():
			return false
		if not clear.contacts.is_empty():
			continue
		var action := CombatAction.new()
		action.source = _owner
		action.source_life = source.life
		action.family = FAMILY
		action.origin = CombatOrigin.new()
		action.origin.owner = source.owner
		action.origin.provenance = source.provenance
		action.origin.source_slot = 4 + placed
		action.origin.activation = tick
		action.origin.committed_at = CombatInstant.at_tick(tick)
		var part := CombatAction.Component.new()
		part.kind = CombatAction.Damage.MAGICAL
		part.base = Quantity.from_count(16 + 4 * int(rank >= 2) + 4 * int(rank >= 4))
		action.components = [part]
		var mine := Mine.new()
		mine.center = point
		mine.placed = tick
		mine.charge = CombatMineCharge.create(action.origin.committed_at, ARM_DELAY, LIFETIME,
			part.base, Quantity.from_count(int(rank == 5)), part.base.multiply(Quantity.from_count(2)))
		mine.delivery = CombatDelivery.activate(_kernel, action, _geometry.realm_id, 0, true)
		if mine.delivery == null or not mine.delivery.bind_mine(mine.charge):
			return false
		_mines.append(mine)
		placed += 1
	return true


func _check_trigger(mine: Mine, tick: int) -> bool:
	if tick > mine.placed + LIFETIME:
		return true
	var sweep := mine.delivery.plan_sweep(_geometry, mine.center, mine.center, TRIGGER_RADIUS, _targets)
	if sweep == null:
		return false
	var entrants: Dictionary[StringName, bool] = {}
	for trigger: RealmGeometry.Contact in sweep.contacts:
		var entrant := _kernel.actor_snapshot(trigger.entity)
		if entrant == null or not entrant.is_alive() or entrant.realm != _geometry.realm_id or entrants.has(entrant.id):
			continue
		var at := CombatInstant.at_contact(tick, trigger.proof)
		if at == null:
			return false
		if at.order_against(CombatInstant.at_tick(mine.placed + LIFETIME)) == RealmCircleTime.Order.AFTER:
			return true
		var blast := _geometry.certify_disk_at(_geometry.realm_id, mine.center, BLAST_RADIUS, trigger.proof, _targets, _owner)
		if blast == null or not blast.unresolved.is_empty() or not mine.delivery.offer_mine_entry(at, entrant.id, blast.contacts):
			return false
		entrants[entrant.id] = true
	return true
