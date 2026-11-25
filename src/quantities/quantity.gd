class_name Quantity
extends RefCounted
## Exact signed decimal storage. Null from a factory or arithmetic marks an invalid
## input or a resource fault. The owning group must stop before publication.

const Magnitude := preload("res://src/quantities/quantity_magnitude.gd")
const MAX_LIMBS := 480
const MAX_DIGITS := MAX_LIMBS * Magnitude.LIMB_DIGITS
const MAX_SCALE := 4096
const INT_MIN := -9223372036854775807 - 1
const INT_MAX := Magnitude.INT_MAX
const ORDINARY_SCALE := 6
const RELATIVE_COUNTS := 100000
const INT_POWERS: Array[int] = [
	1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000,
	10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000,
	1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000,
]

var scale: int:
	get: return _scale
var sign_value: int:
	get: return _sign
var uses_limbs: bool:
	get: return not _limbs.is_empty()

var _scale: int
var _sign: int
var _native: int
var _limbs: PackedInt32Array


static func from_count(count: int, decimal_scale: int = 0) -> Quantity:
	if not _valid_scale(decimal_scale):
		return null
	if count == INT_MIN:
		return _make_wide(-1, decimal_scale, Magnitude.from_digits("9223372036854775808"))
	return _make_native(signi(count), absi(count), decimal_scale)


static func from_integer_count(value: Quantity, decimal_scale: int) -> Quantity:
	if value == null or value.scale != 0 or not _valid_scale(decimal_scale):
		return null
	if value.uses_limbs:
		return _make_wide(value._sign, decimal_scale, value._limbs.duplicate())
	return _make_native(value._sign, value._native, decimal_scale)


## Canonical magnitude text avoids any float or JSON numeric field for the count.
static func from_canonical(negative: bool, decimal_scale: int, digits: String) -> Quantity:
	if not _valid_scale(decimal_scale) or not is_canonical_magnitude(digits, decimal_scale, negative):
		return null
	return _make_wide(-1 if negative else 1, decimal_scale, Magnitude.from_digits(digits))


static func is_canonical_magnitude(digits: String, decimal_scale: int, negative: bool) -> bool:
	var length := digits.length()
	if length == 0 or length > MAX_DIGITS:
		return false
	if digits[0] == "0":
		return length == 1 and decimal_scale == 0 and not negative
	if decimal_scale > 0 and digits[length - 1] == "0":
		return false
	for i: int in length:
		var code := digits.unicode_at(i)
		if code < 48 or code > 57:
			return false
	return true


## Candidate minimum grid for the formula output. Strict branch checks may request a finer grid.
static func ratio_scale(numerator: Quantity, denominator: Quantity, minimum: int = ORDINARY_SCALE) -> int:
	if not _valid_scale(minimum) or denominator._sign <= 0:
		return -1
	if numerator._sign == 0 or _enough_counts(numerator, denominator, minimum):
		return minimum
	var guessed := 5 + denominator._digit_count() - numerator._digit_count() + numerator._scale - denominator._scale
	var target := maxi(minimum + 1, guessed)
	if target <= MAX_SCALE and not _enough_counts(numerator, denominator, target):
		target += 1
	return target if target <= MAX_SCALE else -1


static func quantize_ratio(numerator: Quantity, denominator: Quantity, minimum: int = ORDINARY_SCALE) -> Quantity:
	var target := ratio_scale(numerator, denominator, minimum)
	return round_ratio(numerator, denominator, target) if target >= 0 else null


## Rounds to nearest with ties to even using exact quotient/remainder on the requested grid.
static func round_ratio(numerator: Quantity, denominator: Quantity, target: int) -> Quantity:
	if not _valid_scale(target) or denominator._sign <= 0:
		return null
	if numerator._sign == 0:
		return from_count(0)
	var shift := target + denominator._scale - numerator._scale
	var left := numerator._widen_native(maxi(0, shift))
	var right := denominator._widen_native(maxi(0, -shift))
	if left >= 0 and right > 0:
		@warning_ignore("integer_division")
		var whole := left / right
		var remainder := left % right
		var half_order := right - remainder
		if remainder > half_order or (remainder == half_order and whole % 2 == 1):
			whole += 1
		return _make_native(numerator._sign, whole, target)
	var divisor := Magnitude.shift_decimal(denominator._as_limbs(), maxi(0, -shift))
	var dividend := Magnitude.shift_decimal(numerator._as_limbs(), maxi(0, shift))
	var division := Magnitude.divide(dividend, divisor)
	var half_order := Magnitude.compare(division.remainder, Magnitude.subtract(divisor, division.remainder))
	var odd := not division.whole.is_empty() and division.whole[0] % 2 == 1
	if half_order > 0 or (half_order == 0 and odd):
		division.whole = Magnitude.add(division.whole, PackedInt32Array([1]))
	return _make_wide(numerator._sign, target, division.whole)


## Conservative adjacent grid values for an exact ratio.
static func outward_ratio(numerator: Quantity, denominator: Quantity, target: int) -> Array[Quantity]:
	if (target >= 0 and target < INT_POWERS.size() and numerator._scale == 0 and denominator._scale == 0
			and not numerator.uses_limbs and not denominator.uses_limbs and denominator._sign > 0):
		var compact := _outward_native(numerator, denominator._native, target)
		if not compact.is_empty():
			return compact
	var nearest := round_ratio(numerator, denominator, target)
	if nearest == null:
		return []
	var projected := nearest.multiply(denominator)
	if projected == null:
		return []
	var order := projected.compare(numerator)
	if order == 0:
		return [nearest, nearest]
	var quantum := from_count(1, target)
	var adjacent := nearest.subtract(quantum) if order > 0 else nearest.add(quantum)
	if adjacent == null:
		return []
	if order > 0:
		return [adjacent, nearest]
	return [nearest, adjacent]


## Long division in at most two decimal chunks. Small-rate numerators can
## exceed int64 when scaled all at once, even though the result fits.
static func _outward_native(numerator: Quantity, divisor: int, target: int) -> Array[Quantity]:
	@warning_ignore("integer_division")
	var whole := numerator._native / divisor
	var remainder := numerator._native % divisor
	var places := target
	while places > 0:
		var next := mini(places, 9)
		var radix := INT_POWERS[next]
		@warning_ignore("integer_division")
		var limit := INT_MAX / radix
		if whole > limit or remainder > limit:
			return []
		var shifted := remainder * radix
		@warning_ignore("integer_division")
		var digit := shifted / divisor
		whole *= radix
		if whole > INT_MAX - digit:
			return []
		whole += digit
		remainder = shifted % divisor
		places -= next
	var lower := from_count(numerator._sign * whole, target)
	if remainder == 0:
		return [lower, lower]
	if whole == INT_MAX:
		return []
	var upper := from_count(numerator._sign * (whole + 1), target)
	if numerator._sign >= 0:
		return [lower, upper]
	return [upper, lower]


## Truncated integer quotient and remainder. The remainder follows the dividend's sign.
static func divide_integers(numerator: Quantity, denominator: Quantity) -> Array[Quantity]:
	if numerator._scale != 0 or denominator._scale != 0 or denominator._sign <= 0:
		return []
	if not numerator.uses_limbs and not denominator.uses_limbs:
		@warning_ignore("integer_division")
		var whole := numerator._native / denominator._native
		var part := numerator._native % denominator._native
		return [_make_native(numerator._sign, whole, 0), _make_native(numerator._sign, part, 0)]
	var result := Magnitude.divide(numerator._as_limbs(), denominator._as_limbs())
	return [_make_wide(numerator._sign, 0, result.whole), _make_wide(numerator._sign, 0, result.remainder)]


static func _enough_counts(numerator: Quantity, denominator: Quantity, target: int) -> bool:
	var shift := target + denominator._scale - numerator._scale
	var left := numerator._widen_native(maxi(0, shift))
	var right := denominator._widen_native(maxi(0, -shift))
	if left >= 0 and right > 0:
		@warning_ignore("integer_division")
		return left / right >= RELATIVE_COUNTS
	var dividend := Magnitude.shift_decimal(numerator._as_limbs(), maxi(0, shift))
	var divisor := Magnitude.shift_decimal(denominator._as_limbs(), maxi(0, -shift))
	return Magnitude.compare(dividend, Magnitude.multiply_limb(divisor, RELATIVE_COUNTS)) >= 0


func _digit_count() -> int:
	if not uses_limbs:
		return str(_native).length()
	return (_limbs.size() - 1) * Magnitude.LIMB_DIGITS + str(_limbs[-1]).length()


func magnitude_text() -> String:
	return Magnitude.digits(_limbs) if uses_limbs else str(_native)


func count_at_scale(target: int) -> Quantity:
	if not _valid_scale(target) or target < _scale:
		return null
	var compact := _aligned_native(target)
	if compact >= 0:
		return _make_native(_sign, compact, 0)
	return _make_wide(_sign, 0, _aligned_limbs(target))


## An allocation-free extraction for checked native formula paths.
func native_at_scale(target: int) -> Variant:
	if target < _scale:
		return null
	var compact := _aligned_native(target)
	return compact * _sign if compact >= 0 else null


func absolute() -> Quantity:
	return _with_sign(absi(_sign))


func negated() -> Quantity:
	return _with_sign(-_sign)


func add(other: Quantity) -> Quantity:
	return _combine(other, other._sign)


func subtract(other: Quantity) -> Quantity:
	return _combine(other, -other._sign)


func multiply(other: Quantity) -> Quantity:
	if _sign == 0 or other._sign == 0:
		return from_count(0)
	var result_scale := _scale + other._scale
	if not uses_limbs and not other.uses_limbs:
		@warning_ignore("integer_division")
		if _native <= INT_MAX / other._native:
			return _make_native(_sign * other._sign, _native * other._native, result_scale)
	# Scratch is bounded by the two inputs. Only normalized outputs can persist.
	var product := Magnitude.multiply(_as_limbs(), other._as_limbs())
	return _make_wide(_sign * other._sign, result_scale, product)


func compare(other: Quantity) -> int:
	if _sign != other._sign:
		return -1 if _sign < other._sign else 1
	if _sign == 0:
		return 0
	var target_scale := maxi(_scale, other._scale)
	var left := _aligned_native(target_scale)
	var right := other._aligned_native(target_scale)
	if left >= 0 and right >= 0:
		return (-1 if left < right else int(left > right)) * _sign
	return _sign * Magnitude.compare(_aligned_limbs(target_scale), other._aligned_limbs(target_scale))


func _combine(other: Quantity, other_sign: int) -> Quantity:
	if _sign == 0:
		return other._with_sign(other_sign)
	if other_sign == 0:
		return self
	var target_scale := maxi(_scale, other._scale)
	var left := _aligned_native(target_scale)
	var right := other._aligned_native(target_scale)
	if left >= 0 and right >= 0:
		if _sign != other_sign:
			return _make_native(_sign if left >= right else other_sign, absi(left - right), target_scale)
		if left <= INT_MAX - right:
			return _make_native(_sign, left + right, target_scale)
	var wide_left := _aligned_limbs(target_scale)
	var wide_right := other._aligned_limbs(target_scale)
	if _sign == other_sign:
		return _make_wide(_sign, target_scale, Magnitude.add(wide_left, wide_right))
	if Magnitude.compare(wide_left, wide_right) >= 0:
		return _make_wide(_sign, target_scale, Magnitude.subtract(wide_left, wide_right))
	return _make_wide(other_sign, target_scale, Magnitude.subtract(wide_right, wide_left))


func _aligned_native(target_scale: int) -> int:
	return _widen_native(target_scale - _scale)


func _widen_native(places: int) -> int:
	if uses_limbs or places >= INT_POWERS.size():
		return -1
	var factor: int = INT_POWERS[places]
	@warning_ignore("integer_division")
	return _native * factor if _native <= INT_MAX / factor else -1


func _aligned_limbs(target_scale: int) -> PackedInt32Array:
	return Magnitude.shift_decimal(_as_limbs(), target_scale - _scale)


func _as_limbs() -> PackedInt32Array:
	return _limbs if uses_limbs else Magnitude.from_int(_native)


func _with_sign(new_sign: int) -> Quantity:
	if new_sign == _sign:
		return self
	var result := Quantity.new()
	result._scale = _scale
	result._sign = new_sign
	result._native = _native
	result._limbs = _limbs
	return result


static func _valid_scale(decimal_scale: int) -> bool:
	return decimal_scale >= 0 and decimal_scale <= MAX_SCALE


static func _make_native(signum: int, value: int, decimal_scale: int) -> Quantity:
	var result := Quantity.new()
	if value == 0:
		return result
	while decimal_scale > 0 and value % 10 == 0:
		@warning_ignore("integer_division")
		value /= 10
		decimal_scale -= 1
	if not _valid_scale(decimal_scale):
		return null
	result._sign = signum
	result._native = value
	result._scale = decimal_scale
	return result


## Receives an owned scratch array. Stored limbs never change after construction.
static func _make_wide(signum: int, decimal_scale: int, limbs: PackedInt32Array) -> Quantity:
	if limbs.is_empty():
		return Quantity.new()
	var shift_limbs := 0
	while decimal_scale >= Magnitude.LIMB_DIGITS and limbs[shift_limbs] == 0:
		shift_limbs += 1
		decimal_scale -= Magnitude.LIMB_DIGITS
	if shift_limbs > 0:
		limbs = limbs.slice(shift_limbs)
	while decimal_scale > 0 and limbs[0] % 10 == 0:
		Magnitude.divide_limb(limbs, 10)
		decimal_scale -= 1
	if limbs.size() > MAX_LIMBS or not _valid_scale(decimal_scale):
		return null
	var compact := Magnitude.try_int(limbs)
	if compact >= 0:
		return _make_native(signum, compact, decimal_scale)
	var result := Quantity.new()
	result._sign = signum
	result._scale = decimal_scale
	result._limbs = limbs
	return result
