class_name SpectralLance
extends RefCounted
## One automatically fired spear. Rank and heading are fixed at launch.

const FAMILY := &"P04"
const REACH := 270.0
const STEP := 15.0
const PERIOD := 72

var _owner: StringName
var _rewards: RunRewardQueue
var _kernel: CombatKernel
var _geometry: RealmGeometry
var _targets: int
var _blockers: int
var _last_tick := -1
var _delivery: CombatDelivery
var _position: RealmSweep.Point
var _heading: RealmSweep.Point
var _remaining: float
var _radius: float


static func create(owner: StringName, rewards: RunRewardQueue, kernel: CombatKernel, geometry: RealmGeometry,
		targets: int, blockers: int) -> SpectralLance:
	if rewards == null or rewards.bound_seat != owner or kernel == null or geometry == null or targets <= 0 or blockers <= 0:
		return null
	var actor := kernel.actor_snapshot(owner)
	if actor == null or actor.owner != owner or actor.realm != geometry.realm_id:
		return null
	var result := SpectralLance.new()
	result._owner = owner
	result._rewards = rewards
	result._kernel = kernel
	result._geometry = geometry
	result._targets = targets
	result._blockers = blockers
	return result


func position() -> RealmSweep.Point:
	return PlayerControlState.copy_point(_position) if _delivery != null else null


func heading() -> RealmSweep.Point:
	return PlayerControlState.copy_point(_heading) if _delivery != null else null


func advance(tick: int, candidates: Array[PlayerTargeting.Candidate]) -> bool:
	if tick <= 0 or tick > RunAuthority.MAX_TICK - PERIOD or (_last_tick >= 0 and tick != _last_tick + 1):
		return false
	var source := _kernel.actor_snapshot(_owner)
	if (_delivery == null and source != null and source.is_alive() and source.accepts_new_actions
			and source.realm == _geometry.realm_id and _rewards.active_form(FAMILY) == FAMILY
			and source.cooldown_ready(FAMILY, CombatInstant.at_tick(tick))):
		var start := _geometry.circle_center(_owner, 0)
		if start == null:
			return false
		var aim := CombatDelivery.nearest_known_hostile(_kernel, _geometry, start, REACH, candidates)
		if aim != null and not _launch(tick, source, start, aim, _rewards.ranks()[FAMILY]):
			return false
	if _delivery != null and not _fly(tick):
		return false
	_last_tick = tick
	return true


func _launch(tick: int, source: CombatantState, start: RealmSweep.Point, aim: RealmSweep.Point, rank: int) -> bool:
	var action := CombatAction.new()
	action.source = source.id
	action.source_life = source.life
	action.family = FAMILY
	action.cooldown = FAMILY
	action.cooldown_ticks = PERIOD
	action.origin = CombatOrigin.new()
	action.origin.owner = source.owner
	action.origin.provenance = source.provenance
	action.origin.source_slot = 6
	action.origin.activation = tick
	action.origin.committed_at = CombatInstant.at_tick(tick)
	action.ascending_pierce = rank == 5
	var part := CombatAction.Component.new()
	part.kind = CombatAction.Damage.MAGICAL
	part.base = Quantity.from_count(12 + 4 * int(rank >= 2) + 4 * int(rank >= 4))
	action.components = [part]
	_delivery = CombatDelivery.activate(_kernel, action, _geometry.realm_id, 0, true)
	if _delivery == null:
		return false
	_position = start
	_heading = PlayerControlState.direction(start, aim, RealmSweep.Point.new(1, 0))
	_remaining = REACH
	_radius = 6.0 if rank >= 3 else 2.0
	return true


func _fly(tick: int) -> bool:
	var step := minf(STEP, _remaining)
	var finish := RealmSweep.Point.new(_position.x + _heading.x * step, _position.y + _heading.y * step)
	var sweep := _delivery.plan_sweep(_geometry, _position, finish, _radius, _targets, _blockers)
	if sweep == null:
		return false
	for contact: RealmGeometry.Contact in sweep.contacts:
		var target := _kernel.actor_snapshot(contact.entity)
		if target == null or not target.is_alive() or target.realm != _geometry.realm_id:
			continue
		if _delivery.admit(tick, contact, target.life, true) not in [CombatDelivery.Result.ADMITTED, CombatDelivery.Result.CADENCE]:
			return false
	_position = finish
	_remaining -= step
	if _remaining <= 0.0 or sweep.blocker != null:
		if not _delivery.finish():
			return false
		_delivery = null
	return true
