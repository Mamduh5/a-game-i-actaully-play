class_name QuantityFormula
extends RefCounted
## Exact intermediate formula values for WP04. The posting owner chooses when
## to quantize each state-mutating output.

class BonusCategory:
	var values: Array[Quantity] = []


static func damage_component(base_with_flat_terms: Quantity, categories: Array[BonusCategory],
		defense: Quantity, reduction: Quantity, penetration: Quantity, mitigation_constant: Quantity,
		vulnerability: Quantity, immune: bool) -> QuantityFraction:
	var zero := Quantity.from_count(0)
	if immune:
		return QuantityFraction.from_amount(zero)
	var one := Quantity.from_count(1)
	if (base_with_flat_terms == null or defense == null or reduction == null or penetration == null
			or vulnerability == null or mitigation_constant == null or mitigation_constant.sign_value <= 0):
		return null
	var offense := base_with_flat_terms
	for category: BonusCategory in categories:
		var multiplier := one
		for bonus: Quantity in category.values:
			multiplier = multiplier.add(bonus)
			if multiplier == null:
				return null
		offense = offense.multiply(multiplier)
		if offense == null:
			return null
	var reduction_factor := one.subtract(reduction)
	var penetration_factor := one.subtract(penetration)
	if reduction_factor == null or penetration_factor == null:
		return null
	var effective := defense.multiply(reduction_factor)
	if effective == null:
		return null
	effective = effective.multiply(penetration_factor)
	if effective == null:
		return null
	var denominator := (effective if effective.sign_value > 0 else zero).add(mitigation_constant)
	var numerator := offense.multiply(mitigation_constant)
	if numerator == null:
		return null
	numerator = numerator.multiply(vulnerability)
	return QuantityFraction.create(numerator, denominator)


static func source_limited_recovery(eligible_hp_loss: Quantity, rate: QuantityFraction,
		source_limit: Quantity, amplification: QuantityFraction) -> QuantityFraction:
	var eligible := QuantityFraction.from_amount(eligible_hp_loss)
	if eligible == null or rate == null or source_limit == null or amplification == null:
		return null
	var converted := eligible.times(rate)
	if converted == null:
		return null
	var threshold := source_limit.multiply(converted.divisor)
	if threshold == null:
		return null
	var allowed := QuantityFraction.from_amount(source_limit) if threshold.compare(converted.numerator) < 0 else converted
	return allowed.times(amplification)


## Exact time-zero factors at a specific Collapse tier.
static func collapse_factor(tier: int, for_hp: bool) -> QuantityFraction:
	if tier < 1:
		return null
	var base := QuantityFraction.create(Quantity.from_count(7 if for_hp else 5),
		Quantity.from_count(5 if for_hp else 4))
	var factor := base.raised(tier)
	if factor == null:
		return null
	return factor.times(QuantityFraction.from_amount(Quantity.from_count(3 if for_hp else 2)))
