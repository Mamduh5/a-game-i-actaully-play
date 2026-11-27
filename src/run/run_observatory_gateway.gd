class_name RunObservatoryGateway
extends RefCounted
## Host-owned PR04 mechanism and the local projection used by its presentation.

const INSCRIPTION := &"observatory/inscription"
const WEST_CONDUIT := &"observatory/west_conduit"
const EAST_CONDUIT := &"observatory/east_conduit"
const GATE := &"observatory/early_gateway"
const REACH := 36.0
const PICK_RADIUS := 10.0
const VIEW_RANGE := 88.0

class Mark:
	var id: StringName
	var position: RealmSweep.Point
	var direction: Vector2i
	var inscription: String

var _authority: RunAuthority
var _party: RunParty
var _world: WorldExploration
var _arena: RealmGeometry
var _progression: PartyProgression
var _arrivals: Dictionary[StringName, RealmSweep.Point] = {}
var _points: Dictionary[StringName, RealmSweep.Point] = {}
var _headings: Dictionary[StringName, int] = {WEST_CONDUIT: 0, EAST_CONDUIT: 0}
var _turn_tick: int
var _turns: Array[Dictionary] = []


static func register(authority: RunAuthority, party: RunParty, world: WorldExploration,
		arena: RealmGeometry, arrivals: Dictionary[StringName, RealmSweep.Point],
		progression: PartyProgression) -> RunObservatoryGateway:
	if (authority == null or party == null or world == null or progression == null
			or not party.owns_geometry(world.geometry()) or not authority.matches_world_seed(world.layout_seed())
			or arena == null or arena.realm_id != RunSetup.FINAL_REALM or arrivals.size() != party.initialized_seats().size()):
		return null
	var center := world.early_observatory_center()
	if center == null:
		return null
	var gate := RunObservatoryGateway.new()
	for seat: StringName in party.initialized_seats():
		var point: RealmSweep.Point = arrivals.get(seat)
		if point == null or not is_finite(point.x) or not is_finite(point.y):
			return null
		gate._arrivals[seat] = PlayerControlState.copy_point(point)
	gate._points = {
		INSCRIPTION: RealmSweep.Point.new(center.x, center.y - 56.0),
		WEST_CONDUIT: RealmSweep.Point.new(center.x - 52.0, center.y),
		EAST_CONDUIT: RealmSweep.Point.new(center.x + 52.0, center.y),
		GATE: center,
	}
	var reserved: Array[StringName] = []
	for id: StringName in gate._points:
		if not world.reserve_route_approach(id, gate._points[id], true):
			for prior: StringName in reserved:
				world.release_route_approach(prior)
			return null
		reserved.append(id)
	gate._authority = authority
	gate._party = party
	gate._world = world
	gate._arena = arena
	gate._progression = progression
	return gate


## The inscription and current directions are ordinary visible world clues.
## The aligned gate is disclosed only to seats with local sight before 25:00.
func view_for(seat: StringName) -> Array[Mark]:
	var marks: Array[Mark] = []
	var entrant := _entrant(seat)
	if entrant == null:
		return marks
	for id: StringName in _points:
		if id == GATE and not _can_enter_now():
			continue
		var at := _points[id]
		if (at.x - entrant.position.x) ** 2 + (at.y - entrant.position.y) ** 2 > VIEW_RANGE ** 2:
			continue
		if not _clear_sight(entrant.position, at):
			continue
		var mark := Mark.new()
		mark.id = id
		mark.position = PlayerControlState.copy_point(at)
		if _headings.has(id):
			mark.direction = WorldTopology.CARDINAL[_headings[id]]
		elif id == INSCRIPTION:
			mark.inscription = "The gateway opens when the two conduits face each other."
		marks.append(mark)
	return marks


func turn(intent: RunIntent) -> bool:
	if _authority == null or _aligned() or not _authority.accepted_interaction(intent, _party):
		return false
	var conduit := _pick(intent, [WEST_CONDUIT, EAST_CONDUIT])
	if conduit.is_empty():
		return false
	if _turn_tick != intent.tick:
		_turn_tick = intent.tick
		_turns.clear()
	var receipt := intent.receipt()
	if receipt in _turns:
		return false
	_turns.append(receipt)
	_headings[conduit] = (_headings[conduit] + 1) % WorldTopology.CARDINAL.size()
	return true


func enter(intent: RunIntent) -> RunAuthority.GatewayResult:
	if _authority == null:
		return RunAuthority.GatewayResult.REFUSED
	return _authority.request_gateway(intent, _party, _arena, _arrivals, _progression, self)


## The authority checks the admitted receipt and run epoch separately.
func permits_entry(authority: RunAuthority, party: RunParty, intent: RunIntent) -> bool:
	return (_authority != null and authority == _authority and party == _party and intent != null
		and intent.realm_id == WorldTopology.OVERWORLD and intent.action == PlayerCommand.INTERACT and intent.valid_payload()
		and intent.tick == _party.closed_tick and _can_enter_now() and _pick(intent, [GATE]) == GATE)


## The same-build authority and progression images each retain the early tick.
static func valid_early_tick(seed: int, entry: Variant, closed: int) -> bool:
	return (entry is int and entry > 0 and entry <= closed and entry < RunParty.COLLAPSE_TICK
		and WorldTopology.generate(seed).has_early_observatory())


func _aligned() -> bool:
	return _headings[WEST_CONDUIT] == 1 and _headings[EAST_CONDUIT] == 3


func _can_enter_now() -> bool:
	return _aligned() and _party.closed_tick < RunParty.COLLAPSE_TICK


func _entrant(seat: StringName) -> RunParty.View:
	if (_party == null or _party.closed_tick != _authority.next_tick() - 1 or not _party.can_control(seat)):
		return null
	var entrant := _party.view(seat, CombatInstant.at_tick(_party.closed_tick))
	if (entrant == null or entrant.realm != WorldTopology.OVERWORLD
			or _world.module_at(entrant.position) != WorldTopology.OBSERVATORY):
		return null
	return entrant


func _pick(intent: RunIntent, ids: Array[StringName]) -> StringName:
	var entrant := _entrant(intent.seat_id)
	if entrant == null or entrant.realm != intent.realm_id:
		return &""
	var candidates: Array[PlayerTargeting.Candidate] = []
	for id: StringName in ids:
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = id
		candidate.kind = PlayerTargeting.Kind.MECHANISM
		candidate.position = _points[id]
		candidate.pick_radius = PICK_RADIUS
		candidate.known = true
		candidate.interactable = true
		candidates.append(candidate)
	var cursor := RealmSweep.Point.new(intent.command.x, intent.command.y)
	var picked := PlayerTargeting.new().interact(entrant.position, cursor, REACH, candidates)
	return picked if not picked.is_empty() and _clear_sight(entrant.position, _points[picked]) else &""


func _clear_sight(from: RealmSweep.Point, at: RealmSweep.Point) -> bool:
	var floor := _world.geometry()
	var sight := floor.certify_frozen_path(floor.realm_id, from, at, 0.0, WorldExploration.BLOCKER)
	return sight != null and sight.contacts.is_empty() and sight.unresolved.is_empty()
