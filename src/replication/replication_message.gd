class_name ReplicationMessage
extends RefCounted
## Explicit application messages over the qualified native session channels.

enum Kind { MOVEMENT, BASELINE, STATE, RESYNC, VIEW }

const VERSION := 1
const HEADER_SIZE := 2
const MAX_BODY := NativeSessionFrame.MAX_PAYLOAD - HEADER_SIZE

var kind: Kind
var body: PackedByteArray


static func pack(message_kind: Kind, bytes: PackedByteArray) -> PackedByteArray:
	if bytes.is_empty() or bytes.size() > MAX_BODY or transport_kind(message_kind) == NativeSessionFrame.Kind.ADMISSION:
		return PackedByteArray()
	return PackedByteArray([VERSION, message_kind]) + bytes


static func read(frame: NativeSessionFrame) -> ReplicationMessage:
	if frame == null or frame.payload.size() <= HEADER_SIZE or frame.payload.size() > NativeSessionFrame.MAX_PAYLOAD:
		return null
	if frame.payload[0] != VERSION or frame.payload[1] > Kind.VIEW:
		return null
	var message_kind := frame.payload[1] as Kind
	if frame.kind != transport_kind(message_kind):
		return null
	var message := ReplicationMessage.new()
	message.kind = message_kind
	message.body = frame.payload.slice(HEADER_SIZE)
	return message


static func transport_kind(message_kind: Kind) -> NativeSessionFrame.Kind:
	match message_kind:
		Kind.MOVEMENT, Kind.STATE:
			return NativeSessionFrame.Kind.SEQUENCED
		Kind.BASELINE, Kind.RESYNC, Kind.VIEW:
			return NativeSessionFrame.Kind.RELIABLE
	return NativeSessionFrame.Kind.ADMISSION
