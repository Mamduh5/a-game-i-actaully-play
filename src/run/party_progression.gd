class_name PartyProgression
extends RefCounted
## Shared XP and an isolated frozen ordinary-offer queue for each run seat.
## Only the run owner sends XP entitlements and binds a selection to a seat.

enum Award { APPLIED, DUPLICATE, CONFLICT, INVALID, NUMERIC_FAULT }

const CHECKPOINT_VERSION := 1

# OWNER-T04 prototype pacing. XP requirements use a whole-XP ceiling.
const BASE_XP := 100
const POLYNOMIAL_COEFFICIENT := 12
const POLYNOMIAL_EXPONENT := 2
const TRANSITION_LEVEL := 20
const GROWTH_NUMERATOR := 6
const GROWTH_DENOMINATOR := 5

var _level := 1
var _xp := Quantity.from_count(0)
var _queues: Dictionary[StringName, RunRewardQueue] = {}
var _awarded: Dictionary[StringName, Quantity] = {}
var _blessings: Dictionary[StringName, Array] = {}
var _preparation: Dictionary[StringName, Array] = {}
var _identity: Dictionary = {}
var _epoch: int
var _gateway_tick: int
var _random: RunRandom
var _last_award_tick: int


static func begin(setup: RunSetup, preparations: Dictionary[StringName, RunPreparation]) -> PartyProgression:
	if (setup == null or not setup.is_valid_for(setup.authority_id)
			or preparations.size() != setup.initial_realms.size()):
		return null
	var party := PartyProgression.new()
	party._identity = setup.identity()
	party._epoch = setup.epoch
	party._random = RunRandom.new(setup.seed)
	for seat: StringName in party._identity["initial_realms"]:
		var preparation: RunPreparation = preparations.get(seat)
		if preparation == null or preparation.catalog_revision != setup.catalog_revision:
			return null
		party._preparation[seat] = preparation.checkpoint()
		party._queues[seat] = RunRewardQueue.begin(preparation, party._random, seat)
	return party


func level() -> int:
	return _level


func carried_xp() -> Quantity:
	return _xp


func can_cross_gateway(identity: Dictionary, epoch: int, tick: int) -> bool:
	return _gateway_tick == 0 and epoch == _epoch and _identity == identity and tick >= _last_award_tick


## The authority calls this as part of the closed, validated gateway commit.
func enter_gateway(tick: int) -> void:
	_epoch += 1
	_gateway_tick = tick


func grant_xp(entitlement: StringName, amount: Quantity, tick: int) -> Award:
	if (_queues.is_empty() or entitlement.is_empty() or amount == null or amount.sign_value <= 0
			or tick < 0 or tick > RunAuthority.MAX_TICK):
		return Award.INVALID
	var prior: Quantity = _awarded.get(entitlement)
	if prior != null:
		return Award.DUPLICATE if prior.compare(amount) == 0 else Award.CONFLICT
	if tick < maxi(_last_award_tick, _gateway_tick):
		return Award.INVALID
	var carry := _xp.add(amount)
	if carry == null:
		return Award.NUMERIC_FAULT
	var next_level := _level
	while true:
		var need := xp_to_next(next_level)
		if need == null:
			return Award.NUMERIC_FAULT
		if carry.compare(need) < 0:
			break
		if next_level == RunAuthority.MAX_TICK:
			return Award.NUMERIC_FAULT
		carry = carry.subtract(need)
		if carry == null:
			return Award.NUMERIC_FAULT
		next_level += 1
	var earned := next_level - _level
	for queue: RunRewardQueue in _queues.values():
		if not queue.can_earn(earned):
			return Award.NUMERIC_FAULT
	# Each queue has its own named stream. Seat iteration cannot move the
	# draw position of any other seat.
	for queue: RunRewardQueue in _queues.values():
		for reward: int in earned:
			queue.earn(tick)
	_level = next_level
	_xp = carry
	_awarded[entitlement] = amount
	_last_award_tick = tick
	return Award.APPLIED


func offer(bound_seat: StringName, ordinal: int) -> RunRewardQueue.Offer:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.read_offer(ordinal) if queue != null else null


func select(bound_seat: StringName, ordinal: int, id: StringName) -> RunRewardQueue.Selection:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.select(ordinal, id) if queue != null else RunRewardQueue.Selection.UNKNOWN_REWARD


func compensate_if_stale(bound_seat: StringName, ordinal: int) -> RunRewardQueue.Selection:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.compensate_if_stale(ordinal) if queue != null else RunRewardQueue.Selection.UNKNOWN_REWARD


func active_power_form(bound_seat: StringName, base: StringName) -> StringName:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.active_form(base) if queue != null else &""


func trade_shards(bound_seat: StringName) -> Quantity:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.trade_shards() if queue != null else null


func overflow_bonus_basis_points(bound_seat: StringName, stat: StringName) -> int:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.overflow_bonus_basis_points(stat) if queue != null else 0


## The encounter owns the closed PR05 membership. Publish the benefit only
## after its one-time source claim and the progression frontier commit.
func settle_blessing(store: ProfileStore, presence: RunEncounterPresence, blessing: StringName,
		closed_tick: int) -> ProfileStore.Receipt:
	var invalid := ProfileStore.Receipt.new()
	invalid.status = ProfileStore.CommitResult.INVALID
	if (store == null or presence == null or _identity.is_empty()
			or not ProfileMutation.valid_id(String(blessing)) or not ProfileMutation.valid_id(String(presence.id))):
		return invalid
	var settled_at := presence.settlement_tick(_identity["run"], _epoch)
	if settled_at < 0 or closed_tick < settled_at or closed_tick > RunAuthority.MAX_TICK:
		return invalid
	var seats := presence.recipients()
	for seat: StringName in seats:
		if not _queues.has(seat):
			return invalid
	var record: Array = [blessing, seats, settled_at]
	var operation := "blessing/" + JSON.stringify([_identity["run"], presence.id]).sha256_text()
	if _blessings.has(presence.id):
		if _blessings[presence.id] != record:
			invalid.status = ProfileStore.CommitResult.CONFLICT
			return invalid
		var prior := store.lookup(operation)
		if prior.status == ProfileStore.CommitResult.COMMITTED:
			prior.status = ProfileStore.CommitResult.DUPLICATE
		return prior
	var staged := _blessings.duplicate()
	staged[presence.id] = record
	var mutation := ProfileMutation.new()
	mutation.id = operation
	mutation.rules = String(_identity["rules"])
	mutation.catalog = String(_identity["catalog"])
	mutation.claims.append(operation)
	mutation.frontier = _make_frontier(closed_tick, staged)
	if mutation.frontier == null:
		return invalid
	var receipt := store.commit_confirmed(mutation)
	if receipt.status in [ProfileStore.CommitResult.COMMITTED, ProfileStore.CommitResult.DUPLICATE]:
		_blessings = staged
	return receipt


func has_blessing(bound_seat: StringName, blessing: StringName) -> bool:
	for record: Array in _blessings.values():
		if record[0] == blessing and bound_seat in record[1]:
			return true
	return false


## Attach to the original host's closed native profile mutation. The store
## supplies the atomic durable receipt and compare-and-swap frontier boundary.
func frontier(closed_tick: int) -> ProfileMutation.Frontier:
	return _make_frontier(closed_tick, _blessings)


func _make_frontier(closed_tick: int, blessings: Dictionary[StringName, Array]) -> ProfileMutation.Frontier:
	if _identity.is_empty() or closed_tick < maxi(_last_award_tick, _gateway_tick) or closed_tick > RunAuthority.MAX_TICK:
		return null
	for record: Array in blessings.values():
		if record[2] > closed_tick:
			return null
	var awards: Dictionary[StringName, PackedByteArray] = {}
	for id: StringName in _awarded:
		awards[id] = QuantityCodec.encode(_awarded[id])
	var queues: Dictionary[StringName, Dictionary] = {}
	for seat: StringName in _queues:
		queues[seat] = _queues[seat].checkpoint()
	# The value-only image is stored locally. No received peer bytes enter this decoder.
	var snapshot := {"version": CHECKPOINT_VERSION, "identity": _identity,
		"tick": closed_tick, "awarded_at": _last_award_tick, "preparation": _preparation, "level": _level,
		"xp": QuantityCodec.encode(_xp), "awarded": awards, "random": _random.checkpoint(), "queues": queues}
	if not blessings.is_empty():
		snapshot["blessings"] = blessings
	if _gateway_tick > 0:
		snapshot["gateway_tick"] = _gateway_tick
	var image := var_to_bytes(snapshot)
	if image.is_empty() or image.size() > ProfileMutation.MAX_BYTES:
		return null
	var result := ProfileMutation.Frontier.new()
	result.run = String(_identity["run"])
	result.epoch = _epoch
	result.tick = closed_tick
	result.image = image
	return result


static func reopen(setup: RunSetup, catalog: DefinitionCatalog, saved: Dictionary) -> PartyProgression:
	var bytes: Variant = saved.get("image")
	var epoch: Variant = saved.get("epoch")
	if (setup == null or catalog == null or catalog.revision != setup.catalog_revision
			or not epoch is int or epoch < setup.epoch or epoch - setup.epoch > 1 or not saved.get("tick") is int
			or not bytes is PackedByteArray or bytes.is_empty() or bytes.size() > ProfileMutation.MAX_BYTES):
		return null
	var image: Variant = bytes_to_var(bytes)
	if (not image is Dictionary or not image.get("preparation") is Dictionary
			or image["preparation"].size() != setup.initial_realms.size()):
		return null
	var gateway_tick: Variant = image.get("gateway_tick", 0)
	if (not gateway_tick is int or (epoch == setup.epoch and gateway_tick != 0)
			or (epoch != setup.epoch and (gateway_tick < RunParty.COLLAPSE_TICK or gateway_tick > saved["tick"]))):
		return null
	var preparations: Dictionary[StringName, RunPreparation] = {}
	for seat: StringName in setup.initial_realms:
		var preparation := RunPreparation.reopen(catalog, image["preparation"].get(seat))
		if preparation == null:
			return null
		preparations[seat] = preparation
	var party := begin(setup, preparations)
	if party == null or not party._restore(image, saved["tick"]):
		return null
	party._epoch = epoch
	party._gateway_tick = gateway_tick
	return party


func _restore(image: Dictionary, closed_tick: int) -> bool:
	if (closed_tick < 0 or closed_tick > RunAuthority.MAX_TICK or image.get("tick") != closed_tick
			or image.get("version") != CHECKPOINT_VERSION or image.get("identity") != _identity
			or not image.get("level") is int
			or not image.get("awarded_at") is int or image["awarded_at"] < 0 or image["awarded_at"] > closed_tick):
		return false
	var level: int = image["level"]
	var need := xp_to_next(level)
	var carry := _read_xp(image.get("xp"))
	var awards: Variant = image.get("awarded")
	var queues: Variant = image.get("queues")
	var random: Variant = image.get("random")
	if (need == null or carry == null or carry.compare(need) >= 0 or not awards is Dictionary
			or not queues is Dictionary or queues.size() != _queues.size() or not random is Dictionary):
		return false
	for id: Variant in awards:
		if not id is StringName or id.is_empty():
			return false
		var amount := _read_xp(awards[id])
		if amount == null or amount.sign_value <= 0:
			return false
		_awarded[id] = amount
	for seat: StringName in _queues:
		var queue: Variant = queues.get(seat)
		if not queue is Dictionary or not _queues[seat].restore(queue, level - 1, image["awarded_at"]):
			return false
	if not _random.restore(random):
		return false
	if not _restore_blessings(image.get("blessings", {}), closed_tick):
		return false
	_level = level
	_xp = carry
	_last_award_tick = image["awarded_at"]
	return true


func _restore_blessings(saved: Variant, closed_tick: int) -> bool:
	if not saved is Dictionary:
		return false
	for occurrence: Variant in saved:
		var record: Variant = saved[occurrence]
		if (not occurrence is StringName or not ProfileMutation.valid_id(String(occurrence))
				or not record is Array or record.size() != 3
				or not record[0] is StringName or not ProfileMutation.valid_id(String(record[0]))
				or not record[1] is Array or not record[2] is int or record[2] < 0 or record[2] > closed_tick):
			return false
		var previous := ""
		for seat: Variant in record[1]:
			if not seat is StringName or not _queues.has(seat) or String(seat) <= previous:
				return false
			previous = String(seat)
		_blessings[occurrence] = record
	return true


static func _read_xp(bytes: Variant) -> Quantity:
	if not bytes is PackedByteArray:
		return null
	var amounts := QuantityCodec.decode_fields(bytes, 0, 1)
	return amounts[0] if amounts.size() == 1 and amounts[0].sign_value >= 0 else null


static func xp_to_next(current_level: int) -> Quantity:
	var polynomial := QuantityFraction.from_amount(Quantity.from_count(POLYNOMIAL_EXPONENT))
	var growth := QuantityFraction.create(Quantity.from_count(GROWTH_NUMERATOR), Quantity.from_count(GROWTH_DENOMINATOR))
	var bounds := QuantityProgression.xp_need_bounds(current_level, TRANSITION_LEVEL,
		Quantity.from_count(BASE_XP), Quantity.from_count(POLYNOMIAL_COEFFICIENT), polynomial, growth, 0)
	if bounds.is_empty():
		return null
	var exact := bounds[0]
	var rounded := exact.outward(0)
	return rounded[1] if rounded.size() == 2 else null
