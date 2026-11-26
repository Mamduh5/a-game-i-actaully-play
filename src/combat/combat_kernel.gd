class_name CombatKernel
extends RefCounted
## Run-owned combat admission. All waves at one due instant publish together.

enum Result { IDLE, WAITING, CLOSED, INTERRUPTED, YIELDED, STORAGE_WAIT }
enum Terminal { ACTIVE, VICTORY, DEFEAT }
enum BarrierEnd { EXPIRED, REPLACED, CLAMPED, DECAYED, REMOVED }
enum BarrierAdjustment { CAP, DECAY, REMOVE }
enum ActivationOutcome { PAID, LETHAL, REJECTED, SUPPRESSED }

class LayerReceipt:
	var id: StringName
	var generation: int
	var absorbed: Quantity
	var hostile_depletion: bool

class EndedBarrier:
	var target: StringName
	var life: int
	var id: StringName
	var generation: int
	var reason: BarrierEnd
	var remaining: Quantity

class BarrierChange:
	var removed: Quantity
	var remaining: Quantity
	var ended: EndedBarrier

class ComponentReceipt:
	var kind: CombatAction.Damage
	var incoming: Quantity
	var adjustment: Quantity
	var hp_removed: Quantity
	var hostile_hp_removed: Quantity
	var overkill: Quantity
	var barriers: Array[LayerReceipt] = []

class RecoveryReceipt:
	var id: StringName
	var recipient: StringName
	var life: int
	var eligible_hp_removed: Quantity
	var offered: Quantity
	var restored: Quantity
	var eligible_excess: QuantityLayerLedger.Pool
	var discarded: Quantity

class ActivationReceipt:
	var origin: CombatOrigin
	var source: StringName
	var life: int
	var outcome: ActivationOutcome
	var hp_paid := Quantity.from_count(0)
	var death_statuses: Dictionary[StringName, int] = {}

class Hit:
	var origin: CombatOrigin
	var source: StringName
	var source_life: int
	var family: StringName
	var target: StringName
	var target_life: int
	var shape: int
	var accepted: bool
	var hostile: bool
	var eliminated: bool
	var wave: int
	var event: int
	var parent: int
	var reaction: StringName
	var status_consumed: bool
	var displacement: RealmGeometry.Displacement
	var hp_restored: Quantity
	var damage_recovery: Array[RecoveryReceipt] = []
	var granted_barrier: StringName
	var before_statuses: Dictionary[StringName, int] = {}
	var death_statuses: Dictionary[StringName, int] = {}
	var components: Array[ComponentReceipt] = []

	func dealt_hostile_damage() -> bool:
		if not accepted or not hostile:
			return false
		for component: ComponentReceipt in components:
			if component.hostile_hp_removed.sign_value > 0:
				return true
			for barrier: LayerReceipt in component.barriers:
				if barrier.absorbed.sign_value > 0:
					return true
		return false

class WaveResult:
	var result: Result
	var due: CombatInstant
	var hits: Array[Hit] = []
	var eliminations: Array[Hit] = []
	var ended_barriers: Array[EndedBarrier] = []
	var activations: Array[ActivationReceipt] = []
	var fault: StringName
	var terminal: Terminal
	var waves: int
	var fault_wave: int

class Commitment:
	var action: CombatAction
	var realm: StringName
	var parts: Dictionary[int, bool] = {}
	var payment_pending: bool

class Impact:
	var action: CombatAction
	var origin: CombatOrigin
	var root_occurrence: String
	var target: StringName
	var target_life: int
	var target_visit: int
	var shape: int
	var hostile: bool
	var activation: String
	var parent: int
	var reaction: StringName
	var inherited_statuses: Dictionary[StringName, int] = {}
	var uses_inherited_statuses: bool
	var ancestry: Ancestry

class Ancestry:
	var key: String
	var wave_state: String
	var previous: Ancestry

class Posting:
	var impact: Impact
	var hit: Hit

class BarrierCredit:
	var first_hit: Hit
	var rule: CombatAction.BarrierConversion
	var hp := Quantity.from_count(0)

class ReactionClaim:
	var rule: CombatFollowUp
	var posting: Posting
	var actor: CombatantState
	var target: CombatantState
	var shape: int

class Group:
	var root: CombatRootQueue.Wave
	var pending: Array[Impact] = []
	var actors: Dictionary[StringName, CombatantState]
	var touched: Dictionary[StringName, bool] = {}
	var original_images: Dictionary[StringName, Array] = {}
	var displaced_poses: Dictionary[StringName, Dictionary] = {}
	var geometry: Dictionary[StringName, RealmGeometry] = {}
	var revisions: Dictionary[StringName, int] = {}
	var activation_outcomes: Dictionary[String, ActivationOutcome] = {}
	var receipt: WaveResult

var _actors: Dictionary[StringName, CombatantState] = {}
var _actions: Dictionary[String, Commitment] = {}
var _hp_activations: Dictionary[String, Commitment] = {}
var _latest_activation: Dictionary[String, int] = {}
var _impacts: Dictionary[String, Impact] = {}
var _queue := CombatRootQueue.new()
var _closed: CombatInstant
var _fault: StringName
var _fault_wave: int
var _group: Group
var _geometry: Dictionary[StringName, RealmGeometry] = {}
var _blocker_masks: Dictionary[StringName, int] = {}
var _creator: StringName
var _eligible: Array[StringName] = []
var _terminal: Terminal
var _physical_mitigation := Quantity.from_count(100)
var _magical_mitigation := Quantity.from_count(100)


func add_actor(actor: CombatantState) -> bool:
	if not _accepting() or actor == null or not actor.is_valid() or _actors.has(actor.id):
		return false
	_actors[actor.id] = actor.copy()
	return true


func actor_snapshot(id: StringName) -> CombatantState:
	var actor: CombatantState = _actors.get(id)
	return actor.copy() if actor != null else null


## Absolute HP changes at the closed run boundary. No hit or recovery is emitted.
func change_max_hp(id: StringName, life: int, maximum: Quantity) -> bool:
	var actor: CombatantState = _actors.get(id)
	return _accepting() and actor != null and actor.life == life and actor.change_max_hp(maximum)


## Loss of input control fences new commitments by this seat and its summons.
## Already committed effects still follow their original continuation rule.
func set_player_control(id: StringName, life: int, enabled: bool) -> bool:
	var actor: CombatantState = _actors.get(id)
	if not _accepting() or not _is_player_life(actor, life):
		return false
	actor.accepts_new_actions = enabled
	return true


func revive_player(id: StringName, life: int, now: CombatInstant,
		hp_fraction: Quantity, protection_ticks: int) -> bool:
	var actor: CombatantState = _actors.get(id)
	if (not _accepting() or not _is_player_life(actor, life) or actor.is_alive() or life == Quantity.INT_MAX
			or actor.max_hp == null or now == null or hp_fraction == null or hp_fraction.sign_value <= 0
			or hp_fraction.compare(Quantity.from_count(1)) > 0 or protection_ticks <= 0):
		return false
	if _closed != null and _closed.order_against(now) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
		return false
	var protection := now.after_ticks(protection_ticks)
	var restored := actor.max_hp.multiply(hp_fraction)
	if protection == null or restored == null or restored.sign_value <= 0:
		return false
	actor.life += 1
	actor.hp = QuantityLayerLedger.Pool.new(restored, QuantityErrorBounds.new())
	actor.revival_protected_until = protection
	actor.end_rates(CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL)
	return true


## Restore an authored enemy life at a closed boundary. Work already in
## flight keeps the old activation and can never hit this new life by replay.
func reanimate_spawn(id: StringName, life: int, now: CombatInstant, fraction: Quantity) -> bool:
	var actor: CombatantState = _actors.get(id)
	if (not _accepting() or actor == null or actor.provenance != CombatOrigin.Provenance.SPAWN
			or actor.life != life or actor.is_alive() or life == Quantity.INT_MAX or actor.max_hp == null
			or _closed == null or _closed.order_against(now) != RealmCircleTime.Order.SAME
			or fraction == null or fraction.sign_value <= 0 or fraction.compare(Quantity.from_count(1)) > 0):
		return false
	var restored := actor.max_hp.multiply(fraction)
	if restored == null or restored.sign_value <= 0:
		return false
	actor.life += 1
	actor.hp = QuantityLayerLedger.Pool.new(restored, QuantityErrorBounds.new())
	actor.statuses.clear()
	actor.barriers.clear()
	actor.end_rates(CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL)
	return true


## Move the physical player and its unchanged life between realized realms.
## Previously admitted contacts still refer to the old visit.
func transfer_player(id: StringName, life: int, from: RealmGeometry, destination: RealmGeometry,
		at: RealmSweep.Point) -> bool:
	var actor: CombatantState = _actors.get(id)
	if (not _accepting() or not _is_player_life(actor, life) or not actor.is_alive()
			or actor.realm_visit == Quantity.INT_MAX or from == null or destination == null or at == null
			or actor.realm != from.realm_id or from == destination or _geometry.get(from.realm_id) != from
			or _geometry.get(destination.realm_id) != destination):
		return false
	var radius := from.circle_radius(id, 0)
	var category := from.circle_category(id, 0)
	if radius <= 0.0 or category <= 0:
		return false
	var clearance := destination.certify_circle_snapshot(destination.realm_id, at, radius,
		_blocker_masks[destination.realm_id])
	if clearance == null or not clearance.contacts.is_empty() or not clearance.unresolved.is_empty():
		return false
	var departure := from.fork()
	var arrival := destination.fork()
	if not departure.remove_mutable(id, 0) or not arrival.add_circle(id, 0, at, radius, category):
		return false
	from.adopt(departure)
	destination.adopt(arrival)
	actor.realm = destination.realm_id
	actor.realm_visit += 1
	return true


static func _is_player_life(actor: CombatantState, life: int) -> bool:
	return (actor != null and actor.life == life and actor.provenance == CombatOrigin.Provenance.SEAT
		and actor.controller.is_empty())


## Called by the run at the closed boundary when the authored change is due.
func adjust_barrier(id: StringName, life: int, layer_id: StringName, generation: int,
		kind: BarrierAdjustment, amount: Quantity = null) -> BarrierChange:
	var actor: CombatantState = _actors.get(id)
	if not _accepting() or actor == null or actor.life != life or kind not in BarrierAdjustment.values():
		return null
	if (kind == BarrierAdjustment.REMOVE and amount != null
			or kind != BarrierAdjustment.REMOVE and (amount == null or amount.sign_value < 0)):
		return null
	for layer: CombatantState.Barrier in actor.barriers:
		if layer.id != layer_id or layer.generation != generation:
			continue
		var after: QuantityLayerLedger.Pool
		var reason := BarrierEnd.REMOVED
		match kind:
			BarrierAdjustment.CAP:
				reason = BarrierEnd.CLAMPED
				after = CombatantState.cap_pool(layer.pool, amount)
			BarrierAdjustment.DECAY:
				reason = BarrierEnd.DECAYED
				var debit := QuantityThresholdDebit.resolve(layer.pool.amount, layer.pool.error,
					QuantityFraction.from_amount(amount), amount)
				if debit != null:
					after = QuantityLayerLedger.Pool.new(debit.remaining, debit.error)
			BarrierAdjustment.REMOVE:
				after = QuantityLayerLedger.Pool.new(Quantity.from_count(0), QuantityErrorBounds.new())
		if after == null:
			return null
		var change := BarrierChange.new()
		change.removed = layer.pool.amount.subtract(after.amount)
		if change.removed == null:
			return null
		change.remaining = after.amount
		if change.remaining.sign_value == 0:
			change.ended = _barrier_end(actor, layer, reason)
			actor.barriers.erase(layer)
			actor.end_rates(layer.mask)
		else:
			layer.pool = after
		return change
	return null


func set_defense(id: StringName, life: int, kind: CombatAction.Damage, defense: CombatantState.Defense) -> bool:
	var actor: CombatantState = _actors.get(id)
	if (not _accepting() or actor == null or actor.life != life or defense == null or not defense.is_valid()):
		return false
	match kind:
		CombatAction.Damage.PHYSICAL: actor.physical = defense.copy()
		CombatAction.Damage.MAGICAL: actor.magical = defense.copy()
		_: return false
	return true


func attach_geometry(geometry: RealmGeometry, blocker_mask: int) -> bool:
	if not _accepting() or geometry == null or geometry.realm_id.is_empty() or blocker_mask <= 0:
		return false
	_geometry[geometry.realm_id] = geometry
	_blocker_masks[geometry.realm_id] = blocker_mask
	return true


## The run owns the roster and current survival eligibility (including grace).
func configure_terminal(creator: StringName, eligible: Array[StringName]) -> bool:
	if not _accepting() or not _actors.has(creator) or creator in eligible:
		return false
	for id: StringName in eligible:
		if not _actors.has(id):
			return false
	_creator = creator
	_eligible = eligible.duplicate()
	return true


## The roster owner can close an ordinary wipe after its causal group or idle
## grace boundary. An already decided Creator outcome keeps precedence.
func end_party_defeat() -> bool:
	if not _accepting():
		return false
	_terminal = Terminal.DEFEAT
	_retire_combat_work()
	return true


## Ordinary costs settle now. An HP-priced activation returns a provisional
## key and settles at its own instant, before the group's contacts.
func commit(action: CombatAction) -> String:
	var source := _activation_source(action)
	if source == null:
		return ""
	var origin := action.origin
	var held := _hold(action, source.realm)
	var key := origin.occurrence_key()
	if action.hp_cost != null:
		if _queue.admit(origin, origin.committed_at) != CombatRootQueue.Result.ACCEPTED:
			return ""
		held.payment_pending = true
		_hp_activations[key] = held
	elif not source.pay_activation(action):
		return ""
	_actions[key] = held
	_latest_activation[origin.activation_stream_key()] = origin.activation
	return key


## Some authored deliveries pay only for a particular eligible target. Stage
## the payment, then publish it only when that one contact is admitted.
func commit_for_target(action: CombatAction, realm: StringName, start_tick: int, contact: RealmGeometry.Contact,
		target_life: int, hostile: bool) -> CombatRootQueue.Result:
	var source := _activation_source(action)
	if source == null or action.hp_cost != null or source.realm != realm or contact == null:
		return CombatRootQueue.Result.INVALID
	var target: CombatantState = _actors.get(contact.entity)
	if target == null or not target.is_alive() or target.life != target_life or target.realm != realm:
		return CombatRootQueue.Result.INVALID
	var draft := source.copy()
	if not draft.pay_activation(action):
		return CombatRootQueue.Result.INVALID
	var origin := action.origin
	var key := origin.occurrence_key()
	_actions[key] = _hold(action, realm)
	var admitted := admit_contact(key, 1, realm, start_tick, contact, target_life, hostile)
	_actions.erase(key)
	if admitted == CombatRootQueue.Result.ACCEPTED:
		_actors[draft.id] = draft
		_latest_activation[origin.activation_stream_key()] = origin.activation
	return admitted


func _activation_source(action: CombatAction) -> CombatantState:
	if not _accepting() or action == null or not action.is_valid():
		return null
	var source: CombatantState = _actors.get(action.source)
	var controller := _controller(_actors, source) if source != null else null
	var origin := action.origin
	if (source == null or source.life != action.source_life or not source.is_alive()
			or controller == null or not controller.is_alive() or not controller.accepts_new_actions
			or source.owner != origin.owner or source.provenance != origin.provenance
			or (_closed != null and _closed.order_against(origin.committed_at) != RealmCircleTime.Order.BEFORE)
			or origin.activation <= int(_latest_activation.get(origin.activation_stream_key(), 0))):
		return null
	return source


static func _hold(action: CombatAction, realm: StringName) -> Commitment:
	var held := Commitment.new()
	held.action = action.copy()
	held.realm = realm
	return held


## The delivery owner retires its commitment when it can produce no further
## contacts. Already admitted impacts keep the frozen action.
func finish_delivery(key: String) -> bool:
	return _accepting() and _actions.erase(key)


func admit_contact(key: String, part: int, realm: StringName, start_tick: int, contact: RealmGeometry.Contact,
		target_life: int, hostile: bool) -> CombatRootQueue.Result:
	var held: Commitment = _actions.get(key)
	if (not _accepting() or held == null or part <= 0 or held.realm != realm
			or contact == null or contact.shape < 0):
		return CombatRootQueue.Result.INVALID
	var actor: CombatantState = _actors.get(contact.entity)
	if actor == null or actor.realm != realm or actor.life != target_life:
		return CombatRootQueue.Result.INVALID
	if held.parts.has(part):
		return CombatRootQueue.Result.REPEATED
	if held.action.continuation == CombatAction.Continuation.LIVE_CONTROLLER:
		var source: CombatantState = _actors.get(held.action.source)
		if source == null or source.life != held.action.source_life or not _live_controller(_actors, source):
			return CombatRootQueue.Result.INVALID
	var due := CombatInstant.at_contact(start_tick, contact.proof)
	if due != null and _closed != null and _closed.order_against(due) != RealmCircleTime.Order.BEFORE:
		return CombatRootQueue.Result.CLOSED_INSTANT
	if held.payment_pending and (due == null
			or due.order_against(held.action.origin.committed_at) != RealmCircleTime.Order.SAME):
		return CombatRootQueue.Result.INVALID
	var impact := Impact.new()
	impact.action = held.action
	impact.origin = held.action.origin.copy()
	impact.origin.delivery_part = part
	impact.root_occurrence = impact.origin.occurrence_key()
	impact.target = actor.id
	impact.target_life = target_life
	impact.target_visit = actor.realm_visit
	impact.shape = contact.shape
	impact.hostile = hostile
	if held.payment_pending:
		impact.activation = key
	var result := _queue.admit(impact.origin, due)
	if result == CombatRootQueue.Result.ACCEPTED:
		held.parts[part] = true
		_impacts[impact.origin.occurrence_key()] = impact
	return result


func pending_count() -> int:
	return _queue.pending_count()


## The fixed-step owner can drain older sub-tick impacts before it admits
## actions at the next integer boundary.
func next_due() -> CombatInstant:
	if _group != null:
		return _group.root.due
	var wave := _queue.earliest_wave()
	return wave.due if wave != null else null


## Close an idle survival deadline after the run has admitted all work through it.
## Impacts at the deadline get their full causal group before expiry.
func advance_survival(through: CombatInstant) -> WaveResult:
	if not _fault.is_empty():
		return _result(Result.INTERRUPTED)
	if (not _accepting() or through == null
			or (_closed != null and _closed.order_against(through) != RealmCircleTime.Order.BEFORE)):
		return _result(Result.WAITING)
	if pending_count() > 0:
		var next := _queue.earliest_wave()
		if next == null:
			return _interrupt(&"due_order")
		if next.due.order_against(through) != RealmCircleTime.Order.AFTER:
			return _result(Result.WAITING)
	var draft := Group.new()
	draft.actors = _actors.duplicate()
	draft.receipt = _result(Result.CLOSED)
	draft.receipt.due = through
	if not _expire_barriers(draft, true):
		return _interrupt(&"barrier_time")
	_actors = draft.actors
	_closed = through
	return draft.receipt


## A native earning owner can park a draft between waves or before publication.
func resolve_next(through: CombatInstant, wave_budget: int = 8, authority: RunAuthority = null) -> WaveResult:
	if not _fault.is_empty():
		return _result(Result.INTERRUPTED)
	if _group == null:
		if authority != null and not authority.can_open_earning_group():
			return _result(Result.STORAGE_WAIT)
		var unavailable := _open_group(through)
		if unavailable != null:
			return unavailable
	for step: int in maxi(1, wave_budget):
		if authority != null and not authority.can_open_earning_group():
			return _result(Result.STORAGE_WAIT)
		# The previous slice can finish its last wave and park before publishing.
		if _group.pending.is_empty() and _group.receipt.waves > 0:
			return _publish_group()
		var failure := _resolve_wave(_group)
		if not failure.is_empty():
			return _interrupt(failure)
		if _group.pending.is_empty():
			if authority != null and not authority.can_open_earning_group():
				return _result(Result.STORAGE_WAIT)
			return _publish_group()
	return _result(Result.YIELDED)


func _open_group(through: CombatInstant) -> WaveResult:
	if pending_count() == 0:
		return _result(Result.IDLE)
	var wave := _queue.earliest_wave()
	if wave == null:
		return _interrupt(&"due_order")
	match wave.due.order_against(through):
		RealmCircleTime.Order.AFTER: return _result(Result.WAITING)
		RealmCircleTime.Order.UNRESOLVED: return _interrupt(&"frontier_order")
	_group = Group.new()
	_group.root = wave
	_group.actors = _actors.duplicate()
	_group.receipt = _result(Result.CLOSED)
	_group.receipt.due = wave.due
	if not _expire_barriers(_group, false):
		return _interrupt(&"barrier_time")
	for realm: StringName in _geometry:
		_group.revisions[realm] = _geometry[realm].revision
	var offers: Array[CombatOrigin] = []
	for origin: CombatOrigin in wave.origins:
		if _hp_activations.has(origin.occurrence_key()):
			offers.append(origin)
	# Each payment root is due at its commitment, so only priority and
	# canonical provenance can distinguish competing claims at this instant.
	offers.sort_custom(func(left: CombatOrigin, right: CombatOrigin) -> bool:
		return left.priority > right.priority if left.priority != right.priority else left.canonical_before(right))
	for offer: CombatOrigin in offers:
		var key := offer.occurrence_key()
		var paid := _settle_hp_activation(_group, _hp_activations[key])
		if paid == null:
			return _interrupt(&"hp_payment")
		_group.activation_outcomes[key] = paid.outcome
		_group.receipt.activations.append(paid)
	for origin: CombatOrigin in wave.origins:
		var impact: Impact = _impacts.get(origin.occurrence_key())
		if impact == null or (not impact.activation.is_empty()
				and _group.activation_outcomes[impact.activation] != ActivationOutcome.PAID):
			continue
		if impact.action.continuation == CombatAction.Continuation.LIVE_CONTROLLER:
			var source: CombatantState = _group.actors.get(impact.action.source)
			if source == null or source.life != impact.action.source_life or not _live_controller(_group.actors, source):
				continue
		_group.pending.append(impact)
	return null


static func _live_controller(actors: Dictionary[StringName, CombatantState], source: CombatantState) -> bool:
	var controller := _controller(actors, source)
	return source.is_alive() and controller != null and controller.is_alive()


static func _controller(actors: Dictionary[StringName, CombatantState], source: CombatantState) -> CombatantState:
	if source.controller.is_empty():
		return source
	var controller: CombatantState = actors.get(source.controller)
	if (controller == null or not controller.controller.is_empty()
			or controller.owner != source.owner or controller.provenance != source.provenance):
		return null
	return controller


static func _settle_hp_activation(group: Group, held: Commitment) -> ActivationReceipt:
	var action := held.action
	var receipt := ActivationReceipt.new()
	receipt.origin = action.origin.copy()
	receipt.source = action.source
	receipt.life = action.source_life
	receipt.outcome = ActivationOutcome.REJECTED
	var actor: CombatantState = group.actors.get(action.source)
	if actor == null or actor.life != action.source_life or not _live_controller(group.actors, actor):
		return receipt
	var draft := actor.copy()
	if not draft.pay_activation(action):
		return receipt
	var cost := action.hp_cost
	var debit := QuantityThresholdDebit.resolve(draft.hp.amount, draft.hp.error, QuantityFraction.from_amount(cost), cost)
	if debit == null:
		return null
	var lethal := debit.remaining.sign_value == 0
	if lethal and action.automatic_hp_cost and actor.revival_protected_until != null:
		var protection := group.receipt.due.order_against(actor.revival_protected_until)
		if protection == RealmCircleTime.Order.UNRESOLVED:
			return null
		if protection == RealmCircleTime.Order.BEFORE:
			receipt.outcome = ActivationOutcome.SUPPRESSED
			return receipt
	group.actors[actor.id] = draft
	group.touched[actor.id] = true
	draft.hp = QuantityLayerLedger.Pool.new(debit.remaining, debit.error)
	receipt.hp_paid = debit.debit
	receipt.outcome = ActivationOutcome.LETHAL if lethal else ActivationOutcome.PAID
	if lethal:
		receipt.death_statuses = draft.statuses.duplicate()
		draft.end_rates(CombatAction.Damage.PHYSICAL | CombatAction.Damage.MAGICAL)
	return receipt


func _resolve_wave(group: Group) -> StringName:
	var per_target: Dictionary[StringName, Array] = {}
	for impact: Impact in group.pending:
		if not per_target.has(impact.target):
			per_target[impact.target] = []
		if not _insert_claim(per_target[impact.target], impact):
			return &"claim_order"
	var postings: Array[Posting] = []
	group.receipt.waves += 1
	var targets := per_target.keys()
	targets.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for id: StringName in targets:
		var before := group.actors[id]
		var after := before.copy()
		for impact: Impact in per_target[id]:
			var hit := _draft_hit(impact, before, after, group.receipt.due)
			if hit == null:
				return &"numeric_posting"
			hit.wave = group.receipt.waves
			hit.event = group.receipt.hits.size() + 1
			group.receipt.hits.append(hit)
			if hit.accepted:
				var posting := Posting.new()
				posting.hit = hit
				posting.impact = impact
				postings.append(posting)
		group.actors[id] = after
		group.touched[id] = true
	_apply_statuses(group, postings)
	if not _displace(group, postings):
		return &"displacement"
	if not _recover(group, postings):
		return &"recovery"
	for posting: Posting in postings:
		if posting.hit.eliminated:
			posting.hit.death_statuses = group.actors[posting.hit.target].statuses.duplicate()
			group.receipt.eliminations.append(posting.hit)
			if not _earn_elimination_barrier(group, posting.hit):
				return &"elimination_barrier"
	group.pending.clear()
	return _queue_descendants(group, postings)


func _publish_group() -> WaveResult:
	var group := _group
	for realm: StringName in group.revisions:
		if _geometry[realm].revision != group.revisions[realm]:
			return _interrupt(&"geometry_changed")
	if not _expire_barriers(group, true):
		return _interrupt(&"barrier_time")
	if not _queue.close(group.root):
		return _interrupt(&"stale_wave")
	for realm: StringName in group.geometry:
		_geometry[realm].adopt(group.geometry[realm])
	_actors = group.actors
	for origin: CombatOrigin in group.root.origins:
		_impacts.erase(origin.occurrence_key())
	for key: String in group.activation_outcomes:
		var held := _hp_activations[key]
		if group.activation_outcomes[key] == ActivationOutcome.PAID:
			held.payment_pending = false
		else:
			_actions.erase(key)
		_hp_activations.erase(key)
	_closed = group.root.due
	_group = null
	_terminal = _evaluate_terminal()
	group.receipt.terminal = _terminal
	if _terminal != Terminal.ACTIVE:
		_retire_combat_work()
	return group.receipt


func _retire_combat_work() -> void:
	_queue = CombatRootQueue.new()
	_impacts.clear()
	_actions.clear()
	_hp_activations.clear()


static func _expire_barriers(group: Group, at_deadline: bool) -> bool:
	var ids := group.actors.keys()
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for id: StringName in ids:
		var actor := group.actors[id]
		# Walk the original list so copy-on-write and removal cannot skip a layer.
		for barrier: CombatantState.Barrier in actor.barriers.duplicate():
			if barrier.expires == null:
				continue
			var order := barrier.expires.order_against(group.receipt.due)
			if order == RealmCircleTime.Order.UNRESOLVED:
				return false
			if order == RealmCircleTime.Order.BEFORE or (at_deadline and order == RealmCircleTime.Order.SAME):
				var draft := _edit_actor(group, id)
				for layer: CombatantState.Barrier in draft.barriers:
					if layer.id == barrier.id:
						group.receipt.ended_barriers.append(_barrier_end(draft, layer, BarrierEnd.EXPIRED))
						draft.barriers.erase(layer)
						draft.end_rates(layer.mask)
						break
	return true


func _evaluate_terminal() -> Terminal:
	if _creator.is_empty():
		return Terminal.ACTIVE
	if not _actors[_creator].is_alive():
		return Terminal.VICTORY
	for id: StringName in _eligible:
		if _actors[id].is_alive():
			return Terminal.ACTIVE
	return Terminal.DEFEAT


func _accepting() -> bool:
	return _fault.is_empty() and _group == null and _terminal == Terminal.ACTIVE


static func _apply_statuses(group: Group, postings: Array[Posting]) -> void:
	# Make all finite claims against the captured wave before adding statuses.
	for posting: Posting in postings:
		var hit := posting.hit
		var status := posting.impact.action.consume_status
		var target := group.actors[hit.target]
		if status.is_empty() or not hit.before_statuses.has(status) or not target.statuses.has(status):
			continue
		if target.statuses[status] > 1:
			target.statuses[status] -= 1
		else:
			target.statuses.erase(status)
		hit.status_consumed = true
	for posting: Posting in postings:
		var action := posting.impact.action
		var target := group.actors[posting.hit.target]
		if (target.is_alive() and not action.add_status.is_empty()
				and (action.consume_status.is_empty() or posting.hit.status_consumed)):
			target.statuses[action.add_status] = maxi(int(target.statuses.get(action.add_status, 0)), action.status_units)


func _displace(group: Group, postings: Array[Posting]) -> bool:
	for posting: Posting in postings:
		var offset := posting.impact.action.displacement
		var hit := posting.hit
		var target := group.actors[hit.target]
		if offset == null or not target.is_alive():
			continue
		var realm := target.realm
		if not group.geometry.has(realm):
			if not _geometry.has(realm) or _geometry[realm].revision != group.revisions[realm]:
				return false
			group.geometry[realm] = _geometry[realm].fork()
		var geometry := group.geometry[realm]
		var start := geometry.circle_center(target.id, hit.shape)
		if start == null:
			return false
		var finish := RealmSweep.Point.new(start.x + offset.x, start.y + offset.y)
		hit.displacement = geometry.displace_circle(target.id, hit.shape, finish, _blocker_masks[realm])
		if hit.displacement == null:
			return false
		var settled := hit.displacement.finish
		if settled.x != start.x or settled.y != start.y:
			var poses: Dictionary = group.displaced_poses.get_or_add(target.id, {})
			poses[hit.shape] = [settled.x, settled.y]
	return true


static func _recover(group: Group, postings: Array[Posting]) -> bool:
	var converted: Dictionary[String, BarrierCredit] = {}
	for posting: Posting in postings:
		var action := posting.impact.action
		var source: CombatantState = group.actors.get(posting.hit.source)
		if source == null or source.life != posting.hit.source_life:
			continue
		if not action.damage_recovery.is_empty():
			var owner := _controller(group.actors, source)
			if owner != null and owner.is_alive() and owner.max_hp != null:
				if not _recover_from_damage(_edit_actor(group, owner.id), posting):
					return false
		if not source.is_alive():
			continue
		if action.restore_source != null:
			posting.hit.hp_restored = Quantity.from_count(0)
			if source.max_hp != null:
				var flat := action.restore_source
				var actor := _edit_actor(group, source.id)
				var direct := QuantityLayerLedger.recovery(QuantityFraction.from_amount(flat), flat, actor.hp, actor.max_hp, false)
				if direct == null:
					return false
				actor.hp = direct.hp
				posting.hit.hp_restored = direct.hp_restored
		if action.barrier_for_source != null:
			if not _grant_barrier(group, _edit_actor(group, source.id), posting.hit, action.barrier_for_source):
				return false
		if action.converted_barrier != null:
			var key := action.origin.occurrence_key()
			var credit: BarrierCredit = converted.get(key)
			if credit == null:
				credit = BarrierCredit.new()
				credit.first_hit = posting.hit
				credit.rule = action.converted_barrier
				converted[key] = credit
			for component: ComponentReceipt in posting.hit.components:
				credit.hp = credit.hp.add(component.hostile_hp_removed)
				if credit.hp == null:
					return false
	for credit: BarrierCredit in converted.values():
		if credit.hp.sign_value == 0:
			continue
		var grant := credit.rule.grant.copy()
		var capacity := credit.hp.multiply(credit.rule.rate)
		if capacity == null:
			return false
		if capacity.compare(grant.capacity) < 0:
			grant.capacity = capacity
		if not _grant_barrier(group, _edit_actor(group, credit.first_hit.source), credit.first_hit, grant):
			return false
	return true


static func _earn_elimination_barrier(group: Group, hit: Hit) -> bool:
	if not hit.hostile or hit.origin.provenance != CombatOrigin.Provenance.SEAT:
		return true
	var source: CombatantState = group.actors.get(hit.source)
	var owner := _controller(group.actors, source) if source != null else null
	if owner == null or owner.owner != hit.origin.owner or owner.barrier_on_elimination == null:
		return true
	return _grant_barrier(group, _edit_actor(group, owner.id), hit, owner.barrier_on_elimination)


static func _recover_from_damage(actor: CombatantState, posting: Posting) -> bool:
	var hit := posting.hit
	var action := posting.impact.action
	var eligible := Quantity.from_count(0)
	for component: ComponentReceipt in hit.components:
		eligible = eligible.add(component.hostile_hp_removed)
		if eligible == null:
			return false
	for rule: CombatAction.DamageRecovery in action.damage_recovery:
		var raw := QuantityFormula.source_limited_recovery(eligible, rule.rate, rule.limit, rule.amplification)
		if raw == null:
			return false
		var nominal := Quantity.quantize_ratio(raw.numerator, raw.divisor)
		var draft := QuantityLayerLedger.recovery(raw, nominal, actor.hp, actor.max_hp, rule.admits_excess)
		if draft == null:
			return false
		actor.hp = draft.hp
		var receipt := RecoveryReceipt.new()
		receipt.id = rule.id
		receipt.recipient = actor.id
		receipt.life = actor.life
		receipt.eligible_hp_removed = eligible
		receipt.offered = draft.offered
		receipt.restored = draft.hp_restored
		receipt.eligible_excess = draft.eligible_excess
		receipt.discarded = draft.discarded
		hit.damage_recovery.append(receipt)
	return true


static func _grant_barrier(group: Group, actor: CombatantState, hit: Hit, grant: CombatAction.BarrierGrant) -> bool:
	var prior: CombatantState.Barrier
	for barrier: CombatantState.Barrier in actor.barriers:
		if barrier.id == grant.id:
			prior = barrier
			break
	var prior_pool := prior.pool if prior != null else null
	var prior_expiry := prior.expires if prior != null else null
	var layer := actor.grant_barrier(grant, group.receipt.due)
	if layer == null:
		return false
	if layer != prior:
		if prior != null:
			group.receipt.ended_barriers.append(_barrier_end(actor, prior, BarrierEnd.REPLACED))
		hit.granted_barrier = grant.id
	elif layer.pool != prior_pool or layer.expires != prior_expiry:
		hit.granted_barrier = grant.id
	return true


static func _barrier_end(actor: CombatantState, layer: CombatantState.Barrier, reason: BarrierEnd) -> EndedBarrier:
	var receipt := EndedBarrier.new()
	receipt.target = actor.id
	receipt.life = actor.life
	receipt.id = layer.id
	receipt.generation = layer.generation
	receipt.reason = reason
	receipt.remaining = layer.pool.amount
	return receipt


static func _edit_actor(group: Group, id: StringName) -> CombatantState:
	if not group.touched.has(id):
		group.actors[id] = group.actors[id].copy()
		group.touched[id] = true
	return group.actors[id]


func _queue_descendants(group: Group, postings: Array[Posting]) -> StringName:
	var claims: Array[ReactionClaim] = []
	for posting: Posting in postings:
		var source: CombatantState = group.actors.get(posting.hit.source)
		var target := group.actors[posting.hit.target]
		if source != null and (source.life != posting.hit.source_life or source.realm != target.realm):
			source = null
		if source != null:
			var attacker_failure := _gather_claims(group, claims, source, target, posting, false)
			if not attacker_failure.is_empty():
				return attacker_failure
		var failure := _gather_claims(group, claims, target, source, posting, true)
		if not failure.is_empty():
			return failure
	for claim: ReactionClaim in claims:
		var failure := _choose_descendant(group, claim)
		if not failure.is_empty():
			return failure
	return &"causal_cycle" if _has_repeated_continuation(group) else &""


func _gather_claims(group: Group, claims: Array[ReactionClaim], actor: CombatantState, counterpart: CombatantState,
		posting: Posting, defending: bool) -> StringName:
	for rule: CombatFollowUp in actor.follow_ups:
		if not _reaction_matches(rule, posting, actor.is_alive(), defending):
			continue
		var balance: Quantity = actor.resources.get(rule.resource)
		if rule.cost != null and (balance == null or balance.compare(rule.cost) < 0):
			continue
		var target: CombatantState = counterpart if rule.fresh_target.is_empty() else group.actors.get(rule.fresh_target)
		if target == null or not target.is_alive() or target.realm != actor.realm:
			continue
		var claim := ReactionClaim.new()
		claim.rule = rule
		claim.posting = posting
		claim.actor = actor
		claim.target = target
		claim.shape = posting.hit.shape if target.id == posting.hit.target else 0
		if not rule.fresh_target.is_empty():
			var shape := _fresh_shape(group, claim)
			if shape == -2:
				return &"reaction_geometry"
			if shape == -1:
				continue
			claim.shape = shape
		var index := claims.size()
		for earlier: int in claims.size():
			var existing := claims[earlier]
			if rule.resource.is_empty() or rule.resource != existing.rule.resource or actor.id != existing.actor.id:
				continue
			match _reaction_order(claim, existing):
				RealmCircleTime.Order.BEFORE: index = mini(index, earlier)
				RealmCircleTime.Order.UNRESOLVED: return &"reaction_order"
		claims.insert(index, claim)
	return &""


## A fresh recipient is chosen by the authored eligible target rule. Use the
## updated realm image to certify reach before charging it or admitting a hit.
func _fresh_shape(group: Group, claim: ReactionClaim) -> int:
	var realm := claim.actor.realm
	var geometry: RealmGeometry = group.geometry.get(realm, _geometry.get(realm))
	if geometry == null or _geometry[realm].revision != group.revisions[realm]:
		return -2
	var hit := claim.posting.hit
	var centered_on_impact := claim.rule.cause in [CombatFollowUp.Cause.KILL, CombatFollowUp.Cause.SOLID_IMPACT]
	var center_id := hit.target if centered_on_impact else claim.actor.id
	var center_shape := hit.shape if center_id == hit.target else 0
	var center := geometry.circle_center(center_id, center_shape)
	if center == null:
		return -2
	var reached := geometry.certify_circle_sweep(realm, center, center, claim.rule.reach, claim.rule.collision_mask, center_id)
	if reached == null:
		return -2
	for contact: RealmGeometry.Contact in reached.unresolved:
		if contact.entity == claim.target.id:
			return -2
	var first := -1
	for contact: RealmGeometry.Contact in reached.contacts:
		if contact.entity == claim.target.id and (first < 0 or contact.shape < first):
			first = contact.shape
	return first


static func _reaction_order(first: ReactionClaim, second: ReactionClaim) -> RealmCircleTime.Order:
	if first.rule.priority != second.rule.priority:
		return RealmCircleTime.Order.BEFORE if first.rule.priority > second.rule.priority else RealmCircleTime.Order.AFTER
	var origin := first.posting.hit.origin
	var other := second.posting.hit.origin
	var order := origin.committed_at.order_against(other.committed_at)
	if order != RealmCircleTime.Order.SAME:
		return order
	if origin.canonical_before(other):
		return RealmCircleTime.Order.BEFORE
	if other.canonical_before(origin):
		return RealmCircleTime.Order.AFTER
	if first.posting.hit.event != second.posting.hit.event:
		return RealmCircleTime.Order.BEFORE if first.posting.hit.event < second.posting.hit.event else RealmCircleTime.Order.AFTER
	return RealmCircleTime.Order.BEFORE if String(first.rule.id) < String(second.rule.id) else RealmCircleTime.Order.AFTER


static func _reaction_matches(rule: CombatFollowUp, posting: Posting, alive: bool, defending: bool) -> bool:
	if not defending:
		match rule.cause:
			CombatFollowUp.Cause.PAID_HIT: return alive
			CombatFollowUp.Cause.KILL: return posting.hit.eliminated
			CombatFollowUp.Cause.SOLID_IMPACT:
				return posting.hit.displacement != null and not posting.hit.displacement.stopped_by.is_empty()
		return false
	if rule.cause == CombatFollowUp.Cause.OWN_DEATH:
		return posting.hit.eliminated
	if not posting.impact.hostile:
		return false
	for component: ComponentReceipt in posting.hit.components:
		if (rule.cause in [CombatFollowUp.Cause.HOSTILE_HP, CombatFollowUp.Cause.HOSTILE_DAMAGE]
				and component.hostile_hp_removed.sign_value > 0):
			return true
		for barrier: LayerReceipt in component.barriers:
			if rule.cause == CombatFollowUp.Cause.HOSTILE_DAMAGE and barrier.absorbed.sign_value > 0:
				return true
			if rule.cause == CombatFollowUp.Cause.HOSTILE_LAYER and barrier.id == rule.layer and barrier.hostile_depletion:
				return true
	return false


static func _choose_descendant(group: Group, claim: ReactionClaim) -> StringName:
	var rule := claim.rule
	var balance: Quantity = group.actors[claim.actor.id].resources.get(rule.resource)
	if rule.cost != null and (balance == null or balance.compare(rule.cost) < 0):
		return &""
	var receipt := claim.posting.hit
	var cause := claim.posting.impact
	if rule.cost != null:
		var remainder := balance.subtract(rule.cost)
		if remainder == null:
			return &"reaction_payment"
		_edit_actor(group, claim.actor.id).resources[rule.resource] = remainder
	var action := CombatAction.new()
	action.source = claim.actor.id
	action.source_life = claim.actor.life
	action.family = rule.family
	action.origin = receipt.origin.copy()
	action.origin.owner = claim.actor.owner
	action.origin.provenance = claim.actor.provenance
	action.origin.priority = rule.priority
	action.components = [rule.component]
	action.restore_source = rule.restore_source
	action.damage_recovery = rule.damage_recovery
	action.consume_status = rule.consume_status
	var child := Impact.new()
	child.action = action
	child.origin = action.origin
	child.root_occurrence = cause.root_occurrence
	child.target = claim.target.id
	child.target_life = claim.target.life
	child.target_visit = claim.target.realm_visit
	child.shape = claim.shape
	child.hostile = cause.hostile
	child.parent = receipt.event
	child.reaction = rule.id
	child.ancestry = Ancestry.new()
	child.ancestry.previous = cause.ancestry
	if rule.inherit_parent_statuses and child.target == receipt.target:
		child.uses_inherited_statuses = true
		child.inherited_statuses = receipt.before_statuses.duplicate()
	child.ancestry.key = JSON.stringify([child.action.source, child.action.source_life, child.reaction,
		child.target, child.target_life, child.shape, child.hostile, child.root_occurrence,
		child.uses_inherited_statuses, child.inherited_statuses], "", true)
	group.pending.append(child)
	return &""


## Compare the next wave only after all its competing debits settle. A sibling
## can change a pool, a pose or the next wave even when this branch is free.
func _has_repeated_continuation(group: Group) -> bool:
	if group.pending.is_empty():
		return false
	var parents: Array[int] = []
	for impact: Impact in group.pending:
		parents.append(impact.parent)
	parents.sort()
	var frontier: Array[Array] = []
	for impact: Impact in group.pending:
		frontier.append([impact.ancestry.key, parents.bsearch(impact.parent)])
	var actors: Dictionary[StringName, Array] = {}
	for id: StringName in group.touched:
		if not group.original_images.has(id):
			group.original_images[id] = _life_image(_actors[id])
		var image := _life_image(group.actors[id])
		if image != group.original_images[id]:
			actors[id] = image
	var state := JSON.stringify([actors, group.displaced_poses, frontier], "", true, true)
	for impact: Impact in group.pending:
		var continuation := impact.ancestry
		continuation.wave_state = state
		var ancestor := continuation.previous
		while ancestor != null:
			if continuation.key == ancestor.key and state == ancestor.wave_state:
				return true
			ancestor = ancestor.previous
	return false


static func _life_image(actor: CombatantState) -> Array:
	var layers: Array[Array] = []
	for barrier: CombatantState.Barrier in actor.barriers:
		layers.append([barrier.id, barrier.mask, QuantityCodec.encode(barrier.pool.amount).hex_encode(),
			barrier.pool.error.snapshot().hex_encode()])
	var resources: Dictionary[StringName, String] = {}
	for id: StringName in actor.resources:
		resources[id] = QuantityCodec.encode(actor.resources[id]).hex_encode()
	return [actor.life, actor.realm, QuantityCodec.encode(actor.hp.amount).hex_encode(),
		actor.hp.error.snapshot().hex_encode(), layers, actor.statuses, resources, actor.rate_phases()]


static func _insert_claim(ordered: Array, impact: Impact) -> bool:
	# Validate every comparison on the particular finite claim. Different
	# targets neither exchange pools nor require a PR12 precedence.
	var index := ordered.size()
	for i: int in ordered.size():
		var existing: Impact = ordered[i]
		match impact.origin.claim_order(existing.origin):
			RealmCircleTime.Order.BEFORE: index = mini(index, i)
			RealmCircleTime.Order.UNRESOLVED: return false
			RealmCircleTime.Order.SAME:
				if (impact.parent < existing.parent or (impact.parent == existing.parent
						and String(impact.reaction) < String(existing.reaction))):
					index = mini(index, i)
	ordered.insert(index, impact)
	return true


func _draft_hit(impact: Impact, before: CombatantState, after: CombatantState, now: CombatInstant) -> Hit:
	var hit := Hit.new()
	hit.origin = impact.origin.copy()
	hit.family = impact.action.family
	hit.source = impact.action.source
	hit.source_life = impact.action.source_life
	hit.target = impact.target
	hit.target_life = impact.target_life
	hit.shape = impact.shape
	hit.hostile = impact.hostile
	hit.parent = impact.parent
	hit.reaction = impact.reaction
	if before.life != impact.target_life or before.realm_visit != impact.target_visit or not before.is_alive():
		return hit
	hit.before_statuses = impact.inherited_statuses.duplicate() if impact.uses_inherited_statuses else before.statuses.duplicate()
	hit.accepted = not before.prevents_hit
	if not hit.accepted:
		return hit
	if impact.hostile and before.revival_protected_until != null:
		match now.order_against(before.revival_protected_until):
			RealmCircleTime.Order.UNRESOLVED: return null
			RealmCircleTime.Order.BEFORE: return hit
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
			var insertion := eligible.size()
			if barrier.expires != null:
				for index: int in eligible.size():
					var previous := eligible[index].expires
					var order := barrier.expires.order_against(previous) if previous != null else RealmCircleTime.Order.BEFORE
					if order == RealmCircleTime.Order.UNRESOLVED:
						return null
					if order == RealmCircleTime.Order.BEFORE:
						insertion = index
						break
			eligible.insert(insertion, barrier)
			layers.insert(insertion, barrier.pool)
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
		receipt.generation = barrier.generation
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
	if _group != null:
		_fault_wave = _group.receipt.waves
		_group = null
	return _result(Result.INTERRUPTED)


func _result(kind: Result) -> WaveResult:
	var outcome := WaveResult.new()
	outcome.result = kind
	outcome.fault = _fault
	outcome.fault_wave = _fault_wave
	return outcome
