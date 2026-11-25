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
var _preparation: Dictionary[StringName, Array] = {}
var _identity: Dictionary = {}
var _random: RunRandom
var _last_award_tick: int


static func begin(setup: RunSetup, preparations: Dictionary[StringName, RunPreparation]) -> PartyProgression:
	if (setup == null or not setup.is_valid_for(setup.authority_id)
			or preparations.size() != setup.initial_realms.size()):
		return null
	var party := PartyProgression.new()
	party._identity = setup.identity()
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


func grant_xp(entitlement: StringName, amount: Quantity, tick: int) -> Award:
	if (_queues.is_empty() or entitlement.is_empty() or amount == null or amount.sign_value <= 0
			or tick < 0 or tick > RunAuthority.MAX_TICK):
		return Award.INVALID
	var prior: Quantity = _awarded.get(entitlement)
	if prior != null:
		return Award.DUPLICATE if prior.compare(amount) == 0 else Award.CONFLICT
	if tick < _last_award_tick:
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


## Attach to the original host's closed native profile mutation. The store
## supplies the atomic durable receipt and compare-and-swap frontier boundary.
func frontier(closed_tick: int) -> ProfileMutation.Frontier:
	if _identity.is_empty() or closed_tick < _last_award_tick or closed_tick > RunAuthority.MAX_TICK:
		return null
	var awards: Dictionary[StringName, PackedByteArray] = {}
	for id: StringName in _awarded:
		awards[id] = QuantityCodec.encode(_awarded[id])
	var queues: Dictionary[StringName, Dictionary] = {}
	for seat: StringName in _queues:
		queues[seat] = _queues[seat].checkpoint()
	# The value-only image is stored locally. No received peer bytes enter this decoder.
	var image := var_to_bytes({"version": CHECKPOINT_VERSION, "identity": _identity,
		"tick": closed_tick, "awarded_at": _last_award_tick, "preparation": _preparation, "level": _level,
		"xp": QuantityCodec.encode(_xp), "awarded": awards, "random": _random.checkpoint(), "queues": queues})
	if image.is_empty() or image.size() > ProfileMutation.MAX_BYTES:
		return null
	var result := ProfileMutation.Frontier.new()
	result.run = String(_identity["run"])
	result.epoch = _identity["epoch"]
	result.tick = closed_tick
	result.image = image
	return result


static func reopen(setup: RunSetup, catalog: DefinitionCatalog, saved: Dictionary) -> PartyProgression:
	var bytes: Variant = saved.get("image")
	if (setup == null or catalog == null or catalog.revision != setup.catalog_revision
			or saved.get("epoch") != setup.epoch or not saved.get("tick") is int
			or not bytes is PackedByteArray or bytes.is_empty() or bytes.size() > ProfileMutation.MAX_BYTES):
		return null
	var image: Variant = bytes_to_var(bytes)
	if not image is Dictionary or not image.get("preparation") is Dictionary:
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
	return party


func _restore(image: Dictionary, closed_tick: int) -> bool:
	if (closed_tick < 0 or closed_tick > RunAuthority.MAX_TICK or image.get("tick") != closed_tick
			or image.get("version") != CHECKPOINT_VERSION or image.get("identity") != _identity
			or image.get("preparation") != _preparation or not image.get("level") is int
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
	_level = level
	_xp = carry
	_last_award_tick = image["awarded_at"]
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
