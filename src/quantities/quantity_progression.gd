class_name QuantityProgression
extends RefCounted
## Directed evaluation of the GDS §21.2 XP curve. Coefficients are supplied by
## the caller. Progression can request more precision before committing a level.


static func xp_need_bounds(level: int, transition: int, base: Quantity, coefficient: Quantity,
		exponent: QuantityFraction, growth: QuantityFraction, places: int) -> Array[QuantityFraction]:
	if (level < 1 or transition < 1 or base == null or coefficient == null or exponent == null
			or growth == null or base.sign_value < 0 or coefficient.sign_value < 0
			or exponent.numerator.compare(exponent.divisor) <= 0
			or growth.numerator.compare(growth.divisor) <= 0):
		return []
	var polynomial_level := mini(level, transition)
	var root_bounds := power_bounds(polynomial_level - 1, exponent, places)
	if root_bounds.is_empty():
		return []
	var multiplier := growth.raised(maxi(0, level - transition))
	if multiplier == null:
		return []
	var result: Array[QuantityFraction] = []
	for bound: Quantity in root_bounds:
		var term := coefficient.multiply(bound)
		if term == null:
			return []
		var threshold := QuantityFraction.from_amount(base.add(term))
		if threshold == null:
			return []
		var advanced := threshold.times(multiplier)
		if advanced == null:
			return []
		result.append(advanced)
	return result


static func power_bounds(base: int, exponent: QuantityFraction, places: int) -> Array[Quantity]:
	if (base < 0 or exponent == null or exponent.numerator.sign_value <= 0
			or not exponent.compact() or places < 0 or places > Quantity.MAX_SCALE):
		return []
	var power: int = exponent.numerator.native_at_scale(0)
	var degree: int = exponent.divisor.native_at_scale(0)
	if degree > 1 and places > 0:
		@warning_ignore("integer_division")
		if degree > Quantity.MAX_SCALE / places:
			return []
	var radicand := _integer_power(Quantity.from_count(base), power)
	if radicand == null:
		return []
	if degree == 1 or radicand.sign_value == 0:
		return [radicand, radicand]
	var scaled := radicand.count_at_scale(degree * places)
	if scaled == null:
		return []
	var floor_root := _root_floor(scaled, degree)
	if floor_root == null:
		return []
	var lower := Quantity.from_integer_count(floor_root, places)
	var achieved := _integer_power(floor_root, degree)
	if lower == null or achieved == null:
		return []
	if achieved.compare(scaled) == 0:
		return [lower, lower]
	var upper := lower.add(Quantity.from_count(1, places))
	if upper == null:
		return []
	return [lower, upper]


static func _root_floor(value: Quantity, degree: int) -> Quantity:
	var digits := value.magnitude_text().length()
	var upper_places := 1
	if degree < digits:
		@warning_ignore("integer_division")
		upper_places = (digits + degree - 1) / degree
	var low := Quantity.from_count(0)
	var high := Quantity.from_count(1).count_at_scale(upper_places)
	if high == null:
		return null
	var two := Quantity.from_count(2)
	while true:
		var sum := low.add(high)
		if sum == null:
			return null
		var midpoint: Quantity = Quantity.divide_integers(sum, two)[0]
		if midpoint.compare(low) == 0:
			return low
		var powered := _integer_power(midpoint, degree)
		# For a whole nonnegative integer power, capacity overflow exceeds the
		# representable radicand. It supplies an upper bound, with no posted quantity.
		if powered == null or powered.compare(value) > 0:
			high = midpoint
		else:
			low = midpoint
	return null


static func _integer_power(base: Quantity, power: int) -> Quantity:
	var factor := base
	var result := Quantity.from_count(1)
	while power != 0:
		if power & 1:
			result = result.multiply(factor)
			if result == null:
				return null
		power >>= 1
		if power != 0:
			factor = factor.multiply(factor)
			if factor == null:
				return null
	return result
