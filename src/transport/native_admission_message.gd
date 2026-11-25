class_name NativeAdmissionMessage
extends RefCounted
## Primitive admission payload inside the dedicated reliable frame channel.

enum Operation { OPEN = 1, CHALLENGE = 2, PROOF = 3, ACCEPT = 4, ACK = 5, READY = 6 }

const VERSION := 1
const HEADER := 2

var operation: Operation
var seat: int
var purpose: NativeJoinChallenge.Purpose
var bytes: PackedByteArray


static func open_for(seat_id: int, use: NativeJoinChallenge.Purpose, credential: PackedByteArray) -> PackedByteArray:
	if not _valid_seat(seat_id) or not _valid_purpose(use) or credential.size() != NativeJoinChallenge.DIGEST_SIZE:
		return PackedByteArray()
	var result := PackedByteArray([VERSION, Operation.OPEN, seat_id, use])
	result.append_array(credential)
	return result


static func challenge(transcript: PackedByteArray) -> PackedByteArray:
	if transcript.size() != NativeJoinChallenge.SIZE:
		return PackedByteArray()
	var result := PackedByteArray([VERSION, Operation.CHALLENGE])
	result.append_array(transcript)
	return result


static func proof(signature: PackedByteArray) -> PackedByteArray:
	if signature.is_empty() or signature.size() > NativeJoinChallenge.MAX_SIGNATURE:
		return PackedByteArray()
	var result := PackedByteArray([VERSION, Operation.PROOF])
	result.append_array(signature)
	return result


static func accept(seat_id: int, credential: PackedByteArray) -> PackedByteArray:
	if not _valid_seat(seat_id) or credential.size() != NativeJoinChallenge.DIGEST_SIZE:
		return PackedByteArray()
	var result := PackedByteArray([VERSION, Operation.ACCEPT, seat_id])
	result.append_array(credential)
	return result


static func acknowledge() -> PackedByteArray:
	return PackedByteArray([VERSION, Operation.ACK])


static func ready() -> PackedByteArray:
	return PackedByteArray([VERSION, Operation.READY])


static func decode(payload: PackedByteArray) -> NativeAdmissionMessage:
	if payload.size() < HEADER or payload[0] != VERSION:
		return null
	var message := NativeAdmissionMessage.new()
	match payload[1]:
		Operation.OPEN:
			if (payload.size() != 4 + NativeJoinChallenge.DIGEST_SIZE or not _valid_seat(payload[2])
					or not _valid_purpose(payload[3])):
				return null
			message.seat = payload[2]
			message.purpose = payload[3] as NativeJoinChallenge.Purpose
			message.bytes = payload.slice(4)
		Operation.CHALLENGE:
			if payload.size() != HEADER + NativeJoinChallenge.SIZE:
				return null
			message.bytes = payload.slice(HEADER)
		Operation.PROOF:
			if payload.size() <= HEADER or payload.size() > HEADER + NativeJoinChallenge.MAX_SIGNATURE:
				return null
			message.bytes = payload.slice(HEADER)
		Operation.ACCEPT:
			if payload.size() != 3 + NativeJoinChallenge.DIGEST_SIZE or not _valid_seat(payload[2]):
				return null
			message.seat = payload[2]
			message.bytes = payload.slice(3)
		Operation.ACK, Operation.READY:
			if payload.size() != HEADER:
				return null
		_:
			return null
	message.operation = payload[1] as Operation
	return message


static func _valid_seat(seat_id: int) -> bool:
	return seat_id >= 1 and seat_id <= NativeAdmission.MAX_GUESTS


static func _valid_purpose(value: int) -> bool:
	return value == NativeJoinChallenge.Purpose.INITIAL or value == NativeJoinChallenge.Purpose.RECLAIM
