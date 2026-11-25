class_name ReplicationChunks
extends RefCounted
## A bounded reliable transfer of one already-filtered view or baseline.
## Only a complete transfer reaches the ordinary projection schema decoder.

enum Result { WAITING, COMPLETE, STALE, INVALID }

const MAX_ASSEMBLED := 128 * 1024
const HEADER_SIZE := 15
const PART_BYTES := ReplicationMessage.MAX_BODY - HEADER_SIZE

class Receipt:
	var result: Result
	var body: PackedByteArray

	func _init(verdict: Result, assembled: PackedByteArray = PackedByteArray()) -> void:
		result = verdict
		body = assembled

var _generation: int
var _transfer: int
var _next: int
var _size: int
var _pending := PackedByteArray()


static func split(kind: ReplicationMessage.Kind, transfer: int, body: PackedByteArray) -> Array[PackedByteArray]:
	var parts: Array[PackedByteArray] = []
	if not _valid_kind(kind) or transfer <= 0 or body.is_empty() or body.size() > MAX_ASSEMBLED:
		return parts
	if body.size() <= ReplicationMessage.MAX_BODY:
		parts.append(ReplicationMessage.pack(kind, body))
		return parts
	var index := 0
	for start: int in range(0, body.size(), PART_BYTES):
		var part := PackedByteArray()
		part.resize(HEADER_SIZE)
		part[0] = kind
		part.encode_s64(1, transfer)
		part.encode_u32(9, body.size())
		part.encode_u16(13, index)
		part.append_array(body.slice(start, start + PART_BYTES))
		parts.append(ReplicationMessage.pack(ReplicationMessage.Kind.SNAPSHOT_PART, part))
		index += 1
	return parts


static func payload_kind(message: ReplicationMessage) -> int:
	if (message == null or message.kind != ReplicationMessage.Kind.SNAPSHOT_PART or message.body.size() <= HEADER_SIZE
			or not _valid_kind(message.body[0])):
		return -1
	return message.body[0]


func accept(generation: int, message: ReplicationMessage, expected: ReplicationMessage.Kind) -> Receipt:
	if generation <= 0 or payload_kind(message) != expected:
		return Receipt.new(Result.INVALID)
	var part := message.body
	var transfer := part.decode_s64(1)
	var size := part.decode_u32(9)
	var index := part.decode_u16(13)
	var start := index * PART_BYTES
	if (transfer <= 0 or size <= ReplicationMessage.MAX_BODY or size > MAX_ASSEMBLED or start >= size
			or part.size() != HEADER_SIZE + mini(PART_BYTES, size - start)):
		return Receipt.new(Result.INVALID)
	if generation < _generation or (generation == _generation and transfer < _transfer):
		return Receipt.new(Result.STALE)
	if generation != _generation or transfer != _transfer:
		if index != 0:
			return Receipt.new(Result.INVALID)
		_generation = generation
		_transfer = transfer
		_size = size
		_next = 0
		_pending = PackedByteArray()
	if index < _next:
		return Receipt.new(Result.STALE)
	if index != _next or size != _size:
		_size = 0
		_pending = PackedByteArray()
		return Receipt.new(Result.INVALID)
	_pending.append_array(part.slice(HEADER_SIZE))
	_next += 1
	if _pending.size() < _size:
		return Receipt.new(Result.WAITING)
	var completed := _pending
	_size = 0
	_pending = PackedByteArray()
	return Receipt.new(Result.COMPLETE, completed)


static func _valid_kind(kind: int) -> bool:
	return kind in [ReplicationMessage.Kind.BASELINE, ReplicationMessage.Kind.VIEW]
