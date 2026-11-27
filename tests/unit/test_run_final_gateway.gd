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

class RefusedStore extends ProfileStore:
	var refuse := true

	func _commit_io() -> bool:
		return false if refuse else super._commit_io()


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
