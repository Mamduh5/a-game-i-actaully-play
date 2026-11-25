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


static func draft(raw: QuantityFraction, nominal: Quantity, ordered_layers: Array[Pool],
		hp: Pool, hostile: bool) -> DamageDraft:
	if raw == null or nominal == null or nominal.sign_value < 0:
		return null
	var result := DamageDraft.new()
	var raw_left := raw
	var represented_left := nominal
	var represented_spent := Quantity.from_count(0)
	for pool: Pool in ordered_layers:
		var posting := _resolve(pool, raw_left, represented_left)
		if posting == null:
			return null
		result.layers.append(_debit(posting, hostile))
		represented_spent = represented_spent.add(posting.debit)
		if represented_spent == null:
			return null
		represented_left = posting.overkill
		if represented_left.sign_value == 0:
			raw_left = QuantityFraction.from_amount(represented_left)
		else:
			var exact_residual := pool.error.exact_after(pool.amount, raw_left)
			if exact_residual == null or exact_residual.numerator.sign_value >= 0:
				return null
			raw_left = exact_residual.opposite()
	var hit := _resolve(hp, raw_left, represented_left)
	if hit == null:
		return null
	result.hp = _debit(hit, false)
	result.lethal = hit.debit.sign_value > 0 and hit.remaining.sign_value == 0
	result.eligible_hostile_hp = hit.debit if hostile else Quantity.from_count(0)
	result.overkill = hit.overkill
	# Every threshold correction is attributable to this new origin. Existing receipts
	# are immutable and never recomputed after a later target exhausts its pool.
	result.incoming = represented_spent.add(hit.incoming)
	if result.incoming == null:
		return null
	result.adjustment = result.incoming.subtract(nominal)
	return result if result.adjustment != null else null


static func _resolve(pool: Pool, raw: QuantityFraction, nominal: Quantity) -> QuantityThresholdDebit.Draft:
	if pool == null or pool.amount == null or pool.error == null or pool.amount.sign_value < 0:
		return null
	if raw.numerator.sign_value == 0 and nominal.sign_value == 0:
		var untouched := QuantityThresholdDebit.Draft.new()
		untouched.incoming = nominal
		untouched.debit = nominal
		untouched.remaining = pool.amount
		untouched.overkill = nominal
		untouched.adjustment = nominal
		untouched.error = pool.error
		return untouched
	return QuantityThresholdDebit.resolve(pool.amount, pool.error, raw, nominal)


static func _debit(posting: QuantityThresholdDebit.Draft, hostile: bool) -> Debit:
	var result := Debit.new()
	result.spent = posting.debit
	result.after = Pool.new(posting.remaining, posting.error)
	result.hostile_depletion = hostile and result.spent.sign_value > 0 and result.after.amount.sign_value == 0
	return result
