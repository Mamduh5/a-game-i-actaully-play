class_name SketchFamiliar
extends RefCounted
## One personal P02 slot. Each launched quill retains its own direction and
## penetration allowance while both quills share the paid source activation.

const FAMILY := &"P02"
const REACH := 240.0
const DART_STEP := 12.0
const FOLLOW_STEP := 3.0
const PERIOD := 60

class Dart:
	var position: RealmSweep.Point
	var direction: RealmSweep.Point
	var remaining := REACH
	var penetrations: int
	var phase: int

class Volley:
	var delivery: CombatDelivery
	var darts: Array[Dart] = []

var _kernel: CombatKernel
var _geometry: RealmGeometry
var _owner: StringName
var _rewards: RunRewardQueue
var _targets: int
var _blockers: int
var _position: RealmSweep.Point
var _last_tick := -1
var _volleys: Array[Volley] = []


static func create(kernel: CombatKernel, geometry: RealmGeometry, owner: StringName,
		rewards: RunRewardQueue, targets: int, blockers: int) -> SketchFamiliar:
	if kernel == null or geometry == null or rewards == null or rewards.bound_seat != owner or targets <= 0 or blockers <= 0:
		return null
	var actor := kernel.actor_snapshot(owner)
	if actor == null or actor.owner != owner or actor.realm != geometry.realm_id:
		return null
	var result := SketchFamiliar.new()
	result._kernel = kernel
	result._geometry = geometry
	result._owner = owner
	result._rewards = rewards
	result._targets = targets
	result._blockers = blockers
	return result


func position() -> RealmSweep.Point:
	return PlayerControlState.copy_point(_position) if _position != null else null


func dart_positions() -> Array[RealmSweep.Point]:
	var result: Array[RealmSweep.Point] = []
	for volley: Volley in _volleys:
		for dart: Dart in volley.darts:
			result.append(PlayerControlState.copy_point(dart.position))
	return result


func advance(tick: int, candidates: Array[PlayerTargeting.Candidate]) -> bool:
	if tick <= 0 or tick >= RunAuthority.MAX_TICK or (_last_tick >= 0 and tick != _last_tick + 1):
		return false
	var actor := _kernel.actor_snapshot(_owner)
	if (actor != null and actor.realm == _geometry.realm_id and actor.is_alive() and actor.accepts_new_actions
			and _rewards.active_form(FAMILY) == FAMILY):
		var owner_pose := _geometry.circle_center(_owner, 0)
		if owner_pose == null or not _follow(owner_pose):
			return false
		if actor.cooldown_ready(FAMILY, CombatInstant.at_tick(tick)):
			var target := _choose_target(candidates)
			if target != null and not _launch(tick, actor, target, _rewards.ranks()[FAMILY]):
				return false
	else:
		_position = null
	for index: int in range(_volleys.size() - 1, -1, -1):
		var volley := _volleys[index]
		for i: int in range(volley.darts.size() - 1, -1, -1):
			var dart := volley.darts[i]
			if not _fly(tick, volley.delivery, dart):
				return false
			if dart.remaining <= 0 or dart.penetrations == 0:
				volley.darts.remove_at(i)
		if volley.darts.is_empty():
			if not volley.delivery.finish():
				return false
			_volleys.remove_at(index)
	_last_tick = tick
	return true


func _follow(owner_pose: RealmSweep.Point) -> bool:
	if _position == null:
		_position = PlayerControlState.copy_point(owner_pose)
	var desired := Vector2(owner_pose.x - 16.0 - _position.x, owner_pose.y - _position.y)
	var step := desired.limit_length(FOLLOW_STEP)
	var finish := RealmSweep.Point.new(_position.x + step.x, _position.y + step.y)
	var path := _geometry.certify_frozen_path(_geometry.realm_id, _position, finish, 2.0, _blockers, _owner)
	if path == null or not path.unresolved.is_empty():
		return false
	if path.contacts.is_empty():
		_position = finish
	return true


func _choose_target(candidates: Array[PlayerTargeting.Candidate]) -> RealmSweep.Point:
	var visible: Array[PlayerTargeting.Candidate] = []
	for entry: PlayerTargeting.Candidate in candidates:
		if entry == null or entry.kind != PlayerTargeting.Kind.HOSTILE or not entry.known or not entry.compatible:
			continue
		var actor := _kernel.actor_snapshot(entry.id)
		if actor == null or actor.realm != _geometry.realm_id or not actor.is_alive():
			continue
		var settled := PlayerTargeting.Candidate.new()
		settled.id = entry.id
		settled.position = _geometry.circle_center(entry.id, 0)
		settled.known = true
		settled.compatible = true
		visible.append(settled)
	var id := PlayerTargeting.new().attack_target(_position, REACH, visible)
	return _geometry.circle_center(id, 0) if not id.is_empty() else null


func _launch(tick: int, actor: CombatantState, target: RealmSweep.Point, rank: int) -> bool:
	var action := CombatAction.new()
	action.source = _owner
	action.source_life = actor.life
	action.family = FAMILY
	action.cooldown = FAMILY
	action.cooldown_ticks = PERIOD
	action.origin = CombatOrigin.new()
	action.origin.owner = actor.owner
	action.origin.provenance = actor.provenance
	action.origin.source_slot = 3
	action.origin.activation = tick
	action.origin.committed_at = CombatInstant.at_tick(tick)
	var part := CombatAction.Component.new()
	part.base = Quantity.from_count(8 + 2 * int(rank >= 2) + 2 * int(rank >= 4))
	action.components = [part]
	var volley := Volley.new()
	volley.delivery = CombatDelivery.activate(_kernel, action, _geometry.realm_id, 0, true)
	if volley.delivery == null:
		return false
	var forward := PlayerControlState.direction(_position, target, RealmSweep.Point.new(1, 0))
	for angle: float in ([-3.0, 3.0] if rank >= 3 else [0.0]):
		var axis := Vector2(forward.x, forward.y).rotated(deg_to_rad(angle))
		var dart := Dart.new()
		dart.position = position()
		dart.direction = RealmSweep.Point.new(axis.x, axis.y)
		dart.phase = volley.darts.size()
		dart.penetrations = 2 if rank >= 5 else 1
		volley.darts.append(dart)
	_volleys.append(volley)
	return true


func _fly(tick: int, delivery: CombatDelivery, dart: Dart) -> bool:
	var step := minf(dart.remaining, DART_STEP)
	var finish := RealmSweep.Point.new(dart.position.x + dart.direction.x * step, dart.position.y + dart.direction.y * step)
	var sweep := delivery.plan_sweep(_geometry, dart.position, finish, 1.0, _targets, _blockers)
	if sweep == null:
		return false
	for contact: RealmGeometry.Contact in sweep.contacts:
		var target := _kernel.actor_snapshot(contact.entity)
		if target == null or not target.is_alive() or target.realm != _geometry.realm_id:
			continue
		match delivery.admit(tick, contact, target.life, true, dart.phase):
			CombatDelivery.Result.CADENCE: continue
			CombatDelivery.Result.ADMITTED: dart.penetrations -= 1
			_: return false
		if dart.penetrations == 0:
			break
	dart.remaining = 0.0 if sweep.blocker != null else dart.remaining - step
	dart.position = finish
	return true
