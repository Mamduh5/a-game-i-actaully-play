extends Node
## Diagnostic exchange only. It grants no seat or application access.

const PAIRED_NAME := "fixture.local"
const ADDRESS := "127.0.0.1"
const DEADLINE_MS := 3500

var _link := NativeDtlsLink.new()
var _role: String
var _expects_connect: bool
var _deadline: int
var _connected := false
var _closing := false
var _timed_out := false
var _observed: Dictionary[NativeSessionFrame.Kind, bool] = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "keygen":
		_make_identity(args[1])
		return
	if args.size() != 7 or args[0] not in ["host", "guest"]:
		_finish(false, "invalid fixture arguments")
		return
	_role = args[0]
	var port := args[1].to_int()
	_expects_connect = args[5] == "paired"
	var certificate := X509Certificate.new()
	if certificate.load(args[2]) != OK:
		_finish(false, "certificate load failed")
		return
	var result: Error
	if _role == "host":
		var key := CryptoKey.new()
		if key.load(args[3]) != OK:
			_finish(false, "private fixture key load failed")
			return
		result = _link.listen(ADDRESS, port, key, certificate)
	else:
		result = _link.dial(ADDRESS, port, args[4], certificate)
	if result != OK:
		_finish(false, "transport setup failed")
		return
	if _role == "host" and _link.local_port() != port:
		_finish(false, "unexpected host bind port")
		return
	if _role == "host":
		var ready := FileAccess.open(args[6], FileAccess.WRITE)
		if ready == null:
			_finish(false, "readiness file could not be written")
			return
		ready.store_8(1)
		ready.close()
	print("WP06_LINK_READY ", _role, " ", ADDRESS, " host-port=", port)
	_deadline = Time.get_ticks_msec() + (6500 if _expects_connect else DEADLINE_MS)


func _process(_delta: float) -> void:
	for event: NativeDtlsLink.Event in _link.pump():
		match event.kind:
			NativeDtlsLink.EventKind.CONNECT:
				_connected = true
				print("WP06_LINK_PHASE connected role=", _role)
				if not _expects_connect:
					_finish(false, "unpaired transport connected")
					return
				if _role == "guest" and not _send_probes(event.peer):
					_finish(false, "probe send failed")
					return
			NativeDtlsLink.EventKind.FRAME:
				if not _accept_probe(event):
					_finish(false, "unexpected probe frame")
					return
			NativeDtlsLink.EventKind.DISCONNECT:
				print("WP06_LINK_PHASE disconnected role=", _role)
				if not _closing:
					_link.request_close()
					_closing = true
			NativeDtlsLink.EventKind.FAILURE:
				var refused := not _expects_connect and not _connected and _observed.is_empty()
				_finish(refused, "connect rejected by transport" if refused else
					"transport failure, native type %d, closing=%s" % [event.native_type, _closing])
				return
			_:
				_finish(false, "unexpected event %d with native type %d, closing=%s" % [
					event.kind, event.native_type, _closing,
				])
				return
	if _closing and not _link.is_open():
		var passed := _connected and _observed.size() == 3 if _expects_connect else not _connected
		var reason := "connection deadline" if _timed_out else "protected diagnostic exchange"
		_finish(passed and (not _timed_out or not _expects_connect), reason)
	elif not _closing and Time.get_ticks_msec() >= _deadline:
		_timed_out = true
		_closing = true
		_link.request_close()


func _send_probes(peer: ENetPacketPeer) -> bool:
	for kind: NativeSessionFrame.Kind in [
		NativeSessionFrame.Kind.ADMISSION, NativeSessionFrame.Kind.RELIABLE, NativeSessionFrame.Kind.SEQUENCED,
	]:
		if _link.send(peer, kind, 2, kind, "wp06-transport-probe".to_utf8_buffer()) != OK:
			return false
	return true


func _accept_probe(event: NativeDtlsLink.Event) -> bool:
	var frame := event.frame
	var expected := "wp06-transport-probe" if _role == "host" else "wp06-transport-ack"
	if frame.generation != 2 or frame.sequence != frame.kind or frame.payload.get_string_from_utf8() != expected:
		return false
	_observed[frame.kind] = true
	if _observed.size() == 3:
		print("WP06_LINK_PHASE exchanged role=", _role)
	if _role == "host":
		return _link.send(event.peer, frame.kind, frame.generation, frame.sequence,
			"wp06-transport-ack".to_utf8_buffer()) == OK
	if _observed.size() == 3:
		_link.request_close()
		_closing = true
	return true


func _make_identity(directory: String) -> void:
	set_process(false)
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	if key == null:
		get_tree().quit(1)
		return
	var certificate := crypto.generate_self_signed_certificate(key, "CN=%s,O=Disposable" % PAIRED_NAME,
		"20200101000000", "20350101000000")
	var written := (certificate != null and key.save(directory.path_join("host.key")) == OK
		and certificate.save(directory.path_join("host.crt")) == OK)
	get_tree().quit(0 if written else 1)


func _finish(passed: bool, reason: String) -> void:
	set_process(false)
	print("WP06_LINK_RESULT ", JSON.stringify({"role": _role, "passed": passed, "connected": _connected,
		"frames": _observed.size(), "reason": reason}))
	get_tree().quit(0 if passed else 1)
