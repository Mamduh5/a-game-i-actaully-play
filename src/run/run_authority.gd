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

var _identity: Dictionary = {}
var _realms: Dictionary[StringName, StringName] = {}
var _last_sequences: Dictionary[StringName, int] = {}
var _pending: Dictionary[StringName, Dictionary] = {}
var _overflowed: Dictionary[StringName, bool] = {}
var _random: RunRandom
var _closed_tick: int
var _observation: Dictionary = {}


func start(setup: RunSetup, local_authority_id: StringName) -> bool:
	if not _identity.is_empty() or setup == null or not setup.is_valid_for(local_authority_id):
		return false
	_install(setup, RunRandom.new(setup.seed), 0, {})
	return true


func next_tick() -> int:
	return _closed_tick + 1


## The binding is supplied by the adapter. The intent alone cannot nominate its sender.
func submit(bound_seat: StringName, intent: RunIntent) -> Admission:
	if _identity.is_empty() or intent == null or _closed_tick >= MAX_TICK:
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
	if intent.sequence <= _last_sequences[bound_seat]:
		return Admission.STALE_SEQUENCE
	if not _supports_action(intent.action):
		return Admission.UNSUPPORTED_ACTION

	var seat_intents: Dictionary = _pending[bound_seat]
	if _overflowed.has(bound_seat):
		return Admission.QUEUE_FULL
	if seat_intents.has(intent.sequence):
		var previous: RunIntent = seat_intents[intent.sequence]
		if previous != null and previous.action == intent.action:
			return Admission.DUPLICATE
		# Neither of two conflicting envelopes can win by arriving first.
		seat_intents[intent.sequence] = null
		return Admission.CONFLICT
	if seat_intents.size() >= MAX_OPEN_INTENTS_PER_SEAT:
		# Reject this seat's whole batch. Arrival order cannot select the survivors.
		_overflowed[bound_seat] = true
		seat_intents.clear()
		return Admission.QUEUE_FULL
	seat_intents[intent.sequence] = intent.copy()
	return Admission.QUEUED


## Called by the authoritative fixed-step driver. No signals or view callbacks run here.
func close_tick() -> bool:
	if _identity.is_empty() or _closed_tick >= MAX_TICK:
		return false
	var accepted: Array[RunIntent] = []
	var conflicts: Array[Dictionary] = []
	var overflowed: Array[StringName] = []
	for seat: StringName in _realms:
		if _overflowed.has(seat):
			overflowed.append(seat)
		var seat_intents: Dictionary = _pending[seat]
		var sequences: Array = seat_intents.keys()
		sequences.sort()
		for sequence: int in sequences:
			var intent: RunIntent = seat_intents[sequence]
			if intent == null:
				conflicts.append({"seat": seat, "sequence": sequence})
			else:
				accepted.append(intent)
			_last_sequences[seat] = sequence
		seat_intents.clear()
	_overflowed.clear()

	var receipts: Array[Dictionary] = []
	for intent: RunIntent in accepted:
		receipts.append(intent.receipt())
	var tick := next_tick()
	var outcomes := _resolve_tick(tick, accepted, _random)
	_closed_tick = tick
	_publish(receipts, conflicts, overflowed, outcomes)
	return true


## Detached authority result. View adapters must project their permitted subset.
func closed_result() -> Dictionary:
	return _observation.duplicate(true)


## The last closed admission/RNG frontier. Pending intents are never checkpointed.
func checkpoint() -> Dictionary:
	if _identity.is_empty():
		return {}
	return {
		"version": CHECKPOINT_VERSION,
		"engine": Engine.get_version_info()["hash"],
		"identity": _identity.duplicate(true),
		"tick": _closed_tick,
		"sequences": _last_sequences.duplicate(),
		"random": _random.checkpoint(),
	}


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
	if sequences.size() != setup.initial_realms.size():
		return false
	for seat: StringName in setup.initial_realms:
		var sequence: Variant = sequences.get(seat)
		if not sequence is int or sequence < 0 or (tick == 0 and sequence != 0):
			return false
	var random := RunRandom.new(setup.seed)
	if not saved.get("random") is Dictionary or not random.restore(saved["random"]):
		return false
	if tick == 0 and not saved["random"].is_empty():
		return false
	_install(setup, random, tick, sequences)
	return true


func _install(setup: RunSetup, random: RunRandom, tick: int, sequences: Dictionary) -> void:
	_identity = setup.identity()
	_realms.assign(_identity["initial_realms"])
	_random = random
	_closed_tick = tick
	for seat: StringName in _realms:
		_last_sequences[seat] = sequences.get(seat, 0)
		_pending[seat] = {}
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
