class_name CombatTether
extends RefCounted
## A linked delivery samples its current endpoints without resetting its clock.

class Endpoint:
	var actor: StringName
	var slot: int
	var life := 1
	var anchor: RealmSweep.Point

	func copy() -> Endpoint:
		var result := Endpoint.new()
		result.actor = actor
		result.slot = slot
		result.life = life
		if anchor != null:
			result.anchor = RealmSweep.Point.new(anchor.x, anchor.y)
		return result

class Pulse:
	var _tether: CombatTether
	var _geometry: RealmGeometry
	var _revision: int
	var _endpoint_revision: int
	var instant: CombatDeliverySchedule.Due
	var blocker: RealmGeometry.Contact
	var contacts: Array[RealmGeometry.Contact] = []

var _realm: StringName
var _kernel: CombatKernel
var _delivery: CombatDelivery
var _clock: CombatDeliverySchedule
var _ends: Array[Endpoint] = []
var _remaining_reconnections: int
var _reach: float
var _endpoint_revision: int


static func activate(kernel: CombatKernel, action: CombatAction, geometry: RealmGeometry, first: Endpoint,
		last: Endpoint, duration: int, period: int, max_reach: float, reconnections: int) -> CombatTether:
	if (kernel == null or action == null or action.origin == null or geometry == null or reconnections < 0
			or not is_finite(max_reach) or max_reach <= 0.0
			or not _valid_link(_position(first, kernel, geometry), _position(last, kernel, geometry), max_reach)):
		return null
	var clock := CombatDeliverySchedule.create(action.origin.committed_at, duration, period)
	if clock == null:
		return null
	var delivery := CombatDelivery.activate(kernel, action, geometry.realm_id, period)
	if delivery == null:
		return null
	var tether := CombatTether.new()
	tether._kernel = kernel
	tether._realm = geometry.realm_id
	tether._ends = [first.copy(), last.copy()]
	tether._remaining_reconnections = reconnections
	tether._reach = max_reach
	tether._clock = clock
	tether._delivery = delivery
	return tether


func reconnect(index: int, replacement: Endpoint, geometry: RealmGeometry, now: CombatInstant) -> bool:
	if (index < 0 or index >= _ends.size() or _remaining_reconnections <= 0 or not _clock.active_at(now)
			or geometry == null or geometry.realm_id != _realm or _position(_ends[index], _kernel, geometry) != null
			or not _valid_link(_position(replacement, _kernel, geometry), _position(_ends[1 - index], _kernel, geometry), _reach)):
		return false
	_ends[index] = replacement.copy()
	_remaining_reconnections -= 1
	_endpoint_revision += 1
	return true


## The fixed-step owner supplies settled geometry. This produces actual
## link intersections for a due interval, with one suppression for obstruction.
func due_through(geometry: RealmGeometry, through: CombatInstant, width: float, targets: int, blockers: int) -> Pulse:
	if (geometry == null or geometry.realm_id != _realm or targets <= 0 or blockers < 0
			or not is_finite(width) or width < 0.0):
		return null
	var event := _clock.due_through(through)
	if event == null:
		return null
	var pulse := Pulse.new()
	pulse._tether = self
	pulse._geometry = geometry
	pulse._revision = geometry.revision
	pulse._endpoint_revision = _endpoint_revision
	pulse.instant = event
	if event.kind == CombatDeliverySchedule.Kind.NATURAL_EXPIRY:
		return pulse
	var first := _position(_ends[0], _kernel, geometry)
	var last := _position(_ends[1], _kernel, geometry)
	if not _valid_link(first, last, _reach):
		return pulse
	var sweep := _delivery.plan_sweep(geometry, first, last, width * 0.5, targets, blockers)
	if sweep == null:
		return null
	pulse.blocker = sweep.blocker
	if pulse.blocker == null:
		pulse.contacts = sweep.contacts
	return pulse


func settle(pulse: Pulse) -> bool:
	if not _awaits(pulse):
		return false
	if pulse.instant.kind == CombatDeliverySchedule.Kind.NATURAL_EXPIRY and not _delivery.finish():
		return false
	return _clock.settle(pulse.instant)


func admit(pulse: Pulse, contact: RealmGeometry.Contact, target_life: int, hostile: bool) -> CombatDelivery.Result:
	if not _awaits(pulse) or contact not in pulse.contacts:
		return CombatDelivery.Result.INVALID
	# The spatial fraction locates a target along the link. All intersections
	# become simultaneous contacts at the actual interval's certified time.
	var at := pulse.instant.instant
	var timed := RealmGeometry.Contact.new()
	timed.entity = contact.entity
	timed.shape = contact.shape
	timed.proof = at.proof_snapshot()
	timed.time = timed.proof.earliest
	return _delivery.admit(at.tick, timed, target_life, hostile)


func _awaits(pulse: Pulse) -> bool:
	return (pulse != null and pulse._tether == self and pulse._geometry != null
		and pulse._geometry.revision == pulse._revision and pulse._endpoint_revision == _endpoint_revision
		and _clock.awaits(pulse.instant))


static func _position(end: Endpoint, kernel: CombatKernel, geometry: RealmGeometry) -> RealmSweep.Point:
	if end == null:
		return null
	if end.actor.is_empty():
		if end.anchor != null and is_finite(end.anchor.x) and is_finite(end.anchor.y):
			return end.anchor
		return null
	var actor := kernel.actor_snapshot(end.actor)
	if end.anchor != null or actor == null or actor.life != end.life or actor.realm != geometry.realm_id or not actor.is_alive():
		return null
	return geometry.circle_center(end.actor, end.slot)


static func _valid_link(first: RealmSweep.Point, last: RealmSweep.Point, reach: float) -> bool:
	if first == null or last == null:
		return false
	var dx := (last.x - first.x) / reach
	var dy := (last.y - first.y) / reach
	return (dx != 0.0 or dy != 0.0) and dx * dx + dy * dy <= 1.0
