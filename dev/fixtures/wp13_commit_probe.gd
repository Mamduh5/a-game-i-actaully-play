extends Node

class BoundaryStore extends ProfileStore:
	var boundary: String
	var signal_path: String

	func _commit_io() -> bool:
		if boundary == "before":
			_hold()
		var committed := super._commit_io()
		if committed and boundary == "after":
			_hold()
		return committed

	func _hold() -> void:
		var ready := FileAccess.open(signal_path, FileAccess.WRITE)
		if ready == null:
			return
		ready.store_8(1)
		ready.close()
		OS.delay_msec(15000)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		get_tree().quit(2)
		return
	var root := args[0]
	var mode := args[1]
	var store := BoundaryStore.new()
	var status := store.open("alpha", root)
	var result := {"open": ProfileStore.OpenResult.keys()[status]}
	if status != ProfileStore.OpenResult.OPENED:
		_finish(result)
		return
	if mode in ["before", "after"]:
		if args.size() != 3:
			get_tree().quit(2)
			return
		store.boundary = mode
		store.signal_path = args[2]
		var receipt := store.commit(_transaction(mode, 100 if mode == "before" else 11, 2 if mode == "before" else 3))
		result["fault_returned"] = ProfileStore.CommitResult.keys()[receipt.status]
	elif mode == "seed":
		result["seed"] = ProfileStore.CommitResult.keys()[store.commit(_transaction("seed", 7, 1)).status]
	elif mode == "replay":
		result["replay"] = ProfileStore.CommitResult.keys()[store.commit(_transaction("after", 11, 3)).status]
		result["conflict"] = ProfileStore.CommitResult.keys()[store.commit(_transaction("after", 12, 3)).status]
	elif mode != "inspect":
		get_tree().quit(2)
		return
	result["balance"] = store.balance("coins").native_at_scale(0)
	result["head"] = store.checkpoint()["generation"]
	result["frontier"] = store.frontier("run").get("tick", -1)
	var pending: Array[String] = []
	for entry: Dictionary in store.pending_grants():
		pending.append(entry.grant_key)
	result["pending_grants"] = pending
	for id: String in ["seed", "before", "after"]:
		result[id + "_receipt"] = ProfileStore.CommitResult.keys()[store.lookup(id).status]
	result["closed"] = store.close()
	_finish(result)


func _finish(result: Dictionary) -> void:
	print("WP13_COMMIT ", JSON.stringify(result))
	get_tree().quit(0)


static func _transaction(id: String, amount: int, tick: int) -> ProfileMutation:
	var request := ProfileMutation.new()
	request.id = id
	request.rules = "V42.6/R1"
	request.catalog = "fixture"
	request.deltas["coins"] = Quantity.from_count(amount)
	request.claims = [id + "-claim"]
	var grant := ProfileMutation.Grant.new()
	grant.key = id + "-grant"
	grant.recipient = "beta"
	grant.envelope = id.to_utf8_buffer()
	request.grants = [grant]
	request.frontier = ProfileMutation.Frontier.new()
	request.frontier.run = "run"
	request.frontier.epoch = 1
	request.frontier.tick = tick
	request.frontier.image = PackedByteArray([0, tick, 0, 255])
	return request
