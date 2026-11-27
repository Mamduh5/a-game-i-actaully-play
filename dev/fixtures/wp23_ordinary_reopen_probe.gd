extends Node
## The native driver stops only the disposable process on either side of COMMIT.

const ACCOUNT := "currency/permanent"
const SHELL := preload("res://src/app/main.tscn")

class BoundaryStore extends ProfileStore:
	var boundary: String
	var signal_path: String

	func _commit_io() -> bool:
		if boundary == "before":
			_wait_for_termination()
		var committed := super._commit_io()
		if committed and boundary == "after":
			_wait_for_termination()
		return committed

	func _wait_for_termination() -> void:
		var ready := FileAccess.open(signal_path, FileAccess.WRITE)
		if ready != null:
			ready.store_8(1)
			ready.close()
			OS.delay_msec(15000)

var _store := BoundaryStore.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3 or args[0] not in ["before", "after", "orderly", "read"]:
		get_tree().quit(2)
		return
	var mode := args[0]
	if _store.open("alice", args[1]) != ProfileStore.OpenResult.OPENED:
		get_tree().quit(3)
		return
	var shell := SHELL.instantiate()
	add_child(shell)
	if not shell.bind_profile(_store):
		get_tree().quit(4)
		return
	if mode == "read":
		await _readback(shell, args[2] if args.size() == 3 else "")
		return
	var setup := RunSetup.new()
	setup.run_id = &"ordinary-reopen"
	setup.epoch = 1
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.authority_id = &"alice"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"alice": &"overworld"}
	var key := Crypto.new().generate_rsa(2048)
	var binding := ProfileGrant.Binding.new()
	binding.run = setup.run_id
	binding.rules = setup.rules_revision
	binding.catalog = setup.catalog_revision
	binding.recipient = "alice"
	binding.issuer = key
	binding.recipient_key = key
	var earnings := OrdinaryCurrency.begin(_store, binding, key, ACCOUNT)
	var authority := RunAuthority.new()
	if (not authority.start(setup, setup.authority_id) or not authority.attach_ordinary_currency(earnings)
			or not shell.bind_run(authority) or earnings.accrue("earlier-enemy", Quantity.from_count(7)) != OrdinaryCurrency.Eligibility.QUEUED
			or not earnings.flush() or earnings.accrue("last-enemy", Quantity.from_count(11)) != OrdinaryCurrency.Eligibility.QUEUED):
		get_tree().quit(5)
		return
	if mode == "orderly":
		shell.request_orderly_quit()
		return
	if args.size() == 3:
		_store.boundary = mode
		_store.signal_path = args[2]
		earnings.flush()
	get_tree().quit(6)


func _readback(shell: Control, capture: String) -> void:
	var label := shell.get_node("%IdentityLabel") as Label
	var amount: Variant = _store.balance(ACCOUNT).native_at_scale(0)
	var notice := label.text.ends_with(shell.ORDINARY_EXPOSURE_TEXT)
	print("WP23_REOPEN ", JSON.stringify({"balance": amount, "generation": _store.checkpoint()["generation"], "notice": notice}))
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(capture) != OK:
			get_tree().quit(7)
			return
	get_tree().quit(0 if _store.close() else 8)


func _exit_tree() -> void:
	if not _store.identity().is_empty():
		_store.close()
