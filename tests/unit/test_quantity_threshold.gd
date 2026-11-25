extends GutTest


func test_mixed_rate_pool_keeps_survival_equality_and_overkill_distinct() -> void:
	var hp := Quantity.from_count(1)
	var error := QuantityErrorBounds.new()
	for numerator: int in [2, 3]:
		var part := _fraction(numerator, 9)
		var draft := QuantityThresholdDebit.resolve(hp, error, part, _quantize(part))
		assert_not_null(draft)
		if draft == null:
			return
		hp = draft.remaining
		error = draft.error
	assert_eq(hp.compare(Quantity.from_count(444445, 6)), 0)
	var equal := _fraction(4, 9)
	var delta := QuantityFraction.from_amount(Quantity.from_count(25, 8))
	var less := equal.plus(delta.opposite())
	var greater := equal.plus(delta)
	var survivor := QuantityThresholdDebit.resolve(hp, error, less, _quantize(less))
	var lethal := QuantityThresholdDebit.resolve(hp, error, equal, _quantize(equal))
	var over := QuantityThresholdDebit.resolve(hp, error, greater, _quantize(greater))
	assert_not_null(survivor)
	assert_not_null(lethal)
	assert_not_null(over)
	if survivor == null or lethal == null or over == null:
		return
	assert_eq(survivor.remaining.sign_value, 1)
	assert_eq(survivor.overkill.sign_value, 0)
	assert_eq(lethal.remaining.sign_value, 0)
	assert_eq(lethal.overkill.sign_value, 0)
	assert_eq(lethal.adjustment.compare(Quantity.from_count(1, 6)), 0)
	assert_eq(over.remaining.sign_value, 0)
	assert_eq(over.overkill.compare(Quantity.from_count(25, 8)), 0)
	assert_eq(hp.compare(Quantity.from_count(444445, 6)), 0, "Drafts share the same unchanged starting pool")


func test_debit_refines_when_an_ordinary_grid_rounds_to_a_false_depletion() -> void:
	var one := Quantity.from_count(1)
	var lower := _fraction(9_999_999, 10_000_000)
	var nominal := _quantize(lower)
	assert_eq(nominal.compare(one), 0)
	var draft := QuantityThresholdDebit.resolve(one, QuantityErrorBounds.new(), lower, nominal)
	assert_not_null(draft)
	if draft != null:
		assert_eq(draft.remaining.compare(Quantity.from_count(1, 7)), 0)
		assert_eq(draft.debit.compare(Quantity.from_count(9_999_999, 7)), 0)


func test_outward_bounds_replay_then_fail_safely_when_the_exact_anchor_is_lost() -> void:
	var state := QuantityErrorBounds.new()
	var hp := Quantity.from_count(1)
	var ideal := QuantityFraction.from_amount(hp)
	var denominators: Array[int] = [1000000007, 1000000009, 1000000033]
	for index: int in 12:
		var debit := _fraction(1, denominators[index % denominators.size()])
		var nominal := _quantize(debit)
		ideal = ideal.plus(debit.opposite())
		hp = hp.subtract(nominal)
		state = state.after_change(debit.opposite(), nominal.negated())
		assert_not_null(state)
		if state == null:
			return
		if index == 2:
			assert_false(state.is_exact())
			assert_gt(state.replay_size(), 0)
			assert_lte(state.replay_size(), QuantityErrorBounds.REPLAY_LIMIT)
			assert_eq(state.certify_after(hp, ideal), QuantityErrorBounds.Sign.EQUAL)
			var checkpoint := state.snapshot()
			var reopened := QuantityErrorBounds.restore(checkpoint)
			assert_not_null(reopened)
			if reopened == null:
				return
			assert_eq(reopened.snapshot(), checkpoint)
			assert_eq(reopened.certify_after(hp, ideal), QuantityErrorBounds.Sign.EQUAL)
			var altered := checkpoint.duplicate()
			altered[2] = 255
			assert_null(QuantityErrorBounds.restore(altered))
			state = reopened
	assert_eq(state.replay_size(), 0)
	assert_eq(state.certify_after(hp, _fraction(1, 3)), QuantityErrorBounds.Sign.ABOVE)
	assert_eq(state.certify_after(hp, ideal), QuantityErrorBounds.Sign.UNKNOWN)
	assert_null(QuantityThresholdDebit.resolve(hp, state, ideal, _quantize(ideal)),
		"An unknown threshold has no publishable draft")
	var reconstructed := QuantityErrorBounds.restore(state.snapshot())
	assert_not_null(reconstructed)
	if reconstructed != null:
		assert_eq(reconstructed.certify_after(hp, ideal), QuantityErrorBounds.Sign.UNKNOWN)
	var exact := QuantityErrorBounds.new()
	assert_true(QuantityErrorBounds.restore(exact.snapshot()).is_exact())


func test_mixed_layer_frontier_passes_only_certified_overkill_to_the_next_pool() -> void:
	var barrier := Quantity.from_count(1)
	var uncertainty := QuantityErrorBounds.new()
	for rate: int in [2, 3]:
		var raw := _fraction(rate, 9)
		var hit := QuantityThresholdDebit.resolve(barrier, uncertainty, raw, _quantize(raw))
		barrier = hit.remaining
		uncertainty = hit.error
	var first := QuantityLayerLedger.Pool.new(barrier, uncertainty)
	var quarter_micro := Quantity.from_count(25, 8)
	var second := QuantityLayerLedger.Pool.new(quarter_micro, QuantityErrorBounds.new())
	var hp := QuantityLayerLedger.Pool.new(Quantity.from_count(1), QuantityErrorBounds.new())
	var incoming := _fraction(4, 9).plus(QuantityFraction.from_amount(quarter_micro))
	var resolved := QuantityLayerLedger.draft(incoming, _quantize(incoming), [first, second], hp, true)
	assert_not_null(resolved)
	if resolved != null:
		assert_true(resolved.layers[0].hostile_depletion)
		assert_true(resolved.layers[1].hostile_depletion)
		assert_eq(resolved.layers[1].spent.compare(quarter_micro), 0)
		assert_eq(resolved.hp.spent.sign_value, 0)
		assert_eq(resolved.overkill.sign_value, 0)
		assert_eq(resolved.incoming.compare(barrier.add(quarter_micro)), 0)
		assert_eq(second.amount.compare(quarter_micro), 0)


func test_expired_barrier_replay_keeps_certified_overflow_and_stops_ambiguous_hp() -> void:
	var barrier := QuantityLayerLedger.Pool.new(Quantity.from_count(100), QuantityErrorBounds.new())
	var ideal := QuantityFraction.from_amount(barrier.amount)
	var denominators: Array[int] = [101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173]
	for denominator: int in denominators:
		var raw := _fraction(10, denominator)
		var posted := QuantityThresholdDebit.resolve(barrier.amount, barrier.error, raw, _quantize(raw))
		assert_not_null(posted)
		if posted == null:
			return
		barrier = QuantityLayerLedger.Pool.new(posted.remaining, posted.error)
		ideal = ideal.plus(raw.opposite())
	assert_false(barrier.error.is_exact())
	assert_eq(barrier.error.replay_size(), 0)
	var checkpoint := barrier.error.snapshot()
	barrier.error = QuantityErrorBounds.restore(checkpoint)
	var second := QuantityLayerLedger.Pool.new(Quantity.from_count(1), QuantityErrorBounds.new())
	var hp := QuantityLayerLedger.Pool.new(Quantity.from_count(20), QuantityErrorBounds.new())
	var incoming := _fraction(105, 1)
	var settled := QuantityLayerLedger.draft(incoming, _quantize(incoming), [barrier, second], hp, true)
	assert_not_null(settled)
	if settled == null:
		return
	assert_true(settled.layers[0].hostile_depletion)
	assert_true(settled.layers[1].hostile_depletion)
	assert_false(settled.lethal)
	var hp_spent := Quantity.from_count(104).subtract(barrier.amount)
	assert_eq(settled.hp.spent.compare(hp_spent), 0)
	assert_eq(settled.eligible_hostile_hp.compare(hp_spent), 0)
	assert_eq(settled.incoming.compare(Quantity.from_count(105)), 0)
	assert_false(settled.hp.after.error.is_exact())
	assert_eq(QuantityErrorBounds.restore(settled.hp.after.error.snapshot()).snapshot(), settled.hp.after.error.snapshot())

	var hp_boundary := ideal.plus(_fraction(21, 1))
	assert_null(QuantityLayerLedger.draft(hp_boundary, _quantize(hp_boundary), [barrier, second], hp, true),
		"An ideal equality within an expired interval cannot be published")
	assert_eq(barrier.error.snapshot(), checkpoint)
	assert_eq(hp.amount.compare(Quantity.from_count(20)), 0)


func test_certified_heal_preserves_recovery_cap_and_positive_excess() -> void:
	var one := Quantity.from_count(1)
	var hp := QuantityLayerLedger.Pool.new(one, QuantityErrorBounds.new())
	for debit: int in [2, 3]:
		var raw := _fraction(debit, 9)
		var posted := QuantityThresholdDebit.resolve(hp.amount, hp.error, raw, _quantize(raw))
		hp = QuantityLayerLedger.Pool.new(posted.remaining, posted.error)
	var full := _fraction(5, 9)
	var quantum := _fraction(1, 4_000_000)
	var lower := full.plus(quantum.opposite())
	var upper := full.plus(quantum)
	var under := QuantityLayerLedger.recovery(lower, _quantize(lower), hp, one, true)
	var equal := QuantityLayerLedger.recovery(full, _quantize(full), hp, one, true)
	var excess := QuantityLayerLedger.recovery(upper, _quantize(upper), hp, one, true)
	assert_not_null(under)
	assert_not_null(equal)
	assert_not_null(excess)
	if under == null or equal == null or excess == null:
		return
	assert_eq(under.hp.amount.compare(Quantity.from_count(99999975, 8)), 0)
	assert_eq(under.eligible_excess.amount.sign_value, 0)
	assert_eq(equal.hp.amount.compare(one), 0)
	assert_eq(equal.adjustment.compare(Quantity.from_count(-1, 6)), 0)
	assert_eq(equal.eligible_excess.amount.sign_value, 0)
	assert_eq(excess.hp.amount.compare(one), 0)
	assert_eq(excess.eligible_excess.amount.compare(Quantity.from_count(1, 6)), 0)
	assert_eq(excess.eligible_excess.error.certify_after(excess.eligible_excess.amount, quantum), QuantityErrorBounds.Sign.EQUAL)
	assert_eq(excess.hp_restored.add(excess.eligible_excess.amount).compare(excess.offered), 0)
	var discarded := QuantityLayerLedger.recovery(upper, _quantize(upper), hp, one, false)
	assert_eq(discarded.eligible_excess.amount.sign_value, 0)
	assert_eq(discarded.discarded.compare(excess.eligible_excess.amount), 0)
	var corpse := QuantityLayerLedger.Pool.new(Quantity.from_count(0), QuantityErrorBounds.new())
	var dead := QuantityLayerLedger.recovery(full, _quantize(full), corpse, one, true)
	assert_eq(dead.hp_restored.sign_value, 0)
	assert_eq(dead.eligible_excess.amount.sign_value, 0)
	assert_eq(dead.discarded.compare(_quantize(full)), 0)
	assert_eq(hp.amount.compare(Quantity.from_count(444445, 6)), 0)


func _fraction(numerator: int, divisor: int) -> QuantityFraction:
	return QuantityFraction.create(Quantity.from_count(numerator), Quantity.from_count(divisor))


func _quantize(raw: QuantityFraction) -> Quantity:
	return Quantity.quantize_ratio(raw.numerator, raw.divisor)
