class_name ArcaneTether
extends RefCounted
## The expanded P14 slot retains one link, its original pulse clock and at
## most one replacement endpoint over that link's lifetime.

const FAMILY := &"P14"
const PERIOD := 15
const LIFETIME := 90
const COOLDOWN := 120

var _kernel: CombatKernel
var _geometry: RealmGeometry
var _rewards: RunRewardQueue
var _owner: StringName
var _targets: int
var _blockers: int
var _last_tick := -1
var _link: CombatTether
var _width: float
var _reach: float
var _reconnected: bool


static func create(owner: StringName, rewards: RunRewardQueue, kernel: CombatKernel, geometry: RealmGeometry,
		targets: int, blockers: int) -> ArcaneTether:
	if rewards == null or rewards.bound_seat != owner or kernel == null or geometry == null or targets <= 0 or blockers <= 0:
		return null
	var actor := kernel.actor_snapshot(owner)
	if actor == null or actor.owner != owner or actor.realm != geometry.realm_id:
		return null
	var result := ArcaneTether.new()
	result._owner = owner
	result._rewards = rewards
	result._kernel = kernel
	result._geometry = geometry
	result._targets = targets
	result._blockers = blockers
	return result


func endpoints() -> Array[RealmSweep.Point]:
	var result: Array[RealmSweep.Point] = []
	if _link != null:
		for index: int in 2:
			var point := _link.endpoint_position(index, _geometry)
			if point == null:
				return []
			result.append(PlayerControlState.copy_point(point))
	return result


func advance(tick: int, candidates: Array[PlayerTargeting.Candidate]) -> bool:
	if tick <= 0 or tick > RunAuthority.MAX_TICK - COOLDOWN or (_last_tick >= 0 and tick != _last_tick + 1):
		return false
	var now := CombatInstant.at_tick(tick)
	var source := _kernel.actor_snapshot(_owner)
	if (_link == null and source != null and source.is_alive() and source.accepts_new_actions
			and source.realm == _geometry.realm_id and _rewards.active_form(FAMILY) == FAMILY and source.cooldown_ready(FAMILY, now)):
		if not _start(source, now, candidates, _rewards.ranks()[FAMILY]):
			return false
	if _link != null:
		_repair(now, candidates)
		var due := _link.next_due()
		while due != null and due.order_against(now) == RealmCircleTime.Order.SAME:
			var pulse := _link.due_through(_geometry, now, _width, _targets, _blockers)
			if pulse == null:
				return false
			for contact: RealmGeometry.Contact in pulse.contacts:
				var target := _kernel.actor_snapshot(contact.entity)
				if target != null and target.is_alive() and target.realm == _geometry.realm_id:
					if _link.admit(pulse, contact, target.life, true) not in [CombatDelivery.Result.ADMITTED, CombatDelivery.Result.CADENCE]:
						return false
			if not _link.settle(pulse):
				return false
			due = _link.next_due()
		if due == null:
			_link = null
	_last_tick = tick
	return true


func visible_segment() -> Array[RealmSweep.Point]:
	var points := endpoints()
	if points.size() != 2 or not CombatTether._valid_link(points[0], points[1], _reach):
		return []
	var clear := _geometry.certify_frozen_path(_geometry.realm_id, points[0], points[1], _width * 0.5, _blockers)
	if clear == null or not clear.unresolved.is_empty() or not clear.contacts.is_empty():
		return []
	return points


func _nearest(origin: RealmSweep.Point, reach: float, candidates: Array[PlayerTargeting.Candidate],
		distinct_position: bool) -> CombatTether.Endpoint:
	var best: CombatTether.Endpoint
	var best_distance := reach ** 2
	for candidate: PlayerTargeting.Candidate in candidates:
		if candidate == null or not candidate.known or not candidate.compatible or candidate.kind != PlayerTargeting.Kind.HOSTILE:
			continue
		var target := _kernel.actor_snapshot(candidate.id)
		var pose := _geometry.circle_center(candidate.id, 0)
		if target == null or not target.is_alive() or target.realm != _geometry.realm_id or pose == null:
			continue
		var distance := (pose.x - origin.x) ** 2 + (pose.y - origin.y) ** 2
		if distance > best_distance or (distinct_position and distance == 0.0):
			continue
		if best != null and distance == best_distance and String(target.id) >= String(best.actor):
			continue
		best_distance = distance
		best = CombatTether.Endpoint.new()
		best.actor = target.id
		best.life = target.life
	return best


func _other(origin: RealmSweep.Point, candidates: Array[PlayerTargeting.Candidate]) -> CombatTether.Endpoint:
	var enemy := _nearest(origin, _reach, candidates, true)
	if enemy != null:
		return enemy
	for offset: Vector2 in [Vector2(-32, 0), Vector2(32, 0), Vector2(0, -32), Vector2(0, 32)]:
		var point := RealmSweep.Point.new(origin.x + offset.x, origin.y + offset.y)
		var clear := _geometry.certify_frozen_path(_geometry.realm_id, origin, point, _width * 0.5, _blockers)
		if clear != null and clear.unresolved.is_empty() and clear.contacts.is_empty():
			var anchor := CombatTether.Endpoint.new()
			anchor.anchor = point
			return anchor
	return null


func _start(source: CombatantState, now: CombatInstant, candidates: Array[PlayerTargeting.Candidate], rank: int) -> bool:
	var center := _geometry.circle_center(_owner, 0)
	if center == null:
		return false
	_reach = 150.0 if rank >= 3 else 100.0
	_width = 12.0 if rank >= 3 else 4.0
	var first := _nearest(center, 240.0, candidates, false)
	if first == null:
		return true
	var last := _other(_geometry.circle_center(first.actor, first.slot), candidates)
	if last == null:
		return true
	var action := CombatAction.new()
	action.source = source.id
	action.source_life = source.life
	action.family = FAMILY
	action.origin = CombatOrigin.new()
	action.origin.owner = source.owner
	action.origin.provenance = source.provenance
	action.origin.source_slot = 7
	action.origin.activation = now.tick
	action.origin.committed_at = now
	action.cooldown = FAMILY
	action.cooldown_ticks = COOLDOWN
	action.resonant_interval = PERIOD if rank == 5 else 0
	var part := CombatAction.Component.new()
	part.kind = CombatAction.Damage.MAGICAL
	part.base = Quantity.from_count(8 + 4 * int(rank >= 2) + 4 * int(rank >= 4))
	action.components = [part]
	_link = CombatTether.activate(_kernel, action, _geometry, first, last, LIFETIME, PERIOD, _reach, 1)
	_reconnected = false
	return _link != null


func _repair(now: CombatInstant, candidates: Array[PlayerTargeting.Candidate]) -> void:
	if _reconnected:
		return
	for index: int in 2:
		if _link.endpoint_position(index, _geometry) != null:
			continue
		var other := _link.endpoint_position(1 - index, _geometry)
		if other == null:
			return
		var replacement := _nearest(other, _reach, candidates, true) if _link.anchored(1 - index) else _other(other, candidates)
		if replacement != null:
			_reconnected = _link.reconnect(index, replacement, _geometry, now)
		return
