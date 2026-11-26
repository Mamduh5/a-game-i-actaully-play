extends Node
## Native process-fault witness. Files carry the signed grant and receipt
## between disposable profile processes so each durable boundary is observable.

const Currency := "currency/permanent"
const Commit := ProfileStore.CommitResult

class FixtureClock:
	var elapsed: int

	func sample() -> int:
		return elapsed

class FaultStore extends ProfileStore:
	var point: String
	var marker: String

	func page_limit() -> int:
		return int(_value(_db, "PRAGMA max_page_count", "max_page_count"))

	func writable_pages() -> int:
		return int(_value(_db, "PRAGMA page_count", "page_count"))

	func set_page_limit(pages: int) -> bool:
		return pages > 0 and _value(_db, "PRAGMA max_page_count=%d" % pages, "max_page_count") == pages

	func _commit_io() -> bool:
		if point == "before":
			_park()
		var committed := super._commit_io()
		if committed and point == "after":
			_park()
		return committed

	func _park() -> void:
		var signal_file := FileAccess.open(marker, FileAccess.WRITE)
		if signal_file != null:
			signal_file.store_8(1)
			signal_file.close()
		# The supervising test terminates this disposable process at the marker.
		for _attempt: int in 5000:
			OS.delay_msec(5)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 3]:
		_finish(false, {})
		return
	var role := args[0]
	var root := args[1]
	if role == "keys":
		_finish(_keys(root), {})
		return
	var issuer_public := CryptoKey.new()
	var recipient_public := CryptoKey.new()
	if (issuer_public.load(root.path_join("issuer.pub"), true) != OK
			or recipient_public.load(root.path_join("recipient.pub"), true) != OK):
		_finish(false, {})
		return
	var binding := ProfileGrant.Binding.new()
	binding.run = "wp23-native"
	binding.rules = "V42.6/R1"
	binding.catalog = "wp23-fixture"
	binding.recipient = "bob"
	binding.issuer = issuer_public
	binding.recipient_key = recipient_public
	var local := ""
	if role in ["solo-issue", "inspect-solo"]:
		local = "solo"
	elif role in ["ordinary-write", "inspect-ordinary"]:
		local = "ordinary"
	elif role == "ordinary-full":
		local = "capacity"
	elif role == "ordinary-elapsed":
		local = "elapsed"
	if not local.is_empty():
		binding.recipient = local
		binding.recipient_key = issuer_public
	var issuer_role := role in ["issue", "inspect-issuer", "courier", "ack"]
	var store := FaultStore.new()
	store.point = args[2] if args.size() == 3 else ""
	store.marker = root.path_join("boundary")
	var profile := local if not local.is_empty() else ("alice" if issuer_role else "bob")
	if store.open(profile, root.path_join("profiles")) != ProfileStore.OpenResult.OPENED:
		_finish(false, {})
		return
	var result: Dictionary
	match role:
		"issue", "solo-issue": result = _issue(store, root, binding)
		"ordinary-write", "ordinary-full": result = _ordinary(store, root, binding, role == "ordinary-full")
		"ordinary-elapsed": result = await _elapsed(store, root, binding)
		"inspect-issuer", "inspect-recipient", "inspect-solo", "inspect-ordinary":
			var frontier := store.frontier(binding.run)
			result = {"pending": store.pending_grants().size(),
				"generation": store.checkpoint()["generation"], "tick": frontier.get("tick", -1),
				"balance": store.balance(Currency).native_at_scale(0)}
		"courier":
			var queued := store.pending_grants()
			if queued.size() == 1 and _write(root.path_join("grant.bin"), queued[0].body):
				result = {"pending": 1}
		"apply":
			var key := CryptoKey.new()
			if key.load(root.path_join("recipient.key")) == OK:
				var applied := ProfileGrantSettlement.apply(store, binding, key, FileAccess.get_file_as_bytes(root.path_join("grant.bin")))
				if (applied.receipt.status in [Commit.COMMITTED, Commit.DUPLICATE]
						and not applied.acknowledgement.is_empty()
						and _write(root.path_join("ack.bin"), applied.acknowledgement)):
					result = {"status": applied.receipt.status, "balance": store.balance(Currency).native_at_scale(0)}
		"ack":
			var acked := ProfileGrantSettlement.acknowledge(store, binding, FileAccess.get_file_as_bytes(root.path_join("ack.bin")))
			if acked.status in [Commit.COMMITTED, Commit.DUPLICATE]:
				result = {"status": acked.status, "pending": store.pending_grants().size()}
	_finish(store.close() and not result.is_empty(), result)


func _elapsed(store: ProfileStore, root: String, binding: ProfileGrant.Binding) -> Dictionary:
	var key := CryptoKey.new()
	if key.load(root.path_join("issuer.key")) != OK:
		return {}
	var earnings := OrdinaryCurrency.begin(store, binding, key, Currency)
	if earnings == null or earnings.accrue("enemy/1", Quantity.from_count(17)) != OrdinaryCurrency.Eligibility.QUEUED:
		return {}
	var beginning := earnings.oldest_eligible_usec()
	await _wait_until(beginning + OrdinaryCurrency.DISPATCH_AGE_USEC)
	var first := earnings.dispatch()
	if first.is_empty() or earnings.accrue("enemy/2", Quantity.from_count(23)) != OrdinaryCurrency.Eligibility.QUEUED:
		return {}
	var newer := earnings.dispatch(true)
	if (newer.is_empty() or earnings.write_batch(newer).status != Commit.COMMITTED
			or earnings.confirm_batch(newer).status != Commit.COMMITTED or not earnings.can_earn()):
		return {}
	var newer_age := Time.get_ticks_usec() - beginning
	await _wait_until(beginning + OrdinaryCurrency.MAX_AGE_USEC)
	var fenced := not earnings.can_earn()
	var observed_age := Time.get_ticks_usec() - beginning
	var preserved := earnings.oldest_eligible_usec() == beginning and store.lookup(first).status == Commit.MISSING
	var settled := earnings.flush()
	print("WP23_TIMING ", JSON.stringify({"newer_commit_usec": newer_age, "fence_observed_usec": observed_age}))
	return {"newer_before_deadline": newer_age < OrdinaryCurrency.MAX_AGE_USEC,
		"fenced": fenced, "original_preserved": preserved, "settled": settled and earnings.can_earn(),
		"balance": store.balance(Currency).native_at_scale(0), "generation": store.checkpoint()["generation"]}


func _wait_until(deadline: int) -> void:
	var remaining := deadline - Time.get_ticks_usec()
	while remaining > 0:
		await get_tree().create_timer(float(remaining) / 1_000_000.0, true, false, true).timeout
		remaining = deadline - Time.get_ticks_usec()


static func _ordinary(store: FaultStore, root: String, binding: ProfileGrant.Binding, pressure: bool) -> Dictionary:
	var key := CryptoKey.new()
	if key.load(root.path_join("issuer.key")) != OK:
		return {}
	var clock := FixtureClock.new()
	var earnings := OrdinaryCurrency.begin(store, binding, key, Currency, clock.sample)
	if earnings == null:
		return {}
	var limit := store.page_limit()
	if pressure and not store.set_page_limit(store.writable_pages()):
		return {}
	for index: int in range(OrdinaryCurrency.MAX_BATCH if pressure else 2):
		if earnings.accrue("enemy/%d" % index, Quantity.from_count(index + 1)) != OrdinaryCurrency.Eligibility.QUEUED:
			return {}
	var operation := earnings.dispatch(true)
	if operation.is_empty():
		var replayed := earnings.flush()
		return {"balance": store.balance(Currency).native_at_scale(0), "already_issued": replayed}
	var posted := earnings.write_batch(operation)
	if pressure:
		clock.elapsed = OrdinaryCurrency.MAX_AGE_USEC
		if (posted.status != Commit.UNAVAILABLE or earnings.confirm_batch(operation).status != Commit.MISSING
				or earnings.can_earn() or earnings.oldest_eligible_usec() != 0
				or store.balance(Currency).native_at_scale(0) != 0):
			return {}
		if not store.set_page_limit(limit):
			return {}
		clock.elapsed += 250_000
	elif posted.status != Commit.COMMITTED:
		return {}
	var settled := earnings.flush()
	return {"balance": store.balance(Currency).native_at_scale(0), "settled": settled,
		"generation": store.checkpoint()["generation"], "fault_usec": earnings.fault_elapsed_usec(),
		"fenced": not earnings.can_earn(), "same_operation": store.lookup(operation).status == Commit.COMMITTED}


static func _issue(store: ProfileStore, root: String, binding: ProfileGrant.Binding) -> Dictionary:
	var key := CryptoKey.new()
	if key.load(root.path_join("issuer.key")) != OK:
		return {}
	var award := ProfileGrantSettlement.Entitlement.new()
	award.binding = binding
	award.occurrence = "regional-boss/first"
	award.kind = ProfileGrant.Kind.CURRENCY
	award.award = Currency
	award.amount = Quantity.from_count(17)
	var frontier := ProfileMutation.Frontier.new()
	frontier.run = binding.run
	frontier.epoch = 1
	frontier.tick = 4
	frontier.image = var_to_bytes(["closed", 4, award.occurrence])
	var issued := ProfileGrantSettlement.issue(store, key, [award], frontier)
	return {"status": issued.status} if issued.status in [Commit.COMMITTED, Commit.DUPLICATE] else {}


static func _keys(root: String) -> bool:
	var crypto := Crypto.new()
	for role: String in ["issuer", "recipient"]:
		var key := crypto.generate_rsa(2048)
		if (key == null or key.save(root.path_join(role + ".key")) != OK
				or key.save(root.path_join(role + ".pub"), true) != OK):
			return false
	return true


static func _write(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null or data.is_empty():
		return false
	file.store_buffer(data)
	return file.get_error() == OK


func _finish(passed: bool, result: Dictionary) -> void:
	result["passed"] = passed
	print("WP23_GRANT ", JSON.stringify(result))
	get_tree().quit(0 if passed else 1)
