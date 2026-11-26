class_name WorldActivity
extends RefCounted
## Host-side world work. A registered realm steps on every authoritative
## tick. Observer state has no input to spawning, decisions or delivery.

const ACTORS := 2

class SpawnSite:
	var id: StringName
	var realm: StringName
	var rules: WorldEnemy.Rules
	var positions: Array[RealmSweep.Point] = []
	var first_tick: int
	var period: int
	var limit: int

class Schedule:
	var site: SpawnSite
	var next: int
	var members: Array[StringName] = []

class Frame:
	var tick: int
	var spawns: Array[Array] = []
	var combat: Array[CombatKernel.WaveResult] = []
	var terminal: CombatKernel.Terminal

var _kernel: CombatKernel
var _random: RunRandom
var _realms: Dictionary[StringName, WorldExploration] = {}
var _enemies: Dictionary[StringName, WorldEnemy] = {}
var _players: Dictionary[StringName, bool] = {}
var _sites: Dictionary[StringName, Schedule] = {}
var _defeated_lives: Dictionary[StringName, int] = {}
var _frame: Frame
var _decisions_opened := false
var _tick: int
var _fault: StringName
var _terminal: CombatKernel.Terminal


func _init(kernel: CombatKernel, seed_value: int) -> void:
	_kernel = kernel
	_random = RunRandom.new(seed_value)


func register_realm(exploration: WorldExploration) -> bool:
	if (_kernel == null or exploration == null or exploration.geometry() == null
			or _frame != null or not _fault.is_empty()):
		return false
	var geometry := exploration.geometry()
	if _realms.has(geometry.realm_id) or not _kernel.attach_geometry(geometry, WorldExploration.BLOCKER):
		return false
	_realms[geometry.realm_id] = exploration
	return true


func track_player(id: StringName) -> bool:
	if _kernel == null or _enemies.has(id) or _players.has(id) or _frame != null:
		return false
	var actor := _kernel.actor_snapshot(id)
	if actor == null or actor.provenance != CombatOrigin.Provenance.SEAT or not actor.controller.is_empty():
		return false
	var realm: WorldExploration = _realms.get(actor.realm)
	if realm == null or realm.geometry().circle_center(id, 0) == null:
		return false
	_players[id] = true
	return true


func introduce_enemy(id: StringName, realm: StringName, rules: WorldEnemy.Rules, at: RealmSweep.Point) -> bool:
	return _frame == null and _fault.is_empty() and _spawn(id, realm, rules, at)


## An authorized resurrection names the specific closed corpse. Retain
## faction, stable spawn identity and any old paid delivery.
func reanimate(id: StringName, life: int, fraction: Quantity, recovery_ticks: int) -> bool:
	if (_frame != null or not _fault.is_empty() or _tick == 0 or not _enemies.has(id)
			or _defeated_lives.get(id, 0) != life or recovery_ticks <= 0
			or recovery_ticks > RunAuthority.MAX_TICK - _tick):
		return false
	if not _kernel.reanimate_spawn(id, life, CombatInstant.at_tick(_tick), fraction):
		return false
	_enemies[id].start_reanimated_life(_tick + recovery_ticks)
	return true


func schedule_spawn(site: SpawnSite) -> bool:
	if (site == null or site.id.is_empty() or _sites.has(site.id) or not _realms.has(site.realm)
			or site.first_tick <= _tick or site.first_tick > RunAuthority.MAX_TICK or site.period <= 0
			or site.limit <= 0 or site.rules == null or not site.rules.is_valid() or site.positions.is_empty()
			or _frame != null or not _fault.is_empty()):
		return false
	var saved := SpawnSite.new()
	saved.id = site.id
	saved.realm = site.realm
	saved.rules = site.rules.copy()
	saved.first_tick = site.first_tick
	saved.period = site.period
	saved.limit = site.limit
	for point: RealmSweep.Point in site.positions:
		if _realms[site.realm].module_at(point).is_empty():
			return false
		saved.positions.append(RealmSweep.Point.new(point.x, point.y))
	var schedule := Schedule.new()
	schedule.site = saved
	schedule.next = saved.first_tick
	_sites[site.id] = schedule
	return true


## A caller retains its open input cursor across a storage wait. Resume with
## the same tick to avoid redoing decisions, releases and spawn opportunities.
func advance(tick: int, authority: RunAuthority = null) -> Frame:
	if (_kernel == null or not _fault.is_empty() or tick != _tick + 1 or tick > RunAuthority.MAX_TICK
			or _terminal != CombatKernel.Terminal.ACTIVE
			or (authority != null and not authority.can_open_earning_group())):
		return null
	var now := CombatInstant.at_tick(tick)
	if _frame == null:
		_frame = Frame.new()
		_frame.tick = tick
	if not _decisions_opened:
		if not _drain(now, authority, false):
			return null
		if _frame.terminal != CombatKernel.Terminal.ACTIVE:
			return _finish_frame(tick)
		_spawn_due(tick)
		var likeness := _subjects()
		var ids := _sorted(_enemies.keys())
		var due: Array[StringName] = []
		for id: StringName in ids:
			var place: WorldEnemy.Subject = likeness.get(id)
			if place == null or not _enemies[id].decide(_kernel, _realms[place.realm], likeness, tick):
				_fault = &"world_decision"
				return null
			if _enemies[id].release_due(tick):
				due.append(id)
		if not due.is_empty():
			likeness = _subjects()
		for id: StringName in due:
			var place: WorldEnemy.Subject = likeness.get(id)
			if place == null or not _enemies[id].release(_realms[place.realm].geometry(),
					likeness, tick, WorldExploration.BLOCKER, ACTORS):
				_fault = &"world_delivery"
				return null
		_decisions_opened = true
	if not _drain(now, authority, true):
		return null
	var expiry := _kernel.advance_survival(now)
	if expiry.result == CombatKernel.Result.INTERRUPTED:
		_fault = expiry.fault
		return null
	if expiry.result == CombatKernel.Result.CLOSED and not expiry.ended_barriers.is_empty():
		_frame.combat.append(expiry)
	return _finish_frame(tick)


func _finish_frame(tick: int) -> Frame:
	_tick = tick
	var result := _frame
	_terminal = result.terminal
	_frame = null
	_decisions_opened = false
	return result


func _drain(now: CombatInstant, authority: RunAuthority, inclusive: bool) -> bool:
	while true:
		var due := _kernel.next_due()
		if due == null:
			if _kernel.pending_count() > 0:
				_fault = &"world_combat_order"
				return false
			return true
		if not inclusive:
			match due.order_against(now):
				RealmCircleTime.Order.UNRESOLVED:
					_fault = &"world_combat_order"
					return false
				RealmCircleTime.Order.SAME, RealmCircleTime.Order.AFTER:
					return true
		var closed := _kernel.resolve_next(now, 8, authority)
		match closed.result:
			CombatKernel.Result.CLOSED:
				_frame.combat.append(closed)
				for hit: CombatKernel.Hit in closed.eliminations:
					if _enemies.has(hit.target):
						_defeated_lives[hit.target] = hit.target_life
				if closed.terminal != CombatKernel.Terminal.ACTIVE:
					_frame.terminal = closed.terminal
					return true
			CombatKernel.Result.WAITING, CombatKernel.Result.IDLE:
				return true
			CombatKernel.Result.YIELDED:
				continue
			CombatKernel.Result.STORAGE_WAIT:
				return false
			_:
				_fault = closed.fault
				return false
	return false


func fault() -> StringName:
	return _fault


## Host evidence image. A peer must receive a realm-filtered projection.
func snapshot() -> Dictionary:
	if _frame != null or not _fault.is_empty():
		return {}
	var actors: Dictionary[StringName, Array] = {}
	for subject: WorldEnemy.Subject in _subjects().values():
		var cap: Array = [] if subject.maximum == null else [subject.maximum.magnitude_text(), subject.maximum.scale]
		actors[subject.id] = [subject.realm, subject.life, subject.hp.magnitude_text(), subject.hp.scale,
			subject.at.x, subject.at.y, _realms[subject.realm].module_at(subject.at),
			_enemies[subject.id].state() if _enemies.has(subject.id) else [], cap]
	var sites: Dictionary[StringName, int] = {}
	for id: StringName in _sorted(_sites.keys()):
		sites[id] = _sites[id].next
	return {"tick": _tick, "actors": actors, "opportunities": sites, "rng": _random.checkpoint(),
		"defeated_lives": _defeated_lives.duplicate()}


func _spawn_due(tick: int) -> void:
	for id: StringName in _sorted(_sites.keys()):
		var plan := _sites[id]
		if plan.next != tick:
			continue
		var site := plan.site
		plan.next = tick + site.period if site.period <= RunAuthority.MAX_TICK - tick else -1
		var living := 0
		for member: StringName in plan.members:
			var actor := _kernel.actor_snapshot(member)
			if actor != null and actor.is_alive():
				living += 1
		if living >= site.limit:
			_frame.spawns.append([id, &"full"])
			continue
		var draw := _random.draw(StringName("world-spawn/%s" % id))
		var point := site.positions[draw % site.positions.size()]
		var spawned := StringName("spawn/%d:%s/%d" % [id.length(), id, tick])
		if _spawn(spawned, site.realm, site.rules, point):
			plan.members.append(spawned)
			_frame.spawns.append([id, spawned])
		else:
			_frame.spawns.append([id, &"no_clearance"])


func _spawn(id: StringName, realm: StringName, rules: WorldEnemy.Rules, at: RealmSweep.Point) -> bool:
	if (_kernel == null or id.is_empty() or _kernel.actor_snapshot(id) != null or rules == null
			or not rules.is_valid() or not _realms.has(realm) or _realms[realm].module_at(at).is_empty()):
		return false
	var geometry := _realms[realm].geometry()
	var room := geometry.certify_circle_snapshot(realm, at, rules.radius, WorldExploration.BLOCKER | ACTORS)
	if room == null or not room.unresolved.is_empty():
		return false
	for contact: RealmGeometry.Contact in room.contacts:
		if contact.category & WorldExploration.BLOCKER:
			return false
		var occupant := _kernel.actor_snapshot(contact.entity)
		if occupant == null or occupant.is_alive():
			return false
	if not geometry.add_circle(id, 0, at, rules.radius, ACTORS):
		return false
	var actor := CombatantState.new()
	actor.id = id
	actor.owner = id
	actor.provenance = CombatOrigin.Provenance.SPAWN
	actor.realm = realm
	actor.life = 1
	actor.max_hp = rules.hp
	actor.hp = QuantityLayerLedger.Pool.new(rules.hp, QuantityErrorBounds.new())
	if not _kernel.add_actor(actor):
		geometry.remove_mutable(id, 0)
		return false
	_enemies[id] = WorldEnemy.new(id, rules)
	return true


func _subjects() -> Dictionary[StringName, WorldEnemy.Subject]:
	var result: Dictionary[StringName, WorldEnemy.Subject] = {}
	var ids := _enemies.keys()
	ids.append_array(_players.keys())
	for id: StringName in _sorted(ids):
		var actor := _kernel.actor_snapshot(id)
		if actor == null or not _realms.has(actor.realm):
			continue
		var at := _realms[actor.realm].geometry().circle_center(id, 0)
		if at == null:
			continue
		var subject := WorldEnemy.Subject.new()
		subject.id = id
		subject.realm = actor.realm
		subject.at = at
		subject.life = actor.life
		subject.hp = actor.hp.amount
		subject.maximum = actor.max_hp
		subject.faction = _enemies[id].faction() if _enemies.has(id) else WorldEnemy.PARTY
		result[id] = subject
	return result


static func _sorted(keys: Array[StringName]) -> Array[StringName]:
	keys.sort_custom(func(first: StringName, second: StringName) -> bool: return String(first) < String(second))
	return keys
