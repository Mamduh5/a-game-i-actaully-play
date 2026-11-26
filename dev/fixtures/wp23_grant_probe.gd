extends Node
## Native process-fault witness. Files carry the signed grant and receipt
## between disposable profile processes so each durable boundary is observable.

const Currency := "currency/permanent"
const Commit := ProfileStore.CommitResult

class FaultStore extends ProfileStore:
	var point: String
	var marker: String

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
	var issuer_role := role in ["issue", "inspect-issuer", "courier", "ack"]
	var store := FaultStore.new()
	store.point = args[2] if args.size() == 3 else ""
	store.marker = root.path_join("boundary")
	if store.open("alice" if issuer_role else "bob", root.path_join("profiles")) != ProfileStore.OpenResult.OPENED:
		_finish(false, {})
		return
	var result: Dictionary
	match role:
		"issue": result = _issue(store, root, binding)
		"inspect-issuer", "inspect-recipient":
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
