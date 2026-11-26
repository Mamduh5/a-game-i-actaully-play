class_name WorldPressureHazard
extends RefCounted
## Realm-owned pressure trigger with a telegraphed, one-shot impact.

enum SampleResult { INVALID, UNCHANGED, WARNED }

class Occupant:
	var actor: StringName
	var shape: int
	var weight: float
	var cause: CombatOrigin

class Warning:
	var hazard: StringName
	var begins: CombatInstant
	var due: CombatInstant
	var center: RealmSweep.Point
	var radius: float
	var cause: CombatOrigin

class Strike:
	var warning: Warning
	var contacts: Array[RealmGeometry.Contact] = []

var _realm: StringName
var _id: StringName
var _plate: RealmSweep.Point
var _plate_radius: float
var _center: RealmSweep.Point
var _radius: float
var _warning_ticks: int
var _weight_threshold: float
var _mask: int
var _last_sample: CombatInstant
var _warning: Warning
var _pressed: bool


static func create(realm: StringName, id: StringName, plate: RealmSweep.Point, plate_radius: float,
		center: RealmSweep.Point, radius: float, warning_ticks: int, minimum_weight: float, mask: int) -> WorldPressureHazard:
	if (realm.is_empty() or id.is_empty() or not _finite_point(plate) or not _finite_point(center)
			or not is_finite(plate_radius) or plate_radius <= 0.0 or not is_finite(radius) or radius <= 0.0
			or warning_ticks <= 0 or not is_finite(minimum_weight) or minimum_weight <= 0.0 or mask <= 0):
		return null
	var result := WorldPressureHazard.new()
	result._realm = realm
	result._id = id
	result._plate = RealmSweep.Point.new(plate.x, plate.y)
	result._plate_radius = plate_radius
	result._center = RealmSweep.Point.new(center.x, center.y)
	result._radius = radius
	result._warning_ticks = warning_ticks
	result._weight_threshold = minimum_weight
	result._mask = mask
	return result


func sample(geometry: RealmGeometry, now: CombatInstant, occupants: Array[Occupant]) -> SampleResult:
	if (geometry == null or geometry.realm_id != _realm or now == null or now.after_ticks(0) == null
			or (_last_sample != null and now.order_against(_last_sample) != RealmCircleTime.Order.AFTER)):
		return SampleResult.INVALID
	var eligible: Array[Occupant] = []
	var seen: Dictionary[StringName, bool] = {}
	var certifier := RealmCircleTime.new()
	for occupant: Occupant in occupants:
		if (occupant == null or occupant.actor.is_empty() or occupant.shape < 0 or seen.has(occupant.actor)
				or not is_finite(occupant.weight) or occupant.weight <= 0.0
				or (occupant.cause != null and not occupant.cause.valid_for(now))):
			return SampleResult.INVALID
		var position := geometry.circle_center(occupant.actor, occupant.shape)
		if position == null:
			return SampleResult.INVALID
		seen[occupant.actor] = true
		if occupant.weight < _weight_threshold:
			continue
		var mass_radius := geometry.circle_radius(occupant.actor, occupant.shape)
		var proof := certifier.measure(position, position, mass_radius, _plate, _plate, _plate_radius)
		if proof.outcome == RealmCircleTime.Result.UNRESOLVED:
			return SampleResult.INVALID
		if proof.outcome == RealmCircleTime.Result.HIT:
			eligible.append(occupant)
	var rising := not eligible.is_empty() and not _pressed and _warning == null
	var deadline := now.after_ticks(_warning_ticks) if rising else null
	if rising and deadline == null:
		return SampleResult.INVALID
	_last_sample = now
	_pressed = not eligible.is_empty()
	if not rising:
		return SampleResult.UNCHANGED
	eligible.sort_custom(func(left: Occupant, right: Occupant) -> bool:
		if left.weight != right.weight:
			return left.weight > right.weight
		if left.cause == null or right.cause == null:
			return left.cause == null and right.cause != null
		return left.cause.canonical_before(right.cause))
	var cause := eligible[0].cause
	_warning = Warning.new()
	_warning.hazard = _id
	_warning.begins = now
	_warning.due = deadline
	_warning.center = _center
	_warning.radius = _radius
	_warning.cause = cause.copy() if cause != null else null
	return SampleResult.WARNED


func warning_snapshot() -> Warning:
	if _warning == null:
		return null
	var result := Warning.new()
	result.hazard = _warning.hazard
	result.begins = _warning.begins
	result.due = _warning.due
	result.center = RealmSweep.Point.new(_center.x, _center.y)
	result.radius = _radius
	result.cause = _warning.cause.copy() if _warning.cause != null else null
	return result


## Evaluate the warned shape on the impact instant's authoritative geometry.
## An uncertified query retains the scheduled strike for the caller to resolve.
func take_strike(geometry: RealmGeometry, through: CombatInstant) -> Strike:
	if (geometry == null or geometry.realm_id != _realm or _warning == null or through == null
			or _warning.due.order_against(through) not in [RealmCircleTime.Order.BEFORE, RealmCircleTime.Order.SAME]):
		return null
	var proof := geometry.certify_circle_snapshot(_realm, _center, _radius, _mask)
	if proof == null or not proof.unresolved.is_empty():
		return null
	var result := Strike.new()
	result.warning = warning_snapshot()
	result.contacts = proof.contacts
	_warning = null
	return result


static func _finite_point(point: RealmSweep.Point) -> bool:
	return point != null and is_finite(point.x) and is_finite(point.y)
