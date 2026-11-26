extends GutTest

const Commit := ProfileStore.CommitResult
const Currency := "currency/permanent"

class UnconfirmedStore extends ProfileStore:
	var persist := false

	func _commit_io() -> bool:
		if persist:
			super._commit_io()
		return false

var _issuer: CryptoKey
var _guest: CryptoKey
var _outsider: CryptoKey


func before_all() -> void:
	var crypto := Crypto.new()
	_issuer = crypto.generate_rsa(2048)
	_guest = crypto.generate_rsa(2048)
	_outsider = crypto.generate_rsa(2048)


func test_signed_envelope_binds_original_run_recipient_and_rules() -> void:
	var paired := _binding()
	var amount := Quantity.from_canonical(false, 0, "1" + "0".repeat(400))
	var signed := ProfileGrant.sign_authorization(paired, _issuer, "regional-boss-61", ProfileGrant.Kind.CURRENCY,
		Currency, amount)
	var grant := ProfileGrant.open_authorization(signed, paired)
	assert_not_null(grant)
	assert_eq(grant.amount.compare(amount), 0)
	assert_eq(grant.digest, ProfileMutation.sha256(signed))
	assert_true(ProfileGrant.sign_authorization(paired, _outsider, "regional-boss-61", ProfileGrant.Kind.CURRENCY,
		Currency, amount).is_empty())
	var other := _binding()
	other.run = "another-run"
	assert_null(ProfileGrant.open_authorization(signed, other))
	other = _binding()
	other.rules = "another-rule"
	assert_null(ProfileGrant.open_authorization(signed, other))
	other = _binding()
	other.recipient = "eve"
	assert_null(ProfileGrant.open_authorization(signed, other))
	other = _binding()
	other.issuer = _public(_outsider)
	assert_null(ProfileGrant.open_authorization(signed, other))
	other = _binding()
	other.recipient_key = _public(_outsider)
	assert_null(ProfileGrant.open_authorization(signed, other))
	var changed := signed.duplicate()
	changed[30] ^= 1
	assert_null(ProfileGrant.open_authorization(changed, paired))
	assert_null(ProfileGrant.open_authorization(signed.slice(0, signed.size() - 1), paired))
	assert_true(grant.sign_acknowledgement(null, _guest).is_empty())


func test_important_issue_applies_once_after_reopen_and_ack_compacts_exact_receipt() -> void:
	if not OS.has_feature("windows"):
		return
	var host_root := DirAccess.create_temp("agip-grant-host")
	var guest_root := DirAccess.create_temp("agip-grant-guest")
	var host := ProfileStore.new()
	var guest := ProfileStore.new()
	var paired := _binding()
	assert_eq(host.open("alice", host_root.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(guest.open("bob", guest_root.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var entitlement := _entitlement(paired, "quest-92", 17)
	var frontier := _frontier(paired.run, 10)
	var issue := ProfileGrantSettlement.issue(host, _issuer, [entitlement], frontier)
	assert_eq(issue.status, Commit.COMMITTED)
	assert_eq(host.frontier(paired.run)["image"], frontier.image)
	assert_eq(host.balance(Currency).native_at_scale(0), 0)
	assert_eq(ProfileGrantSettlement.issue(host, _issuer, [entitlement], frontier).status, Commit.DUPLICATE)
	assert_eq(host.pending_grants().size(), 1)
	var packet: PackedByteArray = host.pending_grants()[0].body
	var item := ProfileGrant.open_authorization(packet, paired)
	var applied := ProfileGrantSettlement.apply(guest, paired, _guest, packet)
	assert_eq(applied.receipt.status, Commit.COMMITTED)
	assert_true(not applied.acknowledgement.is_empty())
	assert_eq(guest.balance(Currency).native_at_scale(0), 17)
	assert_eq(host.pending_grants().size(), 1)
	assert_true(host.close())
	assert_true(guest.close())
	assert_eq(guest.open("bob", guest_root.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(host.open("alice", host_root.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var redelivered := ProfileGrantSettlement.apply(guest, paired, _guest, host.pending_grants()[0].body)
	assert_eq(redelivered.receipt.status, Commit.DUPLICATE)
	assert_eq(redelivered.receipt.generation, applied.receipt.generation)
	assert_eq(redelivered.acknowledgement, applied.acknowledgement)
	assert_eq(guest.balance(Currency).native_at_scale(0), 17)
	assert_eq(ProfileGrantSettlement.acknowledge(host, paired, redelivered.acknowledgement).status, Commit.COMMITTED)
	assert_eq(ProfileGrantSettlement.acknowledge(host, paired, redelivered.acknowledgement).status, Commit.DUPLICATE)
	assert_true(host.pending_grants().is_empty())
	assert_null(host.grant(item.key)["body"])
	assert_eq(host.grant(item.key)["digest"], item.digest)
	assert_true(host.close())
	assert_true(guest.close())


func test_receipts_keep_out_of_order_gaps_and_reject_changed_grant_or_ack() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-grant-gap")
	var host := ProfileStore.new()
	var guest := ProfileStore.new()
	assert_eq(host.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var binding := _binding()
	for index: int in range(1, 4):
		var item := _entitlement(binding, "bounty-%d" % index, index)
		assert_eq(ProfileGrantSettlement.issue(host, _issuer, [item], _frontier(binding.run, index)).status, Commit.COMMITTED)
	var queued := host.pending_grants()
	var middle: PackedByteArray = queued[1].body
	var original := ProfileGrant.open_authorization(middle, binding)
	var unpaid := ProfileGrantSettlement.apply(guest, binding, _outsider, middle)
	assert_eq(unpaid.receipt.status, Commit.INVALID)
	assert_true(unpaid.acknowledgement.is_empty())
	var applied := ProfileGrantSettlement.apply(guest, binding, _guest, middle)
	assert_eq(applied.receipt.status, Commit.COMMITTED)
	var altered := ProfileGrant.sign_authorization(binding, _issuer, original.occurrence, original.kind, original.award,
		original.amount.add(Quantity.from_count(9)))
	assert_eq(ProfileGrant.open_authorization(altered, binding).key, original.key)
	var duplicate_with_new_value := ProfileGrantSettlement.apply(guest, binding, _guest, altered)
	assert_eq(duplicate_with_new_value.receipt.status, Commit.CONFLICT)
	assert_true(duplicate_with_new_value.acknowledgement.is_empty())
	var forged_fields: Array = binding.fields()
	forged_fields.append_array([original.key, original.digest, "a".repeat(64)])
	var wrong_proof := ProfileGrant._sign(ProfileGrant.ACK_DOMAIN, forged_fields, _guest)
	assert_eq(ProfileGrantSettlement.acknowledge(host, binding, wrong_proof).status, Commit.INVALID)
	assert_eq(ProfileGrantSettlement.acknowledge(host, binding, applied.acknowledgement).status, Commit.COMMITTED)
	assert_eq(ProfileGrantSettlement.acknowledge(host, binding, wrong_proof).status, Commit.CONFLICT)
	var different_run := _binding()
	different_run.run = "another-run"
	var rebound: Array = different_run.fields()
	rebound.append_array([original.key, original.digest, applied.receipt.digest])
	var wrong_run := ProfileGrant._sign(ProfileGrant.ACK_DOMAIN, rebound, _guest)
	assert_eq(ProfileGrantSettlement.acknowledge(host, different_run, wrong_run).status, Commit.CONFLICT)
	assert_eq(host.pending_grants().size(), 2)
	for row: Dictionary in host.pending_grants():
		var remaining := ProfileGrantSettlement.apply(guest, binding, _guest, row.body)
		assert_eq(remaining.receipt.status, Commit.COMMITTED)
		assert_eq(ProfileGrantSettlement.acknowledge(host, binding, remaining.acknowledgement).status, Commit.COMMITTED)
	assert_true(host.pending_grants().is_empty())
	assert_eq(guest.balance(Currency).native_at_scale(0), 6)
	assert_true(host.close())
	assert_true(guest.close())


func test_issuance_is_replay_stable_for_several_recipients_and_rolls_back_on_stale_frontier() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-grant-recipients")
	var issuer_store := ProfileStore.new()
	assert_eq(issuer_store.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var first := _binding()
	var other := _binding()
	other.recipient = "ruth"
	other.recipient_key = _public(_outsider)
	var bob := _entitlement(first, "boss-82", 3)
	var ruth := _entitlement(other, "boss-82", 5)
	var frontier := _frontier(first.run, 9)
	assert_eq(ProfileGrantSettlement.issue(issuer_store, _issuer, [bob, ruth], frontier).status, Commit.COMMITTED)
	assert_eq(ProfileGrantSettlement.issue(issuer_store, _issuer, [ruth, bob], frontier).status, Commit.DUPLICATE)
	ruth.amount = Quantity.from_count(6)
	assert_eq(ProfileGrantSettlement.issue(issuer_store, _issuer, [bob, ruth], frontier).status, Commit.CONFLICT)
	assert_eq(ProfileGrantSettlement.issue(issuer_store, _issuer, [_entitlement(first, "old-event", 11)],
		_frontier(first.run, 8)).status, Commit.STALE_FRONTIER)
	assert_eq(issuer_store.pending_grants().size(), 2)
	assert_eq(issuer_store.checkpoint()["generation"], 1)
	assert_eq(issuer_store.frontier(first.run)["tick"], 9)
	assert_true(issuer_store.close())


func test_unknown_application_only_acknowledges_a_durable_match() -> void:
	if not OS.has_feature("windows"):
		return
	for committed: bool in [false, true]:
		var scratch := DirAccess.create_temp("agip-grant-unconfirmed")
		var guest := UnconfirmedStore.new()
		assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
		var binding := _binding()
		var packet := ProfileGrant.sign_authorization(binding, _issuer, "victory", ProfileGrant.Kind.CURRENCY,
			Currency, Quantity.from_count(11))
		guest.persist = committed
		var applied := ProfileGrantSettlement.apply(guest, binding, _guest, packet)
		assert_eq(applied.receipt.status, Commit.COMMITTED if committed else Commit.MISSING)
		assert_eq(applied.acknowledgement.is_empty(), not committed)
		assert_eq(guest.balance(Currency).native_at_scale(0), 11 if committed else 0)
		guest.persist = true
		var retried := ProfileGrantSettlement.apply(guest, binding, _guest, packet)
		assert_eq(retried.receipt.status, Commit.DUPLICATE if committed else Commit.COMMITTED)
		assert_false(retried.acknowledgement.is_empty())
		assert_eq(guest.balance(Currency).native_at_scale(0), 11)
		assert_true(guest.close())


func test_discovery_is_unique_across_issuer_and_occurrence() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-grant-discovery")
	var guest := ProfileStore.new()
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var first := _binding()
	var late := _binding()
	late.issuer = _public(_outsider)
	late.run = "later-run"
	var one := Quantity.from_count(1)
	var earned := ProfileGrant.sign_authorization(first, _issuer, "forge-1", ProfileGrant.Kind.DISCOVERY, "rune-R04", one)
	var later_issuer := ProfileStore.new()
	assert_eq(later_issuer.open("ruth", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var discovered := _entitlement(late, "forge-2", 1)
	discovered.kind = ProfileGrant.Kind.DISCOVERY
	discovered.award = "rune-R04"
	assert_eq(ProfileGrantSettlement.issue(later_issuer, _outsider, [discovered], _frontier(late.run, 1)).status, Commit.COMMITTED)
	var repeated: PackedByteArray = later_issuer.pending_grants()[0].body
	assert_eq(ProfileGrantSettlement.apply(guest, first, _guest, earned).receipt.status, Commit.COMMITTED)
	var duplicate := ProfileGrantSettlement.apply(guest, late, _guest, repeated)
	assert_eq(duplicate.receipt.status, Commit.COMMITTED)
	assert_false(duplicate.acknowledgement.is_empty())
	var replay := ProfileGrantSettlement.apply(guest, late, _guest, repeated)
	assert_eq(replay.receipt.status, Commit.DUPLICATE)
	assert_eq(replay.acknowledgement, duplicate.acknowledgement)
	assert_eq(guest.balance("discovery/rune-R04").native_at_scale(0), 1)
	assert_eq(guest.checkpoint()["generation"], 2)
	assert_eq(ProfileGrantSettlement.acknowledge(later_issuer, late, replay.acknowledgement).status, Commit.COMMITTED)
	assert_true(later_issuer.pending_grants().is_empty())
	assert_true(later_issuer.close())
	assert_true(guest.close())


func test_original_pairing_survives_backup_and_conflicting_reenrollment() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-grant-trust")
	var guest := ProfileStore.new()
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var binding := _binding()
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, binding, _issuer).status, Commit.INVALID)
	var first := ProfileGrantSettlement.retain_original_binding(guest, binding, _guest)
	assert_eq(first.status, Commit.COMMITTED)
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, binding, _guest).status, Commit.DUPLICATE)
	var other := _binding()
	other.issuer = _public(_outsider)
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, other, _guest).status, Commit.CONFLICT)
	other = _binding()
	other.catalog = "new-catalog"
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, other, _guest).status, Commit.CONFLICT)
	assert_eq(guest.checkpoint()["generation"], 1)
	assert_eq(guest.save_backup("paired"), ProfileStore.BackupResult.SAVED)
	assert_eq(guest.restore_backup("paired", first.generation, first.anchor), ProfileStore.BackupResult.RESTORED)
	assert_true(guest.close())
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var retained := guest.grant_binding(binding.run, binding.recipient)
	assert_eq(retained.fields(), binding.fields())
	assert_true(retained.issuer.is_public_only())
	assert_true(retained.recipient_key.is_public_only())
	assert_null(guest.grant_binding("new-run", binding.recipient))
	assert_null(guest.grant_binding(binding.run, "eve"))
	assert_true(guest.close())


func test_native_exchange_requires_retained_pairing_and_identical_durable_payload() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-grant-exchange")
	var issuer := ProfileStore.new()
	var guest := ProfileStore.new()
	assert_eq(issuer.open("alice", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(guest.open("bob", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var binding := _binding()
	var issuing := ProfileGrantExchange.new(issuer, _issuer)
	var receiving := ProfileGrantExchange.new(guest, _guest)
	var item := _entitlement(binding, "quest-11", 17)
	assert_eq(ProfileGrantSettlement.issue(issuer, _issuer, [item], _frontier(binding.run, 7)).status, Commit.COMMITTED)
	var row: Dictionary = issuer.pending_grants()[0]
	assert_true(issuing.delivery(binding.run, "bob", row.grant_key).is_empty())
	assert_eq(ProfileGrantSettlement.retain_original_binding(issuer, binding, _issuer).status, Commit.COMMITTED)
	assert_true(issuing.delivery(binding.run, "eve", row.grant_key).is_empty())
	var payload := issuing.delivery(binding.run, "bob", row.grant_key)
	var decoded := _grant_frame(payload)
	assert_true(ProfileGrantExchange.recognizes(decoded))
	assert_eq(receiving.receive(decoded).receipt.status, Commit.INVALID)
	assert_eq(guest.balance(Currency).native_at_scale(0), 0)
	assert_eq(ProfileGrantSettlement.retain_original_binding(guest, binding, _guest).status, Commit.COMMITTED)
	var wrong_channel := _grant_frame(payload, NativeSessionFrame.Kind.SEQUENCED)
	assert_eq(receiving.receive(wrong_channel).receipt.status, Commit.INVALID)
	var changed := payload.duplicate()
	changed[changed.size() - 1] ^= 1
	assert_eq(receiving.receive(_grant_frame(changed)).receipt.status, Commit.INVALID)
	var changed_route := payload.duplicate()
	changed_route[ProfileGrantExchange.HEADER] = 97
	assert_eq(receiving.receive(_grant_frame(changed_route)).receipt.status, Commit.INVALID)
	assert_eq(guest.checkpoint()["generation"], 1)
	var accepted := receiving.receive(decoded)
	var duplicated := receiving.receive(decoded)
	assert_eq(accepted.receipt.status, Commit.COMMITTED)
	assert_eq(duplicated.receipt.status, Commit.DUPLICATE)
	assert_eq(duplicated.reply, accepted.reply)
	assert_eq(guest.balance(Currency).native_at_scale(0), 17)
	assert_eq(issuer.pending_grants().size(), 1)
	assert_eq(issuing.receive(_grant_frame(duplicated.reply)).receipt.status, Commit.COMMITTED)
	assert_eq(issuing.receive(_grant_frame(accepted.reply)).receipt.status, Commit.DUPLICATE)
	assert_true(issuer.pending_grants().is_empty())
	assert_true(issuing.delivery(binding.run, "bob", row.grant_key).is_empty())
	assert_eq(issuer.grant(row.grant_key)["digest"], row.digest)
	assert_true(issuer.close())
	assert_true(guest.close())


static func _grant_frame(payload: PackedByteArray,
		kind: NativeSessionFrame.Kind = NativeSessionFrame.Kind.RELIABLE) -> NativeSessionFrame:
	var packet := NativeSessionFrame.pack(kind, 3, 1, payload)
	return NativeSessionFrame.read(packet, NativeSessionFrame.channel(kind))


func _binding() -> ProfileGrant.Binding:
	var result := ProfileGrant.Binding.new()
	result.recipient = "bob"
	result.run = "original-run"
	result.rules = "V42.6/R1"
	result.catalog = "catalog-1"
	result.issuer = _public(_issuer)
	result.recipient_key = _public(_guest)
	return result


static func _public(key: CryptoKey) -> CryptoKey:
	var copy := CryptoKey.new()
	copy.load_from_string(key.save_to_string(true), true)
	return copy


static func _entitlement(binding: ProfileGrant.Binding, occurrence: String, value: int) -> ProfileGrantSettlement.Entitlement:
	var result := ProfileGrantSettlement.Entitlement.new()
	result.binding = binding
	result.occurrence = occurrence
	result.kind = ProfileGrant.Kind.CURRENCY
	result.award = Currency
	result.amount = Quantity.from_count(value)
	return result


static func _frontier(run: String, tick: int) -> ProfileMutation.Frontier:
	var result := ProfileMutation.Frontier.new()
	result.run = run
	result.epoch = 1
	result.tick = tick
	result.image = var_to_bytes({"closed_tick": tick})
	return result
