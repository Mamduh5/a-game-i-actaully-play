class_name RunRewardQueue
extends RefCounted
## Personal ordinary options. The authority calls earn at the earning event
## and binds the selection to this queue's owning seat.

const POWER_SLOTS := 10
const MAX_RANK := 5
const ORDINARY_OPTIONS := 3

enum Selection { APPLIED, UNKNOWN_REWARD, INVALID_OPTION, STALE_OPTION }

class Offer:
	var ordinal: int
	var earned_at: int
	var options: Dictionary[StringName, int] = {}

	func copy() -> Offer:
		var result := Offer.new()
		result.ordinal = ordinal
		result.earned_at = earned_at
		result.options = options.duplicate()
		return result

var _preparation: RunPreparation
var _random: RunRandom
var _stream: StringName
var _last_offer: int
var _ranks: Dictionary[StringName, int] = {}
var _open: Dictionary[int, Offer] = {}
var _last_shown: Dictionary[StringName, int] = {}


static func begin(preparation: RunPreparation, random: RunRandom, bound_seat: StringName) -> RunRewardQueue:
	if preparation == null or preparation.catalog_revision.is_empty() or random == null or bound_seat.is_empty():
		return null
	var queue := RunRewardQueue.new()
	queue._preparation = preparation
	queue._random = random
	queue._stream = StringName("ordinary_rewards/%s" % bound_seat)
	return queue


func earn(tick: int) -> int:
	if tick < 0 or tick > RunAuthority.MAX_TICK or not can_earn(1):
		return 0
	_last_offer += 1
	var offer := Offer.new()
	offer.ordinal = _last_offer
	offer.earned_at = tick
	var candidates := _eligible_cards()
	_shuffle(candidates)
	for option: int in mini(ORDINARY_OPTIONS, candidates.size()):
		var first := 0
		for index: int in range(1, candidates.size()):
			if int(_last_shown.get(candidates[index], 0)) < int(_last_shown.get(candidates[first], 0)):
				first = index
		var id: StringName = candidates.pop_at(first)
		offer.options[id] = _next_rank(id)
		_last_shown[id] = offer.ordinal
	_open[offer.ordinal] = offer
	return offer.ordinal


func can_earn(count: int) -> bool:
	return _preparation != null and count >= 0 and count <= RunAuthority.MAX_TICK - _last_offer


func read_offer(ordinal: int) -> Offer:
	var offer: Offer = _open.get(ordinal)
	return offer.copy() if offer != null else null


func select(ordinal: int, id: StringName) -> Selection:
	var offer: Offer = _open.get(ordinal)
	if offer == null:
		return Selection.UNKNOWN_REWARD
	if not offer.options.has(id):
		return Selection.INVALID_OPTION
	var rank := _next_rank(id)
	if rank != offer.options[id]:
		return Selection.STALE_OPTION
	_ranks[id] = rank
	_open.erase(ordinal)
	return Selection.APPLIED


func ranks() -> Dictionary[StringName, int]:
	return _ranks.duplicate()


func checkpoint() -> Dictionary:
	var pending: Array[Array] = []
	for offer: Offer in _open.values():
		pending.append([offer.ordinal, offer.earned_at, offer.options.duplicate()])
	return {"ordinal": _last_offer, "ranks": _ranks.duplicate(), "shown": _last_shown.duplicate(), "pending": pending}


## Import into a fresh, already scoped queue. Only validated local recovery
## can install selections and cards without replaying the player's inputs.
func restore(image: Dictionary, expected_offers: int, closed_tick: int) -> bool:
	if (_last_offer != 0 or _preparation == null or not image.get("ordinal") is int
			or image["ordinal"] != expected_offers):
		return false
	var eligible := _preparation.eligible_powers()
	var saved_ranks: Variant = image.get("ranks")
	var shown: Variant = image.get("shown")
	var pending: Variant = image.get("pending")
	if (not _valid_ranks(saved_ranks, POWER_SLOTS, eligible) or not shown is Dictionary
			or not pending is Array or pending.size() > expected_offers):
		return false
	for power: Variant in shown:
		if (not power is StringName or not power in eligible or not shown[power] is int
				or shown[power] < 1 or shown[power] > expected_offers):
			return false
	var offers: Dictionary[int, Offer] = {}
	var previous_ordinal := 0
	var previous_tick := 0
	for row: Variant in pending:
		if (not row is Array or row.size() != 3 or not row[0] is int or not row[1] is int
				or row[0] <= previous_ordinal or row[0] > expected_offers or row[1] < previous_tick
				or row[1] > closed_tick or not _valid_ranks(row[2], ORDINARY_OPTIONS, eligible)):
			return false
		for power: StringName in row[2]:
			if int(shown.get(power, 0)) < row[0]:
				return false
		var offer := Offer.new()
		offer.ordinal = row[0]
		offer.earned_at = row[1]
		offer.options.assign(row[2])
		offers[offer.ordinal] = offer
		previous_ordinal = offer.ordinal
		previous_tick = offer.earned_at
	_last_offer = expected_offers
	_ranks.assign(saved_ranks)
	_last_shown.assign(shown)
	_open = offers
	return true


static func _valid_ranks(rows: Variant, limit: int, eligible: Array[StringName]) -> bool:
	if not rows is Dictionary or rows.size() > limit:
		return false
	for power: Variant in rows:
		if (not power is StringName or not power in eligible or not rows[power] is int
				or rows[power] < 1 or rows[power] > MAX_RANK):
			return false
	return true


func _eligible_cards() -> Array[StringName]:
	var candidates: Array[StringName] = []
	var prepared := _preparation.candidates()
	var blanks := prepared.count(&"")
	for id: StringName in prepared:
		if not id.is_empty() and _next_rank(id) > 0:
			candidates.append(id)
	var owned: Array[StringName] = _ranks.keys()
	owned.sort()
	for id: StringName in owned:
		if not id in prepared and _next_rank(id) > 0:
			candidates.append(id)
	if blanks > 0 and _ranks.size() < POWER_SLOTS:
		var wildcards: Array[StringName] = []
		for id: StringName in _preparation.eligible_powers():
			if not id in prepared and not _ranks.has(id):
				wildcards.append(id)
		_shuffle(wildcards)
		candidates.append_array(wildcards.slice(0, blanks))
	return candidates


func _next_rank(id: StringName) -> int:
	var current: int = _ranks.get(id, 0)
	if current >= MAX_RANK or (current == 0 and _ranks.size() >= POWER_SLOTS):
		return 0
	return current + 1


func _shuffle(candidates: Array[StringName]) -> void:
	for last: int in range(candidates.size() - 1, 0, -1):
		var other := _random.draw(_stream) % (last + 1)
		var id := candidates[last]
		candidates[last] = candidates[other]
		candidates[other] = id
