extends "res://dev/fixtures/wp06_session_probe.gd"
## Exercises same-host reclaim with the protected controller and the movement watermark.

const REALM := &"reclaim_realm"
const SEAT := &"guest"
const RUN := &"reclaim_run"
const Kinds := ReplicationMessage.Kind
const Accepted := GuestMovement.Acceptance

class ReclaimAuthority extends RunAuthority:
	var x: int

	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_AXES

	func _resolve_tick(_tick: int, intents: Array[RunIntent], _random_streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in intents:
			x += int(intent.command.x)
		return []

var _authority := ReclaimAuthority.new()
var _bridge := HostMovementBridge.new()
var _movement := GuestMovement.new()
var _connection: int
var _old_command: NativeSessionHost.Command
var _results: Dictionary = {}


func _ready() -> void:
	super._ready()
	if _role != "host":
		return
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.authority_id = &"host"
	setup.epoch = EPOCH
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"reclaim_fixture"
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	if not _authority.start(setup, &"host"):
		_finish(false)


func _run_host() -> void:
	var batch := _session.pump()
	if not batch.admitted.is_empty() or batch.rejected > 0 or not batch.lost_seats.is_empty():
		print("WP12_RECLAIM_EVENTS ", JSON.stringify({"admitted": batch.admitted, "rejected": batch.rejected,
			"lost": batch.lost_seats}))
	_rejected += batch.rejected
	_lost += batch.lost_seats.size()
	_departures += batch.departures
	if batch.failure or _rejected > 1 or _lost > 1:
		_finish(false)
		return
	if not batch.lost_seats.is_empty():
		if batch.lost_seats != [1] or _admitted != 1 or not _write(_loss_path, PackedByteArray([1])):
			_finish(false)
			return
		_bridge.unbind(1, _connection, EPOCH)
		print("WP06_SESSION_PHASE host-observed-loss")
	for connection: int in batch.admitted:
		_admitted += 1
		if _admitted > 2 or not _bridge.bind(1, connection, EPOCH, RUN, EPOCH, REALM, SEAT, _admitted):
			_finish(false)
			return
		if _admitted == 2:
			_results["replacement_connection"] = connection
			_results["old_movement_fenced"] = _bridge.submit(_authority, _old_command) == RunAuthority.Admission.WRONG_SEAT
			if connection <= _connection or not _results["old_movement_fenced"]:
				_finish(false)
				return
		else:
			_results["original_connection"] = connection
		_connection = connection
		var baseline := MovementBaseline.new()
		baseline.realm = REALM
		baseline.state = _snapshot()
		if not _send(Kinds.BASELINE, baseline.pack()):
			_finish(false)
			return
	for command: NativeSessionHost.Command in batch.commands:
		if _bridge.submit(_authority, command) != RunAuthority.Admission.QUEUED or not _authority.close_tick():
			_finish(false)
			return
		if _admitted == 1:
			_old_command = command
		if not _send(Kinds.STATE, _snapshot().pack()):
			_finish(false)
			return
	if _departures == 1 and not _closing:
		if _admitted != 2 or _authority.x != 2 or _rejected != 1 or _lost != 1:
			_finish(false)
			return
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_results["authoritative_x"] = _authority.x
		_results["generation"] = EPOCH
		_finish(true)


func _guest_ready(_peer: ENetPacketPeer) -> bool:
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		var handshake := super._accept(peer, frame)
		if not handshake:
			_results["admission_stage"] = _guest_stage
		return handshake
	if frame.generation != EPOCH or _guest_stage != 3:
		return false
	var expected := 2 if _mode == "reclaim" else 1
	var wire := ReplicationMessage.read(frame)
	var verdict := _movement.receive_frame(frame)
	if wire == null or verdict != Accepted.APPLIED:
		_results["movement_verdict"] = verdict
		return false
	var scope := _movement.confirmed_scope()
	if scope == null or scope.state.baseline != expected:
		_results["unexpected_baseline"] = scope.state.baseline if scope != null else 0
		return false
	if wire.kind == Kinds.BASELINE and scope.state.acknowledged == expected - 1:
		_frames[RELIABLE] = true
		_results["baseline_ack"] = scope.state.acknowledged
		var input := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
		return not input.is_empty() and _link.send(peer, SEQUENCED, EPOCH, expected, input) == OK
	if wire.kind == Kinds.STATE and scope.state.acknowledged == expected and _movement.position().x == float(expected):
		_frames[SEQUENCED] = true
		_results["closed_ack"] = scope.state.acknowledged
		_results["draw_x"] = _movement.draw_position(1.0).x
		if _mode == "abrupt":
			return _write(_handoff_path, PackedByteArray([1]))
		return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK
	return false


func _snapshot() -> MovementSnapshot:
	var snapshot := MovementSnapshot.new()
	snapshot.epoch = EPOCH
	snapshot.baseline = _admitted
	snapshot.tick = _authority.next_tick() - 1
	snapshot.serial = snapshot.tick + 1
	snapshot.acknowledged = _authority.checkpoint()["sequences"][SEAT]
	snapshot.position = RealmSweep.Point.new(_authority.x, 0.0)
	snapshot.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES)
	snapshot.speed = 60.0
	snapshot.radius = 1.0
	return snapshot


func _send(kind: ReplicationMessage.Kind, bytes: PackedByteArray) -> bool:
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), _admitted,
		ReplicationMessage.pack(kind, bytes)) == OK


func _finish(passed: bool) -> void:
	_results["passed"] = passed
	print("WP12_RECLAIM ", JSON.stringify(_results))
	super._finish(passed)
