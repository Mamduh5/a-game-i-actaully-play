class_name StarterCombat
extends RefCounted
## C01 loadout owner. Weapon and hero are chosen independently at preparation.

enum Attempt { COMMITTED, NO_TARGET, REJECTED, FAULT }

const WEAPON_COOLDOWN := &"main_weapon"

class Cue:
	var radius: float
	var id: StringName
	var position: RealmSweep.Point
	var heading: RealmSweep.Point
	var reach: float
	var half_angle: float
	var impact: int
	var ends: int

class Arrow:
	var delivery: CombatDelivery
	var position: RealmSweep.Point
	var heading: RealmSweep.Point
	var remaining: float

class Sigil:
	var placed: int
	var delivery: CombatDelivery
	var cue: Cue

var _rules: StarterCombatRules
var _weapon: StarterWeapon
var _hero: StringName
var _force_equipped: bool
var _lightning_equipped: bool
var _bleed_equipped: bool
var _kernel: CombatKernel
var _geometry: RealmGeometry
var _actor: StringName
var _targets: int
var _hostiles: int
var _blockers: int
var _last_tick := -1
var _arrows: Array[Arrow] = []
var _sigils: Array[Sigil] = []
var _fracture: Cue
var _effects: Array[Cue] = []
var _resonance: int
var _linked_lives: Dictionary[StringName, int] = {}
var _last_observed_group: CombatInstant

var resonance: int:
	get: return _resonance


static func create(rules: StarterCombatRules, catalog: DefinitionCatalog, preparation: RunPreparation,
		kernel: CombatKernel, geometry: RealmGeometry, actor: StringName, targets: int, hostiles: int,
		blockers: int) -> StarterCombat:
	if (rules == null or not rules.is_valid_for(catalog) or preparation == null
			or preparation.catalog_revision != catalog.revision or kernel == null or geometry == null
			or hostiles <= 0 or (hostiles & targets) != hostiles or blockers <= 0 or (blockers & targets) != 0):
		return null
	var weapon := rules.weapon_for(preparation.weapon)
	var source := kernel.actor_snapshot(actor)
	if weapon == null or source == null or source.realm != geometry.realm_id or geometry.circle_center(actor, 0) == null:
		return null
	var result := StarterCombat.new()
	result._rules = rules.duplicate() as StarterCombatRules
	result._weapon = weapon.duplicate() as StarterWeapon
	result._hero = preparation.hero
	result._force_equipped = &"R03" in preparation.runes()
	result._lightning_equipped = &"R02" in preparation.runes()
	result._bleed_equipped = &"R01" in preparation.runes()
	result._kernel = kernel
	result._geometry = geometry
	result._actor = actor
	result._targets = targets
	result._hostiles = hostiles
	result._blockers = blockers
	return result


func try_weapon(tick: int, targeting: PlayerTargeting, candidates: Array[PlayerTargeting.Candidate],
		bonuses: Array[QuantityFormula.BonusCategory] = [], costs: Dictionary[StringName, Quantity] = {}) -> Attempt:
	if not _open_tick(tick) or targeting == null:
		return Attempt.REJECTED
	var source := _kernel.actor_snapshot(_actor)
	var start := _geometry.circle_center(_actor, 0)
	if source == null or not source.is_alive() or not source.accepts_new_actions or start == null:
		return Attempt.REJECTED
	if not source.cooldown_ready(WEAPON_COOLDOWN, CombatInstant.at_tick(tick)):
		return Attempt.REJECTED
	var id := targeting.attack_target(start, _weapon.reach, _settled_candidates(candidates))
	if id.is_empty():
		return Attempt.NO_TARGET
	var aim := _geometry.circle_center(id, 0)
	var action := _action(source, tick, 0, _weapon.id, _weapon.damage,
		_weapon.cooldown_ticks, CombatAction.Damage.MAGICAL if _weapon.delivery == StarterWeapon.Delivery.SIGIL
		else CombatAction.Damage.PHYSICAL)
	action.components[0].categories = bonuses
	action.activation_costs = costs
	if _hero == StarterCombatRules.CHRONOMANCER:
		action.echo_delay = _rules.echo_delay
		action.echo_radius = _rules.echo_radius
		action.echo_targets = _hostiles
	if _bleed_equipped:
		action.bleed = _rules.bleed_application(bonuses)
	if _lightning_equipped:
		action.lightning_reach = _rules.lightning_reach
		action.lightning_targets = _hostiles
		action.lightning_damage = Quantity.from_count(_rules.lightning_damage)
		action.storm_relay = _force_equipped
		if _bleed_equipped:
			action.rupture_per_stack = _rules.rupture_per_stack
	var heading := PlayerControlState.direction(start, aim, RealmSweep.Point.new(1.0, 0.0))
	if _force_equipped:
		if _bleed_equipped:
			action.wake_targets = _hostiles
			action.wake_radius = _rules.wake_radius
			action.wake_period = _rules.wake_period
			action.wake_duration = _rules.wake_duration
			action.wake_damage = _rules.wake_damage
		if _weapon.delivery == StarterWeapon.Delivery.ARROW:
			action.displacement = RealmSweep.Point.new(heading.x * _rules.force_distance, heading.y * _rules.force_distance)
		else:
			action.push_center = aim if _weapon.delivery == StarterWeapon.Delivery.SIGIL else start
			action.radial_distance = _rules.force_distance
	var result: Attempt
	match _weapon.delivery:
		StarterWeapon.Delivery.CLEAVE: result = _cleave(action, tick, start, heading)
		StarterWeapon.Delivery.ARROW: result = _launch_arrow(action, start, heading)
		StarterWeapon.Delivery.SIGIL: result = _place_sigil(action, tick, start, aim)
	if result == Attempt.COMMITTED:
		targeting.commit_attack_target(id)
	return result


func _settled_candidates(candidates: Array[PlayerTargeting.Candidate]) -> Array[PlayerTargeting.Candidate]:
	var visible: Array[PlayerTargeting.Candidate] = []
	for entry: PlayerTargeting.Candidate in candidates:
		if entry == null or not entry.known or not entry.compatible or _living_target(entry.id) == null:
			continue
		var pose := _geometry.circle_center(entry.id, 0)
		if pose == null:
			continue
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = entry.id
		candidate.kind = entry.kind
		candidate.known = true
		candidate.compatible = true
		candidate.position = pose
		candidate.precision = entry.precision
		visible.append(candidate)
	return visible


## A deliberate manual activation can validly miss. Barrier conversion uses
## only the actual damage from this pulse, summed across its simultaneous hits.
func try_manual(tick: int, selected: RealmSweep.Point = null) -> Attempt:
	if not _open_tick(tick):
		return Attempt.REJECTED
	var source := _kernel.actor_snapshot(_actor)
	var center := _geometry.circle_center(_actor, 0)
	if source == null or not source.is_alive() or not source.accepts_new_actions or center == null:
		return Attempt.REJECTED
	if _hero == StarterCombatRules.CONDUCTOR:
		return _harmonic_burst(tick, source, center)
	if _hero == StarterCombatRules.CHRONOMANCER:
		return _place_fracture(tick, source, center, selected)
	if (_hero != StarterCombatRules.UNDYING or tick > RunAuthority.MAX_TICK - _rules.siphon_lifetime
			or not source.cooldown_ready(StarterCombatRules.SIPHON, CombatInstant.at_tick(tick))):
		return Attempt.REJECTED
	var contacts := _geometry.certify_circle_snapshot(_geometry.realm_id, center, _rules.siphon_radius, _hostiles, _actor)
	if not _certified(contacts):
		return Attempt.FAULT
	var action := _action(source, tick, 1, StarterCombatRules.SIPHON, _rules.siphon_damage,
		_rules.siphon_cooldown, CombatAction.Damage.MAGICAL)
	action.converted_barrier = _rules.siphon_conversion()
	var result := _instant_delivery(action, tick, contacts.contacts)
	if result == Attempt.COMMITTED:
		_effects.append(_ring(StarterCombatRules.SIPHON, center, _rules.siphon_radius, tick, tick + 10))
	return result


func _place_fracture(tick: int, source: CombatantState, center: RealmSweep.Point, selected: RealmSweep.Point) -> Attempt:
	if (selected == null or not is_finite(selected.x) or not is_finite(selected.y)
			or tick > RunAuthority.MAX_TICK - _rules.fracture_cooldown
			or (selected.x - center.x) ** 2 + (selected.y - center.y) ** 2 > _rules.fracture_reach ** 2
			or not source.cooldown_ready(StarterCombatRules.TIME_FRACTURE, CombatInstant.at_tick(tick))):
		return Attempt.REJECTED
	var path := _blockers_between(center, selected)
	if not _certified(path):
		return Attempt.FAULT
	if not path.contacts.is_empty():
		return Attempt.REJECTED
	var action := _action(source, tick, 1, StarterCombatRules.TIME_FRACTURE, 0,
		_rules.fracture_cooldown, CombatAction.Damage.MAGICAL)
	var result := _instant_delivery(action, tick, [])
	if result == Attempt.COMMITTED:
		_fracture = _ring(StarterCombatRules.TIME_FRACTURE, PlayerControlState.copy_point(selected),
			_rules.fracture_radius, tick, tick + _rules.fracture_duration)
		_effects.append(_fracture)
	return result


func _harmonic_burst(tick: int, source: CombatantState, center: RealmSweep.Point) -> Attempt:
	if not source.cooldown_ready(StarterCombatRules.HARMONIC_BURST, CombatInstant.at_tick(tick)):
		return Attempt.REJECTED
	var nearby := _geometry.certify_circle_snapshot(_geometry.realm_id, center, _rules.harmonic_reach, _hostiles, _actor)
	if not _certified(nearby):
		return Attempt.FAULT
	var links: Array[RealmGeometry.Contact] = []
	var distances: Dictionary[StringName, float] = {}
	var reached: Dictionary[StringName, RealmGeometry.Contact] = {}
	for contact: RealmGeometry.Contact in nearby.contacts:
		var at := _geometry.circle_center(contact.entity, contact.shape)
		if at == null or _living_target(contact.entity) == null:
			continue
		var distance := (at.x - center.x) ** 2 + (at.y - center.y) ** 2
		if distance >= float(distances.get(contact.entity, INF)):
			continue
		var path := _blockers_between(center, at)
		if not _certified(path):
			return Attempt.FAULT
		if path.contacts.is_empty():
			distances[contact.entity] = distance
			reached[contact.entity] = contact
	var candidates := reached.keys()
	candidates.sort_custom(func(a: StringName, b: StringName) -> bool:
		return distances[a] < distances[b] if distances[a] != distances[b] else String(a) < String(b))
	for i: int in mini(candidates.size(), _resonance + 1):
		links.append(reached[candidates[i]])
	var action := _action(source, tick, 1, StarterCombatRules.HARMONIC_BURST, _rules.harmonic_damage,
		_rules.harmonic_cooldown, CombatAction.Damage.MAGICAL)
	var result := _instant_delivery(action, tick, links)
	if result != Attempt.COMMITTED:
		return result
	_resonance = 0
	_linked_lives.clear()
	for contact: RealmGeometry.Contact in links:
		var at := _geometry.circle_center(contact.entity, contact.shape)
		var cue := _ring(StarterCombatRules.HARMONIC_BURST, center, sqrt(distances[contact.entity]), tick, tick + 10)
		cue.heading = PlayerControlState.direction(center, at, RealmSweep.Point.new(1.0, 0.0))
		_effects.append(cue)
	return result


## An owned weapon following a landed Burst link on the same life earns one
## charge. Snapshot earlier links so contacts in one group cannot self-prime.
func observe_closed_group(group: CombatKernel.WaveResult) -> void:
	if (group == null or group.result != CombatKernel.Result.CLOSED or group.due == null or (_last_observed_group != null
			and _last_observed_group.order_against(group.due) != RealmCircleTime.Order.BEFORE)):
		return
	_last_observed_group = group.due
	for hit: CombatKernel.Hit in group.hits:
		if hit.source == _actor and hit.wake_duration > 0:
			var motion := hit.displacement
			var length := sqrt((motion.finish.x - motion.start.x) ** 2 + (motion.finish.y - motion.start.y) ** 2)
			var cue := _ring(&"RP02.blood_wake", PlayerControlState.copy_point(motion.start), length,
				group.due.tick, group.due.tick + hit.wake_duration + 1)
			cue.radius = hit.wake_radius
			cue.heading = PlayerControlState.direction(motion.start, motion.finish, RealmSweep.Point.new(1.0, 0.0))
			_effects.append(cue)
		if hit.source == _actor and hit.accepted and hit.arc_start != null and hit.arc_end != null:
			var distance := sqrt((hit.arc_end.x - hit.arc_start.x) ** 2 + (hit.arc_end.y - hit.arc_start.y) ** 2)
			var cue := _ring(hit.family, hit.arc_start, distance, group.due.tick, mini(group.due.tick, RunAuthority.MAX_TICK - 10) + 10)
			cue.heading = PlayerControlState.direction(hit.arc_start, hit.arc_end, RealmSweep.Point.new(1.0, 0.0))
			_effects.append(cue)
	if _hero != StarterCombatRules.CONDUCTOR:
		return
	var actor := _kernel.actor_snapshot(_actor)
	if actor == null or not actor.is_alive():
		return
	var fresh: Dictionary[StringName, int] = {}
	for hit: CombatKernel.Hit in group.hits:
		if (hit.source != _actor or hit.source_life != actor.life or not hit.accepted or not hit.hostile
				or hit.origin == null or hit.origin.owner != actor.owner or hit.parent != 0):
			continue
		if hit.family == StarterCombatRules.HARMONIC_BURST and not hit.eliminated:
			fresh[hit.target] = hit.target_life
		elif hit.family == _weapon.id and _linked_lives.get(hit.target, 0) == hit.target_life:
			_linked_lives.erase(hit.target)
			_resonance = mini(_rules.resonance_cap, _resonance + 1)
	_linked_lives.merge(fresh, true)


## A run supplies the settled poses and planned obstacle motion at this
## boundary. An arrow can admit a hit within the following sub-tick interval.
func advance(tick: int) -> bool:
	if not _open_tick(tick) or not _decay(tick):
		return false
	if _fracture != null and _fracture.ends <= tick:
		_fracture = null
	if _fracture != null and not _kernel.compress_echoes(_actor, _geometry.realm_id, tick, _fracture.position, _fracture.reach):
		return false
	for index: int in range(_sigils.size() - 1, -1, -1):
		var sigil := _sigils[index]
		if (_fracture != null and tick > sigil.placed and sigil.cue.impact > tick
				and (sigil.cue.position.x - _fracture.position.x) ** 2
				+ (sigil.cue.position.y - _fracture.position.y) ** 2 <= _fracture.reach ** 2):
			sigil.cue.impact -= 1
			sigil.cue.ends -= 1
		if sigil.cue.impact > tick:
			continue
		if sigil.cue.impact < tick:
			return false
		var contacts := _geometry.certify_circle_snapshot(_geometry.realm_id, sigil.cue.position, sigil.cue.reach,
			_targets, _actor)
		if not _certified(contacts) or not _admit_all(sigil.delivery, contacts.contacts, tick) or not sigil.delivery.finish():
			return false
		_effects.append(sigil.cue)
		_sigils.remove_at(index)
	var surviving: Array[Arrow] = []
	for arrow: Arrow in _arrows:
		var step := minf(_weapon.travel_per_tick, arrow.remaining)
		var finish := _offset(arrow.position, arrow.heading, step)
		var plan := arrow.delivery.plan_sweep(_geometry, arrow.position, finish, 0.0, _targets, _blockers)
		if plan == null:
			return false
		var hit := false
		for contact: RealmGeometry.Contact in plan.contacts:
			var actor := _living_target(contact.entity)
			if actor == null:
				continue
			var at := _offset(arrow.position, arrow.heading, step * contact.time)
			if arrow.delivery.admit(tick, contact, actor.life, (contact.category & _hostiles) != 0, 0, at) != CombatDelivery.Result.ADMITTED:
				return false
			hit = true
			break
		arrow.remaining -= step
		arrow.position = finish
		if hit or plan.blocker != null or arrow.remaining <= 0.0:
			if not arrow.delivery.finish():
				return false
		else:
			surviving.append(arrow)
	_arrows = surviving
	for index: int in range(_effects.size() - 1, -1, -1):
		if _effects[index].ends <= tick:
			_effects.remove_at(index)
	_last_tick = tick
	return true


func cues() -> Array[Cue]:
	var visible: Array[Cue] = []
	for effect: Cue in _effects:
		visible.append(_copy_cue(effect))
	for sigil: Sigil in _sigils:
		visible.append(_copy_cue(sigil.cue))
	for arrow: Arrow in _arrows:
		var cue := _ring(&"W02", PlayerControlState.copy_point(arrow.position), 0.0, _last_tick, _last_tick + 1)
		cue.heading = PlayerControlState.copy_point(arrow.heading)
		visible.append(cue)
	return visible


func _cleave(action: CombatAction, tick: int, center: RealmSweep.Point, heading: RealmSweep.Point) -> Attempt:
	var possible := _geometry.certify_circle_snapshot(_geometry.realm_id, center, _weapon.reach, _targets, _actor)
	if not _certified(possible):
		return Attempt.FAULT
	var angle := deg_to_rad(_weapon.half_angle_degrees)
	var forward := cos(angle)
	var side := sin(angle)
	var right := _offset(center, RealmSweep.Point.new(heading.x * forward - heading.y * side,
		heading.x * side + heading.y * forward), _weapon.reach)
	var left := _offset(center, RealmSweep.Point.new(heading.x * forward + heading.y * side,
		-heading.x * side + heading.y * forward), _weapon.reach)
	var certifier := RealmCircleTime.new()
	var hits: Array[RealmGeometry.Contact] = []
	for candidate: RealmGeometry.Contact in possible.contacts:
		var target := _geometry.circle_center(candidate.entity, candidate.shape)
		if target == null:
			continue
		var dx := target.x - center.x
		var dy := target.y - center.y
		var inside := dx * heading.x + dy * heading.y >= forward * sqrt(dx * dx + dy * dy)
		if not inside:
			var radius := _geometry.circle_radius(candidate.entity, candidate.shape)
			for boundary: RealmSweep.Point in [left, right]:
				var edge := certifier.measure_segment(target, target, radius, center, boundary)
				if edge.outcome == RealmCircleTime.Result.UNRESOLVED:
					return Attempt.FAULT
				inside = inside or edge.outcome == RealmCircleTime.Result.HIT
		if inside:
			var blockers := _blockers_between(center, target)
			if not _certified(blockers):
				return Attempt.FAULT
			if blockers.contacts.is_empty():
				hits.append(candidate)
	var result := _instant_delivery(action, tick, hits)
	if result == Attempt.COMMITTED:
		var cue := _ring(&"W01", center, _weapon.reach, tick, tick + 9)
		cue.heading = heading
		cue.half_angle = angle
		_effects.append(cue)
	return result


func _launch_arrow(action: CombatAction, center: RealmSweep.Point, heading: RealmSweep.Point) -> Attempt:
	var delivery := CombatDelivery.activate(_kernel, action, _geometry.realm_id)
	if delivery == null:
		return Attempt.REJECTED
	var arrow := Arrow.new()
	arrow.delivery = delivery
	arrow.position = center
	arrow.heading = heading
	arrow.remaining = _weapon.reach
	_arrows.append(arrow)
	return Attempt.COMMITTED


func _place_sigil(action: CombatAction, tick: int, source: RealmSweep.Point, center: RealmSweep.Point) -> Attempt:
	var blockers := _blockers_between(source, center)
	if not _certified(blockers):
		return Attempt.FAULT
	if not blockers.contacts.is_empty() or tick > RunAuthority.MAX_TICK - _weapon.delay_ticks - 12:
		return Attempt.REJECTED
	var delivery := CombatDelivery.activate(_kernel, action, _geometry.realm_id, 0, true)
	if delivery == null:
		return Attempt.REJECTED
	var sigil := Sigil.new()
	sigil.placed = tick
	sigil.delivery = delivery
	var impact := tick + _weapon.delay_ticks
	sigil.cue = _ring(&"W03", center, _weapon.area_radius, impact, impact + 12)
	_sigils.append(sigil)
	return Attempt.COMMITTED


func _instant_delivery(action: CombatAction, tick: int, contacts: Array[RealmGeometry.Contact]) -> Attempt:
	var delivery := CombatDelivery.activate(_kernel, action, _geometry.realm_id, 0, true)
	if delivery == null:
		return Attempt.REJECTED
	return Attempt.COMMITTED if _admit_all(delivery, contacts, tick) and delivery.finish() else Attempt.FAULT


func _admit_all(delivery: CombatDelivery, contacts: Array[RealmGeometry.Contact], tick: int) -> bool:
	for contact: RealmGeometry.Contact in contacts:
		var target := _living_target(contact.entity)
		if target == null:
			continue
		var result := delivery.admit(tick, contact, target.life, (contact.category & _hostiles) != 0)
		if result not in [CombatDelivery.Result.ADMITTED, CombatDelivery.Result.CADENCE]:
			return false
	return true


func _living_target(id: StringName) -> CombatantState:
	var actor := _kernel.actor_snapshot(id)
	return actor if actor != null and actor.realm == _geometry.realm_id and actor.is_alive() else null


func _decay(tick: int) -> bool:
	if _hero != StarterCombatRules.UNDYING:
		return true
	var actor := _kernel.actor_snapshot(_actor)
	if actor == null:
		return false
	for layer: CombatantState.Barrier in actor.barriers:
		if layer.id == StarterCombatRules.SIPHON and layer.expires != null and tick < layer.expires.tick:
			var elapsed := tick - (layer.expires.tick - _rules.siphon_lifetime)
			if elapsed > 0 and elapsed % _rules.siphon_decay_interval == 0:
				return _kernel.adjust_barrier(_actor, actor.life, layer.id, layer.generation,
					CombatKernel.BarrierAdjustment.DECAY, Quantity.from_count(1)) != null
	return true


func _blockers_between(start: RealmSweep.Point, finish: RealmSweep.Point) -> RealmGeometry.SweepCandidates:
	return _geometry.certify_frozen_path(_geometry.realm_id, start, finish, 0.0, _blockers, _actor)


func _open_tick(tick: int) -> bool:
	return tick > 0 and tick < RunAuthority.MAX_TICK - 12 and (_last_tick < 0 or tick == _last_tick + 1)


static func _action(source: CombatantState, tick: int, slot: int, family: StringName, damage: int, cooldown: int,
		kind: CombatAction.Damage) -> CombatAction:
	var result := CombatAction.new()
	result.source = source.id
	result.source_life = source.life
	result.family = family
	result.cooldown = WEAPON_COOLDOWN if slot == 0 else family
	result.cooldown_ticks = cooldown
	result.origin = CombatOrigin.new()
	result.origin.owner = source.owner
	result.origin.provenance = source.provenance
	result.origin.source_slot = slot
	result.origin.activation = tick
	result.origin.committed_at = CombatInstant.at_tick(tick)
	var component := CombatAction.Component.new()
	component.kind = kind
	component.base = Quantity.from_count(damage)
	result.components.append(component)
	return result


static func _certified(contacts: RealmGeometry.SweepCandidates) -> bool:
	return contacts != null and contacts.unresolved.is_empty()


static func _offset(point: RealmSweep.Point, direction: RealmSweep.Point, units: float) -> RealmSweep.Point:
	return RealmSweep.Point.new(point.x + direction.x * units, point.y + direction.y * units)


static func _ring(id: StringName, at: RealmSweep.Point, radius: float, impact: int, ends: int) -> Cue:
	var result := Cue.new()
	result.id = id
	result.position = at
	result.reach = radius
	result.impact = impact
	result.ends = ends
	return result


static func _copy_cue(cue: Cue) -> Cue:
	var result := _ring(cue.id, PlayerControlState.copy_point(cue.position), cue.reach, cue.impact, cue.ends)
	result.half_angle = cue.half_angle
	result.radius = cue.radius
	result.heading = PlayerControlState.copy_point(cue.heading) if cue.heading != null else null
	return result
