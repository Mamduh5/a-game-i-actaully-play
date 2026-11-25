class_name RealmBounds
extends RefCounted
## Axis-aligned realm bounds with scalar double coordinates. Edges are inclusive.

var west: float:
	get: return _west
var north: float:
	get: return _north
var east: float:
	get: return _east
var south: float:
	get: return _south

var _west: float
var _north: float
var _east: float
var _south: float


static func from_edges(x0: float, y0: float, x1: float, y1: float) -> RealmBounds:
	if (not is_finite(x0) or not is_finite(y0) or not is_finite(x1) or not is_finite(y1)
			or x1 < x0 or y1 < y0):
		return null
	var result := RealmBounds.new()
	result._west = x0
	result._north = y0
	result._east = x1
	result._south = y1
	return result


static func from_sweep(x0: float, y0: float, x1: float, y1: float, radius: float) -> RealmBounds:
	if (not is_finite(x0) or not is_finite(y0) or not is_finite(x1) or not is_finite(y1)
			or not is_finite(radius) or radius < 0.0):
		return null
	if radius == 0.0:
		return from_edges(minf(x0, x1), minf(y0, y1), maxf(x0, x1), maxf(y0, y1))
	var scratch := PackedByteArray()
	scratch.resize(8)
	return from_edges(_outward(minf(x0, x1) - radius, false, scratch),
		_outward(minf(y0, y1) - radius, false, scratch),
		_outward(maxf(x0, x1) + radius, true, scratch),
		_outward(maxf(y0, y1) + radius, true, scratch))


func overlaps(other: RealmBounds) -> bool:
	return _west <= other.east and _east >= other.west and _north <= other.south and _south >= other.north


## One adjacent IEEE double beyond the rounded radius expansion.
static func _outward(value: float, upward: bool, scratch: PackedByteArray) -> float:
	if not is_finite(value):
		return value
	if value == 0.0:
		scratch.encode_s64(0, 1)
		var smallest := scratch.decode_double(0)
		return smallest if upward else -smallest
	scratch.encode_double(0, value)
	var step := 1 if (value > 0.0) == upward else -1
	scratch.encode_s64(0, scratch.decode_s64(0) + step)
	return scratch.decode_double(0)
