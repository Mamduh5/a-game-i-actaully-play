extends GutTest

const RUN := &"travel-run"
const OUTSIDE := &"overworld"
const INSIDE := &"silent_garden"
const SEAT := &"guest"

class MovingRun extends RunAuthority:
	func _supports_action(action: StringName) -> bool:
		return action == PlayerCommand.MOVE_TO


func test_guest_click_uses_the_reliable_confirmed_scope_without_predicting_it() -> void:
	var guest := GuestMovement.new()
	var click := PlayerCommand.new(PlayerCommand.INTERACT, 128.25, -64.5)
	assert_true(guest.interaction_packet(click).is_empty())
	assert_eq(guest.install_baseline(OUTSIDE, _snapshot(8), []), GuestMovement.Acceptance.APPLIED)
	assert_true(guest.interaction_packet(PlayerCommand.new(PlayerCommand.MOVE_TO, 128.25, -64.5)).is_empty())
	assert_true(guest.interaction_packet(PlayerCommand.new(PlayerCommand.INTERACT, NAN, 0)).is_empty())
	var packet := guest.interaction_packet(click)
	assert_eq(guest.pending_count(), 0)
	assert_eq(guest.position().x, 0.0)
	var reliable := _receipt(NativeSessionFrame.Kind.RELIABLE, packet, 4, 1)
	var envelope := ReplicationMessage.read(reliable.frame)
	assert_not_null(envelope)
	if envelope != null:
		assert_eq(envelope.kind, ReplicationMessage.Kind.INTERACTION)
		var content := RealmInteractionFrame.read(envelope.body)
		assert_not_null(content)
		if content != null:
			assert_eq(content.epoch, 5)
			assert_eq(content.baseline, 8)
			assert_true(content.command.matches(click))
	var wrong_channel := _receipt(NativeSessionFrame.Kind.SEQUENCED, packet, 4, 1)
	assert_null(ReplicationMessage.read(wrong_channel.frame))
	var invalid := RealmInteractionFrame.pack(5, 8, click)
	invalid.encode_double(17, INF)
	assert_null(RealmInteractionFrame.read(invalid))
	assert_null(RealmInteractionFrame.read(invalid.slice(0, 11)))


func test_late_reliable_click_keeps_its_scope_after_a_newer_sequenced_move() -> void:
	var bridge := HostMovementBridge.new()
	var guest := GuestMovement.new()
	assert_true(bridge.bind(2, 7, 4, RUN, 5, OUTSIDE, SEAT, 8))
	assert_eq(guest.install_baseline(OUTSIDE, _snapshot(8), []), GuestMovement.Acceptance.APPLIED)
	var click := PlayerCommand.new(PlayerCommand.INTERACT, 40.0, 44.0)
	var delayed := _receipt(NativeSessionFrame.Kind.RELIABLE, guest.interaction_packet(click), 4, 1)
	var move := PlayerCommand.new(PlayerCommand.MOVE_TO, 56.0, 32.0)
	var payload := ReplicationMessage.pack(ReplicationMessage.Kind.MOVEMENT, MovementFrame.pack(5, 8, 70, move))
	var newer := _receipt(NativeSessionFrame.Kind.SEQUENCED, payload, 4, 71)
	var authority := MovingRun.new()
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = RUN
	setup.epoch = 5
	setup.authority_id = &"host"
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"host": OUTSIDE, SEAT: OUTSIDE}
	assert_true(authority.start(setup, &"host"))
	assert_eq(bridge.submit(authority, newer), RunAuthority.Admission.QUEUED)
	assert_true(authority.close_tick())
	assert_eq(authority.checkpoint().sequences[SEAT], 70)
	var bound := bridge.read_interaction(delayed)
	assert_not_null(bound)
	if bound != null:
		assert_eq(bound.run, RUN)
		assert_eq(bound.realm, OUTSIDE)
		assert_eq(bound.seat, SEAT)
		assert_eq(bound.sequence, 1)
		assert_true(bound.command.matches(click))
	assert_eq(authority.checkpoint().sequences[SEAT], 70)
	assert_null(bridge.read_interaction(newer))


func test_rebind_rejects_old_realm_click_and_enforces_authenticated_generation() -> void:
	var bridge := HostMovementBridge.new()
	var guest := GuestMovement.new()
	assert_true(bridge.bind(2, 7, 4, RUN, 5, OUTSIDE, SEAT, 8))
	assert_eq(guest.install_baseline(OUTSIDE, _snapshot(8), []), GuestMovement.Acceptance.APPLIED)
	var click := PlayerCommand.new(PlayerCommand.INTERACT, 4.0, 1.0)
	var old_click := _receipt(NativeSessionFrame.Kind.RELIABLE, guest.interaction_packet(click), 4, 1)
	assert_not_null(bridge.read_interaction(old_click))
	assert_true(bridge.bind(2, 7, 4, RUN, 5, INSIDE, SEAT, 9))
	assert_null(bridge.read_interaction(old_click))
	assert_eq(guest.install_baseline(INSIDE, _snapshot(9), []), GuestMovement.Acceptance.APPLIED)
	var payload := guest.interaction_packet(click)
	assert_null(bridge.read_interaction(_receipt(NativeSessionFrame.Kind.RELIABLE, payload, 3, 2)))
	var rebound := _receipt(NativeSessionFrame.Kind.RELIABLE, payload, 4, 2)
	var bound := bridge.read_interaction(rebound)
	assert_not_null(bound)
	if bound != null:
		assert_eq(bound.realm, INSIDE)
		assert_eq(bound.baseline, 9)
	bridge.unbind(2, 7, 4)
	assert_null(bridge.read_interaction(rebound))


static func _snapshot(baseline: int) -> MovementSnapshot:
	var state := MovementSnapshot.new()
	state.epoch = 5
	state.baseline = baseline
	state.serial = 1
	state.position = RealmSweep.Point.new(0.0, 0.0)
	state.movement = PlayerCommand.new(PlayerCommand.MOVE_AXES)
	state.speed = 60.0
	state.radius = 4.0
	return state


static func _receipt(kind: NativeSessionFrame.Kind, body: PackedByteArray,
		generation: int, sequence: int) -> NativeSessionHost.Command:
	var received := NativeSessionHost.Command.new()
	received.seat = 2
	received.connection = 7
	received.frame = NativeSessionFrame.read(NativeSessionFrame.pack(kind, generation, sequence, body),
		NativeSessionFrame.channel(kind))
	return received
