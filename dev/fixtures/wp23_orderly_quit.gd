extends Node
## A disposable process with the actual Main shell and an isolated profile.
## The driver requests a native window close, then launches a fresh readback.

const ACCOUNT := "currency/permanent"

class RetryStore extends ProfileStore:
	var attempts := 0

	func _commit_io() -> bool:
		attempts += 1
		if attempts == 1:
			print("WP23_QUIT first commit refused")
			return false
		return super._commit_io()

var _store: ProfileStore


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["write", "read"]:
		get_tree().quit(2)
		return
	var readback := args[0] == "read"
	_store = ProfileStore.new() if readback else RetryStore.new()
	if _store.open("alice", args[1]) != ProfileStore.OpenResult.OPENED:
		get_tree().quit(3)
		return
	if readback:
		var balance: Variant = _store.balance(ACCOUNT).native_at_scale(0)
		var generation: int = _store.checkpoint()["generation"]
		print("WP23_QUIT balance=%d generation=%d" % [balance, generation])
		var closed := _store.close()
		get_tree().quit(0 if closed and balance == 17 and generation == 1 else 4)
		return
	var setup := RunSetup.new()
	setup.run_id = &"quit-probe"
	setup.epoch = 1
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.authority_id = &"alice"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"alice": &"overworld"}
	var authority := RunAuthority.new()
	var key := Crypto.new().generate_rsa(2048)
	var binding := ProfileGrant.Binding.new()
	binding.run = setup.run_id
	binding.rules = setup.rules_revision
	binding.catalog = setup.catalog_revision
	binding.recipient = "alice"
	binding.issuer = key
	binding.recipient_key = key
	var earnings := OrdinaryCurrency.begin(_store, binding, key, ACCOUNT)
	var shell := preload("res://src/app/main.tscn").instantiate()
	add_child(shell)
	if (not authority.start(setup, setup.authority_id) or not authority.attach_ordinary_currency(earnings)
			or not shell.bind_run(authority) or earnings.accrue("last-enemy", Quantity.from_count(17)) != OrdinaryCurrency.Eligibility.QUEUED):
		get_tree().quit(5)
		return
	print("WP23_QUIT awaiting native close")


func _exit_tree() -> void:
	if _store != null and not _store.identity().is_empty():
		_store.close()
