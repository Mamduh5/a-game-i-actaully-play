extends GutTest


func test_hostile_damage_posts_ordered_absorption_hp_and_overkill_once() -> void:
	var barriers: Array[Quantity] = [_units(30), _units(10)]
	var draft := QuantityPosting.damage(_units(100), barriers, _units(50), true)
	assert_not_null(draft)
	if draft == null:
		return
	assert_eq(draft.layers[0].absorbed.compare(_units(30)), 0)
	assert_eq(draft.layers[1].absorbed.compare(_units(10)), 0)
	assert_true(draft.layers[0].hostile_depletion)
	assert_true(draft.layers[1].hostile_depletion)
	assert_eq(draft.hp_removed.compare(_units(50)), 0)
	assert_eq(draft.eligible_hostile_hp.compare(_units(50)), 0)
	assert_eq(draft.overkill.compare(_units(10)), 0)
	assert_true(draft.lethal)
	assert_eq(barriers[0].compare(_units(30)), 0, "The draft leaves the source pools intact")


func test_one_quantum_below_and_at_depletion_and_non_hostile_payment() -> void:
	var cap := _units(1)
	var quantum := Quantity.from_count(1, 8)
	var almost := QuantityPosting.damage(cap.subtract(quantum), [cap], cap, true)
	assert_false(almost.layers[0].hostile_depletion)
	assert_eq(almost.layers[0].remaining.compare(quantum), 0)
	assert_eq(almost.hp_removed.sign_value, 0)
	var exact := QuantityPosting.damage(cap, [cap], cap, true)
	assert_true(exact.layers[0].hostile_depletion)
	assert_false(exact.lethal)
	var cost := QuantityPosting.damage(cap, [], cap, false)
	assert_true(cost.lethal)
	assert_eq(cost.hp_removed.compare(cap), 0)
	assert_eq(cost.eligible_hostile_hp.sign_value, 0)


func test_capped_recovery_conserves_the_offer_and_discards_ineligible_excess() -> void:
	var allowed := QuantityPosting.recovery(_units(6), _units(98), _units(100), true)
	assert_eq(allowed.hp_restored.compare(_units(2)), 0)
	assert_eq(allowed.hp_after.compare(_units(100)), 0)
	assert_eq(allowed.eligible_excess.compare(_units(4)), 0)
	assert_eq(allowed.discarded.sign_value, 0)
	var denied := QuantityPosting.recovery(_units(6), _units(98), _units(100), false)
	assert_eq(denied.hp_restored.compare(allowed.hp_restored), 0)
	assert_eq(denied.eligible_excess.sign_value, 0)
	assert_eq(denied.discarded.compare(_units(4)), 0)
	var dead := QuantityPosting.recovery(_units(10), _units(0), _units(100), true)
	assert_eq(dead.hp_after.sign_value, 0)
	assert_eq(dead.eligible_excess.sign_value, 0)
	assert_eq(dead.discarded.compare(_units(10)), 0)


func test_faulted_draft_leaves_original_pool_unchanged() -> void:
	var huge := Quantity.from_canonical(false, 0, "9".repeat(Quantity.MAX_DIGITS))
	var tiny := Quantity.from_count(1, 12)
	assert_null(QuantityPosting.damage(tiny, [], huge, true))
	assert_eq(huge.magnitude_text(), "9".repeat(Quantity.MAX_DIGITS))


func test_pr08_debits_only_the_actual_fractional_release() -> void:
	var cap := Quantity.from_count(1355, 1)
	var draft := QuantityPosting.reserve_release(_units(8), _units(100), cap)
	assert_eq(draft.hp_restored.compare(Quantity.from_count(6775, 3)), 0)
	assert_eq(draft.reserve_spent.compare(draft.hp_restored), 0)
	assert_eq(draft.reserve_after.compare(Quantity.from_count(1225, 3)), 0)
	assert_eq(draft.hp_after.compare(Quantity.from_count(106775, 3)), 0)
	assert_eq(QuantityPosting.reserve_release(_units(8), cap, cap).reserve_spent.sign_value, 0)
	assert_eq(QuantityPosting.reserve_release(_units(8), _units(0), cap).reserve_spent.sign_value, 0)


func _units(count: int) -> Quantity:
	return Quantity.from_count(count)
