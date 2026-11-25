class_name QuantityFraction
extends RefCounted
## Reduced transient exact ratio. Live error tracking only stores compact remainders
## or a bounded replay of individual operands.

var numerator: Quantity:
	get: return _numerator
var divisor: Quantity:
	get: return _divisor

var _numerator: Quantity
var _divisor: Quantity


static func from_amount(value: Quantity) -> QuantityFraction:
	return create(value, Quantity.from_count(1))


static func create(value: Quantity, denominator: Quantity) -> QuantityFraction:
	if value == null or denominator == null or denominator.sign_value <= 0:
		return null
	var grid := maxi(value.scale, denominator.scale)
	var n := value.count_at_scale(grid)
	var d := denominator.count_at_scale(grid)
	if n == null or d == null:
		return null
	if n.sign_value == 0:
		return _new(n, Quantity.from_count(1))
	if not n.uses_limbs and not d.uses_limbs:
		return _reduce_native(n.native_at_scale(0), d.native_at_scale(0))
	var common := _gcd(n.absolute(), d)
	if common == null:
		return null
	return _new(_quotient(n, common), _quotient(d, common))


func compact() -> bool:
	return not _numerator.uses_limbs and not _divisor.uses_limbs


func plus(other: QuantityFraction) -> QuantityFraction:
	if _numerator.sign_value == 0:
		return other
	if other.numerator.sign_value == 0:
		return self
	if compact() and other.compact():
		var fast := _plus_native(other.numerator.native_at_scale(0), other.divisor.native_at_scale(0))
		if fast != null:
			return fast
	if _divisor.compare(other.divisor) == 0:
		return create(_numerator.add(other.numerator), _divisor)
	var common := _gcd(_divisor, other.divisor)
	if common == null:
		return null
	var left_factor := _quotient(other.divisor, common)
	var right_factor := _quotient(_divisor, common)
	var left := _numerator.multiply(left_factor)
	var right := other.numerator.multiply(right_factor)
	if left == null or right == null:
		return null
	return create(left.add(right), _divisor.multiply(left_factor))


func opposite() -> QuantityFraction:
	return _new(_numerator.negated(), _divisor)


## Computes this error plus a signed ideal-versus-represented change with scalar guards.
func add_compact_error(ideal: QuantityFraction, represented: Quantity, direction: int) -> QuantityFraction:
	if (not compact() or not ideal.compact() or represented.uses_limbs
			or represented.scale >= Quantity.INT_POWERS.size() or absi(direction) != 1):
		return null
	var ideal_n: int = ideal.numerator.native_at_scale(0)
	var ideal_d: int = ideal.divisor.native_at_scale(0)
	var grid: int = Quantity.INT_POWERS[represented.scale]
	var count: int = represented.native_at_scale(represented.scale)
	if (not _positive_multiplier_fits(ideal_n, grid) or not _positive_multiplier_fits(ideal_d, grid)
			or not _positive_multiplier_fits(count, ideal_d)):
		return null
	var left := ideal_n * grid
	var right := -count * ideal_d
	return _plus_native(direction * (left + right), ideal_d * grid) if _addition_fits(left, right) else null


func _plus_native(right_n: int, right_d: int) -> QuantityFraction:
	var left_d: int = _divisor.native_at_scale(0)
	var left_n: int = _numerator.native_at_scale(0)
	var common := _gcd_native(left_d, right_d)
	@warning_ignore("integer_division")
	var left_factor := right_d / common
	@warning_ignore("integer_division")
	var right_factor := left_d / common
	if (not _positive_multiplier_fits(left_n, left_factor) or not _positive_multiplier_fits(right_n, right_factor)
			or not _positive_multiplier_fits(left_d, left_factor)):
		return null
	var left := left_n * left_factor
	var right := right_n * right_factor
	return _reduce_native(left + right, left_d * left_factor) if _addition_fits(left, right) else null


func times(other: QuantityFraction) -> QuantityFraction:
	var left_cancel := _gcd(_numerator.absolute(), other.divisor)
	var right_cancel := _gcd(other.numerator.absolute(), _divisor)
	if left_cancel == null or right_cancel == null:
		return null
	var numerator_product := _quotient(_numerator, left_cancel).multiply(_quotient(other.numerator, right_cancel))
	var divisor_product := _quotient(_divisor, right_cancel).multiply(_quotient(other.divisor, left_cancel))
	if numerator_product == null or divisor_product == null:
		return null
	return _new(numerator_product, divisor_product)


func over(other: QuantityFraction) -> QuantityFraction:
	if other.numerator.sign_value == 0:
		return null
	var value := other.divisor if other.numerator.sign_value > 0 else other.divisor.negated()
	return times(_new(value, other.numerator.absolute()))


func raised(exponent: int) -> QuantityFraction:
	if exponent < 0:
		return null
	var result := from_amount(Quantity.from_count(1))
	var factor: QuantityFraction = self
	while exponent != 0:
		if exponent & 1:
			result = result.times(factor)
			if result == null:
				return null
		exponent >>= 1
		if exponent != 0:
			factor = factor.times(factor)
			if factor == null:
				return null
	return result


func outward(at_scale: int) -> Array[Quantity]:
	return Quantity.outward_ratio(_numerator, _divisor, at_scale)


static func _gcd(left: Quantity, right: Quantity) -> Quantity:
	if not left.uses_limbs and not right.uses_limbs:
		return Quantity.from_count(_gcd_native(left.native_at_scale(0), right.native_at_scale(0)))
	while right.sign_value != 0:
		var division := Quantity.divide_integers(left, right)
		if division.size() != 2:
			return null
		left = right
		right = division[1]
	return left


static func _quotient(left: Quantity, right: Quantity) -> Quantity:
	return Quantity.divide_integers(left, right)[0]


static func _new(value: Quantity, denominator: Quantity) -> QuantityFraction:
	var result := QuantityFraction.new()
	result._numerator = value
	result._divisor = denominator
	return result


static func _reduce_native(numerator: int, denominator: int) -> QuantityFraction:
	var common := _gcd_native(absi(numerator), denominator)
	@warning_ignore("integer_division")
	return _new(Quantity.from_count(numerator / common), Quantity.from_count(denominator / common))


static func _gcd_native(left: int, right: int) -> int:
	while right != 0:
		var part := left % right
		left = right
		right = part
	return left


static func _positive_multiplier_fits(signed_value: int, factor: int) -> bool:
	@warning_ignore("integer_division")
	return absi(signed_value) <= Quantity.INT_MAX / factor


static func _addition_fits(left: int, right: int) -> bool:
	if right > 0:
		return left <= Quantity.INT_MAX - right
	return left >= -Quantity.INT_MAX - right
