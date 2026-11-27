class_name RunFinalGateway
extends RefCounted
## Normal gateway interaction over the generated Overworld landmark. The
## authority supplies the arena floor and arrival layout, never the peer.

var _authority: RunAuthority
var _party: RunParty
var _progression: PartyProgression
var _floor: RealmGeometry
var _arena: RealmGeometry
var _handle: PlayerTargeting.Candidate
var _reach: float
var _arrivals: Dictionary[StringName, RealmSweep.Point] = {}


static func register(authority: RunAuthority, party: RunParty, world: WorldExploration, arena: RealmGeometry,
		arrivals: Dictionary[StringName, RealmSweep.Point], reach: float, pick_radius: float,
		progression: PartyProgression) -> RunFinalGateway:
	if (authority == null or party == null or progression == null or world == null
			or not party.owns_geometry(world.geometry()) or world.geometry().realm_id != WorldTopology.OVERWORLD
			or arena == null or arena.realm_id != RunSetup.FINAL_REALM or arrivals.size() != party.initialized_seats().size()
			or reach <= 0.0 or not is_finite(reach) or pick_radius <= 0.0 or not is_finite(pick_radius)):
		return null
	var gateway := RunFinalGateway.new()
	for seat: StringName in party.initialized_seats():
		var at := arrivals.get(seat) as RealmSweep.Point
		if at == null or not is_finite(at.x) or not is_finite(at.y):
			return null
		gateway._arrivals[seat] = PlayerControlState.copy_point(at)
	var at := world.module_center(WorldTopology.GATEWAY)
	if at == null or not world.reserve_route_approach(WorldTopology.GATEWAY, at):
		return null
	gateway._authority = authority
	gateway._party = party
	gateway._progression = progression
	gateway._floor = world.geometry()
	gateway._arena = arena
	gateway._reach = reach
	gateway._handle = PlayerTargeting.Candidate.new()
	gateway._handle.id = WorldTopology.GATEWAY
	gateway._handle.kind = PlayerTargeting.Kind.MECHANISM
	gateway._handle.position = at
	gateway._handle.pick_radius = pick_radius
	gateway._handle.interactable = true
	gateway._handle.known = true
	return gateway


## The map can show this position after the closed Collapse boundary.
func revealed_location() -> RealmSweep.Point:
	if _authority.next_tick() <= RunParty.COLLAPSE_TICK or not _party.has_realm(_floor.realm_id):
		return null
	return PlayerControlState.copy_point(_handle.position)


func interact(intent: RunIntent) -> RunAuthority.GatewayResult:
	if (intent == null or intent.tick < RunParty.COLLAPSE_TICK or intent.realm_id != _floor.realm_id
			or intent.action != PlayerCommand.INTERACT or not intent.valid_payload()):
		return RunAuthority.GatewayResult.REFUSED
	var entrant := _party.view(intent.seat_id, CombatInstant.at_tick(intent.tick))
	if entrant == null or entrant.realm != _floor.realm_id or not entrant.alive or not entrant.connected:
		return RunAuthority.GatewayResult.REFUSED
	var cursor := RealmSweep.Point.new(intent.command.x, intent.command.y)
	if PlayerTargeting.new().interact(entrant.position, cursor, _reach, [_handle]).is_empty():
		return RunAuthority.GatewayResult.REFUSED
	var sight := _floor.certify_frozen_path(_floor.realm_id, entrant.position, _handle.position, 0.0, WorldExploration.BLOCKER)
	if sight == null or not sight.contacts.is_empty() or not sight.unresolved.is_empty():
		return RunAuthority.GatewayResult.REFUSED
	return _authority.request_gateway(intent, _party, _arena, _arrivals, _progression)
