extends GutTest

const REALM := &"outer"
const CATEGORY := 1

class DeadlineClock:
	var elapsed: int
	var samples_before_expiry := -1

	func sample() -> int:
		if samples_before_expiry == 0:
			elapsed = OrdinaryCurrency.MAX_AGE_USEC
		elif samples_before_expiry > 0:
			samples_before_expiry -= 1
		return elapsed


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


func test_ordinary_deadline_parks_a_causal_cursor_and_a_completed_unpublished_wave() -> void:
	if not OS.has_feature("windows"):
		return
	var key := Crypto.new().generate_rsa(2048)
	for has_child: bool in [false, true]:
		var setup := RunSetup.new()
		setup.run_id = &"storage-cursor"
		setup.authority_id = &"hero"
		setup.initial_realms = {&"hero": REALM}
		setup.rules_revision = &"V42.6/R1"
		setup.catalog_revision = &"fixture"
		setup.challenge_id = &"normal"
		setup.epoch = 1
		var authority := RunAuthority.new()
		assert_true(authority.start(setup, setup.authority_id))
		var scratch := DirAccess.create_temp("agip-ordinary-cursor")
		var store := ProfileStore.new()
		assert_eq(store.open("hero", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		var paired := ProfileGrant.Binding.new()
		paired.run = String(setup.run_id)
		paired.rules = String(setup.rules_revision)
		paired.catalog = String(setup.catalog_revision)
		paired.recipient = "hero"
		paired.issuer = key
		paired.recipient_key = key
		var clock := DeadlineClock.new()
		var earnings := OrdinaryCurrency.begin(store, paired, key, "currency/permanent", clock.sample)
		assert_true(authority.attach_ordinary_currency(earnings))
		assert_eq(earnings.accrue("older-enemy", Quantity.from_count(7)), OrdinaryCurrency.Eligibility.QUEUED)
		assert_false(earnings.dispatch(true).is_empty())
		var kernel := CombatKernel.new()
		var hero := _actor(&"hero", 10)
		if has_child:
			hero.resources[&"charge"] = Quantity.from_count(1)
			var rule := _reaction(&"paid", CombatFollowUp.Cause.PAID_HIT, 1)
			rule.resource = &"charge"
			rule.cost = Quantity.from_count(1)
			hero.follow_ups.append(rule)
		assert_true(kernel.add_actor(hero))
		assert_true(kernel.add_actor(_actor(&"target", 10)))
		assert_eq(_admit(kernel, kernel.commit(_attack(&"hero", 1, 1, 1)), &"target", 2),
			CombatRootQueue.Result.ACCEPTED)
		var through := CombatInstant.at_tick(3)
		clock.elapsed = OrdinaryCurrency.MAX_AGE_USEC - 1
		if has_child:
			assert_eq(kernel.resolve_next(through, 1, authority).result, CombatKernel.Result.YIELDED)
			clock.elapsed += 1
		else:
			# The deadline expires after the root wave and before its publication.
			clock.samples_before_expiry = 2
		var parked := kernel.resolve_next(through, 1, authority)
		assert_eq(parked.result, CombatKernel.Result.STORAGE_WAIT)
		assert_true(parked.hits.is_empty())
		assert_eq(_count(kernel.actor_snapshot(&"target").hp.amount), 10)
		assert_true(authority.flush_ordinary_currency())
		var resumed := kernel.resolve_next(through, 1, authority)
		assert_eq(resumed.result, CombatKernel.Result.CLOSED)
		assert_eq(resumed.waves, 2 if has_child else 1)
		assert_eq(resumed.hits.size(), 2 if has_child else 1)
		assert_eq(_count(kernel.actor_snapshot(&"target").hp.amount), 8 if has_child else 9)
		assert_eq(store.balance("currency/permanent").native_at_scale(0), 7)
		assert_true(store.close())


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


func test_max_hp_preserves_absolute_health_and_clamping_issues_no_hit() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 80)
	hero.max_hp = Quantity.from_count(100)
	assert_true(kernel.add_actor(hero))
	assert_true(kernel.add_actor(_actor(&"dead", 0)))
	assert_true(kernel.change_max_hp(&"hero", 1, Quantity.from_count(120)))
	assert_eq(_count(kernel.actor_snapshot(&"hero").hp.amount), 80)
	assert_true(kernel.change_max_hp(&"hero", 1, Quantity.from_count(70)))
	assert_eq(_count(kernel.actor_snapshot(&"hero").hp.amount), 70)
	assert_false(kernel.change_max_hp(&"hero", 2, Quantity.from_count(100)))
	assert_false(kernel.change_max_hp(&"hero", 1, Quantity.from_count(0)))
	assert_true(kernel.change_max_hp(&"dead", 1, Quantity.from_count(100)))
	assert_false(kernel.actor_snapshot(&"dead").is_alive())
	assert_eq(kernel.pending_count(), 0)


func test_temporary_barriers_absorb_by_deadline_and_age_before_persistent_layers() -> void:
	var kernel := CombatKernel.new()
	var target := _actor(&"target", 10)
	target.barriers = [_barrier(&"persistent", 2, 1), _barrier(&"later", 2, 1),
		_barrier(&"older", 2, 1), _barrier(&"soon", 2, 1), _barrier(&"newer", 2, 1)]
	target.barriers[1].expires = CombatInstant.at_tick(8)
	target.barriers[2].expires = CombatInstant.at_tick(6)
	target.barriers[3].expires = CombatInstant.at_tick(5)
	target.barriers[4].expires = CombatInstant.at_tick(6)
	assert_true(kernel.add_actor(target))
	assert_true(kernel.add_actor(_actor(&"source", 10)))
	assert_eq(_admit(kernel, kernel.commit(_attack(&"source", 1, 1, 11)), &"target", 2), CombatRootQueue.Result.ACCEPTED)
	var wave := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(wave.result, CombatKernel.Result.CLOSED)
	var component := wave.hits[0].components[0]
	assert_eq(_count(component.hp_removed), 1)
	var order: Array[StringName] = []
	for layer: CombatKernel.LayerReceipt in component.barriers:
		order.append(layer.id)
		assert_true(layer.hostile_depletion)
	assert_eq(order, [&"soon", &"older", &"newer", &"later", &"persistent"])
	assert_true(wave.ended_barriers.is_empty(), "Hostile depletion has its own receipt")


func test_strongest_replacement_and_expiry_keep_complete_instances_and_no_hostile_depletion() -> void:
	var kernel := CombatKernel.new()
	var source := _actor(&"source", 10)
	var original := _barrier(&"guard", 80, 1)
	original.expires = CombatInstant.at_tick(5)
	source.barriers = [original]
	assert_true(kernel.add_actor(source))
	assert_true(kernel.add_actor(_actor(&"target", 10)))
	for activation: int in [1, 2]:
		var action := _attack(&"source", activation, activation, 0)
		action.barrier_for_source = CombatAction.BarrierGrant.new()
		var grant := action.barrier_for_source
		grant.id = &"guard"
		grant.mask = 1
		grant.capacity = Quantity.from_count(60 if activation == 1 else 80)
		grant.duration_ticks = 8
		grant.rule = CombatAction.BarrierRule.STRONGEST
		assert_eq(_admit(kernel, kernel.commit(action), &"target", activation), CombatRootQueue.Result.ACCEPTED)
		var wave := kernel.resolve_next(CombatInstant.at_tick(activation + 1))
		assert_eq(wave.result, CombatKernel.Result.CLOSED)
		var layer := kernel.actor_snapshot(&"source").barriers[0]
		assert_eq(_count(layer.pool.amount), 80)
		assert_eq(layer.expires.tick, 5 if activation == 1 else 10)
		assert_eq(layer.generation, activation)
		assert_eq(wave.ended_barriers.size(), activation - 1)
		if activation == 2:
			assert_eq(wave.ended_barriers[0].reason, CombatKernel.BarrierEnd.REPLACED)
			assert_eq(wave.ended_barriers[0].generation, 1)
	var future := kernel.commit(_attack(&"source", 3, 3, 0))
	assert_ne(future, "")
	var idle := kernel.advance_survival(CombatInstant.at_tick(11))
	assert_eq(idle.result, CombatKernel.Result.CLOSED)
	assert_true(idle.hits.is_empty())
	assert_eq(idle.ended_barriers.size(), 1)
	assert_eq(idle.ended_barriers[0].reason, CombatKernel.BarrierEnd.EXPIRED)
	assert_eq(idle.ended_barriers[0].generation, 2)
	assert_true(kernel.actor_snapshot(&"source").barriers.is_empty())
	assert_eq(_admit(kernel, future, &"target", 10), CombatRootQueue.Result.CLOSED_INSTANT)


func test_hit_at_expiry_drains_before_expiration_and_idle_advance_cannot_skip_it() -> void:
	var kernel := CombatKernel.new()
	var target := _actor(&"target", 10)
	var layer := _barrier(&"timed", 5, 1)
	layer.expires = CombatInstant.at_tick(3)
	target.barriers = [layer]
	assert_true(kernel.add_actor(target))
	assert_true(kernel.add_actor(_actor(&"source", 10)))
	var key := kernel.commit(_attack(&"source", 1, 1, 2))
	var deadline := CombatInstant.at_tick(3)
	assert_eq(kernel.admit_contact(key, 1, REALM, 3, _contact(&"target", true), 1, true), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.advance_survival(deadline).result, CombatKernel.Result.WAITING)
	var wave := kernel.resolve_next(deadline)
	assert_eq(wave.result, CombatKernel.Result.CLOSED)
	assert_eq(_count(wave.hits[0].components[0].barriers[0].absorbed), 2)
	assert_false(wave.hits[0].components[0].barriers[0].hostile_depletion)
	assert_eq(_count(wave.ended_barriers[0].remaining), 3)
	assert_eq(wave.ended_barriers[0].reason, CombatKernel.BarrierEnd.EXPIRED)
	assert_true(kernel.actor_snapshot(&"target").barriers.is_empty())
	assert_eq(_count(kernel.actor_snapshot(&"target").hp.amount), 10)


func test_barrier_accumulation_is_capped_and_clamping_and_decay_have_no_hit() -> void:
	var kernel := CombatKernel.new()
	assert_true(kernel.add_actor(_actor(&"source", 10)))
	assert_true(kernel.add_actor(_actor(&"target", 10)))
	for index: int in [1, 2]:
		var action := _attack(&"source", index, index, 0)
		var grant := CombatAction.BarrierGrant.new()
		grant.id = &"accumulated"
		grant.mask = CombatAction.Damage.PHYSICAL
		grant.capacity = Quantity.from_count(6)
		grant.cap = Quantity.from_count(10)
		grant.rule = CombatAction.BarrierRule.ACCUMULATE
		action.barrier_for_source = grant
		assert_eq(_admit(kernel, kernel.commit(action), &"target", index), CombatRootQueue.Result.ACCEPTED)
		var wave := kernel.resolve_next(CombatInstant.at_tick(index + 1))
		assert_eq(wave.hits[0].granted_barrier, &"accumulated")
		assert_true(wave.ended_barriers.is_empty())
	var cap := CombatKernel.BarrierAdjustment.CAP
	var decay := CombatKernel.BarrierAdjustment.DECAY
	var id := &"accumulated"
	assert_null(kernel.adjust_barrier(&"source", 1, id, 2, cap, Quantity.from_count(1)))
	var grown := kernel.adjust_barrier(&"source", 1, id, 1, cap, Quantity.from_count(12))
	assert_eq(_count(grown.remaining), 10)
	assert_eq(_count(grown.removed), 0)
	var clamped := kernel.adjust_barrier(&"source", 1, id, 1, cap, Quantity.from_count(7))
	assert_eq(_count(clamped.remaining), 7)
	assert_eq(_count(clamped.removed), 3)
	assert_null(clamped.ended)
	var decayed := kernel.adjust_barrier(&"source", 1, id, 1, decay, Quantity.from_count(11))
	assert_eq(_count(decayed.removed), 7)
	assert_eq(decayed.ended.reason, CombatKernel.BarrierEnd.DECAYED)
	assert_true(kernel.actor_snapshot(&"source").barriers.is_empty())
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(4)).result, CombatKernel.Result.IDLE)


func test_damage_recovery_credits_owner_actual_hostile_hp_and_respects_independent_limits() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 8)
	hero.max_hp = Quantity.from_count(10)
	var summon := _actor(&"summon", 7)
	summon.owner = hero.owner
	summon.controller = hero.id
	var enemy := _actor(&"enemy", 5)
	enemy.barriers = [_barrier(&"guard", 6, CombatAction.Damage.PHYSICAL)]
	for actor: CombatantState in [hero, summon, enemy]:
		assert_true(kernel.add_actor(actor))
	for index: int in [1, 2, 3]:
		var action := _attack(&"summon", index, index, 2 if index <= 2 else 20)
		action.origin.owner = hero.owner
		var bounded := CombatAction.DamageRecovery.new()
		bounded.id = &"limited"
		bounded.rate = QuantityFraction.from_amount(Quantity.from_count(1))
		bounded.limit = Quantity.from_count(2)
		bounded.amplification = QuantityFraction.from_amount(Quantity.from_count(2))
		bounded.admits_excess = true
		var independent := bounded.copy()
		independent.id = &"independent"
		independent.limit = Quantity.from_count(20)
		independent.admits_excess = false
		action.damage_recovery = [bounded, independent]
		var key := kernel.commit(action)
		assert_eq(kernel.admit_contact(key, 1, REALM, index, _contact(&"enemy"), 1, index != 1), CombatRootQueue.Result.ACCEPTED)
		var hit := kernel.resolve_next(CombatInstant.at_tick(index + 1)).hits[0]
		assert_eq(_count(hit.damage_recovery[0].eligible_hp_removed), 0 if index <= 2 else 5)
		assert_eq(hit.damage_recovery[0].recipient, &"hero")
		if index == 3:
			assert_eq(_count(hit.components[0].overkill), 13)
			assert_eq(_count(hit.damage_recovery[0].offered), 4)
			assert_eq(_count(hit.damage_recovery[0].restored), 2)
			assert_eq(_count(hit.damage_recovery[0].eligible_excess.amount), 2)
			assert_eq(_count(hit.damage_recovery[1].offered), 10)
			assert_eq(_count(hit.damage_recovery[1].discarded), 10)
	assert_eq(_count(kernel.actor_snapshot(&"hero").hp.amount), 10)
	assert_eq(_count(kernel.actor_snapshot(&"summon").hp.amount), 7)


func test_hp_payment_is_atomic_fails_or_suppresses_without_cooldown_and_stops_lethal_cast() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 5)
	hero.resources[&"mp"] = Quantity.from_count(4)
	hero.revival_protected_until = CombatInstant.at_tick(4)
	hero.barriers = [_barrier(&"guard", 20, CombatAction.Damage.PHYSICAL)]
	hero.follow_ups = [_reaction(&"reprisal", CombatFollowUp.Cause.HOSTILE_DAMAGE, 10)]
	assert_true(kernel.add_actor(hero))
	assert_true(kernel.add_actor(_actor(&"creator", 10)))
	assert_true(kernel.configure_terminal(&"creator", [&"hero"]))
	var expected: Array[CombatKernel.ActivationOutcome] = [
		CombatKernel.ActivationOutcome.REJECTED, CombatKernel.ActivationOutcome.SUPPRESSED,
		CombatKernel.ActivationOutcome.PAID, CombatKernel.ActivationOutcome.LETHAL,
	]
	for index: int in [1, 2, 3, 4]:
		var action := _attack(&"hero", index, index, 1 if index == 3 else 10)
		action.automatic_hp_cost = true
		action.hp_cost = Quantity.from_count(1 if index == 3 else 9)
		action.activation_costs[&"mp"] = Quantity.from_count(5 if index == 1 else 1)
		action.cooldown = &"cast"
		action.cooldown_ticks = 1
		# The first attempt tests insufficient MP independently of revival protection.
		if index == 1:
			action.automatic_hp_cost = false
		var key := kernel.commit(action)
		assert_ne(key, "")
		assert_eq(kernel.admit_contact(key, 1, REALM, index, _contact(&"creator", true), 1, true),
			CombatRootQueue.Result.ACCEPTED)
		var closed := kernel.resolve_next(CombatInstant.at_tick(index), 1)
		assert_eq(closed.activations.size(), 1)
		assert_eq(closed.activations[0].outcome, expected[index - 1])
		var paid := [0, 0, 1, 4]
		assert_eq(_count(closed.activations[0].hp_paid), paid[index - 1])
		assert_eq(closed.hits.size(), 1 if index == 3 else 0)
		assert_eq(closed.terminal, CombatKernel.Terminal.DEFEAT if index == 4 else CombatKernel.Terminal.ACTIVE)
		assert_eq(_count(kernel.actor_snapshot(&"hero").barriers[0].pool.amount), 20)
	assert_eq(_count(kernel.actor_snapshot(&"hero").resources[&"mp"]), 2)
	assert_eq(_count(kernel.actor_snapshot(&"creator").hp.amount), 9)
	assert_eq(kernel.pending_count(), 0)


func test_controller_death_suspends_live_delivery_but_committed_kill_keeps_attribution() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 4)
	hero.max_hp = Quantity.from_count(10)
	var victim := _actor(&"victim", 4)
	var summon := _actor(&"summon", 8)
	summon.controller = hero.id
	summon.owner = hero.owner
	for actor: CombatantState in [hero, summon, victim, _actor(&"survivor", 8), _actor(&"creator", 8)]:
		assert_true(kernel.add_actor(actor))
	assert_true(kernel.configure_terminal(&"creator", [&"hero", &"survivor"]))
	var committed := _attack(&"summon", 1, 1, 4)
	committed.origin.owner = hero.owner
	var recovery := CombatAction.DamageRecovery.new()
	recovery.id = &"vital"
	recovery.rate = QuantityFraction.from_amount(Quantity.from_count(1))
	recovery.limit = Quantity.from_count(10)
	recovery.amplification = recovery.rate
	committed.damage_recovery = [recovery]
	var retained := kernel.commit(committed)
	var continuous := _attack(&"summon", 2, 1, 4)
	continuous.origin.owner = hero.owner
	continuous.continuation = CombatAction.Continuation.LIVE_CONTROLLER
	var suspended := kernel.commit(continuous)
	assert_eq(_admit(kernel, suspended, &"victim", 3), CombatRootQueue.Result.ACCEPTED)
	assert_eq(_admit(kernel, kernel.commit(_attack(&"creator", 1, 1, 4)), &"hero", 2), CombatRootQueue.Result.ACCEPTED)
	assert_eq(kernel.resolve_next(CombatInstant.at_tick(3)).terminal, CombatKernel.Terminal.ACTIVE)
	assert_eq(kernel.admit_contact(suspended, 2, REALM, 4, _contact(&"victim"), 1, true), CombatRootQueue.Result.INVALID)
	var new_attack := _attack(&"summon", 3, 4, 4)
	new_attack.origin.owner = hero.owner
	assert_eq(kernel.commit(new_attack), "")
	assert_true(kernel.resolve_next(CombatInstant.at_tick(4)).hits.is_empty())
	assert_eq(_admit(kernel, retained, &"victim", 4), CombatRootQueue.Result.ACCEPTED)
	var closed := kernel.resolve_next(CombatInstant.at_tick(5))
	assert_eq(closed.eliminations.size(), 1)
	assert_eq(closed.eliminations[0].origin.owner, &"hero")
	assert_true(closed.hits[0].damage_recovery.is_empty())
	assert_false(kernel.actor_snapshot(&"hero").is_alive())


func test_same_instant_hp_payment_claims_use_authored_priority_in_both_admission_orders() -> void:
	for reversed: bool in [false, true]:
		var kernel := CombatKernel.new()
		var hero := _actor(&"hero", 5)
		hero.resources[&"charge"] = Quantity.from_count(1)
		assert_true(kernel.add_actor(hero))
		for slot: int in ([2, 1] if reversed else [1, 2]):
			var action := _attack(&"hero", 1, 1, 0)
			action.origin.source_slot = slot
			action.origin.priority = slot
			action.hp_cost = Quantity.from_count(slot)
			action.activation_costs[&"charge"] = Quantity.from_count(1)
			assert_ne(kernel.commit(action), "")
		var wave := kernel.resolve_next(CombatInstant.at_tick(1))
		assert_eq(wave.activations.size(), 2)
		assert_eq(wave.activations[0].origin.source_slot, 2)
		assert_eq(wave.activations[0].outcome, CombatKernel.ActivationOutcome.PAID)
		assert_eq(wave.activations[1].outcome, CombatKernel.ActivationOutcome.REJECTED)
		assert_eq(_count(kernel.actor_snapshot(&"hero").hp.amount), 3)


func test_fully_absorbed_hostile_damage_qualifies_even_if_layer_survives() -> void:
	var kernel := CombatKernel.new()
	var hero := _actor(&"hero", 5)
	hero.follow_ups = [_reaction(&"reprisal", CombatFollowUp.Cause.HOSTILE_DAMAGE, 1)]
	hero.barriers = [_barrier(&"guard", 5, CombatAction.Damage.PHYSICAL)]
	assert_true(kernel.add_actor(hero))
	assert_true(kernel.add_actor(_actor(&"enemy", 5)))
	assert_eq(_admit(kernel, kernel.commit(_attack(&"enemy", 1, 1, 2)), &"hero", 2), CombatRootQueue.Result.ACCEPTED)
	var closed := kernel.resolve_next(CombatInstant.at_tick(3))
	assert_eq(closed.hits.size(), 2)
	assert_eq(closed.hits[1].reaction, &"reprisal")
	assert_false(closed.hits[0].components[0].barriers[0].hostile_depletion)
	assert_eq(_count(kernel.actor_snapshot(&"hero").hp.amount), 5)


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


static func _contact(id: StringName, stationary: bool = false) -> RealmGeometry.Contact:
	var geometry := RealmGeometry.new(REALM)
	geometry.add_circle(id, 0, RealmSweep.Point.new(0, 0), 2.0, CATEGORY)
	var start := RealmSweep.Point.new(0 if stationary else -8, 0)
	var finish := RealmSweep.Point.new(0 if stationary else 8, 0)
	var sweep := geometry.certify_circle_sweep(REALM, start, finish, 0.0, CATEGORY)
	return sweep.contacts[0]


static func _admit(kernel: CombatKernel, key: String, id: StringName, tick: int) -> CombatRootQueue.Result:
	return kernel.admit_contact(key, 1, REALM, tick, _contact(id), 1, true)


static func _count(quantity: Quantity) -> int:
	return quantity.native_at_scale(0)
