class_name OrdinaryCurrency
extends RefCounted
## One original run, recipient and currency account. A dispatch keeps its
## source occurrences and their original clock until the exact receipt exists.

enum Eligibility { QUEUED, DUPLICATE, CONFLICT, INVALID, FENCED }

const MAX_AGE_USEC := 5_000_000
const DISPATCH_AGE_USEC := 4_000_000
const MAX_BATCH := ProfileMutation.MAX_ITEMS >> 1 # Source and amount claim per occurrence.
const Commit := ProfileStore.CommitResult

class Earning:
	var occurrence: String
	var amount: Quantity
	var eligible_at: int
	var source_claim: String
	var value_claim: String
	var operation: String

class Batch:
	var mutation: ProfileMutation
	var digest: String
	var occurrences: Array[String] = []

var _store: ProfileStore
var _binding: ProfileGrant.Binding
var _issuer_profile: String
var _signer: CryptoKey
var _account: String
var _scope: Array[String]
var _facts_scope: Array[String]
var _clock: Callable
var _now := -1
var _oldest := -1
var _fault_since := -1
var _elapsed_fault := 0
var _pending: Dictionary[String, Earning] = {}
var _in_flight: Dictionary[String, Batch] = {}


static func begin(store: ProfileStore, binding: ProfileGrant.Binding, issuer: CryptoKey, account: String,
		clock: Callable = Callable()) -> OrdinaryCurrency:
	if (store == null or store.identity().is_empty() or binding == null or issuer == null or issuer.is_public_only()
			or not ProfileGrant.valid_field(account) or not account.begins_with("currency/")):
		return null
	var paired := ProfileGrant.Binding.restore(binding.record())
	if paired == null or ProfileGrant.fingerprint(issuer) != ProfileGrant.fingerprint(paired.issuer):
		return null
	if paired.recipient == store.identity():
		if ProfileGrant.fingerprint(paired.issuer) != ProfileGrant.fingerprint(paired.recipient_key):
			return null
	else:
		var saved := store.grant_binding(paired.run, paired.recipient)
		if saved == null or saved.fields() != paired.fields():
			return null
	var tracker := OrdinaryCurrency.new()
	tracker._store = store
	tracker._binding = paired
	tracker._issuer_profile = store.identity()
	tracker._signer = issuer
	tracker._account = account
	tracker._facts_scope = paired.fields()
	tracker._scope = [paired.run, paired.recipient, tracker._facts_scope[4], account]
	tracker._clock = clock
	return tracker


func belongs_to(run: StringName, rules: StringName, catalog: StringName) -> bool:
	return (_binding != null and _binding.run == String(run)
		and _binding.rules == String(rules) and _binding.catalog == String(catalog))


func recipient() -> String:
	return _binding.recipient


func account() -> String:
	return _account


## The authoritative driver calls before opening another earning group.
## Service continues while this fence is raised.
func can_earn() -> bool:
	return _poll() and _fault_since < 0


func accrue(occurrence: String, amount: Quantity) -> Eligibility:
	if not ProfileGrant.valid_field(occurrence) or amount == null or amount.sign_value <= 0:
		return Eligibility.INVALID
	if not can_earn():
		return Eligibility.FENCED
	var prior: Earning = _pending.get(occurrence)
	if prior != null:
		return Eligibility.DUPLICATE if prior.amount.compare(amount) == 0 else Eligibility.CONFLICT
	var earned := Earning.new()
	earned.occurrence = occurrence
	earned.amount = amount
	earned.eligible_at = _now
	earned.source_claim = "ordinary-source/" + JSON.stringify([_scope, occurrence]).sha256_text()
	earned.value_claim = "ordinary-value/" + JSON.stringify(
		[earned.source_claim, _facts_scope, QuantityCodec.encode(amount).hex_encode()]).sha256_text()
	_pending[occurrence] = earned
	if _oldest < 0:
		_oldest = _now
	return Eligibility.QUEUED


func oldest_eligible_usec() -> int:
	return _oldest


func fault_elapsed_usec() -> int:
	_poll()
	return _elapsed_fault if _fault_since < 0 else _elapsed_fault + (_now - _fault_since)


func pending_amount() -> Quantity:
	var total := Quantity.from_count(0)
	for earned: Earning in _pending.values():
		total = total.add(earned.amount)
		if total == null:
			return null
	return total


## Dispatch moves each selected occurrence to an immutable transaction draft.
## Another batch may finish first. Each stays pending until confirmation.
func dispatch(force: bool = false) -> String:
	if not _poll():
		return ""
	var queued: Array[Earning] = []
	for earned: Earning in _pending.values():
		if earned.operation.is_empty():
			queued.append(earned)
	if queued.is_empty():
		return ""
	queued.sort_custom(func(first: Earning, second: Earning) -> bool:
		return first.occurrence < second.occurrence if first.eligible_at == second.eligible_at else first.eligible_at < second.eligible_at)
	if not force and queued.size() < MAX_BATCH and _now - queued[0].eligible_at < DISPATCH_AGE_USEC:
		return ""
	var drafted: Array[Earning] = []
	var total := Quantity.from_count(0)
	for earned: Earning in queued:
		var prior := _store.lookup_claim(earned.source_claim)
		if prior.status == Commit.COMMITTED:
			if not _same_earning(earned, prior):
				return ""
			_pending.erase(earned.occurrence)
			_refresh_oldest()
			continue
		if prior.status != Commit.MISSING:
			return ""
		var sum := total.add(earned.amount)
		if sum == null:
			break
		drafted.append(earned)
		total = sum
		if drafted.size() == MAX_BATCH:
			break
	if drafted.is_empty():
		_release_if_settled()
		return ""
	var batch := _draft(drafted, total)
	if batch == null:
		return ""
	for earned: Earning in drafted:
		earned.operation = batch.mutation.id
	_in_flight[batch.mutation.id] = batch
	return batch.mutation.id


func write_batch(operation: String) -> ProfileStore.Receipt:
	var batch: Batch = _in_flight.get(operation)
	if batch == null or not _poll():
		return _verdict(Commit.INVALID, operation)
	var prior := _read_exact(batch)
	if prior.status == Commit.COMMITTED:
		prior.status = Commit.DUPLICATE
		return prior
	if prior.status != Commit.MISSING:
		return prior
	var posted := _store.commit_confirmed(batch.mutation)
	_poll()
	return posted


func confirm_batch(operation: String) -> ProfileStore.Receipt:
	var batch: Batch = _in_flight.get(operation)
	if batch == null or not _poll():
		return _verdict(Commit.INVALID, operation)
	var durable := _read_exact(batch)
	if durable.status == Commit.COMMITTED:
		for occurrence: String in batch.occurrences:
			_pending.erase(occurrence)
		_in_flight.erase(operation)
		_refresh_oldest()
		_release_if_settled()
	return durable


## Flush callers wait for true before leaving a mandatory boundary. A
## failure keeps the transaction and earning clock for service/retry.
func flush() -> bool:
	if not _poll():
		return false
	_service_in_flight()
	if not _in_flight.is_empty():
		return false
	while not _pending.is_empty():
		var operation := dispatch(true)
		if operation.is_empty():
			return _pending.is_empty()
		write_batch(operation)
		if confirm_batch(operation).status != Commit.COMMITTED:
			return false
	return true


func service() -> void:
	if not _poll():
		return
	if _fault_since >= 0:
		flush()
		return
	_service_in_flight()
	var operation := dispatch()
	if not operation.is_empty():
		write_batch(operation)
		confirm_batch(operation)


func _service_in_flight() -> void:
	# A later batch can own the store's unresolved commit fence and must
	# get its own receipt lookup even if an earlier draft remains pending.
	for operation: String in _in_flight.keys():
		write_batch(operation)
		confirm_batch(operation)


func _draft(entries: Array[Earning], total: Quantity) -> Batch:
	var batch := Batch.new()
	var mutation := ProfileMutation.new()
	var ids: Array[String] = []
	for earned: Earning in entries:
		ids.append(earned.source_claim)
		mutation.claims.append_array([earned.source_claim, earned.value_claim])
		batch.occurrences.append(earned.occurrence)
	ids.sort()
	var occurrence := "ordinary/" + JSON.stringify(ids).sha256_text()
	mutation.rules = _binding.rules
	mutation.catalog = _binding.catalog
	if _binding.recipient == _store.identity():
		mutation.id = occurrence
		mutation.deltas[_account] = total
	else:
		var bytes := ProfileGrant.sign_authorization(_binding, _signer, occurrence, ProfileGrant.Kind.CURRENCY, _account, total)
		var grant := ProfileGrant.open_authorization(bytes, _binding)
		if grant == null:
			return null
		var saved := ProfileMutation.Grant.new()
		saved.key = grant.key
		saved.recipient = _binding.recipient
		saved.envelope = bytes
		mutation.grants.append(saved)
		mutation.id = grant.issue_id()
	batch.mutation = mutation
	var recorded := mutation.record()
	if recorded.is_empty():
		return null
	batch.digest = recorded.sha256_text()
	return batch


func _same_earning(earned: Earning, prior: ProfileStore.Receipt) -> bool:
	var facts := _store.lookup_claim(earned.value_claim)
	if facts.status == Commit.COMMITTED and facts.id == prior.id:
		return true
	if facts.status in [Commit.COMMITTED, Commit.MISSING] and _fault_since < 0:
		_fault_since = _now
	return false


func _read_exact(batch: Batch) -> ProfileStore.Receipt:
	var durable := _store.lookup(batch.mutation.id)
	if durable.status == Commit.COMMITTED and durable.digest != batch.digest:
		durable.status = Commit.CONFLICT
		if _fault_since < 0:
			_fault_since = _now
	return durable


func _poll() -> bool:
	if _store == null or _store.identity() != _issuer_profile:
		return false
	var sampled: Variant = _clock.call() if _clock.is_valid() else Time.get_ticks_usec()
	if not sampled is int or sampled < 0 or sampled < _now:
		return false
	_now = sampled
	if _fault_since < 0 and _oldest >= 0 and _now - _oldest >= MAX_AGE_USEC:
		_fault_since = _oldest + MAX_AGE_USEC
	return true


func _refresh_oldest() -> void:
	_oldest = -1
	for earned: Earning in _pending.values():
		_oldest = earned.eligible_at if _oldest < 0 else mini(_oldest, earned.eligible_at)


func _release_if_settled() -> void:
	if _pending.is_empty() and _fault_since >= 0:
		_elapsed_fault += _now - _fault_since
		_fault_since = -1


static func _verdict(status: ProfileStore.CommitResult, operation: String) -> ProfileStore.Receipt:
	var result := ProfileStore.Receipt.new()
	result.status = status
	result.id = operation
	return result
