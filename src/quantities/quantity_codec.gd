class_name QuantityCodec
extends RefCounted
## WP04 candidate binary format. Header precedes the bounded ASCII magnitude.

const VERSION := 1
const HEADER_SIZE := 8


static func encode(amount: Quantity) -> PackedByteArray:
	var digits := amount.magnitude_text().to_ascii_buffer()
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE)
	bytes[0] = VERSION
	bytes[1] = int(amount.sign_value < 0)
	bytes.encode_u16(2, amount.scale)
	bytes.encode_u32(4, digits.size())
	bytes.append_array(digits)
	return bytes


## Callers validate their outer frame length before allocating the frame itself.
static func decode(bytes: PackedByteArray) -> Quantity:
	if bytes.size() < HEADER_SIZE or bytes[0] != VERSION or bytes[1] > 1:
		return null
	var scale := bytes.decode_u16(2)
	var size := bytes.decode_u32(4)
	if not _valid_header(scale, size) or bytes.size() != HEADER_SIZE + size:
		return null
	for i: int in range(HEADER_SIZE, bytes.size()):
		if bytes[i] < 48 or bytes[i] > 57:
			return null
	return Quantity.from_canonical(bytes[1] == 1, scale, bytes.slice(HEADER_SIZE).get_string_from_ascii())


## One framed value. Reject declared lengths before reading a payload.
static func read_value(file: FileAccess) -> Quantity:
	var header := file.get_buffer(HEADER_SIZE)
	if header.size() != HEADER_SIZE or header[0] != VERSION or header[1] > 1:
		return null
	var size := header.decode_u32(4)
	if not _valid_header(header.decode_u16(2), size):
		return null
	var payload := file.get_buffer(size)
	if payload.size() != size:
		return null
	header.append_array(payload)
	return decode(header)


## Decodes a caller-defined sequence of framed quantities, with no trailing bytes.
static func decode_fields(bytes: PackedByteArray, start: int, count: int) -> Array[Quantity]:
	var fields: Array[Quantity] = []
	var at := start
	if at < 0 or at > bytes.size() or count < 1:
		return []
	for _index: int in count:
		if bytes.size() - at < HEADER_SIZE:
			return []
		var length := bytes.decode_u32(at + 4)
		if not _valid_header(bytes.decode_u16(at + 2), length) or length > bytes.size() - at - HEADER_SIZE:
			return []
		var end := at + HEADER_SIZE + length
		var amount := decode(bytes.slice(at, end))
		if amount == null:
			return []
		fields.append(amount)
		at = end
	if at != bytes.size():
		return []
	return fields


static func _valid_header(scale: int, size: int) -> bool:
	return scale <= Quantity.MAX_SCALE and size > 0 and size <= Quantity.MAX_DIGITS
