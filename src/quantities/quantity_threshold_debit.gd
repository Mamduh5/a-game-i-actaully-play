class_name QuantityThresholdDebit
extends RefCounted
## Resolves one pool frontier. The owner commits the returned amount and error
## together, after every other posting in the group can also be certified.

class Draft:
	var incoming: Quantity
	var debit: Quantity
	var remaining: Quantity
	var overkill: Quantity
	var adjustment: Quantity
	var error: QuantityErrorBounds


static func resolve(remaining: Quantity, bounds: QuantityErrorBounds, raw: QuantityFraction,
		nominal: Quantity) -> Draft:
	if (remaining == null or bounds == null or raw == null or nominal == null
			or remaining.sign_value < 0 or raw.numerator.sign_value < 0
			or raw.numerator.sign_value != nominal.sign_value):
		return null
	var branch := bounds.certify_after(remaining, raw)
	if branch == QuantityErrorBounds.Sign.UNKNOWN:
		return null
	var incoming := nominal
	if remaining.compare(nominal) != branch:
		incoming = _align_branch(remaining, bounds, raw, branch)
		if incoming == null or incoming.sign_value != nominal.sign_value or remaining.compare(incoming) != branch:
			return null
	var draft := Draft.new()
	draft.incoming = incoming
	var zero := Quantity.from_count(0)
	draft.adjustment = zero if incoming == nominal else incoming.subtract(nominal)
	draft.debit = incoming if branch == QuantityErrorBounds.Sign.ABOVE else remaining
	draft.remaining = remaining.subtract(incoming) if branch == QuantityErrorBounds.Sign.ABOVE else zero
	draft.overkill = incoming.subtract(remaining) if branch == QuantityErrorBounds.Sign.BELOW else zero
	if draft.adjustment == null or draft.remaining == null or draft.overkill == null:
		return null
	if branch == QuantityErrorBounds.Sign.ABOVE:
		draft.error = bounds.after_debit(raw, draft.debit)
	else:
		draft.error = QuantityErrorBounds.new()
	return draft if draft.error != null else null


static func _align_branch(remaining: Quantity, bounds: QuantityErrorBounds, raw: QuantityFraction,
		branch: QuantityErrorBounds.Sign) -> Quantity:
	if branch == QuantityErrorBounds.Sign.EQUAL:
		return remaining
	var exact := bounds.exact_after(remaining, raw)
	if exact == null:
		return null
	var delta := Quantity.quantize_ratio(exact.numerator.absolute(), exact.divisor)
	if delta == null or delta.sign_value <= 0:
		return null
	# Compare against an independently rounded exact residual. The correction consists
	# of the prior pool error, current rounding error and this residual's rounding.
	return remaining.subtract(delta) if branch == QuantityErrorBounds.Sign.ABOVE else remaining.add(delta)
