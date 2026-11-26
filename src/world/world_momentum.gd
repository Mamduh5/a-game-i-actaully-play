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
	var _normal_x: float
	var _normal_y: float
	var _mover: WorldMomentum
	var _receiver: WorldMomentum
	var _mover_revision: int
	var _receiver_revision: int
	var _transferred: bool

var _mass: float
var _resistance: float
var _influences: Dictionary[String, Influence] = {}
var _contacts: Dictionary[StringName, bool] = {}
var _revision: int


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
	_revision += 1
	return true


func velocity() -> RealmSweep.Point:
	return _velocity_with("", null)


func _velocity_with(replaced: String, replacement: Influence) -> RealmSweep.Point:
	var x := 0.0
	var y := 0.0
	var keys := _ordered_keys()
	if replacement != null and not _influences.has(replaced):
		keys.append(replaced)
		keys.sort()
	for key: String in keys:
		var entry := replacement if key == replaced else _influences[key]
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
	_revision += 1
	return true


func separate(entity: StringName, slot: int) -> bool:
	if not _contacts.erase(RealmSpatialIndex.shape_key(entity, slot)):
		return false
	_revision += 1
	return true


func refresh_contacts(near: RealmGeometry.SweepCandidates) -> void:
	var remaining: Dictionary[StringName, bool] = {}
	for hits: Array[RealmGeometry.Contact] in [near.contacts, near.unresolved]:
		for hit: RealmGeometry.Contact in hits:
			var key := RealmSpatialIndex.shape_key(hit.entity, hit.shape)
			if _contacts.has(key):
				remaining[key] = true
	if remaining.size() != _contacts.size():
		_revision += 1
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
	result._normal_x = nx
	result._normal_y = ny
	result._mover = self
	result._receiver = other
	result._mover_revision = _revision
	result._receiver_revision = other._revision if other != null else -1
	return result


## Apply a passive normal impulse for an isolated pair. Each body uses its
## own displacement resistance. Attribution follows the impact.
func transfer(impact: Impact, mover_id: StringName, mover_shape: int, restitution: float) -> bool:
	if (impact == null or impact._mover != self or impact._receiver == null or impact._transferred
			or impact._mover_revision != _revision or impact._receiver_revision != impact._receiver._revision
			or mover_id.is_empty() or mover_shape < 0 or not is_finite(restitution)
			or restitution < 0.0 or restitution > 1.0):
		return false
	var receiver := impact._receiver
	var mass_ratio := minf(_mass, receiver._mass) / maxf(_mass, receiver._mass)
	var light_share := 1.0 / (1.0 + mass_ratio)
	var heavy_share := mass_ratio * light_share
	var mover_share := light_share if _mass <= receiver._mass else heavy_share
	var receiver_share := heavy_share if _mass <= receiver._mass else light_share
	var mover_mobility := 1.0 - _resistance
	var receiver_mobility := 1.0 - receiver._resistance
	var mover_velocity := velocity()
	var receiver_velocity := receiver.velocity()
	var mover_normal := mover_velocity.x * impact._normal_x + mover_velocity.y * impact._normal_y
	var receiver_normal := receiver_velocity.x * impact._normal_x + receiver_velocity.y * impact._normal_y
	var weighted_approach := mover_mobility * mover_normal - receiver_mobility * receiver_normal
	var normal_change := impact.approach_speed * (1.0 + restitution)
	if not is_finite(weighted_approach) or not is_finite(normal_change):
		return false
	# Asymmetric resistance can accelerate both bodies' center of mass. Limit
	# the impulse where its quadratic kinetic cost overtakes its linear loss.
	var kinetic_cost := mover_share * mover_mobility ** 2 + receiver_share * receiver_mobility ** 2
	if weighted_approach <= 0.0:
		normal_change = 0.0
	elif (normal_change * 0.5) * kinetic_cost > weighted_approach:
		normal_change = 2.0 * (weighted_approach / kinetic_cost)
	var mover_change := -normal_change * mover_share * mover_mobility
	var receiver_change := normal_change * receiver_share * receiver_mobility
	var key := "cause/%s" % impact.primary.occurrence_key() if impact.primary != null else "neutral/%s" % impact.neutral_cause
	var mover_post := _adjusted_influence(key, impact, mover_change)
	var receiver_post := receiver._adjusted_influence(key, impact, receiver_change)
	if mover_post == null or receiver_post == null:
		return false
	_influences[key] = mover_post
	receiver._influences[key] = receiver_post
	_revision += 1
	receiver._revision += 1
	receiver._contacts[RealmSpatialIndex.shape_key(mover_id, mover_shape)] = true
	impact._transferred = true
	return true


func _adjusted_influence(key: String, impact: Impact, normal_change: float) -> Influence:
	var previous: Influence = _influences.get(key)
	var result := Influence.new()
	result.origin = impact.primary.copy() if impact.primary != null else null
	result.neutral_id = impact.neutral_cause
	var dx := normal_change * impact._normal_x
	var dy := normal_change * impact._normal_y
	result.x = (previous.x if previous != null else 0.0) + dx
	result.y = (previous.y if previous != null else 0.0) + dy
	if not is_finite(result.x) or not is_finite(result.y) or _velocity_with(key, result) == null:
		return null
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
