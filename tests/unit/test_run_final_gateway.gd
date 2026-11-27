extends GutTest

const Route := preload("res://tests/unit/test_run_realm_passages.gd").Route
const Host := &"host"
const Guest := &"guest"
const Garden := &"silent_garden"
const Outside := WorldTopology.OVERWORLD
const Arena := RunSetup.FINAL_REALM
const Currency := "currency/common"
const Transfer := RunAuthority.GatewayResult
const Collapse := RunParty.COLLAPSE_TICK
const Observatory := preload("res://src/run/run_observatory_gateway.gd")

class RefusedStore extends ProfileStore:
	var refuse := true

	func _commit_io() -> bool:
		return false if refuse else super._commit_io()


func test_pr04_conditions_on_a_generated_observatory_and_keeps_the_ordinary_gateway() -> void:
	var ordinary_seeds: Dictionary[bool, int] = {}
	var eligible_seed := _early_seed()
	assert_ne(eligible_seed, -1)
	for seed: int in range(128):
		var layout := WorldTopology.generate(seed)
		if not layout.has_early_observatory():
			ordinary_seeds[layout.center(WorldTopology.OBSERVATORY) != null] = seed
			continue
		assert_not_null(layout.center(WorldTopology.OBSERVATORY))
		assert_true(WorldTopology.restore(layout.manifest()).has_early_observatory())
	assert_eq(ordinary_seeds.size(), 2)
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	for seed: int in ordinary_seeds.values():
		var route := Route.new(Garden, seed)
		assert_true(route.begin(catalog.revision))
		var arena := RealmGeometry.new(Arena)
		var progression := _progression(route.setup, catalog)
		assert_null(Observatory.register(route.authority, route.party, route.outer, arena, _arrivals(), progression))
		var normal := RunFinalGateway.register(route.authority, route.party, route.outer, arena, _arrivals(), 36.0, 10.0, progression)
		assert_not_null(normal)
		assert_null(normal.revealed_location())
		route.authority._closed_tick = Collapse
		assert_not_null(normal.revealed_location())


func test_pr04_requires_local_alignment_and_carries_a_remote_body_after_settlement() -> void:
	if not OS.has_feature("windows"):
		return
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var route := Route.new(Garden, _early_seed())
	assert_true(route.begin(catalog.revision))
	var arena := RealmGeometry.new(Arena)
	var arrivals := _arrivals()
	var progression := _progression(route.setup, catalog)
	var gate := Observatory.register(route.authority, route.party, route.outer, arena, arrivals, progression)
	assert_not_null(gate)
	if gate == null:
		return
	assert_null(Observatory.register(route.authority, route.party, route.outer, arena, arrivals, progression))
	assert_true(gate.view_for(Host).is_empty())
	var center := route.outer.module_center(WorldTopology.OBSERVATORY)
	var floor := route.outer.geometry()
	assert_true(floor.commit_circle_pose(Host, 0, Route.offset(center, 0, -12)))
	var inscription := _observatory_mark(gate, Observatory.INSCRIPTION)
	assert_false(inscription.inscription.is_empty())
	assert_null(_observatory_mark(gate, Observatory.GATE))
	assert_true(gate.view_for(Guest).is_empty())
	var closed := route.input(Host, PlayerCommand.INTERACT, center)
	assert_true(route.submit(closed))
	assert_eq(gate.enter(closed), Transfer.REFUSED)
	assert_eq(route.authority.request_gateway(closed, route.party, arena, arrivals, progression), Transfer.REFUSED)
	var west := _observatory_mark(gate, Observatory.WEST_CONDUIT).position
	var east := _observatory_mark(gate, Observatory.EAST_CONDUIT).position
	var too_far := route.input(Host, PlayerCommand.INTERACT, west)
	assert_true(route.submit(too_far))
	assert_false(gate.turn(too_far))
	assert_true(floor.commit_circle_pose(Host, 0, Route.offset(west, -16, 0)))
	var obstruction := RealmOutline.Edge.new()
	obstruction.first = Route.offset(west, -8, -12)
	obstruction.last = Route.offset(west, -8, 12)
	assert_true(floor.add_segment(&"conduit-screen", 0, obstruction, WorldExploration.BLOCKER, false))
	var covered := route.input(Host, PlayerCommand.INTERACT, west)
	assert_true(route.submit(covered))
	assert_false(gate.turn(covered))
	assert_true(floor.remove_mutable(&"conduit-screen", 0))
	var turn := route.input(Host, PlayerCommand.INTERACT, west)
	assert_false(gate.turn(turn))
	assert_true(route.submit(turn))
	assert_true(gate.turn(turn))
	assert_false(gate.turn(turn))
	assert_eq(_observatory_mark(gate, Observatory.WEST_CONDUIT).direction, Vector2i.RIGHT)
	assert_null(_observatory_mark(gate, Observatory.GATE))
	assert_true(floor.commit_circle_pose(Host, 0, Route.offset(east, 16, 0)))
	for index: int in 3:
		var rotate := route.input(Host, PlayerCommand.INTERACT, east)
		assert_true(route.submit(rotate))
		assert_true(gate.turn(rotate))
	assert_eq(_observatory_mark(gate, Observatory.EAST_CONDUIT).direction, Vector2i.LEFT)
	assert_not_null(_observatory_mark(gate, Observatory.GATE))

	var entry := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(entry))
	assert_true(route.passages.interact(entry))
	var body_at := route.inner.module_center(WorldTopology.ENTRY)
	assert_true(route.add_sentinel(Garden, Route.offset(body_at, 16, 0)))
	var death := route.authority.next_tick()
	assert_true(route.admit_sentinel_hit(Guest, death))
	assert_true(route.party.observe_combat(route.kernel.resolve_next(CombatInstant.at_tick(death))))
	assert_true(route.authority.close_tick())
	var body := route.party.view(Guest, CombatInstant.at_tick(death))
	assert_false(body.alive)
	assert_eq(body.realm, Garden)
	assert_true(gate.view_for(Guest).is_empty())
	assert_eq(progression.grant_xp(&"ordinary-choice", Quantity.from_count(100), death), PartyProgression.Award.APPLIED)
	var frozen := progression.offer(Guest, 1)

	var store := RefusedStore.new()
	var directory := DirAccess.create_temp("agip-early-gateway")
	assert_eq(store.open("alice", directory.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var key := Crypto.new().generate_rsa(2048)
	var earnings := OrdinaryCurrency.begin(store, _binding(store, route.setup, key), key, Currency)
	assert_true(route.authority.attach_ordinary_currency(earnings))
	assert_eq(earnings.accrue("observatory-award", Quantity.from_count(17)), OrdinaryCurrency.Eligibility.QUEUED)
	assert_true(floor.commit_circle_pose(Host, 0, Route.offset(center, -15, 0)))
	var click := route.input(Host, PlayerCommand.INTERACT, center)
	click.reliable = true
	assert_true(route.submit(click))
	var now := CombatInstant.at_tick(click.tick)
	assert_eq(route.kernel.advance_survival(now).result, CombatKernel.Result.CLOSED)
	assert_eq(gate.enter(click), Transfer.SETTLEMENT_WAIT)
	assert_eq(store.balance(Currency).sign_value, 0)
	assert_false(route.authority.close_tick())
	assert_eq(route.party.view(Guest, now).realm, Garden)
	assert_null(arena.circle_center(Host, 0))
	store.refuse = false
	assert_eq(route.authority.retry_gateway(), Transfer.ENTERED)
	assert_eq(gate.enter(click), Transfer.REFUSED)
	assert_eq(route.authority.retry_gateway(), Transfer.REFUSED)
	assert_eq(store.balance(Currency).native_at_scale(0), 17)
	assert_null(route.kernel.actor_snapshot(&"sentinel"))
	assert_true(gate.view_for(Host).is_empty())
	var arrived := route.party.view(Guest, now)
	assert_false(arrived.alive)
	assert_eq(arrived.realm, Arena)
	assert_eq(arrived.wait_until.tick, body.wait_until.tick)
	assert_eq(progression.offer(Guest, 1).options, frozen.options)

	var saved := route.authority.checkpoint()
	assert_eq(saved["early_gateway_tick"], click.tick)
	var reopened := RunAuthority.new()
	assert_true(reopened.restore(route.setup, Host, saved))
	assert_eq(reopened.checkpoint(), saved)
	var earlier := saved.duplicate(true)
	earlier.erase("early_gateway_tick")
	assert_false(RunAuthority.new().restore(route.setup, Host, earlier))
	var forged := saved.duplicate(true)
	forged["early_gateway_tick"] = click.tick + 1
	assert_false(RunAuthority.new().restore(route.setup, Host, forged))
	var frontier := progression.frontier(click.tick)
	var saved_frontier := {"epoch": frontier.epoch, "tick": frontier.tick, "image": frontier.image}
	var recovered := PartyProgression.reopen(route.setup, catalog, saved_frontier)
	assert_not_null(recovered)
	assert_eq(recovered.frontier(click.tick).image, frontier.image)
	var image: Dictionary = bytes_to_var(frontier.image)
	image.erase("early_gateway_tick")
	saved_frontier["image"] = var_to_bytes(image)
	assert_null(PartyProgression.reopen(route.setup, catalog, saved_frontier))
	assert_true(store.close())


func test_pr04_gate_expires_at_collapse_after_the_conduits_are_aligned() -> void:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var route := Route.new(Garden, _early_seed())
	assert_true(route.begin(catalog.revision))
	var progression := _progression(route.setup, catalog)
	var arena := RealmGeometry.new(Arena)
	var gate := Observatory.register(route.authority, route.party, route.outer, arena, _arrivals(), progression)
	assert_not_null(gate)
	var floor := route.outer.geometry()
	var center := route.outer.module_center(WorldTopology.OBSERVATORY)
	for side: StringName in [Observatory.WEST_CONDUIT, Observatory.EAST_CONDUIT]:
		assert_true(floor.commit_circle_pose(Host, 0, center))
		var mark := _observatory_mark(gate, side)
		assert_true(floor.commit_circle_pose(Host, 0, mark.position))
		for index: int in (1 if side == Observatory.WEST_CONDUIT else 3):
			var rotate := route.input(Host, PlayerCommand.INTERACT, mark.position)
			assert_true(route.submit(rotate))
			assert_true(gate.turn(rotate))
	assert_true(floor.commit_circle_pose(Host, 0, center))
	route.authority._closed_tick = Collapse - 1
	route.party._tick = Collapse - 1
	assert_not_null(_observatory_mark(gate, Observatory.GATE))
	var attempt := route.input(Host, PlayerCommand.INTERACT, center)
	assert_true(route.submit(attempt))
	assert_eq(attempt.tick, Collapse)
	assert_null(_observatory_mark(gate, Observatory.GATE))
	assert_eq(route.kernel.advance_survival(CombatInstant.at_tick(Collapse)).result, CombatKernel.Result.CLOSED)
	assert_eq(gate.enter(attempt), Transfer.REFUSED)
	assert_true(route.authority.belongs_to(route.setup.run_id, 1))
	assert_null(arena.circle_center(Host, 0))


static func _early_seed() -> int:
	for seed: int in range(128):
		if WorldTopology.generate(seed).has_early_observatory():
			return seed
	return -1


static func _observatory_mark(gate: Observatory, id: StringName) -> Observatory.Mark:
	for mark: Observatory.Mark in gate.view_for(Host):
		if mark.id == id:
			return mark
	return null


func test_normal_gateway_checks_the_clock_and_waits_for_durable_settlement_before_moving_all_seats() -> void:
	if not OS.has_feature("windows"):
		return
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var route := Route.new(Garden)
	assert_true(route.begin(catalog.revision))
	var prep := _progression(route.setup, catalog)
	var floor := route.outer.geometry()
	var handle := route.outer.module_center(WorldTopology.GATEWAY)
	var arena := RealmGeometry.new(Arena)
	var arrivals := _arrivals()
	var gateway := RunFinalGateway.register(route.authority, route.party, route.outer, arena, arrivals, 36.0, 10.0, prep)
	assert_not_null(gateway)
	assert_true(floor.commit_circle_pose(Host, 0, Route.offset(handle, -14, 0)))
	assert_true(floor.add_circle(Host, 2, Route.offset(handle, -14, 9), 3, 2))
	var entry := route.input(Guest, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(entry))
	assert_true(route.passages.interact(entry))
	var old_world := WorldActivity.new(route.kernel, Route.Seed)
	assert_true(old_world.register_realm(route.outer))
	assert_true(old_world.register_realm(route.inner))
	var inner_entry := route.inner.module_center(WorldTopology.ENTRY)
	assert_true(route.add_sentinel(Garden, Route.offset(inner_entry, 16, 0)))
	assert_true(_add_attacker(route.kernel, floor, Route.offset(handle, -32, 0)))
	var trial := RunRealmTrial.declare(route.party, route.inner, inner_entry, 25.0, false, false)
	assert_true(trial.start(Guest, CombatInstant.at_tick(route.party.closed_tick)))
	assert_eq(prep.grant_xp(&"already-earned", Quantity.from_count(100), 2), PartyProgression.Award.APPLIED)
	var frozen := prep.offer(Guest, 1)

	assert_true(_step_to(route, Collapse - 3))
	var death := route.authority.next_tick()
	assert_true(route.party.set_guest_connected(Guest, false, death))
	assert_true(route.admit_sentinel_hit(Guest, death))
	assert_true(_strike(route.kernel, floor, &"raider", Host, death, death, 5, true))
	var wave := route.kernel.resolve_next(CombatInstant.at_tick(death))
	assert_true(route.party.observe_combat(wave))
	assert_true(route.authority.close_tick())
	var corpse := route.party.view(Guest, CombatInstant.at_tick(death))
	assert_false(corpse.alive)
	assert_false(corpse.connected)
	assert_eq(corpse.deaths, 1)
	assert_eq(corpse.realm, Garden)
	assert_true(_strike(route.kernel, floor, &"raider", Host, death + 1, Collapse + 3, 50))
	var early := route.input(Host, PlayerCommand.INTERACT, handle)
	assert_true(route.submit(early))
	assert_eq(early.tick, Collapse - 1)
	assert_null(gateway.revealed_location())
	assert_eq(gateway.interact(early), Transfer.REFUSED)

	var store := RefusedStore.new()
	var directory := DirAccess.create_temp("agip-gateway-settlement")
	assert_eq(store.open("alice", directory.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var key := Crypto.new().generate_rsa(2048)
	var binding := _binding(store, route.setup, key)
	var earnings := OrdinaryCurrency.begin(store, binding, key, Currency)
	assert_true(route.authority.attach_ordinary_currency(earnings))
	assert_eq(earnings.accrue("closed-world-earning", Quantity.from_count(17)), OrdinaryCurrency.Eligibility.QUEUED)
	var operation := earnings.dispatch(true)
	var click := route.input(Host, PlayerCommand.INTERACT, handle)
	assert_eq(click.tick, Collapse)
	assert_true(route.submit(click))
	var now := CombatInstant.at_tick(Collapse)
	assert_eq(route.kernel.advance_survival(now).result, CombatKernel.Result.CLOSED)
	assert_eq(gateway.revealed_location().x, handle.x)
	var forged := click.copy()
	forged.sequence += 99
	assert_eq(gateway.interact(forged), Transfer.REFUSED)
	var screen := RealmOutline.Edge.new()
	screen.first = Route.offset(handle, -7, -10)
	screen.last = Route.offset(handle, -7, 10)
	assert_true(floor.add_segment(&"screen", 0, screen, WorldExploration.BLOCKER, false))
	assert_eq(gateway.interact(click), Transfer.REFUSED)
	assert_true(floor.remove_mutable(&"screen", 0))
	assert_true(arena.add_circle(&"obstacle", 0, arrivals[Guest], 5, WorldExploration.BLOCKER))
	assert_eq(gateway.interact(click), Transfer.REFUSED)
	assert_false(route.authority.checkpoint().is_empty())
	assert_null(arena.circle_center(Host, 0))
	assert_true(arena.remove_mutable(&"obstacle", 0))
	var old_move := route.input(Host, PlayerCommand.MOVE_TO, handle)
	assert_eq(route.authority.submit(Host, old_move), RunAuthority.Admission.QUEUED)
	assert_eq(gateway.interact(click), Transfer.SETTLEMENT_WAIT)
	assert_eq(store.lookup(operation).status, ProfileStore.CommitResult.MISSING)
	assert_eq(earnings.pending_amount().native_at_scale(0), 17)
	assert_false(route.authority.close_tick())
	assert_false(route.authority.can_open_earning_group())
	assert_true(route.authority.checkpoint().is_empty())
	assert_eq(route.party.view(Host, now).realm, Outside)
	assert_eq(route.party.view(Guest, now).realm, Garden)
	assert_null(arena.circle_center(Host, 0))
	assert_eq(route.kernel.pending_count(), 2)
	assert_eq(route.authority.retry_gateway(), Transfer.SETTLEMENT_WAIT)
	var old_frontier := prep.frontier(Collapse)
	assert_eq(old_frontier.epoch, 1)
	var retired := route.kernel.actor_snapshot(&"raider")

	store.refuse = false
	assert_eq(route.authority.retry_gateway(), Transfer.ENTERED)
	assert_eq(route.authority.retry_gateway(), Transfer.REFUSED)
	assert_eq(gateway.interact(click), Transfer.REFUSED)
	assert_null(gateway.revealed_location())
	assert_false(route.authority.belongs_to(route.setup.run_id, 1))
	assert_true(route.party.belongs_to(route.setup.run_id, 2))
	assert_eq(route.authority.next_tick(), Collapse + 1)
	assert_eq(route.authority.submit(Host, old_move), RunAuthority.Admission.WRONG_EPOCH)
	assert_eq(route.kernel.pending_count(), 1)
	assert_null(route.kernel.actor_snapshot(&"raider"))
	assert_null(route.kernel.actor_snapshot(&"sentinel"))
	retired.realm = Arena
	assert_false(route.kernel.add_actor(retired))
	assert_null(old_world.advance(1))
	assert_false(trial.complete(now))
	assert_null(floor.circle_center(Host, 0))
	assert_null(floor.circle_center(Host, 2))
	assert_null(route.inner.geometry().circle_center(Guest, 0))
	assert_eq(arena.circle_center(Host, 2).y - arena.circle_center(Host, 0).y, 9.0)
	var host := route.kernel.actor_snapshot(Host)
	assert_eq(host.hp.amount.native_at_scale(0), 15)
	assert_eq(host.resources[&"mana"].native_at_scale(0), 7)
	var carried := route.party.view(Guest, now)
	assert_eq(carried.realm, Arena)
	assert_eq(carried.position.x, arrivals[Guest].x)
	assert_false(carried.alive)
	assert_false(carried.connected)
	assert_true(carried.within_grace)
	assert_eq(carried.deaths, corpse.deaths)
	assert_eq(carried.wait_until.tick, corpse.wait_until.tick)
	assert_eq(prep.offer(Guest, 1).options, frozen.options)
	var saved := route.authority.checkpoint()
	assert_eq(saved["world_epoch"], 2)
	var restored := RunAuthority.new()
	assert_true(restored.restore(route.setup, Host, saved))
	assert_true(restored.belongs_to(route.setup.run_id, 2))
	assert_eq(restored.checkpoint(), saved)
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_result()["accepted"].is_empty())
	assert_eq(route.kernel.advance_survival(CombatInstant.at_tick(Collapse + 3)).hits.size(), 0)
	assert_eq(route.kernel.next_due().tick, death + 10)
	var still_bleeding := route.kernel.resolve_next(CombatInstant.at_tick(death + 10))
	assert_eq(still_bleeding.hits.size(), 1)
	assert_eq(still_bleeding.hits[0].family, &"R01.bleed")
	assert_eq(still_bleeding.hits[0].origin.owner, &"raider")
	assert_eq(route.kernel.actor_snapshot(Host).hp.amount.native_at_scale(0), 13)
	var arena_frontier := prep.frontier(Collapse)
	assert_eq(arena_frontier.epoch, 2)
	var entitlement := ProfileGrantSettlement.Entitlement.new()
	entitlement.binding = binding
	entitlement.occurrence = "fixture-arena-award"
	entitlement.kind = ProfileGrant.Kind.CURRENCY
	entitlement.award = Currency
	entitlement.amount = Quantity.from_count(2)
	assert_eq(ProfileGrantSettlement.issue(store, key, [entitlement], old_frontier, route.authority).status,
		ProfileStore.CommitResult.INVALID)
	assert_eq(ProfileGrantSettlement.issue(store, key, [entitlement], arena_frontier, route.authority).status,
		ProfileStore.CommitResult.COMMITTED)
	assert_true(store.close())
	assert_eq(store.open("alice", directory.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.balance(Currency).native_at_scale(0), 19)
	assert_eq(store.checkpoint()["generation"], 2)
	var recovered := PartyProgression.reopen(route.setup, catalog, store.frontier(String(route.setup.run_id)))
	assert_not_null(recovered)
	assert_eq(recovered.frontier(Collapse).image, arena_frontier.image)
	assert_eq(recovered.offer(Guest, 1).options, frozen.options)
	assert_true(store.close())


static func _arrivals() -> Dictionary[StringName, RealmSweep.Point]:
	return {Host: RealmSweep.Point.new(128, 128), Guest: RealmSweep.Point.new(152, 128)}


static func _step_to(route: Route, through: int) -> bool:
	while route.authority.next_tick() <= through:
		if not route.authority.close_tick() or not route.authority.closed_party:
			return false
	return true


static func _progression(setup: RunSetup, catalog: DefinitionCatalog) -> PartyProgression:
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	return PartyProgression.begin(setup, {Host: prep, Guest: prep})


static func _binding(store: ProfileStore, setup: RunSetup, key: CryptoKey) -> ProfileGrant.Binding:
	var binding := ProfileGrant.Binding.new()
	binding.issuer = key
	binding.recipient_key = key
	binding.recipient = store.identity()
	binding.run = String(setup.run_id)
	binding.rules = String(setup.rules_revision)
	binding.catalog = String(setup.catalog_revision)
	return binding


static func _add_attacker(kernel: CombatKernel, floor: RealmGeometry, at: RealmSweep.Point) -> bool:
	var actor := CombatantState.new()
	actor.id = &"raider"
	actor.owner = actor.id
	actor.life = 1
	actor.realm = Outside
	actor.provenance = CombatOrigin.Provenance.SPAWN
	actor.max_hp = Quantity.from_count(20)
	actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
	return kernel.add_actor(actor) and floor.add_circle(actor.id, 0, at, 4, 2)


static func _strike(kernel: CombatKernel, floor: RealmGeometry, source: StringName, target: StringName,
		committed: int, due: int, amount: int, applies_bleed: bool = false) -> bool:
	var action := CombatAction.new()
	action.source = source
	action.source_life = 1
	action.family = &"old-swings"
	action.origin = CombatOrigin.new()
	action.origin.owner = source
	action.origin.provenance = CombatOrigin.Provenance.SPAWN
	action.origin.activation = committed
	action.origin.committed_at = CombatInstant.at_tick(committed)
	var damage := CombatAction.Component.new()
	damage.base = Quantity.from_count(amount)
	action.components = [damage]
	if applies_bleed:
		var application := CombatBleedLedger.Application.new()
		application.offense = CombatAction.Component.new()
		application.offense.base = Quantity.from_count(2)
		application.duration = 30
		application.period = 10
		application.capacity = 1
		action.bleed = application
	var delivery := CombatDelivery.activate(kernel, action, floor.realm_id)
	var proof := floor.certify_circle_snapshot(floor.realm_id, floor.circle_center(target, 0), 0, 2)
	return (delivery != null and proof != null and proof.contacts.size() == 1 and proof.contacts[0].entity == target
		and delivery.admit(due, proof.contacts[0], 1, true) == CombatDelivery.Result.ADMITTED and delivery.finish())
