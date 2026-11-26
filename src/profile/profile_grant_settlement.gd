class_name ProfileGrantSettlement
extends RefCounted
## Durable operations for important permanent grants. Remote applications
## use the original run's paired keys. Local awards post with issuance.

class Entitlement:
	var binding: ProfileGrant.Binding
	var occurrence: String
	var kind: ProfileGrant.Kind
	var award: String
	var amount: Quantity

class Application:
	var receipt: ProfileStore.Receipt
	var acknowledgement: PackedByteArray


## Called at original pairing from the local identity and authenticated peer
## identities. Receiving an envelope never enrolls or replaces a binding.
static func retain_original_binding(store: ProfileStore, binding: ProfileGrant.Binding,
		local_key: CryptoKey) -> ProfileStore.Receipt:
	if store == null or binding == null or not binding.is_valid() or local_key == null or local_key.is_public_only():
		return _invalid()
	var expected := binding.recipient_key if store.identity() == binding.recipient else binding.issuer
	if ProfileGrant.fingerprint(local_key) != ProfileGrant.fingerprint(expected):
		return _invalid()
	return store.commit_confirmed(ProfileMutation.retain_binding(binding))


## One transaction records the shared occurrence, each personal envelope
## and the replayable authoritative frontier. The caller owns eligibility.
static func issue(store: ProfileStore, issuer: CryptoKey, entitlements: Array[Entitlement],
		frontier: ProfileMutation.Frontier, authority: RunAuthority = null) -> ProfileStore.Receipt:
	if (store == null or frontier == null or entitlements.is_empty()
			or entitlements.size() > ProfileMutation.MAX_ITEMS
			or (authority != null and not authority.belongs_to(StringName(frontier.run), frontier.epoch))):
		return _invalid()
	var mutation := ProfileMutation.new()
	mutation.frontier = frontier
	var local: ProfileGrant
	for entitlement: Entitlement in entitlements:
		if entitlement == null or entitlement.binding == null or entitlement.binding.run != frontier.run:
			return _invalid()
		var bound := entitlement.binding
		var bytes := ProfileGrant.sign_authorization(bound, issuer, entitlement.occurrence,
			entitlement.kind, entitlement.award, entitlement.amount)
		var grant := ProfileGrant.open_authorization(bytes, bound)
		if grant == null:
			return _invalid()
		if mutation.id.is_empty():
			mutation.id = grant.issue_id()
			mutation.rules = bound.rules
			mutation.catalog = bound.catalog
			mutation.claims.append(mutation.id)
		elif mutation.id != grant.issue_id() or mutation.rules != bound.rules or mutation.catalog != bound.catalog:
			return _invalid()
		if bound.recipient == store.identity():
			if local != null or ProfileGrant.fingerprint(bound.recipient_key) != ProfileGrant.fingerprint(issuer):
				return _invalid()
			local = grant
			continue
		var saved := ProfileMutation.Grant.new()
		saved.key = grant.key
		saved.recipient = bound.recipient
		saved.envelope = bytes
		mutation.grants.append(saved)
	if authority != null:
		for entitlement: Entitlement in entitlements:
			if not authority.flush_ordinary_currency(entitlement.binding.recipient):
				var pending := ProfileStore.Receipt.new()
				pending.id = mutation.id
				pending.status = ProfileStore.CommitResult.UNAVAILABLE
				return pending
	return _issue_with_local(store, mutation, local) if local != null else store.commit_confirmed(mutation)


static func _issue_with_local(store: ProfileStore, mutation: ProfileMutation, local: ProfileGrant) -> ProfileStore.Receipt:
	var application := local.application()
	mutation.deltas = application.deltas
	mutation.claims.append_array(application.claims)
	if local.kind != ProfileGrant.Kind.DISCOVERY:
		return store.commit_confirmed(mutation)
	var previous := store.lookup(mutation.id)
	if previous.status == ProfileStore.CommitResult.COMMITTED:
		if previous.digest == mutation.record().sha256_text():
			previous.status = ProfileStore.CommitResult.DUPLICATE
			return previous
		# The original transaction may have recorded an already known discovery.
	elif previous.status == ProfileStore.CommitResult.MISSING:
		var known := store.balance("discovery/" + local.award)
		if known == null:
			previous.status = ProfileStore.CommitResult.UNAVAILABLE
			return previous
		if known.sign_value == 0:
			return store.commit_confirmed(mutation)
		if known.compare(Quantity.from_count(1)) != 0:
			previous.status = ProfileStore.CommitResult.CORRUPT
			return previous
	else:
		return previous
	mutation.claims.erase("discovery/" + local.award)
	mutation.deltas.clear()
	return store.commit_confirmed(mutation)


static func apply(store: ProfileStore, binding: ProfileGrant.Binding, recipient: CryptoKey,
		bytes: PackedByteArray) -> Application:
	var applied := Application.new()
	applied.receipt = _invalid()
	if (store == null or binding == null or store.identity() != binding.recipient or recipient == null
			or recipient.is_public_only() or ProfileGrant.fingerprint(recipient) != ProfileGrant.fingerprint(binding.recipient_key)):
		return applied
	var grant := ProfileGrant.open_authorization(bytes, binding)
	if grant == null:
		return applied
	var request := grant.application()
	var previous := store.lookup(request.id)
	match previous.status:
		ProfileStore.CommitResult.COMMITTED:
			previous.status = (
				ProfileStore.CommitResult.DUPLICATE if grant.matches_application(previous.digest)
				else ProfileStore.CommitResult.CONFLICT)
			applied.receipt = previous
		ProfileStore.CommitResult.MISSING:
			if grant.kind == ProfileGrant.Kind.DISCOVERY:
				var discovered := store.balance("discovery/" + grant.award)
				if discovered == null:
					applied.receipt.status = ProfileStore.CommitResult.UNAVAILABLE
					return applied
				if discovered.sign_value > 0:
					if discovered.compare(Quantity.from_count(1)) != 0:
						applied.receipt.status = ProfileStore.CommitResult.CORRUPT
						return applied
					request = grant.application(true)
			applied.receipt = store.commit_confirmed(request)
		_:
			applied.receipt = previous
	applied.acknowledgement = grant.sign_acknowledgement(applied.receipt, recipient)
	return applied


static func acknowledge(store: ProfileStore, binding: ProfileGrant.Binding,
		bytes: PackedByteArray) -> ProfileStore.Receipt:
	var facts := ProfileGrant.open_acknowledgement(bytes, binding)
	if store == null or facts.is_empty():
		return _invalid()
	var mutation := ProfileMutation.new()
	mutation.id = "ack/" + facts[0]
	mutation.rules = binding.rules
	mutation.catalog = binding.catalog
	mutation.claims.append("application-proof/" + facts[2])
	mutation.claims.append("ack-binding/" + JSON.stringify([binding.fields(), facts]).sha256_text())
	mutation.acknowledgements[facts[0]] = facts[1]
	var previous := store.lookup(mutation.id)
	if previous.status == ProfileStore.CommitResult.COMMITTED:
		previous.status = (
			ProfileStore.CommitResult.DUPLICATE if previous.digest == mutation.record().sha256_text()
			else ProfileStore.CommitResult.CONFLICT)
		return previous
	if previous.status != ProfileStore.CommitResult.MISSING:
		return previous
	var prior := store.grant(facts[0])
	if prior.is_empty() or prior.recipient != binding.recipient or prior.digest != facts[1] or prior.body == null:
		return _invalid()
	var grant := ProfileGrant.open_authorization(prior.body, binding)
	if grant == null or not grant.matches_application(facts[2]):
		return _invalid()
	return store.commit_confirmed(mutation)


static func _invalid() -> ProfileStore.Receipt:
	var receipt := ProfileStore.Receipt.new()
	receipt.status = ProfileStore.CommitResult.INVALID
	return receipt
