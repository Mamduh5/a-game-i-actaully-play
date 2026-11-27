class_name WorldEnemy
extends RefCounted
## An authored opponent uses the same sensing, windup and delivery while
## the host is drawing its realm or stepping it without a view.

const PARTY := &"party"

class Rules:
	var faction: StringName
	var foes: Array[StringName] = []
	var family: StringName
	var hp: Quantity
	var damage: Quantity
	var damage_kind: CombatAction.Damage = CombatAction.Damage.PHYSICAL
	var radius: float
	var displacement_resistance: float
	var sight: float
	var stride: float
	var attack_range: float
	var attack_radius: float
	var windup_ticks: int
	var recovery_ticks: int
	var pursuit_ticks: int
	var hunter: bool
	var ground_only: bool

	func is_valid() -> bool:
		return (not faction.is_empty() and faction != PARTY and not family.is_empty()
			and hp != null and hp.sign_value > 0 and damage != null and damage.sign_value > 0
			and damage_kind in CombatAction.Damage.values() and radius > 0.0 and is_finite(radius)
			and is_finite(displacement_resistance) and displacement_resistance >= 0.0 and displacement_resistance <= 1.0
			and sight > 0.0 and is_finite(sight) and stride >= 0.0 and is_finite(stride)
			and attack_range > 0.0 and is_finite(attack_range) and attack_radius > 0.0 and is_finite(attack_radius)
			and windup_ticks > 0 and recovery_ticks > 0 and pursuit_ticks >= 0
			and faction not in foes and &"" not in foes)

	func copy() -> Rules:
		var captured := Rules.new()
		captured.faction = faction
		captured.foes = foes.duplicate()
		captured.family = family
		captured.hp = hp
		captured.damage = damage
		captured.damage_kind = damage_kind
		captured.radius = radius
		captured.displacement_resistance = displacement_resistance
		captured.sight = sight
		captured.stride = stride
		captured.attack_range = attack_range
		captured.attack_radius = attack_radius
		captured.windup_ticks = windup_ticks
		captured.recovery_ticks = recovery_ticks
		captured.pursuit_ticks = pursuit_ticks
		captured.hunter = hunter
		captured.ground_only = ground_only
		return captured

class Subject:
	var id: StringName
	var realm: StringName
	var faction: StringName
	var life: int
	var hp: Quantity
	var maximum: Quantity
	var at: RealmSweep.Point
	var airborne: bool
	var close_call_margin: float

class Strike:
	var delivery: CombatDelivery
	var origin: RealmSweep.Point
	var center: RealmSweep.Point
	var due: int
	var watched: StringName
	var watched_life: int
	var watched_visit: int

class Threat:
	var center: RealmSweep.Point
	var radius: float
	var start_tick: int
	var impact_tick: int

var _id: StringName
var _rules: Rules
var _pursuit: StringName
var _last_seen: RealmSweep.Point
var _remember_until: int
var _ready_at: int
var _attack: Strike
var _activated: int


func _init(id: StringName, rules: Rules) -> void:
	_id = id
	_rules = rules.copy()


func decide(kernel: CombatKernel, room: WorldExploration, settled: Dictionary[StringName, Subject], tick: int) -> bool:
	var self_pose: Subject = settled[_id]
	if self_pose.hp.sign_value <= 0 or _attack != null or tick < _ready_at:
		return true
	var at := self_pose.at
	var geometry := room.geometry()
	var blockers := WorldExploration.BLOCKER
	var target := _detect(geometry, self_pose, settled, blockers)
	if target != null and target.faction == PARTY and _rules.hunter:
		_pursuit = target.id
		_last_seen = target.at
		_remember_until = tick + mini(RunAuthority.MAX_TICK - tick, _rules.pursuit_ticks)
	elif _last_seen != null:
		var former: Subject = settled.get(_pursuit)
		if (former == null or former.hp.sign_value <= 0 or tick > _remember_until
				or _distance(at, _last_seen) == 0.0):
			_pursuit = &""
			_last_seen = null
		else:
			target = null
	if target != null and _distance(at, target.at) <= _rules.attack_range:
		return _commit_strike(kernel, self_pose, target, tick)
	var destination := target.at if target != null else _last_seen
	if destination == null or _rules.stride == 0.0:
		return true
	destination = room.enemy_waypoint(at, destination, _rules.radius)
	if destination == null:
		return true
	var distance := _distance(at, destination)
	if distance == 0.0:
		return true
	var end := destination
	if distance > _rules.stride:
		var travel := _rules.stride / distance
		end = RealmSweep.Point.new(lerpf(at.x, destination.x, travel), lerpf(at.y, destination.y, travel))
	return geometry.displace_circle(_id, 0, end, blockers) != null


func release_due(tick: int) -> bool:
	return _attack != null and _attack.due <= tick


func threat() -> Threat:
	if _attack == null:
		return null
	var warning := Threat.new()
	warning.center = PlayerControlState.copy_point(_attack.center)
	warning.radius = _rules.attack_radius
	warning.start_tick = _attack.due - _rules.windup_ticks
	warning.impact_tick = _attack.due
	return warning


func release(kernel: CombatKernel, geometry: RealmGeometry, subjects: Dictionary[StringName, Subject],
		tick: int, blockers: int, targets: int, near_misses: Dictionary[StringName, bool]) -> bool:
	if not release_due(tick):
		return true
	var held := _attack
	var clear := _unobstructed(geometry, held.origin, held.center, blockers)
	if clear:
		var plan := held.delivery.plan_sweep(geometry, held.center, held.center, _rules.attack_radius, targets)
		if plan == null:
			return false
		var watched_contact := false
		for contact: RealmGeometry.Contact in plan.contacts:
			watched_contact = watched_contact or contact.entity == held.watched
			var other: Subject = subjects.get(contact.entity)
			if (other != null and other.realm == geometry.realm_id and other.hp.sign_value > 0 and _hostile(other.faction)
					and (not _rules.ground_only or not other.airborne)
					and _unobstructed(geometry, held.origin, other.at, _cover_for(other, blockers))):
				if held.delivery.admit(tick, contact, other.life, true) not in [
						CombatDelivery.Result.ADMITTED, CombatDelivery.Result.CADENCE]:
					return false
		if not watched_contact and not held.watched.is_empty():
			var watched: Subject = subjects.get(held.watched)
			if _narrow_miss(kernel, geometry, held, watched, tick, blockers):
				near_misses[held.watched] = true
	if not held.delivery.finish():
		return false
	_attack = null
	return true


func _narrow_miss(kernel: CombatKernel, floor: RealmGeometry, held: Strike, watched: Subject,
		tick: int, blockers: int) -> bool:
	if (watched == null or watched.realm != floor.realm_id or watched.life != held.watched_life
			or watched.hp.sign_value <= 0 or (_rules.ground_only and watched.airborne)):
		return false
	var contact := RealmCircleTime.new()
	var in_band := false
	for slot: int in floor.circle_slots(watched.id):
		var at := floor.circle_center(watched.id, slot)
		var radius := floor.circle_radius(watched.id, slot)
		var edge := contact.measure(at, at, radius,
			held.center, held.center, _rules.attack_radius + watched.close_call_margin)
		if edge.outcome == RealmCircleTime.Result.UNRESOLVED:
			return false
		in_band = in_band or edge.outcome == RealmCircleTime.Result.HIT
	if not in_band or not _unobstructed(floor, held.origin, watched.at, _cover_for(watched, blockers)):
		return false
	var actor := kernel.actor_snapshot(watched.id)
	return _threatens(actor, watched, tick) and actor.realm_visit == held.watched_visit


static func _cover_for(subject: Subject, blockers: int) -> int:
	return blockers & ~WorldExploration.VAULTABLE_BLOCKER if subject.airborne else blockers


func _threatens(actor: CombatantState, target: Subject, tick: int) -> bool:
	if (actor == null or actor.prevents_hit or (_rules.ground_only and target.airborne)
			or (actor.revival_protected_until != null and CombatInstant.at_tick(tick).order_against(
				actor.revival_protected_until) not in [RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER])):
		return false
	var defense := actor.physical if _rules.damage_kind == CombatAction.Damage.PHYSICAL else actor.magical
	return not defense.immune and defense.vulnerability.sign_value > 0


func state() -> Array:
	var memory: Array = [] if _last_seen == null else [_pursuit, _last_seen.x, _last_seen.y, _remember_until]
	var strike: Array = [] if _attack == null else [
		_attack.due, _attack.origin.x, _attack.origin.y, _attack.center.x, _attack.center.y]
	if _attack != null and not _attack.watched.is_empty():
		strike.append_array([_attack.watched, _attack.watched_life, _attack.watched_visit])
	return [_rules.faction, _activated, _ready_at, memory, strike]


func faction() -> StringName:
	return _rules.faction


func start_reanimated_life(ready_at: int) -> void:
	_pursuit = &""
	_last_seen = null
	_remember_until = 0
	_ready_at = maxi(_ready_at, ready_at)


func _detect(geometry: RealmGeometry, self_pose: Subject, known: Dictionary[StringName, Subject], blockers: int) -> Subject:
	var best: Subject
	var best_distance := INF
	for other: Subject in known.values():
		if other.id == _id or other.realm != self_pose.realm or other.hp.sign_value <= 0 or not _hostile(other.faction):
			continue
		var distance := _distance(self_pose.at, other.at)
		var player_priority := _rules.hunter and other.faction == PARTY
		var best_player := _rules.hunter and best != null and best.faction == PARTY
		var preferred := (player_priority and not best_player) or (player_priority == best_player and distance < best_distance)
		if preferred and distance <= _rules.sight and _unobstructed(geometry, self_pose.at, other.at, blockers):
			best = other
			best_distance = distance
	return best


func _commit_strike(kernel: CombatKernel, self_pose: Subject, target: Subject, tick: int) -> bool:
	if (_rules.windup_ticks > RunAuthority.MAX_TICK - tick
			or _rules.recovery_ticks > RunAuthority.MAX_TICK - tick - _rules.windup_ticks
			or _activated == Quantity.INT_MAX):
		return false
	var action := CombatAction.new()
	action.source = _id
	action.source_life = self_pose.life
	action.family = _rules.family
	action.origin = CombatOrigin.new()
	action.origin.provenance = CombatOrigin.Provenance.SPAWN
	action.origin.owner = _id
	action.origin.activation = _activated + 1
	action.origin.committed_at = CombatInstant.at_tick(tick)
	var component := CombatAction.Component.new()
	component.kind = _rules.damage_kind
	component.base = _rules.damage
	action.components = [component]
	var delivery := CombatDelivery.activate(kernel, action, self_pose.realm)
	if delivery == null:
		return false
	_attack = Strike.new()
	_attack.delivery = delivery
	_attack.origin = self_pose.at
	_attack.center = target.at
	_attack.due = tick + _rules.windup_ticks
	if target.close_call_margin > 0.0:
		var actor := kernel.actor_snapshot(target.id)
		if _threatens(actor, target, tick):
			_attack.watched = target.id
			_attack.watched_life = target.life
			_attack.watched_visit = actor.realm_visit
	_ready_at = _attack.due + _rules.recovery_ticks
	_activated += 1
	return true


func _hostile(faction: StringName) -> bool:
	return (_rules.hunter and faction == PARTY) or faction in _rules.foes


static func _distance(first: RealmSweep.Point, second: RealmSweep.Point) -> float:
	var dx := first.x - second.x
	var dy := first.y - second.y
	return sqrt(dx * dx + dy * dy)


static func _unobstructed(geometry: RealmGeometry, start: RealmSweep.Point, finish: RealmSweep.Point, blockers: int) -> bool:
	var sight := geometry.certify_frozen_path(geometry.realm_id, start, finish, 0.0, blockers)
	return sight != null and sight.contacts.is_empty() and sight.unresolved.is_empty()
