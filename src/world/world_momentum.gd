class_name WorldMomentum
extends RefCounted
## Directional influence for one movable body. The geometry owner supplies
## actual contact and separation facts. Only authored force adds energy.

class Influence:
	var origin: CombatOrigin
	var neutral_id: StringName
	var x: float
	var y: float

class Impact:
	var approach_speed: float
	var strength: float
	var primary: CombatOrigin
	var neutral_cause: StringName
	var participants: Array[CombatOrigin] = []

var _mass: float
var _resistance: float
var _influences: Dictionary[String, Influence] = {}
var _contacts: Dictionary[StringName, bool] = {}


static func create(mass: float, displacement_resistance: float) -> WorldMomentum:
	if not is_finite(mass) or mass <= 0.0 or not is_finite(displacement_resistance) or displacement_resistance < 0.0 or displacement_resistance > 1.0:
		return null
	var body := WorldMomentum.new()
	body._mass = mass
	body._resistance = displacement_resistance
	return body


func apply_impulse(force: RealmSweep.Point, origin: CombatOrigin, neutral_id: StringName = &"") -> bool:
	if (force == null or not is_finite(force.x) or not is_finite(force.y)
			or (origin == null and neutral_id.is_empty())
			or (origin != null and (not neutral_id.is_empty() or not origin.valid_for(origin.committed_at)))):
		return false
	var key := "cause/%s" % origin.occurrence_key() if origin != null else "neutral/%s" % neutral_id
	if _influences.has(key):
		return false
	var entry := Influence.new()
	entry.origin = origin.copy() if origin != null else null
	entry.neutral_id = neutral_id
	if _resistance < 1.0:
		entry.x = (force.x / _mass) * (1.0 - _resistance)
		entry.y = (force.y / _mass) * (1.0 - _resistance)
		if not is_finite(entry.x) or not is_finite(entry.y):
			return false
	_influences[key] = entry
	if velocity() == null:
		_influences.erase(key)
		return false
	return true


func velocity() -> RealmSweep.Point:
	var x := 0.0
	var y := 0.0
	for key: String in _ordered_keys():
		var entry := _influences[key]
		x += entry.x
		y += entry.y
	if not is_finite(x) or not is_finite(y):
		return null
	return RealmSweep.Point.new(x, y)


## The authored loss factor applies uniformly to the remaining influences.
func attenuate(factor: float) -> bool:
	if not is_finite(factor) or factor < 0.0 or factor > 1.0:
		return false
	for key: String in _influences.keys():
		var entry := _influences[key]
		entry.x *= factor
		entry.y *= factor
		if entry.x == 0.0 and entry.y == 0.0:
			_influences.erase(key)
	return true


func separate(entity: StringName, slot: int) -> bool:
	return _contacts.erase(RealmSpatialIndex.shape_key(entity, slot))


func refresh_contacts(near: RealmGeometry.SweepCandidates) -> void:
	var remaining: Dictionary[StringName, bool] = {}
	for hits: Array[RealmGeometry.Contact] in [near.contacts, near.unresolved]:
		for hit: RealmGeometry.Contact in hits:
			var key := RealmSpatialIndex.shape_key(hit.entity, hit.shape)
			if _contacts.has(key):
				remaining[key] = true
	_contacts = remaining


## The normal points from this body toward the other surface. An absent
## other body is immovable. Effects and HP damage are authored separately.
func contact(entity: StringName, slot: int, normal: RealmSweep.Point, minimum_speed: float, other: WorldMomentum = null) -> Impact:
	if (entity.is_empty() or slot < 0 or normal == null or other == self
			or not is_finite(minimum_speed) or minimum_speed <= 0.0):
		return null
	var key := RealmSpatialIndex.shape_key(entity, slot)
	if _contacts.has(key):
		return null
	var largest := maxf(absf(normal.x), absf(normal.y))
	if largest == 0.0 or not is_finite(largest) or not is_finite(normal.x) or not is_finite(normal.y):
		return null
	var nx := normal.x / largest
	var ny := normal.y / largest
	var length := sqrt(nx * nx + ny * ny)
	nx /= length
	ny /= length
	_contacts[key] = true
	var projected: Dictionary[String, float] = {}
	var causes: Dictionary[String, Influence] = {}
	_project(nx, ny, projected, causes)
	var reduced_mass := _mass
	if other != null:
		other._project(-nx, -ny, projected, causes)
		var light := minf(_mass, other._mass)
		reduced_mass = light / (1.0 + light / maxf(_mass, other._mass))
	var keys := projected.keys()
	keys.sort()
	var approach := 0.0
	var strongest := 0.0
	var primary: Influence
	var result := Impact.new()
	for source: String in keys:
		var contribution := projected[source]
		approach += contribution
		if contribution > 0.0 and causes[source].origin != null:
			result.participants.append(causes[source].origin.copy())
		if contribution > strongest:
			strongest = contribution
			primary = causes[source]
	if primary == null or approach < minimum_speed or not is_finite(approach):
		return null
	result.approach_speed = approach
	result.strength = (0.5 * reduced_mass * approach) * approach
	if not is_finite(result.strength):
		return null
	result.primary = primary.origin.copy() if primary.origin != null else null
	result.neutral_cause = primary.neutral_id
	return result


func _ordered_keys() -> Array[String]:
	var keys := _influences.keys()
	keys.sort()
	return keys


func _project(nx: float, ny: float, projected: Dictionary[String, float], causes: Dictionary[String, Influence]) -> void:
	for key: String in _ordered_keys():
		var entry := _influences[key]
		var value: float = projected.get(key, 0.0)
		projected[key] = value + entry.x * nx + entry.y * ny
		causes[key] = entry
