class_name MovementBaseline
extends RefCounted
## A reliable reset containing only the collision edges disclosed to this guest.

const VERSION := 1
const HEADER_SIZE := 4
const EDGE_SIZE := 32
const MAX_REALM_BYTES := 64

var realm: StringName
var state: MovementSnapshot
var blockers: Array[GuestMovement.Blocker] = []


func pack() -> PackedByteArray:
	var name_bytes := String(realm).to_utf8_buffer()
	var state_bytes := state.pack() if state != null else PackedByteArray()
	var size := HEADER_SIZE + name_bytes.size() + state_bytes.size() + blockers.size() * EDGE_SIZE
	if (not _valid_name(name_bytes) or state_bytes.is_empty() or size > ReplicationMessage.MAX_BODY):
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE)
	bytes[0] = VERSION
	bytes[1] = name_bytes.size()
	bytes.encode_u16(2, blockers.size())
	bytes.append_array(name_bytes)
	bytes.append_array(state_bytes)
	var offset := bytes.size()
	bytes.resize(size)
	for edge: GuestMovement.Blocker in blockers:
		if edge == null or not _valid_point(edge.first) or not _valid_point(edge.last):
			return PackedByteArray()
		bytes.encode_double(offset, edge.first.x)
		bytes.encode_double(offset + 8, edge.first.y)
		bytes.encode_double(offset + 16, edge.last.x)
		bytes.encode_double(offset + 24, edge.last.y)
		offset += EDGE_SIZE
	return bytes


static func read(bytes: PackedByteArray) -> MovementBaseline:
	if bytes.size() < HEADER_SIZE + MovementSnapshot.SIZE or bytes.size() > ReplicationMessage.MAX_BODY or bytes[0] != VERSION:
		return null
	var state_start := HEADER_SIZE + int(bytes[1])
	var edge_start := state_start + MovementSnapshot.SIZE
	var count := bytes.decode_u16(2)
	if edge_start + count * EDGE_SIZE != bytes.size():
		return null
	var name_bytes := bytes.slice(HEADER_SIZE, state_start)
	if not _valid_name(name_bytes):
		return null
	var reset := MovementBaseline.new()
	reset.realm = StringName(name_bytes.get_string_from_ascii())
	reset.state = MovementSnapshot.read(bytes.slice(state_start, edge_start))
	if reset.state == null:
		return null
	for offset: int in range(edge_start, bytes.size(), EDGE_SIZE):
		var edge := GuestMovement.Blocker.new()
		edge.first = RealmSweep.Point.new(bytes.decode_double(offset), bytes.decode_double(offset + 8))
		edge.last = RealmSweep.Point.new(bytes.decode_double(offset + 16), bytes.decode_double(offset + 24))
		if not _valid_point(edge.first) or not _valid_point(edge.last):
			return null
		reset.blockers.append(edge)
	return reset


static func _valid_name(bytes: PackedByteArray) -> bool:
	if bytes.is_empty() or bytes.size() > MAX_REALM_BYTES:
		return false
	for character: int in bytes:
		if not (character >= 33 and character <= 126):
			return false
	return true


static func _valid_point(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
