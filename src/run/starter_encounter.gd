class_name StarterEncounter
extends RunAuthority
## Composes the first native encounter without owning input devices or rendering.

const PLAYER_BODY := 4
const SIGHT := 420.0
const TUNING: StarterCombatRules = preload("res://src/catalog/starter_combat.tres")

class Build:
	var preparation: RunPreparation
	var powers: RunRewardQueue
	var start: RealmSweep.Point
	var maximum_hp: Quantity
	var physical_defense := Quantity.from_count(0)
	var magical_defense := Quantity.from_count(0)

class Seat:
	var weapon: StarterWeapon
	var manual: StringName
	var targeting := PlayerTargeting.new()
	var selected: StringName
	var combat: StarterCombat
	var speed: float
	var vault: VaultTravel
	var familiar: SketchFamiliar
	var mines: RunicMines
	var lance: SpectralLance
	var tether: ArcaneTether

class Fighter:
	var id: StringName
	var at: RealmSweep.Point
	var radius: float
	var hp: Quantity
	var maximum: Quantity
	var enemy: bool

	func at_pose(pose: RealmSweep.Point) -> Fighter:
		var fighter := Fighter.new()
		fighter.id = id
		fighter.at = PlayerControlState.copy_point(pose)
		fighter.radius = radius
		fighter.hp = hp
		fighter.maximum = maximum
		fighter.enemy = enemy
		return fighter

class View:
	var player: Fighter
	var others: Array[Fighter] = []
	var threats: Array[WorldEnemy.Threat] = []
	var cues: Array[StarterCombat.Cue] = []
	var mines: Array[RealmSweep.Point] = []
	var darts: Array[RealmSweep.Point] = []
	var lances: Array[RealmSweep.Point] = []
	var tethers: Array[Array] = []
	var familiars: Array[RealmSweep.Point] = []
	var tick: int
	var barrier: Quantity
	var selected: StringName
	var manual_ready: bool
	var defeated: bool
	var cleared: bool

var _floor: WorldExploration
var _geometry: RealmGeometry
var _kernel := CombatKernel.new()
var _activity: WorldActivity
var _party: RunParty
var _seats: Dictionary[StringName, Seat] = {}
var _enemies: Array[StringName] = []
var _fault: StringName


## The run owner supplies already prepared builds and their own reward queues.
static func assemble(setup: RunSetup, host: StringName, floor: WorldExploration,
		builds: Dictionary[StringName, Build]) -> StarterEncounter:
	if (setup == null or not setup.is_valid_for(setup.authority_id) or floor == null
			or builds.size() != setup.initial_realms.size() or not builds.has(host)):
		return null
	var encounter := StarterEncounter.new()
	encounter._floor = floor
	encounter._geometry = floor.geometry()
	encounter._activity = WorldActivity.new(encounter._kernel, setup.seed)
	if not encounter._activity.register_realm(floor):
		return null
	var draft := encounter._geometry.fork()
	var actors: Dictionary[StringName, StringName] = {}
	for seat: StringName in setup.identity()["initial_realms"]:
		if (setup.initial_realms[seat] != encounter._geometry.realm_id
				or floor.view(seat).is_empty()
				or not encounter._prepare_seat(seat, builds.get(seat), setup.catalog_revision)):
			encounter._geometry.adopt(draft)
			return null
		actors[seat] = seat
	var realms: Dictionary[StringName, RealmGeometry] = {encounter._geometry.realm_id: encounter._geometry}
	encounter._party = RunParty.begin(setup, host, encounter._kernel, realms, actors, WorldExploration.BLOCKER)
	if encounter._party == null or not encounter.start(setup, setup.authority_id):
		encounter._geometry.adopt(draft)
		return null
	for seat: StringName in actors:
		floor.observe_seat(seat, encounter._geometry.realm_id, builds[seat].start)
	return encounter


func _prepare_seat(id: StringName, build: Build, revision: StringName) -> bool:
	if (build == null or build.preparation == null or build.preparation.catalog_revision != revision
			or build.powers == null or build.powers.bound_seat != id
			or build.start == null or _floor.module_at(build.start).is_empty()
			or build.maximum_hp == null or build.maximum_hp.sign_value <= 0):
		return false
	var placement := _geometry.certify_circle_snapshot(_geometry.realm_id, build.start,
		WorldExploration.STARTER_RADIUS, WorldExploration.BLOCKER)
	if placement == null or not placement.contacts.is_empty() or not placement.unresolved.is_empty():
		return false
	var actor := CombatantState.new()
	var prep := build.preparation
	actor.id = id
	actor.owner = id
	actor.life = 1
	actor.provenance = CombatOrigin.Provenance.SEAT
	actor.realm = _geometry.realm_id
	actor.max_hp = _entry_amount(prep, &"maximum_hp", build.maximum_hp)
	actor.physical.rating = _entry_amount(prep, &"physical_defense", build.physical_defense)
	actor.magical.rating = _entry_amount(prep, &"magical_defense", build.magical_defense)
	if actor.max_hp == null or actor.physical.rating == null or actor.magical.rating == null:
		return false
	actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
	var margin := TUNING.close_call_margin if prep.hero == StarterCombatRules.ACROBAT else 0.0
	if (not TUNING.prepare_hero(actor, build.preparation) or not _kernel.add_actor(actor)
			or not _geometry.add_circle(id, 0, build.start, WorldExploration.STARTER_RADIUS, PLAYER_BODY)
			or not _activity.track_player(id, margin)):
		return false
	var seat := Seat.new()
	var movement_bonus := float(prep.upgrade_basis_points(&"movement")) / RunPreparation.BASIS_POINTS
	seat.speed = PlayerControlState.REFERENCE_SPEED * (1.0 + movement_bonus)
	seat.weapon = TUNING.weapon_for(build.preparation.weapon)
	match build.preparation.hero:
		StarterCombatRules.UNDYING: seat.manual = StarterCombatRules.SIPHON
		StarterCombatRules.ACROBAT: seat.manual = StarterCombatRules.VAULT
		StarterCombatRules.CONDUCTOR: seat.manual = StarterCombatRules.HARMONIC_BURST
		StarterCombatRules.CHRONOMANCER: seat.manual = StarterCombatRules.TIME_FRACTURE
		_: return false
	var foes := WorldActivity.ACTORS
	var walls := WorldExploration.BLOCKER
	seat.combat = StarterCombat.create(TUNING, build.preparation.catalog, build.preparation,
		_kernel, _geometry, id, foes, foes, walls)
	seat.familiar = SketchFamiliar.create(_kernel, _geometry, id, build.powers, foes, walls)
	seat.mines = RunicMines.create(id, build.powers, _kernel, _geometry, foes, walls, seat.combat)
	seat.lance = SpectralLance.create(id, build.powers, _kernel, _geometry, foes, walls)
	seat.tether = ArcaneTether.create(id, build.powers, _kernel, _geometry, foes, walls)
	if (seat.combat == null or seat.familiar == null or seat.mines == null
			or seat.lance == null or seat.tether == null):
		return false
	_seats[id] = seat
	return true


static func _entry_amount(prep: RunPreparation, stat: StringName, authored: Quantity) -> Quantity:
	if authored == null or authored.sign_value < 0:
		return null
	var bonus := prep.upgrade_basis_points(stat)
	return authored.multiply(Quantity.from_count(RunPreparation.BASIS_POINTS + bonus, 4)) if bonus != 0 else authored


func place_enemy(id: StringName, rules: WorldEnemy.Rules, at: RealmSweep.Point) -> bool:
	if _party == null or next_tick() != 1 or not _activity.introduce_enemy(id, _geometry.realm_id, rules, at):
		return false
	_enemies.append(id)
	_enemies.sort()
	return true


func fault() -> StringName:
	return _fault


func party_statuses() -> Dictionary[StringName, StringName]:
	return _party.status_ids()


func movement_state(seat: StringName, baseline: int, serial: int) -> MovementSnapshot:
	var tick := _party.closed_tick
	var member := _party.view(seat, CombatInstant.at_tick(tick))
	if member == null:
		return null
	var state := MovementSnapshot.new()
	state.epoch = _epoch
	state.baseline = baseline
	state.revision = _geometry.compatible_revision(WorldExploration.BLOCKER)
	state.serial = serial
	state.tick = tick
	state.acknowledged = movement_acknowledgement(seat)
	state.position = member.position
	state.movement = _party.movement_input(seat)
	state.speed = _movement_speed(_seats[seat], tick + 1)
	state.radius = _geometry.circle_radius(seat, 0)
	state.permits_prediction = _party.can_control(seat) and _seats[seat].vault == null
	return state


func can_open_earning_group() -> bool:
	return _party != null and not _party.defeated and _fault.is_empty() and super.can_open_earning_group()


func _supports_action(action: StringName) -> bool:
	return action in PlayerCommand.ACTIONS


func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	var frame := _activity.advance(tick, self, _play.bind(tick, accepted, outcomes), _observe_wave)
	if frame == null or not _party.close_tick(tick):
		_fault = _activity.fault() if not _activity.fault().is_empty() else &"encounter_boundary"
		return [{"fault": _fault}]
	for closed: CombatKernel.WaveResult in frame.combat:
		for hit: CombatKernel.Hit in closed.hits:
			if hit.accepted:
				outcomes.append({"at": closed.due.tick, "family": hit.family, "owner": hit.origin.owner,
					"target": hit.target, "damage": hit.dealt_hostile_damage(), "eliminated": hit.eliminated,
					"pushed": hit.displacement != null})
	for id: StringName in frame.near_misses:
		if not _party.can_control(id):
			continue
		if not _seats[id].combat.record_close_call(tick):
			_fault = &"close_call_frontier"
			return [{"fault": _fault}]
		outcomes.append({"seat": id, "close_call": true})
	for id: StringName in _seats:
		var state := _party.view(id, CombatInstant.at_tick(tick))
		_floor.observe_seat(id, state.realm if state.alive else &"", state.position)
	return outcomes


func _play(tick: int, accepted: Array[RunIntent], outcomes: Array[Dictionary]) -> bool:
	for intent: RunIntent in accepted:
		if intent.action in [PlayerCommand.MOVE_AXES, PlayerCommand.MOVE_TO, PlayerCommand.AIM]:
			_party.apply_input(intent.seat_id, intent.command)
	var targets: Dictionary[StringName, Array] = {}
	for id: StringName in _seats:
		var at := _move_seat(id, tick)
		if at == null:
			return false
		targets[id] = _targets(at)
	for intent: RunIntent in accepted:
		var id := intent.seat_id
		var seat := _seats[id]
		if not _party.can_control(id):
			continue
		var command := intent.command
		var at := _geometry.circle_center(id, 0)
		var pointer := RealmSweep.Point.new(command.x, command.y)
		match intent.action:
			PlayerCommand.MANUAL:
				var result := _try_manual(id, tick, pointer)
				if result == StarterCombat.Attempt.FAULT:
					return false
				outcomes.append({"seat": id, "manual": result == StarterCombat.Attempt.COMMITTED})
			PlayerCommand.TARGET:
				seat.selected = seat.targeting.select(at, pointer, seat.weapon.reach, targets[id])
			PlayerCommand.INTERACT:
				_party.apply_input(id, command)
	for id: StringName in _seats:
		var seat := _seats[id]
		if seat.vault != null and not _activity.mark_airborne(id):
			return false
		if _party.can_control(id):
			var weapon := seat.combat.try_weapon(tick, seat.targeting, targets[id])
			if weapon == StarterCombat.Attempt.FAULT:
				return false
			if weapon == StarterCombat.Attempt.COMMITTED:
				outcomes.append({"seat": id, "weapon": seat.weapon.id})
		if (not seat.combat.advance(tick) or not seat.familiar.advance(tick, targets[id])
				or not seat.mines.advance(tick) or not seat.lance.advance(tick, targets[id])
				or not seat.tether.advance(tick, targets[id])):
			return false
	return true


static func _movement_speed(seat: Seat, tick: int) -> float:
	return seat.speed * seat.combat.movement_multiplier(tick)


func _move_seat(id: StringName, tick: int) -> RealmSweep.Point:
	var seat := _seats[id]
	if seat.vault == null:
		return _party.step_movement(id, _movement_speed(seat, tick), 1.0 / 60.0)
	if _party.can_control(id) and not seat.vault.advance(_geometry):
		return null
	if not _party.can_control(id) or not seat.vault.airborne():
		seat.vault = null
	return _geometry.circle_center(id, 0)


func _try_manual(id: StringName, tick: int, pointer: RealmSweep.Point) -> StarterCombat.Attempt:
	var seat := _seats[id]
	if seat.manual != StarterCombatRules.VAULT:
		return seat.combat.try_manual(tick, pointer)
	if seat.vault != null or not _kernel.actor_snapshot(id).cooldown_ready(seat.manual, CombatInstant.at_tick(tick)):
		return StarterCombat.Attempt.REJECTED
	var pending := VaultTravel.plan(_geometry, id, pointer, TUNING.vault_distance, TUNING.vault_steps)
	if pending == null:
		return StarterCombat.Attempt.REJECTED
	var attempt := seat.combat.commit_vault(tick)
	if attempt == StarterCombat.Attempt.COMMITTED:
		seat.vault = pending
	return attempt


func _observe_wave(closed: CombatKernel.WaveResult) -> bool:
	if not _party.observe_combat(closed):
		return false
	for seat: Seat in _seats.values():
		seat.combat.observe_closed_group(closed)
	return true


func _targets(from: RealmSweep.Point) -> Array[PlayerTargeting.Candidate]:
	var result: Array[PlayerTargeting.Candidate] = []
	for id: StringName in _enemies:
		var actor := _kernel.actor_vitals(id)
		var at := _geometry.circle_center(id, 0)
		if actor.hp.sign_value <= 0 or not _visible(from, at):
			continue
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = id
		candidate.kind = PlayerTargeting.Kind.HOSTILE
		candidate.position = at
		candidate.pick_radius = _geometry.circle_radius(id, 0)
		candidate.known = true
		candidate.compatible = true
		result.append(candidate)
	return result


## Shared with the local renderer and evidence sampler. It omits off-view
## actors, their projectiles, and hidden source identities for warnings.
func view_for(id: StringName) -> View:
	var seat: Seat = _seats.get(id)
	if seat == null:
		return null
	var actor := _kernel.actor_snapshot(id)
	var pose := _geometry.circle_center(id, 0)
	var view := View.new()
	view.tick = _party.closed_tick
	view.player = _fighter(id, false)
	view.defeated = _party.defeated
	view.manual_ready = (_party.can_control(id) and seat.vault == null
		and actor.cooldown_ready(seat.manual, CombatInstant.at_tick(view.tick + 1)))
	view.barrier = Quantity.from_count(0)
	for barrier: CombatantState.Barrier in actor.barriers:
		view.barrier = view.barrier.add(barrier.pool.amount)
	view.cleared = not _enemies.is_empty()
	for enemy: StringName in _enemies:
		var target := _fighter(enemy, true)
		if target.hp.sign_value > 0:
			view.cleared = false
			if _visible(pose, target.at):
				view.others.append(target)
				if enemy == seat.selected:
					view.selected = enemy
	for ally: StringName in _seats:
		if ally != id:
			var avatar := _fighter(ally, false)
			if _visible(pose, avatar.at):
				view.others.append(avatar)
	for threat: WorldEnemy.Threat in _activity.threats(_geometry.realm_id):
		if _visible(pose, threat.center):
			view.threats.append(threat)
	for other: Seat in _seats.values():
		for cue: StarterCombat.Cue in other.combat.cues():
			if _visible(pose, cue.position) and _visible_direction(pose, cue):
				view.cues.append(cue)
		_append_visible(view.familiars, pose, [other.familiar.position()])
		_append_visible(view.darts, pose, other.familiar.dart_positions())
		_append_visible(view.lances, pose, [other.lance.position()])
		_append_visible(view.mines, pose, other.mines.positions())
		var link := other.tether.visible_segment()
		if link.size() == 2 and _visible(pose, link[0]) and _visible(pose, link[1]):
			view.tethers.append(link)
	return view


func _fighter(id: StringName, enemy: bool) -> Fighter:
	var actor := _kernel.actor_vitals(id)
	var fighter := Fighter.new()
	fighter.id = id
	fighter.at = _geometry.circle_center(id, 0)
	fighter.radius = _geometry.circle_radius(id, 0)
	fighter.hp = actor.hp
	fighter.maximum = actor.maximum
	fighter.enemy = enemy
	return fighter


func _append_visible(output: Array[RealmSweep.Point], from: RealmSweep.Point, points: Array[RealmSweep.Point]) -> void:
	for at: RealmSweep.Point in points:
		if _visible(from, at):
			output.append(at)


func _visible_direction(from: RealmSweep.Point, cue: StarterCombat.Cue) -> bool:
	if cue.id not in [StarterCombatRules.HARMONIC_BURST, &"R02.lightning", &"RP02.blood_wake", &"RP03.storm_relay"]:
		return true
	var end := RealmSweep.Point.new(cue.position.x + cue.heading.x * cue.reach,
		cue.position.y + cue.heading.y * cue.reach)
	return _visible(from, end)


func _visible(from: RealmSweep.Point, at: RealmSweep.Point) -> bool:
	if from == null or at == null or (from.x - at.x) ** 2 + (from.y - at.y) ** 2 > SIGHT ** 2:
		return false
	var sight := _geometry.certify_frozen_path(_geometry.realm_id, from, at, 0.0, WorldExploration.BLOCKER)
	return sight != null and sight.contacts.is_empty() and sight.unresolved.is_empty()
