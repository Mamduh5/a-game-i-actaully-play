class_name RunAuthority
extends RefCounted
## One owner of the admission queue, logical tick and last closed observation.
## This core sits behind local and authenticated input adapters.

enum Admission {
	QUEUED, INACTIVE, WRONG_RUN, WRONG_EPOCH, WRONG_SEAT, WRONG_REALM,
	WRONG_TICK, STALE_SEQUENCE, UNSUPPORTED_ACTION, DUPLICATE, CONFLICT, QUEUE_FULL,
}

const CHECKPOINT_VERSION := 1
const MAX_OPEN_INTENTS_PER_SEAT := 64
const MAX_TICK := 9223372036854775806

class InputStream:
	var through: int
	var pending: Dictionary[int, RunIntent] = {}

class SeatInputs:
	var primary := InputStream.new()
	var reliable := InputStream.new()
	var overflowed := false

var _identity: Dictionary = {}
var _realms: Dictionary[StringName, StringName] = {}
var _inputs: Dictionary[StringName, SeatInputs] = {}
var _random: RunRandom
var _closed_tick: int
var _observation: Dictionary = {}
var _ordinary_currency: Array[OrdinaryCurrency] = []
var _quitting := false
var _settled_quit := false
var _resolving := false


func start(setup: RunSetup, local_authority_id: StringName) -> bool:
	if not _identity.is_empty() or setup == null or not setup.is_valid_for(local_authority_id):
		return false
	_install(setup, RunRandom.new(setup.seed), 0, {})
	return true


func next_tick() -> int:
	return _closed_tick + 1


func belongs_to(run: StringName, epoch: int) -> bool:
	return not _identity.is_empty() and _identity["run"] == run and _identity["epoch"] == epoch


func attach_ordinary_currency(earnings: OrdinaryCurrency) -> bool:
	if (_identity.is_empty() or _quitting or earnings == null
			or not earnings.belongs_to(_identity["run"], _identity["rules"], _identity["catalog"])):
		return false
	for existing: OrdinaryCurrency in _ordinary_currency:
		if existing.recipient() == earnings.recipient() and existing.account() == earnings.account():
			return false
	_ordinary_currency.append(earnings)
	return true


## Also used by the group owner before opening an earning boundary within a tick.
func can_open_earning_group() -> bool:
	if _quitting:
		return false
	var permitted := true
	for earnings: OrdinaryCurrency in _ordinary_currency:
		if not earnings.can_earn():
			permitted = false
	return permitted


## An empty recipient flushes the run. A purchase or personal settlement
## can require the recipient's own pending earnings before it commits.
func flush_ordinary_currency(recipient: String = "") -> bool:
	var settled := true
	for earnings: OrdinaryCurrency in _ordinary_currency:
		if (recipient.is_empty() or earnings.recipient() == recipient) and not earnings.flush():
			settled = false
	return settled


func service_ordinary_currency() -> void:
	for earnings: OrdinaryCurrency in _ordinary_currency:
		earnings.service()


## Fence every account before flushing the first, so a partial success
## cannot admit new earnings before the remaining accounts settle.
func settle_orderly_quit() -> bool:
	if _identity.is_empty() or _resolving:
		return false
	if not _quitting:
		_quitting = true
		for earnings: OrdinaryCurrency in _ordinary_currency:
			earnings.end_earning()
	if not _settled_quit:
		_settled_quit = flush_ordinary_currency()
	return _settled_quit


## Apply the accepted interact at its closed boundary. Revoke any input
## already queued for this seat's old realm and keep the shared clock.
func transfer_seat(intent: RunIntent, party: RunParty, source: RealmGeometry, destination: RealmGeometry,
		at: RealmSweep.Point) -> bool:
	if (_quitting or intent == null or party == null or source == null or destination == null
			or intent.action != PlayerCommand.INTERACT or intent.tick != _closed_tick
			or not belongs_to(intent.run_id, intent.epoch) or not party.belongs_to(intent.run_id, intent.epoch)
			or source.realm_id != intent.realm_id or _realms.get(intent.seat_id) != source.realm_id
			or intent.receipt() not in _observation["accepted"]):
		return false
	var seat := intent.seat_id
	if not party.transfer_living(seat, _closed_tick, source, destination, at):
		return false
	var inputs := _inputs[seat]
	for sequence: int in inputs.primary.pending:
		inputs.primary.through = maxi(inputs.primary.through, sequence)
	inputs.primary.pending.clear()
	inputs.reliable = InputStream.new()
	inputs.overflowed = false
	_realms[seat] = destination.realm_id
	_observation["outcomes"].append({"seat": seat, "realm_entered": destination.realm_id})
	return true


## The trusted adapter retires the reliable stream when its binding ends.
## Movement keeps its existing watermark through connection and scope changes.
func retire_reliable_interactions(run: StringName, epoch: int, seat: StringName, realm: StringName) -> void:
	if belongs_to(run, epoch) and _realms.get(seat) == realm:
		_inputs[seat].reliable = InputStream.new()


## The binding is supplied by the adapter. The intent alone cannot nominate its sender.
func submit(bound_seat: StringName, intent: RunIntent) -> Admission:
	if _identity.is_empty() or _quitting or intent == null or _closed_tick >= MAX_TICK:
		return Admission.INACTIVE
	if intent.run_id != _identity["run"]:
		return Admission.WRONG_RUN
	if intent.epoch != _identity["epoch"]:
		return Admission.WRONG_EPOCH
	if bound_seat != intent.seat_id or not _realms.has(bound_seat):
		return Admission.WRONG_SEAT
	if intent.realm_id != _realms[bound_seat]:
		return Admission.WRONG_REALM
	if intent.tick != next_tick():
		return Admission.WRONG_TICK
	var inputs := _inputs[bound_seat]
	var stream := inputs.reliable if intent.reliable else inputs.primary
	if intent.sequence <= stream.through:
		return Admission.STALE_SEQUENCE
	if not _supports_action(intent.action) or not intent.valid_payload():
		return Admission.UNSUPPORTED_ACTION

	if inputs.overflowed:
		return Admission.QUEUE_FULL
	if stream.pending.has(intent.sequence):
		var previous := stream.pending[intent.sequence]
		if previous != null and previous.matches_payload(intent):
			return Admission.DUPLICATE
		# Neither of two conflicting envelopes can win by arriving first.
		stream.pending[intent.sequence] = null
		return Admission.CONFLICT
	if inputs.primary.pending.size() + inputs.reliable.pending.size() >= MAX_OPEN_INTENTS_PER_SEAT:
		# Reject this seat's whole batch. Arrival order cannot select the survivors.
		inputs.overflowed = true
		inputs.primary.pending.clear()
		inputs.reliable.pending.clear()
		return Admission.QUEUE_FULL
	stream.pending[intent.sequence] = intent.copy()
	return Admission.QUEUED


## Called by the authoritative fixed-step driver. No signals or view callbacks run here.
func close_tick() -> bool:
	if _identity.is_empty() or _closed_tick >= MAX_TICK or not can_open_earning_group():
		return false
	var accepted: Array[RunIntent] = []
	var conflicts: Array[Dictionary] = []
	var overflowed: Array[StringName] = []
	for seat: StringName in _realms:
		var inputs := _inputs[seat]
		if inputs.overflowed:
			overflowed.append(seat)
			inputs.overflowed = false
		# The two streams keep independent sequence domains. Movement resolves
		# first and reliable interactions retain their own admitted order.
		for stream: InputStream in [inputs.primary, inputs.reliable]:
			var sequences := stream.pending.keys()
			sequences.sort()
			for sequence: int in sequences:
				var intent := stream.pending[sequence]
				if intent == null:
					var conflict := {"seat": seat, "sequence": sequence}
					if stream == inputs.reliable:
						conflict["reliable"] = true
					conflicts.append(conflict)
				else:
					accepted.append(intent)
				stream.through = sequence
			stream.pending.clear()

	var receipts: Array[Dictionary] = []
	for intent: RunIntent in accepted:
		receipts.append(intent.receipt())
	var tick := next_tick()
	_resolving = true
	var outcomes := _resolve_tick(tick, accepted, _random)
	_closed_tick = tick
	_publish(receipts, conflicts, overflowed, outcomes)
	_resolving = false
	return true


## Detached authority result. View adapters must project their permitted subset.
func closed_result() -> Dictionary:
	return _observation.duplicate(true)


## The last closed admission/RNG frontier. Pending intents are never checkpointed.
func checkpoint() -> Dictionary:
	if _identity.is_empty() or _quitting:
		return {}
	var sequences: Dictionary[StringName, int] = {}
	for seat: StringName in _inputs:
		sequences[seat] = _inputs[seat].primary.through
	var saved := {
		"version": CHECKPOINT_VERSION,
		"engine": Engine.get_version_info()["hash"],
		"identity": _identity.duplicate(true),
		"tick": _closed_tick,
		"sequences": sequences,
		"random": _random.checkpoint(),
	}
	if _realms != _identity["initial_realms"]:
		saved["current_realms"] = _realms.duplicate()
	return saved


## Restores locally supplied, same-build data into a new authority. WP24 owns recovery proof.
func restore(setup: RunSetup, local_authority_id: StringName, saved: Dictionary) -> bool:
	if not _identity.is_empty() or setup == null or not setup.is_valid_for(local_authority_id):
		return false
	if saved.get("version") != CHECKPOINT_VERSION or saved.get("engine") != Engine.get_version_info()["hash"]:
		return false
	if saved.get("identity") != setup.identity() or not saved.get("tick") is int:
		return false
	var tick: int = saved["tick"]
	if tick < 0 or tick > MAX_TICK or not saved.get("sequences") is Dictionary:
		return false
	var sequences: Dictionary = saved["sequences"]
	var realms: Variant = saved.get("current_realms", setup.initial_realms)
	if sequences.size() != setup.initial_realms.size():
		return false
	if (not realms is Dictionary or realms.size() != setup.initial_realms.size()
			or (tick == 0 and realms != setup.initial_realms)):
		return false
	for seat: StringName in setup.initial_realms:
		var sequence: Variant = sequences.get(seat)
		var realm: Variant = realms.get(seat)
		if (not sequence is int or sequence < 0 or (tick == 0 and sequence != 0)
				or not realm is StringName or realm.is_empty()):
			return false
	var random := RunRandom.new(setup.seed)
	if not saved.get("random") is Dictionary or not random.restore(saved["random"]):
		return false
	if tick == 0 and not saved["random"].is_empty():
		return false
	_install(setup, random, tick, sequences)
	_realms.assign(realms)
	return true


func _install(setup: RunSetup, random: RunRandom, tick: int, sequences: Dictionary) -> void:
	_identity = setup.identity()
	_realms.assign(_identity["initial_realms"])
	_random = random
	_closed_tick = tick
	for seat: StringName in _realms:
		var inputs := SeatInputs.new()
		inputs.primary.through = sequences.get(seat, 0)
		_inputs[seat] = inputs
	_publish([], [], [], [])


func _publish(
		accepted: Array[Dictionary],
		conflicts: Array[Dictionary],
		overflowed: Array[StringName],
		outcomes: Array[Dictionary]
) -> void:
	_observation = {
		"tick": _closed_tick,
		"accepted": accepted,
		"conflicts": conflicts,
		"overflowed": overflowed,
		"outcomes": outcomes.duplicate(true),
	}


## Rules supply supported semantic actions and resolve a whole canonical batch.
## Outcomes are closed facts containing value data, with no live object references.
func _supports_action(_action: StringName) -> bool:
	return false


func _resolve_tick(_tick: int, _accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
	return []
