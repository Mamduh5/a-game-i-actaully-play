class_name QuantityPosting
extends RefCounted
## A pure posting draft over a certified represented amount. Only its owner can publish.

class LayerDebit:
	var absorbed: Quantity
	var remaining: Quantity
	var hostile_depletion: bool

class DamageDraft:
	var layers: Array[LayerDebit] = []
	var hp_remaining: Quantity
	var hp_removed: Quantity
	var overkill: Quantity
	var eligible_hostile_hp: Quantity
	var lethal: bool

class RecoveryDraft:
	var hp_restored: Quantity
	var hp_after: Quantity
	var eligible_excess: Quantity
	var discarded: Quantity


## Layer compatibility, ordering and origin arbitration are supplied by the group's owner.
static func damage(incoming: Quantity, ordered_layers: Array[Quantity], hp: Quantity,
		hostile: bool) -> DamageDraft:
	if not _valid(incoming) or not _valid(hp):
		return null
	var draft := DamageDraft.new()
	var remaining := incoming
	for capacity: Quantity in ordered_layers:
		if not _valid(capacity):
			return null
		var layer := LayerDebit.new()
		layer.absorbed = _minimum(remaining, capacity)
		layer.remaining = capacity.subtract(layer.absorbed)
		remaining = remaining.subtract(layer.absorbed)
		if layer.remaining == null or remaining == null:
			return null
		layer.hostile_depletion = hostile and layer.absorbed.sign_value > 0 and layer.remaining.sign_value == 0
		draft.layers.append(layer)
	draft.hp_removed = _minimum(remaining, hp)
	draft.hp_remaining = hp.subtract(draft.hp_removed)
	draft.overkill = remaining.subtract(draft.hp_removed)
	if draft.hp_remaining == null or draft.overkill == null:
		return null
	draft.eligible_hostile_hp = draft.hp_removed if hostile else Quantity.from_count(0)
	draft.lethal = hp.sign_value > 0 and draft.hp_remaining.sign_value == 0
	return draft


## The represented offer already includes the source limit and amplifier. Eligibility and any
## reserve conversion are decisions of the caller for this one source.
static func recovery(offered: Quantity, hp: Quantity, max_hp: Quantity,
		excess_allowed: bool) -> RecoveryDraft:
	if not _valid(offered) or not _valid(hp) or not _valid(max_hp) or hp.compare(max_hp) > 0:
		return null
	var draft := RecoveryDraft.new()
	var zero := Quantity.from_count(0)
	if hp.sign_value == 0:
		draft.hp_restored = zero
		draft.hp_after = hp
		draft.eligible_excess = zero
		draft.discarded = offered
		return draft
	var missing := max_hp.subtract(hp)
	if missing == null:
		return null
	draft.hp_restored = _minimum(offered, missing)
	draft.hp_after = hp.add(draft.hp_restored)
	var excess := offered.subtract(draft.hp_restored)
	if draft.hp_after == null or excess == null:
		return null
	draft.eligible_excess = excess if excess_allowed else zero
	draft.discarded = zero if excess_allowed else excess
	return draft


static func _valid(amount: Quantity) -> bool:
	return amount != null and amount.sign_value >= 0


static func _minimum(left: Quantity, right: Quantity) -> Quantity:
	return left if left.compare(right) <= 0 else right
