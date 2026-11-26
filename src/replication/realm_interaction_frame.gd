class_name RealmInteractionFrame
extends RefCounted
## A reliable click refers to the last confirmed realm baseline. The host
## supplies the seat and resolves the actual interaction on authoritative geometry.

const VERSION := 1
const SIZE := 33

var epoch: int
var baseline: int
var command: PlayerCommand


static func pack(epoch_id: int, baseline_id: int, input: PlayerCommand) -> PackedByteArray:
	if epoch_id <= 0 or baseline_id <= 0 or input == null or input.action != PlayerCommand.INTERACT or not input.valid():
		return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(SIZE)
	bytes[0] = VERSION
	bytes.encode_s64(1, epoch_id)
	bytes.encode_s64(9, baseline_id)
	bytes.encode_double(17, input.x)
	bytes.encode_double(25, input.y)
	return bytes


static func read(bytes: PackedByteArray) -> RealmInteractionFrame:
	if bytes.size() != SIZE or bytes[0] != VERSION:
		return null
	var epoch_id := bytes.decode_s64(1)
	var baseline_id := bytes.decode_s64(9)
	var input := PlayerCommand.new(PlayerCommand.INTERACT, bytes.decode_double(17), bytes.decode_double(25))
	if epoch_id <= 0 or baseline_id <= 0 or not input.valid():
		return null
	var frame := RealmInteractionFrame.new()
	frame.epoch = epoch_id
	frame.baseline = baseline_id
	frame.command = input
	return frame
