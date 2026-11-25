extends Node
## Disposable private-loopback probe for the real host/link boundary.

const ADDRESS := "127.0.0.1"
const PAIRED_NAME := "fixture.local"
const EPOCH := 2
const TIMEOUT := 7000
const ADMISSION := NativeSessionFrame.Kind.ADMISSION
const RELIABLE := NativeSessionFrame.Kind.RELIABLE
const SEQUENCED := NativeSessionFrame.Kind.SEQUENCED
const INITIAL := NativeJoinChallenge.Purpose.INITIAL
const RECLAIM := NativeJoinChallenge.Purpose.RECLAIM

var _link := NativeDtlsLink.new()
var _session: NativeSessionHost
var _guest_key := CryptoKey.new()
var _host_id: PackedByteArray
var _run_id := "wp06-test-run".sha256_buffer()
var _invitation: PackedByteArray
var _mode: String
var _role: String
var _deadline: int
var _close_at := -1
var _closing := false
var _guest_stage := 0
var _admitted := 0
var _rejected := 0
var _departures := 0
var _lost := 0
var _handoff_path: String
var _credential_path: String
var _loss_path: String
var _frames: Dictionary[NativeSessionFrame.Kind, bool] = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[0] == "keygen":
		_keygen(args[1], args[2])
		return
	if (args.size() not in [8, 9, 10] or args[0] not in ["host", "guest"]
			or args[7] not in ["paired", "early", "client-close", "wrong-invite", "abrupt", "reclaim", "unacked"]):
		_finish(false)
		return
	_role = args[0]
	_mode = args[7]
	if _mode in ["abrupt", "reclaim", "unacked"]:
		if args.size() < 9 or (_mode in ["abrupt", "unacked"] and _role == "guest" and args.size() != 10):
			_finish(false)
			return
		if _role == "host":
			_loss_path = args[8]
		else:
			_credential_path = args[8]
			if _mode in ["abrupt", "unacked"]:
				_handoff_path = args[9]
	var port := args[1].to_int()
	var certificate := X509Certificate.new()
	if certificate.load(args[2]) != OK:
		_finish(false)
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(FileAccess.get_file_as_bytes(args[2]))
	_host_id = hash.finish()
	_deadline = Time.get_ticks_msec() + (51000 if _mode == "abrupt" else TIMEOUT)
	if _role == "host":
		_setup_host(port, certificate, args)
	else:
		_invitation = FileAccess.get_file_as_bytes(args[5])
		if _guest_key.load(args[4]) != OK or _link.dial(ADDRESS, port, PAIRED_NAME, certificate) != OK:
			_finish(false)
			return
		print("WP06_SESSION_PHASE guest-ready")


func _setup_host(port: int, certificate: X509Certificate, args: PackedStringArray) -> void:
	var key := CryptoKey.new()
	var guest_public := CryptoKey.new()
	if key.load(args[3]) != OK or guest_public.load(args[4], true) != OK:
		_finish(false)
		return
	var owner := NativeAdmission.new(_host_id, _run_id, EPOCH)
	_invitation = owner.offer(1, guest_public, Time.get_ticks_msec(), _deadline)
	_session = NativeSessionHost.new(owner, EPOCH, TIMEOUT)
	if _session.listen(ADDRESS, port, key, certificate) != OK:
		_finish(false)
		return
	if not _write(args[5], _invitation) or not _write(args[6], PackedByteArray([1])):
		_finish(false)
		return
	print("WP06_SESSION_PHASE host-ready")


func _process(_delta: float) -> void:
	if _role == "host":
		_run_host()
	else:
		_run_guest()
	if Time.get_ticks_msec() >= _deadline and is_processing():
		_finish(false)


func _run_host() -> void:
	var batch := _session.pump()
	if batch.failure:
		_finish(false)
		return
	_admitted += batch.admitted.size()
	if not batch.admitted.is_empty():
		print("WP06_SESSION_PHASE admitted")
	_rejected += batch.rejected
	_departures += batch.departures
	if not batch.lost_seats.is_empty():
		_lost += batch.lost_seats.size()
		if _mode == "abrupt" and _lost == 1 and batch.lost_seats == [1]:
			_frames.clear()
			if not _write(_loss_path, PackedByteArray([1])):
				_finish(false)
				return
			print("WP06_SESSION_PHASE host-observed-loss")
	for command: NativeSessionHost.Command in batch.commands:
		var frame := command.frame
		if command.seat != 1 or frame.payload != PackedByteArray([frame.kind]):
			_finish(false)
			return
		_frames[frame.kind] = true
		if _session.send(command.connection, frame.kind, frame.sequence, frame.payload) != OK:
			_finish(false)
			return
	var passed := (_frames.is_empty() and _admitted == 0 and _rejected == 1) if _expects_refusal() else (
		_frames.size() == 2 and _admitted == 1 and _rejected == 0 and _departures == int(_mode == "paired"))
	if _mode == "abrupt":
		passed = _frames.size() == 2 and _admitted == 2 and _rejected == 0 and _departures == 1 and _lost == 1
	if passed and _close_at < 0:
		print("WP06_SESSION_PHASE boundary-observed")
		_close_at = Time.get_ticks_msec() + 400
	if _close_at >= 0 and Time.get_ticks_msec() >= _close_at and not _closing:
		print("WP06_SESSION_PHASE host-draining")
		_closing = true
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(passed)


func _run_guest() -> void:
	for event: NativeDtlsLink.Event in _link.pump():
		match event.kind:
			NativeDtlsLink.EventKind.CONNECT:
				var error: Error
				if _mode == "early":
					error = _link.send(event.peer, RELIABLE, EPOCH, 1, PackedByteArray([RELIABLE]))
				else:
					error = _link.send(event.peer, ADMISSION, EPOCH, 1,
						NativeAdmissionMessage.open_for(1, _purpose(), _invitation))
				if error != OK:
					_finish(false)
					return
			NativeDtlsLink.EventKind.FRAME:
				if _expects_refusal() or not _accept(event.peer, event.frame):
					_finish(false)
					return
			NativeDtlsLink.EventKind.DISCONNECT:
				if _mode == "unacked":
					_finish(_guest_stage == 2 and _frames.is_empty())
				else:
					_finish(_frames.is_empty() if _expects_refusal() else _frames.size() == 2)
				return
			_:
				_finish(false)
				return


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.generation != EPOCH:
		return false
	if frame.kind != ADMISSION:
		if _guest_stage != 3 or frame.sequence != 1 or frame.payload != PackedByteArray([frame.kind]):
			return false
		_frames[frame.kind] = true
		if _frames.size() == 2:
			if _mode == "abrupt":
				return _write(_handoff_path, PackedByteArray([1]))
			elif _mode == "client-close":
				print("WP06_SESSION_PHASE guest-draining")
				_link.request_close()
			else:
				print("WP06_SESSION_PHASE guest-requested-leave")
				return _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK
		return true
	if frame.sequence != _guest_stage + 1:
		return false
	_guest_stage += 1
	var message := NativeAdmissionMessage.decode(frame.payload)
	if message == null:
		return false
	match message.operation:
		NativeAdmissionMessage.Operation.CHALLENGE:
			var attempt := message.bytes.decode_s64(NativeJoinChallenge.ATTEMPT_OFFSET)
			var signed := NativeJoinChallenge.sign_challenge(message.bytes, _purpose(), EPOCH, attempt,
				_host_id, _run_id, _guest_key)
			return _guest_stage == 1 and _link.send(peer, ADMISSION, EPOCH, 2, NativeAdmissionMessage.proof(signed)) == OK
		NativeAdmissionMessage.Operation.ACCEPT:
			if _guest_stage != 2 or message.seat != 1:
				return false
			if not _credential_path.is_empty() and not _write(_credential_path, message.bytes):
				return false
			if _mode == "unacked":
				return _write(_handoff_path, PackedByteArray([1]))
			return _link.send(peer, ADMISSION, EPOCH, 3, NativeAdmissionMessage.acknowledge()) == OK
		NativeAdmissionMessage.Operation.READY:
			return (_guest_stage == 3 and _link.send(peer, RELIABLE, EPOCH, 1, PackedByteArray([RELIABLE])) == OK
				and _link.send(peer, SEQUENCED, EPOCH, 1, PackedByteArray([SEQUENCED])) == OK)
	return false


func _purpose() -> NativeJoinChallenge.Purpose:
	return RECLAIM if _mode in ["reclaim", "unacked"] else INITIAL


func _expects_refusal() -> bool:
	return _mode in ["early", "wrong-invite"]


func _keygen(role: String, output: String) -> void:
	set_process(false)
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var result := false
	if key != null and role == "host":
		var cert := crypto.generate_self_signed_certificate(key, "CN=%s,O=Disposable" % PAIRED_NAME,
			"20200101000000", "20350101000000")
		result = (cert != null and key.save(output.path_join("host.key")) == OK
			and cert.save(output.path_join("host.crt")) == OK)
	elif key != null and role == "guest":
		result = (key.save(output.path_join("guest.key")) == OK and key.save(output.path_join("guest.pub"), true) == OK)
	get_tree().quit(0 if result else 1)


func _finish(passed: bool) -> void:
	set_process(false)
	print("WP06_SESSION_RESULT ", JSON.stringify({"passed": passed, "role": _role,
		"admitted": _admitted, "rejected": _rejected, "frames": _frames.size(), "departures": _departures,
		"lost": _lost}))
	get_tree().quit(0 if passed else 1)


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return true
