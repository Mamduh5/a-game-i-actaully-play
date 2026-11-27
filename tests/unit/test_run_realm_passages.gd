extends GutTest

const Host := &"host"
const Guest := &"guest"
const Source := WorldTopology.OVERWORLD
const Admission := RunAuthority.Admission

class TravelAuthority extends RunAuthority:
	var party: RunParty
	var activity: WorldActivity
	var closed_party := false
	var interactions: Array[RunIntent] = []

	func _supports_action(action: StringName) -> bool:
		return action in [PlayerCommand.INTERACT, PlayerCommand.MOVE_TO]

	func _resolve_tick(tick: int, accepted: Array[RunIntent], _streams: RunRandom) -> Array[Dictionary]:
		interactions.clear()
		for intent: RunIntent in accepted:
			if intent.action == PlayerCommand.MOVE_TO:
				party.apply_input(intent.seat_id, intent.command)
			elif intent.action == PlayerCommand.INTERACT:
				interactions.append(intent)
		for seat: StringName in party.initialized_seats():
			party.step_movement(seat, 6000.0, 1.0 / 60.0)
		closed_party = (activity == null or activity.advance(tick) != null) and party.close_tick(tick)
		return []

class Route:
	const Seed := 2507
	var outer := WorldExploration.create(WorldTopology.generate(Seed), [Host, Guest])
	var inner: WorldExploration
	var kernel := CombatKernel.new()
	var setup := RunSetup.new()
	var party: RunParty
	var authority := TravelAuthority.new()
	var passages: RunRealmPassages
	var handle := outer.module_center(WorldTopology.ANCHORS[0])
	var sequence: int

	func _init(realm: StringName) -> void:
		inner = WorldExploration.create(WorldTopology.generate_optional(Seed, realm), [Host, Guest])

	func begin() -> bool:
		setup.run_id = &"passage-test"
		setup.authority_id = Host
		setup.initial_realms = {Host: Source, Guest: Source}
		setup.epoch = 1
		setup.seed = Seed
		setup.role = RunSetup.Role.HOST
		setup.rules_revision = &"V42.6/R1"
		setup.catalog_revision = &"starter"
		setup.challenge_id = &"normal"
		var realms: Dictionary[StringName, RealmGeometry] = {
			Source: outer.geometry(), inner.geometry().realm_id: inner.geometry(),
		}
		for geometry: RealmGeometry in realms.values():
			if not kernel.attach_geometry(geometry, WorldExploration.BLOCKER):
				return false
		if not _add_actor(Host, Source, offset(handle, -96, 0), 20, CombatOrigin.Provenance.SEAT):
			return false
		if not _add_actor(Guest, Source, offset(handle, 8, -10), 20, CombatOrigin.Provenance.SEAT):
			return false
		party = RunParty.begin(setup, Host, kernel, realms, {Host: Host, Guest: Guest}, WorldExploration.BLOCKER)
		authority.party = party
		if party == null or not authority.start(setup, Host):
			return false
		passages = RunRealmPassages.new(authority, party)
		return passages.register_optional(&"test/entry", outer, handle, inner, 36.0, 10.0)

	func input(seat: StringName, action: StringName, point: RealmSweep.Point) -> RunIntent:
		sequence += 1
		var tick := authority.next_tick()
		var state := party.view(seat, CombatInstant.at_tick(tick))
		return RunIntent.new(setup.run_id, setup.epoch, state.realm, seat, tick, sequence,
			action, PlayerCommand.new(action, point.x, point.y))

	func submit(intent: RunIntent) -> bool:
		return (authority.submit(intent.seat_id, intent) == Admission.QUEUED
			and authority.close_tick() and authority.closed_party)

	func walk_to_exit(seat: StringName) -> bool:
		var exit := inner.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
		if exit.is_empty():
			return false
		for waypoint: RealmSweep.Point in exit:
			if not submit(input(seat, PlayerCommand.MOVE_TO, waypoint)):
				return false
		var desired: RealmSweep.Point = exit.back()
		var landed := party.view(seat, CombatInstant.at_tick(authority.next_tick() - 1)).position
		return landed.x == desired.x and landed.y == desired.y

	func _add_actor(id: StringName, realm: StringName, at: RealmSweep.Point, life_hp: int,
			kind: CombatOrigin.Provenance) -> bool:
		var actor := CombatantState.new()
		actor.id = id
		actor.owner = id
		actor.realm = realm
		actor.life = 1
		actor.provenance = kind
		actor.max_hp = Quantity.from_count(life_hp)
		actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
		actor.resources[&"mana"] = Quantity.from_count(7)
		var room := outer if realm == Source else inner
		return kernel.add_actor(actor) and room.geometry().add_circle(id, 0, at, 4, 2)

	func add_sentinel(realm: StringName, point: RealmSweep.Point) -> bool:
		return _add_actor(&"sentinel", realm, point, 100, CombatOrigin.Provenance.SPAWN)

	func admit_sentinel_hit(target: StringName, due_at: int) -> bool:
		var actor := kernel.actor_snapshot(target)
		var floor := outer.geometry() if actor.realm == Source else inner.geometry()
		var pose := floor.circle_center(target, 0)
		var swept := floor.certify_circle_snapshot(actor.realm, pose, 0.0, 2)
		for contact: RealmGeometry.Contact in swept.contacts:
			if contact.entity != target:
				continue
			var action := CombatAction.new()
			action.source = &"sentinel"
			action.source_life = 1
			action.family = &"fixture"
			action.origin = CombatOrigin.new()
			action.origin.provenance = CombatOrigin.Provenance.SPAWN
			action.origin.owner = action.source
			action.origin.activation = 1
			action.origin.committed_at = CombatInstant.at_tick(authority.next_tick())
			var part := CombatAction.Component.new()
			part.base = Quantity.from_count(20)
			action.components = [part]
			var delivery := CombatDelivery.activate(kernel, action, actor.realm)
			return (delivery != null and delivery.admit(due_at, contact, actor.life, true)
				== CombatDelivery.Result.ADMITTED and delivery.finish())
		return false

	static func offset(center: RealmSweep.Point, x: float, y: float) -> RealmSweep.Point:
		return RealmSweep.Point.new(center.x + x, center.y + y)


func test_native_click_closes_with_equal_sequence_movement_and_enters_only_its_seat() -> void:
	var realm := WorldTopology.OPTIONAL_REALMS[0]
	var route := Route.new(realm)
	assert_true(route.begin())
	var bridge := HostMovementBridge.new(route.authority)
	assert_true(bridge.bind(1, 10, 1, route.setup.run_id, 1, Source, Guest, 1))
	var click := _native_click(route.handle, 10, 1, 1)
	var step := Route.offset(route.handle, 5, -8)
	var move := _native_move(step, 10, 1, 1)
	assert_eq(bridge.submit_interaction(click), Admission.QUEUED)
	assert_eq(bridge.submit_interaction(click), Admission.DUPLICATE)
	assert_eq(bridge.submit(route.authority, move), Admission.QUEUED)
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_party)
	var receipts: Array = route.authority.closed_result()["accepted"]
	assert_eq(receipts.size(), 2)
	assert_false(receipts[0].has("reliable"))
	assert_true(receipts[1]["reliable"])
	assert_eq(bridge.submit_interaction(click), Admission.STALE_SEQUENCE)
	assert_eq(route.authority.checkpoint()["sequences"][Guest], 1)
	assert_eq(route.party.view(Guest, CombatInstant.at_tick(1)).position.x, step.x)
	assert_true(route.passages.interact(route.authority.interactions[0]))
	assert_false(route.passages.interact(route.authority.interactions[0]))
	assert_eq(route.party.view(Host, CombatInstant.at_tick(1)).realm, Source)
	assert_eq(route.party.view(Guest, CombatInstant.at_tick(1)).realm, realm)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, 2)), Admission.WRONG_REALM)
	assert_eq(bridge.submit(route.authority, _native_move(step, 10, 1, 2)), Admission.WRONG_REALM)
	assert_true(bridge.bind(1, 10, 1, route.setup.run_id, 1, realm, Guest, 2))
	assert_ne(bridge.submit_interaction(_native_click(route.handle, 10, 1, 2)), Admission.QUEUED)
	assert_eq(bridge.submit(route.authority, _native_move(step, 10, 1, 2)), Admission.WRONG_REALM)


func test_rebinding_or_detaching_retires_pending_reliable_clicks_and_preserves_movement_frontier() -> void:
	var route := Route.new(WorldTopology.OPTIONAL_REALMS[0])
	assert_true(route.begin())
	var bridge := HostMovementBridge.new(route.authority)
	assert_true(bridge.bind(1, 10, 1, route.setup.run_id, 1, Source, Guest, 1))
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, 70)), Admission.QUEUED)
	assert_eq(bridge.submit(route.authority, _native_move(route.handle, 10, 1, 2)), Admission.QUEUED)
	assert_true(route.authority.close_tick())
	assert_eq(route.authority.interactions.size(), 1)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, 71)), Admission.QUEUED)
	assert_true(bridge.bind(1, 11, 1, route.setup.run_id, 1, Source, Guest, 2))
	bridge.unbind(1, 10, 1)
	assert_ne(bridge.submit_interaction(_native_click(route.handle, 10, 1, 72)), Admission.QUEUED)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 11, 2, 1)), Admission.QUEUED)
	assert_eq(bridge.submit(route.authority, _native_move(route.handle, 11, 2, 2)), Admission.STALE_SEQUENCE)
	assert_true(route.authority.close_tick())
	assert_eq(route.authority.interactions.size(), 1)
	assert_eq(route.authority.interactions[0].sequence, 1)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 11, 2, 2)), Admission.QUEUED)
	bridge.unbind(1, 11, 1)
	assert_true(route.authority.close_tick())
	assert_true(route.authority.interactions.is_empty())
	assert_eq(route.authority.checkpoint()["sequences"][Guest], 2)


func test_reliable_and_sequenced_inputs_share_the_open_seat_quota() -> void:
	var route := Route.new(WorldTopology.OPTIONAL_REALMS[0])
	assert_true(route.begin())
	var bridge := HostMovementBridge.new(route.authority)
	assert_true(bridge.bind(1, 10, 1, route.setup.run_id, 1, Source, Guest, 1))
	assert_eq(bridge.submit(route.authority, _native_move(route.handle, 10, 1, 1)), Admission.QUEUED)
	var limit := RunAuthority.MAX_OPEN_INTENTS_PER_SEAT
	for sequence: int in range(1, limit):
		assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, sequence)), Admission.QUEUED)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, limit)), Admission.QUEUE_FULL)
	assert_true(route.authority.close_tick())
	assert_eq(route.authority.closed_result()["overflowed"], [Guest])
	assert_true(route.authority.closed_result()["accepted"].is_empty())
	assert_eq(route.authority.checkpoint()["sequences"][Guest], 0)
	assert_eq(bridge.submit(route.authority, _native_move(route.handle, 10, 1, 2)), Admission.QUEUED)
	assert_eq(bridge.submit_interaction(_native_click(route.handle, 10, 1, limit + 1)), Admission.QUEUED)


static func _native_click(at: RealmSweep.Point, connection: int, baseline: int, sequence: int) -> NativeSessionHost.Command:
	var click := PlayerCommand.new(PlayerCommand.INTERACT, at.x, at.y)
	return _native_packet(ReplicationMessage.Kind.INTERACTION, RealmInteractionFrame.pack(1, baseline, click),
		connection, sequence)


static func _native_move(at: RealmSweep.Point, connection: int, baseline: int, sequence: int) -> NativeSessionHost.Command:
	var move := PlayerCommand.new(PlayerCommand.MOVE_TO, at.x, at.y)
	return _native_packet(ReplicationMessage.Kind.MOVEMENT, MovementFrame.pack(1, baseline, sequence, move),
		connection, sequence)


static func _native_packet(kind: ReplicationMessage.Kind, payload: PackedByteArray, connection: int,
		sequence: int) -> NativeSessionHost.Command:
	var lane := ReplicationMessage.transport_kind(kind)
	var result := NativeSessionHost.Command.new()
	result.connection = connection
	result.seat = 1
	result.frame = NativeSessionFrame.read(NativeSessionFrame.pack(lane, 1, sequence,
		ReplicationMessage.pack(kind, payload)), NativeSessionFrame.channel(lane))
	return result


func test_each_optional_realm_has_an_intentional_round_trip_and_keeps_party_clock() -> void:
	for space: StringName in WorldTopology.OPTIONAL_REALMS:
		var route := Route.new(space)
		assert_true(route.begin())
		assert_true(route.submit(route.input(Host, PlayerCommand.MOVE_TO, route.handle)))
		var entry := route.input(Host, PlayerCommand.INTERACT, route.handle)
		assert_false(route.passages.interact(entry))
		assert_true(route.submit(entry))
		assert_true(route.passages.interact(entry))
		var crossed := route.authority.next_tick()
		assert_false(route.passages.interact(entry))
		assert_eq(route.authority.next_tick(), crossed)
		var body := route.kernel.actor_snapshot(Host)
		assert_eq(body.realm, space)
		assert_eq(body.realm_visit, 1)
		assert_eq(body.resources[&"mana"].native_at_scale(0), 7)
		assert_null(route.outer.geometry().circle_center(Host, 0))
		assert_not_null(route.outer.geometry().circle_center(Guest, 0))
		assert_not_null(route.inner.geometry().circle_center(Host, 0))
		assert_eq(route.outer.view(Host).visible, [])
		assert_eq(route.inner.view(Host).visible.size(), 1)
		assert_eq(route.inner.view(Guest).visible, [])
		var restored := TravelAuthority.new()
		assert_true(restored.restore(route.setup, Host, route.authority.checkpoint()))
		var timed := route.input(Host, PlayerCommand.MOVE_TO, route.handle)
		assert_eq(restored.submit(Host, timed), Admission.QUEUED)
		assert_true(route.walk_to_exit(Host))
		var exit := route.input(Host, PlayerCommand.INTERACT, route.inner.module_center(WorldTopology.RETURN_EXIT))
		assert_true(route.submit(exit))
		assert_true(route.passages.interact(exit))
		assert_eq(route.kernel.actor_snapshot(Host).realm, Source)
		assert_eq(route.kernel.actor_snapshot(Host).realm_visit, 2)
		assert_eq(route.inner.view(Host).visible, [])
		assert_eq(route.outer.view(Host).visible.size(), 1)


func test_portal_requires_physical_reach_and_clears_the_players_old_queued_scope() -> void:
	var route := Route.new(&"silent_garden")
	assert_true(route.begin())
	var too_far := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(too_far))
	assert_false(route.passages.interact(too_far))
	assert_true(route.submit(route.input(Host, PlayerCommand.MOVE_TO, Route.offset(route.handle, -32, 0))))
	assert_true(route.outer.place_route_solid(&"screen", Route.offset(route.handle, -24, 0), 3))
	var blocked := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(blocked))
	assert_false(route.passages.interact(blocked))
	assert_eq(route.kernel.actor_snapshot(Host).realm_visit, 0)
	assert_true(route.outer.remove_route_solid(&"screen"))
	var admitted := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(admitted))
	var queued := route.input(Host, PlayerCommand.MOVE_TO, Route.offset(route.handle, 40, 0))
	assert_eq(route.authority.submit(Host, queued), Admission.QUEUED)
	assert_true(route.passages.interact(admitted))
	assert_eq(route.authority.submit(Host, queued), Admission.WRONG_REALM)
	queued.realm_id = &"silent_garden"
	assert_eq(route.authority.submit(Host, queued), Admission.STALE_SEQUENCE)
	assert_true(route.authority.close_tick())
	assert_eq(route.authority.closed_result().accepted.size(), 0)


func test_contact_from_an_old_visit_cannot_hit_the_same_life_after_return() -> void:
	var route := Route.new(&"fractured_beyond")
	assert_true(route.begin())
	assert_true(route.submit(route.input(Host, PlayerCommand.MOVE_TO, route.handle)))
	assert_true(route.add_sentinel(Source, Route.offset(route.handle, -24, 0)))
	assert_true(route.admit_sentinel_hit(Host, 80))
	var into_realm := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(into_realm))
	assert_true(route.passages.interact(into_realm))
	assert_true(route.walk_to_exit(Host))
	var leave := route.input(Host, PlayerCommand.INTERACT, route.inner.module_center(WorldTopology.RETURN_EXIT))
	assert_true(route.submit(leave))
	assert_true(route.passages.interact(leave))
	assert_lt(route.authority.next_tick(), 80)
	var late := route.kernel.resolve_next(CombatInstant.at_tick(80))
	assert_eq(late.result, CombatKernel.Result.CLOSED)
	assert_eq(late.hits.size(), 1)
	assert_false(late.hits[0].accepted)
	assert_eq(late.eliminations.size(), 0)
	assert_eq(route.kernel.actor_snapshot(Host).hp.amount.native_at_scale(0), 20)


func test_teammates_body_stays_in_its_realm_and_requires_physical_return_to_rescue() -> void:
	var route := Route.new(&"silent_garden")
	assert_true(route.begin())
	var guest_entry := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(guest_entry))
	assert_true(route.passages.interact(guest_entry))
	assert_true(route.submit(route.input(Host, PlayerCommand.MOVE_TO, route.handle)))
	var host_entry := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(host_entry))
	assert_true(route.passages.interact(host_entry))
	var entry := route.inner.module_center(WorldTopology.ENTRY)
	assert_true(route.add_sentinel(&"silent_garden", Route.offset(entry, -25, 0)))
	var death_tick := route.authority.next_tick()
	assert_true(route.admit_sentinel_hit(Guest, death_tick))
	var wave := route.kernel.resolve_next(CombatInstant.at_tick(death_tick))
	assert_true(route.party.observe_combat(wave))
	assert_true(route.authority.close_tick())
	var defeated := route.party.view(Guest, CombatInstant.at_tick(death_tick))
	assert_false(defeated.alive)
	var ready := defeated.wait_until.tick
	assert_true(route.walk_to_exit(Host))
	var exit := route.input(Host, PlayerCommand.INTERACT, route.inner.module_center(WorldTopology.RETURN_EXIT))
	assert_true(route.submit(exit))
	assert_true(route.passages.interact(exit))
	var split := route.party.view(Guest, CombatInstant.at_tick(route.authority.next_tick() - 1))
	assert_eq(split.realm, &"silent_garden")
	assert_false(split.alive)
	assert_eq(split.wait_until.tick, ready)
	assert_eq(split.position.x, defeated.position.x)
	assert_eq(split.position.y, defeated.position.y)
	assert_null(route.outer.geometry().circle_center(Guest, 0))
	while route.authority.next_tick() < ready:
		if not route.authority.close_tick():
			fail_test("Authority could not reach the original rescue deadline.")
			return
	assert_false(route.party.begin_rescue(Host, Guest, ready))
	var reentry := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(reentry))
	assert_true(route.passages.interact(reentry))
	assert_true(route.party.begin_rescue(Host, Guest, route.authority.next_tick()))
	for _tick: int in RunParty.RESCUE_PROGRESS / RunParty.HELPER_RATE[1]:
		if not route.authority.close_tick():
			fail_test("Authority could not finish the ordinary rescue.")
			return
	var revived := route.party.view(Guest, CombatInstant.at_tick(route.authority.next_tick() - 1))
	assert_true(revived.alive)
	assert_eq(revived.realm, &"silent_garden")
	assert_eq(route.kernel.actor_snapshot(Guest).life, 2)
	assert_eq(route.kernel.actor_snapshot(Guest).hp.amount.native_at_scale(0), 6)


func test_split_serialization_uses_each_seats_actual_scope_and_one_clock() -> void:
	var route := Route.new(&"inverted_archive")
	assert_true(route.begin())
	var cross := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(cross))
	assert_true(route.passages.interact(cross))
	var now := CombatInstant.at_tick(route.authority.next_tick() - 1)
	var actors: Array[RecipientView.Actor] = []
	for id: StringName in [Host, Guest]:
		var facts := route.party.view(id, now)
		var row := RecipientView.Actor.new()
		row.id = id
		row.realm = facts.realm
		row.position = facts.position
		actors.append(row)
	for row: RecipientView.Actor in actors:
		var scope := RecipientView.Scope.new()
		scope.seat = row.id
		scope.realm = row.realm
		scope.actors = {Host: true, Guest: true}
		var map := route.outer if row.realm == Source else route.inner
		var bytes := RecipientView.pack(scope, 1, 2, now.tick, 3, "9", route.party.status_ids(), actors, [], map)
		var receipt := RecipientView.read(bytes)
		assert_not_null(receipt)
		assert_eq(receipt.tick, now.tick)
		assert_eq(receipt.level, 3)
		assert_eq(receipt.xp, "9")
		assert_eq(receipt.realm, String(row.realm))
		assert_eq(receipt.actors.keys(), [String(row.id)])
		assert_eq(receipt.party.size(), 2)
		assert_eq(receipt.explored.size(), 0 if row.realm == Source else 1)


func test_pr11_preserves_occupied_trials_and_allows_exit_after_the_collapse_boundary() -> void:
	var route := Route.new(&"silent_garden")
	assert_true(route.begin())
	var arrival := route.inner.module_center(WorldTopology.ENTRY)
	var resettable := RunRealmTrial.declare(route.party, route.inner, arrival, 30, true, false)
	var completed := RunRealmTrial.declare(route.party, route.inner, arrival, 30, true, false)
	var dormant := RunRealmTrial.declare(route.party, route.inner, arrival, 30, false, false)
	var persistent := RunRealmTrial.declare(route.party, route.inner, arrival, 30, false, false)
	var before := CombatInstant.at_tick(RunRealmTrial.COLLAPSE_TICK - 1)
	var collapse := CombatInstant.at_tick(RunRealmTrial.COLLAPSE_TICK)
	assert_false(resettable.start(Guest, before))
	var guest_enter := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(guest_enter))
	assert_true(route.passages.interact(guest_enter))
	assert_true(route.submit(route.input(Host, PlayerCommand.MOVE_TO, route.handle)))
	var host_enter := route.input(Host, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(host_enter))
	assert_true(route.passages.interact(host_enter))
	assert_false(resettable.start(Guest, before))
	while route.authority.next_tick() <= before.tick:
		if not route.authority.close_tick() or not route.authority.closed_party:
			fail_test("Party and authority must reach the last pre-Collapse boundary together")
			return
	assert_true(resettable.start(Guest, before))
	assert_true(completed.start(Host, before))
	assert_true(persistent.start(Host, before))
	assert_false(completed.complete(collapse))
	assert_eq(dormant.observe(collapse), RunRealmTrial.Observation.INVALID)
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_party)
	assert_eq(route.party.closed_tick, collapse.tick)
	assert_false(completed.complete(before))
	assert_eq(dormant.observe(before), RunRealmTrial.Observation.INVALID)
	assert_eq(dormant.observe(collapse), RunRealmTrial.Observation.RETAINED)
	assert_true(completed.complete(collapse))
	assert_false(dormant.start(Host, before))
	assert_false(dormant.start(Host, collapse))
	assert_eq(resettable.observe(collapse), RunRealmTrial.Observation.RETAINED)
	var exit := route.inner.module_center(WorldTopology.RETURN_EXIT)
	assert_true(route.walk_to_exit(Guest))
	var guest_exit := route.input(Guest, PlayerCommand.INTERACT, exit)
	assert_true(route.submit(guest_exit))
	assert_true(route.passages.interact(guest_exit))
	var one_remains := CombatInstant.at_tick(route.party.closed_tick)
	assert_eq(resettable.observe(one_remains), RunRealmTrial.Observation.RETAINED)
	assert_eq(resettable.phase, RunRealmTrial.Phase.ACTIVE)
	assert_true(route.walk_to_exit(Host))
	var host_exit := route.input(Host, PlayerCommand.INTERACT, exit)
	assert_true(route.submit(host_exit))
	assert_true(route.passages.interact(host_exit))
	var empty := CombatInstant.at_tick(route.party.closed_tick)
	assert_eq(resettable.observe(empty), RunRealmTrial.Observation.RESET)
	assert_eq(resettable.phase, RunRealmTrial.Phase.DORMANT)
	assert_eq(resettable.observe(empty), RunRealmTrial.Observation.RETAINED)
	assert_eq(persistent.observe(empty), RunRealmTrial.Observation.RETAINED)
	assert_eq(persistent.phase, RunRealmTrial.Phase.ACTIVE)
	assert_eq(completed.observe(empty), RunRealmTrial.Observation.RETAINED)
	assert_eq(completed.phase, RunRealmTrial.Phase.COMPLETED)
	assert_false(resettable.start(Host, empty))


func test_first_entry_and_return_observe_the_same_already_active_optional_world() -> void:
	var route := Route.new(&"inverted_archive")
	assert_true(route.begin())
	var activity := WorldActivity.new(route.kernel, Route.Seed)
	assert_true(activity.register_realm(route.outer))
	assert_true(activity.register_realm(route.inner))
	assert_true(activity.track_player(Host))
	assert_true(activity.track_player(Guest))
	route.authority.activity = activity
	var resident := WorldEnemy.Rules.new()
	resident.faction = &"archive"
	resident.family = &"fixture"
	resident.hp = Quantity.from_count(40)
	resident.displacement_resistance = 0.75
	resident.damage = Quantity.from_count(1)
	resident.radius = 4.0
	resident.sight = 20.0
	resident.attack_range = 8.0
	resident.attack_radius = 4.0
	resident.windup_ticks = 1
	resident.recovery_ticks = 1
	var site := WorldActivity.SpawnSite.new()
	site.id = &"archive"
	site.realm = &"inverted_archive"
	site.rules = resident
	site.positions = [Route.offset(route.inner.module_center(WorldTopology.ENTRY), 28.0, 0.0)]
	site.first_tick = 1
	site.period = 3
	site.limit = 1
	assert_true(activity.schedule_spawn(site))
	resident.displacement_resistance = 0.0
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_party)
	var id := &"spawn/7:archive/1"
	assert_eq(route.kernel.actor_snapshot(id).displacement_resistance, 0.75)
	var active: Array = activity.snapshot().actors[id]
	assert_eq(route.inner.view(Guest).visible, [])
	var enter := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(enter))
	assert_true(route.passages.interact(enter))
	assert_eq(activity.snapshot().actors[id], active)
	assert_eq(activity.snapshot().actors[Guest][0], &"inverted_archive")
	assert_true(route.walk_to_exit(Guest))
	var leave := route.input(Guest, PlayerCommand.INTERACT, route.inner.module_center(WorldTopology.RETURN_EXIT))
	assert_true(route.submit(leave))
	assert_true(route.passages.interact(leave))
	var reenter := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(reenter))
	assert_true(route.passages.interact(reenter))
	var resumed := activity.snapshot()
	assert_eq(resumed.actors[id], active)
	assert_eq(resumed.actors[Guest][0], &"inverted_archive")
	assert_eq(resumed.rng[&"world-spawn/archive"][1], 1)
	assert_eq(resumed.tick, route.authority.next_tick() - 1)
