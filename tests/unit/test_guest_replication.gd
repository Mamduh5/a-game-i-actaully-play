extends GutTest

const Acceptance := GuestMovement.Acceptance
const Admission := RunAuthority.Admission
const LARGE_ID := 9007199254740993

class MovementAuthority extends RunAuthority:
	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_AXES or action == PlayerCommand.MOVE_TO


func test_movement_schemas_keep_exact_frontiers_and_reject_malformed_bytes() -> void:
	var bytes := MovementFrame.pack(LARGE_ID, LARGE_ID + 1, LARGE_ID + 2, _axis(1.0))
	var cmd := MovementFrame.read(bytes)
	assert_not_null(cmd)
	assert_eq([cmd.epoch, cmd.baseline, cmd.sequence], [LARGE_ID, LARGE_ID + 1, LARGE_ID + 2])
	assert_true(cmd.command.matches(_axis(1.0)))
	assert_true(MovementFrame.pack(1, 1, 1, PlayerCommand.new(PlayerCommand.MANUAL)).is_empty())
	assert_null(MovementFrame.read(bytes + PackedByteArray([0])))
	bytes.encode_double(26, NAN)
	assert_null(MovementFrame.read(bytes))
	var packet := MovementBaseline.new()
	packet.realm = &"core"
	packet.state = _state(2, 3, LARGE_ID, LARGE_ID + 42, 0, 2.0)
	packet.blockers = [_wall(5.0)]
	var wire := packet.pack()
	var restored := MovementBaseline.read(wire)
	assert_not_null(restored)
	assert_eq(restored.realm, &"core")
	assert_eq(restored.state.tick, LARGE_ID + 42)
	assert_eq(restored.blockers[0].last.y, 20.0)
	assert_eq(restored.pack(), wire)
	wire.encode_u16(2, 65535)
	assert_null(MovementBaseline.read(wire))
	packet.realm = &""
	assert_true(packet.pack().is_empty())


func test_host_binds_native_sender_and_uses_authoritative_admission_and_acknowledgement() -> void:
	var setup := RunSetup.new()
	setup.run_id = &"fixture"
	setup.authority_id = &"host"
	setup.epoch = 2
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.challenge_id = &"fixture"
	setup.initial_realms = {&"guest": &"core"}
	var authority := MovementAuthority.new()
	assert_true(authority.start(setup, &"host"))
	var bridge := HostMovementBridge.new()
	assert_true(bridge.bind(1, 10, 7, &"fixture", 2, &"core", &"guest", 5))
	assert_false(bridge.bind(1, 11, 6, &"fixture", 2, &"core", &"guest", 6))
	var packet := _movement_wire(2, 5)
	var message := NativeSessionHost.Command.new()
	var kind := NativeSessionFrame.Kind.SEQUENCED
	message.frame = NativeSessionFrame.read(NativeSessionFrame.pack(kind, 7, 1, packet), NativeSessionFrame.channel(kind))
	message.connection = 11
	message.seat = 1
	assert_eq(bridge.submit(authority, message), Admission.WRONG_SEAT)
	message.connection = 10
	message.frame.generation = 8
	assert_eq(bridge.submit(authority, message), Admission.WRONG_SEAT)
	message.frame.generation = 7
	message.frame.payload = _movement_wire(1, 5)
	assert_eq(bridge.submit(authority, message), Admission.WRONG_EPOCH)
	message.frame.payload = _movement_wire(2, 4)
	assert_eq(bridge.submit(authority, message), Admission.WRONG_REALM)
	message.frame.payload = packet
	assert_eq(bridge.submit(authority, message), Admission.QUEUED)
	assert_eq(bridge.submit(authority, message), Admission.DUPLICATE)
	assert_true(authority.close_tick())
	assert_eq(authority.checkpoint()["sequences"][&"guest"], 3)
	assert_eq(bridge.submit(authority, message), Admission.STALE_SEQUENCE)
	bridge.unbind(1, 11, 7)
	assert_eq(bridge.submit(authority, message), Admission.STALE_SEQUENCE)
	bridge.unbind(1, 10, 7)
	assert_eq(bridge.submit(authority, message), Admission.WRONG_SEAT)


func test_bridge_preserves_watermark_through_live_reclaim_and_disconnect() -> void:
	var bridge := HostMovementBridge.new()
	assert_true(bridge.bind(1, 10, 7, &"fixture", 2, &"core", &"guest", 5))
	assert_false(bridge.bind(1, 11, 7, &"fixture", 2, &"core", &"guest", 5))
	assert_true(bridge.bind(1, 11, 7, &"fixture", 2, &"core", &"guest", 6))
	bridge.unbind(1, 10, 7)
	assert_true(bridge.bind(1, 11, 7, &"fixture", 2, &"core", &"guest", 7), "Obsolete loss cannot unbind the reclaim")
	bridge.unbind(1, 11, 7)
	assert_false(bridge.bind(1, 10, 7, &"fixture", 3, &"core", &"guest", 1))
	assert_false(bridge.bind(1, 11, 7, &"fixture", 2, &"core", &"guest", 8))
	assert_false(bridge.bind(1, 12, 6, &"fixture", 3, &"core", &"guest", 1))
	assert_false(bridge.bind(1, 12, 7, &"fixture", 1, &"core", &"guest", 20))
	assert_false(bridge.bind(1, 12, 7, &"fixture", 2, &"core", &"guest", 6))
	assert_true(bridge.bind(1, 12, 7, &"fixture", 3, &"other", &"guest", 1))
	assert_true(bridge.bind(1, 1, 8, &"fixture", 3, &"other", &"guest", 2), "New host generation restarts connection ordinals")
	bridge.unbind(1, 1, 7)
	assert_true(bridge.bind(1, 1, 8, &"fixture", 3, &"other", &"guest", 3), "Old host generation cannot deactivate a reused ordinal")


func test_motion_lock_and_forced_correction_supersede_unacknowledged_movement() -> void:
	for via_baseline: bool in [false, true]:
		for locked: bool in [false, true]:
			var guest := GuestMovement.new()
			assert_eq(guest.install_baseline(&"core", _state(1, 1, 1, 0, 0, 0.0), []), Acceptance.APPLIED)
			assert_false(guest.issue(_axis(1.0)).is_empty())
			assert_true(guest.advance())
			var baseline := 2 if via_baseline else 1
			var correction := _state(1, baseline, 2, 1, 0, 9.0)
			correction.permits_prediction = not locked
			correction.forced_correction = not locked
			if via_baseline:
				assert_eq(guest.install_baseline(&"core", correction, []), Acceptance.APPLIED)
			else:
				assert_eq(guest.receive(correction), Acceptance.APPLIED)
			assert_eq(guest.pending_count(), 0)
			assert_true(guest.latest_packet().is_empty())
			assert_eq(guest.draw_position(0.0).x, 9.0)
			if locked:
				assert_true(guest.issue(_axis(0.0)).is_empty(), "Key release during a motion lock")
				assert_false(guest.advance())
			assert_eq(guest.receive(_state(1, baseline, 3, 2, 0, 9.0)), Acceptance.APPLIED)
			assert_true(guest.latest_packet().is_empty())
			assert_true(guest.advance())
			assert_eq(guest.position().x, 9.0)
			assert_eq(MovementFrame.read(guest.issue(_axis(-1.0)).slice(ReplicationMessage.HEADER_SIZE)).sequence, 2)


func test_prediction_repeats_complete_intent_and_replays_until_host_ack() -> void:
	var guest := GuestMovement.new()
	var original := _state(1, 1, 1, 0, 0, 0.0)
	assert_eq(guest.install_baseline(&"core", original, []), Acceptance.APPLIED)
	original.speed = 0.0
	var first := _axis(1.0)
	var wire := guest.issue(first)
	first.x = -1.0
	assert_eq(guest.latest_packet(), wire, "A replaceable intent can be resent after loss")
	assert_true(guest.advance())
	assert_true(guest.advance())
	assert_eq(guest.position().x, 2.0)
	assert_eq(guest.receive(_state(1, 1, 2, 1, 0, 0.0)), Acceptance.APPLIED)
	assert_eq(guest.position().x, 1.0)
	assert_eq(guest.pending_count(), 1)
	assert_eq(guest.receive(_state(1, 1, 3, 2, 1, 0.5)), Acceptance.APPLIED)
	assert_eq(guest.pending_count(), 0)
	assert_true(guest.latest_packet().is_empty())
	assert_eq(guest.draw_position(0.5).x, 0.25, "A small correction only affects the drawing")
	assert_eq(guest.position().x, 0.5)


func test_disclosed_wall_baseline_recovery_and_forced_authoritative_snap() -> void:
	var guest := GuestMovement.new()
	var wall := _wall(5.0)
	assert_eq(guest.install_baseline(&"core", _state(1, 1, 1, 0, 0, 0.0), [wall]), Acceptance.APPLIED)
	wall.first.x = 50.0
	assert_false(guest.issue(_axis(1.0)).is_empty())
	for step: int in 7:
		assert_true(guest.advance())
	assert_almost_eq(guest.position().x, 4.0, 0.000001)
	assert_eq(guest.receive(_state(1, 3, 3, 7, 1, 3.5)), Acceptance.NEED_BASELINE)
	assert_true(guest.needs_baseline())
	assert_false(guest.advance())
	assert_eq(guest.install_baseline(&"core", _state(1, 2, 2, 7, 1, 3.5), []), Acceptance.STALE)
	assert_eq(guest.receive(_state(1, 1, 1, 7, 1, 3.5)), Acceptance.STALE)
	var forced := _state(1, 3, 3, 7, 1, 9.0)
	forced.permits_prediction = false
	forced.forced_correction = true
	assert_eq(guest.install_baseline(&"core", forced, [_wall(5.0)]), Acceptance.APPLIED)
	assert_eq(guest.draw_position(0.0).x, 9.0)
	assert_true(guest.issue(_axis(-1.0)).is_empty())
	assert_false(guest.advance())
	assert_eq(guest.install_baseline(&"other", _state(2, 1, 1, 0, 0, 10.0), []), Acceptance.APPLIED)
	assert_eq(guest.receive(_state(1, 3, 10, 20, 1, 9.0)), Acceptance.STALE)
	assert_eq(guest.draw_position(0.0).x, 10.0)
	assert_eq(MovementFrame.read(guest.issue(_axis(1.0)).slice(ReplicationMessage.HEADER_SIZE)).sequence, 1)


func test_prediction_near_maximum_tick_does_not_wrap() -> void:
	var guest := GuestMovement.new()
	var last := RunAuthority.MAX_TICK
	assert_eq(guest.install_baseline(&"core", _state(1, 1, 1, last - 2, 0, 0.0), []), Acceptance.APPLIED)
	assert_false(guest.issue(_axis(1.0)).is_empty())
	assert_true(guest.advance())
	assert_true(guest.advance())
	assert_eq(guest.receive(_state(1, 1, 2, last - 1, 0, 0.0)), Acceptance.APPLIED)
	assert_eq(guest.position().x, 1.0)
	assert_false(guest.advance())


func test_ipv6_private_policy_requires_a_complete_ula_hextet() -> void:
	for address: String in ["::1", "fc00::1", "Fdab::1", "127.0.0.1", "172.16.0.1"]:
		assert_true(NativeDtlsLink.private_ip(address), address)
	for address: String in ["fc::1", "fd1::1", "fc0::1", "2001:db8::1", "172.32.0.1"]:
		assert_false(NativeDtlsLink.private_ip(address), address)


func test_projection_filters_before_serializing_actor_fog_and_timed_warning_rows() -> void:
	var layout := WorldTopology.generate(22)
	var world := WorldExploration.create(layout, [&"host", &"guest"])
	assert_true(world.observe_seat(&"host", layout.realm, layout.center(WorldTopology.ANCHORS[0])))
	var scope := RecipientView.Scope.new()
	scope.seat = &"guest"
	scope.realm = layout.realm
	scope.actors = {&"shown": true, &"remote_actor": true, &"explicitly_denied": false}
	scope.warnings = {&"cue": true, &"remote_cue": true, &"elapsed": true}
	var actors: Array[RecipientView.Actor] = [
		_actor(&"shown", scope.realm, 11.0), _actor(&"unseen_actor", scope.realm, 445001.0),
		_actor(&"remote_actor", &"other", 445002.0), _actor(&"explicitly_denied", scope.realm, 445003.0),
	]
	var warnings: Array[RecipientView.Warning] = [
		_warning(&"cue", scope.realm, 12.0, LARGE_ID + 25),
		_warning(&"unseen_cue", scope.realm, 445004.0, LARGE_ID + 25),
		_warning(&"remote_cue", &"other", 445005.0, LARGE_ID + 25),
		_warning(&"elapsed", scope.realm, 445006.0, LARGE_ID - 1),
	]
	var party: Dictionary[StringName, StringName] = {&"host": &"living", &"guest": &"down"}
	var bytes := RecipientView.pack(scope, 3, 5, LARGE_ID, 2, "1234", party, actors, warnings, world)
	var raw := bytes.get_string_from_utf8()
	assert_true(raw.find("44500") == -1, "Denied coordinates never enter the message")
	var decoded: Dictionary = JSON.parse_string(raw)
	assert_eq(decoded["actors"].keys(), ["shown"])
	assert_eq(decoded["warnings"].keys(), ["cue"])
	assert_eq(decoded["warnings"]["cue"].slice(5), [str(LARGE_ID - 5), str(LARGE_ID + 25)])
	assert_eq(decoded["tick"], str(LARGE_ID))
	assert_eq(decoded["party"], {"host": "living", "guest": "down"})
	assert_eq(decoded["explored"].size(), 1)
	scope.realm = &"other"
	raw = RecipientView.pack(scope, 3, 6, LARGE_ID, 2, "1234", party, actors, warnings, world).get_string_from_utf8()
	decoded = JSON.parse_string(raw)
	assert_eq(decoded["actors"].keys(), ["remote_actor"])
	assert_true(decoded["explored"].is_empty(), "A spectator realm does not inherit another realm's map")
	assert_eq(decoded["party"].size(), 2)


static func _state(epoch: int, baseline: int, serial: int, tick: int, ack: int, x: float) -> MovementSnapshot:
	var state := MovementSnapshot.new()
	state.epoch = epoch
	state.baseline = baseline
	state.serial = serial
	state.tick = tick
	state.acknowledged = ack
	state.position = RealmSweep.Point.new(x, 0.0)
	state.movement = _axis(0.0)
	state.speed = 60.0
	state.radius = 1.0
	return state


static func _axis(x: float) -> PlayerCommand:
	return PlayerCommand.new(PlayerCommand.MOVE_AXES, x, 0.0)


static func _movement_wire(epoch: int, baseline: int) -> PackedByteArray:
	return ReplicationMessage.pack(ReplicationMessage.Kind.MOVEMENT, MovementFrame.pack(epoch, baseline, 3, _axis(1.0)))


static func _wall(x: float) -> GuestMovement.Blocker:
	var wall := GuestMovement.Blocker.new()
	wall.first = RealmSweep.Point.new(x, -20.0)
	wall.last = RealmSweep.Point.new(x, 20.0)
	return wall


static func _actor(id: StringName, realm: StringName, x: float) -> RecipientView.Actor:
	var actor := RecipientView.Actor.new()
	actor.id = id
	actor.realm = realm
	actor.position = RealmSweep.Point.new(x, 0.0)
	return actor


static func _warning(id: StringName, realm: StringName, x: float, impact: int) -> RecipientView.Warning:
	var warning := RecipientView.Warning.new()
	warning.id = id
	warning.realm = realm
	warning.origin = RealmSweep.Point.new(x, 0.0)
	warning.end = RealmSweep.Point.new(x + 1.0, 0.0)
	warning.radius = 2.0
	warning.activation = LARGE_ID - 5
	warning.impact = impact
	return warning
