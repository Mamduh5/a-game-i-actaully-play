class_name RunParty
extends RefCounted
## Fixed-step roster owner. The host applies authenticated seat changes
## before that tick's input and combat.

const LOGICAL_HZ := 60
const COLLAPSE_TICK := 25 * 60 * LOGICAL_HZ
const GUEST_GRACE := 60 * LOGICAL_HZ
const RESCUE_REACH := 32.0
const RESCUE_PROGRESS := 120 * 4
const HELPER_RATE := [0, 4, 6, 7]
const REVIVE_PROTECTION := 120
const INITIAL_WAIT := 300
const WAIT_INCREMENT := 180
const MAX_WAIT := 1200

enum RescueInterruption { NONE, MOVED_AWAY, OBSTRUCTED, HOSTILE_DAMAGE, LINK_LOSS, DEATH }

class Body:
	var position: RealmSweep.Point
	var ready: CombatInstant
	var progress: int

class Member:
	var actor: StringName
	var realm: StringName
	var life: int
	var deaths: int
	var connected := true
	var grace_until: CombatInstant
	var body: Body
	var controls := PlayerControlState.new()
	var aiding: StringName
	var aid_pose: RealmSweep.Point
	var last_interruption: RescueInterruption

class View:
	var seat: StringName
	var realm: StringName
	var position: RealmSweep.Point
	var connected: bool
	var alive: bool
	var within_grace: bool
	var deaths: int
	var wait_until: CombatInstant
	var rescue_progress: int
	var rescue_interruption: RescueInterruption

var _host: StringName
var _run: StringName
var _epoch: int
var _members: Dictionary[StringName, Member] = {}
var _actors: Dictionary[StringName, Member] = {}
var _kernel: CombatKernel
var _realms: Dictionary[StringName, RealmGeometry]
var _blockers: int
var _tick: int
var _last_combat: CombatInstant
var _terminal: CombatKernel.Terminal
var _terminal_tick: int
var _currency_authority: WeakRef
var _settlement_pending := false

var terminal: CombatKernel.Terminal:
	get: return CombatKernel.Terminal.ACTIVE if _settlement_pending else _terminal

var defeated: bool:
	get: return terminal == CombatKernel.Terminal.DEFEAT

var settlement_pending: bool:
	get: return _settlement_pending

var closed_tick: int:
	get: return _tick


static func begin(setup: RunSetup, host: StringName, kernel: CombatKernel,
		realms: Dictionary[StringName, RealmGeometry], actors: Dictionary[StringName, StringName],
		blockers: int) -> RunParty:
	if (setup == null or not setup.is_valid_for(setup.authority_id) or kernel == null or blockers <= 0
			or not setup.initial_realms.has(host) or actors.size() != setup.initial_realms.size()):
		return null
	var party := RunParty.new()
	party._host = host
	party._run = setup.run_id
	party._epoch = setup.epoch
	party._kernel = kernel
	party._realms = realms.duplicate()
	party._blockers = blockers
	var seats: Array[StringName] = setup.initial_realms.keys()
	seats.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for seat: StringName in seats:
		var realm := setup.initial_realms[seat]
		var actor := kernel.actor_snapshot(actors.get(seat, &""))
		var geometry: RealmGeometry = realms.get(realm)
		if (actor == null or actor.realm != realm or actor.owner != seat or not actor.is_alive()
				or actor.max_hp == null or actor.provenance != CombatOrigin.Provenance.SEAT
				or not actor.controller.is_empty() or not actor.accepts_new_actions or geometry == null
				or geometry.realm_id != realm or geometry.circle_center(actor.id, 0) == null):
			return null
		var member := Member.new()
		member.actor = actor.id
		member.realm = realm
		member.life = actor.life
		party._members[seat] = member
		party._actors[actor.id] = member
	return party


func initialized_seats() -> Array[StringName]:
	return _members.keys()


func host_seat() -> StringName:
	return _host


func belongs_to(run: StringName, epoch: int) -> bool:
	return run == _run and epoch > 0 and epoch == _epoch


func has_realm(realm: StringName) -> bool:
	return _realms.has(realm)


func owns_geometry(geometry: RealmGeometry) -> bool:
	return geometry != null and _realms.get(geometry.realm_id) == geometry


func attach_currency_authority(authority: RunAuthority) -> bool:
	if (_currency_authority != null or authority == null or _tick != 0
			or _terminal != CombatKernel.Terminal.ACTIVE or not authority.belongs_to(_run, _epoch)):
		return false
	_currency_authority = weakref(authority)
	return true


func hp_scale() -> Quantity:
	return Quantity.from_count(100 + 50 * (_members.size() - 1), 2)


func attack_scale() -> Quantity:
	return Quantity.from_count(100 + 10 * (_members.size() - 1), 2)


func population_scale() -> Quantity:
	return Quantity.from_count(100 + 25 * (_members.size() - 1), 2)


func reinforcement_frequency_scale() -> Quantity:
	return population_scale()


func set_guest_connected(seat: StringName, connected: bool, tick: int) -> bool:
	var member: Member = _members.get(seat)
	if (member == null or seat == _host or member.connected == connected
			or not _next_tick(tick)):
		return false
	var deadline := CombatInstant.at_tick(tick).after_ticks(GUEST_GRACE) if not connected else null
	if (not connected and deadline == null) or not _kernel.set_player_control(member.actor, member.life, connected):
		return false
	member.connected = connected
	member.grace_until = deadline
	member.controls.release_movement()
	_stop_aiding(member, RescueInterruption.LINK_LOSS)
	return true


func can_control(seat: StringName) -> bool:
	var member: Member = _members.get(seat)
	return _terminal == CombatKernel.Terminal.ACTIVE and member != null and member.connected and member.body == null


func transfer_living(seat: StringName, tick: int, source: RealmGeometry, destination: RealmGeometry,
		at: RealmSweep.Point) -> bool:
	if tick != _tick or not can_control(seat) or source == null or destination == null:
		return false
	var member := _members[seat]
	if (member.realm != source.realm_id or _realms.get(member.realm) != source
			or _realms.get(destination.realm_id) != destination
			or not _kernel.transfer_player(member.actor, member.life, source, destination, at)):
		return false
	member.realm = destination.realm_id
	member.controls = PlayerControlState.new()
	_stop_aiding(member, RescueInterruption.MOVED_AWAY)
	return true


func stage_gateway(seat: StringName, tick: int, arena: RealmGeometry,
		arrivals: Dictionary[StringName, RealmSweep.Point]) -> CombatKernel.ArenaTransfer:
	if tick != _tick or not can_control(seat) or arena == null or _realms.has(arena.realm_id):
		return null
	if arrivals.size() != _members.size():
		return null
	var moves: Array[CombatKernel.ArenaArrival] = []
	for id: StringName in _members:
		var member := _members[id]
		var move := CombatKernel.ArenaArrival.new()
		move.actor = member.actor
		move.life = member.life
		move.alive = member.body == null
		move.source = _realms[member.realm]
		move.at = arrivals.get(id)
		moves.append(move)
	return _kernel.stage_arena(CombatInstant.at_tick(tick), arena, _blockers, moves)


func enter_gateway(transfer: CombatKernel.ArenaTransfer, epoch: int) -> bool:
	if (epoch <= _epoch or epoch - _epoch != 1 or _terminal != CombatKernel.Terminal.ACTIVE
			or not _kernel.enter_arena(transfer, CombatInstant.at_tick(_tick))):
		return false
	_epoch = epoch
	var arena := transfer.destination()
	_realms = {arena.realm_id: arena}
	for member: Member in _members.values():
		member.realm = arena.realm_id
		member.controls = PlayerControlState.new()
		_stop_aiding(member, RescueInterruption.MOVED_AWAY)
		if member.body != null:
			member.body.position = arena.circle_center(member.actor, 0)
	return true


func apply_input(seat: StringName, command: PlayerCommand) -> bool:
	if not can_control(seat) or command == null or not command.valid():
		return false
	if command.action == PlayerCommand.INTERACT:
		return _interact_with_body(seat, RealmSweep.Point.new(command.x, command.y))
	if command.action not in [PlayerCommand.MOVE_AXES, PlayerCommand.MOVE_TO, PlayerCommand.AIM]:
		return false
	_members[seat].controls.apply(command)
	return true


func _interact_with_body(seat: StringName, cursor: RealmSweep.Point) -> bool:
	var helper := _members[seat]
	var position := _position(helper)
	if position == null:
		return false
	var possible: Array[PlayerTargeting.Candidate] = []
	for target_seat: StringName in _members:
		var target := _members[target_seat]
		if target.body == null or target.realm != helper.realm:
			continue
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = target_seat
		candidate.kind = PlayerTargeting.Kind.PROTECTED
		candidate.position = target.body.position
		candidate.pick_radius = _realms[target.realm].circle_radius(target.actor, 0)
		candidate.known = true
		candidate.interactable = true
		possible.append(candidate)
	var picked := PlayerTargeting.new().interact(position, cursor, RESCUE_REACH, possible)
	return not picked.is_empty() and begin_rescue(seat, picked, _tick + 1)


func step_movement(seat: StringName, speed: float, seconds: float) -> RealmSweep.Point:
	var member: Member = _members.get(seat)
	if member == null:
		return null
	if not can_control(seat):
		return _position(member)
	return member.controls.step(_realms[member.realm], member.actor, 0, _blockers, speed, seconds)


func movement_input(seat: StringName) -> PlayerCommand:
	var member: Member = _members.get(seat)
	return member.controls.movement_snapshot() if member != null else null


func view(seat: StringName, now: CombatInstant) -> View:
	var member: Member = _members.get(seat)
	if member == null or now == null:
		return null
	var result := View.new()
	result.seat = seat
	result.realm = member.realm
	result.position = _position(member)
	result.connected = member.connected
	result.alive = member.body == null
	result.within_grace = _within_grace(member, now)
	result.deaths = member.deaths
	result.rescue_interruption = member.last_interruption
	if member.body != null:
		result.wait_until = member.body.ready
		result.rescue_progress = member.body.progress
	return result


func status_ids() -> Dictionary[StringName, StringName]:
	var statuses: Dictionary[StringName, StringName] = {}
	for seat: StringName in _members:
		var member := _members[seat]
		if not member.connected:
			statuses[seat] = &"disconnected"
		else:
			statuses[seat] = &"living" if member.body == null else &"down"
	return statuses


## Called after deliberate interaction with the body has been admitted.
## The authoritative pose and actual approach still have to permit it.
func begin_rescue(helper_seat: StringName, body_seat: StringName, tick: int) -> bool:
	var target: Member = _members.get(body_seat)
	if not _next_tick(tick) or not can_control(helper_seat) or target == null or target.body == null:
		return false
	var helper := _members[helper_seat]
	var now := CombatInstant.at_tick(tick)
	var position := _position(helper)
	if (target.body.ready.order_against(now) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
			or not _can_reach(helper, target, position)):
		return false
	if helper.aiding != body_seat:
		helper.aiding = body_seat
		helper.aid_pose = position
		helper.last_interruption = RescueInterruption.NONE
	return true


## Process closed combat groups before publishing rescue and encounter state.
## Both hit eliminations and lethal HP prices can create a body.
func observe_combat(wave: CombatKernel.WaveResult) -> bool:
	if (_terminal != CombatKernel.Terminal.ACTIVE or wave == null
			or wave.result != CombatKernel.Result.CLOSED or wave.due == null
			or wave.due.order_against(CombatInstant.at_tick(_tick)) != RealmCircleTime.Order.AFTER
			or wave.due.order_against(CombatInstant.at_tick(_tick + 1)) not in [
				RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]
			or (_last_combat != null and _last_combat.order_against(wave.due) != RealmCircleTime.Order.BEFORE)):
		return false
	for hit: CombatKernel.Hit in wave.hits:
		var member: Member = _actors.get(hit.target)
		if member != null and member.life == hit.target_life and hit.dealt_hostile_damage():
			_stop_aiding(member, RescueInterruption.HOSTILE_DAMAGE)
	for hit: CombatKernel.Hit in wave.eliminations:
		_record_death(hit.target, hit.target_life, wave.due)
	for activation: CombatKernel.ActivationReceipt in wave.activations:
		if activation.outcome == CombatKernel.ActivationOutcome.LETHAL:
			_record_death(activation.source, activation.life, wave.due)
	_last_combat = wave.due
	var terminal_result := wave.terminal
	if terminal_result == CombatKernel.Terminal.ACTIVE and not _has_survivor(wave.due):
		if not _kernel.end_party_defeat():
			return false
		terminal_result = CombatKernel.Terminal.DEFEAT
	if terminal_result != CombatKernel.Terminal.ACTIVE:
		_stage_terminal(terminal_result, _tick + 1)
	return true


## Advance once per active tick, after combat. An original-host suspension
## calls neither this step nor the link transition and spends no guest grace.
func close_tick(tick: int) -> bool:
	if (tick != _tick + 1 or tick > RunAuthority.MAX_TICK
			or (_terminal != CombatKernel.Terminal.ACTIVE and tick != _terminal_tick)):
		return false
	if _terminal != CombatKernel.Terminal.ACTIVE:
		return _close_terminal()
	var now := CombatInstant.at_tick(tick)
	var helpers: Dictionary[StringName, int] = {}
	for helper: Member in _members.values():
		if helper.aiding.is_empty():
			continue
		var target := _members[helper.aiding]
		var position := _position(helper)
		if target.body == null:
			_stop_aiding(helper, RescueInterruption.NONE)
		elif (position != null and _distance_squared(position, target.body.position) >
				_distance_squared(helper.aid_pose, target.body.position)):
			_stop_aiding(helper, RescueInterruption.MOVED_AWAY)
		elif not _can_reach(helper, target, position):
			_stop_aiding(helper, RescueInterruption.OBSTRUCTED)
		else:
			helper.aid_pose = position
			helpers[helper.aiding] = int(helpers.get(helper.aiding, 0)) + 1
	for body_seat: StringName in helpers:
		var member := _members[body_seat]
		member.body.progress = mini(RESCUE_PROGRESS,
			member.body.progress + HELPER_RATE[helpers[body_seat]])
		if member.body.progress == RESCUE_PROGRESS and _kernel.revive_player(
				member.actor, member.life, now, Quantity.from_count(30, 2), REVIVE_PROTECTION):
			member.life += 1
			member.body = null
			for helper: Member in _members.values():
				if helper.aiding == body_seat:
					_stop_aiding(helper, RescueInterruption.NONE)
	if not _has_survivor(now):
		if not _kernel.end_party_defeat():
			return false
		_stage_terminal(CombatKernel.Terminal.DEFEAT, tick)
		return _close_terminal()
	_tick = tick
	return true


func _stage_terminal(result: CombatKernel.Terminal, tick: int) -> void:
	_terminal = result
	_terminal_tick = tick
	_settlement_pending = _currency_authority != null


func _close_terminal() -> bool:
	if _settlement_pending:
		var authority := _currency_authority.get_ref() as RunAuthority
		if authority == null or not authority.settle_terminal_currency():
			return false
		_settlement_pending = false
	_tick = _terminal_tick
	return true


func _record_death(actor: StringName, life: int, now: CombatInstant) -> void:
	var member: Member = _actors.get(actor)
	if member == null or member.life != life or member.body != null:
		return
	member.deaths += 1
	_stop_aiding(member, RescueInterruption.DEATH)
	member.controls.release_movement()
	var body := Body.new()
	body.position = _position(member)
	var increments := mini(member.deaths - 1, MAX_WAIT)
	var wait := mini(INITIAL_WAIT + increments * WAIT_INCREMENT, MAX_WAIT)
	body.ready = now.after_ticks(wait)
	if body.ready == null:
		body.ready = CombatInstant.at_tick(RunAuthority.MAX_TICK)
	member.body = body


func _can_reach(helper: Member, body: Member, position: RealmSweep.Point) -> bool:
	if (position == null or body.body.position == null or helper.realm != body.realm
			or _distance_squared(position, body.body.position) > RESCUE_REACH ** 2):
		return false
	var route := _realms[body.realm].certify_frozen_path(body.realm, position, body.body.position, 0.0,
		_blockers, helper.actor)
	return route != null and route.contacts.is_empty() and route.unresolved.is_empty()


func _position(member: Member) -> RealmSweep.Point:
	if member.body != null:
		return PlayerControlState.copy_point(member.body.position)
	return _realms[member.realm].circle_center(member.actor, 0)


func _has_survivor(now: CombatInstant) -> bool:
	for member: Member in _members.values():
		if member.body == null and (member.connected or _within_grace(member, now)):
			return true
	return false


func _next_tick(tick: int) -> bool:
	return _terminal == CombatKernel.Terminal.ACTIVE and tick == _tick + 1 and tick <= RunAuthority.MAX_TICK


static func _within_grace(member: Member, now: CombatInstant) -> bool:
	return member.grace_until != null and now.order_against(member.grace_until) == RealmCircleTime.Order.BEFORE


static func _stop_aiding(member: Member, reason: RescueInterruption) -> void:
	if not member.aiding.is_empty():
		member.last_interruption = reason
	member.aiding = &""
	member.aid_pose = null


static func _distance_squared(first: RealmSweep.Point, second: RealmSweep.Point) -> float:
	return (first.x - second.x) ** 2 + (first.y - second.y) ** 2
