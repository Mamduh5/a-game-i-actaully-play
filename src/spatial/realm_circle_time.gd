class_name RealmCircleTime
extends RefCounted
## Outward binary64 bounds for a circle sweep against circles and segments.
## A caller refines unresolved or intersecting bounds before ordering events.

enum Result { MISS, HIT, UNRESOLVED }
enum Order { BEFORE, SAME, AFTER, UNRESOLVED }

class Contact:
	var outcome: Result
	var earliest: float
	var latest: float
	var _exact_ratio: PackedFloat64Array

	func _init(result: Result, lower: float = 0.0, upper: float = 0.0) -> void:
		outcome = result
		earliest = lower
		latest = upper

	func order_against(other: Contact) -> Order:
		if outcome != Result.HIT or other.outcome != Result.HIT:
			return Order.UNRESOLVED
		if latest < other.earliest:
			return Order.BEFORE
		if earliest > other.latest:
			return Order.AFTER
		if earliest == latest and earliest == other.earliest and earliest == other.latest:
			return Order.SAME
		if _exact_ratio.size() == 2 and other._exact_ratio.size() == 2:
			return RealmCircleTime._order_fractions(_exact_ratio, other._exact_ratio)
		return Order.UNRESOLVED

class Interval:
	var lower: float
	var upper: float

	func _init(minimum: float, maximum: float) -> void:
		lower = minimum
		upper = maximum

	func is_point(value: float) -> bool:
		return lower == value and upper == value

var _bits := PackedByteArray()


func _init() -> void:
	_bits.resize(8)


func measure(start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		target_start: RealmSweep.Point, target_finish: RealmSweep.Point, target_radius: float) -> Contact:
	if (not _finite_point(start) or not _finite_point(finish) or not _finite_point(target_start)
			or not _finite_point(target_finish) or not is_finite(radius) or not is_finite(target_radius)
			or radius < 0.0 or target_radius < 0.0):
		return Contact.new(Result.UNRESOLVED)
	var x := _difference(start.x, target_start.x)
	var y := _difference(start.y, target_start.y)
	var r := _add(_point(radius), _point(target_radius))
	var dx := _subtract(_difference(finish.x, start.x), _difference(target_finish.x, target_start.x))
	var dy := _subtract(_difference(finish.y, start.y), _difference(target_finish.y, target_start.y))
	if dy.is_point(0.0):
		var horizontal := _axis_contact(x, dx, y, r)
		if horizontal != null:
			return horizontal
	if dx.is_point(0.0):
		var vertical := _axis_contact(y, dy, x, r)
		if vertical != null:
			return vertical
	var r_squared := _square(r)
	var separation := _subtract(_add(_square(x), _square(y)), r_squared)
	if separation.upper <= 0.0:
		return Contact.new(Result.HIT)
	if not is_finite(separation.lower) or separation.lower <= 0.0:
		return Contact.new(Result.UNRESOLVED)
	var projection := _add(_multiply(x, dx), _multiply(y, dy))
	if projection.lower >= 0.0:
		return Contact.new(Result.MISS)
	var speed_squared := _add(_square(dx), _square(dy))
	var cross := _subtract(_multiply(x, dy), _multiply(y, dx))
	var discriminant := _subtract(_multiply(speed_squared, r_squared), _square(cross))
	if discriminant.upper < 0.0:
		return Contact.new(Result.MISS)
	if projection.upper >= 0.0 or not is_finite(discriminant.upper) or discriminant.lower < 0.0:
		return _refine_tangency([x, y, dx, dy, r])
	var root := _enclose(sqrt(discriminant.lower), sqrt(discriminant.upper))
	var divisor := _subtract(root, projection)
	if divisor.lower <= 0.0 or not is_finite(divisor.upper):
		return Contact.new(Result.UNRESOLVED)
	return _contact_on_path(_divide_positive(separation, divisor))


func measure_segment(start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		a: RealmSweep.Point, b: RealmSweep.Point) -> Contact:
	if (not _finite_point(start) or not _finite_point(finish) or not _finite_point(a)
			or not _finite_point(b) or not is_finite(radius) or radius < 0.0):
		return Contact.new(Result.UNRESOLVED)
	if a.x == b.x and _inside_axis(start.y, finish.y, a.y, b.y):
		return _measure_axis(start.x, finish.x, a.x, radius)
	if a.y == b.y and _inside_axis(start.x, finish.x, a.x, b.x):
		return _measure_axis(start.y, finish.y, a.y, radius)
	var first := measure(start, finish, radius, a, a, 0.0)
	if a.x == b.x and a.y == b.y:
		return first
	var last := measure(start, finish, radius, b, b, 0.0)
	var ends := _first_contact(first, last)
	if ends.outcome == Result.HIT and ends.latest == 0.0:
		return ends
	return _first_contact(ends, _segment_side(start, finish, radius, a, b))


## Squared distance to a convex obstacle along a linear path is convex. A
## strictly increasing distance at the start rules out a new entry later.
func departs_circle(start: RealmSweep.Point, finish: RealmSweep.Point, center: RealmSweep.Point) -> bool:
	var x := _difference(start.x, center.x)
	var y := _difference(start.y, center.y)
	var dx := _difference(finish.x, start.x)
	var dy := _difference(finish.y, start.y)
	var derivative := _add(_multiply(x, dx), _multiply(y, dy))
	return derivative.lower > 0.0 or (derivative.is_point(0.0) and (start.x != finish.x or start.y != finish.y))


func departs_segment(start: RealmSweep.Point, finish: RealmSweep.Point,
		a: RealmSweep.Point, b: RealmSweep.Point) -> bool:
	if a.x == b.x and a.y == b.y:
		return departs_circle(start, finish, a)
	var ex := _difference(b.x, a.x)
	var ey := _difference(b.y, a.y)
	var x := _difference(start.x, a.x)
	var y := _difference(start.y, a.y)
	var along := _add(_multiply(ex, x), _multiply(ey, y))
	if along.upper <= 0.0:
		return _recedes_from_segment_end(start, finish, a, ex, ey, false)
	var length_squared := _add(_square(ex), _square(ey))
	if along.lower >= length_squared.upper:
		return _recedes_from_segment_end(start, finish, b, ex, ey, true)
	if along.lower < 0.0 or along.upper > length_squared.lower:
		return false
	var dx := _difference(finish.x, start.x)
	var dy := _difference(finish.y, start.y)
	var cross := _subtract(_multiply(ex, y), _multiply(ey, x))
	var across := _subtract(_multiply(ex, dy), _multiply(ey, dx))
	return (_multiply(cross, across).lower > 0.0
		or (cross.is_point(0.0) and (across.lower > 0.0 or across.upper < 0.0)))


func _recedes_from_segment_end(start: RealmSweep.Point, finish: RealmSweep.Point, endpoint: RealmSweep.Point,
		ex: Interval, ey: Interval, beyond_last: bool) -> bool:
	var x := _difference(start.x, endpoint.x)
	var y := _difference(start.y, endpoint.y)
	var dx := _difference(finish.x, start.x)
	var dy := _difference(finish.y, start.y)
	var derivative := _add(_multiply(x, dx), _multiply(y, dy))
	if derivative.lower > 0.0:
		return true
	var along_speed := _add(_multiply(ex, dx), _multiply(ey, dy))
	return (derivative.is_point(0.0) and (start.x != finish.x or start.y != finish.y)
		and (along_speed.lower >= 0.0 if beyond_last else along_speed.upper <= 0.0))


func _segment_side(start: RealmSweep.Point, finish: RealmSweep.Point, radius: float,
		a: RealmSweep.Point, b: RealmSweep.Point) -> Contact:
	var ex := _difference(b.x, a.x)
	var ey := _difference(b.y, a.y)
	var norm_squared := _add(_square(ex), _square(ey))
	if norm_squared.lower <= 0.0 or not is_finite(norm_squared.upper):
		return Contact.new(Result.UNRESOLVED)
	var x := _difference(start.x, a.x)
	var y := _difference(start.y, a.y)
	var along := _add(_multiply(ex, x), _multiply(ey, y))
	var cross := _subtract(_multiply(ex, y), _multiply(ey, x))
	var norm := _enclose(sqrt(norm_squared.lower), sqrt(norm_squared.upper))
	var limit := _multiply(_point(radius), norm)
	if cross.lower >= -limit.lower and cross.upper <= limit.lower:
		var initial := _within_segment(along, norm_squared)
		# When starting inside the strip but beyond an endpoint, any capsule
		# entry passes through that endpoint's disk before reaching the side.
		return initial
	if cross.lower <= limit.upper and cross.upper >= -limit.upper:
		return Contact.new(Result.UNRESOLVED)
	var dx := _difference(finish.x, start.x)
	var dy := _difference(finish.y, start.y)
	var across := _subtract(_multiply(ex, dy), _multiply(ey, dx))
	if cross.upper < -limit.upper:
		cross = Interval.new(-cross.upper, -cross.lower)
		across = Interval.new(-across.upper, -across.lower)
	if across.lower >= 0.0:
		return Contact.new(Result.MISS)
	if across.upper >= 0.0:
		return Contact.new(Result.UNRESOLVED)
	var time := _contact_on_path(_divide_positive(_subtract(cross, limit), Interval.new(-across.upper, -across.lower)))
	if time.outcome != Result.HIT:
		return time
	var speed_along := _add(_multiply(ex, dx), _multiply(ey, dy))
	var projection := _add(along, _multiply(speed_along, Interval.new(time.earliest, time.latest)))
	var within := _within_segment(projection, norm_squared)
	return time if within.outcome == Result.HIT else within


func _measure_axis(start: float, finish: float, boundary: float, radius: float) -> Contact:
	return measure(RealmSweep.Point.new(start, 0.0), RealmSweep.Point.new(finish, 0.0), radius,
		RealmSweep.Point.new(boundary, 0.0), RealmSweep.Point.new(boundary, 0.0), 0.0)


static func _inside_axis(start: float, finish: float, a: float, b: float) -> bool:
	return minf(start, finish) >= minf(a, b) and maxf(start, finish) <= maxf(a, b)


static func _within_segment(along: Interval, norm_squared: Interval) -> Contact:
	if along.upper < 0.0 or along.lower > norm_squared.upper:
		return Contact.new(Result.MISS)
	if along.lower >= 0.0 and along.upper <= norm_squared.lower:
		return Contact.new(Result.HIT)
	return Contact.new(Result.UNRESOLVED)


static func _first_contact(a: Contact, b: Contact) -> Contact:
	if a.outcome == Result.MISS or (b.outcome == Result.HIT and b.latest == 0.0):
		return b
	if b.outcome == Result.MISS or (a.outcome == Result.HIT and a.latest == 0.0):
		return a
	if a.outcome != Result.HIT or b.outcome != Result.HIT:
		return Contact.new(Result.UNRESOLVED)
	match a.order_against(b):
		Order.BEFORE, Order.SAME:
			return a
		Order.AFTER:
			return b
	return Contact.new(Result.HIT, minf(a.earliest, b.earliest), minf(a.latest, b.latest))


func _divide_positive(numerator: Interval, denominator: Interval) -> Interval:
	return _enclose(maxf(0.0, numerator.lower) / denominator.upper, numerator.upper / denominator.lower)


static func _contact_on_path(time: Interval) -> Contact:
	if time.lower > 1.0:
		return Contact.new(Result.MISS)
	if time.upper > 1.0 or not is_finite(time.upper):
		return Contact.new(Result.UNRESOLVED)
	return Contact.new(Result.HIT, maxf(0.0, time.lower), time.upper)


## Collinear roots reduce to an exact ratio when the input differences fit a
## scalar. Compare cross-products on the rare overlapping interval path.
func _axis_contact(position: Interval, advance: Interval, perpendicular: Interval, radius: Interval) -> Contact:
	if perpendicular.is_point(0.0):
		return _axis_hit(position, advance, radius)
	if perpendicular.lower != perpendicular.upper or radius.lower != radius.upper:
		return null
	var offset := absf(perpendicular.lower)
	if offset > radius.lower:
		return Contact.new(Result.MISS)
	if offset == radius.lower:
		return _axis_hit(position, advance, _point(0.0))
	return null


func _axis_hit(position: Interval, advance: Interval, radius: Interval) -> Contact:
	if position.lower != position.upper or advance.lower != advance.upper or radius.lower != radius.upper:
		return null
	if absf(position.lower) <= radius.lower:
		return Contact.new(Result.HIT)
	if (position.lower < 0.0) == (advance.lower < 0.0) or advance.lower == 0.0:
		return Contact.new(Result.MISS)
	var gap := _difference(absf(position.lower), radius.lower)
	var speed := absf(advance.lower)
	if gap.lower != gap.upper or gap.lower <= 0.0 or not is_finite(speed):
		return null
	return _exact_ratio_hit(gap.lower, speed)


## In units at a common binary scale, the small operands have an exact int64
## determinant. This resolves zero discriminants without subtracting doubles.
func _refine_tangency(operands: Array[Interval]) -> Contact:
	const SAFE_COORDINATE := 32767.0
	const MAX_REFINEMENT_SCALE := 1024
	for operand: Interval in operands:
		if operand.lower != operand.upper or not is_finite(operand.lower):
			return Contact.new(Result.UNRESOLVED)
	var integers := PackedInt64Array()
	integers.resize(operands.size())
	var scale := 1
	while scale <= MAX_REFINEMENT_SCALE:
		var integral := true
		for index: int in operands.size():
			var value := operands[index].lower * scale
			if absf(value) > SAFE_COORDINATE:
				return Contact.new(Result.UNRESOLVED)
			integers[index] = int(value)
			integral = integral and float(integers[index]) == value
		if integral:
			return _classify_integer_tangent(integers)
		scale <<= 1
	return Contact.new(Result.UNRESOLVED)


func _classify_integer_tangent(values: PackedInt64Array) -> Contact:
	var speed_squared := values[2] * values[2] + values[3] * values[3]
	var approaching := -(values[0] * values[2] + values[1] * values[3])
	if speed_squared == 0 or approaching <= 0:
		return Contact.new(Result.MISS)
	var cross := values[0] * values[3] - values[1] * values[2]
	var discriminant := speed_squared * values[4] * values[4] - cross * cross
	if discriminant < 0:
		return Contact.new(Result.MISS)
	if discriminant == 0:
		return _exact_ratio_hit(float(approaching), float(speed_squared))
	return Contact.new(Result.UNRESOLVED)


func _exact_ratio_hit(distance: float, speed: float) -> Contact:
	if distance > speed:
		return Contact.new(Result.MISS)
	var rounded := distance / speed
	var time := _enclose(rounded, rounded)
	var contact := Contact.new(Result.HIT, maxf(0.0, time.lower), minf(1.0, time.upper))
	contact._exact_ratio = PackedFloat64Array([distance, speed])
	return contact


static func _order_fractions(a: PackedFloat64Array, b: PackedFloat64Array) -> Order:
	var scratch := PackedByteArray()
	scratch.resize(8)
	var left := _binary_product(a[0], b[1], scratch)
	var right := _binary_product(b[0], a[1], scratch)
	for index: int in left.size():
		if left[index] < right[index]:
			return Order.BEFORE
		if left[index] > right[index]:
			return Order.AFTER
	return Order.SAME


static func _binary_product(a: float, b: float, scratch: PackedByteArray) -> PackedInt64Array:
	const LIMB_BITS := 27
	const MASK := (1 << LIMB_BITS) - 1
	var first := _binary_parts(a, scratch)
	var second := _binary_parts(b, scratch)
	var exponent := first[0] + second[0]
	var low := (first[1] & MASK) * (second[1] & MASK)
	var middle := ((first[1] >> LIMB_BITS) * (second[1] & MASK)
		+ (second[1] >> LIMB_BITS) * (first[1] & MASK) + (low >> LIMB_BITS))
	var high := (first[1] >> LIMB_BITS) * (second[1] >> LIMB_BITS) + (middle >> LIMB_BITS)
	low &= MASK
	middle &= MASK
	# Normalized factors have 53 bits. Shift a 105-bit product by one to
	# compare both products at 106 bits, then compare exponent and limbs.
	if high < (1 << 51):
		exponent -= 1
		high = (high << 1) | (middle >> (LIMB_BITS - 1))
		middle = ((middle << 1) | (low >> (LIMB_BITS - 1))) & MASK
		low = (low << 1) & MASK
	return PackedInt64Array([exponent, high, middle, low])


static func _binary_parts(value: float, scratch: PackedByteArray) -> PackedInt64Array:
	scratch.encode_double(0, value)
	var bits := scratch.decode_s64(0)
	var exponent := (bits >> 52) & 2047
	var fraction := bits & ((1 << 52) - 1)
	if exponent > 0:
		return PackedInt64Array([exponent, fraction | (1 << 52)])
	exponent = 1
	while fraction < (1 << 52):
		fraction <<= 1
		exponent -= 1
	return PackedInt64Array([exponent, fraction])


func _difference(a: float, b: float) -> Interval:
	var rounded := a - b
	if not is_finite(rounded):
		return Interval.new(-INF, INF)
	# Error-free TwoSum transformation for the exactness of the difference.
	var back := rounded - a
	var remainder := (a - (rounded - back)) + (-b - back)
	return _point(rounded) if remainder == 0.0 else _enclose(rounded, rounded)


func _add(a: Interval, b: Interval) -> Interval:
	if a.lower == a.upper and b.lower == b.upper:
		return _difference(a.lower, -b.lower)
	if a.is_point(0.0):
		return b
	if b.is_point(0.0):
		return a
	return _enclose(a.lower + b.lower, a.upper + b.upper)


func _subtract(a: Interval, b: Interval) -> Interval:
	if a.lower == a.upper and b.lower == b.upper:
		return _difference(a.lower, b.lower)
	if b.is_point(0.0):
		return a
	return _enclose(a.lower - b.upper, a.upper - b.lower)


func _multiply(a: Interval, b: Interval) -> Interval:
	if a.is_point(0.0) or b.is_point(0.0):
		return _point(0.0)
	if a.is_point(1.0):
		return b
	if b.is_point(1.0):
		return a
	var first := a.lower * b.lower
	var second := a.lower * b.upper
	var third := a.upper * b.lower
	var fourth := a.upper * b.upper
	return _enclose(minf(minf(first, second), minf(third, fourth)), maxf(maxf(first, second), maxf(third, fourth)))


func _square(value: Interval) -> Interval:
	if value.is_point(0.0) or value.is_point(1.0) or value.is_point(-1.0):
		return _point(value.lower * value.lower)
	var first := value.lower * value.lower
	var second := value.upper * value.upper
	var smallest := minf(first, second) if value.lower > 0.0 or value.upper < 0.0 else 0.0
	var bounds := _enclose(smallest, maxf(first, second))
	bounds.lower = maxf(bounds.lower, 0.0)
	return bounds


func _enclose(lower: float, upper: float) -> Interval:
	if not is_finite(lower) or not is_finite(upper):
		return Interval.new(-INF, INF)
	return Interval.new(RealmBounds.adjacent(lower, false, _bits), RealmBounds.adjacent(upper, true, _bits))


static func _point(value: float) -> Interval:
	return Interval.new(value, value)


static func _finite_point(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
