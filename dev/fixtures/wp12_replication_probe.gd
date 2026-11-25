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
const EXTRA_ACTORS := 220
const EXTRA_BLOCKERS := 280
const WARNING_TICK := 20
const IMPACT_TICK := 30
const LOW_BLOCKER := 1
const AVATAR := 2
const SEALED_BLOCKER := 4

class ProbeAuthority extends RunAuthority:
	var controls := PlayerControlState.new()
	var geometry := RealmGeometry.new(REALM)
	var moved := false

	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_AXES or action == PlayerCommand.MOVE_TO

	func _resolve_tick(_tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		for intent: RunIntent in accepted:
			controls.apply(intent.command)
		moved = controls.step(geometry, BODY, 0, LOW_BLOCKER | SEALED_BLOCKER, 60.0,
			GuestMovement.SECONDS_PER_TICK) != null
		return []

class ObservedReplica extends GuestReplica:
	var last_view: PackedByteArray

	func _receive_view(bytes: PackedByteArray) -> GuestReplica.Acceptance:
		var verdict := super._receive_view(bytes)
		if verdict == GuestReplica.Acceptance.APPLIED:
			last_view = bytes
		return verdict

var _movement := GuestMovement.new()
var _replica := ObservedReplica.new()
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
var _reliable_sequence: int
var _ack_at: int
var _leave_at: int
var _caught_stale := false
var _saw_snap := false
var _saw_unlock := false
var _saw_impact := false
var _saw_view := false
var _avatar: Polygon2D
var _cue: Line2D
var _result: Dictionary = {}
var _large := OS.get_environment("AGIP_WP12_LARGE_VIEW") == "1"
var _sealed_vault := OS.get_environment("AGIP_WP12_SEALED_VAULT") == "1"


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
		if (not _authority.start(setup, &"host")
				or not _authority.geometry.add_circle(BODY, 0, RealmSweep.Point.new(0.0, 0.0), 1.0, AVATAR)):
			_finish(false)
			return
		var disclosed := _disclosed_blockers()
		for index: int in disclosed.size():
			var edge := RealmOutline.Edge.new()
			edge.first = disclosed[index].first
			edge.last = disclosed[index].last
			var category := SEALED_BLOCKER if _sealed_vault and index == 1 else LOW_BLOCKER
			if not _authority.geometry.add_segment(&"wall", index, edge, category, true):
				_finish(false)
				return
	elif _role == "guest" and DisplayServer.get_name() != "headless":
		_make_stage()


func _physics_process(_delta: float) -> void:
	if _role == "host":
		if _host_state >= 5 and _authority.next_tick() <= IMPACT_TICK:
			if not _authority.close_tick():
				_finish(false)
			elif _authority.next_tick() == WARNING_TICK + 1 and not _send_threat_tick(6, WARNING_TICK):
				_finish(false)
			elif _authority.next_tick() == IMPACT_TICK + 1 and not _impact():
				_finish(false)
		return
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
		if batch.departures != 1 or _host_state != 8:
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
			reset.blockers = _disclosed_blockers()
			_host_state = 3
			return _send_reliable_parts("baseline_parts", reset.envelopes(1))
		4:
			var state := _state(2, 1.0)
			state.tick = 1
			state.acknowledged = _authority.checkpoint()["sequences"][SEAT]
			state.movement = _authority.controls.movement_snapshot()
			_result["closed_movement_ack"] = state.acknowledged
			_host_state = 5
			_next_publish = Time.get_ticks_msec() + 91
			return (_send_host(Kinds.STATE, 2, state.pack())
				and _send_reliable_parts("view_parts", ReplicationChunks.split(Kinds.VIEW, 2, _view(_large))))
		5:
			var vault := _authority.geometry.displace_circle(BODY, 0, RealmSweep.Point.new(9.0, 0.0), SEALED_BLOCKER)
			if vault == null or not _is_landing(vault.finish) or vault.stopped_by.size() != int(_sealed_vault):
				return false
			_result["vault_landing_x"] = vault.finish.x
			_result["vault_sealed_contacts"] = vault.stopped_by.size()
			_authority.controls.apply(PlayerCommand.new(PlayerCommand.MOVE_AXES))
			var state := _state(3, _authority.geometry.circle_center(BODY, 0).x)
			state.tick = _authority.next_tick() - 1
			state.acknowledged = 1
			state.permits_prediction = false
			state.forced_correction = true
			_host_state = 6
			_next_publish = Time.get_ticks_msec() + 37
			return _send_host(Kinds.STATE, 3, state.pack())
		6:
			var stale := _state(4, 999.0)
			stale.epoch = RUN_EPOCH - 1
			_host_state = 7
			_next_publish = Time.get_ticks_msec() + 37
			return _send_host(Kinds.STATE, 4, stale.pack())
		7:
			var resumed := _state(5, _authority.geometry.circle_center(BODY, 0).x)
			resumed.tick = _authority.next_tick() - 1
			resumed.acknowledged = 1
			_host_state = 8
			return _send_host(Kinds.STATE, 5, resumed.pack())
	return false


func _impact() -> bool:
	if _host_state != 8:
		return false
	var from := RealmSweep.Point.new(2.0, 0.0)
	var to := RealmSweep.Point.new(3.0, 0.0)
	var hit := _authority.geometry.certify_circle_sweep(REALM, from, to, 1.0, AVATAR)
	if hit == null or not hit.unresolved.is_empty():
		return false
	# The fixture's previously obstructed position was inside the same threat.
	var control := RealmGeometry.new(REALM)
	if not control.add_circle(BODY, 0, RealmSweep.Point.new(4.0, 0.0), 1.0, AVATAR):
		return false
	var positive := control.certify_circle_sweep(REALM, from, to, 1.0, AVATAR)
	if positive == null or positive.contacts.size() != 1 or not hit.contacts.is_empty():
		return false
	_result["authority_impact_tick"] = IMPACT_TICK
	_result["authority_impact_unix_ms"] = _unix_ms()
	_result["contact_at_obstructed_pose"] = true
	_result["contact_after_forced_motion"] = false
	return _send_threat_tick(7, IMPACT_TICK)


func _send_threat_tick(serial: int, tick: int) -> bool:
	if _host_state != 8:
		return false
	var settled := _state(serial, _authority.geometry.circle_center(BODY, 0).x)
	settled.tick = tick
	settled.acknowledged = 1
	return _send_host(Kinds.STATE, serial, settled.pack())


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
	var payload_kind: int = ReplicationChunks.payload_kind(wire) if wire.kind == Kinds.SNAPSHOT_PART else wire.kind
	if payload_kind == Kinds.VIEW:
		return _observe_view(frame)
	var verdict := _movement.receive_frame(frame)
	if verdict == Accepted.WAITING_FOR_PARTS:
		return true
	if verdict == Accepted.NEED_BASELINE and _baseline_at == 0:
		_result["missing_baseline_detected"] = true
		return _resync_sequence == 1 and _request_baseline()
	if verdict == Accepted.STALE and _saw_snap:
		_caught_stale = _is_landing(_movement.position())
		_result["stale_epoch_preserved_pose"] = _caught_stale
		return _caught_stale
	if verdict != Accepted.APPLIED:
		return false
	if payload_kind == Kinds.BASELINE:
		var scope := _movement.confirmed_scope()
		if scope == null or not _replica.install_scope(scope.realm, scope.state):
			return false
		_baseline_at = Time.get_ticks_msec()
		_result["resync_ms"] = _baseline_at - _resync_started
		var dropped := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1.0))
		_result["dropped_movement_messages"] = int(not dropped.is_empty())
		return not dropped.is_empty()
	if _movement.latest_packet().is_empty() and _ack_at == 0 and frame.sequence == 2:
		_ack_at = Time.get_ticks_msec()
		_result["retry_to_ack_ms"] = _ack_at - _move_at
		_result["pending_after_ack"] = _movement.pending_count()
		if _move_at <= 0 or _movement.pending_count() != 0:
			return false
		# Leave an input unacknowledged just before the fixture enters its
		# authority-owned motion lock. This packet is deliberately withheld.
		var withheld := _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, -1.0))
		_result["pending_before_lock"] = _movement.pending_count()
		return not withheld.is_empty()
	if frame.sequence == 3:
		_saw_snap = (_is_landing(_movement.draw_position(0.0)) and not _movement.advance()
			and _movement.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES)).is_empty())
		_result["forced_snap_draw_x"] = _movement.draw_position(0.0).x
		_result["pending_during_lock"] = _movement.pending_count()
		return _saw_snap and _movement.pending_count() == 0
	if frame.sequence == 5:
		_saw_unlock = _movement.latest_packet().is_empty() and _movement.advance() and _is_landing(_movement.position())
		_result["unlock_preserved_pose"] = _saw_unlock
		return _saw_unlock
	if frame.sequence == 6:
		if _movement.confirmed_scope().state.tick != WARNING_TICK or not _replica.active_warning_ids(WARNING_TICK).has("eligible-cue"):
			return false
		_result["observed_warning_tick"] = WARNING_TICK
		_result["warning_activation_unix_ms"] = _unix_ms()
		if _cue != null:
			_cue.show()
			_capture("active-cue.png")
		return true
	if frame.sequence == 7:
		_saw_impact = _saw_unlock and _movement.confirmed_scope().state.tick == IMPACT_TICK
		_result["observed_impact_tick"] = IMPACT_TICK if _saw_impact else 0
		if _cue != null:
			_cue.hide()
		return _saw_impact
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
	if _caught_stale and _saw_view and _saw_impact and _leave_at == 0:
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


func _send_reliable_parts(receipt_field: String, parts: Array[PackedByteArray]) -> bool:
	_result[receipt_field] = parts.size()
	for payload: PackedByteArray in parts:
		_reliable_sequence += 1
		if _session.send(_connection, RELIABLE, _reliable_sequence, payload) != OK:
			return false
	return not parts.is_empty()


func _observe_view(frame: NativeSessionFrame) -> bool:
	var verdict := _replica.receive_frame(frame)
	if verdict == GuestReplica.Acceptance.WAITING_FOR_PARTS:
		return not _saw_view and _replica.actor_ids().is_empty()
	if verdict != GuestReplica.Acceptance.APPLIED:
		return false
	var ids := _replica.actor_ids()
	if not "visible" in ids or ids.size() != (1 + EXTRA_ACTORS if _large else 1):
		return false
	var cue := _replica.warning_sample("eligible-cue")
	if (cue == null or _replica.active_warning_ids(cue.activation - 1).has("eligible-cue")
			or not _replica.active_warning_ids(cue.activation).has("eligible-cue")
			or _replica.active_warning_ids(cue.impact + 1).has("eligible-cue")):
		return false
	var bytes := _replica.last_view
	var raw := bytes.get_string_from_utf8()
	var decoded: Variant = JSON.parse_string(raw)
	if not decoded is Dictionary or raw.contains("773451") or "remote" in ids or "hidden" in ids:
		return false
	_result["view_sha256"] = _digest(bytes)
	_result["warning_received_unix_ms"] = _unix_ms()
	_result["warning_lead_from_sample_tick"] = cue.impact - String(decoded["tick"]).to_int()
	if _large:
		_result["disclosed_actor_count"] = ids.size()
		_result["view_bytes"] = bytes.size()
	else:
		_result["filtered_view"] = decoded
	_saw_view = true
	if _avatar != null:
		_cue = Line2D.new()
		_cue.points = PackedVector2Array([Vector2(160.0 + cue.origin.x * 40.0, 310.0),
			Vector2(160.0 + cue.end.x * 40.0, 310.0)])
		_cue.width = 8.0
		_cue.default_color = Color("ed5769")
		_cue.hide()
		add_child(_cue)
	return true


func _finish(passed: bool) -> void:
	_result["passed"] = passed
	_result["role"] = _role
	print("WP12_RESULT ", JSON.stringify(_result))
	super._finish(passed)


func _make_stage() -> void:
	RenderingServer.set_default_clear_color(Color("182632"))
	_draw_wall(360, Color("df9948"))
	if _sealed_vault:
		_draw_wall(480, Color("95a6ad"))
	_avatar = Polygon2D.new()
	var outline := PackedVector2Array()
	for index: int in 32:
		outline.append(Vector2.from_angle(TAU * index / 32.0) * 40.0)
	_avatar.polygon = outline
	_avatar.position = Vector2(160, 240)
	_avatar.color = Color("80dac9")
	add_child(_avatar)


func _draw_wall(x: float, color: Color) -> void:
	var wall := Line2D.new()
	wall.points = PackedVector2Array([Vector2(x, 80), Vector2(x, 400)])
	wall.width = 5.0
	wall.default_color = color
	add_child(wall)


func _capture(filename: String) -> void:
	var directory := OS.get_environment("AGIP_WP12_CAPTURE")
	if _avatar == null or directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
	_result[filename] = result == OK
	if result == OK and filename == "active-cue.png":
		_result["warning_rendered_unix_ms"] = _unix_ms()


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


func _disclosed_blockers() -> Array[GuestMovement.Blocker]:
	var disclosed: Array[GuestMovement.Blocker] = [_wall(5.0)]
	if _sealed_vault:
		disclosed.append(_wall(8.0))
	if _large:
		for index: int in EXTRA_BLOCKERS:
			disclosed.append(_wall(20.0 + index * 10))
	return disclosed


func _is_landing(point: RealmSweep.Point) -> bool:
	var expected := 7.0 if _sealed_vault else 9.0
	return point != null and absf(point.x - expected) < 0.000001


static func _wall(x: float) -> GuestMovement.Blocker:
	var blocker := GuestMovement.Blocker.new()
	blocker.first = RealmSweep.Point.new(x, -20.0)
	blocker.last = RealmSweep.Point.new(x, 20.0)
	return blocker


static func _view(large: bool) -> PackedByteArray:
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
	if large:
		for index: int in EXTRA_ACTORS:
			var actor := RecipientView.Actor.new()
			actor.id = StringName("disclosed_actor_%04d" % index)
			actor.realm = REALM
			actor.position = RealmSweep.Point.new(index * 2.0, 2.0)
			scope.actors[actor.id] = true
			actors.append(actor)
	var warning := RecipientView.Warning.new()
	warning.id = &"eligible-cue"
	warning.realm = REALM
	warning.origin = RealmSweep.Point.new(2.0, 0.0)
	warning.end = RealmSweep.Point.new(3.0, 0.0)
	warning.radius = 1.0
	warning.activation = WARNING_TICK
	warning.impact = IMPACT_TICK
	return RecipientView.pack(scope, RUN_EPOCH, BASELINE, 1, 1, "0", {SEAT: &"living"}, actors, [warning], null,
		ReplicationChunks.MAX_ASSEMBLED)


static func _digest(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


static func _unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
