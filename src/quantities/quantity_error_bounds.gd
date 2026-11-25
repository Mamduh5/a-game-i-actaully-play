class_name QuantityErrorBounds
extends RefCounted
## Ideal pool minus represented pool. States are immutable between closed drafts.

enum Sign { BELOW = -1, EQUAL = 0, ABOVE = 1, UNKNOWN = 2 }

const BOUND_SCALE := 18
const REPLAY_LIMIT := 8
const VERSION := 1
const HEADER_SIZE := 3

var _exact: QuantityFraction
var _lower: Quantity
var _upper: Quantity
var _anchor: QuantityFraction
var _suffix: Array[QuantityFraction] = []


func _init(exact_image: QuantityFraction = null) -> void:
	_exact = exact_image if exact_image != null else QuantityFraction.from_amount(Quantity.from_count(0))


## The caller supplies ideal and represented signed changes in the same orientation.
func after_change(ideal: QuantityFraction, represented: Quantity) -> QuantityErrorBounds:
	return _after_change(ideal, represented, 1)


func after_debit(ideal: QuantityFraction, represented: Quantity) -> QuantityErrorBounds:
	return _after_change(ideal, represented, -1)


## Difference between two error states. Combining independent intervals conserves
## the bound. A replay from either pool alone cannot certify the combined state.
func minus(other: QuantityErrorBounds) -> QuantityErrorBounds:
	if other._exact != null:
		return _accumulate(other._exact.opposite())
	var own := _outward_bounds()
	if own.size() != 2:
		return null
	return _from_bounds(own[0].subtract(other._upper), own[1].subtract(other._lower))


func opposite() -> QuantityErrorBounds:
	if _exact != null:
		return QuantityErrorBounds.new(_exact.opposite())
	var next := _from_bounds(_upper.negated(), _lower.negated())
	if _anchor != null:
		next._anchor = _anchor.opposite()
		for operand: QuantityFraction in _suffix:
			next._suffix.append(operand.opposite())
	return next


func _outward_bounds() -> Array[Quantity]:
	if _exact != null:
		return _exact.outward(BOUND_SCALE)
	return [_lower, _upper]


static func _from_bounds(lower: Quantity, upper: Quantity) -> QuantityErrorBounds:
	if lower == null or upper == null:
		return null
	var state := QuantityErrorBounds.new()
	state._exact = null
	state._lower = lower
	state._upper = upper
	return state


func _after_change(ideal: QuantityFraction, represented: Quantity, direction: int) -> QuantityErrorBounds:
	if ideal == null or represented == null:
		return null
	if _exact != null:
		var fast := _exact.add_compact_error(ideal, represented, direction)
		if fast != null:
			return QuantityErrorBounds.new(fast)
	var represented_ratio := QuantityFraction.from_amount(represented)
	if represented_ratio == null:
		return null
	var error := ideal.plus(represented_ratio.opposite())
	if error == null:
		return null
	return _accumulate(error if direction > 0 else error.opposite())


## Sign of ideal remaining capacity after a prospective, positive exact debit.
func certify_after(remaining: Quantity, incoming: QuantityFraction) -> Sign:
	if remaining == null or incoming == null or incoming.numerator.sign_value < 0:
		return Sign.UNKNOWN
	if _exact != null:
		if _certifies_above_native(remaining, incoming):
			return Sign.ABOVE
		return _exact_sign(_exact, remaining, incoming)
	var directed := incoming.outward(BOUND_SCALE)
	if directed.size() != 2:
		return Sign.UNKNOWN
	var minimum := remaining.subtract(directed[1])
	var maximum := remaining.subtract(directed[0])
	if minimum == null or maximum == null:
		return Sign.UNKNOWN
	minimum = minimum.add(_lower)
	maximum = maximum.add(_upper)
	if minimum == null or maximum == null:
		return Sign.UNKNOWN
	if minimum.sign_value > 0:
		return Sign.ABOVE
	if maximum.sign_value < 0:
		return Sign.BELOW
	if minimum.sign_value == 0 and maximum.sign_value == 0:
		return Sign.EQUAL
	var residual := exact_after(remaining, incoming)
	return residual.numerator.sign_value as Sign if residual != null else Sign.UNKNOWN


## Can require replay. A null result means that only the outward bounds remain.
func exact_after(remaining: Quantity, incoming: QuantityFraction) -> QuantityFraction:
	var replay := _exact if _exact != null else _anchor
	if replay == null:
		return null
	for operand: QuantityFraction in _suffix:
		replay = replay.plus(operand)
		if replay == null:
			return null
	return _exact_residual(replay, remaining, incoming)


func is_exact() -> bool:
	return _exact != null


func replay_size() -> int:
	return _suffix.size()


func snapshot() -> PackedByteArray:
	if _exact != null:
		var exact_bytes := PackedByteArray([VERSION, 0, 0])
		_append_ratio(exact_bytes, _exact)
		return exact_bytes
	var bytes := PackedByteArray([VERSION, 1, _suffix.size()])
	bytes.append_array(QuantityCodec.encode(_lower))
	bytes.append_array(QuantityCodec.encode(_upper))
	if _anchor != null:
		_append_ratio(bytes, _anchor)
		for error: QuantityFraction in _suffix:
			_append_ratio(bytes, error)
	return bytes


static func restore(bytes: PackedByteArray) -> QuantityErrorBounds:
	if bytes.size() < HEADER_SIZE or bytes[0] != VERSION or bytes[1] > 1 or bytes[2] > REPLAY_LIMIT:
		return null
	var count := int(bytes[2])
	if bytes[1] == 0 and count != 0:
		return null
	var fields := QuantityCodec.decode_fields(bytes, HEADER_SIZE, 2 if count == 0 else 4 + 2 * count)
	if fields.is_empty():
		return null
	var state := QuantityErrorBounds.new()
	if bytes[1] == 0:
		state._exact = _read_ratio(fields, 0)
		return state if state._exact != null and state._exact.compact() else null
	state._exact = null
	state._lower = fields[0]
	state._upper = fields[1]
	if (state._lower.scale > BOUND_SCALE or state._upper.scale > BOUND_SCALE
			or state._lower.compare(state._upper) > 0):
		return null
	if count == 0:
		return state
	state._anchor = _read_ratio(fields, 2)
	if state._anchor == null or not state._anchor.compact():
		return null
	var replay := state._anchor
	for index: int in count:
		var error := _read_ratio(fields, 4 + index * 2)
		if error == null:
			return null
		state._suffix.append(error)
		if replay != null:
			replay = replay.plus(error)
	if replay != null:
		var reference := replay.outward(BOUND_SCALE)
		if not reference.is_empty() and (
				state._lower.compare(reference[0]) > 0 or state._upper.compare(reference[1]) < 0):
			return null
	return state


static func _append_ratio(bytes: PackedByteArray, fraction: QuantityFraction) -> void:
	bytes.append_array(QuantityCodec.encode(fraction.numerator))
	bytes.append_array(QuantityCodec.encode(fraction.divisor))


static func _read_ratio(fields: Array[Quantity], offset: int) -> QuantityFraction:
	var numerator := fields[offset]
	var divisor := fields[offset + 1]
	if numerator.scale != 0 or divisor.scale != 0:
		return null
	var ratio := QuantityFraction.create(numerator, divisor)
	if ratio == null or ratio.numerator.compare(numerator) != 0 or ratio.divisor.compare(divisor) != 0:
		return null
	return ratio


func _accumulate(error: QuantityFraction) -> QuantityErrorBounds:
	var next := QuantityErrorBounds.new()
	if _exact != null:
		var exact := _exact.plus(error)
		if exact != null and exact.compact():
			next._exact = exact
			return next
		if exact != null:
			var enclosing := exact.outward(BOUND_SCALE)
			if enclosing.is_empty():
				return null
			next._lower = enclosing[0]
			next._upper = enclosing[1]
		else:
			if not _add_bounds(next, _exact.outward(BOUND_SCALE), error.outward(BOUND_SCALE)):
				return null
		next._anchor = _exact
		next._suffix.append(error)
	else:
		if not _add_bounds(next, [_lower, _upper], error.outward(BOUND_SCALE)):
			return null
		if _anchor != null and _suffix.size() < REPLAY_LIMIT:
			next._anchor = _anchor
			next._suffix = _suffix.duplicate()
			next._suffix.append(error)
	next._exact = null
	return next


## A coarse integer proof for the ordinary case, far from a threshold.
func _certifies_above_native(remaining: Quantity, incoming: QuantityFraction) -> bool:
	if remaining.uses_limbs or remaining.scale >= Quantity.INT_POWERS.size() or not incoming.compact():
		return false
	var remaining_count: int = remaining.native_at_scale(remaining.scale)
	var incoming_count: int = incoming.numerator.native_at_scale(0)
	var divisor: int = incoming.divisor.native_at_scale(0)
	var absolute_error: int = absi(_exact.numerator.native_at_scale(0))
	var error_divisor: int = _exact.divisor.native_at_scale(0)
	@warning_ignore("integer_division")
	var remaining_floor := remaining_count / Quantity.INT_POWERS[remaining.scale]
	@warning_ignore("integer_division")
	var incoming_ceil := incoming_count / divisor + int(incoming_count % divisor != 0)
	@warning_ignore("integer_division")
	var error_ceil := absolute_error / error_divisor + int(absolute_error % error_divisor != 0)
	return remaining_floor > incoming_ceil and remaining_floor - incoming_ceil > error_ceil


static func _add_bounds(target: QuantityErrorBounds, old: Array[Quantity], delta: Array[Quantity]) -> bool:
	if old.size() != 2 or delta.size() != 2:
		return false
	target._lower = old[0].add(delta[0])
	target._upper = old[1].add(delta[1])
	return target._lower != null and target._upper != null


static func _exact_sign(error: QuantityFraction, remaining: Quantity, incoming: QuantityFraction) -> Sign:
	var residual := _exact_residual(error, remaining, incoming)
	return residual.numerator.sign_value as Sign if residual != null else Sign.UNKNOWN


static func _exact_residual(error: QuantityFraction, remaining: Quantity, incoming: QuantityFraction) -> QuantityFraction:
	var pool := QuantityFraction.from_amount(remaining)
	if pool == null:
		return null
	var adjusted := pool.plus(error)
	if adjusted == null:
		return null
	return adjusted.plus(incoming.opposite())
