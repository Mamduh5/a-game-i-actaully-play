class_name MovementSnapshot
extends RefCounted
## A complete replaceable movement state tied to one reliable geometry baseline.

const VERSION := 1
const SIZE := 98

var epoch: int
var baseline: int
var revision: int
var serial: int
var tick: int
var acknowledged: int
var position: RealmSweep.Point
var movement: PlayerCommand
var speed: float
var radius: float
var permits_prediction := true
var forced_correction: bool


func valid() -> bool:
	return (epoch > 0 and baseline > 0 and revision >= 0 and serial > 0 and tick >= 0
		and tick <= RunAuthority.MAX_TICK and acknowledged >= 0 and position != null
		and is_finite(position.x) and is_finite(position.y) and MovementFrame.is_voluntary(movement)
		and is_finite(speed) and speed >= 0.0 and is_finite(radius) and radius > 0.0)


func pack() -> PackedByteArray:
	if not valid():
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(SIZE)
	bytes[0] = VERSION
	bytes[1] = int(permits_prediction) | (int(forced_correction) << 1) | (4 if movement.action == PlayerCommand.MOVE_TO else 0)
	bytes.encode_s64(2, epoch)
	bytes.encode_s64(10, baseline)
	bytes.encode_s64(18, revision)
	bytes.encode_s64(26, serial)
	bytes.encode_s64(34, tick)
	bytes.encode_s64(42, acknowledged)
	bytes.encode_double(50, position.x)
	bytes.encode_double(58, position.y)
	bytes.encode_double(66, movement.x)
	bytes.encode_double(74, movement.y)
	bytes.encode_double(82, speed)
	bytes.encode_double(90, radius)
	return bytes


static func read(bytes: PackedByteArray) -> MovementSnapshot:
	if bytes.size() != SIZE or bytes[0] != VERSION or bytes[1] > 7:
		return null
	var state := MovementSnapshot.new()
	var flags := int(bytes[1])
	state.permits_prediction = (flags & 1) != 0
	state.forced_correction = (flags & 2) != 0
	var action := PlayerCommand.MOVE_TO if (flags & 4) != 0 else PlayerCommand.MOVE_AXES
	state.epoch = bytes.decode_s64(2)
	state.baseline = bytes.decode_s64(10)
	state.revision = bytes.decode_s64(18)
	state.serial = bytes.decode_s64(26)
	state.tick = bytes.decode_s64(34)
	state.acknowledged = bytes.decode_s64(42)
	state.position = RealmSweep.Point.new(bytes.decode_double(50), bytes.decode_double(58))
	state.movement = PlayerCommand.new(action, bytes.decode_double(66), bytes.decode_double(74))
	state.speed = bytes.decode_double(82)
	state.radius = bytes.decode_double(90)
	return state if state.valid() else null
