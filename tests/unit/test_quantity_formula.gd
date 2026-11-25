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


func test_world_time_switch_is_exact_at_25_and_27_minutes() -> void:
	var just_before := QuantityFormula.world_time_factor(Quantity.from_count(1499999, 3), true)
	var comparison := just_before.plus(_fraction(-3, 1))
	assert_eq(comparison.numerator.sign_value, -1)
	var at := QuantityFormula.world_time_factor(Quantity.from_count(1500), true)
	assert_eq(at.numerator.compare(Quantity.from_count(21)), 0)
	assert_eq(at.divisor.compare(Quantity.from_count(5)), 0)
	var next := QuantityFormula.world_time_factor(Quantity.from_count(1620), false)
	assert_eq(next.numerator.compare(Quantity.from_count(25)), 0)
	assert_eq(next.divisor.compare(Quantity.from_count(8)), 0)


func test_directed_xp_power_keeps_both_bounds_and_exact_roots() -> void:
	var noninteger := _fraction(5, 2)
	var bounds := QuantityProgression.power_bounds(2, noninteger, 24)
	assert_eq(bounds.size(), 2)
	if bounds.size() != 2:
		return
	var target := Quantity.from_count(32)
	assert_eq(bounds[0].multiply(bounds[0]).compare(target), -1)
	assert_eq(bounds[1].multiply(bounds[1]).compare(target), 1)
	assert_eq(bounds[1].subtract(bounds[0]).compare(Quantity.from_count(1, 24)), 0)
	var exact := QuantityProgression.power_bounds(4, noninteger, 24)
	assert_eq(exact[0].compare(target), 0)
	assert_eq(exact[1].compare(target), 0)
	assert_true(QuantityProgression.power_bounds(2, _fraction(4097, 4096), 2).is_empty())


func test_xp_curve_transition_uses_the_authored_level_and_preserves_carry() -> void:
	var base := Quantity.from_count(40)
	var coefficient := Quantity.from_count(3)
	var squared := _fraction(2, 1)
	var growth := _fraction(5, 4)
	var transition := QuantityProgression.xp_need_bounds(6, 6, base, coefficient, squared, growth, 24)
	var later := QuantityProgression.xp_need_bounds(7, 6, base, coefficient, squared, growth, 24)
	assert_eq(transition[0].numerator.compare(Quantity.from_count(115)), 0)
	assert_eq(transition[1].divisor.compare(Quantity.from_count(1)), 0)
	assert_eq(later[0].numerator.compare(Quantity.from_count(575)), 0)
	assert_eq(later[1].divisor.compare(Quantity.from_count(4)), 0)
	var level_one := QuantityProgression.xp_need_bounds(1, 6, base, coefficient, squared, growth, 24)
	var level_two := QuantityProgression.xp_need_bounds(2, 6, base, coefficient, squared, growth, 24)
	var carry := Quantity.from_count(85).subtract(level_one[0].numerator).subtract(level_two[0].numerator)
	assert_eq(carry.compare(Quantity.from_count(2)), 0)


func _fraction(numerator: int, divisor: int) -> QuantityFraction:
	return QuantityFraction.create(Quantity.from_count(numerator), Quantity.from_count(divisor))
