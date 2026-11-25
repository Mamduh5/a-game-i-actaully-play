class_name NativeSessionFrame
extends RefCounted
## Bounded primitive envelope. Higher layers validate sender, state and message payload.

enum Kind { ADMISSION = 1, RELIABLE = 2, SEQUENCED = 3 }

const VERSION := 1
const HEADER_SIZE := 20
const MAX_PAYLOAD := 4096
const CHANNEL_COUNT := 3

var kind: Kind
var generation: int
var sequence: int
var payload: PackedByteArray


static func pack(message_kind: Kind, epoch: int, id: int, bytes: PackedByteArray) -> PackedByteArray:
	if channel(message_kind) < 0 or epoch < 1 or id < 1 or bytes.is_empty() or bytes.size() > MAX_PAYLOAD:
		return PackedByteArray()
	var frame := PackedByteArray()
	frame.resize(HEADER_SIZE)
	frame[0] = VERSION
	frame[1] = message_kind
	frame.encode_u16(2, bytes.size())
	frame.encode_s64(4, epoch)
	frame.encode_s64(12, id)
	frame.append_array(bytes)
	return frame


static func read(bytes: PackedByteArray, received_channel: int) -> NativeSessionFrame:
	if bytes.size() < HEADER_SIZE or bytes.size() > HEADER_SIZE + MAX_PAYLOAD or bytes[0] != VERSION:
		return null
	if bytes[1] < Kind.ADMISSION or bytes[1] > Kind.SEQUENCED:
		return null
	var message_kind := bytes[1] as Kind
	if received_channel < 0 or channel(message_kind) != received_channel:
		return null
	var size := bytes.decode_u16(2)
	var epoch := bytes.decode_s64(4)
	var id := bytes.decode_s64(12)
	if size == 0 or HEADER_SIZE + size != bytes.size() or epoch < 1 or id < 1:
		return null
	var frame := NativeSessionFrame.new()
	frame.kind = message_kind
	frame.generation = epoch
	frame.sequence = id
	frame.payload = bytes.slice(HEADER_SIZE)
	return frame


static func channel(message_kind: Kind) -> int:
	match message_kind:
		Kind.ADMISSION:
			return 0
		Kind.RELIABLE:
			return 1
		Kind.SEQUENCED:
			return 2
	return -1
