class_name QuantityRateCursor
extends RefCounted
## Fixed-grid cumulative posting for one live compatible stream. The caller owns
## stream identity, expiry, and publication of the surrounding group.

const VERSION := 1
const HEADER_SIZE := 11

var occurrences: int:
	get: return _occurrences
var posted: Quantity:
	get: return _posted
var grid: int:
	get: return _grid

var _numerator: Quantity
var _denominator: Quantity
var _grid: int
var _occurrences: int
var _posted := Quantity.from_count(0)
var _scaled_numerator: int
var _native_denominator: int


static func create(numerator: Quantity, denominator: Quantity) -> QuantityRateCursor:
	if numerator.sign_value <= 0 or denominator.sign_value <= 0:
		return null
	var grid := Quantity.ratio_scale(numerator, denominator)
	if grid < 0:
		return null
	var cursor := QuantityRateCursor.new()
	cursor._numerator = numerator
	cursor._denominator = denominator
	cursor._grid = grid
	var scalar: Variant = numerator.native_at_scale(grid + denominator.scale)
	if scalar != null and not denominator.uses_limbs:
		cursor._scaled_numerator = scalar
		cursor._native_denominator = denominator.native_at_scale(denominator.scale)
	return cursor


func next_debit() -> Quantity:
	if _numerator == null or _occurrences == Quantity.INT_MAX:
		return null
	var next := _occurrences + 1
	var cumulative := _projection(next)
	if cumulative == null:
		return null
	var debit := cumulative.subtract(_posted)
	if debit == null:
		return null
	_posted = cumulative
	_occurrences = next
	return debit


func matches_rate(numerator: Quantity, denominator: Quantity) -> bool:
	return _numerator.compare(numerator) == 0 and _denominator.compare(denominator) == 0


## A group advances the detached cursor until its entire draft can publish.
func copy() -> QuantityRateCursor:
	var result := QuantityRateCursor.new()
	result._numerator = _numerator
	result._denominator = _denominator
	result._grid = _grid
	result._occurrences = _occurrences
	result._posted = _posted
	result._scaled_numerator = _scaled_numerator
	result._native_denominator = _native_denominator
	return result


func snapshot() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE)
	bytes[0] = VERSION
	bytes.encode_u16(1, _grid)
	bytes.encode_s64(3, _occurrences)
	for amount: Quantity in [_numerator, _denominator, _posted]:
		bytes.append_array(QuantityCodec.encode(amount))
	return bytes


## Only the rounding phase affects future debits for the same exact rate.
## Whole-grid rates have no phase. For other rates, preserve the residual
## and the parity needed by nearest-even rounding, without a cumulative count.
func continuation_phase() -> PackedByteArray:
	if _native_denominator > 0 and _scaled_numerator % _native_denominator == 0:
		return PackedByteArray()
	var initial := _projection(1)
	var first := initial.multiply(_denominator) if initial != null else null
	if first != null and first.compare(_numerator) == 0:
		return PackedByteArray()
	var ideal := _numerator.multiply(Quantity.from_count(_occurrences))
	var represented := _posted.multiply(_denominator)
	var residual := ideal.subtract(represented) if ideal != null and represented != null else null
	var integer_count := _posted.count_at_scale(_grid)
	if residual == null or integer_count == null:
		# Keep the full cursor identity if the reduced phase cannot be encoded.
		var full := PackedByteArray([1])
		full.append_array(snapshot())
		return full
	var digits := integer_count.magnitude_text()
	var parity := int(digits.right(1)) % 2
	var phase := PackedByteArray([0, parity])
	for amount: Quantity in [_numerator, _denominator, residual]:
		phase.append_array(QuantityCodec.encode(amount))
	return phase


static func restore(bytes: PackedByteArray) -> QuantityRateCursor:
	if bytes.size() < HEADER_SIZE or bytes[0] != VERSION:
		return null
	var values := QuantityCodec.decode_fields(bytes, HEADER_SIZE, 3)
	if values.is_empty():
		return null
	var count := bytes.decode_s64(3)
	var cursor := create(values[0], values[1])
	if cursor == null or count < 0 or bytes.decode_u16(1) != cursor.grid:
		return null
	var expected := cursor._projection(count)
	if expected == null or expected.compare(values[2]) != 0:
		return null
	cursor._occurrences = count
	cursor._posted = values[2]
	return cursor


func _projection(count: int) -> Quantity:
	if _native_denominator > 0:
		@warning_ignore("integer_division")
		if count <= Quantity.INT_MAX / _scaled_numerator:
			var dividend := count * _scaled_numerator
			@warning_ignore("integer_division")
			var whole := dividend / _native_denominator
			var part := dividend % _native_denominator
			var opposite := _native_denominator - part
			if part > opposite or (part == opposite and whole % 2 == 1):
				whole += 1
			return Quantity.from_count(whole, _grid)
	var total := _numerator.multiply(Quantity.from_count(count))
	return Quantity.round_ratio(total, _denominator, _grid) if total != null else null
