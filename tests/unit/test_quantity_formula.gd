extends GutTest


func test_damage_formula_preserves_category_stacking_and_separate_penetration() -> void:
	var category := QuantityFormula.BonusCategory.new()
	category.values = [Quantity.from_count(1, 1), Quantity.from_count(2, 1)]
	var independent := QuantityFormula.BonusCategory.new()
	independent.values = [Quantity.from_count(25, 2)]
	var incoming := QuantityFormula.damage_component(Quantity.from_count(120), [category, independent],
		Quantity.from_count(80), Quantity.from_count(25, 2), Quantity.from_count(5, 1),
		Quantity.from_count(100), Quantity.from_count(13, 1), false)
	assert_not_null(incoming)
	if incoming != null:
		assert_eq(incoming.numerator.compare(Quantity.from_count(195)), 0)
		assert_eq(incoming.divisor.compare(Quantity.from_count(1)), 0)


func test_qas_defense_fixture_and_source_limited_amplified_recovery() -> void:
	var incoming := QuantityFormula.damage_component(Quantity.from_count(100), [], Quantity.from_count(100),
		Quantity.from_count(5, 1), Quantity.from_count(2, 1), Quantity.from_count(100),
		Quantity.from_count(14, 1), false)
	assert_eq(incoming.numerator.compare(Quantity.from_count(100)), 0)
	assert_eq(incoming.divisor.compare(Quantity.from_count(1)), 0)
	var hit := QuantityPosting.damage(incoming.numerator, [Quantity.from_count(30)], Quantity.from_count(50), true)
	assert_eq(hit.overkill.compare(Quantity.from_count(20)), 0)
	var rate := QuantityFraction.create(Quantity.from_count(1), Quantity.from_count(5))
	var amplification := QuantityFraction.create(Quantity.from_count(3), Quantity.from_count(2))
	var offer := QuantityFormula.source_limited_recovery(hit.eligible_hostile_hp, rate,
		Quantity.from_count(4), amplification)
	assert_eq(offer.numerator.compare(Quantity.from_count(6)), 0)
	assert_eq(offer.divisor.compare(Quantity.from_count(1)), 0)


func test_collapse_computes_from_the_base_at_the_exact_tier() -> void:
	var hp := QuantityFormula.collapse_factor(1, true)
	assert_eq(hp.numerator.compare(Quantity.from_count(21)), 0)
	assert_eq(hp.divisor.compare(Quantity.from_count(5)), 0)
	var attack := QuantityFormula.collapse_factor(2, false)
	assert_eq(attack.numerator.compare(Quantity.from_count(25)), 0)
	assert_eq(attack.divisor.compare(Quantity.from_count(8)), 0)
	var widened := QuantityFormula.collapse_factor(120, true)
	assert_true(widened.numerator.uses_limbs)
	assert_eq(widened.numerator.magnitude_text(),
		"774258632968047828143753452239517150895073420828298643733841795277783560311952311790861937087837016003")
	assert_eq(widened.divisor.magnitude_text(),
		"752316384526264005099991383822237233803945956334136013765601092018187046051025390625")
