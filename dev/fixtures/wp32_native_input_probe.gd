extends "res://dev/fixtures/wp06_session_probe.gd"
## Controlled authenticated guest input to the same WP32 encounter owner.

const HOST := &"host"
const GUEST := &"guest"
const RUN := &"wp32-native-input"
const REALM := WorldTopology.OVERWORLD
const KINDS := ReplicationMessage.Kind
const QUEUED := RunAuthority.Admission.QUEUED
const ROSTER: CatalogBundle = preload("res://src/catalog/starter_roster.tres")

var _encounter: StarterEncounter
var _bridge: HostMovementBridge
var _movement := GuestMovement.new()
var _connection: int
var _baseline := 1
var _sent: int
var _move_ready := false
var _cast_ready := false
var _stale_refused := false
var _old_cast := PackedByteArray()
var _facts: Dictionary = {}


func _ready() -> void:
	super._ready()
	if is_processing() and _role == "host" and not _assemble():
		_finish(false)


func _assemble() -> bool:
	var catalog := ROSTER.compile()
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = RUN
	setup.seed = 3207
	setup.epoch = EPOCH
	setup.authority_id = HOST
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"encounter-fixture"
	setup.initial_realms = {HOST: REALM, GUEST: REALM}
	var world := WorldExploration.create(WorldTopology.generate(setup.seed), [HOST, GUEST])
	var builds: Dictionary[StringName, StarterEncounter.Build] = {}
	for id: StringName in [HOST, GUEST]:
		var build := StarterEncounter.Build.new()
		build.preparation = prep
		build.powers = RunRewardQueue.begin(prep, RunRandom.new(setup.seed), id)
		build.start = RealmSweep.Point.new(46, 210) if id == HOST else RealmSweep.Point.new(90, 128)
		build.maximum_hp = Quantity.from_count(100)
		builds[id] = build
	_encounter = StarterEncounter.assemble(setup, HOST, world, builds)
	if _encounter == null:
		return false
	_bridge = HostMovementBridge.new(_encounter)
	var enemy := WorldEnemy.Rules.new()
	enemy.faction = &"sparring"
	enemy.foes = [WorldEnemy.PARTY]
	enemy.family = &"fixture/sweep"
	enemy.hp = Quantity.from_count(300)
	enemy.damage = Quantity.from_count(16)
	enemy.radius = 12.0
	enemy.sight = 154.0
	enemy.attack_range = 103.0
	enemy.attack_radius = 26.0
	enemy.windup_ticks = 39
	enemy.recovery_ticks = 78
	return _encounter.place_enemy(&"sparring-foe", enemy, RealmSweep.Point.new(155, 128))


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
		if not _publish_baseline():
			_finish(false)
			return
	for command: NativeSessionHost.Command in batch.commands:
		if not _queue(command):
			_finish(false)
			return
	if _move_ready and _cast_ready and (_baseline == 1 or _stale_refused) and not _close_round():
		_finish(false)
		return
	if _departures == 1 and not _closing:
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(_facts.get("cooldown_refused", false))


func _queue(command: NativeSessionHost.Command) -> bool:
	var wire := ReplicationMessage.read(command.frame)
	if wire == null:
		return false
	if wire.kind == KINDS.MOVEMENT and not _move_ready:
		_move_ready = _bridge.submit(_encounter, command) == QUEUED
		return _move_ready
	if wire.kind == KINDS.INTERACTION:
		var admission := _bridge.submit_interaction(command)
		if _baseline == 2 and command.frame.sequence == 2:
			_stale_refused = admission == RunAuthority.Admission.UNSUPPORTED_ACTION
			return _stale_refused
		if not _cast_ready:
			_cast_ready = admission == QUEUED
			return _cast_ready
	return false


func _close_round() -> bool:
	_move_ready = false
	_cast_ready = false
	if not _encounter.close_tick() or not _encounter.fault().is_empty():
		return false
	var state := _snapshot()
	var closed := _encounter.closed_result()
	if closed["accepted"].size() != 2 or state.acknowledged != _baseline:
		return false
	var committed := false
	var guest_hit := false
	for event: Dictionary in closed["outcomes"]:
		if event.get("seat") == GUEST and event.has("manual"):
			committed = bool(event.manual)
		if event.get("family") == StarterCombatRules.SIPHON and event.get("owner") == GUEST and event.get("damage"):
			guest_hit = true
	if _baseline == 1:
		var view := _encounter.view_for(GUEST)
		if not committed or not guest_hit or state.position.x <= 90.0 or view.barrier.native_at_scale(0) != 18:
			return false
		_facts = {"cast_tick": state.tick, "guest_owned_hit": guest_hit, "barrier": 18, "movement_ack": state.acknowledged}
		_baseline = 2
		return _publish_baseline()
	_facts["stale_refused"] = _stale_refused
	_facts["cooldown_refused"] = not committed and not guest_hit
	_facts["new_movement_ack"] = state.acknowledged
	return bool(_facts.cooldown_refused) and _publish(KINDS.STATE, state.pack())


func _snapshot() -> MovementSnapshot:
	var view := _encounter.view_for(GUEST)
	var state := MovementSnapshot.new()
	state.epoch = EPOCH
	state.baseline = _baseline
	state.tick = view.tick
	state.serial = view.tick + 1
	state.acknowledged = _encounter.checkpoint()["sequences"][GUEST]
	state.position = view.player.at
	state.speed = PlayerControlState.REFERENCE_SPEED
	state.radius = view.player.radius
	state.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0 if view.tick == 1 else 0.0)
	return state


func _publish_baseline() -> bool:
	var baseline := MovementBaseline.new()
	baseline.realm = REALM
	baseline.state = _snapshot()
	return (_bridge.bind(1, _connection, EPOCH, RUN, EPOCH, REALM, GUEST, _baseline)
		and _publish(KINDS.BASELINE, baseline.pack()))


func _publish(kind: ReplicationMessage.Kind, payload: PackedByteArray) -> bool:
	_sent += 1
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), _sent,
		ReplicationMessage.pack(kind, payload)) == OK


func _guest_ready(_peer: ENetPacketPeer) -> bool:
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	var wire := ReplicationMessage.read(frame)
	if (wire == null or frame.generation != EPOCH or _guest_stage != 3
			or _movement.receive_frame(frame) != GuestMovement.Acceptance.APPLIED):
		return false
	var scope := _movement.confirmed_scope()
	if wire.kind == KINDS.STATE:
		if scope.state.acknowledged != 2 or scope.state.tick != 2 or scope.state.baseline != 2:
			return false
		_facts["last_ack"] = 2
		_frames[SEQUENCED] = true
		return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK
	if wire.kind != KINDS.BASELINE or scope.realm != REALM:
		return false
	var action := PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)
	if scope.state.baseline == 1 and scope.state.tick == 0:
		_old_cast = _movement.interaction_packet(action)
		return (_link.send(peer, SEQUENCED, EPOCH, 1, _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))) == OK
			and _link.send(peer, RELIABLE, EPOCH, 1, _old_cast) == OK)
	if scope.state.baseline != 2 or scope.state.tick != 1 or scope.state.acknowledged != 1:
		return false
	_facts["first_ack"] = 1
	_frames[RELIABLE] = true
	return (_link.send(peer, SEQUENCED, EPOCH, 2, _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES))) == OK
		and _link.send(peer, RELIABLE, EPOCH, 2, _old_cast) == OK
		and _link.send(peer, RELIABLE, EPOCH, 3, _movement.interaction_packet(action)) == OK)


func _finish(passed: bool) -> void:
	print("WP32_NATIVE_INPUT ", JSON.stringify(_facts))
	super._finish(passed)
