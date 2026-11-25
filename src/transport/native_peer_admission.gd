class_name NativePeerAdmission
extends RefCounted
## Dispatches frames from protected peers. The caller assigns each DTLS
## connection a fresh local handle and carries replies on that same connection.

class Peer:
	var next_operation := NativeAdmissionMessage.Operation.OPEN
	var deadline: int
	var seat: int
	var ready := false
	var reliable_id := 0
	var sequenced_id := 0

class Action:
	var disconnect := false
	var voluntary := false
	var replaced_connection: int
	var reply: PackedByteArray
	var reply_sequence: int
	var command: NativeSessionFrame
	var seat: int

var _authority: NativeAdmission
var _generation: int
var _peers: Dictionary[int, Peer] = {}


func _init(authority: NativeAdmission, generation: int) -> void:
	_authority = authority
	_generation = generation


func attach(connection: int, now: int, admission_deadline: int) -> bool:
	if (connection < 1 or now < 0 or admission_deadline <= now or _generation < 1 or _authority == null
			or _peers.has(connection) or _peers.size() >= NativeDtlsLink.MAX_PEERS):
		return false
	var peer := Peer.new()
	peer.deadline = admission_deadline
	_peers[connection] = peer
	return true


func detach(connection: int) -> void:
	if _peers.erase(connection):
		_authority.drop_connection(connection)


func expired(now: int) -> Array[int]:
	var timed_out: Array[int] = []
	for connection: int in _peers:
		if not _peers[connection].ready and now >= _peers[connection].deadline:
			timed_out.append(connection)
	for connection: int in timed_out:
		detach(connection)
	return timed_out


func can_send(connection: int) -> bool:
	var peer: Peer = _peers.get(connection)
	return peer != null and peer.ready and _authority.owns(connection, _generation, peer.seat)


func receive(connection: int, frame: NativeSessionFrame, now: int) -> Action:
	var peer: Peer = _peers.get(connection)
	if peer == null or frame == null or now < 0 or frame.generation != _generation:
		return _reject(connection)
	if peer.ready:
		return _command(connection, peer, frame)
	if frame.kind != NativeSessionFrame.Kind.ADMISSION or now >= peer.deadline:
		return _reject(connection)
	var message := NativeAdmissionMessage.decode(frame.payload)
	if message == null or message.operation != peer.next_operation:
		return _reject(connection)
	var action := Action.new()
	match message.operation:
		NativeAdmissionMessage.Operation.OPEN:
			if frame.sequence != 1:
				return _reject(connection)
			var challenge := _authority.begin(connection, _generation, message.seat, message.purpose,
				message.bytes, now, peer.deadline)
			if challenge.is_empty():
				return _reject(connection)
			peer.next_operation = NativeAdmissionMessage.Operation.PROOF
			action.reply = NativeAdmissionMessage.challenge(challenge)
			action.reply_sequence = 1
		NativeAdmissionMessage.Operation.PROOF:
			if frame.sequence != 2:
				return _reject(connection)
			var accepted := _authority.complete(connection, message.bytes, now)
			if accepted == null:
				return _reject(connection)
			peer.seat = accepted.seat
			peer.next_operation = NativeAdmissionMessage.Operation.ACK
			action.reply = NativeAdmissionMessage.accept(accepted.seat, accepted.credential)
			action.reply_sequence = 2
			action.replaced_connection = accepted.replaced_controller
			if accepted.replaced_controller != 0:
				detach(accepted.replaced_controller)
		NativeAdmissionMessage.Operation.ACK:
			if frame.sequence != 3 or not _authority.acknowledge(connection, _generation):
				return _reject(connection)
			peer.ready = true
			action.seat = peer.seat
			action.reply = NativeAdmissionMessage.ready()
			action.reply_sequence = 3
		_:
			return _reject(connection)
	return action


func _command(connection: int, peer: Peer, frame: NativeSessionFrame) -> Action:
	if not _authority.owns(connection, _generation, peer.seat):
		return _reject(connection)
	var action := Action.new()
	match frame.kind:
		NativeSessionFrame.Kind.ADMISSION:
			var message := NativeAdmissionMessage.decode(frame.payload)
			if frame.sequence != 4 or message == null or message.operation != NativeAdmissionMessage.Operation.LEAVE:
				return _reject(connection)
			detach(connection)
			action.disconnect = true
			action.voluntary = true
			return action
		NativeSessionFrame.Kind.RELIABLE:
			if frame.sequence <= peer.reliable_id:
				return action
			peer.reliable_id = frame.sequence
		NativeSessionFrame.Kind.SEQUENCED:
			if frame.sequence <= peer.sequenced_id:
				return action
			peer.sequenced_id = frame.sequence
		_:
			return _reject(connection)
	action.command = frame
	action.seat = peer.seat
	return action


func _reject(connection: int) -> Action:
	detach(connection)
	var action := Action.new()
	action.disconnect = true
	return action
