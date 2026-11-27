extends GutTest

const SEAT := &"player"
const REALM := WorldTopology.OVERWORLD
const RUN := &"wp32-test"


func test_generated_encounter_strike_hits_a_stationary_player_and_misses_after_legal_movement() -> void:
	for evades: bool in [false, true]:
		var encounter := _encounter(62.0)
		assert_not_null(encounter)
		assert_true(encounter.close_tick())
		var warning := encounter.view_for(SEAT).threats[0]
		assert_eq(warning.impact_tick, 40)
		assert_eq(warning.center.x, 62.0)
		warning.center.x = -999.0
		assert_eq(encounter.view_for(SEAT).threats[0].center.x, 62.0)
		if evades:
			var move := PlayerCommand.new(PlayerCommand.MOVE_AXES, 0.0, -1.0)
			assert_eq(_submit(encounter, 1, move), RunAuthority.Admission.QUEUED)
		while encounter.next_tick() <= warning.impact_tick:
			assert_true(encounter.close_tick())
			assert_eq(encounter.fault(), &"")
		var view := encounter.view_for(SEAT)
		assert_true(view.threats.is_empty())
		assert_eq(view.player.hp.native_at_scale(0), 100 if evades else 84)
		var events: Array = encounter.closed_result()["outcomes"]
		assert_eq(events.size(), 0 if evades else 1)
		if evades:
			assert_lt(view.player.at.y, 80.0)


func test_encounter_manual_and_weapon_commit_at_the_closed_boundary_with_a_hidden_foe() -> void:
	var encounter := _encounter(90.0)
	assert_not_null(encounter)
	assert_true(encounter.place_enemy(&"covered", _foe(), RealmSweep.Point.new(344, 228)))
	assert_eq(encounter.view_for(SEAT).others.size(), 1)
	var aim := PlayerCommand.new(PlayerCommand.TARGET, 344, 228)
	assert_eq(_submit(encounter, 1, aim), RunAuthority.Admission.QUEUED)
	var cast := PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)
	var bridge := HostMovementBridge.new(encounter)
	assert_true(bridge.bind(1, 20, 3, RUN, 1, REALM, SEAT, 17))
	var payload := ReplicationMessage.pack(ReplicationMessage.Kind.INTERACTION,
		RealmInteractionFrame.pack(1, 17, cast))
	var received := NativeSessionHost.Command.new()
	received.seat = 1
	received.connection = 20
	received.frame = NativeSessionFrame.read(NativeSessionFrame.pack(NativeSessionFrame.Kind.RELIABLE, 3, 1, payload),
		NativeSessionFrame.channel(NativeSessionFrame.Kind.RELIABLE))
	assert_eq(bridge.submit_interaction(received), RunAuthority.Admission.QUEUED)
	assert_eq(bridge.submit_interaction(received), RunAuthority.Admission.DUPLICATE)
	assert_true(encounter.close_tick())
	assert_eq(encounter.checkpoint().sequences[SEAT], 1)
	assert_eq(encounter.closed_result().accepted.size(), 2)
	assert_true(encounter.closed_result().accepted[1].reliable)
	var view := encounter.view_for(SEAT)
	assert_false(view.manual_ready)
	assert_eq(view.selected, &"")
	assert_eq(view.others.size(), 1)
	assert_eq(view.others[0].id, &"near")
	assert_eq(view.barrier.native_at_scale(0), 18)
	var hits: Array[StringName] = []
	for outcome: Dictionary in encounter.closed_result()["outcomes"]:
		if outcome.has("family"):
			hits.append(outcome.family)
			assert_eq(outcome.target, &"near")
			assert_eq(outcome.owner, SEAT)
	assert_eq(hits.size(), 2)
	assert_true(&"W01" in hits)
	assert_true(StarterCombatRules.SIPHON in hits)


func test_peer_encounter_snapshot_preserves_closed_health_and_omits_covered_creatures() -> void:
	var encounter := _encounter(90.0)
	assert_true(encounter.place_enemy(&"covered", _foe(), RealmSweep.Point.new(344, 228)))
	var cast := PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)
	assert_eq(_submit(encounter, 1, cast), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	var state := encounter.movement_state(SEAT, 1, 2)
	var source := encounter.view_for(SEAT)
	var body := RecipientView.pack_encounter(source, state, REALM, encounter.party_statuses(), null)
	assert_false(body.get_string_from_utf8().contains("covered"))
	var replica := GuestReplica.new()
	assert_true(replica.install_scope(REALM, state))
	var frame := _view_frame(body, ReplicationMessage.Kind.VIEW_STATE)
	assert_eq(replica.receive_frame(frame), GuestReplica.Acceptance.APPLIED)
	assert_eq(replica.receive_frame(frame), GuestReplica.Acceptance.STALE)
	assert_null(replica.encounter_view(&"other", 1))
	var view := replica.encounter_view(SEAT, 1, RealmSweep.Point.new(91, 128))
	assert_not_null(view)
	if view != null:
		assert_eq(view.player.at.x, 91.0)
		assert_eq(view.player.hp.native_at_scale(0), 100)
		assert_eq(view.others[0].hp.native_at_scale(0), 56)
		assert_eq(view.barrier.native_at_scale(0), 18)
		assert_false(view.manual_ready)
		assert_eq(view.threats.size(), 1)
		assert_eq(view.threats[0].impact_tick, 40)
		assert_eq(view.cues.size(), source.cues.size())
		view.others[0].at.x = 999.0
		view.threats[0].center.x = 999.0
		assert_eq(replica.encounter_view(SEAT, 1).others[0].at.x, 155.0)
		assert_eq(replica.encounter_view(SEAT, 1).threats[0].center.x, 90.0)
	var invalid: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	invalid["encounter"]["roster"]["near"][1] = "zz"
	assert_eq(replica.receive_frame(_view_frame(JSON.stringify(invalid).to_utf8_buffer(),
		ReplicationMessage.Kind.VIEW)), GuestReplica.Acceptance.INVALID)
	var newer := encounter.movement_state(SEAT, 2, 3)
	assert_true(replica.install_scope(REALM, newer))
	assert_eq(replica.receive_frame(frame), GuestReplica.Acceptance.STALE)
	assert_null(replica.encounter_view(SEAT, 1))


static func _encounter(start_x: float) -> StarterEncounter:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.epoch = 1
	setup.seed = 3207
	setup.authority_id = SEAT
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"test"
	setup.initial_realms = {SEAT: REALM}
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(start_x, 128.0)
	build.maximum_hp = Quantity.from_count(100)
	var floor := WorldExploration.create(WorldTopology.generate(setup.seed), [SEAT])
	var encounter := StarterEncounter.assemble(setup, SEAT, floor, {SEAT: build})
	return encounter if encounter != null and encounter.place_enemy(&"near", _foe(), RealmSweep.Point.new(155, 128)) else null


static func _foe() -> WorldEnemy.Rules:
	var rules := WorldEnemy.Rules.new()
	rules.faction = &"test-foe"
	rules.foes = [WorldEnemy.PARTY]
	rules.family = &"fixture/test-sweep"
	rules.hp = Quantity.from_count(100)
	rules.damage = Quantity.from_count(16)
	rules.radius = 12.0
	rules.sight = 154.0
	rules.attack_range = 103.0
	rules.attack_radius = 26.0
	rules.windup_ticks = 39
	rules.recovery_ticks = 78
	return rules


static func _submit(encounter: StarterEncounter, sequence: int, command: PlayerCommand) -> RunAuthority.Admission:
	var intent := RunIntent.new(RUN, 1, REALM, SEAT, encounter.next_tick(), sequence, command.action, command)
	return encounter.submit(SEAT, intent)


static func _view_frame(body: PackedByteArray, kind: ReplicationMessage.Kind) -> NativeSessionFrame:
	var lane := ReplicationMessage.transport_kind(kind)
	return NativeSessionFrame.read(NativeSessionFrame.pack(lane, 1, 1, ReplicationMessage.pack(kind, body)),
		NativeSessionFrame.channel(lane))
