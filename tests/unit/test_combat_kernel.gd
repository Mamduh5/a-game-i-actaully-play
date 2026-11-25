extends GutTest

const REALM := &"outer"
const CATEGORY := 1


func test_simultaneous_lethal_roots_keep_both_commitments_with_reversed_arrival() -> void:
	for reversed: bool in [false, true]:
		var kernel := CombatKernel.new()
		assert_true(kernel.add_actor(_actor(&"first", 10)))
		assert_true(kernel.add_actor(_actor(&"second", 10)))
		var first := kernel.commit(_attack(&"first", 1, 1, 10))
		var second := kernel.commit(_attack(&"second", 1, 1, 10))
		assert_ne(first, "")
		assert_ne(second, "")
		var order: Array[String] = [first, second]
		if reversed:
			order.reverse()
		for key: String in order:
			var target := &"second" if key == first else &"first"
			assert_eq(_admit(kernel, key, target, 2), CombatRootQueue.Result.ACCEPTED)
		assert_eq(kernel.resolve_next(CombatInstant.at_tick(2)).result, CombatKernel.Result.WAITING)
		var result := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(result.result, CombatKernel.Result.CLOSED)
		assert_eq(result.hits.size(), 2)
		if result.hits.size() != 2:
			continue
		assert_eq(result.hits[0].source, &"second")
		assert_eq(result.hits[1].source, &"first")
		assert_true(result.hits[0].eliminated)
		assert_true(result.hits[1].eliminated)
		assert_eq(_count(result.hits[0].components[0].hp_removed), 10)
		assert_false(kernel.actor_snapshot(&"first").is_alive())
		assert_false(kernel.actor_snapshot(&"second").is_alive())
		assert_eq(kernel.commit(_attack(&"first", 2, 4, 5)), "")
		assert_eq(kernel.resolve_next(CombatInstant.at_tick(4)).result, CombatKernel.Result.IDLE)


func test_commitment_captures_offense_and_later_uses_live_target_defense() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"archer", 50)))
	var target := _actor(&"target", 120)
	target.statuses[&"old_mark"] = 2
	assert_true(kernel.add_actor(target))
	var shot := _attack(&"archer", 1, 1, 50)
	var category := QuantityFormula.BonusCategory.new()
	category.values.append(Quantity.from_count(1))
	shot.components[0].categories.append(category)
	var key := kernel.commit(shot)
	assert_ne(key, "")
	assert_eq(kernel.commit(shot), "", "One logical activation can commit once.")
	var contact := _contact(&"target")
	assert_eq(kernel.admit_contact(key, 1, REALM, 3, contact, 2, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.admit_contact(key, 1, &"elsewhere", 3, contact, 1, true), CombatRootQueue.Result.INVALID)
	assert_eq(kernel.admit_contact(key, 1, REALM, 3, contact, 1, true), CombatRootQueue.Result.ACCEPTED)
	assert_eq(_admit(kernel, key, &"target", 8), CombatRootQueue.Result.REPEATED)
	category.values.clear()
	shot.components[0].base = Quantity.from_count(1)
	target.statuses[&"old_mark"] = 9
	contact.proof.earliest = 0.0
	contact.proof.latest = 0.0
	var live := CombatantState.Defense.new()
	live.rating = Quantity.from_count(100)
	assert_true(kernel.set_defense(&"target", 1, CombatAction.Damage.PHYSICAL, live))
	live.rating = Quantity.from_count(500)
	assert_true(kernel.finish_delivery(key))
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(3)).result, CombatKernel.Result.WAITING)

	var wave := kernel.resolve_next(CombatInstant.at_tick(4))
	assert_eq(wave.result, CombatKernel.Result.CLOSED)
	assert_eq(wave.hits.size(), 1)
	if wave.hits.size() != 1:
		return
	var hit := wave.hits[0]
	assert_eq(hit.family, &"fixture_attack")
	assert_eq(hit.before_statuses[&"old_mark"], 2)
	assert_eq(_count(hit.components[0].incoming), 50)
	assert_eq(_count(kernel.actor_snapshot(&"target").hp.amount), 70)


func test_finite_shared_barrier_has_one_depletion_and_one_elimination_by_precedence() -> void:
	for reversed: bool in [true, false]:
		var kernel := CombatKernel.new()
		assert_true(kernel.add_actor(_actor(&"a", 30)))
		assert_true(kernel.add_actor(_actor(&"z", 30)))
		var target := _actor(&"target", 35)
		target.barriers.append(_barrier(&"ward", 25, CombatAction.Damage.PHYSICAL))
		target.statuses[&"burning"] = 1
		assert_true(kernel.add_actor(target))
		var stronger := _attack(&"z", 1, 1, 40)
		stronger.origin.priority = 7
		var high := kernel.commit(stronger)
		var low := kernel.commit(_attack(&"a", 1, 1, 40))
		var order: Array[String] = [high, low]
		if reversed:
			order.reverse()
		for key: String in order:
			assert_eq(_admit(kernel, key, &"target", 2), CombatRootQueue.Result.ACCEPTED)
		var wave := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(wave.result, CombatKernel.Result.CLOSED)
		assert_eq(wave.hits.size(), 2)
		if wave.hits.size() != 2:
			continue
		var priority := wave.hits[0]
		var remainder := wave.hits[1]
		assert_eq(priority.source, &"z")
		assert_false(priority.eliminated)
		assert_eq(_count(priority.components[0].barriers[0].absorbed), 25)
		assert_true(priority.components[0].barriers[0].hostile_depletion)
		assert_eq(_count(priority.components[0].hostile_hp_removed), 15)
		assert_eq(_count(remainder.components[0].hostile_hp_removed), 20)
		assert_eq(_count(remainder.components[0].overkill), 20)
		assert_true(remainder.components[0].barriers.is_empty())
		assert_true(remainder.eliminated)
		assert_eq(remainder.source, &"a")
		assert_eq(remainder.before_statuses, priority.before_statuses)


func test_committed_later_delivery_survives_owner_death_and_cannot_hit_a_dead_target_again() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"archer", 5)))
	assert_true(kernel.add_actor(_actor(&"other", 16)))
	var in_flight := kernel.commit(_attack(&"archer", 1, 1, 16))
	var retaliation := kernel.commit(_attack(&"other", 1, 1, 5))
	assert_eq(_admit(kernel, retaliation, &"archer", 2), CombatRootQueue.Result.ACCEPTED)
	assert_true(kernel.resolve_next(CombatInstant.at_tick(3)).hits[0].eliminated)
	assert_eq(kernel.commit(_attack(&"archer", 2, 4, 30)), "")
	assert_eq(_admit(kernel, in_flight, &"other", 4), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.admit_contact(in_flight, 2, REALM, 5, _contact(&"other"), 1, true),
		CombatRootQueue.Result.ACCEPTED)
	var closed := kernel.resolve_next(CombatInstant.at_tick(5))
	assert_true(closed.hits[0].eliminated)
	assert_eq(closed.hits[0].source_life, 1)
	var late := kernel.resolve_next(CombatInstant.at_tick(6))
	assert_false(late.hits[0].accepted)
	assert_false(late.hits[0].eliminated)
	assert_true(late.hits[0].components.is_empty())


func test_same_kind_matching_rate_carries_across_contributors_until_exact_lethality() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"a", 10)))
	assert_true(kernel.add_actor(_actor(&"b", 10)))
	var target := _actor(&"target", 1)
	target.physical.rating = Quantity.from_count(200)
	assert_true(kernel.add_actor(target))
	var micros: Array[int] = []
	for index: int in 3:
		var source := &"b" if index == 1 else &"a"
		var tick := 2 * index + 1
		var key := kernel.commit(_attack(source, index + 1, tick, 1))
		assert_eq(_admit(kernel, key, &"target", tick), CombatRootQueue.Result.ACCEPTED)
		var wave := kernel.resolve_next(CombatInstant.at_tick(tick + 1))
		assert_eq(wave.result, CombatKernel.Result.CLOSED)
		if wave.hits.is_empty():
			return
		var hit := wave.hits[0]
		var micro: int = hit.components[0].hp_removed.native_at_scale(6)
		micros.append(micro)
		assert_eq(hit.eliminated, index == 2)
	assert_eq(micros, [333333, 333334, 333333])
	assert_false(kernel.actor_snapshot(&"target").is_alive())


func test_component_compatibility_distinguishes_hit_rejection_from_damage_immunity() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(&"source", 10)
	source.resources[&"charge"] = Quantity.from_count(5)
	assert_true(kernel.add_actor(source))
	var target := _actor(&"target", 30)
	target.barriers.append(_barrier(&"physical", 10, CombatAction.Damage.PHYSICAL))
	target.physical.immune = true
	assert_true(kernel.add_actor(target))
	var blocked := _actor(&"blocked", 30)
	blocked.prevents_hit = true
	assert_true(kernel.add_actor(blocked))
	var mixed := _attack(&"source", 1, 1, 11)
	mixed.activation_costs[&"charge"] = Quantity.from_count(2)
	var magic := CombatAction.Component.new()
	magic.kind = CombatAction.Damage.MAGICAL
	magic.base = Quantity.from_count(7)
	mixed.components.append(magic)
	var key := kernel.commit(mixed)
	assert_eq(_admit(kernel, key, &"target", 2), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.admit_contact(key, 2, REALM, 2, _contact(&"blocked"), 1, false), CombatRootQueue.Result.ACCEPTED)
	var wave := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(wave.result, CombatKernel.Result.CLOSED)
	assert_eq(wave.hits.size(), 2)
	if wave.hits.size() != 2:
		return
	assert_false(wave.hits[0].accepted)
	assert_true(wave.hits[0].components.is_empty())
	assert_true(wave.hits[1].accepted)
	assert_eq(_count(wave.hits[1].components[0].incoming), 0)
	assert_eq(_count(wave.hits[1].components[1].hp_removed), 7)
	assert_eq(_count(kernel.actor_snapshot(&"target").barriers[0].pool.amount), 10)
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"charge"]), 3)


func test_failed_payment_preserves_all_pools_and_committed_miss_keeps_its_cost_and_cooldown() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(&"source", 20)
	source.resources[&"mana"] = Quantity.from_count(7)
	source.resources[&"charge"] = Quantity.from_count(1)
	assert_true(kernel.add_actor(source))
	var action := _attack(&"source", 1, 2, 5)
	action.activation_costs = {&"mana": Quantity.from_count(4), &"charge": Quantity.from_count(2)}
	action.cooldown = &"fixture_cast"
	action.cooldown_ticks = 5
	assert_eq(kernel.commit(action), "")
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"mana"]), 7)
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"charge"]), 1)
	action.activation_costs[&"charge"] = Quantity.from_count(1)
	var committed := kernel.commit(action)
	assert_ne(committed, "")
	assert_true(kernel.finish_delivery(committed))
	assert_eq(kernel.pending_count(), 0)
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"mana"]), 3)
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"charge"]), 0)

	var retry := _attack(&"source", 2, 6, 3)
	retry.cooldown = action.cooldown
	retry.cooldown_ticks = 5
	retry.activation_costs[&"mana"] = Quantity.from_count(1)
	assert_eq(kernel.commit(retry), "")
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"mana"]), 3)
	retry.origin.committed_at = CombatInstant.at_tick(7)
	assert_ne(kernel.commit(retry), "")
	assert_eq(kernel.commit(retry), "")
	assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"mana"]), 2)


func test_numeric_resource_failure_releases_neither_partial_debits_nor_receipts() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"source", 20)))
	assert_true(kernel.add_actor(_actor(&"a_first", 10)))
	assert_true(kernel.add_actor(_actor(&"z_last", 10)))
	var regular := kernel.commit(_attack(&"source", 1, 1, 5))
	var oversized := _attack(&"source", 2, 1, 1)
	oversized.components[0].base = Quantity.from_canonical(false, 0, "9".repeat(Quantity.MAX_DIGITS))
	assert_not_null(oversized.components[0].base)
	var wide := kernel.commit(oversized)
	assert_eq(_admit(kernel, regular, &"a_first", 2), CombatRootQueue.Result.ACCEPTED)
	assert_eq(_admit(kernel, wide, &"z_last", 2), CombatRootQueue.Result.ACCEPTED)
	var wave := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(wave.result, CombatKernel.Result.INTERRUPTED)
	assert_eq(wave.fault, &"numeric_posting")
	assert_true(wave.hits.is_empty())
	assert_eq(kernel.pending_count(), 2)
	assert_eq(_count(kernel.actor_snapshot(&"a_first").hp.amount), 10)
	assert_eq(_count(kernel.actor_snapshot(&"z_last").hp.amount), 10)
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(4)).result, CombatKernel.Result.INTERRUPTED)


func test_lethal_reaction_finishes_before_terminal_and_future_delivery_cannot_hold_a_wipe() -> void:
	for immediate: bool in [true, false]:
		var kernel := CombatKernel.new()
		var hero := _actor(&"hero", 3)
		if immediate:
			hero.follow_ups.append(_reaction(&"reprisal", CombatFollowUp.Cause.HOSTILE_HP, 4))
		assert_true(kernel.add_actor(hero))
		assert_true(kernel.add_actor(_actor(&"creator", 4)))
		assert_true(kernel.configure_terminal(&"creator", [&"hero"]))
		var later := kernel.commit(_attack(&"hero", 1, 1, 4))
		var lethal := kernel.commit(_attack(&"creator", 1, 1, 3))
		assert_eq(_admit(kernel, later, &"creator", 4), CombatRootQueue.Result.ACCEPTED)
		assert_eq(_admit(kernel, lethal, &"hero", 2), CombatRootQueue.Result.ACCEPTED)
		var result := kernel.resolve_next(CombatInstant.at_tick(3), 1)
		if immediate:
			assert_eq(result.result, CombatKernel.Result.YIELDED)
			assert_true(result.hits.is_empty())
			assert_true(kernel.actor_snapshot(&"hero").is_alive())
			assert_false(kernel.finish_delivery(later))
			result = kernel.resolve_next(CombatInstant.at_tick(3), 1)
		assert_eq(result.result, CombatKernel.Result.CLOSED)
		assert_eq(result.terminal, CombatKernel.Terminal.VICTORY if immediate else CombatKernel.Terminal.DEFEAT)
		assert_eq(result.hits.size(), 2 if immediate else 1)
		if immediate and result.hits.size() == 2:
			assert_eq(result.hits[1].parent, result.hits[0].event)
			assert_eq(result.hits[1].source, &"hero")
			assert_eq(result.hits[1].reaction, &"reprisal")
		assert_false(kernel.actor_snapshot(&"hero").is_alive())
		assert_eq(kernel.pending_count(), 0)
		assert_eq(kernel.resolve_next(CombatInstant.at_tick(6)).result, CombatKernel.Result.IDLE)


func test_hostile_layer_depletion_creates_one_separate_descendant_even_on_lethal() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 3)
	hero.barriers.append(_barrier(&"fortified", 2, CombatAction.Damage.PHYSICAL))
	var release := _reaction(&"release", CombatFollowUp.Cause.HOSTILE_LAYER, 1)
	release.layer = &"fortified"
	hero.follow_ups.append(release)
	assert_true(kernel.add_actor(hero))
	assert_true(kernel.add_actor(_actor(&"enemy", 9)))
	var enemy := kernel.commit(_attack(&"enemy", 1, 1, 5))
	assert_eq(_admit(kernel, enemy, &"hero", 2), CombatRootQueue.Result.ACCEPTED)
	var result := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(result.hits.size(), 2)
	if result.hits.size() == 2:
		assert_true(result.hits[0].eliminated)
		assert_eq(result.hits[1].reaction, &"release")
		assert_eq(result.hits[1].source, &"hero")
	assert_eq(_count(kernel.actor_snapshot(&"enemy").hp.amount), 8)


func test_finite_immediate_chain_keeps_every_posting_under_different_slices() -> void:
	for budget: int in [1, 11, 180]:
		var kernel := CombatKernel.new()
		var source := _actor(&"source", 5)
		source.resources[&"chain"] = Quantity.from_count(96)
		var paid := _reaction(&"paid", CombatFollowUp.Cause.PAID_HIT, 0)
		paid.resource = &"chain"
		paid.cost = Quantity.from_count(1)
		source.follow_ups.append(paid)
		assert_true(kernel.add_actor(source))
		assert_true(kernel.add_actor(_actor(&"target", 5)))
		var key := kernel.commit(_attack(&"source", 1, 1, 0))
		assert_eq(_admit(kernel, key, &"target", 2), CombatRootQueue.Result.ACCEPTED)
		var result := kernel.resolve_next(CombatInstant.at_tick(3), budget)
		var calls := 1
		while result.result == CombatKernel.Result.YIELDED and calls < 100:
			assert_true(result.hits.is_empty())
			assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"chain"]), 96)
			result = kernel.resolve_next(CombatInstant.at_tick(3), budget)
			calls += 1
		assert_eq(result.result, CombatKernel.Result.CLOSED)
		assert_eq(result.waves, 97)
		assert_eq(result.hits.size(), 97)
		assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"chain"]), 0)
		for index: int in result.hits.size():
			assert_eq(result.hits[index].parent, index)


func test_status_claims_displacement_and_child_preparent_view_follow_the_group_order() -> void:
	var kernel := CombatKernel.new()
	var actor := _actor(&"source", 4)
	actor.max_hp = Quantity.from_count(6)
	actor.resources[&"charge"] = Quantity.from_count(1)
	var paid := _reaction(&"lightning", CombatFollowUp.Cause.PAID_HIT, 1)
	paid.resource = &"charge"
	paid.cost = Quantity.from_count(1)
	paid.inherit_parent_statuses = true
	paid.consume_status = &"old"
	actor.follow_ups.append(paid)
	assert_true(kernel.add_actor(actor))
	var target := _actor(&"target", 20)
	target.statuses[&"old"] = 1
	assert_true(kernel.add_actor(target))
	var geometry := _geometry_with_wall(&"target")
	assert_true(kernel.attach_geometry(geometry, 2))
	var action := _attack(&"source", 1, 1, 1)
	action.consume_status = &"old"
	action.add_status = &"new"
	action.status_units = 1
	action.displacement = RealmSweep.Point.new(10.0, 0.0)
	action.restore_source = Quantity.from_count(8)
	var key := kernel.commit(action)
	assert_eq(_admit(kernel, key, &"target", 2), CombatRootQueue.Result.ACCEPTED)
	var result := kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.result, CombatKernel.Result.YIELDED)
	assert_eq(geometry.circle_center(&"target", 0).x, 0.0)
	assert_eq(_count(kernel.actor_snapshot(&"source").hp.amount), 4)
	result = kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.result, CombatKernel.Result.CLOSED)
	assert_eq(result.hits.size(), 2)
	if result.hits.size() == 2:
		assert_true(result.hits[0].status_consumed)
		assert_eq(result.hits[0].displacement.stopped_by.size(), 1)
		assert_eq(result.hits[1].before_statuses, {&"old": 1})
		assert_false(result.hits[1].status_consumed, "The inherited observation does not restore a spent stack")
	assert_eq(kernel.actor_snapshot(&"target").statuses, {&"new": 1})
	assert_almost_eq(geometry.circle_center(&"target", 0).x, 4.0, 0.000001)
	assert_eq(_count(kernel.actor_snapshot(&"source").hp.amount), 6)


func test_zero_progress_cycle_rejects_the_group_without_publishing_its_geometry_or_hp() -> void:
	var kernel := CombatKernel.new()
	for id: StringName in [&"a", &"b"]:
		var actor := _actor(id, 10)
		actor.max_hp = Quantity.from_count(10)
		var mirror := _reaction(&"mirror", CombatFollowUp.Cause.HOSTILE_HP, 1)
		mirror.restore_source = Quantity.from_count(1)
		actor.follow_ups.append(mirror)
		assert_true(kernel.add_actor(actor))
	var geometry := _geometry_with_wall(&"b")
	assert_true(kernel.attach_geometry(geometry, 2))
	var action := _attack(&"a", 1, 1, 1)
	action.displacement = RealmSweep.Point.new(10.0, 0.0)
	assert_eq(_admit(kernel, kernel.commit(action), &"b", 2), CombatRootQueue.Result.ACCEPTED)
	var result := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(result.result, CombatKernel.Result.INTERRUPTED)
	assert_eq(result.fault, &"causal_cycle")
	assert_eq(result.fault_wave, 3)
	assert_true(result.hits.is_empty())
	assert_eq(kernel.pending_count(), 1)
	assert_eq(_count(kernel.actor_snapshot(&"a").hp.amount), 10)
	assert_eq(_count(kernel.actor_snapshot(&"b").hp.amount), 10)
	assert_eq(geometry.circle_center(&"b", 0).x, 0.0)


func test_paid_and_free_reactions_drain_in_two_actor_and_three_actor_chains() -> void:
	for budget: int in [1, 11, 180]:
		for size: int in [2, 3]:
			var kernel := _reaction_ring(size, 5)
			var result := kernel.resolve_next(CombatInstant.at_tick(3), budget)
			var slices := 1
			while result.result == CombatKernel.Result.YIELDED and slices < 20:
				assert_eq(_count(kernel.actor_snapshot(&"a").resources[&"charge"]), 5)
				assert_true(result.hits.is_empty())
				result = kernel.resolve_next(CombatInstant.at_tick(3), budget)
				slices += 1
			assert_eq(result.result, CombatKernel.Result.CLOSED)
			assert_eq(result.waves, 12 if size == 2 else 16)
			assert_eq(result.hits.size(), result.waves)
			assert_eq(_count(kernel.actor_snapshot(&"a").resources[&"charge"]), 0)
			assert_eq(_count(kernel.actor_snapshot(&"a").hp.amount), 9)
			assert_eq(_count(kernel.actor_snapshot(&"b").hp.amount), 10)
			if size == 3:
				assert_eq(_count(kernel.actor_snapshot(&"c").hp.amount), 10)


func test_free_three_actor_ring_interrupts_without_publishing() -> void:
	var kernel := _reaction_ring(3, 0)
	var result := kernel.resolve_next(CombatInstant.at_tick(3), 3)
	assert_eq(result.result, CombatKernel.Result.YIELDED)
	result = kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.result, CombatKernel.Result.INTERRUPTED)
	assert_eq(result.fault, &"causal_cycle")
	assert_eq(result.fault_wave, 4)
	assert_true(result.hits.is_empty())
	assert_eq(kernel.pending_count(), 1)
	for id: StringName in [&"a", &"b", &"c"]:
		assert_eq(_count(kernel.actor_snapshot(id).hp.amount), 10)


func test_committed_hit_preserves_defender_fresh_contact_after_source_life_or_realm_changes() -> void:
	for change: String in ["same", "life", "realm", "removed"]:
		var kernel := CombatKernel.new()
		var source := _actor(&"source", 10)
		source.resources[&"charge"] = Quantity.from_count(1)
		var bonus := _reaction(&"source_bonus", CombatFollowUp.Cause.PAID_HIT, 1)
		bonus.resource = &"charge"
		bonus.cost = Quantity.from_count(1)
		source.follow_ups.append(bonus)
		var defender := _actor(&"defender", 10)
		defender.follow_ups.append(_reaction(&"counterpart", CombatFollowUp.Cause.HOSTILE_HP, 1))
		var nearby := _reaction(&"nearby", CombatFollowUp.Cause.HOSTILE_HP, 2)
		nearby.fresh_target = &"witness"
		nearby.reach = 4.0
		nearby.collision_mask = CATEGORY
		defender.follow_ups.append(nearby)
		assert_true(kernel.add_actor(source))
		assert_true(kernel.add_actor(defender))
		assert_true(kernel.add_actor(_actor(&"witness", 10)))
		var geometry := RealmGeometry.new(REALM)
		assert_true(geometry.add_circle(&"defender", 0, RealmSweep.Point.new(0, 0), 1.0, CATEGORY))
		assert_true(geometry.add_circle(&"witness", 0, RealmSweep.Point.new(3, 0), 1.0, CATEGORY))
		assert_true(kernel.attach_geometry(geometry, 2))
		assert_eq(_admit(kernel, kernel.commit(_attack(&"source", 1, 1, 1)), &"defender", 2), CombatRootQueue.Result.ACCEPTED)
		# Fixture for the future lifecycle/transfer owner. The committed hit
		# still carries its original source life and realm.
		match change:
			"life": kernel._actors[&"source"].life += 1
			"realm": kernel._actors[&"source"].realm = &"elsewhere"
			"removed": kernel._actors.erase(&"source")
		var result := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(result.result, CombatKernel.Result.CLOSED)
		assert_eq(result.hits.size(), 6 if change == "same" else 2, change)
		assert_eq(_count(kernel.actor_snapshot(&"witness").hp.amount), 6 if change == "same" else 8, change)
		if change != "removed":
			assert_eq(_count(kernel.actor_snapshot(&"source").hp.amount), 8 if change == "same" else 10, change)
			assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"charge"]), 0 if change == "same" else 1, change)


func test_stage_six_barrier_protects_the_child_and_cannot_absorb_its_originating_wave() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"a", 10)))
	var opponent := _actor(&"b", 10)
	opponent.follow_ups.append(_reaction(&"retaliate", CombatFollowUp.Cause.HOSTILE_HP, 5))
	assert_true(kernel.add_actor(opponent))
	var first := _attack(&"a", 1, 1, 1)
	first.barrier_for_source = CombatAction.BarrierGrant.new()
	first.barrier_for_source.id = &"ward"
	first.barrier_for_source.mask = CombatAction.Damage.PHYSICAL
	first.barrier_for_source.capacity = Quantity.from_count(4)
	assert_eq(_admit(kernel, kernel.commit(first), &"b", 2), CombatRootQueue.Result.ACCEPTED)
	assert_eq(_admit(kernel, kernel.commit(_attack(&"b", 1, 1, 2)), &"a", 2), CombatRootQueue.Result.ACCEPTED)
	var result := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(result.hits.size(), 3)
	if result.hits.size() == 3:
		assert_true(result.hits[0].components[0].barriers.is_empty())
		assert_eq(_count(result.hits[0].components[0].hp_removed), 2)
		assert_eq(result.hits[1].granted_barrier, &"ward")
		assert_eq(_count(result.hits[2].components[0].barriers[0].absorbed), 4)
		assert_eq(_count(result.hits[2].components[0].hp_removed), 1)
	assert_eq(_count(kernel.actor_snapshot(&"a").hp.amount), 7)


func test_solid_impact_descendant_certifies_a_fresh_target_from_the_draft_pose() -> void:
	for x: float in [5.0, 9.0]:
		var kernel := CombatKernel.new()
		var source := _actor(&"source", 10)
		var target := _actor(&"target", 10)
		var collision := _reaction(&"impact", CombatFollowUp.Cause.SOLID_IMPACT, 2)
		collision.fresh_target = &"nearby"
		collision.reach = 2.0
		collision.collision_mask = 4
		source.follow_ups.append(collision)
		assert_true(kernel.add_actor(source))
		assert_true(kernel.add_actor(target))
		assert_true(kernel.add_actor(_actor(&"nearby", 10)))
		var geometry := _geometry_with_wall(&"target")
		assert_true(geometry.add_circle(&"nearby", 0, RealmSweep.Point.new(x, 0), 1.0, 4))
		assert_true(kernel.attach_geometry(geometry, 2))
		var action := _attack(&"source", 1, 1, 1)
		action.displacement = RealmSweep.Point.new(10.0, 0.0)
		assert_eq(_admit(kernel, kernel.commit(action), &"target", 2), CombatRootQueue.Result.ACCEPTED)
		var result := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(result.result, CombatKernel.Result.CLOSED)
		assert_eq(result.hits.size(), 2 if x == 5.0 else 1)
		assert_eq(_count(kernel.actor_snapshot(&"nearby").hp.amount), 8 if x == 5.0 else 10)


func test_finite_reactions_contend_by_authored_priority_across_same_actor_hits() -> void:
	for reverse: bool in [false, true]:
		var kernel := CombatKernel.new()
		var source := _actor(&"source", 10)
		source.resources[&"charge"] = Quantity.from_count(1)
		for index: int in 2:
			var rule := _reaction(StringName("rule_%d" % index), CombatFollowUp.Cause.PAID_HIT, index + 2)
			rule.priority = index
			rule.resource = &"charge"
			rule.cost = Quantity.from_count(1)
			source.follow_ups.append(rule)
		if reverse:
			source.follow_ups.reverse()
		assert_true(kernel.add_actor(source))
		assert_true(kernel.add_actor(_actor(&"target", 10)))
		assert_eq(_admit(kernel, kernel.commit(_attack(&"source", 1, 1, 1)), &"target", 2), CombatRootQueue.Result.ACCEPTED)
		var result := kernel.resolve_next(CombatInstant.at_tick(3))
		assert_eq(result.hits.size(), 2)
		if result.hits.size() == 2:
			assert_eq(result.hits[1].reaction, &"rule_1")
		assert_eq(_count(kernel.actor_snapshot(&"source").resources[&"charge"]), 0)


func test_elimination_reaction_publishes_distinct_entitlements_at_the_closed_boundary() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(&"source", 10)
	var bloom := _reaction(&"bloom", CombatFollowUp.Cause.KILL, 2)
	bloom.fresh_target = &"second"
	bloom.reach = 4.0
	bloom.collision_mask = CATEGORY
	source.follow_ups.append(bloom)
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(&"first", 1)))
	assert_true(kernel.add_actor(_actor(&"second", 2)))
	var geometry := RealmGeometry.new(REALM)
	assert_true(geometry.add_circle(&"first", 0, RealmSweep.Point.new(0.0, 0.0), 1.0, CATEGORY))
	assert_true(geometry.add_circle(&"second", 0, RealmSweep.Point.new(3.0, 0.0), 1.0, CATEGORY))
	assert_true(kernel.attach_geometry(geometry, 2))
	assert_eq(_admit(kernel, kernel.commit(_attack(&"source", 1, 1, 1)), &"first", 2), CombatRootQueue.Result.ACCEPTED)
	var result := kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.result, CombatKernel.Result.YIELDED)
	assert_true(result.eliminations.is_empty())
	result = kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.eliminations.size(), 2)
	if result.eliminations.size() == 2:
		assert_eq(result.eliminations[0].target, &"first")
		assert_eq(result.eliminations[1].target, &"second")
		assert_eq(result.eliminations[1].origin.owner, &"source")
		assert_eq(result.eliminations[1].parent, result.eliminations[0].event)


func test_contention_on_geometry_during_a_yield_preserves_the_last_committed_combat_state() -> void:
	var kernel := CombatKernel.new()
	var attacker := _actor(&"a", 10)
	attacker.resources[&"charge"] = Quantity.from_count(1)
	var paid := _reaction(&"paid", CombatFollowUp.Cause.PAID_HIT, 1)
	paid.resource = &"charge"
	paid.cost = Quantity.from_count(1)
	attacker.follow_ups.append(paid)
	assert_true(kernel.add_actor(attacker))
	assert_true(kernel.add_actor(_actor(&"b", 10)))
	var geometry := _geometry_with_wall(&"b")
	assert_true(kernel.attach_geometry(geometry, 2))
	var action := _attack(&"a", 1, 1, 2)
	action.displacement = RealmSweep.Point.new(10.0, 0.0)
	assert_eq(_admit(kernel, kernel.commit(action), &"b", 2), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(3), 1).result, CombatKernel.Result.YIELDED)
	assert_true(geometry.commit_circle_pose(&"b", 0, RealmSweep.Point.new(-2.0, 0.0)))
	var result := kernel.resolve_next(CombatInstant.at_tick(3), 1)
	assert_eq(result.result, CombatKernel.Result.INTERRUPTED)
	assert_eq(result.fault, &"geometry_changed")
	assert_eq(kernel.pending_count(), 1)
	assert_eq(_count(kernel.actor_snapshot(&"b").hp.amount), 10)
	assert_eq(_count(kernel.actor_snapshot(&"a").resources[&"charge"]), 1)
	assert_eq(geometry.circle_center(&"b", 0).x, -2.0)


func _reaction_ring(size: int, charge: int) -> CombatKernel:
	var kernel := CombatKernel.new()
	var ids: Array[StringName] = [&"a", &"b", &"c"]
	var geometry := RealmGeometry.new(REALM)
	for index: int in size:
		var actor := _actor(ids[index], 10)
		actor.max_hp = Quantity.from_count(10)
		var mirror := _reaction(&"mirror", CombatFollowUp.Cause.HOSTILE_HP, 1)
		mirror.restore_source = Quantity.from_count(1)
		if index == 0 and charge > 0:
			mirror.resource = &"charge"
			mirror.cost = Quantity.from_count(1)
			actor.resources[&"charge"] = Quantity.from_count(charge)
		if size == 3:
			mirror.fresh_target = ids[(index + 1) % size]
			mirror.reach = 6.0
			mirror.collision_mask = CATEGORY
			assert_true(geometry.add_circle(actor.id, 0, RealmSweep.Point.new(index * 2.0, 0), 0.5, CATEGORY))
		actor.follow_ups.append(mirror)
		assert_true(kernel.add_actor(actor))
	if size == 3:
		assert_true(kernel.attach_geometry(geometry, 2))
	var start := _attack(&"a" if size == 2 else &"c", 1, 1, 1)
	assert_eq(_admit(kernel, kernel.commit(start), &"b" if size == 2 else &"a", 2), CombatRootQueue.Result.ACCEPTED)
	return kernel


static func _reaction(id: StringName, cause: CombatFollowUp.Cause, damage: int) -> CombatFollowUp:
	var rule := CombatFollowUp.new()
	rule.id = id
	rule.family = id
	rule.cause = cause
	rule.component = CombatAction.Component.new()
	rule.component.base = Quantity.from_count(damage)
	return rule


static func _geometry_with_wall(target: StringName) -> RealmGeometry:
	var geometry := RealmGeometry.new(REALM)
	geometry.add_circle(target, 0, RealmSweep.Point.new(0, 0), 1.0, CATEGORY)
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(5, -10)
	edge.last = RealmSweep.Point.new(5, 10)
	geometry.add_segment(&"wall", 0, edge, 2, true)
	return geometry


static func _actor(id: StringName, hp: int) -> CombatantState:
	var actor := CombatantState.new()
	actor.id = id
	actor.owner = id
	actor.realm = REALM
	actor.life = 1
	actor.hp = QuantityLayerLedger.Pool.new(Quantity.from_count(hp), QuantityErrorBounds.new())
	return actor


static func _attack(id: StringName, sequence: int, tick: int, damage: int) -> CombatAction:
	var origin := CombatOrigin.new()
	origin.owner = id
	origin.activation = sequence
	origin.committed_at = CombatInstant.at_tick(tick)
	var action := CombatAction.new()
	action.source = id
	action.source_life = 1
	action.family = &"fixture_attack"
	action.origin = origin
	var component := CombatAction.Component.new()
	component.base = Quantity.from_count(damage)
	action.components.append(component)
	return action


static func _barrier(id: StringName, capacity: int, mask: int) -> CombatantState.Barrier:
	var barrier := CombatantState.Barrier.new()
	barrier.id = id
	barrier.mask = mask
	barrier.pool = QuantityLayerLedger.Pool.new(Quantity.from_count(capacity), QuantityErrorBounds.new())
	return barrier


static func _contact(id: StringName) -> RealmGeometry.Contact:
	var geometry := RealmGeometry.new(REALM)
	geometry.add_circle(id, 0, RealmSweep.Point.new(0, 0), 2.0, CATEGORY)
	var sweep := geometry.certify_circle_sweep(REALM, RealmSweep.Point.new(-8, 0), RealmSweep.Point.new(8, 0), 0.0, CATEGORY)
	return sweep.contacts[0]


static func _admit(kernel: CombatKernel, key: String, id: StringName, tick: int) -> CombatRootQueue.Result:
	return kernel.admit_contact(key, 1, REALM, tick, _contact(id), 1, true)


static func _count(quantity: Quantity) -> int:
	return quantity.native_at_scale(0)
