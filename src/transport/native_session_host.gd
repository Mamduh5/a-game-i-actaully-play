class_name NativeSessionHost
extends RefCounted
## Host-side boundary between the protected link and the authority command port.
## Only acknowledged, currently controlled seats produce commands.

const MAX_CONNECTION_ID := 9223372036854775807

class Command:
	var connection: int
	var seat: int
	var frame: NativeSessionFrame

class Batch:
	var commands: Array[Command] = []
	var admitted: Array[int] = []
	var lost_seats: Array[int] = []
	var rejected := 0
	var departures := 0
	var failure := false

var _link := NativeDtlsLink.new()
var _driver: NativePeerAdmission
var _generation: int
var _admission_timeout: int
var _next_connection := 0
var _closing := false
var _handles: Dictionary[ENetPacketPeer, int] = {}
var _peers: Dictionary[int, ENetPacketPeer] = {}


func _init(authority: NativeAdmission, generation: int, admission_timeout_ms: int) -> void:
	_driver = NativePeerAdmission.new(authority, generation)
	_generation = generation
	_admission_timeout = admission_timeout_ms


func listen(address: String, port: int, private_key: CryptoKey, certificate: X509Certificate) -> Error:
	if _closing or _admission_timeout <= 0 or _generation <= 0:
		return ERR_INVALID_PARAMETER
	return _link.listen(address, port, private_key, certificate)


func is_open() -> bool:
	return _link.is_open()


func request_close() -> void:
	_closing = true
	for connection: int in _peers.keys():
		_drop(connection)
	_link.request_close()


func pump() -> Batch:
	var batch := Batch.new()
	var now := Time.get_ticks_msec()
	for timed_out: int in _driver.expired(now):
		_drop(timed_out)
		batch.rejected += 1
	for event: NativeDtlsLink.Event in _link.pump():
		var connection: int = _handles.get(event.peer, 0)
		match event.kind:
			NativeDtlsLink.EventKind.CONNECT:
				if not _attach(event.peer, now):
					batch.rejected += 1
			NativeDtlsLink.EventKind.DISCONNECT:
				_record_loss(batch, connection, _driver.controlled_seat(connection))
				_drop(connection)
			NativeDtlsLink.EventKind.FRAME:
				if connection > 0:
					_dispatch(connection, event.frame, now, batch)
			NativeDtlsLink.EventKind.REJECTED_FRAME:
				_record_loss(batch, connection, _driver.controlled_seat(connection))
				_drop(connection)
				batch.rejected += 1
			NativeDtlsLink.EventKind.FAILURE:
				request_close()
				batch.failure = true
				batch.commands.clear()
				batch.admitted.clear()
				return batch
	for index: int in range(batch.admitted.size() - 1, -1, -1):
		if not _driver.can_send(batch.admitted[index]):
			batch.admitted.remove_at(index)
	for index: int in range(batch.commands.size() - 1, -1, -1):
		if not _driver.can_send(batch.commands[index].connection):
			batch.commands.remove_at(index)
	return batch


func send(connection: int, kind: NativeSessionFrame.Kind, sequence: int, bytes: PackedByteArray) -> Error:
	if kind == NativeSessionFrame.Kind.ADMISSION or not _driver.can_send(connection):
		return ERR_UNAUTHORIZED
	return _link.send(_peers.get(connection), kind, _generation, sequence, bytes)


func _attach(peer: ENetPacketPeer, now: int) -> bool:
	if _closing or _next_connection == MAX_CONNECTION_ID or now > MAX_CONNECTION_ID - _admission_timeout:
		_link.request_peer_close(peer)
		return false
	_next_connection += 1
	if not _driver.attach(_next_connection, now, now + _admission_timeout):
		_link.request_peer_close(peer)
		return false
	_handles[peer] = _next_connection
	_peers[_next_connection] = peer
	return true


func _drop(connection: int) -> void:
	var peer: ENetPacketPeer = _peers.get(connection)
	if peer != null:
		_peers.erase(connection)
		_handles.erase(peer)
		_driver.detach(connection)
		_link.request_peer_close(peer)


func _dispatch(connection: int, frame: NativeSessionFrame, now: int, batch: Batch) -> void:
	var active_seat := _driver.controlled_seat(connection)
	var action := _driver.receive(connection, frame, now)
	if action.replaced_connection > 0:
		_drop(action.replaced_connection)
	if action.disconnect:
		_drop(connection)
		if action.voluntary:
			batch.departures += 1
		else:
			_record_loss(batch, connection, active_seat)
			batch.rejected += 1
		return
	if not action.reply.is_empty():
		if _link.send(_peers[connection], NativeSessionFrame.Kind.ADMISSION,
				_generation, action.reply_sequence, action.reply) != OK:
			_drop(connection)
			batch.rejected += 1
			return
		if action.seat > 0:
			batch.admitted.append(connection)
	if action.command != null:
		var command := Command.new()
		command.connection = connection
		command.seat = action.seat
		command.frame = action.command
		batch.commands.append(command)


static func _record_loss(batch: Batch, connection: int, seat: int) -> void:
	if batch.admitted.has(connection):
		batch.admitted.erase(connection)
	elif seat > 0:
		batch.lost_seats.append(seat)
