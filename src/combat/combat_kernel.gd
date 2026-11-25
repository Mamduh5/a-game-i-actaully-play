class_name CombatKernel
extends RefCounted
## Run-owned admission and stages 1–3 of a due wave. No caller reads drafted
## HP, barriers or receipts before every posting in the wave certifies.

enum Result { IDLE, WAITING, CLOSED, INTERRUPTED }

class LayerReceipt:
	var id: StringName
	var absorbed: Quantity
	var hostile_depletion: bool

class ComponentReceipt:
	var kind: CombatAction.Damage
	var incoming: Quantity
	var adjustment: Quantity
	var hp_removed: Quantity
	var hostile_hp_removed: Quantity
	var overkill: Quantity
	var barriers: Array[LayerReceipt] = []

class Hit:
	var origin: CombatOrigin
	var source: StringName
	var source_life: int
	var family: StringName
	var target: StringName
	var target_life: int
	var shape: int
	var accepted: bool
	var eliminated: bool
	var before_statuses: Dictionary[StringName, int] = {}
	var components: Array[ComponentReceipt] = []

class WaveResult:
	var result: Result
	var due: CombatInstant
	var hits: Array[Hit] = []
	var fault: StringName

class Commitment:
	var action: CombatAction
	var realm: StringName
	var parts: Dictionary[int, bool] = {}

class Impact:
	var action: CombatAction
	var origin: CombatOrigin
	var target: StringName
	var target_life: int
	var shape: int
	var hostile: bool

var _actors: Dictionary[StringName, CombatantState] = {}
var _actions: Dictionary[String, Commitment] = {}
var _latest_activation: Dictionary[String, int] = {}
var _impacts: Dictionary[String, Impact] = {}
var _queue := CombatRootQueue.new()
var _closed: CombatInstant
var _fault: StringName
var _physical_mitigation := Quantity.from_count(100)
var _magical_mitigation := Quantity.from_count(100)


func add_actor(actor: CombatantState) -> bool:
	if not _fault.is_empty() or actor == null or not actor.is_valid() or _actors.has(actor.id):
		return false
	_actors[actor.id] = actor.copy()
	return true


func actor_snapshot(id: StringName) -> CombatantState:
	var actor: CombatantState = _actors.get(id)
	return actor.copy() if actor != null else null


func set_defense(id: StringName, life: int, kind: CombatAction.Damage, defense: CombatantState.Defense) -> bool:
	var actor: CombatantState = _actors.get(id)
	if (not _fault.is_empty() or actor == null or actor.life != life or defense == null or not defense.is_valid()):
		return false
	match kind:
		CombatAction.Damage.PHYSICAL: actor.physical = defense.copy()
		CombatAction.Damage.MAGICAL: actor.magical = defense.copy()
		_: return false
	return true


## The caller validates authored placement and eligibility. A successful
## commitment consumes its activation costs once, including after a miss.
func commit(action: CombatAction) -> String:
	if not _fault.is_empty() or action == null or not action.is_valid():
		return ""
	var source: CombatantState = _actors.get(action.source)
	var origin := action.origin
	if (source == null or source.life != action.source_life or not source.is_alive()
			or source.owner != origin.owner or source.provenance != origin.provenance):
		return ""
	if _closed != null and _closed.order_against(origin.committed_at) != RealmCircleTime.Order.BEFORE:
		return ""
	var stream := origin.activation_stream_key()
	if origin.activation <= int(_latest_activation.get(stream, 0)) or not source.pay_activation(action):
		return ""
	var held := Commitment.new()
	held.action = action.copy()
	held.realm = source.realm
	var key := origin.occurrence_key()
	_actions[key] = held
	_latest_activation[stream] = origin.activation
	return key


## The delivery owner retires its commitment when it can produce no further
## contacts. Already admitted impacts keep the frozen action.
func finish_delivery(key: String) -> bool:
	return _fault.is_empty() and _actions.erase(key)


func admit_contact(key: String, part: int, realm: StringName, start_tick: int, contact: RealmGeometry.Contact,
		target_life: int, hostile: bool) -> CombatRootQueue.Result:
	var held: Commitment = _actions.get(key)
	if (not _fault.is_empty() or held == null or part <= 0 or held.realm != realm
			or contact == null or contact.shape < 0):
		return CombatRootQueue.Result.INVALID
	var actor: CombatantState = _actors.get(contact.entity)
	if actor == null or actor.realm != realm or actor.life != target_life:
		return CombatRootQueue.Result.INVALID
	if held.parts.has(part):
		return CombatRootQueue.Result.REPEATED
	var due := CombatInstant.at_contact(start_tick, contact.proof)
	var impact := Impact.new()
	impact.action = held.action
	impact.origin = held.action.origin.copy()
	impact.origin.delivery_part = part
	impact.target = actor.id
	impact.target_life = target_life
	impact.shape = contact.shape
	impact.hostile = hostile
	var result := _queue.admit(impact.origin, due)
	if result == CombatRootQueue.Result.ACCEPTED:
		held.parts[part] = true
		_impacts[impact.origin.occurrence_key()] = impact
	return result


func pending_count() -> int:
	return _queue.pending_count()


func resolve_next(through: CombatInstant) -> WaveResult:
	if not _fault.is_empty():
		return _result(Result.INTERRUPTED)
	if pending_count() == 0:
		return _result(Result.IDLE)
	var wave := _queue.earliest_wave()
	if wave == null:
		return _interrupt(&"due_order")
	match wave.due.order_against(through):
		RealmCircleTime.Order.AFTER: return _result(Result.WAITING)
		RealmCircleTime.Order.UNRESOLVED: return _interrupt(&"frontier_order")
	var per_target: Dictionary[StringName, Array] = {}
	for origin: CombatOrigin in wave.origins:
		var impact: Impact = _impacts[origin.occurrence_key()]
		if not per_target.has(impact.target):
			per_target[impact.target] = []
		if not _insert_claim(per_target[impact.target], impact):
			return _interrupt(&"claim_order")
	var drafted: Dictionary[StringName, CombatantState] = {}
	var receipts := _result(Result.CLOSED)
	receipts.due = wave.due
	var targets := per_target.keys()
	targets.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for id: StringName in targets:
		var before := _actors[id]
		var after := before.copy()
		for impact: Impact in per_target[id]:
			var hit := _draft_hit(impact, before, after)
			if hit == null:
				return _interrupt(&"numeric_posting")
			receipts.hits.append(hit)
		drafted[id] = after
	if not _queue.close(wave):
		return _interrupt(&"stale_wave")
	for id: StringName in drafted:
		_actors[id] = drafted[id]
	for origin: CombatOrigin in wave.origins:
		_impacts.erase(origin.occurrence_key())
	_closed = wave.due
	return receipts


static func _insert_claim(ordered: Array, impact: Impact) -> bool:
	# Validate every comparison on the particular finite claim. Different
	# targets neither exchange pools nor require a PR12 precedence.
	var index := ordered.size()
	for i: int in ordered.size():
		var existing: Impact = ordered[i]
		match impact.origin.claim_order(existing.origin):
			RealmCircleTime.Order.BEFORE: index = mini(index, i)
			RealmCircleTime.Order.UNRESOLVED: return false
	ordered.insert(index, impact)
	return true


func _draft_hit(impact: Impact, before: CombatantState, after: CombatantState) -> Hit:
	var hit := Hit.new()
	hit.origin = impact.origin.copy()
	hit.family = impact.action.family
	hit.source = impact.action.source
	hit.source_life = impact.action.source_life
	hit.target = impact.target
	hit.target_life = impact.target_life
	hit.shape = impact.shape
	if before.life != impact.target_life or not before.is_alive():
		return hit
	hit.before_statuses = before.statuses.duplicate()
	hit.accepted = not before.prevents_hit
	if not hit.accepted:
		return hit
	var lived_before_posting := after.is_alive()
	for component: CombatAction.Component in impact.action.components:
		var uses_physical := component.kind == CombatAction.Damage.PHYSICAL
		var defense := before.physical if uses_physical else before.magical
		var mitigation := _physical_mitigation if uses_physical else _magical_mitigation
		var raw := QuantityFormula.damage_component(component.base, component.categories, defense.rating, defense.reduction,
			component.penetration, mitigation, defense.vulnerability, defense.immune)
		if raw == null or raw.numerator.sign_value < 0:
			return null
		var posted := _post_component(after, component.kind, raw, impact.hostile)
		if posted == null:
			return null
		hit.components.append(posted)
	hit.eliminated = lived_before_posting and not after.is_alive()
	return hit


static func _post_component(actor: CombatantState, kind: CombatAction.Damage, raw: QuantityFraction,
		hostile: bool) -> ComponentReceipt:
	var nominal := actor.post_rate(kind, raw)
	if nominal == null:
		return null
	var eligible: Array[CombatantState.Barrier] = []
	var layers: Array[QuantityLayerLedger.Pool] = []
	for barrier: CombatantState.Barrier in actor.barriers:
		if barrier.mask & kind:
			eligible.append(barrier)
			layers.append(barrier.pool)
	var draft := QuantityLayerLedger.draft(raw, nominal, layers, actor.hp, hostile)
	if draft == null:
		return null
	var posted := ComponentReceipt.new()
	posted.kind = kind
	posted.incoming = draft.incoming
	posted.adjustment = draft.adjustment
	posted.hp_removed = draft.hp.spent
	posted.hostile_hp_removed = draft.eligible_hostile_hp
	posted.overkill = draft.overkill
	actor.hp = draft.hp.after
	var lost_mask := 0
	for index: int in eligible.size():
		var barrier := eligible[index]
		var debit := draft.layers[index]
		var receipt := LayerReceipt.new()
		receipt.id = barrier.id
		receipt.absorbed = debit.spent
		receipt.hostile_depletion = debit.hostile_depletion
		posted.barriers.append(receipt)
		barrier.pool = debit.after
		if barrier.pool.amount.sign_value == 0:
			lost_mask |= barrier.mask
			actor.barriers.erase(barrier)
	if not actor.is_alive():
		lost_mask = CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL
	if lost_mask != 0:
		actor.end_rates(lost_mask)
	return posted


func _interrupt(cause: StringName) -> WaveResult:
	_fault = cause
	return _result(Result.INTERRUPTED)


func _result(kind: Result) -> WaveResult:
	var outcome := WaveResult.new()
	outcome.result = kind
	outcome.fault = _fault
	return outcome
