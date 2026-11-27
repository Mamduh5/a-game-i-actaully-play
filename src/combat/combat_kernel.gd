class_name CombatKernel
extends RefCounted
## Run-owned combat admission. All waves at one due instant publish together.

enum Result { IDLE, WAITING, CLOSED, INTERRUPTED, YIELDED, STORAGE_WAIT }
enum Terminal { ACTIVE, VICTORY, DEFEAT }
enum BarrierEnd { EXPIRED, REPLACED, CLAMPED, DECAYED, REMOVED }
enum BarrierAdjustment { CAP, DECAY, REMOVE }
enum ActivationOutcome { PAID, LETHAL, REJECTED, SUPPRESSED }

class ActorVitals:
	var realm: StringName
	var life: int
	var hp: Quantity
	var maximum: Quantity

class ArenaArrival:
	var actor: StringName
	var life: int
	var alive: bool
	var source: RealmGeometry
	var at: RealmSweep.Point

class ArenaTransfer:
	var _arena: RealmGeometry
	var _arena_draft: RealmGeometry
	var _blockers: int
	var _boundary: CombatInstant
	var _revisions: Dictionary[RealmGeometry, int] = {}
	var _departures: Dictionary[RealmGeometry, RealmGeometry] = {}
	var _players: Dictionary[StringName, CombatantState] = {}

	func destination() -> RealmGeometry:
		return _arena

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
	var wake_duration: int
	var wake_radius: float
	var arc_start: RealmSweep.Point
	var arc_end: RealmSweep.Point
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
	var penetrations: int
	var currents: Dictionary[StringName, Array] = {}
	var armed_mine: CombatMineCharge
	var mine_center: RealmSweep.Point
	var mine_trigger_radius: float
	var mine_blast_radius: float
	var mine_targets: int
	var action: CombatAction
	var realm: StringName
	var parts: Dictionary[int, bool] = {}
	var payment_pending: bool

class Impact:
	var lance: Commitment
	var tether: Commitment
	var contact_position: RealmSweep.Point
	var pre_parent_bleed: CombatBleedLedger.Prestate
	var arc_start: RealmSweep.Point
	var arc_end: RealmSweep.Point
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

class MineEntry:
	var held: Commitment
	var proof: RealmCircleTime.Contact
	var entrant: StringName
	var life: int
	var visit: int
	var realm: StringName

class Ancestry:
	var key: String
	var wave_state: String
	var previous: Ancestry

class Posting:
	var rupture_stacks: int
	var before_bleed: CombatBleedLedger.Prestate
	var impact: Impact
	var hit: Hit

class BarrierCredit:
	var first_hit: Hit
	var rule: CombatAction.BarrierConversion
	var hp := Quantity.from_count(0)

class ReactionClaim:
	var arc_start: RealmSweep.Point
	var arc_end: RealmSweep.Point
	var rule: CombatFollowUp
	var posting: Posting
	var actor: CombatantState
	var target: CombatantState
	var shape: int

class Group:
	var penetrations: Dictionary[Commitment, int] = {}
	var currents: Dictionary[Commitment, Dictionary] = {}
	var detonations: Array[CombatMineCharge] = []
	var echoes: Array[Echo] = []
	var wakes: Array[Wake] = []
	var bleeds: Dictionary[StringName, CombatBleedLedger] = {}
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

class Echo:
	var realm: StringName
	var center: RealmSweep.Point
	var action: CombatAction
	var origin: CombatOrigin
	var radius: float
	var targets: int
	var due: CombatInstant
	var last_advanced: int

class EchoCue:
	var center: RealmSweep.Point
	var radius: float
	var due: int

class Wake:
	var realm: StringName
	var start: RealmSweep.Point
	var finish: RealmSweep.Point
	var action: CombatAction
	var origin: CombatOrigin
	var cadence: CombatDeliverySchedule

	func copy() -> Wake:
		var result := Wake.new()
		result.realm = realm
		result.start = start
		result.finish = finish
		result.action = action
		result.origin = origin
		result.cadence = cadence.copy()
		return result

var _wakes: Array[Wake] = []
var _echoes: Array[Echo] = []
var _actors: Dictionary[StringName, CombatantState] = {}
var _bleeds: Dictionary[StringName, CombatBleedLedger] = {}
var _actions: Dictionary[String, Commitment] = {}
var _hp_activations: Dictionary[String, Commitment] = {}
var _latest_activation: Dictionary[String, int] = {}
var _impacts: Dictionary[String, Impact] = {}
var _mine_entries: Dictionary[String, MineEntry] = {}
var _queue := CombatRootQueue.new()
var _closed: CombatInstant
var _fault: StringName
var _fault_wave: int
var _group: Group
var _geometry: Dictionary[StringName, RealmGeometry] = {}
var _blocker_masks: Dictionary[StringName, int] = {}
var _arena: RealmGeometry
var _retired_actors: Dictionary[StringName, bool] = {}
var _creator: StringName
var _eligible: Array[StringName] = []
var _terminal: Terminal
var _physical_mitigation := Quantity.from_count(100)
var _magical_mitigation := Quantity.from_count(100)

var terminal: Terminal:
	get: return _terminal


func add_actor(actor: CombatantState) -> bool:
	if (not _accepting() or actor == null or not actor.is_valid() or _actors.has(actor.id)
			or (_arena != null and (actor.realm != _arena.realm_id or _retired_actors.has(actor.id)))):
		return false
	_actors[actor.id] = actor.copy()
	return true


func actor_snapshot(id: StringName) -> CombatantState:
	var actor: CombatantState = _actors.get(id)
	return actor.copy() if actor != null else null


## Sample the published life and health for spatial decisions and readback.
func actor_vitals(id: StringName) -> ActorVitals:
	var actor: CombatantState = _actors.get(id)
	if actor == null:
		return null
	var result := ActorVitals.new()
	result.realm = actor.realm
	result.life = actor.life
	result.hp = actor.hp.amount
	result.maximum = actor.max_hp
	return result


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


## Draft all arrivals before changing either side of the gateway.
func stage_arena(now: CombatInstant, arena: RealmGeometry, blockers: int,
		arrivals: Array[ArenaArrival]) -> ArenaTransfer:
	if (not _accepting() or _arena != null or _closed == null or now == null
			or _closed.order_against(now) != RealmCircleTime.Order.SAME
			or arena == null or arena.realm_id != RunSetup.FINAL_REALM or _geometry.has(arena.realm_id)
			or blockers <= 0 or arrivals.is_empty() or arrivals.size() > RunSetup.MAX_SEATS):
		return null
	var transfer := ArenaTransfer.new()
	transfer._arena = arena
	transfer._arena_draft = arena.fork()
	transfer._revisions[arena] = arena.revision
	transfer._blockers = blockers
	transfer._boundary = now
	for move: ArenaArrival in arrivals:
		if move == null or move.source == null or move.at == null or transfer._players.has(move.actor):
			return null
		var actor: CombatantState = _actors.get(move.actor)
		var source := move.source
		if (not _is_player_life(actor, move.life) or actor.is_alive() != move.alive
				or actor.realm_visit == Quantity.INT_MAX or actor.realm != source.realm_id
				or _geometry.get(source.realm_id) != source):
			return null
		if not transfer._departures.has(source):
			transfer._revisions[source] = source.revision
			transfer._departures[source] = source.fork()
		var departure := transfer._departures[source]
		if not _draft_arena_body(move.actor, source, departure, transfer._arena_draft, move.at, blockers):
			return null
		transfer._players[move.actor] = actor
	return transfer


static func _draft_arena_body(id: StringName, source: RealmGeometry, departure: RealmGeometry,
		arrival: RealmGeometry, at: RealmSweep.Point, blockers: int) -> bool:
	var anchor := source.circle_center(id, 0)
	if anchor == null:
		return false
	for slot: int in source.circle_slots(id):
		var start := source.circle_center(id, slot)
		var finish := RealmSweep.Point.new(at.x + (start.x - anchor.x), at.y + (start.y - anchor.y))
		var radius := source.circle_radius(id, slot)
		var clear := arrival.certify_circle_snapshot(arrival.realm_id, finish, radius, blockers, id)
		if (clear == null or not clear.contacts.is_empty() or not clear.unresolved.is_empty()
				or not departure.remove_mutable(id, slot)
				or not arrival.add_circle(id, slot, finish, radius, source.circle_category(id, slot))):
			return false
	return true


## Retire old spatial work without resolving hits or expiry reactions.
## Character-owned health, cooldowns and attached status clocks carry over.
func enter_arena(transfer: ArenaTransfer, now: CombatInstant) -> bool:
	if (transfer == null or now == null or not _accepting() or _arena != null or _closed == null
			or transfer._boundary == null or transfer._players.is_empty()
			or _closed.order_against(now) != RealmCircleTime.Order.SAME
			or transfer._boundary.order_against(now) != RealmCircleTime.Order.SAME):
		return false
	for floor: RealmGeometry in transfer._revisions:
		if floor.revision != transfer._revisions[floor]:
			return false
	for id: StringName in transfer._players:
		if _actors.get(id) != transfer._players[id]:
			return false
	var carried: Dictionary[StringName, CombatBleedLedger] = {}
	for id: StringName in transfer._players:
		if _bleeds.has(id):
			carried[id] = _bleeds[id]
	for source: RealmGeometry in transfer._departures:
		source.adopt(transfer._departures[source])
	_arena = transfer._arena
	_arena.adopt(transfer._arena_draft)
	for id: StringName in _actors:
		if not transfer._players.has(id):
			_retired_actors[id] = true
	_actors = transfer._players.duplicate()
	for actor: CombatantState in _actors.values():
		actor.realm = _arena.realm_id
		actor.realm_visit += 1
	_geometry = {_arena.realm_id: _arena}
	_blocker_masks = {_arena.realm_id: transfer._blockers}
	_retire_combat_work()
	_bleeds = carried
	return true


func arena_started() -> bool:
	return _arena != null


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
	if not _accepting() or _arena != null or geometry == null or geometry.realm_id.is_empty() or blocker_mask <= 0:
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


func bind_mine(key: String, mine: CombatMineCharge, center: RealmSweep.Point, trigger_radius: float,
		blast_radius: float, targets: int) -> bool:
	var held: Commitment = _actions.get(key)
	if (not _accepting() or held == null or held.action.family != &"P03" or held.action.components.size() != 1
			or center == null or not is_finite(center.x) or not is_finite(center.y) or not is_finite(trigger_radius)
			or not is_finite(blast_radius) or trigger_radius <= 0 or blast_radius < trigger_radius or targets <= 0
			or held.armed_mine != null or not held.parts.is_empty() or mine == null or mine.end_reason != CombatMineCharge.End.LIVE):
		return false
	held.armed_mine = mine
	held.mine_center = PlayerControlState.copy_point(center)
	held.mine_trigger_radius = trigger_radius
	held.mine_blast_radius = blast_radius
	held.mine_targets = targets
	return true


## Register a prospective entry. A preceding combat group can eliminate the
## entrant before this instant, leaving the mine for another eligible crossing.
func offer_mine_entry(key: String, part: int, start_tick: int, contact: RealmGeometry.Contact) -> bool:
	if contact == null:
		return false
	var at := CombatInstant.at_contact(start_tick, contact.proof)
	var held: Commitment = _actions.get(key)
	var entrant: CombatantState = _actors.get(contact.entity)
	if (not _accepting() or held == null or held.armed_mine == null or part < 1 or held.parts.has(part)
			or entrant == null or not entrant.is_alive() or entrant.realm != held.realm or at == null
			or (_closed != null and _closed.order_against(at) != RealmCircleTime.Order.BEFORE)):
		return false
	var origin := held.action.origin.copy()
	origin.delivery_part = part
	var entry := MineEntry.new()
	entry.held = held
	entry.entrant = entrant.id
	entry.life = entrant.life
	entry.visit = entrant.realm_visit
	entry.realm = held.realm
	entry.proof = contact.proof.copy()
	if _queue.admit(origin, at) != CombatRootQueue.Result.ACCEPTED:
		return false
	held.parts[part] = true
	_mine_entries[origin.occurrence_key()] = entry
	return true


func _resolve_mine_entry(group: Group, origin: CombatOrigin, entry: MineEntry) -> bool:
	var held := entry.held
	var entrant := group.actors[entry.entrant]
	if (held.armed_mine.end_reason != CombatMineCharge.End.LIVE or held.armed_mine in group.detonations
			or not entrant.is_alive() or entrant.life != entry.life or entrant.realm_visit != entry.visit or entrant.realm != entry.realm):
		return true
	var geometry := _geometry[held.realm]
	var inside := geometry.certify_disk_at(held.realm, held.mine_center, held.mine_trigger_radius,
		entry.proof, held.mine_targets, held.action.source)
	if inside == null or not inside.unresolved.is_empty():
		return false
	var eligible := false
	for contact: RealmGeometry.Contact in inside.contacts:
		if contact.entity == entrant.id:
			eligible = true
			break
	if not eligible:
		return true
	var blast := geometry.certify_disk_at(held.realm, held.mine_center, held.mine_blast_radius,
		entry.proof, held.mine_targets, held.action.source)
	var potency := held.armed_mine.potency_at(group.receipt.due)
	if blast == null or not blast.unresolved.is_empty() or potency == null:
		return false
	var action := held.action.copy()
	action.components[0].base = potency
	group.detonations.append(held.armed_mine)
	var seen: Dictionary[StringName, bool] = {}
	for contact: RealmGeometry.Contact in blast.contacts:
		var target: CombatantState = group.actors.get(contact.entity)
		if target == null or target.realm != held.realm or not target.is_alive() or seen.has(target.id):
			continue
		seen[target.id] = true
		var impact := Impact.new()
		impact.action = action
		impact.origin = origin
		impact.root_occurrence = origin.occurrence_key()
		impact.target = target.id
		impact.target_life = target.life
		impact.target_visit = target.realm_visit
		impact.shape = contact.shape
		impact.hostile = true
		group.pending.append(impact)
	return true


func admit_contact(key: String, part: int, realm: StringName, start_tick: int, contact: RealmGeometry.Contact,
		target_life: int, hostile: bool, position: RealmSweep.Point = null) -> CombatRootQueue.Result:
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
	if held.armed_mine != null:
		return CombatRootQueue.Result.INVALID
	if due != null and _closed != null and _closed.order_against(due) != RealmCircleTime.Order.BEFORE:
		return CombatRootQueue.Result.CLOSED_INSTANT
	if held.payment_pending and (due == null
			or due.order_against(held.action.origin.committed_at) != RealmCircleTime.Order.SAME):
		return CombatRootQueue.Result.INVALID
	var impact := Impact.new()
	impact.contact_position = PlayerControlState.copy_point(position) if position != null else null
	impact.action = held.action
	if held.action.ascending_pierce:
		impact.lance = held
	if held.action.resonant_interval > 0:
		impact.tether = held
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
	return _queue.pending_count() + _bleeds.size() + _wakes.size() + _echoes.size()


## The fixed-step owner can drain older sub-tick impacts before it admits
## actions at the next integer boundary.
func next_due() -> CombatInstant:
	if _group != null:
		return _group.root.due
	var wave := _next_wave()
	return wave.due if wave != null else null


func _next_wave() -> CombatRootQueue.Wave:
	var roots := _queue.earliest_wave()
	if (_bleeds.is_empty() and _wakes.is_empty() and _echoes.is_empty()) or (roots == null and _queue.pending_count() > 0):
		return roots
	var times: Array[CombatInstant] = []
	for echo: Echo in _echoes:
		times.append(echo.due)
	if roots != null:
		times.append(roots.due)
	for ledger: CombatBleedLedger in _bleeds.values():
		times.append_array(ledger.deadlines())
	for wake: Wake in _wakes:
		var next := wake.cadence.next_event()
		times.append(next.instant if next != null else null)
	var first: CombatInstant
	for due: CombatInstant in times:
		if due == null:
			return null
		if first == null or due.order_against(first) == RealmCircleTime.Order.BEFORE:
			first = due
	for due: CombatInstant in times:
		if first.order_against(due) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]:
			return null
	if first == null or (roots != null and first.order_against(roots.due) == RealmCircleTime.Order.SAME):
		return roots
	var wave := CombatRootQueue.Wave.new()
	wave.due = first
	return wave


## Close an idle survival deadline after the run has admitted all work through it.
## Impacts at the deadline get their full causal group before expiry.
func advance_survival(through: CombatInstant) -> WaveResult:
	if not _fault.is_empty():
		return _result(Result.INTERRUPTED)
	if (not _accepting() or through == null
			or (_closed != null and _closed.order_against(through) != RealmCircleTime.Order.BEFORE)):
		return _result(Result.WAITING)
	if pending_count() > 0:
		var next := _next_wave()
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
	var wave := _next_wave()
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
	for id: StringName in _bleeds:
		_group.bleeds[id] = _bleeds[id].copy()
	for wake: Wake in _wakes:
		_group.wakes.append(wake.copy())
	_group.echoes = _echoes.duplicate()
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
		var entry: MineEntry = _mine_entries.get(origin.occurrence_key())
		if entry != null and not _resolve_mine_entry(_group, origin, entry):
			return _interrupt(&"mine_entry")
		if impact == null or (not impact.activation.is_empty()
				and _group.activation_outcomes[impact.activation] != ActivationOutcome.PAID):
			continue
		if impact.action.continuation == CombatAction.Continuation.LIVE_CONTROLLER:
			var source: CombatantState = _group.actors.get(impact.action.source)
			if source == null or source.life != impact.action.source_life or not _live_controller(_group.actors, source):
				continue
		_group.pending.append(impact)
	if not _advance_bleeds(_group, false):
		return _interrupt(&"bleed_cadence")
	if not _advance_wakes(_group):
		return _interrupt(&"wake_geometry_or_cadence")
	if not _deliver_echoes(_group):
		return _interrupt(&"echo_geometry")
	return null


## Ticks join the input wave. Expiry follows every application at that instant.
static func _advance_bleeds(group: Group, expiring: bool) -> bool:
	for id: StringName in group.bleeds.keys():
		var ledger := group.bleeds[id]
		var target := group.actors[id]
		if not target.is_alive():
			group.bleeds.erase(id)
			continue
		for owner: String in ledger.owners():
			var tick := ledger.due_for_owner(owner, group.receipt.due)
			if tick == null or (tick.event.kind == CombatDeliverySchedule.Kind.NATURAL_EXPIRY) != expiring:
				continue
			for stack: CombatBleedLedger.Stack in tick.stacks:
				var impact := Impact.new()
				impact.action = CombatAction.new()
				impact.action.source = stack.source
				impact.action.source_life = stack.source_life
				impact.action.origin = stack.origin
				impact.action.family = &"R01.bleed"
				impact.action.components = [stack.offense]
				impact.origin = stack.origin
				impact.root_occurrence = stack.id
				impact.target = id
				impact.target_life = target.life
				impact.target_visit = target.realm_visit
				impact.hostile = true
				group.pending.append(impact)
			if not ledger.settle(tick):
				return false
		if ledger.owners().is_empty():
			group.bleeds.erase(id)
	return true


func _advance_wakes(group: Group) -> bool:
	for index: int in range(group.wakes.size() - 1, -1, -1):
		var wake := group.wakes[index]
		var due := wake.cadence.due_through(group.receipt.due)
		if due == null:
			continue
		if due.kind == CombatDeliverySchedule.Kind.TICK:
			var geometry := _geometry[wake.realm]
			var coverage := geometry.certify_frozen_path(wake.realm, wake.start, wake.finish,
				wake.action.wake_radius, wake.action.wake_targets, wake.action.source)
			if coverage == null or not coverage.unresolved.is_empty():
				return false
			var reached: Dictionary[StringName, bool] = {}
			for contact: RealmGeometry.Contact in coverage.contacts:
				var target: CombatantState = group.actors.get(contact.entity)
				if target == null or not target.is_alive() or target.realm != wake.realm or reached.has(target.id):
					continue
				reached[target.id] = true
				var impact := Impact.new()
				impact.action = CombatAction.new()
				impact.action.family = &"RP02.blood_wake"
				impact.action.source = wake.action.source
				impact.action.source_life = wake.action.source_life
				var part := CombatAction.Component.new()
				part.base = Quantity.from_count(wake.action.wake_damage)
				impact.action.components = [part]
				impact.origin = wake.origin
				impact.root_occurrence = wake.origin.occurrence_key()
				impact.reaction = impact.action.family
				impact.target = target.id
				impact.target_life = target.life
				impact.target_visit = target.realm_visit
				impact.shape = contact.shape
				impact.hostile = true
				group.pending.append(impact)
		if not wake.cadence.settle(due):
			return false
		var expiry := wake.cadence.due_through(group.receipt.due)
		if expiry != null and not wake.cadence.settle(expiry):
			return false
		if wake.cadence.end_reason == CombatDeliverySchedule.End.NATURAL:
			group.wakes.remove_at(index)
	return true


## One extra logical step per tick of overlap. A retry cannot move the same
## pending repetition twice, and reaching the current boundary fires it there.
func compress_schedules(actor_id: StringName, realm: StringName, tick: int, center: RealmSweep.Point, radius: float) -> bool:
	var source: CombatantState = _actors.get(actor_id)
	var now := CombatInstant.at_tick(tick)
	if (not _accepting() or source == null or not _geometry.has(realm) or center == null or now == null
			or not is_finite(center.x) or not is_finite(center.y) or not is_finite(radius) or radius <= 0.0
			or (_closed != null and _closed.order_against(now) != RealmCircleTime.Order.BEFORE)):
		return false
	for echo: Echo in _echoes:
		if (echo.origin.owner != source.owner or echo.origin.provenance != source.provenance
				or echo.realm != realm or echo.last_advanced >= tick or echo.due.tick <= tick):
			continue
		if (echo.center.x - center.x) ** 2 + (echo.center.y - center.y) ** 2 <= radius ** 2:
			echo.due = CombatInstant.at_tick(echo.due.tick - 1)
			echo.last_advanced = tick
	for id: StringName in _bleeds:
		var target := _actors[id]
		if target.realm != realm:
			continue
		var point := _geometry[realm].circle_center(id, 0)
		if point != null and (point.x - center.x) ** 2 + (point.y - center.y) ** 2 <= radius ** 2:
			_bleeds[id].compress_owner(source.provenance, source.owner, tick)
	return true


func echo_cues(actor_id: StringName, realm: StringName) -> Array[EchoCue]:
	var result: Array[EchoCue] = []
	var source: CombatantState = _actors.get(actor_id)
	if source == null:
		return result
	for echo: Echo in _echoes:
		if echo.origin.owner == source.owner and echo.origin.provenance == source.provenance and echo.realm == realm:
			var cue := EchoCue.new()
			cue.center = PlayerControlState.copy_point(echo.center)
			cue.radius = echo.radius
			cue.due = echo.due.tick
			result.append(cue)
	return result


func _schedule_echo(group: Group, posting: Posting) -> bool:
	var parent := posting.impact.action
	var hit := posting.hit
	if parent.echo_delay == 0 or not hit.hostile:
		return true
	var realm := group.actors[hit.target].realm
	var geometry: RealmGeometry = group.geometry.get(realm, _geometry.get(realm))
	var center := posting.impact.contact_position
	if center == null and geometry != null:
		center = geometry.circle_center(hit.target, hit.shape)
	var at := group.receipt.due
	var boundary := at.order_against(CombatInstant.at_tick(at.tick))
	if boundary not in [RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER]:
		return false
	var start := at.tick + int(boundary == RealmCircleTime.Order.AFTER)
	if center == null or start > RunAuthority.MAX_TICK - parent.echo_delay:
		return false
	var echo := Echo.new()
	echo.realm = realm
	echo.center = PlayerControlState.copy_point(center)
	echo.origin = hit.origin.copy()
	echo.targets = parent.echo_targets
	echo.radius = parent.echo_radius
	echo.due = CombatInstant.at_tick(start + parent.echo_delay)
	echo.last_advanced = start
	echo.action = CombatAction.new()
	echo.action.source = hit.source
	echo.action.source_life = hit.source_life
	echo.action.family = StarterCombatRules.TEMPORAL_ECHO
	for original: CombatAction.Component in parent.components:
		var part := original.copy()
		part.base = original.base.multiply(Quantity.from_count(25, 2))
		if part.base == null:
			return false
		echo.action.components.append(part)
	group.echoes.append(echo)
	return true


func _deliver_echoes(group: Group) -> bool:
	for index: int in range(group.echoes.size() - 1, -1, -1):
		var echo := group.echoes[index]
		if echo.due.order_against(group.receipt.due) != RealmCircleTime.Order.SAME:
			continue
		var contacts := _geometry[echo.realm].certify_circle_snapshot(echo.realm, echo.center, echo.radius, echo.targets)
		if contacts == null or not contacts.unresolved.is_empty():
			return false
		var seen: Dictionary[StringName, bool] = {}
		for contact: RealmGeometry.Contact in contacts.contacts:
			var target: CombatantState = group.actors.get(contact.entity)
			if target == null or not target.is_alive() or target.realm != echo.realm or seen.has(target.id):
				continue
			seen[target.id] = true
			var impact := Impact.new()
			impact.action = echo.action
			impact.origin = echo.origin
			impact.root_occurrence = echo.origin.occurrence_key()
			impact.reaction = echo.action.family
			impact.target = target.id
			impact.target_life = target.life
			impact.target_visit = target.realm_visit
			impact.shape = contact.shape
			impact.hostile = true
			group.pending.append(impact)
		group.echoes.remove_at(index)
	return true


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
		if group.bleeds.has(actor.id):
			receipt.death_statuses[&"R01"] = group.bleeds[actor.id].stack_count()
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
			var count := 0
			if impact.lance != null:
				count = group.penetrations.get(impact.lance, impact.lance.penetrations)
			if impact.tether != null:
				if not group.currents.has(impact.tether):
					group.currents[impact.tether] = impact.tether.currents.duplicate()
				var prior: Array = group.currents[impact.tether].get(id, [])
				if (not prior.is_empty() and prior[0] == before.life and prior[1] == before.realm_visit
						and group.receipt.due.tick - int(prior[2]) == impact.action.resonant_interval):
					count = mini(int(prior[3]) + 1, 4)
			var hit := _draft_hit(impact, before, after, group.receipt.due, count)
			if hit == null:
				return &"numeric_posting"
			hit.wave = group.receipt.waves
			hit.event = group.receipt.hits.size() + 1
			group.receipt.hits.append(hit)
			if hit.accepted:
				if impact.lance != null:
					group.penetrations[impact.lance] = mini(count + 1, 4)
				if impact.tether != null:
					group.currents[impact.tether][id] = [before.life, before.realm_visit, group.receipt.due.tick, count]
				var posting := Posting.new()
				if group.bleeds.has(id):
					posting.before_bleed = group.bleeds[id].capture(group.receipt.due)
				posting.hit = hit
				posting.impact = impact
				postings.append(posting)
		group.actors[id] = after
		group.touched[id] = true
	for posting: Posting in postings:
		var hit := posting.hit
		var impact := posting.impact
		if impact.reaction != &"R02.lightning" or impact.action.rupture_per_stack <= 0 or not group.bleeds.has(hit.target):
			continue
		var eligible := CombatRuneGate.lightning_prestate(group.receipt.hits[hit.parent - 1], hit,
			impact.pre_parent_bleed, posting.before_bleed)
		var ledger := group.bleeds[hit.target]
		posting.rupture_stacks = ledger.consume(hit.origin, eligible, group.receipt.due, ledger.stack_count()).size()
		if ledger.owners().is_empty():
			group.bleeds.erase(hit.target)
	_apply_statuses(group, postings)
	for posting: Posting in postings:
		if not _schedule_echo(group, posting):
			return &"echo_schedule"
		var application := posting.impact.action.bleed
		var hit := posting.hit
		if application == null or not hit.hostile or not group.actors[hit.target].is_alive():
			continue
		if not group.bleeds.has(hit.target):
			group.bleeds[hit.target] = CombatBleedLedger.create(hit.target, hit.target_life)
		if not group.bleeds[hit.target].apply(hit, group.receipt.due, application):
			return &"bleed_application"
	if not _displace(group, postings):
		return &"displacement"
	if not _recover(group, postings):
		return &"recovery"
	for posting: Posting in postings:
		if posting.hit.eliminated:
			posting.hit.death_statuses = group.actors[posting.hit.target].statuses.duplicate()
			if group.bleeds.has(posting.hit.target):
				posting.hit.death_statuses[&"R01"] = group.bleeds[posting.hit.target].stack_count()
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
	if not _advance_bleeds(group, true):
		return _interrupt(&"bleed_expiry")
	if not group.root.origins.is_empty() and not _queue.close(group.root):
		return _interrupt(&"stale_wave")
	for realm: StringName in group.geometry:
		_geometry[realm].adopt(group.geometry[realm])
	_actors = group.actors
	_bleeds = group.bleeds
	_wakes = group.wakes
	_echoes = group.echoes
	for lance: Commitment in group.penetrations:
		lance.penetrations = group.penetrations[lance]
	for tether: Commitment in group.currents:
		tether.currents.assign(group.currents[tether])
	for origin: CombatOrigin in group.root.origins:
		_impacts.erase(origin.occurrence_key())
		_mine_entries.erase(origin.occurrence_key())
	for charge: CombatMineCharge in group.detonations:
		charge.detonate(group.receipt.due)
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
	_bleeds.clear()
	_wakes.clear()
	_echoes.clear()
	_queue = CombatRootQueue.new()
	_impacts.clear()
	_mine_entries.clear()
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
		var action := posting.impact.action
		var offset := action.displacement
		var hit := posting.hit
		var target := group.actors[hit.target]
		if (offset == null and action.push_center == null) or not target.is_alive() or target.displacement_resistance == 1.0:
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
		var scale := 1.0 - target.displacement_resistance
		var finish: RealmSweep.Point
		if action.push_center != null:
			var center := action.push_center
			var axis := PlayerControlState.direction(center, start, RealmSweep.Point.new(0, 0))
			if axis.x == 0.0 and axis.y == 0.0:
				continue
			if action.radial_pull:
				var distance := sqrt((start.x - center.x) ** 2 + (start.y - center.y) ** 2)
				var portion := minf(1.0, action.radial_distance * scale / distance)
				finish = RealmSweep.Point.new(lerpf(start.x, center.x, portion), lerpf(start.y, center.y, portion))
			else:
				offset = RealmSweep.Point.new(axis.x * action.radial_distance, axis.y * action.radial_distance)
		if finish == null:
			finish = RealmSweep.Point.new(start.x + offset.x * scale, start.y + offset.y * scale)
		hit.displacement = geometry.displace_body(target.id, hit.shape, finish, _blocker_masks[realm])
		if hit.displacement == null:
			return false
		var settled := hit.displacement.finish
		if settled.x != start.x or settled.y != start.y:
			if hit.hostile and action.wake_targets > 0 and posting.before_bleed != null and posting.before_bleed.has_owner(hit.origin):
				var wake := Wake.new()
				wake.realm = realm
				wake.start = PlayerControlState.copy_point(start)
				wake.finish = PlayerControlState.copy_point(settled)
				wake.action = action
				wake.origin = hit.origin.copy()
				wake.cadence = CombatDeliverySchedule.create(group.receipt.due, action.wake_duration, action.wake_period)
				if wake.cadence == null:
					return false
				group.wakes.append(wake)
				hit.wake_duration = action.wake_duration
				hit.wake_radius = action.wake_radius
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
	if owner == null or not owner.is_alive() or owner.owner != hit.origin.owner or owner.barrier_on_elimination == null:
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
			if posting.rupture_stacks > 0 and target.is_alive():
				_queue_rupture(group, claims, posting, source)
			if posting.hit.hostile and posting.impact.action.lightning_damage != null:
				var arc_failure := _queue_lightning(group, claims, posting, source)
				if not arc_failure.is_empty():
					return arc_failure
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


static func _queue_rupture(group: Group, claims: Array[ReactionClaim], posting: Posting, source: CombatantState) -> void:
	var hit := posting.hit
	var rule := CombatFollowUp.new()
	rule.id = &"RP01.thunder_rupture"
	rule.family = rule.id
	rule.component = CombatAction.Component.new()
	rule.component.kind = CombatAction.Damage.MAGICAL
	rule.component.base = Quantity.from_count(posting.impact.action.rupture_per_stack).multiply(Quantity.from_count(posting.rupture_stacks))
	var claim := ReactionClaim.new()
	claim.rule = rule
	claim.posting = posting
	claim.actor = source
	claim.target = group.actors[hit.target]
	claim.shape = hit.shape
	claims.append(claim)


func _queue_lightning(group: Group, claims: Array[ReactionClaim], posting: Posting, source: CombatantState) -> StringName:
	var action := posting.impact.action
	var hit := posting.hit
	var geometry: RealmGeometry = group.geometry.get(source.realm, _geometry.get(source.realm))
	if geometry == null or _geometry[source.realm].revision != group.revisions[source.realm]:
		return &"reaction_geometry"
	var motion := hit.displacement
	var center := motion.start if motion != null else geometry.circle_center(hit.target, hit.shape)
	if center == null:
		return &"reaction_geometry"
	var starts: Array[RealmSweep.Point] = [center]
	if action.storm_relay and motion != null and (motion.finish.x != center.x or motion.finish.y != center.y):
		starts.append(motion.finish)
	for i: int in starts.size():
		var at := starts[i]
		var contacts := geometry.certify_circle_snapshot(source.realm, at, action.lightning_reach, action.lightning_targets, hit.target)
		if contacts == null or not contacts.unresolved.is_empty():
			return &"reaction_geometry"
		var selected: RealmGeometry.Contact
		var best := INF
		for contact: RealmGeometry.Contact in contacts.contacts:
			var other: CombatantState = group.actors.get(contact.entity)
			if other == null or not other.is_alive() or other.realm != source.realm or other.id == source.id:
				continue
			var pose := geometry.circle_center(other.id, contact.shape)
			if pose == null:
				continue
			var distance := (pose.x - at.x) ** 2 + (pose.y - at.y) ** 2
			# Snapshot enumeration is canonical. Keep the first clear shape at a tied distance.
			if distance >= best:
				continue
			var sight := geometry.certify_frozen_path(source.realm, at, pose, 0.0, _blocker_masks[source.realm], hit.target)
			if sight == null or not sight.unresolved.is_empty():
				return &"reaction_geometry"
			if sight.contacts.is_empty():
				selected = contact
				best = distance
		if selected == null:
			continue
		var rule := CombatFollowUp.new()
		rule.id = &"R02.lightning" if i == 0 else &"RP03.storm_relay"
		rule.family = rule.id
		rule.component = CombatAction.Component.new()
		rule.component.kind = CombatAction.Damage.MAGICAL
		rule.component.base = action.lightning_damage
		var claim := ReactionClaim.new()
		claim.rule = rule
		claim.posting = posting
		claim.actor = source
		claim.target = group.actors[selected.entity]
		claim.shape = selected.shape
		claim.arc_start = at
		claim.arc_end = geometry.circle_center(selected.entity, selected.shape)
		claims.append(claim)
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
			CombatFollowUp.Cause.PAID_HIT: return alive and posting.hit.family not in [
				&"R01.bleed", &"RP02.blood_wake", StarterCombatRules.TEMPORAL_ECHO]
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
	if rule.id == &"R02.lightning":
		action.rupture_per_stack = cause.action.rupture_per_stack
	action.origin = receipt.origin.copy()
	action.origin.owner = claim.actor.owner
	action.origin.provenance = claim.actor.provenance
	action.origin.priority = rule.priority
	action.components = [rule.component]
	action.restore_source = rule.restore_source
	action.damage_recovery = rule.damage_recovery
	action.consume_status = rule.consume_status
	var child := Impact.new()
	if rule.id == &"R02.lightning":
		child.pre_parent_bleed = claim.posting.before_bleed
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
	child.arc_start = claim.arc_start
	child.arc_end = claim.arc_end
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


func _draft_hit(impact: Impact, before: CombatantState, after: CombatantState, now: CombatInstant, penetrations: int) -> Hit:
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
	hit.arc_start = impact.arc_start
	hit.arc_end = impact.arc_end
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
		var base := component.base
		if penetrations > 0:
			base = base.multiply(Quantity.from_count(100 + 25 * penetrations, 2))
		var raw := QuantityFormula.damage_component(base, component.categories, defense.rating, defense.reduction,
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
