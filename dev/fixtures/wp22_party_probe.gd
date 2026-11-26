extends "res://dev/fixtures/wp06_session_probe.gd"
## Two native processes exercise the run's ordinary admitted movement and
## recipient projection. Each admitted movement steps one logical fixture tick.

const HOST := &"host"
const GUEST := &"guest"
const MAIN := &"overworld"
const SPLIT := &"observatory"
const RUN := &"wp22-party"
const Kinds := ReplicationMessage.Kind

class PartyAuthority extends RunAuthority:
	var party: RunParty
	var valid := true

	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_AXES

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _random_streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in accepted:
			valid = valid and party.apply_input(intent.seat_id, intent.command)
		valid = valid and party.step_movement(GUEST, 60.0, 1.0 / 60.0) != null and party.close_tick(tick)
		return []

var _authority := PartyAuthority.new()
var _bridge := HostMovementBridge.new()
var _movement := GuestMovement.new()
var _party: RunParty
var _progression: PartyProgression
var _host_encounter: RunEncounterPresence
var _guest_encounter: RunEncounterPresence
var _outside: RunEncounterPresence
var _connection: int
var _packet: int
var _active_profile := ProfileStore.new()
var _results: Dictionary = {}
var _saw_view := false
var _acked_reclaim := false
var _sent_leave := false


func _ready() -> void:
	super._ready()
	if not is_processing():
		return
	if _active_profile.open("wp22-%s" % _role) != ProfileStore.OpenResult.OPENED:
		_finish(false)
		return
	_results["opened_profile"] = _active_profile.identity()
	if _role == "host" and not _start_party():
		_finish(false)


func _start_party() -> bool:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = RUN
	setup.authority_id = HOST
	setup.initial_realms = {HOST: MAIN, GUEST: SPLIT}
	setup.epoch = EPOCH
	setup.seed = 22
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	var kernel := CombatKernel.new()
	var realms: Dictionary[StringName, RealmGeometry] = {}
	var preparations: Dictionary[StringName, RunPreparation] = {}
	for seat: StringName in [HOST, GUEST]:
		var realm := setup.initial_realms[seat]
		var geometry := RealmGeometry.new(realm)
		var start_x := 220.0 if seat == HOST else 221.0
		var actor := CombatantState.new()
		actor.id = seat
		actor.owner = seat
		actor.realm = realm
		actor.life = 1
		actor.max_hp = Quantity.from_count(100)
		actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
		if (not kernel.add_actor(actor) or not geometry.add_circle(seat, 0, RealmSweep.Point.new(start_x, 0), 1.0, 1)
				or not kernel.attach_geometry(geometry, 2)):
			return false
		realms[realm] = geometry
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		slots[0] = &"P01" if seat == HOST else &"P02"
		preparations[seat] = RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	_progression = PartyProgression.begin(setup, preparations)
	_party = RunParty.begin(setup, HOST, kernel, realms, {HOST: HOST, GUEST: GUEST}, 2)
	if _party == null or _progression == null or not _authority.start(setup, HOST):
		return false
	_authority.party = _party
	var now := CombatInstant.at_tick(0)
	var center := RealmSweep.Point.new(0, 0)
	_host_encounter = RunEncounterPresence.start(_party, &"host-ordinary", MAIN, center, 20.0, now)
	_guest_encounter = RunEncounterPresence.start(_party, &"guest-ordinary", SPLIT, center, 20.0, now)
	_outside = RunEncounterPresence.start(_party, &"outside-control", SPLIT, center, 20.0, now)
	return _host_encounter != null and _guest_encounter != null and _outside != null


func _run_host() -> void:
	var batch := _session.pump()
	_rejected += batch.rejected
	_lost += batch.lost_seats.size()
	_departures += batch.departures
	if batch.failure or _rejected > 0 or _lost > 1:
		_finish(false)
		return
	if not batch.lost_seats.is_empty() and not _record_guest_loss(batch.lost_seats):
		_finish(false)
		return
	for connection: int in batch.admitted:
		if not _bind_guest(connection):
			_finish(false)
			return
	for command: NativeSessionHost.Command in batch.commands:
		if not _apply_guest_command(command):
			_finish(false)
			return
	if _departures == 1 and not _closing:
		if _admitted != 2 or _lost != 1 or _snapshot().acknowledged != 4 or _snapshot().position.x != 219.0:
			_finish(false)
			return
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(true)


func _record_guest_loss(seats: Array[int]) -> bool:
	var tick := _authority.next_tick()
	_bridge.unbind(1, _connection, EPOCH)
	if seats != [1] or tick != 4 or not _party.set_guest_connected(GUEST, false, tick):
		return false
	if not _authority.close_tick() or not _authority.valid or _snapshot().position.x != 220.0:
		return false
	var now := CombatInstant.at_tick(tick)
	if not _host_encounter.settle(now) or not _guest_encounter.settle(now):
		return false
	_results["host_local"] = _host_encounter.recipients()
	_results["guest_local_in_grace"] = _guest_encounter.recipients()
	_results["stationary_x"] = _snapshot().position.x
	_results["disconnected"] = _party.status_ids()[GUEST] == &"disconnected"
	_results["locked_hp_scale"] = _party.hp_scale().native_at_scale(2)
	if _progression.grant_xp(_host_encounter.id, Quantity.from_count(100), tick) != PartyProgression.Award.APPLIED:
		return false
	var host_offer := _progression.offer(HOST, 1)
	var guest_offer := _progression.offer(GUEST, 1)
	if host_offer == null or guest_offer == null:
		return false
	_results["host_frozen"] = host_offer.options.keys()
	_results["guest_frozen"] = guest_offer.options.keys()
	var save := ProfileMutation.new()
	save.id = "wp22-shared-xp"
	save.rules = "V42.6/R1"
	save.catalog = String(_authority.checkpoint()["identity"]["catalog"])
	save.frontier = _progression.frontier(tick)
	if _active_profile.commit(save).status != ProfileStore.CommitResult.COMMITTED:
		return false
	_results["host_frontier_tick"] = _active_profile.frontier(String(RUN))["tick"]
	print("WP06_SESSION_PHASE host-observed-loss")
	return _write(_loss_path, PackedByteArray([1]))


func _bind_guest(connection: int) -> bool:
	_admitted += 1
	if _admitted > 2 or not _bridge.bind(1, connection, EPOCH, RUN, EPOCH, SPLIT, GUEST, _admitted):
		return false
	_connection = connection
	if _admitted == 2 and not _party.set_guest_connected(GUEST, true, _authority.next_tick()):
		return false
	var baseline := MovementBaseline.new()
	baseline.realm = SPLIT
	baseline.state = _snapshot()
	return _send(Kinds.BASELINE, baseline.pack())


func _apply_guest_command(command: NativeSessionHost.Command) -> bool:
	if _bridge.submit(_authority, command) != RunAuthority.Admission.QUEUED or not _authority.close_tick() or not _authority.valid:
		return false
	var state := _snapshot()
	var now := CombatInstant.at_tick(state.tick)
	if _admitted == 1:
		if not _guest_encounter.observe(now):
			return false
		match state.acknowledged:
			1: _results["inclusive_x"] = state.position.x
			2:
				if not _outside.settle(now):
					return false
				_results["outside"] = _outside.recipients().is_empty()
			3: _results["return_x"] = state.position.x
	elif not _publish_guest_view(now):
		return false
	return _send(Kinds.STATE, state.pack())


func _publish_guest_view(now: CombatInstant) -> bool:
	var scope := RecipientView.Scope.new()
	scope.seat = GUEST
	scope.realm = SPLIT
	scope.actors = {GUEST: true}
	var actors: Array[RecipientView.Actor] = []
	for seat: StringName in _party.initialized_seats():
		var source := _party.view(seat, now)
		var actor := RecipientView.Actor.new()
		actor.id = seat
		actor.realm = source.realm
		actor.position = source.position
		actors.append(actor)
	var view := RecipientView.pack(scope, EPOCH, _admitted, now.tick, _progression.level(), "0",
		_party.status_ids(), actors, [], null)
	return _send(Kinds.VIEW, view)


func _guest_ready(_peer: ENetPacketPeer) -> bool:
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	if frame.generation != EPOCH or _guest_stage != 3:
		return false
	var wire := ReplicationMessage.read(frame)
	if wire == null:
		return false
	if wire.kind == Kinds.VIEW:
		var view := RecipientView.read(wire.body)
		if (_mode != "reclaim" or view == null or StringName(view.realm) != SPLIT or view.level != 2
				or view.party.size() != 2 or view.actors.has("host") or not view.actors.has("guest")):
			return false
		_saw_view = true
		_results["realm"] = view.realm
		_results["level"] = view.level
		_results["visible_actor_ids"] = view.actors.keys()
		_results["party_status"] = view.party
		return _leave_after_receipts(peer)
	if _movement.receive_frame(frame) != GuestMovement.Acceptance.APPLIED:
		return false
	var scope := _movement.confirmed_scope()
	var ack := scope.state.acknowledged
	if wire.kind == Kinds.BASELINE:
		_frames[RELIABLE] = true
		_results["baseline_ack"] = ack
		return _move(peer, -1.0, ack + 1)
	var expected := 221.0 if ack == 2 else (219.0 if ack == 4 else 220.0)
	if wire.kind != Kinds.STATE or scope.state.position.x != expected:
		return false
	if ack < 3:
		return _move(peer, 1.0 if ack == 1 else -1.0, ack + 1)
	_frames[SEQUENCED] = true
	_results["closed_ack"] = ack
	_results["authoritative_x"] = scope.state.position.x
	if _mode == "abrupt":
		return ack == 3 and _write(_handoff_path, PackedByteArray([1]))
	_acked_reclaim = ack == 4
	return _acked_reclaim and _leave_after_receipts(peer)


func _leave_after_receipts(peer: ENetPacketPeer) -> bool:
	if not _saw_view or not _acked_reclaim or _sent_leave:
		return true
	_sent_leave = true
	return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK


func _move(peer: ENetPacketPeer, x: float, sequence: int) -> bool:
	var input := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, x))
	return not input.is_empty() and _link.send(peer, SEQUENCED, EPOCH, sequence, input) == OK


func _snapshot() -> MovementSnapshot:
	var state := MovementSnapshot.new()
	state.epoch = EPOCH
	state.baseline = _admitted
	state.tick = _authority.next_tick() - 1
	state.serial = state.tick + 1
	state.acknowledged = _authority.checkpoint()["sequences"][GUEST]
	state.position = _party.view(GUEST, CombatInstant.at_tick(state.tick)).position
	state.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES)
	state.speed = 60.0
	state.radius = 1.0
	return state


func _send(kind: ReplicationMessage.Kind, bytes: PackedByteArray) -> bool:
	_packet += 1
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), _packet,
		ReplicationMessage.pack(kind, bytes)) == OK


func _finish(passed: bool) -> void:
	_active_profile.close()
	_results["passed"] = passed
	print("WP22_PARTY ", JSON.stringify(_results))
	super._finish(passed)
