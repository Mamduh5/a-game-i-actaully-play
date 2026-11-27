class_name RealmInteractionFrame
extends RefCounted
## A reliable world command refers to the last confirmed realm baseline.
## The host supplies the seat and resolves it on authoritative geometry.

const VERSION := 1
const SIZE := 33
const COMBAT_VERSION := 2
const COMBAT_ACTIONS := [PlayerCommand.MANUAL, PlayerCommand.TARGET]

var epoch: int
var baseline: int
var command: PlayerCommand


static func pack(epoch_id: int, baseline_id: int, input: PlayerCommand) -> PackedByteArray:
	if (epoch_id <= 0 or baseline_id <= 0 or input == null or input.action not in PlayerCommand.RELIABLE_ACTIONS
			or not input.valid()):
		return PackedByteArray()
	var combat := input.action != PlayerCommand.INTERACT
	var offset := int(combat)
	var bytes := PackedByteArray()
	bytes.resize(SIZE + offset)
	bytes[0] = COMBAT_VERSION if combat else VERSION
	if combat:
		bytes[1] = COMBAT_ACTIONS.find(input.action)
	bytes.encode_s64(1 + offset, epoch_id)
	bytes.encode_s64(9 + offset, baseline_id)
	bytes.encode_double(17 + offset, input.x)
	bytes.encode_double(25 + offset, input.y)
	return bytes


static func read(bytes: PackedByteArray) -> RealmInteractionFrame:
	var action := PlayerCommand.INTERACT
	var offset := 0
	if bytes.size() == SIZE + 1 and bytes[0] == COMBAT_VERSION and bytes[1] < COMBAT_ACTIONS.size():
		action = COMBAT_ACTIONS[bytes[1]]
		offset = 1
	elif bytes.size() != SIZE or bytes[0] != VERSION:
		return null
	var epoch_id := bytes.decode_s64(1 + offset)
	var baseline_id := bytes.decode_s64(9 + offset)
	var input := PlayerCommand.new(action, bytes.decode_double(17 + offset), bytes.decode_double(25 + offset))
	if epoch_id <= 0 or baseline_id <= 0 or not input.valid():
		return null
	var frame := RealmInteractionFrame.new()
	frame.epoch = epoch_id
	frame.baseline = baseline_id
	frame.command = input
	return frame
