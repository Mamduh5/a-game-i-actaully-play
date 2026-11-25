class_name QuantityMagnitude
extends RefCounted
## Unsigned little-endian limbs for the WP04 candidate. Arrays are owned by callers.

const RADIX := 1000000000
const LIMB_DIGITS := 9
const INT_MAX := 9223372036854775807
const POWERS: Array[int] = [1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000]

class Quotient:
	var whole: PackedInt32Array
	var remainder: PackedInt32Array


static func from_int(value: int) -> PackedInt32Array:
	var limbs := PackedInt32Array()
	while value != 0:
		limbs.append(value % RADIX)
		@warning_ignore("integer_division")
		value /= RADIX
	return limbs


## Called after the decoder bounds and validates the digits.
static func from_digits(digits: String) -> PackedInt32Array:
	var limbs := PackedInt32Array()
	var end := digits.length()
	while end > 0:
		var start := maxi(end - LIMB_DIGITS, 0)
		limbs.append(digits.substr(start, end - start).to_int())
		end = start
	trim(limbs)
	return limbs


static func try_int(limbs: PackedInt32Array) -> int:
	var value := 0
	for i: int in range(limbs.size() - 1, -1, -1):
		@warning_ignore("integer_division")
		if value > (INT_MAX - limbs[i]) / RADIX:
			return -1
		value = value * RADIX + limbs[i]
	return value


static func digits(limbs: PackedInt32Array) -> String:
	var chunks := PackedStringArray()
	for i: int in range(limbs.size() - 1, -1, -1):
		chunks.append(str(limbs[i]) if chunks.is_empty() else "%09d" % limbs[i])
	return "".join(chunks) if not chunks.is_empty() else "0"


static func compare(left: PackedInt32Array, right: PackedInt32Array) -> int:
	if left.size() != right.size():
		return -1 if left.size() < right.size() else 1
	for i: int in range(left.size() - 1, -1, -1):
		if left[i] != right[i]:
			return -1 if left[i] < right[i] else 1
	return 0


static func add(left: PackedInt32Array, right: PackedInt32Array) -> PackedInt32Array:
	var size := maxi(left.size(), right.size())
	var result := PackedInt32Array()
	result.resize(size + 1)
	var carry := 0
	for i: int in size:
		var total := carry
		if i < left.size():
			total += left[i]
		if i < right.size():
			total += right[i]
		result[i] = total % RADIX
		@warning_ignore("integer_division")
		carry = total / RADIX
	result[size] = carry
	trim(result)
	return result


## Requires left >= right.
static func subtract(left: PackedInt32Array, right: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(left.size())
	var borrow := 0
	for i: int in left.size():
		var difference := left[i] - borrow
		if i < right.size():
			difference -= right[i]
		borrow = int(difference < 0)
		result[i] = difference + borrow * RADIX
	trim(result)
	return result


static func multiply(left: PackedInt32Array, right: PackedInt32Array) -> PackedInt32Array:
	if left.is_empty() or right.is_empty():
		return PackedInt32Array()
	var result := PackedInt32Array()
	result.resize(left.size() + right.size())
	for i: int in left.size():
		var carry := 0
		for j: int in right.size():
			# Each term is < RADIX² + 2 × RADIX, inside signed int64.
			var total := left[i] * right[j] + result[i + j] + carry
			result[i + j] = total % RADIX
			@warning_ignore("integer_division")
			carry = total / RADIX
		result[i + right.size()] = carry
	trim(result)
	return result


static func multiply_limb(limbs: PackedInt32Array, factor: int) -> PackedInt32Array:
	return multiply(limbs, PackedInt32Array([factor]))


static func shift_decimal(limbs: PackedInt32Array, places: int) -> PackedInt32Array:
	if limbs.is_empty() or places == 0:
		return limbs
	var result := multiply_limb(limbs, POWERS[places % LIMB_DIGITS])
	@warning_ignore("integer_division")
	var whole := places / LIMB_DIGITS
	if whole == 0:
		return result
	var shifted := PackedInt32Array()
	shifted.resize(whole)
	shifted.append_array(result)
	return shifted


## Changes the quotient in place. Requires 0 < divisor < RADIX.
static func divide_limb(limbs: PackedInt32Array, divisor: int) -> int:
	var remainder := 0
	for i: int in range(limbs.size() - 1, -1, -1):
		var current := remainder * RADIX + limbs[i]
		@warning_ignore("integer_division")
		limbs[i] = current / divisor
		remainder = current % divisor
	trim(limbs)
	return remainder


static func divide(dividend: PackedInt32Array, divisor: PackedInt32Array) -> Quotient:
	var result := Quotient.new()
	if compare(dividend, divisor) < 0:
		result.remainder = dividend
		return result
	if divisor.size() == 1:
		result.whole = dividend.duplicate()
		var remainder := divide_limb(result.whole, divisor[0])
		if remainder != 0:
			result.remainder = PackedInt32Array([remainder])
		return result
	result.whole.resize(dividend.size())
	for i: int in range(dividend.size() - 1, -1, -1):
		if dividend[i] != 0 or not result.remainder.is_empty():
			result.remainder.insert(0, dividend[i])
		if compare(result.remainder, divisor) < 0:
			continue
		var low := 1
		var high := RADIX
		while high - low > 1:
			@warning_ignore("integer_division")
			var middle := (low + high) / 2
			if compare(multiply_limb(divisor, middle), result.remainder) <= 0:
				low = middle
			else:
				high = middle
		result.whole[i] = low
		result.remainder = subtract(result.remainder, multiply_limb(divisor, low))
	trim(result.whole)
	return result


static func trim(limbs: PackedInt32Array) -> void:
	var size := limbs.size()
	while size > 0 and limbs[size - 1] == 0:
		size -= 1
	if size != limbs.size():
		limbs.resize(size)
