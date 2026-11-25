class_name PartyProgression
extends RefCounted
## Shared XP and an isolated frozen ordinary-offer queue for each run seat.
## Only the run owner sends XP entitlements and binds a selection to a seat.

enum Award { APPLIED, DUPLICATE, CONFLICT, INVALID, NUMERIC_FAULT }

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


static func begin(setup: RunSetup, preparations: Dictionary[StringName, RunPreparation],
		random: RunRandom) -> PartyProgression:
	if (setup == null or random == null or not setup.is_valid_for(setup.authority_id)
			or preparations.size() != setup.initial_realms.size()):
		return null
	var party := PartyProgression.new()
	for seat: StringName in setup.initial_realms:
		var preparation: RunPreparation = preparations.get(seat)
		if preparation == null or preparation.catalog_revision != setup.catalog_revision:
			return null
		party._queues[seat] = RunRewardQueue.begin(preparation, random, seat)
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
	return Award.APPLIED


func offer(bound_seat: StringName, ordinal: int) -> RunRewardQueue.Offer:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.read_offer(ordinal) if queue != null else null


func select(bound_seat: StringName, ordinal: int, id: StringName) -> RunRewardQueue.Selection:
	var queue: RunRewardQueue = _queues.get(bound_seat)
	return queue.select(ordinal, id) if queue != null else RunRewardQueue.Selection.UNKNOWN_REWARD


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
