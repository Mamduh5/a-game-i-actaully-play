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
	assert_true(kernel.add_actor(_actor(&"source", 10)))
	var target := _actor(&"target", 30)
	target.barriers.append(_barrier(&"physical", 10, CombatAction.Damage.PHYSICAL))
	target.physical.immune = true
	assert_true(kernel.add_actor(target))
	var blocked := _actor(&"blocked", 30)
	blocked.prevents_hit = true
	assert_true(kernel.add_actor(blocked))
	var mixed := _attack(&"source", 1, 1, 11)
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
