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


func _fraction(numerator: int, divisor: int) -> QuantityFraction:
	return QuantityFraction.create(Quantity.from_count(numerator), Quantity.from_count(divisor))


func _quantize(raw: QuantityFraction) -> Quantity:
	return Quantity.quantize_ratio(raw.numerator, raw.divisor)
