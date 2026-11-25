class_name CombatKernel
extends RefCounted
## Run-owned combat admission. All waves at one due instant publish together.

enum Result { IDLE, WAITING, CLOSED, INTERRUPTED, YIELDED }
enum Terminal { ACTIVE, VICTORY, DEFEAT }

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
	var wave: int
	var event: int
	var parent: int
	var reaction: StringName
	var status_consumed: bool
	var displacement: RealmGeometry.Displacement
	var hp_restored: Quantity
	var granted_barrier: StringName
	var before_statuses: Dictionary[StringName, int] = {}
	var death_statuses: Dictionary[StringName, int] = {}
	var components: Array[ComponentReceipt] = []

class WaveResult:
	var result: Result
	var due: CombatInstant
	var hits: Array[Hit] = []
	var eliminations: Array[Hit] = []
	var fault: StringName
	var terminal: Terminal
	var waves: int
	var fault_wave: int

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
	var parent: int
	var reaction: StringName
	var inherited_statuses: Dictionary[StringName, int] = {}
	var uses_inherited_statuses: bool
	var ancestry: Ancestry

class Ancestry:
	var key: String
	var previous: Ancestry

class Posting:
	var impact: Impact
	var hit: Hit

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
	var geometry: Dictionary[StringName, RealmGeometry] = {}
	var revisions: Dictionary[StringName, int] = {}
	var receipt: WaveResult

var _actors: Dictionary[StringName, CombatantState] = {}
var _actions: Dictionary[String, Commitment] = {}
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


## The caller validates authored placement and eligibility. A successful
## commitment consumes its activation costs once, including after a miss.
func commit(action: CombatAction) -> String:
	if not _accepting() or action == null or not action.is_valid():
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


func resolve_next(through: CombatInstant, wave_budget: int = 8) -> WaveResult:
	if not _fault.is_empty():
		return _result(Result.INTERRUPTED)
	if _group == null:
		var unavailable := _open_group(through)
		if unavailable != null:
			return unavailable
	for step: int in maxi(1, wave_budget):
		var failure := _resolve_wave(_group)
		if not failure.is_empty():
			return _interrupt(failure)
		if _group.pending.is_empty():
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
	for realm: StringName in _geometry:
		_group.revisions[realm] = _geometry[realm].revision
	for origin: CombatOrigin in wave.origins:
		_group.pending.append(_impacts[origin.occurrence_key()])
	return null


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
			var hit := _draft_hit(impact, before, after)
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
	group.pending.clear()
	return _queue_descendants(group, postings)


func _publish_group() -> WaveResult:
	var group := _group
	for realm: StringName in group.revisions:
		if _geometry[realm].revision != group.revisions[realm]:
			return _interrupt(&"geometry_changed")
	if not _queue.close(group.root):
		return _interrupt(&"stale_wave")
	for realm: StringName in group.geometry:
		_geometry[realm].adopt(group.geometry[realm])
	_actors = group.actors
	for origin: CombatOrigin in group.root.origins:
		_impacts.erase(origin.occurrence_key())
	_closed = group.root.due
	_group = null
	_terminal = _evaluate_terminal()
	group.receipt.terminal = _terminal
	if _terminal != Terminal.ACTIVE:
		_queue = CombatRootQueue.new()
		_impacts.clear()
		_actions.clear()
	return group.receipt


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
	return true


static func _recover(group: Group, postings: Array[Posting]) -> bool:
	for posting: Posting in postings:
		var action := posting.impact.action
		var source: CombatantState = group.actors.get(posting.hit.source)
		if source == null or source.life != posting.hit.source_life or not source.is_alive():
			continue
		if action.restore_source != null:
			var before := source.hp.amount
			var actor := _edit_actor(group, source.id)
			if not actor.recover_hp(action.restore_source):
				return false
			posting.hit.hp_restored = actor.hp.amount.subtract(before)
			if posting.hit.hp_restored == null:
				return false
		if action.barrier_for_source != null:
			_grant_barrier(_edit_actor(group, source.id), posting.hit, action.barrier_for_source)
	return true


static func _grant_barrier(actor: CombatantState, hit: Hit, grant: CombatAction.BarrierGrant) -> void:
	for barrier: CombatantState.Barrier in actor.barriers:
		if barrier.id == grant.id:
			return
	var barrier := CombatantState.Barrier.new()
	barrier.id = grant.id
	barrier.mask = grant.mask
	barrier.pool = QuantityLayerLedger.Pool.new(grant.capacity, QuantityErrorBounds.new())
	actor.barriers.append(barrier)
	hit.granted_barrier = grant.id


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
		if source == null or source.life != posting.hit.source_life or source.realm != target.realm:
			continue
		var failure := _gather_claims(group, claims, source, target, posting, false)
		if not failure.is_empty():
			return failure
		failure = _gather_claims(group, claims, target, source, posting, true)
		if not failure.is_empty():
			return failure
	for claim: ReactionClaim in claims:
		var failure := _choose_descendant(group, claim)
		if not failure.is_empty():
			return failure
	return &""


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
	for component: ComponentReceipt in posting.hit.components:
		if rule.cause == CombatFollowUp.Cause.HOSTILE_HP and component.hostile_hp_removed.sign_value > 0:
			return true
		if rule.cause == CombatFollowUp.Cause.HOSTILE_LAYER:
			for barrier: LayerReceipt in component.barriers:
				if barrier.id == rule.layer and barrier.hostile_depletion:
					return true
	return false


static func _choose_descendant(group: Group, claim: ReactionClaim) -> StringName:
	var rule := claim.rule
	var balance: Quantity = group.actors[claim.actor.id].resources.get(rule.resource)
	if rule.cost != null and (balance == null or balance.compare(rule.cost) < 0):
		return &""
	var receipt := claim.posting.hit
	var cause := claim.posting.impact
	var budget := QuantityCodec.encode(balance).hex_encode() if balance != null else ""
	var contact := [receipt.source, receipt.source_life, receipt.target, receipt.target_life, receipt.shape, claim.shape]
	var equivalent := JSON.stringify([rule.id, contact, _life_image(claim.actor), _life_image(claim.target), budget], "", true)
	var ancestor := cause.ancestry
	while ancestor != null:
		if equivalent == ancestor.key:
			return &"causal_cycle"
		ancestor = ancestor.previous
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
	action.consume_status = rule.consume_status
	var child := Impact.new()
	child.action = action
	child.origin = action.origin
	child.target = claim.target.id
	child.target_life = claim.target.life
	child.shape = claim.shape
	child.hostile = cause.hostile
	child.parent = receipt.event
	child.reaction = rule.id
	child.ancestry = Ancestry.new()
	child.ancestry.key = equivalent
	child.ancestry.previous = cause.ancestry
	if rule.inherit_parent_statuses and child.target == receipt.target:
		child.uses_inherited_statuses = true
		child.inherited_statuses = receipt.before_statuses.duplicate()
	group.pending.append(child)
	return &""


static func _life_image(actor: CombatantState) -> Array:
	var layers: Array[Array] = []
	for barrier: CombatantState.Barrier in actor.barriers:
		layers.append([barrier.id, QuantityCodec.encode(barrier.pool.amount).hex_encode(),
			barrier.pool.error.snapshot().hex_encode()])
	return [actor.id, actor.life, QuantityCodec.encode(actor.hp.amount).hex_encode(),
		actor.hp.error.snapshot().hex_encode(), layers, actor.statuses]


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


func _draft_hit(impact: Impact, before: CombatantState, after: CombatantState) -> Hit:
	var hit := Hit.new()
	hit.origin = impact.origin.copy()
	hit.family = impact.action.family
	hit.source = impact.action.source
	hit.source_life = impact.action.source_life
	hit.target = impact.target
	hit.target_life = impact.target_life
	hit.shape = impact.shape
	hit.parent = impact.parent
	hit.reaction = impact.reaction
	if before.life != impact.target_life or not before.is_alive():
		return hit
	hit.before_statuses = impact.inherited_statuses.duplicate() if impact.uses_inherited_statuses else before.statuses.duplicate()
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
