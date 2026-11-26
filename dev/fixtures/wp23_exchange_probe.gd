extends "res://dev/fixtures/wp06_session_probe.gd"
## The original guest drops an application acknowledgement. On fresh
## processes the old guest hosts and the old host delivers both old grants.

const Original := "wp23-run-one"
const Reversed := "wp23-run-two"
const Currency := "currency/permanent"
const Commit := ProfileStore.CommitResult
const Start := [67]

var _store := ProfileStore.new()
var _exchange: ProfileGrantExchange
var _identity_key := CryptoKey.new()
var _reverse := false
var _received: Array[int] = []
var _sent := 0
var _left := false
var _original_issuer: bool


func _ready() -> void:
	_reverse = OS.get_environment("AGIP_WP23_REVERSED") == "1"
	_run_id = (Reversed if _reverse else Original).sha256_buffer()
	super._ready()
	if not is_processing():
		return
	_original_issuer = (_role == "host") != _reverse
	var profile := "alice" if _original_issuer else "bob"
	var key_path := OS.get_cmdline_user_args()[3 if _role == "host" else 4]
	if (_store.open(profile, OS.get_environment("AGIP_WP23_PROFILES")) != ProfileStore.OpenResult.OPENED
			or _identity_key.load(key_path) != OK):
		_finish(false)
		return
	_exchange = ProfileGrantExchange.new(_store, _identity_key)
	if _reverse and _store.grant_binding(Original, "bob") == null:
		_finish(false)


func _keygen(_role_name: String, output: String) -> void:
	set_process(false)
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	if key == null:
		get_tree().quit(1)
		return
	var certificate := crypto.generate_self_signed_certificate(key, "CN=%s,O=Disposable" % PAIRED_NAME,
		"20200101000000", "20350101000000")
	var ok := (certificate != null and key.save(output.path_join("peer.key")) == OK
		and key.save(output.path_join("peer.pub"), true) == OK and certificate.save(output.path_join("host.crt")) == OK)
	get_tree().quit(0 if ok else 1)


func _retain_original() -> bool:
	var remote := CryptoKey.new()
	if remote.load(OS.get_environment("AGIP_WP23_ORIGINAL_PEER"), true) != OK:
		return false
	var binding := ProfileGrant.Binding.new()
	binding.run = Original
	binding.rules = "V42.6/R1"
	binding.catalog = "wp23-fixture"
	binding.recipient = "bob"
	binding.issuer = _identity_key if _original_issuer else remote
	binding.recipient_key = remote if _original_issuer else _identity_key
	return ProfileGrantSettlement.retain_original_binding(_store, binding, _identity_key).status == Commit.COMMITTED


func _issue() -> bool:
	var binding := _store.grant_binding(Original, "bob")
	if binding == null:
		return false
	for index: int in [1, 2]:
		var award := ProfileGrantSettlement.Entitlement.new()
		award.binding = binding
		award.occurrence = "regional-boss/%d" % index
		award.kind = ProfileGrant.Kind.CURRENCY
		award.award = Currency
		award.amount = Quantity.from_count(17 if index == 1 else 23)
		var frontier := ProfileMutation.Frontier.new()
		frontier.run = Original
		frontier.epoch = EPOCH
		frontier.tick = index
		frontier.image = var_to_bytes(["closed", index, award.occurrence])
		if ProfileGrantSettlement.issue(_store, _identity_key, [award], frontier).status != Commit.COMMITTED:
			return false
	return true


func _deliveries() -> Array[PackedByteArray]:
	var binding := _store.grant_binding(Original, "bob")
	var packets: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
	var queued := _store.pending_grants()
	if queued.size() != 2 or binding == null:
		return []
	for row: Dictionary in queued:
		var item := ProfileGrant.open_authorization(row.body, binding)
		if item == null or item.occurrence not in ["regional-boss/1", "regional-boss/2"]:
			return []
		packets[item.occurrence.right(1).to_int() - 1] = _exchange.delivery(Original, "bob", row.grant_key)
	return [] if packets[0].is_empty() or packets[1].is_empty() else packets


func _run_host() -> void:
	var batch := _session.pump()
	_admitted += batch.admitted.size()
	_rejected += batch.rejected
	_lost += batch.lost_seats.size()
	_departures += batch.departures
	if batch.failure or _admitted > 1 or _lost != 0 or _rejected != 0:
		_finish(false)
		return
	for command: NativeSessionHost.Command in batch.commands:
		if command.seat != 1 or not _host_command(command):
			_finish(false)
			return
	if _departures == 1 and not _closing:
		_closing = true
		print("WP06_SESSION_PHASE host-draining")
		_session.request_close()
	if _closing and not _session.is_open():
		_finish(_admitted == 1 and _sent == (3 if _reverse else 1))


func _host_command(command: NativeSessionHost.Command) -> bool:
	if not _reverse:
		if _sent != 0 or command.frame.kind != RELIABLE or command.frame.payload != PackedByteArray(Start):
			return false
		if not _retain_original() or not _issue():
			return false
		var deliveries := _deliveries()
		_sent += 1
		return not deliveries.is_empty() and _session.send(command.connection, RELIABLE, _sent, deliveries[0]) == OK
	var result := _exchange.receive(command.frame)
	_received.append(result.receipt.status)
	if result.reply.is_empty():
		return result.receipt.status == Commit.INVALID
	_sent += 1
	if _session.send(command.connection, RELIABLE, _sent, result.reply) != OK:
		return false
	if _sent == 1:
		_sent += 1
		return _session.send(command.connection, RELIABLE, _sent, result.reply) == OK
	return true


func _guest_ready(peer: ENetPacketPeer) -> bool:
	if not _reverse:
		return (_retain_original()
			and _link.send(peer, RELIABLE, EPOCH, 1, PackedByteArray(Start)) == OK)
	var deliveries := _deliveries()
	if deliveries.is_empty():
		return false
	var damaged := deliveries[0].duplicate()
	damaged[damaged.size() - 1] ^= 1
	var wrong_run := deliveries[0].duplicate()
	var route := Reversed.to_ascii_buffer()
	for index: int in route.size():
		wrong_run[ProfileGrantExchange.HEADER + index] = route[index]
	for packet: PackedByteArray in [damaged, wrong_run, deliveries[0], deliveries[1]]:
		_sent += 1
		if _link.send(peer, RELIABLE, EPOCH, _sent, packet) != OK:
			return false
	return true


func _accept(peer: ENetPacketPeer, frame: NativeSessionFrame) -> bool:
	if frame.kind == ADMISSION:
		return super._accept(peer, frame)
	if _guest_stage != 3 or frame.generation != EPOCH or frame.sequence != _received.size() + 1:
		return false
	var result := _exchange.receive(frame)
	_received.append(result.receipt.status)
	if not _reverse:
		if result.receipt.status != Commit.COMMITTED or result.reply.is_empty():
			return false
		# Application is durable. Intentionally leave without sending its acknowledgement.
	elif _received.size() < 3:
		return result.receipt.status in [Commit.COMMITTED, Commit.DUPLICATE]
	_left = _link.send(peer, ADMISSION, EPOCH, 4, NativeAdmissionMessage.leave()) == OK
	return _left


func _run_guest() -> void:
	for event: NativeDtlsLink.Event in _link.pump():
		match event.kind:
			NativeDtlsLink.EventKind.CONNECT:
				if _link.send(event.peer, ADMISSION, EPOCH, 1,
						NativeAdmissionMessage.open_for(1, INITIAL, _invitation)) == OK:
					continue
			NativeDtlsLink.EventKind.FRAME:
				if _accept(event.peer, event.frame):
					continue
			NativeDtlsLink.EventKind.DISCONNECT:
				_finish(_left)
				return
		_finish(false)
		return


func _finish(passed: bool) -> void:
	var state := {}
	if not _store.identity().is_empty():
		var pending := _store.pending_grants().size()
		var balance: Variant = _store.balance(Currency).native_at_scale(0)
		var generation: int = _store.checkpoint().get("generation", -1)
		var expected: Array[int]
		if _reverse:
			expected = [Commit.COMMITTED, Commit.DUPLICATE, Commit.COMMITTED] if _original_issuer else [
				Commit.INVALID, Commit.INVALID, Commit.DUPLICATE, Commit.COMMITTED]
		else:
			expected = [] if _original_issuer else [Commit.COMMITTED]
		passed = (passed and _received == expected
			and pending == (2 if _original_issuer and not _reverse else 0)
			and balance == (0 if _original_issuer else (40 if _reverse else 17)))
		state = {"reversed": _reverse, "profile": _store.identity(), "balance": balance,
			"pending": pending, "generation": generation, "received": _received}
		passed = _store.close() and passed
	state["passed"] = passed
	print("WP23_EXCHANGE ", JSON.stringify(state))
	super._finish(passed)
