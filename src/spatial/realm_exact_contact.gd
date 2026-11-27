extends RefCounted
## Rare-path predicates for the first root of a swept contact. Binary64 inputs
## are exact dyadics. Coefficients use a common integer unit per path.

class Integer:
	const BITS := 30
	const MASK := (1 << BITS) - 1

	var direction: int
	var words: PackedInt32Array

	static func make(polarity: int, digits: PackedInt32Array) -> Integer:
		while not digits.is_empty() and digits[-1] == 0:
			digits.resize(digits.size() - 1)
		var result := Integer.new()
		result.direction = 0 if digits.is_empty() else polarity
		result.words = digits
		return result

	static func mantissa(polarity: int, significant: int, shift: int) -> Integer:
		@warning_ignore("integer_division")
		var first_word := shift / BITS
		var digits := PackedInt32Array()
		digits.resize(first_word)
		var offset := shift % BITS
		var carry := 0
		while significant != 0:
			var part := ((significant & MASK) << offset) | carry
			digits.append(part & MASK)
			carry = part >> BITS
			significant >>= BITS
		digits.append(carry)
		return make(polarity, digits)

	func opposite() -> Integer:
		var result := Integer.new()
		result.direction = -direction
		result.words = words
		return result

	func subtract(other: Integer) -> Integer:
		return add(other.opposite())

	func add(other: Integer) -> Integer:
		if direction == 0:
			return other
		if other.direction == 0:
			return self
		if direction == other.direction:
			var digits := PackedInt32Array()
			var carry := 0
			for index: int in maxi(words.size(), other.words.size()):
				var total := carry
				if index < words.size():
					total += words[index]
				if index < other.words.size():
					total += other.words[index]
				digits.append(total & MASK)
				carry = total >> BITS
			digits.append(carry)
			return make(direction, digits)
		var order := compare_magnitude(other)
		if order == 0:
			return Integer.new()
		var larger := self if order > 0 else other
		var smaller := other if order > 0 else self
		var digits := PackedInt32Array()
		var borrow := 0
		for index: int in larger.words.size():
			var difference := larger.words[index] - borrow
			if index < smaller.words.size():
				difference -= smaller.words[index]
			digits.append(difference & MASK)
			borrow = int(difference < 0)
		return make(larger.direction, digits)

	func multiply(other: Integer) -> Integer:
		if direction == 0 or other.direction == 0:
			return Integer.new()
		var digits := PackedInt32Array()
		digits.resize(words.size() + other.words.size())
		for first: int in words.size():
			var carry := 0
			for second: int in other.words.size():
				var index := first + second
				var total := int(words[first]) * other.words[second] + digits[index] + carry
				digits[index] = total & MASK
				carry = total >> BITS
			digits[first + other.words.size()] = carry
		return make(direction * other.direction, digits)

	func compare_magnitude(other: Integer) -> int:
		if words.size() != other.words.size():
			return signi(words.size() - other.words.size())
		for index: int in range(words.size() - 1, -1, -1):
			if words[index] != other.words[index]:
				return signi(words[index] - other.words[index])
		return 0


	static func from_doubles(values: PackedFloat64Array) -> Array[Integer]:
		const SIGNIFICANT_MASK := (1 << 52) - 1
		var scratch := PackedByteArray()
		scratch.resize(8)
		var encodings := PackedInt64Array()
		var common_exponent := 2047
		for value: float in values:
			scratch.encode_double(0, value)
			var bits := scratch.decode_s64(0)
			encodings.append(bits)
			if value != 0.0:
				common_exponent = mini(common_exponent, maxi(1, (bits >> 52) & 2047))
		var result: Array[Integer] = []
		for bits: int in encodings:
			var exponent := (bits >> 52) & 2047
			var significant := bits & SIGNIFICANT_MASK
			if exponent > 0:
				significant |= 1 << 52
			if significant == 0:
				result.append(Integer.new())
			else:
				result.append(Integer.mantissa(-1 if bits < 0 else 1, significant,
					maxi(1, exponent) - common_exponent))
		return result


class Root:
	# The path equation is speed * t² - 2 * projection * t + separation.
	var speed: Integer
	var projection: Integer
	var separation: Integer
	var discriminant: Integer

	func first_contact() -> bool:
		return (speed.direction > 0 and projection.direction > 0 and discriminant.direction >= 0
			and evaluate_linear(speed, speed.opposite()) <= 0)

	## Compare this first root against another first root. Past the other
	## vertex we are after its entry. On the near side the polynomial's
	## sign gives the order, including shared roots of different equations.
	func compare(other: Root) -> int:
		if evaluate_linear(other.speed, other.projection.opposite()) > 0:
			return 1
		return -evaluate_path(other)

	## Sign of the other path's squared separation minus squared radius at
	## this exact instant. Eliminate t² using this root's own equation.
	func evaluate_path(other: Root) -> int:
		var slope := other.speed.multiply(projection).subtract(speed.multiply(other.projection))
		var offset := speed.multiply(other.separation).subtract(other.speed.multiply(separation))
		return evaluate_linear(slope.add(slope), offset)

	## Sign of slope * t + offset at the smaller root.
	func evaluate_linear(slope: Integer, offset: Integer) -> int:
		var left := speed.multiply(offset).add(slope.multiply(projection))
		if discriminant.direction == 0 or slope.direction == 0:
			return left.direction
		if left.direction != slope.direction:
			return -slope.direction
		var left_squared := left.multiply(left)
		var right_squared := slope.multiply(slope).multiply(discriminant)
		return left.direction * left_squared.compare_magnitude(right_squared)

	func compare_time(time: float) -> int:
		var numbers := Integer.from_doubles(PackedFloat64Array([1.0, time]))
		return evaluate_linear(numbers[0], numbers[1].opposite())


static func path(values: PackedFloat64Array) -> Root:
	var numbers := Integer.from_doubles(values)
	var x := numbers[0].subtract(numbers[4])
	var y := numbers[1].subtract(numbers[5])
	var dx := numbers[2].subtract(numbers[0]).subtract(numbers[6].subtract(numbers[4]))
	var dy := numbers[3].subtract(numbers[1]).subtract(numbers[7].subtract(numbers[5]))
	var radius := numbers[8].add(numbers[9])
	var speed := dx.multiply(dx).add(dy.multiply(dy))
	var projection := x.multiply(dx).add(y.multiply(dy)).opposite()
	var separation := x.multiply(x).add(y.multiply(y)).subtract(radius.multiply(radius))
	return _root(speed, projection, separation)


## Side entry starts outside the infinite strip. Paths that start inside the
## strip and enter through a finite end first intersect its endpoint circle.
static func segment_side(values: PackedFloat64Array) -> Root:
	var numbers := Integer.from_doubles(values)
	var x := numbers[0].subtract(numbers[4])
	var y := numbers[1].subtract(numbers[5])
	var dx := numbers[2].subtract(numbers[0])
	var dy := numbers[3].subtract(numbers[1])
	var ex := numbers[6].subtract(numbers[4])
	var ey := numbers[7].subtract(numbers[5])
	var radius := numbers[8]
	var length := ex.multiply(ex).add(ey.multiply(ey))
	var along := ex.multiply(x).add(ey.multiply(y))
	var lateral := ex.multiply(y).subtract(ey.multiply(x))
	var separation := lateral.multiply(lateral).subtract(radius.multiply(radius).multiply(length))
	if separation.direction <= 0:
		if along.direction >= 0 and along.subtract(length).direction <= 0:
			return ratio(PackedFloat64Array([0.0, 1.0]))
		return null
	var across := ex.multiply(dy).subtract(ey.multiply(dx))
	var root := _root(across.multiply(across), lateral.multiply(across).opposite(), separation)
	if not root.first_contact():
		return null
	var along_speed := ex.multiply(dx).add(ey.multiply(dy))
	if root.evaluate_linear(along_speed, along) < 0 or root.evaluate_linear(along_speed, along.subtract(length)) > 0:
		return null
	return root


static func ratio(values: PackedFloat64Array) -> Root:
	var numbers := Integer.from_doubles(values)
	return _root(numbers[1].multiply(numbers[1]), numbers[0].multiply(numbers[1]),
		numbers[0].multiply(numbers[0]))


static func _root(speed: Integer, projection: Integer, separation: Integer) -> Root:
	var result := Root.new()
	result.speed = speed
	result.projection = projection
	result.separation = separation
	result.discriminant = projection.multiply(projection).subtract(speed.multiply(separation))
	return result
