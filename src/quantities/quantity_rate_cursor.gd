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


func snapshot() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE)
	bytes[0] = VERSION
	bytes.encode_u16(1, _grid)
	bytes.encode_s64(3, _occurrences)
	for amount: Quantity in [_numerator, _denominator, _posted]:
		bytes.append_array(QuantityCodec.encode(amount))
	return bytes


static func restore(bytes: PackedByteArray) -> QuantityRateCursor:
	if bytes.size() < HEADER_SIZE or bytes[0] != VERSION:
		return null
	var at := HEADER_SIZE
	var values: Array[Quantity] = []
	for _index: int in 3:
		if bytes.size() - at < QuantityCodec.HEADER_SIZE:
			return null
		var length := bytes.decode_u32(at + 4)
		if length <= 0 or length > Quantity.MAX_DIGITS or length > bytes.size() - at - QuantityCodec.HEADER_SIZE:
			return null
		var end := at + QuantityCodec.HEADER_SIZE + length
		var value := QuantityCodec.decode(bytes.slice(at, end))
		if value == null:
			return null
		values.append(value)
		at = end
	var count := bytes.decode_s64(3)
	var cursor := create(values[0], values[1])
	if cursor == null or count < 0 or at != bytes.size() or bytes.decode_u16(1) != cursor.grid:
		return null
	var expected := cursor._projection(count)
	if expected == null or expected.compare(values[2]) != 0:
		return null
	cursor._occurrences = count
	cursor._posted = values[2]
	return cursor


func _projection(count: int) -> Quantity:
	var total := _numerator.multiply(Quantity.from_count(count))
	return Quantity.round_ratio(total, _denominator, _grid) if total != null else null
