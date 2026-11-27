extends "res://dev/fixtures/wp06_session_probe.gd"
## Scoped travel through the production adapters on two disposable native peers.

const HOST := &"host"
const GUEST := &"guest"
const RUN := &"wp25-native-passage"
const OUTSIDE := WorldTopology.OVERWORLD
const GARDEN := &"silent_garden"
const SEED := 2507
const SPEED := 60.0
const RADIUS := 4.0
const Kinds := ReplicationMessage.Kind
const Queued := RunAuthority.Admission.QUEUED

class PassageAuthority extends RunAuthority:
	var party: RunParty
	var clicks: Array[RunIntent] = []
	var valid := true

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.MOVE_AXES, PlayerCommand.INTERACT]

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		clicks.clear()
		for intent: RunIntent in accepted:
			if intent.action == PlayerCommand.INTERACT:
				clicks.append(intent)
			else:
				valid = valid and party.apply_input(intent.seat_id, intent.command)
		valid = valid and party.step_movement(GUEST, SPEED, 1.0 / 60.0) != null and party.close_tick(tick)
		return []

var _authority := PassageAuthority.new()
var _bridge := HostMovementBridge.new(_authority)
var _passages: RunRealmPassages
var _party: RunParty
var _rooms: Dictionary[StringName, WorldExploration] = {}
var _movement := GuestMovement.new()
var _replica := GuestReplica.new()
var _connection: int
var _baseline := 1
var _published: int
var _received_click := false
var _received_motion := false
var _sent_click := PackedByteArray()
var _facts: Dictionary = {}


func _ready() -> void:
	super._ready()
	if is_processing() and _role == "host" and not _start_run():
		_finish(false)


func _start_run() -> bool:
	_rooms[OUTSIDE] = WorldExploration.create(WorldTopology.generate(SEED), [HOST, GUEST])
	_rooms[GARDEN] = WorldExploration.create(WorldTopology.generate_optional(SEED, GARDEN), [HOST, GUEST])
	var kernel := CombatKernel.new()
	var floors: Dictionary[StringName, RealmGeometry] = {}
	for id: StringName in _rooms:
		floors[id] = _rooms[id].geometry()
		if not kernel.attach_geometry(floors[id], WorldExploration.BLOCKER):
			return false
	var handle := _rooms[OUTSIDE].module_center(WorldTopology.ANCHORS[0])
	for seat: StringName in [HOST, GUEST]:
		var player := CombatantState.new()
		player.id = seat
		player.owner = seat
		player.life = 1
		player.realm = OUTSIDE
		player.max_hp = Quantity.from_count(20)
		player.hp = QuantityLayerLedger.Pool.new(player.max_hp, QuantityErrorBounds.new())
		var position := RealmSweep.Point.new(handle.x - 24.0, handle.y) if seat == HOST else handle
		if not kernel.add_actor(player) or not floors[OUTSIDE].add_circle(seat, 0, position, RADIUS, 2):
			return false
		_rooms[OUTSIDE].observe_seat(seat, OUTSIDE, position)
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = RUN
	setup.authority_id = HOST
	setup.epoch = EPOCH
	setup.seed = SEED
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"starter"
	setup.challenge_id = &"normal"
	setup.initial_realms = {HOST: OUTSIDE, GUEST: OUTSIDE}
	_party = RunParty.begin(setup, HOST, kernel, floors, {HOST: HOST, GUEST: GUEST}, WorldExploration.BLOCKER)
	_authority.party = _party
	_passages = RunRealmPassages.new(_authority, _party)
	return (_party != null and _authority.start(setup, HOST)
		and _passages.register_optional(&"garden", _rooms[OUTSIDE], handle, _rooms[GARDEN], 36.0, 10.0))


func _run_host() -> void:
	var batch := _session.pump()
	_admitted += batch.admitted.size()
	_rejected += batch.rejected
	_departures += batch.departures
	_lost += batch.lost_seats.size()
	if batch.failure or _admitted > 1 or _rejected != 0 or _lost != 0:
		_finish(false)
		return
	for connection: int in batch.admitted:
		_connection = connection
		if not _publish_scope():
			_finish(false)
			return
	for command: NativeSessionHost.Command in batch.commands:
		if not _queue_command(command):
			_finish(false)
			return
	if _received_motion and _received_click and not _close_and_publish():
		_finish(false)
		return
	if _departures == 1 and not _closing:
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(_authority.next_tick() == 3 and _facts.get("stale_refused", false))


func _queue_command(command: NativeSessionHost.Command) -> bool:
	var wire := ReplicationMessage.read(command.frame)
	if wire == null:
		return false
	if wire.kind == Kinds.MOVEMENT and not _received_motion:
		_received_motion = _bridge.submit(_authority, command) == Queued
		return _received_motion
	if wire.kind == Kinds.INTERACTION and not _received_click:
		var admission := _bridge.submit_interaction(command)
		_received_click = admission == (Queued if _baseline == 1 else RunAuthority.Admission.UNSUPPORTED_ACTION)
		if _baseline == 2:
			_facts["stale_refused"] = _received_click
		return _received_click
	return false


func _close_and_publish() -> bool:
	_received_click = false
	_received_motion = false
	if not _authority.close_tick() or not _authority.valid:
		return false
	var state := _snapshot()
	if _baseline == 1:
		if (_authority.clicks.size() != 1 or state.acknowledged != 1
				or _authority.clicks[0].sequence != 1 or not _passages.interact(_authority.clicks[0])):
			return false
		_baseline = 2
		_facts["crossed_tick"] = state.tick
		_facts["source_moved_one_unit"] = state.position.x == _rooms[OUTSIDE].module_center(WorldTopology.ANCHORS[0]).x + 1.0
		return _facts["source_moved_one_unit"] and _publish_scope()
	_facts["host_realm"] = _party.view(HOST, CombatInstant.at_tick(state.tick)).realm
	_facts["guest_realm"] = _party.view(GUEST, CombatInstant.at_tick(state.tick)).realm
	_facts["movement_ack"] = state.acknowledged
	return (state.acknowledged == 2 and _facts["host_realm"] == OUTSIDE and _facts["guest_realm"] == GARDEN
		and _authority.clicks.is_empty() and _send(Kinds.STATE, state.pack()))


func _publish_scope() -> bool:
	var state := _snapshot()
	var now := CombatInstant.at_tick(state.tick)
	var baseline := MovementBaseline.new()
	baseline.realm = _party.view(GUEST, now).realm
	baseline.state = state
	if not _bridge.bind(1, _connection, EPOCH, RUN, EPOCH, baseline.realm, GUEST, _baseline):
		return false
	var scope := RecipientView.Scope.new()
	scope.seat = GUEST
	scope.realm = baseline.realm
	scope.actors = {HOST: true, GUEST: true}
	var actors: Array[RecipientView.Actor] = []
	for seat: StringName in _party.initialized_seats():
		var view := _party.view(seat, now)
		var actor := RecipientView.Actor.new()
		actor.id = seat
		actor.realm = view.realm
		actor.position = view.position
		actors.append(actor)
	var view_bytes := RecipientView.pack(scope, EPOCH, _baseline, state.tick, 1, "0", _party.status_ids(),
		actors, [], _rooms[scope.realm])
	return _send(Kinds.BASELINE, baseline.pack()) and _send(Kinds.VIEW, view_bytes)


func _snapshot() -> MovementSnapshot:
	var result := MovementSnapshot.new()
	result.epoch = EPOCH
	result.baseline = _baseline
	result.tick = _authority.next_tick() - 1
	result.serial = result.tick + 1
	result.acknowledged = _authority.checkpoint()["sequences"][GUEST]
	result.position = _party.view(GUEST, CombatInstant.at_tick(result.tick)).position
	result.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES)
	result.speed = SPEED
	result.radius = RADIUS
	return result


func _send(kind: ReplicationMessage.Kind, bytes: PackedByteArray) -> bool:
	_published += 1
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), _published,
		ReplicationMessage.pack(kind, bytes)) == OK


func _guest_ready(_peer: ENetPacketPeer) -> bool:
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	var wire := ReplicationMessage.read(frame)
	if wire == null or frame.generation != EPOCH or _guest_stage != 3:
		return false
	if wire.kind == Kinds.VIEW:
		return _receive_view(peer, frame, wire.body)
	if _movement.receive_frame(frame) != GuestMovement.Acceptance.APPLIED:
		return false
	var scope := _movement.confirmed_scope()
	if wire.kind == Kinds.BASELINE:
		return _replica.install_scope(scope.realm, scope.state)
	if scope.realm != GARDEN or scope.state.acknowledged != 2 or scope.state.tick != 2:
		return false
	_facts["movement_ack"] = scope.state.acknowledged
	_frames[SEQUENCED] = true
	return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK


func _receive_view(peer: ENetPacketPeer, frame: NativeSessionFrame, body: PackedByteArray) -> bool:
	if _replica.receive_frame(frame) != GuestReplica.Acceptance.APPLIED:
		return false
	var view := RecipientView.read(body)
	if view.party != {"host": "living", "guest": "living"}:
		return false
	if view.baseline == 1:
		if view.realm != String(OUTSIDE) or view.tick != 0 or _replica.actor_ids() != ["guest", "host"]:
			return false
		var at := _movement.position()
		_sent_click = _movement.interaction_packet(PlayerCommand.new(PlayerCommand.INTERACT, at.x, at.y))
	else:
		if view.baseline != 2 or view.realm != String(GARDEN) or view.tick != 1 or _replica.actor_ids() != ["guest"]:
			return false
		_facts["arrival_realm"] = view.realm
		_facts["visible"] = _replica.actor_ids()
		_facts["party"] = view.party
		_facts["arrival_cell_seen"] = not view.explored.is_empty()
		_frames[RELIABLE] = true
	var movement := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
	return (_link.send(peer, SEQUENCED, EPOCH, view.baseline, movement) == OK
		and _link.send(peer, RELIABLE, EPOCH, view.baseline, _sent_click) == OK)


func _finish(passed: bool) -> void:
	print("WP25_NATIVE ", JSON.stringify(_facts))
	super._finish(passed)
