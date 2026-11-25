class_name QuantityLayerLedger
extends RefCounted
## Certified damage over one origin's ordered finite claims. A failed draft has
## no effect on any supplied pool.

class Pool:
	var amount: Quantity
	var error: QuantityErrorBounds

	func _init(value: Quantity, uncertainty: QuantityErrorBounds) -> void:
		amount = value
		error = uncertainty

class Debit:
	var spent: Quantity
	var after: Pool
	var hostile_depletion: bool

class DamageDraft:
	var layers: Array[Debit] = []
	var hp: Debit
	var incoming: Quantity
	var overkill: Quantity
	var adjustment: Quantity
	var lethal: bool
	var eligible_hostile_hp: Quantity

class RecoveryDraft:
	var hp: Pool
	var hp_restored: Quantity
	var eligible_excess: Pool
	var discarded: Quantity
	var offered: Quantity
	var adjustment: Quantity
	var reserve_after: Pool
	var reserve_stored: Quantity


static func draft(raw: QuantityFraction, nominal: Quantity, ordered_layers: Array[Pool],
		hp: Pool, hostile: bool) -> DamageDraft:
	if raw == null or nominal == null or nominal.sign_value < 0:
		return null
	var result := DamageDraft.new()
	var zero := Quantity.from_count(0)
	var raw_left := raw if nominal.sign_value != 0 or raw.numerator.sign_value != 0 else null
	var incoming_error: QuantityErrorBounds
	var represented_left := nominal
	var represented_spent := zero
	for pool: Pool in ordered_layers:
		if raw_left == null:
			var untouched := _untouched(pool, zero)
			if untouched == null:
				return null
			result.layers.append(untouched)
			continue
		var bounds := _effective_bounds(pool, incoming_error)
		if bounds == null:
			return null
		var posting := QuantityThresholdDebit.resolve(pool.amount, bounds, raw_left, represented_left)
		if posting == null:
			return null
		result.layers.append(_debit(posting, hostile))
		represented_spent = represented_spent.add(posting.debit)
		if represented_spent == null:
			return null
		represented_left = posting.overkill
		incoming_error = null
		if represented_left.sign_value == 0:
			raw_left = null
		else:
			var exact_residual := bounds.exact_after(pool.amount, raw_left)
			if exact_residual != null:
				if exact_residual.numerator.sign_value >= 0:
					return null
				raw_left = exact_residual.opposite()
			else:
				# The exhausted layer has already certified strict overkill. Carry the
				# unresolved ideal-minus-represented difference into the next pool.
				var residual_error := bounds.after_debit(raw_left, posting.incoming)
				if residual_error == null:
					return null
				incoming_error = residual_error.opposite()
				raw_left = QuantityFraction.from_amount(represented_left)
				if raw_left == null:
					return null
	if raw_left == null:
		result.hp = _untouched(hp, zero)
		result.overkill = zero
		result.incoming = represented_spent
	else:
		var bounds := _effective_bounds(hp, incoming_error)
		if bounds == null:
			return null
		var hit := QuantityThresholdDebit.resolve(hp.amount, bounds, raw_left, represented_left)
		if hit == null:
			return null
		result.hp = _debit(hit, false)
		result.lethal = hit.debit.sign_value > 0 and hit.remaining.sign_value == 0
		result.overkill = hit.overkill
		result.incoming = represented_spent.add(hit.incoming)
	if result.hp == null or result.incoming == null:
		return null
	result.eligible_hostile_hp = result.hp.spent if hostile else zero
	# Every threshold correction is attributable to this new origin. Existing receipts
	# are immutable and never recomputed after a later target exhausts its pool.
	result.adjustment = result.incoming.subtract(nominal)
	return result if result.adjustment != null else null


## Maximum HP is the represented cap of this life. Raw and nominal describe
## the same already-eligible healing source, after its independent limits.
static func recovery(raw: QuantityFraction, nominal: Quantity, hp: Pool,
		maximum: Quantity, excess_allowed: bool) -> RecoveryDraft:
	if (raw == null or nominal == null or raw.numerator.sign_value != nominal.sign_value or nominal.sign_value < 0
			or hp == null or hp.amount == null or hp.error == null or maximum == null
			or hp.amount.sign_value < 0 or hp.amount.compare(maximum) > 0):
		return null
	var zero := Quantity.from_count(0)
	var living := hp.error.certify_after(hp.amount, QuantityFraction.from_amount(zero))
	if (hp.amount.sign_value == 0 and living != QuantityErrorBounds.Sign.EQUAL) or (
			hp.amount.sign_value > 0 and living != QuantityErrorBounds.Sign.ABOVE):
		return null
	var result := RecoveryDraft.new()
	result.eligible_excess = Pool.new(zero, QuantityErrorBounds.new())
	if living == QuantityErrorBounds.Sign.EQUAL or nominal.sign_value == 0:
		result.hp = hp
		result.hp_restored = zero
		result.discarded = nominal
		result.offered = nominal
		result.adjustment = zero
		return result
	var missing := maximum.subtract(hp.amount)
	if missing == null:
		return null
	var missing_error := hp.error.opposite()
	var posted := QuantityThresholdDebit.resolve(missing, missing_error, raw, nominal)
	if posted == null:
		return null
	var after := maximum.subtract(posted.remaining)
	if after == null:
		return null
	result.hp = Pool.new(after, posted.error.opposite())
	result.hp_restored = posted.debit
	result.offered = posted.incoming
	result.adjustment = posted.adjustment
	result.discarded = posted.overkill
	if excess_allowed and posted.overkill.sign_value > 0:
		var error := missing_error.after_debit(raw, posted.incoming)
		if error == null:
			return null
		result.eligible_excess = Pool.new(posted.overkill, error.opposite())
		result.discarded = zero
	return result


## Recovery and its one-to-one reserve conversion belong to the same origin.
## A correction at the reserve boundary is included in this draft's offer.
static func recovery_to_reserve(raw: QuantityFraction, nominal: Quantity, hp: Pool,
		maximum: Quantity, reserve: Pool, reserve_cap: Quantity) -> RecoveryDraft:
	if (reserve == null or reserve.amount == null or reserve.error == null or reserve_cap == null
			or reserve.amount.sign_value < 0 or reserve.amount.compare(reserve_cap) > 0):
		return null
	var result := recovery(raw, nominal, hp, maximum, true)
	if result == null:
		return null
	var excess := result.eligible_excess
	var zero := Quantity.from_count(0)
	result.reserve_stored = zero
	result.reserve_after = reserve
	if excess.amount.sign_value == 0:
		return result

	var room := reserve_cap.subtract(reserve.amount)
	var room_error := reserve.error.opposite().minus(excess.error)
	var deposit := QuantityThresholdDebit.resolve(room, room_error, QuantityFraction.from_amount(excess.amount),
			excess.amount)
	if deposit == null:
		return null
	var balance := reserve_cap.subtract(deposit.remaining)
	var offer := result.hp_restored.add(deposit.incoming)
	if balance == null or offer == null:
		return null
	result.reserve_after = Pool.new(balance, deposit.error.opposite())
	result.reserve_stored = deposit.debit
	result.eligible_excess = Pool.new(zero, QuantityErrorBounds.new())
	result.discarded = deposit.overkill
	result.offered = offer
	result.adjustment = offer.subtract(nominal)
	return result if result.adjustment != null else null


static func _effective_bounds(pool: Pool, incoming_error: QuantityErrorBounds) -> QuantityErrorBounds:
	if pool == null or pool.amount == null or pool.amount.sign_value < 0 or pool.error == null:
		return null
	return pool.error if incoming_error == null else pool.error.minus(incoming_error)


static func _untouched(pool: Pool, zero: Quantity) -> Debit:
	if _effective_bounds(pool, null) == null:
		return null
	var result := Debit.new()
	result.spent = zero
	result.after = Pool.new(pool.amount, pool.error)
	return result


static func _debit(posting: QuantityThresholdDebit.Draft, hostile: bool) -> Debit:
	var result := Debit.new()
	result.spent = posting.debit
	result.after = Pool.new(posting.remaining, posting.error)
	result.hostile_depletion = hostile and result.spent.sign_value > 0 and result.after.amount.sign_value == 0
	return result
