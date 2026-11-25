class_name CombatOrigin
extends RefCounted
## Stable provenance for a committed event and PR12 finite-claim precedence.

enum Provenance { SEAT, SPAWN }

var provenance: Provenance
var owner: StringName
var source_slot: int
var activation: int
var delivery_part: int
var priority: int
var committed_at: CombatInstant


func valid_for(due: CombatInstant) -> bool:
	if (provenance not in [Provenance.SEAT, Provenance.SPAWN] or owner.is_empty()
			or source_slot < 0 or activation < 1 or delivery_part < 0 or committed_at == null or due == null):
		return false
	var order := committed_at.order_against(due)
	return order in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]


func occurrence_key() -> String:
	return "%d/%d:%s/%d/%d/%d" % [provenance, owner.length(), owner, source_slot, activation, delivery_part]


func copy() -> CombatOrigin:
	var result := CombatOrigin.new()
	result.provenance = provenance
	result.owner = owner
	result.source_slot = source_slot
	result.activation = activation
	result.delivery_part = delivery_part
	result.priority = priority
	result.committed_at = committed_at
	return result


func canonical_before(other: CombatOrigin) -> bool:
	if provenance != other.provenance:
		return provenance < other.provenance
	if owner != other.owner:
		return String(owner) < String(other.owner)
	if source_slot != other.source_slot:
		return source_slot < other.source_slot
	if activation != other.activation:
		return activation < other.activation
	return delivery_part < other.delivery_part


## Higher authored priority, earlier commitment, then stable provenance.
func claim_order(other: CombatOrigin) -> RealmCircleTime.Order:
	if priority != other.priority:
		return RealmCircleTime.Order.BEFORE if priority > other.priority else RealmCircleTime.Order.AFTER
	var commitment := committed_at.order_against(other.committed_at)
	if commitment != RealmCircleTime.Order.SAME:
		return commitment
	if canonical_before(other):
		return RealmCircleTime.Order.BEFORE
	return RealmCircleTime.Order.AFTER if other.canonical_before(self) else RealmCircleTime.Order.SAME
