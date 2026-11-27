extends GutTest

const SEAT := &"player"
const REALM := WorldTopology.OVERWORLD
const RUN := &"wp32-test"
const CURRENCY := StarterEncounter.COMMON_CURRENCY

class TerminalWriteStore extends ProfileStore:
	var commits_before_refusal := -1

	func _commit_io() -> bool:
		if commits_before_refusal == 0:
			return false
		if commits_before_refusal > 0:
			commits_before_refusal -= 1
		return super._commit_io()

class EarningClock:
	var reads_before_deadline := -1
	var now: int

	func sample() -> int:
		if reads_before_deadline == 0:
			now = OrdinaryCurrency.MAX_AGE_USEC
		elif reads_before_deadline > 0:
			reads_before_deadline -= 1
		return now


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


func test_bloodbound_publishes_paid_health_and_crimson_cue_in_scoped_view() -> void:
	var encounter := _encounter(90.0, &"H07")
	assert_not_null(encounter)
	assert_eq(_submit(encounter, 1, PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	var state := encounter.movement_state(SEAT, 1, 2)
	var source := encounter.view_for(SEAT)
	var body := RecipientView.pack_encounter(source, state, REALM, encounter.party_statuses(), null)
	var replica := GuestReplica.new()
	assert_true(replica.install_scope(REALM, state))
	assert_eq(replica.receive_frame(_view_frame(body, ReplicationMessage.Kind.VIEW_STATE)), GuestReplica.Acceptance.APPLIED)
	var view := replica.encounter_view(SEAT, 1)
	assert_not_null(view)
	assert_eq(view.player.hp.native_at_scale(0), 75)
	assert_false(view.manual_ready)
	assert_true(view.cues.any(func(cue: StarterCombat.Cue) -> bool: return cue.id == StarterCombatRules.CRIMSON_OFFERING))


func test_spear_is_selectable_for_an_eligible_hero_and_publishes_direction_while_moving() -> void:
	var encounter := _encounter(62.0, &"H02", &"W04")
	assert_not_null(encounter)
	assert_eq(_submit(encounter, 1, PlayerCommand.new(PlayerCommand.MOVE_TO, 75, 128)), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	var state := encounter.movement_state(SEAT, 1, 2)
	var source := encounter.view_for(SEAT)
	var body := RecipientView.pack_encounter(source, state, REALM, encounter.party_statuses(), null)
	var replica := GuestReplica.new()
	assert_true(replica.install_scope(REALM, state))
	assert_eq(replica.receive_frame(_view_frame(body, ReplicationMessage.Kind.VIEW_STATE)), GuestReplica.Acceptance.APPLIED)
	var view := replica.encounter_view(SEAT, 1)
	assert_not_null(view)
	assert_almost_eq(view.player.at.x, 62.0 + 100.0 / 60.0, 0.000001)
	assert_eq(view.others[0].hp.native_at_scale(0), 80)
	assert_eq(view.cues[0].id, &"W04")
	assert_eq(view.cues[0].heading.x, 1.0)
	assert_eq(view.cues[0].reach, 125.0)


func test_twin_daggers_cadence_and_hands_reach_guest_replica_while_hero_moves() -> void:
	var encounter := _encounter(121.0, &"H02", &"W06")
	assert_not_null(encounter)
	var sides: Array[float] = []
	for tick: int in range(1, 26):
		if tick in [1, 25]:
			assert_eq(_submit(encounter, tick, PlayerCommand.new(PlayerCommand.MOVE_AXES, 1, 0)), RunAuthority.Admission.QUEUED)
		elif tick == 4:
			assert_eq(_submit(encounter, tick, PlayerCommand.new(PlayerCommand.MOVE_AXES)), RunAuthority.Admission.QUEUED)
		assert_true(encounter.close_tick())
		if tick not in [1, 24, 25]:
			continue
		var source := encounter.view_for(SEAT)
		var state := encounter.movement_state(SEAT, 1, 2)
		var replica := GuestReplica.new()
		assert_true(replica.install_scope(REALM, state))
		var body := RecipientView.pack_encounter(source, state, REALM, encounter.party_statuses(), null)
		assert_eq(replica.receive_frame(_view_frame(body, ReplicationMessage.Kind.VIEW_STATE)), GuestReplica.Acceptance.APPLIED)
		var view := replica.encounter_view(SEAT, tick)
		assert_not_null(view)
		assert_eq(view.others[0].hp.native_at_scale(0), 82 if tick == 25 else 91)
		if tick == 24:
			assert_true(view.cues.is_empty())
			continue
		assert_almost_eq(view.player.at.x, 121.0 + (4.0 if tick == 25 else 1.0) * 100.0 / 60.0, 0.000001)
		assert_eq(view.cues.size(), 1)
		assert_eq(view.cues[0].id, &"W06")
		assert_eq(view.cues[0].heading.x, 1.0)
		sides.append(view.cues[0].position.y - view.player.at.y)
	assert_eq(sides, [-5.0, 5.0])


func test_live_defeat_waits_for_currency_and_closing_marker_then_publishes_once() -> void:
	if not OS.has_feature("windows"):
		return
	var signer := Crypto.new().generate_rsa(2048)
	for committed_before_refusal: int in [0, 1]:
		var foe := _foe()
		foe.damage = Quantity.from_count(100)
		foe.windup_ticks = 2
		var encounter := _encounter(62.0, &"H01", &"W01", foe)
		assert_not_null(encounter)
		var scope := encounter.checkpoint().identity as Dictionary
		var scratch := DirAccess.create_temp("agip-encounter-ending")
		var store := TerminalWriteStore.new()
		assert_eq(store.open(String(SEAT), scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		var binding := ProfileGrant.Binding.new()
		binding.run = String(scope.run)
		binding.rules = String(scope.rules)
		binding.catalog = String(scope.catalog)
		binding.recipient = String(SEAT)
		binding.issuer = signer
		binding.recipient_key = signer
		var account := "currency/permanent"
		var ordinary := OrdinaryCurrency.begin(store, binding, signer, account)
		assert_true(encounter.attach_ordinary_currency(ordinary))
		assert_true(encounter.begin_ordinary_session(store))
		assert_true(encounter.close_tick())
		assert_true(encounter.close_tick())
		assert_eq(encounter.view_for(SEAT).threats[0].impact_tick, 3)
		assert_eq(ordinary.accrue("fixture/earlier-spawn", Quantity.from_count(7)), OrdinaryCurrency.Eligibility.QUEUED)
		var previous := encounter.closed_result()
		var move := PlayerCommand.new(PlayerCommand.MOVE_TO, 64, 128)
		assert_eq(_submit(encounter, 1, move), RunAuthority.Admission.QUEUED)
		store.commits_before_refusal = committed_before_refusal
		assert_false(encounter.close_tick())
		assert_eq(encounter.next_tick(), 3)
		assert_eq(encounter.movement_acknowledgement(SEAT), 0)
		assert_eq(encounter.closed_result(), previous)
		assert_true(encounter.checkpoint().is_empty())
		assert_eq(encounter.fault(), &"")
		assert_null(encounter.view_for(SEAT))
		assert_eq(_submit(encounter, 2, move), RunAuthority.Admission.INACTIVE)
		assert_eq(ordinary.accrue("fixture/late-spawn", Quantity.from_count(1)), OrdinaryCurrency.Eligibility.FENCED)
		assert_eq(store.balance(account).native_at_scale(0), 7 * committed_before_refusal)
		assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.POSSIBLE_EXPOSURE)
		assert_false(encounter.close_tick())
		store.commits_before_refusal = -1
		assert_true(encounter.close_tick())
		assert_eq(encounter.closed_result().accepted.size(), 1)
		assert_eq(encounter.closed_result().outcomes.size(), 1)
		assert_eq(encounter.movement_acknowledgement(SEAT), 1)
		assert_true(encounter.view_for(SEAT).defeated)
		assert_eq(encounter.view_for(SEAT).player.hp.sign_value, 0)
		assert_false(encounter.close_tick())
		assert_eq(encounter.next_tick(), 4)
		assert_true(store.close())
		assert_eq(store.open(String(SEAT), scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		assert_eq(store.balance(account).native_at_scale(0), 7)
		assert_eq(store.checkpoint()["generation"], 3)
		assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
		assert_true(store.close())


func test_active_currency_deadline_holds_input_and_resumes_world_at_the_same_tick() -> void:
	if not OS.has_feature("windows"):
		return
	var signer := Crypto.new().generate_rsa(2048)
	var foe := _foe()
	foe.windup_ticks = 2
	var control := _encounter(62.0, &"H01", &"W01", foe)
	var walk := PlayerCommand.new(PlayerCommand.MOVE_TO, 78, 128)
	var siphon := PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)
	assert_true(control.close_tick())
	assert_true(control.close_tick())
	assert_eq(_submit(control, 1, walk), RunAuthority.Admission.QUEUED)
	assert_eq(_submit(control, 2, siphon), RunAuthority.Admission.QUEUED)
	assert_true(control.close_tick())
	var expected := control.closed_result()
	var view := control.view_for(SEAT)
	assert_eq(view.player.hp.native_at_scale(0), 84)
	assert_eq(view.others[0].hp.native_at_scale(0), 76)
	assert_eq(view.barrier.native_at_scale(0), 18)
	# With two or five reads the deadline falls before decisions or just
	# before the combat wave publishes. The accepted commands are identical.
	for reads: int in [1, 4]:
		var encounter := _encounter(62.0, &"H01", &"W01", foe)
		var scope := encounter.checkpoint().identity as Dictionary
		var scratch := DirAccess.create_temp("agip-active-earning")
		var store := TerminalWriteStore.new()
		assert_eq(store.open(String(SEAT), scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		var binding := ProfileGrant.Binding.new()
		binding.run = String(scope.run)
		binding.rules = String(scope.rules)
		binding.catalog = String(scope.catalog)
		binding.recipient = String(SEAT)
		binding.issuer = signer
		binding.recipient_key = signer
		var clock := EarningClock.new()
		var ordinary := OrdinaryCurrency.begin(store, binding, signer, "currency/permanent", clock.sample)
		assert_true(encounter.attach_ordinary_currency(ordinary))
		assert_true(encounter.begin_ordinary_session(store))
		assert_true(encounter.close_tick())
		assert_true(encounter.close_tick())
		assert_eq(ordinary.accrue("fixture/earlier-spawn", Quantity.from_count(7)), OrdinaryCurrency.Eligibility.QUEUED)
		var previous := encounter.closed_result()
		assert_eq(_submit(encounter, 1, walk), RunAuthority.Admission.QUEUED)
		assert_eq(_submit(encounter, 2, siphon), RunAuthority.Admission.QUEUED)
		store.commits_before_refusal = 0
		clock.reads_before_deadline = reads
		assert_false(encounter.close_tick())
		assert_eq(encounter.fault(), &"")
		assert_eq(encounter.next_tick(), 3)
		assert_true(encounter.has_unpublished_tick())
		assert_eq(encounter.closed_result(), previous)
		assert_eq(encounter.movement_acknowledgement(SEAT), 0)
		assert_null(encounter.view_for(SEAT))
		assert_null(encounter.movement_state(SEAT, 1, 3))
		assert_true(encounter.checkpoint().is_empty())
		assert_eq(_submit(encounter, 3, walk), RunAuthority.Admission.INACTIVE)
		assert_eq(encounter._kernel.actor_vitals(SEAT).hp.native_at_scale(0), 100)
		assert_almost_eq(encounter._geometry.circle_center(SEAT, 0).x, 62.0 if reads == 1 else view.player.at.x, 0.000001)
		encounter.service_ordinary_currency()
		assert_false(encounter.close_tick())
		assert_eq(store.balance("currency/permanent").sign_value, 0)
		store.commits_before_refusal = -1
		encounter.service_ordinary_currency()
		assert_true(encounter.close_tick())
		assert_eq(encounter.closed_result(), expected)
		assert_eq(encounter.movement_acknowledgement(SEAT), 2)
		assert_eq(encounter.view_for(SEAT).player.at.x, view.player.at.x)
		assert_eq(encounter.view_for(SEAT).player.hp.native_at_scale(0), 84)
		assert_eq(encounter.view_for(SEAT).others[0].hp.native_at_scale(0), 76)
		assert_eq(encounter.view_for(SEAT).barrier.native_at_scale(0), 18)
		assert_eq(store.balance("currency/permanent").native_at_scale(0), 7)
		assert_true(encounter.close_tick())
		assert_eq(encounter.closed_result().outcomes, [])
		assert_true(encounter.settle_orderly_quit())
		assert_true(store.close())
		assert_eq(store.open(String(SEAT), scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		assert_eq(store.balance("currency/permanent").native_at_scale(0), 7)
		assert_eq(store.checkpoint()["generation"], 3)
		assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
		assert_true(store.close())


func test_gameplay_earning_retains_its_deadline_and_later_elimination_across_sqlite_refusal() -> void:
	if not OS.has_feature("windows"):
		return
	var encounter := _assemble({SEAT: 62.0})
	assert_not_null(encounter)
	var scratch := DirAccess.create_temp("agip-closed-earning")
	var store := TerminalWriteStore.new()
	assert_eq(store.open("issuer", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var key := Crypto.new().generate_rsa(2048)
	var clock := EarningClock.new()
	var ordinary := OrdinaryCurrency.begin(store, _grant_binding(encounter, "issuer", key, key), key, CURRENCY, clock.sample)
	var first := _foe()
	first.hp = Quantity.from_count(20)
	var second := _foe()
	second.hp = Quantity.from_count(24)
	assert_false(encounter.place_enemy(&"first", first, RealmSweep.Point.new(110, 128), 7))
	assert_true(encounter.bind_enemy_currency({SEAT: ordinary}))
	assert_true(encounter.place_enemy(&"first", first, RealmSweep.Point.new(110, 128), 7))
	assert_true(encounter.place_enemy(&"second", second, RealmSweep.Point.new(155, 128), 11))
	assert_false(encounter.close_tick())
	assert_true(encounter.begin_ordinary_session(store))
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [&"first"])
	assert_eq(ordinary.pending_amount().native_at_scale(0), 7)
	assert_eq(ordinary.oldest_eligible_usec(), 0)
	assert_true(encounter.close_tick())
	var before := encounter.closed_result()
	assert_eq(_submit(encounter, 1, PlayerCommand.new(PlayerCommand.MOVE_TO, 78, 128)), RunAuthority.Admission.QUEUED)
	assert_eq(_submit(encounter, 2, PlayerCommand.new(PlayerCommand.MANUAL, 155, 128)), RunAuthority.Admission.QUEUED)
	store.commits_before_refusal = 0
	clock.reads_before_deadline = 4
	assert_false(encounter.close_tick())
	assert_true(encounter.has_unpublished_tick())
	assert_eq(encounter.closed_result(), before)
	assert_eq(encounter.movement_acknowledgement(SEAT), 0)
	assert_null(encounter.view_for(SEAT))
	assert_eq(encounter._kernel.actor_vitals(&"second").hp.native_at_scale(0), 24)
	encounter.service_ordinary_currency()
	assert_false(encounter.close_tick())
	assert_eq(ordinary.pending_amount().native_at_scale(0), 7)
	assert_eq(ordinary.oldest_eligible_usec(), 0)
	assert_eq(store.balance(CURRENCY).sign_value, 0)
	store.commits_before_refusal = -1
	encounter.service_ordinary_currency()
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [&"second"])
	assert_eq(encounter.movement_acknowledgement(SEAT), 2)
	assert_eq(encounter.closed_result().accepted.size(), 2)
	assert_true(encounter.view_for(SEAT).cleared)
	assert_eq(ordinary.pending_amount().native_at_scale(0), 11)
	assert_eq(ordinary.oldest_eligible_usec(), OrdinaryCurrency.MAX_AGE_USEC)
	assert_eq(store.balance(CURRENCY).native_at_scale(0), 7)
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [])
	assert_true(encounter.settle_orderly_quit())
	assert_true(store.close())
	assert_eq(store.open("issuer", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.balance(CURRENCY).native_at_scale(0), 18)
	assert_eq(store.checkpoint()["generation"], 4)
	assert_eq(ProfileOrdinarySession.reopen_status(store), ProfileOrdinarySession.ReopenStatus.CLEAR)
	assert_true(store.close())


func test_gameplay_currency_issues_for_a_late_nearby_guest_and_excludes_outside_guest() -> void:
	if not OS.has_feature("windows"):
		return
	var encounter := _assemble({SEAT: 62.0, &"late": 323.5, &"outside": 322.25})
	assert_not_null(encounter)
	var scratch := DirAccess.create_temp("agip-gameplay-party-earning")
	var issuer := ProfileStore.new()
	var late_store := ProfileStore.new()
	var outside_store := ProfileStore.new()
	assert_eq(issuer.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(late_store.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(outside_store.open("carol", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var crypto := Crypto.new()
	var owner := crypto.generate_rsa(2048)
	var late := crypto.generate_rsa(2048)
	var outside := crypto.generate_rsa(2048)
	var local := _grant_binding(encounter, "alice", owner, owner)
	var eligible := _grant_binding(encounter, "bob", owner, late)
	var excluded := _grant_binding(encounter, "carol", owner, outside)
	assert_eq(ProfileGrantSettlement.retain_original_binding(issuer, eligible, owner).status, ProfileStore.CommitResult.COMMITTED)
	assert_eq(ProfileGrantSettlement.retain_original_binding(issuer, excluded, owner).status, ProfileStore.CommitResult.COMMITTED)
	assert_eq(ProfileGrantSettlement.retain_original_binding(late_store, eligible, late).status, ProfileStore.CommitResult.COMMITTED)
	var first := OrdinaryCurrency.begin(issuer, local, owner, CURRENCY)
	var second := OrdinaryCurrency.begin(issuer, eligible, owner, CURRENCY)
	var third := OrdinaryCurrency.begin(issuer, excluded, owner, CURRENCY)
	assert_false(encounter.bind_enemy_currency({SEAT: first, &"late": first, &"outside": third}))
	assert_false(encounter.bind_enemy_currency({SEAT: second, &"late": first, &"outside": third}))
	assert_true(encounter.bind_enemy_currency({SEAT: first, &"late": second, &"outside": third}))
	assert_true(encounter.begin_ordinary_session(issuer))
	var foe := _foe()
	foe.hp = Quantity.from_count(20)
	assert_true(encounter.place_enemy(&"reward", foe, RealmSweep.Point.new(110, 128), 3))
	var step := PlayerCommand.new(PlayerCommand.MOVE_AXES, -1, 0)
	var intent := RunIntent.new(RUN, 1, REALM, &"late", 1, 1, step.action, step)
	assert_eq(encounter.submit(&"late", intent), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [&"reward"])
	assert_eq(encounter.closed_result().outcomes[1].owner, SEAT)
	assert_eq(first.pending_amount().native_at_scale(0), 3)
	assert_eq(second.pending_amount().native_at_scale(0), 3)
	assert_eq(third.pending_amount().native_at_scale(0), 0)
	assert_true(encounter.settle_orderly_quit())
	assert_eq(issuer.balance(CURRENCY).native_at_scale(0), 3)
	var grants := issuer.pending_grants()
	assert_eq(grants.size(), 1)
	if grants.size() == 1:
		assert_eq(grants[0].recipient, "bob")
		var applied := ProfileGrantSettlement.apply(late_store, eligible, late, grants[0].body)
		assert_eq(applied.receipt.status, ProfileStore.CommitResult.COMMITTED)
		assert_eq(ProfileGrantSettlement.apply(late_store, eligible, late, grants[0].body).receipt.status, ProfileStore.CommitResult.DUPLICATE)
		assert_eq(ProfileGrantSettlement.acknowledge(issuer, eligible, applied.acknowledgement).status, ProfileStore.CommitResult.COMMITTED)
	assert_true(issuer.pending_grants().is_empty())
	assert_eq(late_store.balance(CURRENCY).native_at_scale(0), 3)
	assert_eq(outside_store.balance(CURRENCY).sign_value, 0)
	assert_true(late_store.close())
	assert_eq(late_store.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(late_store.balance(CURRENCY).native_at_scale(0), 3)
	assert_true(late_store.close())
	assert_true(outside_store.close())
	assert_true(issuer.close())


func test_gameplay_currency_survives_faction_only_kill_and_pays_once_across_combat_lives() -> void:
	if not OS.has_feature("windows"):
		return
	var encounter := _assemble({SEAT: 62.0})
	var scratch := DirAccess.create_temp("agip-original-spawn-earning")
	var store := ProfileStore.new()
	assert_eq(store.open("issuer", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var key := Crypto.new().generate_rsa(2048)
	var binding := _grant_binding(encounter, "issuer", key, key)
	var ordinary := OrdinaryCurrency.begin(store, binding, key, CURRENCY)
	assert_true(encounter.bind_enemy_currency({SEAT: ordinary}))
	assert_true(encounter.begin_ordinary_session(store))
	var foe := _foe()
	foe.faction = &"victim"
	foe.foes = []
	foe.hp = Quantity.from_count(9)
	var striker := _foe()
	striker.faction = &"predator"
	striker.foes = [&"victim"]
	striker.radius = 4
	striker.attack_radius = 4
	striker.windup_ticks = 1
	assert_true(encounter.place_enemy(&"reward", foe, RealmSweep.Point.new(144, 128), 3))
	assert_true(encounter.place_enemy(&"faction", striker, RealmSweep.Point.new(173, 128)))
	assert_true(encounter.close_tick())
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [&"reward"])
	assert_eq(ordinary.pending_amount().sign_value, 0)
	assert_true(encounter._activity.reanimate(&"reward", 1, Quantity.from_count(1), 10))
	assert_eq(_submit(encounter, 1, PlayerCommand.new(PlayerCommand.MANUAL, 144, 128)), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	assert_eq(_eliminations(encounter), [&"reward"])
	assert_eq(ordinary.pending_amount().native_at_scale(0), 3)
	assert_true(encounter._activity.reanimate(&"reward", 2, Quantity.from_count(1), 10))
	assert_eq(_submit(encounter, 2, PlayerCommand.new(PlayerCommand.MOVE_TO, 78, 128)), RunAuthority.Admission.QUEUED)
	var later_kills: Array[StringName] = []
	for tick: int in range(4, 13):
		assert_true(encounter.close_tick())
		later_kills.append_array(_eliminations(encounter))
	assert_eq(later_kills, [&"reward"])
	assert_eq(ordinary.pending_amount().native_at_scale(0), 3)
	assert_true(encounter.settle_orderly_quit())
	assert_true(store.close())
	assert_eq(store.open("issuer", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.balance(CURRENCY).native_at_scale(0), 3)
	# Replay the same original occurrence from an empty live earning buffer.
	var replay := _assemble({SEAT: 62.0})
	var retry := OrdinaryCurrency.begin(store, binding, key, CURRENCY)
	assert_true(replay.bind_enemy_currency({SEAT: retry}))
	assert_true(replay.place_enemy(&"reward", foe, RealmSweep.Point.new(144, 128), 3))
	assert_true(replay.begin_ordinary_session(store))
	assert_true(replay.close_tick())
	assert_true(replay.close_tick())
	assert_eq(_submit(replay, 1, PlayerCommand.new(PlayerCommand.MANUAL, 144, 128)), RunAuthority.Admission.QUEUED)
	assert_true(replay.close_tick())
	assert_eq(_eliminations(replay), [&"reward"])
	assert_true(replay.settle_orderly_quit())
	assert_eq(store.balance(CURRENCY).native_at_scale(0), 3)
	assert_true(store.close())


static func _grant_binding(encounter: StarterEncounter, recipient: String, issuer: CryptoKey,
		key: CryptoKey) -> ProfileGrant.Binding:
	var identity: Dictionary = encounter.checkpoint().identity
	var binding := ProfileGrant.Binding.new()
	binding.run = String(identity.run)
	binding.rules = String(identity.rules)
	binding.catalog = String(identity.catalog)
	binding.recipient = recipient
	binding.issuer = issuer
	binding.recipient_key = key
	return binding


static func _eliminations(encounter: StarterEncounter) -> Array[StringName]:
	var ids: Array[StringName] = []
	for outcome: Dictionary in encounter.closed_result().outcomes:
		if outcome.get("eliminated", false):
			ids.append(outcome.target)
	return ids


static func _encounter(start_x: float, hero: StringName = &"H01", weapon: StringName = &"W01",
		foe: WorldEnemy.Rules = null) -> StarterEncounter:
	var encounter := _assemble({SEAT: start_x}, hero, weapon)
	var enemy := foe if foe != null else _foe()
	return encounter if encounter != null and encounter.place_enemy(&"near", enemy, RealmSweep.Point.new(155, 128)) else null


static func _assemble(positions: Dictionary[StringName, float], hero: StringName = &"H01",
		weapon: StringName = &"W01") -> StarterEncounter:
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
	setup.role = RunSetup.Role.HOST if positions.size() > 1 else RunSetup.Role.SOLO
	var builds: Dictionary[StringName, StarterEncounter.Build] = {}
	for id: StringName in positions:
		setup.initial_realms[id] = REALM
		var build := StarterEncounter.Build.new()
		build.preparation = RunPreparation.select(catalog, hero, weapon, [&"", &""], slots, {hero: true, weapon: true})
		build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), id)
		build.start = RealmSweep.Point.new(positions[id], 128.0)
		build.maximum_hp = Quantity.from_count(100)
		builds[id] = build
	var floor := WorldExploration.create(WorldTopology.generate(setup.seed), positions.keys())
	return StarterEncounter.assemble(setup, SEAT, floor, builds)


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
