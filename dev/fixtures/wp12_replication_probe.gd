extends "res://dev/fixtures/wp06_session_probe.gd"
## Drives the qualified transport with a labeled movement and visibility fixture.

const Kinds := ReplicationMessage.Kind
const Accepted := GuestMovement.Acceptance
const REALM := &"probe_realm"
const RUN := &"probe_run"
const SEAT := &"guest"
const BODY := &"character"
const RUN_EPOCH := 2
const BASELINE := 2

class ProbeAuthority extends RunAuthority:
	var controls := PlayerControlState.new()
	var geometry := RealmGeometry.new(REALM)
	var moved := false

	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_AXES or action == PlayerCommand.MOVE_TO

	func _resolve_tick(_tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in accepted:
			controls.apply(intent.command)
		moved = controls.step(geometry, BODY, 0, 1, 60.0, GuestMovement.SECONDS_PER_TICK) != null
		return []

var _movement := GuestMovement.new()
var _bridge := HostMovementBridge.new()
var _authority := ProbeAuthority.new()
var _peer: ENetPacketPeer
var _connection: int
var _host_state: int
var _next_publish: int
var _resync_started: int
var _resync_sequence: int
var _baseline_at: int
var _move_at: int
var _motion_ticks: int
var _movement_sequence: int
var _ack_at: int
var _leave_at: int
var _caught_stale := false
var _saw_snap := false
var _saw_view := false
var _avatar: Polygon2D
var _result: Dictionary = {}


func _ready() -> void:
	super._ready()
	if _role == "host":
		var setup := RunSetup.new()
		setup.run_id = RUN
		setup.authority_id = &"host"
		setup.epoch = RUN_EPOCH
		setup.rules_revision = &"V42.6/R1"
		setup.catalog_revision = &"fixture"
		setup.challenge_id = &"fixture"
		setup.initial_realms = {SEAT: REALM}
		var edge := RealmOutline.Edge.new()
		edge.first = _wall().first
		edge.last = _wall().last
		if (not _authority.start(setup, &"host")
				or not _authority.geometry.add_circle(BODY, 0, RealmSweep.Point.new(0.0, 0.0), 1.0, 2)
				or not _authority.geometry.add_segment(&"wall", 0, edge, 1, true)):
			_finish(false)
	elif _role == "guest" and DisplayServer.get_name() != "headless":
		_make_stage()


func _physics_process(_delta: float) -> void:
	if _role != "guest" or _motion_ticks >= 7 or _move_at > 0 or not is_processing():
		return
	if _baseline_at > 0 and _movement.advance():
		_motion_ticks += 1


func _run_host() -> void:
	var batch := _session.pump()
	if batch.failure or batch.rejected != 0 or not batch.lost_seats.is_empty():
		_finish(false)
		return
	for command: NativeSessionHost.Command in batch.commands:
		if not _host_receive(command):
			_finish(false)
			return
	var now := Time.get_ticks_msec()
	if _next_publish > 0 and now >= _next_publish:
		_next_publish = 0
		if not _publish():
			_finish(false)
			return
	if batch.departures > 0:
		if batch.departures != 1 or _host_state != 6:
			_finish(false)
			return
		_result["host_owned_leave"] = true
		print("WP06_SESSION_PHASE host-draining")
		_closing = true
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(true)


func _host_receive(command: NativeSessionHost.Command) -> bool:
	var wire := ReplicationMessage.read(command.frame)
	if wire == null or command.seat != 1:
		return false
	if wire.kind == Kinds.RESYNC and wire.body.size() == 16:
		var epoch := wire.body.decode_s64(0)
		var baseline := wire.body.decode_s64(8)
		if _host_state == 0 and epoch == 0 and baseline == 0:
			_connection = command.connection
			_host_state = 1
			_result["withheld_initial_baselines"] = 1
			return _send_host(Kinds.STATE, 1, _state(1, 0.0).pack())
		if _host_state == 1 and command.connection == _connection and epoch == RUN_EPOCH and baseline == BASELINE:
			_host_state = 2
			_next_publish = Time.get_ticks_msec() + 65
			return true
	if wire.kind != Kinds.MOVEMENT or _host_state != 3:
		return false
	if _bridge.submit(_authority, command) != RunAuthority.Admission.QUEUED or not _authority.close_tick():
		return false
	var pose := _authority.geometry.circle_center(BODY, 0)
	if not _authority.moved or pose.x != 1.0:
		return false
	_result["host_movement_x"] = pose.x
	_host_state = 4
	_next_publish = Time.get_ticks_msec() + 37
	return true


func _publish() -> bool:
	match _host_state:
		2:
			if not _bridge.bind(1, _connection, EPOCH, RUN, RUN_EPOCH, REALM, SEAT, BASELINE):
				return false
			var reset := MovementBaseline.new()
			reset.realm = REALM
			reset.state = _state(1, 0.0)
			reset.blockers = [_wall()]
			_host_state = 3
			return _send_host(Kinds.BASELINE, 1, reset.pack())
		4:
			var state := _state(2, 1.0)
			state.tick = 1
			state.acknowledged = _authority.checkpoint()["sequences"][SEAT]
			state.movement = _authority.controls.movement_snapshot()
			_result["closed_movement_ack"] = state.acknowledged
			_host_state = 5
			_next_publish = Time.get_ticks_msec() + 91
			return _send_host(Kinds.STATE, 2, state.pack()) and _send_host(Kinds.VIEW, 2, _view())
		5:
			if not _authority.geometry.commit_circle_pose(BODY, 0, RealmSweep.Point.new(9.0, 0.0)):
				return false
			var state := _state(3, _authority.geometry.circle_center(BODY, 0).x)
			state.tick = 2
			state.acknowledged = 1
			state.permits_prediction = false
			state.forced_correction = true
			_host_state = 6
			_next_publish = Time.get_ticks_msec() + 37
			return _send_host(Kinds.STATE, 3, state.pack())
		6:
			var stale := _state(4, 999.0)
			stale.epoch = RUN_EPOCH - 1
			return _send_host(Kinds.STATE, 4, stale.pack())
	return false


func _guest_ready(peer: ENetPacketPeer) -> bool:
	_peer = peer
	return _request_baseline()


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	if frame.generation != EPOCH or _guest_stage != 3:
		return false
	var wire := ReplicationMessage.read(frame)
	if wire == null:
		return false
	if wire.kind == Kinds.VIEW:
		return _observe_view(wire.body)
	var verdict := _movement.receive_frame(frame)
	if verdict == Accepted.NEED_BASELINE and _baseline_at == 0:
		_result["missing_baseline_detected"] = true
		return _resync_sequence == 1 and _request_baseline()
	if verdict == Accepted.STALE and _saw_snap:
		_caught_stale = _movement.position().x == 9.0
		_result["stale_epoch_preserved_pose"] = _caught_stale
		return _caught_stale
	if verdict != Accepted.APPLIED:
		return false
	if wire.kind == Kinds.BASELINE:
		_baseline_at = Time.get_ticks_msec()
		_result["resync_ms"] = _baseline_at - _resync_started
		var dropped := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
		_result["dropped_movement_messages"] = int(not dropped.is_empty())
		return not dropped.is_empty()
	if _movement.latest_packet().is_empty() and _ack_at == 0 and frame.sequence == 2:
		_ack_at = Time.get_ticks_msec()
		_result["retry_to_ack_ms"] = _ack_at - _move_at
		_result["pending_after_ack"] = _movement.pending_count()
		return _move_at > 0 and _movement.pending_count() == 0
	if frame.sequence == 3:
		_saw_snap = (_movement.draw_position(0.0).x == 9.0 and not _movement.advance()
			and _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, -1.0)).is_empty())
		_result["forced_snap_draw_x"] = _movement.draw_position(0.0).x
		return _saw_snap
	return false


func _run_guest() -> void:
	super._run_guest()
	if not is_processing():
		return
	if _avatar != null and _movement.position() != null:
		_avatar.position.x = 160.0 + float(_movement.draw_position(0.55).x) * 40.0
	var now := Time.get_ticks_msec()
	if _motion_ticks == 7 and _move_at == 0:
		var position := _movement.position().x
		_result["predicted_wall_x"] = position
		if absf(position - 4.0) > 0.000001 or not _retry_movement(now):
			_finish(false)
			return
		_capture("wall.png")
	if _caught_stale and _saw_view and _leave_at == 0:
		_leave_at = now + 100
		_capture("forced.png")
	if _leave_at > 0 and now >= _leave_at:
		_leave_at = -1
		_frames[SEQUENCED] = true
		_frames[RELIABLE] = true
		print("WP06_SESSION_PHASE guest-requested-leave")
		if _link.send(_peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) != OK:
			_finish(false)


func _request_baseline() -> bool:
	_resync_sequence += 1
	_resync_started = Time.get_ticks_msec()
	return _link.send(_peer, RELIABLE, EPOCH, _resync_sequence, _movement.resync_request()) == OK


func _retry_movement(now: int) -> bool:
	_move_at = now
	_movement_sequence += 1
	_result["held_movement_ms"] = now - _baseline_at
	return _link.send(_peer, SEQUENCED, EPOCH, _movement_sequence, _movement.latest_packet()) == OK


func _send_host(kind: ReplicationMessage.Kind, sequence: int, bytes: PackedByteArray) -> bool:
	return _session.send(_connection, ReplicationMessage.transport_kind(kind), sequence, ReplicationMessage.pack(kind, bytes)) == OK


func _observe_view(bytes: PackedByteArray) -> bool:
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not decoded is Dictionary or decoded.get("actors", {}).keys() != ["visible"]:
		return false
	var cue: Array = decoded.get("warnings", {}).get("eligible-cue", [])
	if cue.size() != 7 or bytes.get_string_from_utf8().contains("773451"):
		return false
	_result["view_sha256"] = _digest(bytes)
	_result["warning_lead_from_sample_tick"] = String(cue[6]).to_int() - String(decoded["tick"]).to_int()
	_result["filtered_view"] = decoded
	_saw_view = true
	if _avatar != null:
		var marker := Line2D.new()
		marker.points = PackedVector2Array([Vector2(160.0 + float(cue[0]) * 40.0, 310.0),
			Vector2(160.0 + float(cue[2]) * 40.0, 310.0)])
		marker.width = 8.0
		marker.default_color = Color("ed5769")
		add_child(marker)
	return true


func _finish(passed: bool) -> void:
	_result["passed"] = passed
	_result["role"] = _role
	print("WP12_RESULT ", JSON.stringify(_result))
	super._finish(passed)


func _make_stage() -> void:
	RenderingServer.set_default_clear_color(Color("182632"))
	var wall := Line2D.new()
	wall.points = PackedVector2Array([Vector2(360, 80), Vector2(360, 400)])
	wall.width = 5.0
	wall.default_color = Color("df9948")
	add_child(wall)
	_avatar = Polygon2D.new()
	var outline := PackedVector2Array()
	for index: int in 32:
		outline.append(Vector2.from_angle(TAU * index / 32.0) * 40.0)
	_avatar.polygon = outline
	_avatar.position = Vector2(160, 240)
	_avatar.color = Color("80dac9")
	add_child(_avatar)


func _capture(filename: String) -> void:
	var directory := OS.get_environment("AGIP_WP12_CAPTURE")
	if _avatar == null or directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
	_result[filename] = result == OK


static func _state(serial: int, x: float) -> MovementSnapshot:
	var state := MovementSnapshot.new()
	state.epoch = RUN_EPOCH
	state.baseline = BASELINE
	state.serial = serial
	state.position = RealmSweep.Point.new(x, 0.0)
	state.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES)
	state.speed = 60.0
	state.radius = 1.0
	return state


static func _wall() -> GuestMovement.Blocker:
	var blocker := GuestMovement.Blocker.new()
	blocker.first = RealmSweep.Point.new(5.0, -20.0)
	blocker.last = RealmSweep.Point.new(5.0, 20.0)
	return blocker


static func _view() -> PackedByteArray:
	var scope := RecipientView.Scope.new()
	scope.seat = SEAT
	scope.realm = REALM
	scope.actors = {&"visible": true, &"remote": true}
	scope.warnings = {&"eligible-cue": true}
	var actors: Array[RecipientView.Actor] = []
	for id: StringName in [&"visible", &"remote", &"hidden"]:
		var actor := RecipientView.Actor.new()
		actor.id = id
		actor.realm = &"other" if id == &"remote" else REALM
		actor.position = RealmSweep.Point.new(2.0 if id == &"visible" else 773451.0, 0.0)
		actors.append(actor)
	var warning := RecipientView.Warning.new()
	warning.id = &"eligible-cue"
	warning.realm = REALM
	warning.origin = RealmSweep.Point.new(2.0, 0.0)
	warning.end = RealmSweep.Point.new(3.0, 0.0)
	warning.radius = 1.0
	warning.activation = 20
	warning.impact = 30
	return RecipientView.pack(scope, RUN_EPOCH, BASELINE, 1, 1, "0", {SEAT: &"living"}, actors, [warning], null)


static func _digest(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()
