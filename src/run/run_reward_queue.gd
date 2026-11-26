class_name RunRewardQueue
extends RefCounted
## Personal ordinary options. The authority calls earn at the earning event
## and binds the selection to this queue's owning seat.

const POWER_SLOTS := 10
const MAX_RANK := 5
const ORDINARY_OPTIONS := 3
const OVERFLOW_STATS := [&"overflow.damage", &"overflow.max_hp", &"overflow.physical_defense"]
const OVERFLOW_STEPS := [300, 200, 100]
const SHARD_OPTION := &"utility.trade_shard"

enum Selection { APPLIED, UNKNOWN_REWARD, INVALID_OPTION, STALE_OPTION, COMPENSATED, NUMERIC_FAULT }
enum Kind { POWER, OVERFLOW, UTILITY }

class Offer:
	var ordinal: int
	var earned_at: int
	var kind: Kind
	var evolution: StringName
	var fusion: StringName
	var options: Dictionary[StringName, int] = {}

	func copy() -> Offer:
		var result := Offer.new()
		result.ordinal = ordinal
		result.earned_at = earned_at
		result.kind = kind
		result.evolution = evolution
		result.fusion = fusion
		result.options = options.duplicate()
		return result

var _preparation: RunPreparation
var _random: RunRandom
var _stream: StringName
var _last_offer: int
var _ranks: Dictionary[StringName, int] = {}
var _forms: Dictionary[StringName, StringName] = {}
var _transformation_order: Array[StringName] = []
var _overflow: Dictionary[StringName, int] = {}
var _trade_shards := Quantity.from_count(0)
var _open: Dictionary[int, Offer] = {}
var _last_shown: Dictionary[StringName, int] = {}
var _evolution_shown: Dictionary[StringName, int] = {}
var _fusion_shown: Dictionary[StringName, int] = {}


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
	if offer.options.is_empty():
		offer.kind = Kind.OVERFLOW
		for stat: StringName in OVERFLOW_STATS:
			var next := _next_overflow(stat)
			if next > 0:
				offer.options[stat] = next
		if offer.options.is_empty():
			offer.kind = Kind.UTILITY
			offer.options[SHARD_OPTION] = 1
	offer.evolution = _next_bonus(CatalogEntry.Kind.EVOLUTION, _evolution_shown)
	if not offer.evolution.is_empty():
		offer.options[offer.evolution] = 1
		_evolution_shown[offer.evolution] = offer.ordinal
	offer.fusion = _next_bonus(CatalogEntry.Kind.FUSION, _fusion_shown)
	if not offer.fusion.is_empty():
		offer.options[offer.fusion] = 1
		_fusion_shown[offer.fusion] = offer.ordinal
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
	if not _still_eligible(offer, id):
		return compensate_if_stale(ordinal)
	if id == offer.evolution or id == offer.fusion:
		_install_form(_preparation.catalog.lookup(id), _forms)
		_transformation_order.append(id)
	else:
		match offer.kind:
			Kind.POWER: _ranks[id] = offer.options[id]
			Kind.OVERFLOW: _overflow[id] = offer.options[id]
			Kind.UTILITY: return _grant_shard(ordinal, Selection.APPLIED)
	_open.erase(ordinal)
	return Selection.APPLIED


func compensate_if_stale(ordinal: int) -> Selection:
	var offer: Offer = _open.get(ordinal)
	if offer == null:
		return Selection.UNKNOWN_REWARD
	for id: StringName in offer.options:
		if _still_eligible(offer, id):
			return Selection.STALE_OPTION
	return _grant_shard(ordinal, Selection.COMPENSATED)


func ranks() -> Dictionary[StringName, int]:
	return _ranks.duplicate()


func active_form(base: StringName) -> StringName:
	return _forms.get(base, base) if _ranks.has(base) else &""


func trade_shards() -> Quantity:
	return _trade_shards


func overflow_bonus_basis_points(stat: StringName) -> int:
	var total := 0
	for step: int in int(_overflow.get(stat, 0)):
		total += OVERFLOW_STEPS[step]
	return total


func checkpoint() -> Dictionary:
	var pending: Array[Array] = []
	for offer: Offer in _open.values():
		var row: Array = [offer.ordinal, offer.earned_at, offer.options.duplicate(), offer.kind]
		if not offer.evolution.is_empty() or not offer.fusion.is_empty():
			row.append(offer.evolution)
		if not offer.fusion.is_empty():
			row.append(offer.fusion)
		pending.append(row)
	var saved := {"ordinal": _last_offer, "ranks": _ranks.duplicate(), "shown": _last_shown.duplicate(), "pending": pending,
		"overflow": _overflow.duplicate(), "shards": QuantityCodec.encode(_trade_shards)}
	if not _evolution_shown.is_empty():
		saved["evolution_shown"] = _evolution_shown.duplicate()
	if not _fusion_shown.is_empty():
		saved["fusion_shown"] = _fusion_shown.duplicate()
	if not _transformation_order.is_empty():
		var field := "evolution_order"
		for id: StringName in _transformation_order:
			if _fusion_shown.has(id):
				field = "transformation_order"
				break
		saved[field] = _transformation_order.duplicate()
	return saved


## Import into a fresh, already scoped queue. Only validated local recovery
## can install selections and cards without replaying the player's inputs.
func restore(image: Dictionary, expected_offers: int, closed_tick: int) -> bool:
	if (_last_offer != 0 or _preparation == null or not image.get("ordinal") is int
			or image["ordinal"] != expected_offers):
		return false
	var eligible := _preparation.eligible_powers()
	var saved_ranks: Variant = image.get("ranks")
	var overflow: Variant = image.get("overflow", {})
	var shards: Variant = image.get("shards", QuantityCodec.encode(Quantity.from_count(0)))
	var shown: Variant = image.get("shown")
	var pending: Variant = image.get("pending")
	var evolution_shown: Variant = image.get("evolution_shown", {})
	var fusion_shown: Variant = image.get("fusion_shown", {})
	var order: Variant = image.get("transformation_order", image.get("evolution_order", []))
	if (not _valid_options(saved_ranks, POWER_SLOTS, eligible, MAX_RANK) or not shown is Dictionary
			or not _valid_options(overflow, OVERFLOW_STATS.size(), OVERFLOW_STATS, OVERFLOW_STEPS.size())
			or not shards is PackedByteArray or not pending is Array or pending.size() > expected_offers
			or not order is Array or order.size() > POWER_SLOTS + (POWER_SLOTS >> 1)
			or not _valid_bonus_rotation(evolution_shown, CatalogEntry.Kind.EVOLUTION, expected_offers)
			or not _valid_bonus_rotation(fusion_shown, CatalogEntry.Kind.FUSION, expected_offers)):
		return false
	var wallet := QuantityCodec.decode_fields(shards, 0, 1)
	if wallet.size() != 1 or wallet[0].sign_value < 0 or wallet[0].scale != 0:
		return false
	for power: Variant in shown:
		if (not power is StringName or not power in eligible or not shown[power] is int
				or shown[power] < 1 or shown[power] > expected_offers):
			return false
	var restored: Dictionary[StringName, StringName] = {}
	for id: Variant in order:
		if not id is StringName or not (evolution_shown.has(id) or fusion_shown.has(id)):
			return false
		var def := _preparation.catalog.lookup(id)
		if not _can_transform(def, saved_ranks, restored):
			return false
		_install_form(def, restored)
	var offers: Dictionary[int, Offer] = {}
	var previous_ordinal := 0
	var previous_tick := 0
	for row: Variant in pending:
		if (not row is Array or row.size() < 3 or row.size() > 6 or not row[0] is int or not row[1] is int
				or row[0] <= previous_ordinal or row[0] > expected_offers or row[1] < previous_tick
				or row[1] > closed_tick or not row[2] is Dictionary):
			return false
		var kind: Variant = row[3] if row.size() >= 4 else Kind.POWER
		var evolution: Variant = row[4] if row.size() >= 5 else &""
		var fusion: Variant = row[5] if row.size() == 6 else &""
		var ordinary: Dictionary = row[2].duplicate()
		if (not _strip_bonus(evolution, evolution_shown, row[0], ordinary)
				or not _strip_bonus(fusion, fusion_shown, row[0], ordinary)):
			return false
		if (row.size() == 5 and evolution.is_empty()) or (row.size() == 6 and fusion.is_empty()):
			return false
		if not kind is int or not _valid_frozen_options(kind, ordinary, eligible, shown, row[0]):
			return false
		var offer := Offer.new()
		offer.ordinal = row[0]
		offer.earned_at = row[1]
		offer.kind = kind
		offer.evolution = evolution
		offer.fusion = fusion
		offer.options.assign(row[2])
		offers[offer.ordinal] = offer
		previous_ordinal = offer.ordinal
		previous_tick = offer.earned_at
	_last_offer = expected_offers
	_ranks.assign(saved_ranks)
	_forms = restored
	_transformation_order.assign(order)
	_overflow.assign(overflow)
	_trade_shards = wallet[0]
	_last_shown.assign(shown)
	_evolution_shown.assign(evolution_shown)
	_fusion_shown.assign(fusion_shown)
	_open = offers
	return true


func _valid_bonus_rotation(saved: Variant, kind: CatalogEntry.Kind, ordinal: int) -> bool:
	if not saved is Dictionary:
		return false
	for id: Variant in saved:
		if not id is StringName or not saved[id] is int or saved[id] < 1 or saved[id] > ordinal:
			return false
		var definition := _preparation.catalog.lookup(id)
		if definition == null or definition.kind != kind:
			return false
	return true


static func _strip_bonus(id: Variant, shown: Dictionary, ordinal: int, choices: Dictionary) -> bool:
	if not id is StringName:
		return false
	if id.is_empty():
		return true
	return choices.get(id) == 1 and int(shown.get(id, 0)) >= ordinal and choices.erase(id)


static func _valid_frozen_options(kind: Kind, rows: Variant, eligible: Array[StringName], shown: Dictionary, ordinal: int) -> bool:
	if not rows is Dictionary or rows.is_empty():
		return false
	match kind:
		Kind.POWER:
			if not _valid_options(rows, ORDINARY_OPTIONS, eligible, MAX_RANK):
				return false
			for id: StringName in rows:
				if int(shown.get(id, 0)) < ordinal:
					return false
			return true
		Kind.OVERFLOW:
			return _valid_options(rows, OVERFLOW_STATS.size(), OVERFLOW_STATS, OVERFLOW_STEPS.size())
		Kind.UTILITY:
			return _valid_options(rows, 1, [SHARD_OPTION], 1)
	return false


static func _valid_options(rows: Variant, limit: int, eligible: Array, highest_step: int) -> bool:
	if not rows is Dictionary or rows.size() > limit:
		return false
	for power: Variant in rows:
		if (not power is StringName or not power in eligible or not rows[power] is int
				or rows[power] < 1 or rows[power] > highest_step):
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
	owned.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
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


func _next_overflow(stat: StringName) -> int:
	var current: int = _overflow.get(stat, 0)
	return current + 1 if current < OVERFLOW_STEPS.size() else 0


func _next_bonus(kind: CatalogEntry.Kind, rotation: Dictionary[StringName, int]) -> StringName:
	var next: StringName
	var last := _last_offer
	for id: StringName in _preparation.catalog.ids_of_kind(kind):
		var shown: int = rotation.get(id, 0)
		if shown < last and _can_transform(_preparation.catalog.lookup(id), _ranks, _forms):
			next = id
			last = shown
	return next


func _can_transform(form: CatalogDefinition, ranks_by_base: Dictionary,
		forms_by_base: Dictionary[StringName, StringName]) -> bool:
	if form == null:
		return false
	if form.kind == CatalogEntry.Kind.EVOLUTION:
		if (ranks_by_base.get(form.base.id, 0) != MAX_RANK or forms_by_base.has(form.base.id)
				or not _has_catalyst(form, ranks_by_base, forms_by_base)):
			return false
	elif form.kind == CatalogEntry.Kind.FUSION:
		for link: CatalogDefinition.Reference in form.components:
			var component := _preparation.catalog.resolve(link)
			if forms_by_base.get(component.base.id) != component.id:
				return false
	else:
		return false
	var projected := forms_by_base.duplicate()
	_install_form(form, projected)
	for id: StringName in projected.values():
		var active := _preparation.catalog.lookup(id)
		if active.kind == CatalogEntry.Kind.FUSION and not _fusion_requirements(active, ranks_by_base, projected):
			return false
	return true


func _fusion_requirements(fusion: CatalogDefinition, ranks_by_base: Dictionary, forms_by_base: Dictionary) -> bool:
	var equipped := _preparation.runes()
	for rune: CatalogDefinition.Reference in fusion.fusion_runes:
		if rune.id not in equipped:
			return false
	var first := _preparation.catalog.resolve(fusion.components[0])
	var second := _preparation.catalog.resolve(fusion.components[1])
	return ((first.catalyst.id == second.base.id or _has_catalyst(first, ranks_by_base, forms_by_base))
		and (second.catalyst.id == first.base.id or _has_catalyst(second, ranks_by_base, forms_by_base)))


func _has_catalyst(form: CatalogDefinition, ranks_by_base: Dictionary, forms_by_base: Dictionary) -> bool:
	var catalyst := _preparation.catalog.resolve(form.catalyst)
	if catalyst.kind == CatalogEntry.Kind.RUNE:
		return catalyst.id in _preparation.runes()
	if not ranks_by_base.has(catalyst.id):
		return false
	var provided := _preparation.catalog.lookup(forms_by_base.get(catalyst.id, catalyst.id))
	if provided.kind == CatalogEntry.Kind.FUSION:
		var first := _preparation.catalog.resolve(provided.components[0])
		var retained := provided.first_component_capabilities if first.base.id == catalyst.id else provided.second_component_capabilities
		return form.catalyst_capability in retained
	return form.catalyst_capability in provided.capabilities


func _install_form(form: CatalogDefinition, slots: Dictionary[StringName, StringName]) -> void:
	if form.kind == CatalogEntry.Kind.EVOLUTION:
		slots[form.base.id] = form.id
		return
	for link: CatalogDefinition.Reference in form.components:
		var component := _preparation.catalog.resolve(link)
		slots[component.base.id] = form.id


func _still_eligible(offer: Offer, id: StringName) -> bool:
	if id == offer.evolution or id == offer.fusion:
		return _can_transform(_preparation.catalog.lookup(id), _ranks, _forms)
	match offer.kind:
		Kind.POWER: return _next_rank(id) == offer.options[id]
		Kind.OVERFLOW: return _next_overflow(id) == offer.options[id]
		Kind.UTILITY: return true
	return false


func _grant_shard(ordinal: int, result: Selection) -> Selection:
	var wallet := _trade_shards.add(Quantity.from_count(1))
	if wallet == null:
		return Selection.NUMERIC_FAULT
	_trade_shards = wallet
	_open.erase(ordinal)
	return result


func _shuffle(candidates: Array[StringName]) -> void:
	for last: int in range(candidates.size() - 1, 0, -1):
		var other := _random.draw(_stream) % (last + 1)
		var id := candidates[last]
		candidates[last] = candidates[other]
		candidates[other] = id
