class_name NativeDtlsLink
extends RefCounted
## Low-level protected transport only. Connection events do not admit a participant.

enum EventKind { CONNECT, DISCONNECT, FRAME, REJECTED_FRAME, FAILURE }

const MAX_PUMP_EVENTS := 32
const MAX_PEERS := 8
const DRAIN_LIMIT_MS := 300

class Event:
	var kind: EventKind
	var peer: ENetPacketPeer
	var frame: NativeSessionFrame
	var native_type: int

var _host: ENetConnection
var _server := false
var _peers: Dictionary[ENetPacketPeer, bool] = {}
var _departing: Dictionary[ENetPacketPeer, bool] = {}
var _drain_deadline := -1


func listen(bind_to: String, port: int, key: CryptoKey, certificate: X509Certificate) -> Error:
	if _host != null:
		return ERR_ALREADY_IN_USE
	if not private_ip(bind_to) or not _valid_port(port) or key == null or certificate == null:
		return ERR_INVALID_PARAMETER
	var host := ENetConnection.new()
	var error := host.create_host_bound(bind_to, port, MAX_PEERS, NativeSessionFrame.CHANNEL_COUNT)
	if error != OK:
		return error
	error = host.dtls_server_setup(TLSOptions.server(key, certificate))
	if error != OK:
		host.destroy()
		return error
	_host = host
	_server = true
	return OK


func dial(address: String, port: int, paired_name: String, anchor: X509Certificate) -> Error:
	if _host != null:
		return ERR_ALREADY_IN_USE
	if not private_ip(address) or not _valid_port(port) or paired_name.is_empty() or anchor == null:
		return ERR_INVALID_PARAMETER
	var host := ENetConnection.new()
	var error := host.create_host(1, NativeSessionFrame.CHANNEL_COUNT)
	if error != OK:
		return error
	error = host.dtls_client_setup(paired_name, TLSOptions.client(anchor))
	if error != OK:
		host.destroy()
		return error
	var remote := host.connect_to_host(address, port, NativeSessionFrame.CHANNEL_COUNT)
	if remote == null:
		host.destroy()
		return ERR_CANT_CONNECT
	_host = host
	_server = false
	return OK


## Pump order here is transport order. The higher-level owner admits, fences and sequences commands.
func pump() -> Array[Event]:
	var events: Array[Event] = []
	if _host == null:
		return events
	for _work: int in MAX_PUMP_EVENTS:
		var raw := _host.service(0)
		var type: int = raw[0]
		if type == ENetConnection.EVENT_NONE:
			break
		var observed := Event.new()
		observed.native_type = type
		observed.peer = raw[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				_peers[observed.peer] = true
				observed.kind = EventKind.CONNECT
			ENetConnection.EVENT_DISCONNECT:
				_peers.erase(observed.peer)
				_departing.erase(observed.peer)
				observed.kind = EventKind.DISCONNECT
				if not _server:
					# This client has one peer. Finish after its disconnect is acknowledged.
					events.append(observed)
					_host.flush()
					_close()
					return events
			ENetConnection.EVENT_RECEIVE:
				var payload := observed.peer.get_packet()
				if _drain_deadline >= 0 or _departing.has(observed.peer):
					continue
				observed.frame = NativeSessionFrame.read(payload, raw[3])
				observed.kind = EventKind.FRAME if observed.frame != null else EventKind.REJECTED_FRAME
			_:
				observed.kind = EventKind.FAILURE
				events.append(observed)
				_close()
				return events
		events.append(observed)
	# Keep servicing the socket through the bounded drain so its last ACK can leave.
	if _drain_deadline >= 0 and Time.get_ticks_msec() >= _drain_deadline:
		_close()
	return events


func send(peer: ENetPacketPeer, kind: NativeSessionFrame.Kind, generation: int, sequence: int,
		payload: PackedByteArray) -> Error:
	if _host == null or _drain_deadline >= 0 or not _peers.has(peer) or _departing.has(peer):
		return ERR_UNCONFIGURED
	var bytes := NativeSessionFrame.pack(kind, generation, sequence, payload)
	if bytes.is_empty():
		return ERR_INVALID_PARAMETER
	var flags := 0 if kind == NativeSessionFrame.Kind.SEQUENCED else ENetPacketPeer.FLAG_RELIABLE
	return peer.send(NativeSessionFrame.channel(kind), bytes, flags)


func request_peer_close(peer: ENetPacketPeer) -> void:
	if not _peers.has(peer) or _departing.has(peer):
		return
	_departing[peer] = true
	peer.peer_disconnect()


func request_close() -> void:
	if _host == null or _drain_deadline >= 0:
		return
	if _server:
		_host.refuse_new_connections(true)
	for peer: ENetPacketPeer in _peers:
		request_peer_close(peer)
	_drain_deadline = Time.get_ticks_msec() + DRAIN_LIMIT_MS


func is_open() -> bool:
	return _host != null


func local_port() -> int:
	return _host.get_local_port() if _host != null and _server else 0


func _close() -> void:
	_host.destroy()
	_host = null
	_peers.clear()
	_departing.clear()
	_drain_deadline = -1


static func private_ip(address: String) -> bool:
	if not address.is_valid_ip_address():
		return false
	if address.contains(":"):
		var lower := address.to_lower()
		return lower == "::1" or lower.begins_with("fc") or lower.begins_with("fd")
	var groups := address.split(".")
	if groups.size() != 4:
		return false
	for group: String in groups:
		if group != str(group.to_int()) or group.to_int() < 0 or group.to_int() > 255:
			return false
	var first := groups[0].to_int()
	var second := groups[1].to_int()
	return (first == 127 or first == 10 or (first == 172 and second >= 16 and second <= 31)
		or (first == 192 and second == 168))


static func _valid_port(port: int) -> bool:
	return port >= 1 and port <= 65535
