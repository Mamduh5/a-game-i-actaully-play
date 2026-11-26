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
