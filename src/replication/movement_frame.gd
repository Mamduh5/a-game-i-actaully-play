class_name MovementFrame
extends RefCounted
## Replaceable voluntary movement. Run and seat IDs are bound by the host.

const VERSION := 1
const SIZE := 42

var epoch: int
var baseline: int
var sequence: int
var command: PlayerCommand


static func is_voluntary(value: PlayerCommand) -> bool:
	return (value != null and value.action in [PlayerCommand.MOVE_AXES, PlayerCommand.MOVE_TO] and value.valid())


static func pack(epoch_id: int, baseline_id: int, input_sequence: int, input: PlayerCommand) -> PackedByteArray:
	if epoch_id < 1 or baseline_id < 1 or input_sequence < 1 or not is_voluntary(input):
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(SIZE)
	bytes[0] = VERSION
	bytes[1] = 1 if input.action == PlayerCommand.MOVE_AXES else 2
	bytes.encode_s64(2, epoch_id)
	bytes.encode_s64(10, baseline_id)
	bytes.encode_s64(18, input_sequence)
	bytes.encode_double(26, input.x)
	bytes.encode_double(34, input.y)
	return bytes


static func read(bytes: PackedByteArray) -> MovementFrame:
	if bytes.size() != SIZE or bytes[0] != VERSION or bytes[1] not in [1, 2]:
		return null
	var input := PlayerCommand.new(PlayerCommand.MOVE_AXES if bytes[1] == 1 else PlayerCommand.MOVE_TO,
		bytes.decode_double(26), bytes.decode_double(34))
	var envelope := MovementFrame.new()
	envelope.epoch = bytes.decode_s64(2)
	envelope.baseline = bytes.decode_s64(10)
	envelope.sequence = bytes.decode_s64(18)
	if envelope.epoch < 1 or envelope.baseline < 1 or envelope.sequence < 1 or not is_voluntary(input):
		return null
	envelope.command = input
	return envelope
