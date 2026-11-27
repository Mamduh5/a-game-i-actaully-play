class_name RunAuthority
extends RefCounted
## One owner of the admission queue, logical tick and last closed observation.
## This core sits behind local and authenticated input adapters.

enum Admission {
	QUEUED, INACTIVE, WRONG_RUN, WRONG_EPOCH, WRONG_SEAT, WRONG_REALM,
	WRONG_TICK, STALE_SEQUENCE, UNSUPPORTED_ACTION, DUPLICATE, CONFLICT, QUEUE_FULL,
}
enum Exit { ACTIVE, QUIT, SUSPEND }
enum GatewayResult { REFUSED, SETTLEMENT_WAIT, ENTERED }

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
	var published_movement: int

class ClosingTick:
	var accepted: Array[Dictionary] = []
	var conflicts: Array[Dictionary] = []
	var overflowed: Array[StringName] = []
	var outcomes: Array[Dictionary] = []

class PendingGateway:
	var party: RunParty
	var progression: PartyProgression
	var transfer: CombatKernel.ArenaTransfer
	var entrant: StringName
	var early: bool

var _identity: Dictionary = {}
var _epoch: int
var _realms: Dictionary[StringName, StringName] = {}
var _inputs: Dictionary[StringName, SeatInputs] = {}
var _random: RunRandom
var _closed_tick: int
var _observation: Dictionary = {}
var _ordinary_currency: Array[OrdinaryCurrency] = []
var _ordinary_session: ProfileOrdinarySession
var _exit := Exit.ACTIVE
var _ordinary_ending := false
var _ordinary_settled := false
var _resolving := false
var _closing: ClosingTick
var _gateway: PendingGateway
var _early_gateway_tick: int


func start(setup: RunSetup, local_authority_id: StringName) -> bool:
	if not _identity.is_empty() or setup == null or not setup.is_valid_for(local_authority_id):
		return false
	_install(setup, RunRandom.new(setup.seed), 0, {})
	return true


func next_tick() -> int:
	return _closed_tick + 1


func movement_acknowledgement(seat: StringName) -> int:
	var inputs: SeatInputs = _inputs.get(seat)
	return inputs.published_movement if inputs != null else -1


func belongs_to(run: StringName, epoch: int) -> bool:
	return not _identity.is_empty() and _identity["run"] == run and _epoch == epoch


func matches_world_seed(seed: int) -> bool:
	return not _identity.is_empty() and _identity["seed"] == seed


func attach_ordinary_currency(earnings: OrdinaryCurrency) -> bool:
	if (_identity.is_empty() or _exit != Exit.ACTIVE or _ordinary_ending or _closing != null or _gateway != null or earnings == null
			or not earnings.belongs_to(_identity["run"], _identity["rules"], _identity["catalog"])
			or (_ordinary_session != null and not _ordinary_session.tracks(earnings))):
		return false
	for existing: OrdinaryCurrency in _ordinary_currency:
		if existing.recipient() == earnings.recipient() and existing.account() == earnings.account():
			return false
	_ordinary_currency.append(earnings)
	return true


## The live shell confirms the issuer's activity before opening earning groups.
func begin_ordinary_session(profile: ProfileStore) -> bool:
	if _identity.is_empty() or _exit != Exit.ACTIVE or _ordinary_ending or _gateway != null or _resolving or profile == null:
		return false
	if _ordinary_session != null:
		if not _ordinary_session.uses(profile):
			return false
	else:
		for earnings: OrdinaryCurrency in _ordinary_currency:
			if not earnings.issued_by(profile) or earnings.oldest_eligible_usec() >= 0:
				return false
		_ordinary_session = ProfileOrdinarySession.prepare(profile, _identity["run"], _identity["rules"], _identity["catalog"])
		if _ordinary_session == null:
			return false
	return _ordinary_session.open()


## Also used by the group owner before opening an earning boundary within a tick.
func can_open_earning_group() -> bool:
	if (_exit != Exit.ACTIVE or _ordinary_ending or (_closing != null and not _resolving) or _gateway != null
			or (_ordinary_session != null and not _ordinary_session.is_open())):
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


func settle_orderly_quit() -> bool:
	return _settle_exit(Exit.QUIT)


## Supply the closed authority component after all ordinary earnings settle.
## WP24 owns the full recovery image and the durable suspension acknowledgement.
func prepare_orderly_suspension() -> Dictionary:
	if (_gateway != null or _closing != null or (_ordinary_ending and _exit == Exit.ACTIVE)
			or _identity.get("role") != RunSetup.Role.HOST or not _settle_exit(Exit.SUSPEND)):
		return {}
	return _closed_checkpoint()


## Fence every account before flushing the first, so a partial success
## cannot admit new earnings before the remaining accounts settle.
func _settle_exit(requested: Exit) -> bool:
	if _identity.is_empty() or _resolving or (_exit == Exit.QUIT and requested != Exit.QUIT):
		return false
	_exit = requested
	return _close_ordinary_session()


## The party calls this only after combat or survival has decided a terminal result.
func settle_terminal_currency() -> bool:
	return not _identity.is_empty() and _close_ordinary_session()


func _close_ordinary_session() -> bool:
	if not _ordinary_ending:
		_ordinary_ending = true
		for earnings: OrdinaryCurrency in _ordinary_currency:
			earnings.end_earning()
	if not _ordinary_settled:
		_ordinary_settled = flush_ordinary_currency() and (_ordinary_session == null or _ordinary_session.settle())
	return _ordinary_settled


## Apply the accepted interact at its closed boundary. Revoke any input
## already queued for this seat's old realm and keep the shared clock.
func transfer_seat(intent: RunIntent, party: RunParty, source: RealmGeometry, destination: RealmGeometry,
		at: RealmSweep.Point) -> bool:
	if not accepted_interaction(intent, party) or source == null or destination == null or source.realm_id != intent.realm_id:
		return false
	var seat := intent.seat_id
	if not party.transfer_living(seat, _closed_tick, source, destination, at):
		return false
	_retire_scope(seat)
	_realms[seat] = destination.realm_id
	_observation["outcomes"].append({"seat": seat, "realm_entered": destination.realm_id})
	return true


## The normal owner checks its handle. An early request also needs live PR04
## proof from the Observatory bound to this authority and party.
func request_gateway(intent: RunIntent, party: RunParty, arena: RealmGeometry,
		arrivals: Dictionary[StringName, RealmSweep.Point], progression: PartyProgression,
		observatory: RunObservatoryGateway = null) -> GatewayResult:
	if (not accepted_interaction(intent, party) or _epoch != _identity["epoch"] or _epoch == Quantity.INT_MAX
			or intent.realm_id != WorldTopology.OVERWORLD or arena == null or arena.realm_id != RunSetup.FINAL_REALM
			or not _progression_can_cross(progression)):
		return GatewayResult.REFUSED
	if observatory != null:
		if not observatory.permits_entry(self, party, intent):
			return GatewayResult.REFUSED
	elif _closed_tick < RunParty.COLLAPSE_TICK:
		return GatewayResult.REFUSED
	var transfer := party.stage_gateway(intent.seat_id, _closed_tick, arena, arrivals)
	if transfer == null:
		return GatewayResult.REFUSED
	_gateway = PendingGateway.new()
	_gateway.party = party
	_gateway.progression = progression
	_gateway.transfer = transfer
	_gateway.entrant = intent.seat_id
	_gateway.early = observatory != null
	return retry_gateway()


## A settled prefix never changes the old tick or clears its commands.
## Only the completed transition publishes the new epoch and all seat scopes.
func retry_gateway() -> GatewayResult:
	if _gateway == null or _exit != Exit.ACTIVE or _resolving:
		return GatewayResult.REFUSED
	_resolving = true
	var settled := flush_ordinary_currency()
	_resolving = false
	if not settled:
		return GatewayResult.SETTLEMENT_WAIT
	var attempt := _gateway
	_gateway = null
	if not _progression_can_cross(attempt.progression) or not attempt.party.enter_gateway(attempt.transfer, _epoch + 1):
		return GatewayResult.REFUSED
	attempt.progression.enter_gateway(_closed_tick, attempt.early)
	if attempt.early:
		_early_gateway_tick = _closed_tick
	_epoch += 1
	for seat: StringName in _realms:
		_retire_scope(seat)
		_realms[seat] = RunSetup.FINAL_REALM
	_observation["world_epoch"] = _epoch
	_observation["outcomes"].append({"seat": attempt.entrant, "gateway_entered": RunSetup.FINAL_REALM})
	return GatewayResult.ENTERED


func _progression_can_cross(progression: PartyProgression) -> bool:
	return progression != null and progression.can_cross_gateway(_identity, _epoch, _closed_tick)


func accepted_interaction(intent: RunIntent, party: RunParty) -> bool:
	return (_exit == Exit.ACTIVE and not _ordinary_ending and _gateway == null and _closing == null and not _resolving
		and intent != null and party != null
		and intent.action == PlayerCommand.INTERACT and intent.valid_payload() and intent.tick == _closed_tick
		and belongs_to(intent.run_id, intent.epoch) and party.belongs_to(intent.run_id, intent.epoch)
		and _realms.get(intent.seat_id) == intent.realm_id and intent.receipt() in _observation["accepted"])


func _retire_scope(seat: StringName) -> void:
	var inputs := _inputs[seat]
	for sequence: int in inputs.primary.pending:
		inputs.primary.through = maxi(inputs.primary.through, sequence)
	inputs.published_movement = inputs.primary.through
	inputs.primary.pending.clear()
	inputs.reliable = InputStream.new()
	inputs.overflowed = false


## The trusted adapter retires the reliable stream when its binding ends.
## Movement keeps its existing watermark through connection and scope changes.
func retire_reliable_interactions(run: StringName, epoch: int, seat: StringName, realm: StringName) -> void:
	if belongs_to(run, epoch) and _realms.get(seat) == realm:
		_inputs[seat].reliable = InputStream.new()


## The binding is supplied by the adapter. The intent alone cannot nominate its sender.
func submit(bound_seat: StringName, intent: RunIntent) -> Admission:
	if (_identity.is_empty() or _exit != Exit.ACTIVE or _ordinary_ending or _closing != null or _resolving
			or _gateway != null or intent == null or _closed_tick >= MAX_TICK):
		return Admission.INACTIVE
	if intent.run_id != _identity["run"]:
		return Admission.WRONG_RUN
	if intent.epoch != _epoch:
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
	if _identity.is_empty() or _closed_tick >= MAX_TICK or _resolving or _exit != Exit.ACTIVE:
		return false
	if _closing == null and not can_open_earning_group():
		return false
	_resolving = true
	var tick := next_tick()
	if _closing == null:
		_closing = _resolve_open_tick(tick)
	var published := _finish_resolved_tick(tick, _closing.outcomes)
	if published:
		_closed_tick = tick
		_publish(_closing.accepted, _closing.conflicts, _closing.overflowed, _closing.outcomes)
		_closing = null
	_resolving = false
	return published


func has_unpublished_tick() -> bool:
	return _closing != null


func _resolve_open_tick(tick: int) -> ClosingTick:
	var accepted: Array[RunIntent] = []
	var closing := ClosingTick.new()
	for seat: StringName in _realms:
		var inputs := _inputs[seat]
		if inputs.overflowed:
			closing.overflowed.append(seat)
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
					closing.conflicts.append(conflict)
				else:
					accepted.append(intent)
				stream.through = sequence
			stream.pending.clear()

	for intent: RunIntent in accepted:
		closing.accepted.append(intent.receipt())
	closing.outcomes = _resolve_tick(tick, accepted, _random)
	return closing


## Detached authority result. View adapters must project their permitted subset.
func closed_result() -> Dictionary:
	return _observation.duplicate(true)


## The last closed admission/RNG frontier. Pending intents are never checkpointed.
func checkpoint() -> Dictionary:
	if _identity.is_empty() or _exit != Exit.ACTIVE or _closing != null or _resolving or _gateway != null:
		return {}
	return _closed_checkpoint()


func _closed_checkpoint() -> Dictionary:
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
	if _epoch != _identity["epoch"]:
		saved["world_epoch"] = _epoch
	if _early_gateway_tick > 0:
		saved["early_gateway_tick"] = _early_gateway_tick
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
	var epoch: Variant = saved.get("world_epoch", setup.epoch)
	if not epoch is int or epoch < setup.epoch or epoch - setup.epoch > 1:
		return false
	var early_tick := 0
	if saved.has("early_gateway_tick"):
		var entry: Variant = saved["early_gateway_tick"]
		if epoch == setup.epoch or not RunObservatoryGateway.valid_early_tick(setup.seed, entry, tick):
			return false
		early_tick = entry
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
		if epoch != setup.epoch and ((early_tick == 0 and tick < RunParty.COLLAPSE_TICK) or realm != RunSetup.FINAL_REALM):
			return false
		if epoch == setup.epoch and realm == RunSetup.FINAL_REALM and setup.initial_realms[seat] != realm:
			return false
	var random := RunRandom.new(setup.seed)
	if not saved.get("random") is Dictionary or not random.restore(saved["random"]):
		return false
	if tick == 0 and not saved["random"].is_empty():
		return false
	_install(setup, random, tick, sequences)
	_epoch = epoch
	_early_gateway_tick = early_tick
	_realms.assign(realms)
	_publish([], [], [], [])
	return true


func _install(setup: RunSetup, random: RunRandom, tick: int, sequences: Dictionary) -> void:
	_identity = setup.identity()
	_epoch = setup.epoch
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
	for inputs: SeatInputs in _inputs.values():
		inputs.published_movement = inputs.primary.through
	_observation = {
		"tick": _closed_tick,
		"accepted": accepted,
		"conflicts": conflicts,
		"overflowed": overflowed,
		"outcomes": outcomes.duplicate(true),
	}
	if _epoch != _identity["epoch"]:
		_observation["world_epoch"] = _epoch


## Rules supply supported semantic actions and resolve a whole canonical batch.
## Outcomes are closed facts containing value data, with no live object references.
func _supports_action(_action: StringName) -> bool:
	return false


func _resolve_tick(_tick: int, _accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
	return []


## A storage wait can keep the admitted batch private until it can close.
func _finish_resolved_tick(_tick: int, _outcomes: Array[Dictionary]) -> bool:
	return true
