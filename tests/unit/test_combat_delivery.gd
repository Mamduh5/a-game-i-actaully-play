extends GutTest

const REALM := &"delivery"
const SOURCE := &"source"
const TARGET := &"target"
const MANA := &"mana"


func test_refresh_keeps_exact_phase_and_tick_precedes_natural_expiry() -> void:
	var certifier := RealmCircleTime.new()
	var contact := certifier.measure(RealmSweep.Point.new(0, 0), RealmSweep.Point.new(8, 0), 0.0,
		RealmSweep.Point.new(3, 0), RealmSweep.Point.new(3, 0), 1.0)
	var start := CombatInstant.at_contact(10, contact)
	var schedule := CombatDeliverySchedule.create(start, 8, 4)
	assert_not_null(schedule)
	assert_null(schedule.due_through(CombatInstant.at_tick(14)))
	assert_true(schedule.refresh(start.after_ticks(2), 10))
	assert_false(schedule.refresh(start.after_ticks(5), 20), "An earlier unsettled tick retains the frontier")
	for index: int in [1, 2, 3]:
		var expected := start.after_ticks(index * 4)
		var interval := schedule.due_through(expected)
		assert_not_null(interval)
		if interval == null:
			return
		assert_eq(interval.kind, CombatDeliverySchedule.Kind.TICK)
		assert_eq(interval.instant.order_against(expected), RealmCircleTime.Order.SAME)
		assert_eq(interval.ordinal, index)
		assert_true(schedule.settle(interval))
		assert_false(schedule.settle(interval))
	var expiry := schedule.due_through(start.after_ticks(12))
	assert_not_null(expiry)
	if expiry != null:
		assert_eq(expiry.kind, CombatDeliverySchedule.Kind.NATURAL_EXPIRY)
		assert_true(schedule.settle(expiry))
	assert_eq(schedule.end_reason, CombatDeliverySchedule.End.NATURAL)
	assert_null(schedule.due_through(CombatInstant.at_tick(100)))


func test_early_cleanup_never_issues_expiry_and_due_entries_are_bound_to_their_effect() -> void:
	var start := CombatInstant.at_tick(2)
	var first := CombatDeliverySchedule.create(start, 7, 10, true)
	var second := CombatDeliverySchedule.create(start, 7, 10, true)
	var tick := first.due_through(start)
	assert_not_null(tick)
	assert_false(second.settle(tick))
	assert_true(first.settle(tick))
	assert_null(first.due_through(CombatInstant.at_tick(8)))
	assert_true(first.end_early(CombatDeliverySchedule.End.REALM_CLEANUP))
	assert_false(first.end_early(CombatDeliverySchedule.End.REALM_CLEANUP))
	assert_null(first.due_through(CombatInstant.at_tick(10)))
	var expiry := second.due_through(start)
	assert_true(second.settle(expiry))
	assert_eq(second.due_through(CombatInstant.at_tick(9)).kind, CombatDeliverySchedule.Kind.NATURAL_EXPIRY)


func test_paid_delivery_reentry_cadence_uses_frozen_action_and_misses_cost_once() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	source.resources[MANA] = Quantity.from_count(8)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(TARGET, 15)))
	var geometry := RealmGeometry.new(REALM)
	var point := RealmSweep.Point.new(3, 0)
	assert_true(geometry.add_circle(TARGET, 0, point, 1.0, 1))
	var query := geometry.certify_circle_sweep(REALM, RealmSweep.Point.new(0, 0), RealmSweep.Point.new(8, 0), 0.0, 1)
	var contact := query.contacts[0]
	var action := _action(1)
	assert_null(CombatDelivery.activate(kernel, action, &"another_realm", 4))
	var field := CombatDelivery.activate(kernel, action, REALM, 4)
	assert_not_null(field)
	if field == null:
		return
	var schedule := CombatDeliverySchedule.create(CombatInstant.at_tick(1), 8, 2)
	assert_eq(field.admit(2, contact, 1, true), CombatDelivery.Result.ADMITTED)
	action.components[0].base = Quantity.from_count(12)
	assert_true(schedule.refresh(CombatInstant.at_tick(3), 10))
	assert_eq(field.admit(3, contact, 1, true), CombatDelivery.Result.CADENCE)
	assert_eq(field.admit(6, contact, 2, true), CombatDelivery.Result.INVALID)
	assert_eq(field.admit(6, contact, 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(field.finish())
	assert_eq(field.admit(10, contact, 1, true), CombatDelivery.Result.CLOSED)
	assert_false(field.finish())
	for frontier: int in [3, 7]:
		var group := kernel.resolve_next(CombatInstant.at_tick(frontier))
		assert_eq(group.result, CombatKernel.Result.CLOSED)
		assert_eq(group.hits.size(), 1)
		if group.hits.size() == 1:
			assert_eq(group.hits[0].origin.delivery_part, 1 if frontier == 3 else 2)
	assert_eq(kernel.actor_snapshot(TARGET).hp.amount.native_at_scale(0), 11)
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 5)
	var missed := CombatDelivery.activate(kernel, _action(8), REALM)
	assert_not_null(missed)
	if missed != null:
		assert_true(missed.finish())
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 2)


func test_sweep_sorts_actual_contacts_and_interception_wins_equal_time() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	source.resources[MANA] = Quantity.from_count(3)
	assert_true(kernel.add_actor(source))
	var geometry := RealmGeometry.new(REALM)
	var ids: Array[StringName] = [&"a_before", &"behind", &"equal", &"z_first"]
	var positions := [4, 12, 9, 2]
	for index: int in ids.size():
		assert_true(kernel.add_actor(_actor(ids[index], 10)))
		assert_true(geometry.add_circle(ids[index], 0, RealmSweep.Point.new(positions[index], 0), 1.0, 1))
	assert_true(geometry.add_circle(SOURCE, 0, RealmSweep.Point.new(0, 0), 1.0, 1))
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(8, -4)
	edge.last = RealmSweep.Point.new(8, 4)
	assert_true(geometry.add_segment(&"shield", 0, edge, 2, true))
	var delivery := CombatDelivery.activate(kernel, _action(1), REALM, 0, true)
	var sweep := delivery.plan_sweep(geometry, RealmSweep.Point.new(0, 0), RealmSweep.Point.new(16, 0), 0.0, 1, 2)
	assert_not_null(sweep)
	if sweep == null:
		return
	assert_eq(sweep.revision, geometry.revision)
	assert_eq(sweep.blocker.entity, &"shield")
	assert_eq(sweep.contacts.size(), 2)
	if sweep.contacts.size() == 2:
		assert_eq(sweep.contacts[0].entity, &"z_first")
		assert_eq(sweep.contacts[1].entity, &"a_before")
	for planned: RealmGeometry.Contact in sweep.contacts:
		assert_eq(delivery.admit(2, planned, 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(delivery.finish())
	for index: int in sweep.contacts.size():
		var closed := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(closed.result, CombatKernel.Result.CLOSED)
		assert_eq(closed.hits[0].target, sweep.contacts[index].entity)
	assert_eq(kernel.actor_snapshot(&"equal").hp.amount.native_at_scale(0), 10)
	assert_eq(kernel.actor_snapshot(&"behind").hp.amount.native_at_scale(0), 10)


func test_priced_pulse_declines_next_interval_without_canceling_frozen_prior_contact() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 10)
	source.resources[MANA] = Quantity.from_count(4)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(TARGET, 10)))
	var first := CombatInstant.at_tick(1)
	var clock := CombatDeliverySchedule.create(first, 10, 2, true)
	var first_tick := clock.due_through(first)
	assert_eq(CombatDelivery.activate_pulse(clock, first_tick, kernel, _action(2), REALM).result,
		CombatDelivery.PulseResult.INVALID)
	var paid := CombatDelivery.activate_pulse(clock, first_tick, kernel, _action(1), REALM)
	assert_eq(paid.result, CombatDelivery.PulseResult.PAID)
	if paid.delivery == null:
		return
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	assert_eq(paid.delivery.admit(5, proof, 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(paid.delivery.finish())
	var later := clock.due_through(CombatInstant.at_tick(3))
	var unpaid := CombatDelivery.activate_pulse(clock, later, kernel, _action(3), REALM)
	assert_eq(unpaid.result, CombatDelivery.PulseResult.DECLINED)
	assert_eq(clock.end_reason, CombatDeliverySchedule.End.PAYMENT_DECLINED)
	assert_null(clock.due_through(CombatInstant.at_tick(20)))
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 1)
	var group := kernel.resolve_next(CombatInstant.at_tick(5))
	assert_eq(group.result, CombatKernel.Result.CLOSED)
	assert_eq(group.hits.size(), 1)
	assert_eq(kernel.actor_snapshot(TARGET).hp.amount.native_at_scale(0), 8)


func test_target_price_settles_only_with_eligible_certified_contact() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 10)
	source.resources[MANA] = Quantity.from_count(6)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(TARGET, 20)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var contact := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var first := _action(1)
	first.cooldown = &"target_price"
	first.cooldown_ticks = 5
	assert_eq(kernel.commit_for_target(first, REALM, 2, contact, 2, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.commit_for_target(first, REALM, 0, contact, 1, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 6)
	assert_eq(kernel.pending_count(), 0)
	assert_eq(kernel.commit_for_target(first, REALM, 2, contact, 1, true), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.commit_for_target(first, REALM, 2, contact, 1, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(2)).hits.size(), 1)
	var second := _action(5)
	second.cooldown = first.cooldown
	second.cooldown_ticks = first.cooldown_ticks
	assert_eq(kernel.commit_for_target(second, REALM, 5, contact, 1, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 3)
	second.origin.committed_at = CombatInstant.at_tick(6)
	assert_eq(kernel.commit_for_target(second, REALM, 6, contact, 1, true), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 0)
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(6)).hits.size(), 1)
	assert_eq(kernel.actor_snapshot(TARGET).hp.amount.native_at_scale(0), 16)


func test_bleed_preserves_owned_snapshots_and_consumes_only_captured_existing_stacks() -> void:
	var kernel := CombatKernel.new()
	var second_source := &"teammate"
	assert_true(kernel.add_actor(_actor(SOURCE, 20)))
	assert_true(kernel.add_actor(_actor(second_source, 20)))
	assert_true(kernel.add_actor(_actor(TARGET, 150)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var bleed := CombatBleedLedger.create(TARGET, 1)
	var application := CombatBleedLedger.Application.new()
	application.capacity = 2
	application.duration = 12
	application.period = 3
	application.offense = CombatAction.Component.new()
	var first_origin: CombatOrigin
	var second_origin: CombatOrigin
	var snapshots: CombatBleedLedger.Prestate
	for index: int in [1, 2, 3]:
		var instant := CombatInstant.at_tick(index)
		var closed := _realized_hit(kernel, proof, second_source if index == 2 else SOURCE, &"primary", index)
		var hit := closed.hits[0]
		application.offense.base = Quantity.from_count(index * 5)
		if index == 1:
			first_origin = hit.origin
		elif index == 2:
			second_origin = hit.origin
		else:
			snapshots = bleed.capture(instant)
		assert_true(bleed.apply(hit, instant, application))
		assert_false(bleed.apply(hit, instant, application))
	var removed := bleed.consume(first_origin, snapshots, CombatInstant.at_tick(3), 2)
	assert_eq(removed.size(), 1)
	if removed.size() == 1:
		assert_eq(removed[0].offense.base.native_at_scale(0), 5)
	assert_true(bleed.consume(first_origin, snapshots, CombatInstant.at_tick(3), 2).is_empty())
	assert_null(bleed.due_for(first_origin, CombatInstant.at_tick(3)))
	var owned := bleed.due_for(first_origin, CombatInstant.at_tick(4))
	assert_not_null(owned)
	if owned != null:
		assert_eq(owned.stacks.size(), 1)
		assert_eq(owned.stacks[0].offense.base.native_at_scale(0), 15)
		assert_true(bleed.settle(owned))
	assert_null(bleed.due_for(second_origin, CombatInstant.at_tick(4)))
	var teammate := bleed.due_for(second_origin, CombatInstant.at_tick(5))
	assert_not_null(teammate)
	if teammate != null:
		assert_eq(teammate.stacks[0].offense.base.native_at_scale(0), 10)


func test_distinct_source_window_respects_family_owner_exclusions_and_cooldown() -> void:
	var kernel := CombatKernel.new()
	var partner := &"partner"
	assert_true(kernel.add_actor(_actor(SOURCE, 20)))
	assert_true(kernel.add_actor(_actor(partner, 20)))
	assert_true(kernel.add_actor(_actor(TARGET, 150)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var window := CombatSourceWindow.create(TARGET, 1, 4, 3)
	var extended := CombatSourceWindow.create(TARGET, 1, 4, 3, 2)
	var families: Array[StringName] = [&"familiar", &"familiar", &"blade", &"rune", &"wave", &"blade", &"familiar", &"blade"]
	var times: Array[int] = [1, 2, 3, 4, 5, 6, 8, 9]
	var matched: Array[CombatSourceWindow.Match] = []
	var additional: Array[CombatSourceWindow.Match] = []
	for index: int in times.size():
		var origin := partner if index == 2 else SOURCE
		var wave := _realized_hit(kernel, proof, origin, families[index], times[index])
		var pair := window.observe(wave, wave.hits[0], index != 3)
		if pair != null:
			matched.append(pair)
		var possible_third := extended.observe(wave, wave.hits[0], index != 3)
		if possible_third != null:
			additional.append(possible_third)
	assert_eq(matched.size(), 2)
	if matched.size() == 2:
		assert_eq(matched[0].first_family, &"familiar")
		assert_eq(matched[0].first.activation, 2)
		assert_eq(matched[0].second_family, &"wave")
		assert_eq(matched[0].second.owner, SOURCE)
		assert_eq(matched[1].first.activation, 8)
		assert_eq(matched[1].second.activation, 9)
	assert_eq(additional.size(), 3)
	if additional.size() == 3:
		assert_null(additional[0].third)
		assert_eq(additional[1].third.activation, 6)
		assert_eq(additional[1].third_family, &"blade")
		assert_eq(additional[2].first.activation, 8)


func test_retuned_rate_keeps_exact_accrued_progress_without_affecting_other_domains() -> void:
	var attacks := CombatCadenceProgress.create(10)
	var ticks := CombatCadenceProgress.create(4)
	assert_eq(attacks.advance(5), 0)
	assert_eq(ticks.advance(5), 1)
	assert_false(attacks.retune(0))
	assert_true(attacks.retune(12))
	assert_eq(attacks.advance(5), 0)
	assert_eq(attacks.advance(1), 1)
	assert_eq(ticks.advance(5), 1)
	assert_eq(ticks.advance(1), 0)
	assert_eq(attacks.advance(-1), -1)
	assert_eq(attacks.advance(30), 2)
	assert_eq(attacks.advance(6), 1)


func test_returning_flight_tracks_live_anchor_and_keeps_one_frozen_hit_per_phase() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	source.resources[MANA] = Quantity.from_count(3)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(TARGET, 20)))
	var geometry := RealmGeometry.new(REALM)
	var launch := RealmSweep.Point.new(0, 0)
	var outbound := RealmSweep.Point.new(8, 0)
	assert_true(geometry.add_circle(SOURCE, 0, launch, 1.0, 1))
	assert_true(geometry.add_circle(TARGET, 0, RealmSweep.Point.new(3, 0), 1.0, 1))
	var action := _action(1)
	var flight := CombatReturningFlight.create(kernel, action, REALM, launch, outbound, 10)
	assert_not_null(flight)
	if flight == null:
		return
	action.components[0].base = Quantity.from_count(20)
	var outward := flight.plan(geometry, null, 4.0, 0.0, 1, 2)
	assert_eq(outward.sweep.contacts.size(), 1)
	assert_eq(flight.admit(outward, 2, outward.sweep.contacts[0], 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(flight.settle(outward))
	var reach := flight.plan(geometry, null, 4.0, 0.0, 1, 2)
	assert_eq(reach.sweep.contacts.size(), 1)
	assert_eq(flight.admit(reach, 3, reach.sweep.contacts[0], 1, true), CombatDelivery.Result.CADENCE)
	assert_true(flight.settle(reach))
	assert_eq(flight.phase, CombatReturningFlight.Phase.RETURNING)
	var stale := flight.plan(geometry, launch, 4.0, 0.0, 1, 2)
	assert_true(geometry.commit_circle_pose(SOURCE, 0, RealmSweep.Point.new(8, 8)))
	assert_true(geometry.commit_circle_pose(TARGET, 0, RealmSweep.Point.new(8, 2)))
	assert_false(flight.settle(stale))
	var returning := flight.plan(geometry, geometry.circle_center(SOURCE, 0), 4.0, 0.0, 1, 2)
	assert_eq(returning.finish.x, 8.0)
	assert_eq(returning.finish.y, 4.0)
	assert_eq(returning.sweep.contacts.size(), 1)
	assert_eq(flight.admit(returning, 4, returning.sweep.contacts[0], 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(flight.settle(returning))
	assert_true(geometry.commit_circle_pose(SOURCE, 0, RealmSweep.Point.new(12, 4)))
	var catch_step := flight.plan(geometry, geometry.circle_center(SOURCE, 0), 4.0, 0.0, 1, 2)
	assert_true(flight.settle(catch_step))
	assert_eq(flight.phase, CombatReturningFlight.Phase.FINISHED)
	for frontier: int in [3, 5]:
		assert_eq(kernel.resolve_next(CombatInstant.at_tick(frontier)).hits.size(), 1)
	assert_eq(kernel.actor_snapshot(TARGET).hp.amount.native_at_scale(0), 16)
	assert_eq(kernel.actor_snapshot(SOURCE).resources[MANA].native_at_scale(0), 0)


func test_returning_flight_leaves_a_certified_clear_pose_at_large_wall_coordinates() -> void:
	for wall_slant: float in [0.0, 70.0]:
		var kernel := CombatKernel.new()
		var source := _actor(SOURCE, 20)
		source.resources[MANA] = Quantity.from_count(3)
		assert_true(kernel.add_actor(source))
		var geometry := RealmGeometry.new(REALM)
		var edge := RealmOutline.Edge.new()
		edge.first = RealmSweep.Point.new(1100 - wall_slant, 900)
		edge.last = RealmSweep.Point.new(1100 + wall_slant, 1100)
		assert_true(geometry.add_segment(&"wall", 0, edge, 2, true))
		var launch := RealmSweep.Point.new(1000, 1000)
		var flight := CombatReturningFlight.create(kernel, _action(1), REALM, launch,
			RealmSweep.Point.new(1200, 1000), 10)
		var outward := flight.plan(geometry, null, 150.0, 10.0, 1, 2)
		assert_not_null(outward)
		if outward == null:
			continue
		assert_eq(outward.sweep.blocker.entity, &"wall")
		assert_true(outward.finish.x > 1080.0)
		var stored := geometry.certify_circle_snapshot(REALM, outward.finish, 10.0, 2)
		assert_true(stored.contacts.is_empty())
		assert_true(stored.unresolved.is_empty())
		assert_true(flight.settle(outward))
		var returning := flight.plan(geometry, launch, 30.0, 10.0, 1, 2)
		assert_not_null(returning)
		if returning == null:
			continue
		assert_null(returning.sweep.blocker)
		assert_almost_eq(returning.finish.x, outward.finish.x - 30.0, 0.000001)
		assert_eq(returning.next_phase, CombatReturningFlight.Phase.RETURNING)
		assert_true(flight.settle(returning))
		if returning.sweep.blocker != null:
			continue
		var obstruction := RealmOutline.Edge.new()
		obstruction.first = RealmSweep.Point.new(1020, 900)
		obstruction.last = RealmSweep.Point.new(1020, 1100)
		assert_true(geometry.add_segment(&"new_wall", 0, obstruction, 2, true))
		var intercepted := flight.plan(geometry, launch, 100.0, 10.0, 1, 2)
		assert_eq(intercepted.sweep.blocker.entity, &"new_wall")
		assert_eq(intercepted.next_phase, CombatReturningFlight.Phase.FINISHED)


func test_returning_flight_clips_against_the_blockers_elapsed_motion() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	source.resources[MANA] = Quantity.from_count(3)
	assert_true(kernel.add_actor(source))
	var geometry := RealmGeometry.new(REALM)
	var launch := RealmSweep.Point.new(1000, 1000)
	var before := RealmSweep.Point.new(1100, 1000)
	assert_true(geometry.add_circle(&"shield", 0, before, 10.0, 2))
	assert_true(geometry.stage_circle_motion(&"shield", 0, RealmSweep.Point.new(1140, 1000)))
	var flight := CombatReturningFlight.create(kernel, _action(1), REALM, launch,
		RealmSweep.Point.new(1200, 1000), 10)
	var outward := flight.plan(geometry, null, 150.0, 10.0, 1, 2)
	assert_not_null(outward)
	if outward == null:
		return
	assert_eq(outward.sweep.blocker.entity, &"shield")
	assert_almost_eq(outward.finish.x, 1109.090909090909, 0.000001)
	assert_true(flight.settle(outward))
	assert_true(geometry.commit_circle_motion(&"shield", 0))
	var returning := flight.plan(geometry, launch, 30.0, 10.0, 1, 2)
	assert_null(returning.sweep.blocker)
	assert_eq(returning.next_phase, CombatReturningFlight.Phase.RETURNING)


func test_mines_detonate_on_arming_and_cap_independent_waiting_charge() -> void:
	var certifier := RealmCircleTime.new()
	var proof := certifier.measure(RealmSweep.Point.new(0, 0), RealmSweep.Point.new(8, 0), 0.0,
		RealmSweep.Point.new(3, 0), RealmSweep.Point.new(3, 0), 1.0)
	var placed := CombatInstant.at_contact(2, proof)
	var base := Quantity.from_count(3)
	var gain := Quantity.from_count(4)
	var cap := Quantity.from_count(12)
	var early := CombatMineCharge.create(placed, 1, 6, base, gain, cap)
	var developing := CombatMineCharge.create(placed, 1, 6, base, gain, cap)
	var saturated := CombatMineCharge.create(placed, 1, 6, base, gain, cap)
	var abandoned := CombatMineCharge.create(placed, 1, 6, base, gain, cap)
	assert_null(early.detonate(CombatInstant.at_tick(3)))
	assert_eq(early.detonate(placed.after_ticks(1)).native_at_scale(0), 3)
	assert_null(early.detonate(placed.after_ticks(3)))
	assert_eq(developing.detonate(CombatInstant.at_tick(5)).native_at_scale(0), 7)
	assert_eq(saturated.detonate(placed.after_ticks(6)).native_at_scale(0), 12)
	assert_false(abandoned.expire(CombatInstant.at_tick(8)))
	assert_true(abandoned.expire(placed.after_ticks(6)))
	assert_eq(abandoned.end_reason, CombatMineCharge.End.EXPIRED)
	assert_null(abandoned.detonate(placed.after_ticks(6)))


func test_tether_follows_endpoints_suppresses_obstruction_and_reconnects_without_reset() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	source.resources[MANA] = Quantity.from_count(3)
	assert_true(kernel.add_actor(source))
	var geometry := RealmGeometry.new(REALM)
	for id: StringName in [&"first", &"last", TARGET]:
		assert_true(kernel.add_actor(_actor(id, 20)))
		var x := 0.0 if id == &"first" else (8.0 if id == &"last" else 4.0)
		assert_true(geometry.add_circle(id, 0, RealmSweep.Point.new(x, 0), 1.0, 1))
	var first := CombatTether.Endpoint.new()
	first.actor = &"first"
	var last := CombatTether.Endpoint.new()
	last.actor = &"last"
	var link := CombatTether.activate(kernel, _action(1), geometry, first, last, 8, 2, 20.0, 1)
	assert_not_null(link)
	if link == null:
		return
	var pulse := link.due_through(geometry, CombatInstant.at_tick(3), 0.0, 1, 2)
	assert_eq(pulse.contacts.size(), 3)
	for contact: RealmGeometry.Contact in pulse.contacts:
		assert_eq(link.admit(pulse, contact, 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(link.settle(pulse))
	var wave := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(wave.hits.size(), 3)
	assert_eq(wave.due.tick, 3)
	assert_true(geometry.commit_circle_pose(&"last", 0, RealmSweep.Point.new(8, 4)))
	var moving := link.due_through(geometry, CombatInstant.at_tick(5), 0.0, 1, 2)
	assert_eq(moving.contacts.size(), 2)
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(5, -2)
	edge.last = RealmSweep.Point.new(5, 6)
	assert_true(geometry.add_segment(&"wall", 0, edge, 2, false))
	assert_false(link.settle(moving))
	var blocked := link.due_through(geometry, CombatInstant.at_tick(5), 0.0, 1, 2)
	assert_not_null(blocked.blocker)
	assert_true(blocked.contacts.is_empty())
	assert_true(link.settle(blocked))
	assert_true(geometry.remove_mutable(&"wall", 0))
	assert_true(geometry.remove_mutable(&"last", 0))
	var anchor := CombatTether.Endpoint.new()
	anchor.anchor = RealmSweep.Point.new(8, 0)
	assert_true(link.reconnect(1, anchor, geometry, CombatInstant.at_tick(6)))
	assert_null(link.due_through(geometry, CombatInstant.at_tick(6), 0.0, 1, 2))
	var restored := link.due_through(geometry, CombatInstant.at_tick(7), 0.0, 1, 2)
	assert_eq(restored.contacts.size(), 2)
	assert_true(link.settle(restored))
	var last_tick := link.due_through(geometry, CombatInstant.at_tick(9), 0.0, 1, 2)
	assert_eq(last_tick.instant.kind, CombatDeliverySchedule.Kind.TICK)
	assert_true(link.settle(last_tick))
	var expiry := link.due_through(geometry, CombatInstant.at_tick(9), 0.0, 1, 2)
	assert_eq(expiry.instant.kind, CombatDeliverySchedule.Kind.NATURAL_EXPIRY)
	assert_true(link.settle(expiry))


func test_burn_refresh_and_stronger_transfer_preserve_continuous_intensity_and_phase() -> void:
	var kernel := CombatKernel.new()
	var ally := &"ally"
	for id: StringName in [SOURCE, ally, TARGET]:
		assert_true(kernel.add_actor(_actor(id, 100)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var ignition := _realized_hit(kernel, proof, SOURCE, &"fire", 1)
	var burn := CombatBurn.ignite(ignition.hits[0], ignition.due, Quantity.from_count(10), 8, 2,
		Quantity.from_count(25, 2), Quantity.from_count(2))
	assert_not_null(burn)
	if burn == null:
		return
	var teammate := _realized_hit(kernel, proof, ally, &"fire", 2)
	assert_false(burn.refresh(teammate.hits[0], teammate.due, 8))
	var refresh := _realized_hit(kernel, proof, SOURCE, &"fire", 3)
	var owner := refresh.hits[0].origin
	assert_true(burn.refresh(refresh.hits[0], refresh.due, 8))
	assert_false(burn.transfer(owner, refresh.due, 3, Quantity.from_count(9)))
	assert_false(burn.transfer(owner, refresh.due, 3, Quantity.from_count(10)))
	var first := burn.due_through(CombatInstant.at_tick(3))
	assert_eq(first.unmitigated.native_at_scale(0), 15)
	assert_true(burn.settle(first))
	var old_next := burn.due_through(CombatInstant.at_tick(5))
	assert_false(burn.transfer(owner, CombatInstant.at_tick(4), 3, Quantity.from_count(12)))
	assert_false(burn.transfer(owner, CombatInstant.at_tick(4), 3, Quantity.from_count(20)))
	assert_true(burn.active_for(owner, CombatInstant.at_tick(11)))
	assert_true(burn.transfer(owner, CombatInstant.at_tick(4), 3, Quantity.from_count(24)))
	assert_false(burn.settle(old_next))
	var second := burn.due_through(CombatInstant.at_tick(5))
	assert_eq(second.due.instant.tick, 5)
	assert_eq(second.unmitigated.native_at_scale(0), 24)
	assert_true(burn.settle(second))
	var last := burn.due_through(CombatInstant.at_tick(7))
	assert_eq(last.unmitigated.native_at_scale(0), 24)
	assert_true(burn.settle(last))
	var expiry := burn.due_through(CombatInstant.at_tick(7))
	assert_eq(expiry.due.kind, CombatDeliverySchedule.Kind.NATURAL_EXPIRY)
	assert_true(burn.settle(expiry))
	assert_false(burn.active_for(owner, CombatInstant.at_tick(8)))


func test_burn_transfer_uses_ramped_donor_without_multiplying_receiver_intensity() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(SOURCE, 100)))
	assert_true(kernel.add_actor(_actor(TARGET, 100)))
	var recipient := &"recipient"
	assert_true(kernel.add_actor(_actor(recipient, 100)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	assert_true(geometry.add_circle(recipient, 0, center, 1.0, 2))
	var donor_contact := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var receiver_contact := geometry.certify_circle_sweep(REALM, center, center, 0.0, 2).contacts[0]
	var ignition := _realized_hit(kernel, donor_contact, SOURCE, &"fire", 1)
	var base := Quantity.from_count(10)
	var growth := Quantity.from_count(25, 2)
	var cap := Quantity.from_count(2)
	var donor := CombatBurn.ignite(ignition.hits[0], ignition.due, base, 20, 4, growth, cap)
	var receiver_hit := _realized_hit(kernel, receiver_contact, SOURCE, &"fire", 4)
	var receiver := CombatBurn.ignite(receiver_hit.hits[0], receiver_hit.due, base, 20, 1, growth, cap)
	var first_due := CombatInstant.at_tick(5)
	var captured := donor.due_through(first_due)
	assert_eq(captured.unmitigated.native_at_scale(0), 20)
	var bounded := captured.unmitigated.multiply(Quantity.from_count(75, 2))
	assert_false(receiver.transfer(receiver_hit.hits[0].origin, receiver_hit.due, 2, base))
	assert_true(receiver.transfer(receiver_hit.hits[0].origin, receiver_hit.due, 2, bounded))
	var first := receiver.due_through(first_due)
	assert_eq(first.due.instant.tick, 5)
	assert_eq(first.unmitigated.native_at_scale(0), 15)
	assert_true(receiver.settle(first))
	var second := receiver.due_through(CombatInstant.at_tick(6))
	assert_eq(second.unmitigated.native_at_scale(0), 18)
	assert_true(receiver.settle(second))
	var expiry := receiver.due_through(CombatInstant.at_tick(6))
	assert_eq(expiry.due.kind, CombatDeliverySchedule.Kind.NATURAL_EXPIRY)
	assert_true(receiver.settle(expiry))
	assert_eq(donor.due_through(first_due).unmitigated.native_at_scale(0), 20)


func test_chill_tracks_owners_independently_with_strongest_effective_slow() -> void:
	var kernel := CombatKernel.new()
	var ally := &"ally"
	for id: StringName in [SOURCE, ally, TARGET]:
		assert_true(kernel.add_actor(_actor(id, 100)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var chill := CombatChillLedger.create(TARGET, 1)
	var first := _realized_hit(kernel, proof, SOURCE, &"frost", 1)
	var strong := _realized_hit(kernel, proof, ally, &"frost", 2)
	var again := _realized_hit(kernel, proof, ally, &"frost", 3)
	assert_true(chill.apply(first.hits[0], first.due, Quantity.from_count(4, 1), 8))
	assert_true(chill.apply(strong.hits[0], strong.due, Quantity.from_count(8, 1), 3))
	assert_true(chill.apply(again.hits[0], again.due, Quantity.from_count(1, 1), 2))
	assert_false(chill.apply(strong.hits[0], strong.due, Quantity.from_count(8, 1), 12))
	var resistance := Quantity.from_count(5, 1)
	assert_true(chill.owned_at(first.hits[0].origin, CombatInstant.at_tick(4)))
	assert_true(chill.owned_at(strong.hits[0].origin, CombatInstant.at_tick(4)))
	assert_eq(chill.strongest_at(CombatInstant.at_tick(4), resistance).native_at_scale(2), 40)
	assert_false(chill.owned_at(strong.hits[0].origin, CombatInstant.at_tick(6)))
	assert_eq(chill.strongest_at(CombatInstant.at_tick(6), resistance).native_at_scale(2), 20)


func test_chill_same_owner_uses_strongest_active_potency_and_its_own_duration() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(SOURCE, 100)))
	assert_true(kernel.add_actor(_actor(TARGET, 100)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	var proof := geometry.certify_circle_snapshot(REALM, center, 0.0, 1).contacts[0]
	var chill := CombatChillLedger.create(TARGET, 1)
	var weak := _realized_hit(kernel, proof, SOURCE, &"frost", 1)
	var strong := _realized_hit(kernel, proof, SOURCE, &"frost", 2)
	var reapplied := _realized_hit(kernel, proof, SOURCE, &"frost", 3)
	assert_true(chill.apply(weak.hits[0], weak.due, Quantity.from_count(2, 1), 6))
	assert_true(chill.apply(strong.hits[0], strong.due, Quantity.from_count(8, 1), 10))
	assert_true(chill.apply(reapplied.hits[0], reapplied.due, Quantity.from_count(2, 1), 14))
	var zero := Quantity.from_count(0)
	assert_eq(chill.strongest_at(CombatInstant.at_tick(4), zero).native_at_scale(2), 80)
	assert_eq(chill.strongest_at(CombatInstant.at_tick(12), zero).native_at_scale(2), 80)
	assert_eq(chill.strongest_at(CombatInstant.at_tick(13), zero).native_at_scale(2), 20)
	assert_eq(chill.strongest_at(CombatInstant.at_tick(18), zero).native_at_scale(2), 0)


func test_fracture_shared_cap_preserves_owned_stacks_and_strongest_exposure() -> void:
	var kernel := CombatKernel.new()
	var ally := &"ally"
	for id: StringName in [SOURCE, ally, TARGET]:
		assert_true(kernel.add_actor(_actor(id, 100)))
	var geometry := RealmGeometry.new(REALM)
	var point := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, point, 1.0, 1))
	var proof := geometry.certify_circle_sweep(REALM, point, point, 0.0, 1).contacts[0]
	var fracture := CombatFractureLedger.create(TARGET, 1, Quantity.from_count(5, 1))
	var authored := CombatFractureLedger.Rule.new()
	authored.capacity = 2
	authored.duration = 6
	authored.reduction_per_stack = Quantity.from_count(2, 1)
	authored.exposure_at_capacity = Quantity.from_count(1, 1)
	var first := _realized_hit(kernel, proof, SOURCE, &"weapon", 1)
	assert_true(fracture.apply(first.hits[0], first.due, authored))
	assert_false(fracture.apply(first.hits[0], first.due, authored))
	var second := _realized_hit(kernel, proof, SOURCE, &"weapon", 2)
	assert_true(fracture.apply(second.hits[0], second.due, authored))
	authored.exposure_at_capacity = Quantity.from_count(3, 1)
	var other := _realized_hit(kernel, proof, ally, &"weapon", 3)
	assert_true(fracture.apply(other.hits[0], other.due, authored))
	assert_eq(fracture.effective_at(other.due).reduction.native_at_scale(2), 50)
	assert_eq(fracture.effective_at(other.due).exposure.native_at_scale(2), 10)
	var fourth := _realized_hit(kernel, proof, ally, &"weapon", 4)
	assert_true(fracture.apply(fourth.hits[0], fourth.due, authored))
	var combined := fracture.effective_at(fourth.due)
	assert_eq(combined.reduction.native_at_scale(2), 50)
	assert_eq(combined.exposure.native_at_scale(2), 30)
	assert_eq(fracture.stacks_for(first.hits[0].origin, fourth.due), 2)
	assert_eq(fracture.stacks_for(other.hits[0].origin, fourth.due), 2)
	assert_eq(fracture.effective_at(CombatInstant.at_tick(9)).reduction.native_at_scale(2), 40)


func test_rune_gate_checks_equipped_ids_and_lightning_uses_the_correct_target_prestate() -> void:
	var bundle := load("res://src/catalog/starter_roster.tres") as CatalogBundle
	var catalog := bundle.compile()
	var gate := CombatRuneGate.create(catalog, SOURCE, [&"R01", &"R02"])
	assert_not_null(gate)
	assert_null(CombatRuneGate.create(catalog, SOURCE, [&"R01", &"R01"]))
	if gate == null:
		return
	var kernel := CombatKernel.new()
	var source := _actor(SOURCE, 20)
	var teammate := &"another_target"
	for index: int in 2:
		var rule := CombatFollowUp.new()
		rule.id = &"same_target" if index == 0 else &"other_target"
		rule.family = &"lightning"
		rule.cause = CombatFollowUp.Cause.PAID_HIT
		rule.resource = rule.id
		rule.cost = Quantity.from_count(1)
		rule.component = CombatAction.Component.new()
		rule.component.base = Quantity.from_count(1)
		if index == 1:
			rule.fresh_target = teammate
			rule.reach = 6.0
			rule.collision_mask = 1
		source.resources[rule.resource] = Quantity.from_count(1)
		source.follow_ups.append(rule)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(TARGET, 20)))
	assert_true(kernel.add_actor(_actor(teammate, 20)))
	var geometry := RealmGeometry.new(REALM)
	var center := RealmSweep.Point.new(0, 0)
	assert_true(geometry.add_circle(TARGET, 0, center, 1.0, 1))
	assert_true(geometry.add_circle(teammate, 0, RealmSweep.Point.new(4, 0), 1.0, 1))
	assert_true(geometry.add_circle(SOURCE, 0, RealmSweep.Point.new(-2, 0), 1.0, 1))
	assert_true(kernel.attach_geometry(geometry, 2))
	var proof := geometry.certify_circle_sweep(REALM, center, center, 0.0, 1).contacts[0]
	var wave := _realized_hit(kernel, proof, SOURCE, &"weapon", 1)
	assert_eq(wave.hits.size(), 3)
	if wave.hits.size() != 3:
		return
	var parent := wave.hits[0]
	assert_true(gate.allows(parent, &"R01", &"R02", true))
	assert_false(gate.allows(parent, &"R01", &"R03", true))
	assert_false(gate.allows(parent, &"R01", &"R02", false))
	assert_false(CombatRuneGate.create(catalog, &"teammate", [&"R01", &"R02"]).allows(parent, &"R01", &"R02", true))
	var prior := CombatBleedLedger.create(TARGET, 1).capture(wave.due)
	var next := CombatBleedLedger.create(teammate, 1).capture(wave.due)
	for index: int in [1, 2]:
		var child := wave.hits[index]
		assert_same(CombatRuneGate.lightning_prestate(parent, child, prior, next),
			prior if child.target == TARGET else next)


func _realized_hit(kernel: CombatKernel, contact: RealmGeometry.Contact, source: StringName,
		family: StringName, tick: int) -> CombatKernel.WaveResult:
	var action := _action(tick)
	action.source = source
	action.origin.owner = source
	action.family = family
	action.activation_costs.clear()
	var delivery := CombatDelivery.activate(kernel, action, REALM)
	assert_eq(delivery.admit(tick, contact, 1, true), CombatDelivery.Result.ADMITTED)
	assert_true(delivery.finish())
	return kernel.resolve_next(CombatInstant.at_tick(tick))


static func _actor(id: StringName, hp: int) -> CombatantState:
	var actor := CombatantState.new()
	actor.id = id
	actor.life = 1
	actor.owner = id
	actor.realm = REALM
	actor.hp = QuantityLayerLedger.Pool.new(Quantity.from_count(hp), QuantityErrorBounds.new())
	return actor


static func _action(tick: int) -> CombatAction:
	var action := CombatAction.new()
	action.source = SOURCE
	action.source_life = 1
	action.family = &"field"
	action.origin = CombatOrigin.new()
	action.origin.owner = SOURCE
	action.origin.activation = tick
	action.origin.committed_at = CombatInstant.at_tick(tick)
	var component := CombatAction.Component.new()
	component.base = Quantity.from_count(2)
	action.components = [component]
	action.activation_costs[MANA] = Quantity.from_count(3)
	return action
