extends GutTest

const HOST := &"host"
const GUEST := &"guest"
const ALLY := &"ally"
const REMOTE := &"remote"
const FIRST := &"overworld"
const SECOND := &"observatory"
const ENEMY := &"enemy"
const BLOCKERS := 2
const Commit := ProfileStore.CommitResult

class BlessingStore extends ProfileStore:
	var persist := false

	func _commit_io() -> bool:
		if persist:
			super._commit_io()
		return false

class Scenario:
	var setup := RunSetup.new()
	var kernel := CombatKernel.new()
	var realms: Dictionary[StringName, RealmGeometry] = {}
	var party: RunParty

	func _init(seats: Array[StringName]) -> void:
		setup.role = RunSetup.Role.SOLO if seats.size() == 1 else RunSetup.Role.HOST
		setup.run_id = &"party-test"
		setup.authority_id = &"owner"
		setup.epoch = 1
		setup.rules_revision = &"wp22"
		setup.catalog_revision = &"starter"
		setup.challenge_id = &"default"
		realms[FIRST] = RealmGeometry.new(FIRST)
		realms[SECOND] = RealmGeometry.new(SECOND)
		var actors: Dictionary[StringName, StringName] = {}
		for index: int in seats.size():
			var seat := seats[index]
			var realm := SECOND if seat == REMOTE else FIRST
			setup.initial_realms[seat] = realm
			actors[seat] = seat
			add_actor(seat, realm, CombatOrigin.Provenance.SEAT, float(index) * 10.0)
		add_actor(ENEMY, FIRST, CombatOrigin.Provenance.SPAWN, 100.0)
		for geometry: RealmGeometry in realms.values():
			kernel.attach_geometry(geometry, BLOCKERS)
		party = RunParty.begin(setup, HOST, kernel, realms, actors, BLOCKERS)

	func add_actor(id: StringName, realm: StringName, cause: CombatOrigin.Provenance, x: float) -> void:
		var actor := CombatantState.new()
		actor.id = id
		actor.owner = id
		actor.realm = realm
		actor.provenance = cause
		actor.life = 1
		actor.max_hp = Quantity.from_count(100)
		actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
		actor.resources[&"mana"] = Quantity.from_count(10)
		kernel.add_actor(actor)
		realms[realm].add_circle(id, 0, RealmSweep.Point.new(x, 0), 2.0, 1)

	func move(seat: StringName, x: float) -> bool:
		return party.apply_input(seat, PlayerCommand.new(PlayerCommand.MOVE_TO, x, 0))

	func action(source: StringName, tick: int, damage: int) -> CombatAction:
		var actor := kernel.actor_snapshot(source)
		var result := CombatAction.new()
		result.source = source
		result.source_life = actor.life
		result.family = &"fixture"
		result.origin = CombatOrigin.new()
		result.origin.owner = actor.owner
		result.origin.provenance = actor.provenance
		result.origin.activation = tick
		result.origin.committed_at = CombatInstant.at_tick(tick)
		var component := CombatAction.Component.new()
		component.base = Quantity.from_count(damage)
		result.components = [component]
		return result

	func contact_for(target: StringName, realm: StringName) -> RealmGeometry.Contact:
		var geometry := realms[realm]
		var center := geometry.circle_center(target, 0)
		for hit: RealmGeometry.Contact in geometry.certify_circle_snapshot(realm, center, 0.0, 1).contacts:
			if hit.entity == target:
				return hit
		return null

	func admit(held: String, target: StringName, tick: int, hostile: bool) -> CombatRootQueue.Result:
		var actor := kernel.actor_snapshot(target)
		return kernel.admit_contact(held, 1, actor.realm, tick, contact_for(target, actor.realm),
			actor.life, hostile)

	func hit(source: StringName, target: StringName, tick: int, damage: int) -> CombatKernel.WaveResult:
		var held := kernel.commit(action(source, tick, damage))
		if admit(held, target, tick, true) != CombatRootQueue.Result.ACCEPTED:
			return null
		kernel.finish_delivery(held)
		return resolve(tick)

	func pay(source: StringName, tick: int, price: int, automatic: bool) -> CombatKernel.WaveResult:
		var cast := action(source, tick, 1)
		cast.hp_cost = Quantity.from_count(price)
		cast.automatic_hp_cost = automatic
		cast.activation_costs[&"mana"] = Quantity.from_count(1)
		if kernel.commit(cast).is_empty():
			return null
		return resolve(tick)

	func resolve(tick: int) -> CombatKernel.WaveResult:
		var wave := kernel.resolve_next(CombatInstant.at_tick(tick))
		return wave if party.observe_combat(wave) else null

	func close_through(first: int, last: int) -> bool:
		for tick: int in range(first, last + 1):
			if not party.close_tick(tick):
				return false
		return true

	func view(seat: StringName, tick: int) -> RunParty.View:
		return party.view(seat, CombatInstant.at_tick(tick))


func test_party_multiplier_is_locked_from_the_initialized_roster() -> void:
	var seats: Array[StringName] = [HOST, GUEST, ALLY, REMOTE]
	for size: int in range(1, seats.size() + 1):
		var run := Scenario.new(seats.slice(0, size))
		assert_eq(run.party.hp_scale().native_at_scale(2), 100 + 50 * (size - 1))
		assert_eq(run.party.attack_scale().native_at_scale(2), 100 + 10 * (size - 1))
		assert_eq(run.party.population_scale().native_at_scale(2), 100 + 25 * (size - 1))
		assert_eq(run.party.reinforcement_frequency_scale().native_at_scale(2), 100 + 25 * (size - 1))
		assert_false(run.party.set_guest_connected(&"new_seat", true, 1))
		assert_false(run.party.set_guest_connected(HOST, false, 1))
		if size > 1:
			assert_true(run.party.set_guest_connected(GUEST, false, 1))
			assert_true(run.party.close_tick(1))
			assert_eq(run.party.hp_scale().native_at_scale(2), 100 + 50 * (size - 1))


func test_stationary_guest_stays_vulnerable_and_resolves_its_paid_attack() -> void:
	var run := Scenario.new([HOST, GUEST])
	assert_true(run.move(GUEST, 80))
	assert_eq(run.party.step_movement(GUEST, 60, 1.0 / 60.0).x, 11.0)
	var held := run.kernel.commit(run.action(GUEST, 1, 9))
	assert_false(held.is_empty())
	assert_true(run.party.close_tick(1))
	assert_true(run.party.set_guest_connected(GUEST, false, 2))
	assert_false(run.move(GUEST, 90))
	assert_eq(run.party.step_movement(GUEST, 60, 1.0 / 60.0).x, 11.0)
	assert_eq(run.kernel.commit(run.action(GUEST, 2, 20)), "")
	assert_eq(run.admit(held, ENEMY, 2, true), CombatRootQueue.Result.ACCEPTED)
	assert_true(run.kernel.finish_delivery(held))
	assert_not_null(run.resolve(2))
	assert_eq(run.kernel.actor_snapshot(ENEMY).hp.amount.native_at_scale(0), 91)
	assert_true(run.party.close_tick(2))
	var hit := run.hit(ENEMY, GUEST, 3, 120)
	assert_not_null(hit)
	assert_eq(hit.eliminations[0].target, GUEST)
	assert_true(run.party.close_tick(3))
	assert_false(run.view(GUEST, 3).alive)
	assert_eq(run.view(GUEST, 3).position.x, 11.0)
	assert_true(run.party.set_guest_connected(GUEST, true, 4))
	assert_eq(run.party.status_ids()[GUEST], &"down")
	assert_false(run.party.can_control(GUEST))
	assert_true(run.party.close_tick(4))


func test_last_living_guest_reclaims_before_or_at_deadline_and_wipe_is_final_after_it() -> void:
	var deadline := 2 + RunParty.GUEST_GRACE
	for offset: int in [-1, 0, 1]:
		var run := Scenario.new([HOST, GUEST])
		assert_true(run.party.close_tick(1))
		assert_true(run.party.set_guest_connected(GUEST, false, 2))
		assert_not_null(run.pay(HOST, 2, 100, false))
		assert_true(run.close_through(2, deadline - 2))
		assert_true(run.view(GUEST, deadline - 2).within_grace)
		assert_false(run.party.defeated)
		for tick: int in range(deadline - 1, deadline + 1):
			if tick == deadline + offset:
				assert_true(run.party.set_guest_connected(GUEST, true, tick))
			assert_true(run.party.close_tick(tick))
		assert_eq(run.party.defeated, offset == 1)
		assert_true(run.view(GUEST, deadline).alive)
		if offset == 1:
			assert_false(run.party.set_guest_connected(GUEST, true, deadline + 1))
			assert_false(run.party.close_tick(deadline + 1))


func test_expiry_keeps_a_vulnerable_guest_in_a_run_with_another_survivor() -> void:
	var run := Scenario.new([HOST, GUEST])
	assert_true(run.party.set_guest_connected(GUEST, false, 1))
	var deadline := 1 + RunParty.GUEST_GRACE
	assert_true(run.close_through(1, deadline))
	assert_false(run.party.defeated)
	assert_false(run.view(GUEST, deadline).within_grace)
	assert_eq(run.kernel.actor_snapshot(GUEST).hp.amount.native_at_scale(0), 100)
	assert_true(run.party.set_guest_connected(GUEST, true, deadline + 1))
	assert_eq(run.party.step_movement(GUEST, 100, 1.0).x, 10.0)


func test_rescue_obeys_physical_access_interruptions_and_shared_diminishing_rate() -> void:
	var run := Scenario.new([HOST, GUEST, ALLY, REMOTE])
	assert_true(run.party.set_guest_connected(GUEST, false, 1))
	assert_not_null(run.hit(ENEMY, GUEST, 1, 100))
	var ready := 1 + RunParty.INITIAL_WAIT
	assert_true(run.close_through(1, ready - 2))
	assert_false(run.party.begin_rescue(HOST, GUEST, ready - 1))
	assert_false(run.party.apply_input(HOST, PlayerCommand.new(PlayerCommand.INTERACT, 10, 0)))
	assert_true(run.party.close_tick(ready - 1))
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(5, -10)
	edge.last = RealmSweep.Point.new(5, 10)
	assert_true(run.realms[FIRST].add_segment(&"door", 0, edge, BLOCKERS, false))
	assert_false(run.party.begin_rescue(HOST, GUEST, ready))
	assert_false(run.party.begin_rescue(REMOTE, GUEST, ready))
	assert_false(run.party.apply_input(ALLY, PlayerCommand.new(PlayerCommand.INTERACT, 50, 0)))
	assert_true(run.party.apply_input(ALLY, PlayerCommand.new(PlayerCommand.INTERACT, 10, 0)))
	assert_true(run.party.close_tick(ready))
	assert_eq(run.view(GUEST, ready).rescue_progress, 4)
	assert_true(run.realms[FIRST].remove_mutable(&"door", 0))
	assert_true(run.party.begin_rescue(HOST, GUEST, ready + 1))
	assert_true(run.party.close_tick(ready + 1))
	assert_eq(run.view(GUEST, ready + 1).rescue_progress, 10)
	assert_true(run.move(ALLY, 21))
	assert_eq(run.party.step_movement(ALLY, 60, 1.0 / 60.0).x, 21.0)
	assert_not_null(run.hit(ENEMY, HOST, ready + 2, 1))
	assert_true(run.party.close_tick(ready + 2))
	assert_eq(run.view(GUEST, ready + 2).rescue_progress, 10)
	assert_eq(run.view(HOST, ready + 2).rescue_interruption, RunParty.RescueInterruption.HOSTILE_DAMAGE)
	assert_eq(run.view(ALLY, ready + 2).rescue_interruption, RunParty.RescueInterruption.MOVED_AWAY)
	assert_true(run.party.begin_rescue(HOST, GUEST, ready + 3))
	assert_true(run.party.begin_rescue(ALLY, GUEST, ready + 3))
	assert_true(run.close_through(ready + 3, ready + 80))
	assert_false(run.view(GUEST, ready + 80).alive)
	assert_true(run.party.close_tick(ready + 81))
	assert_true(run.view(GUEST, ready + 81).alive)
	assert_false(run.party.can_control(GUEST))
	assert_eq(run.kernel.actor_snapshot(GUEST).life, 2)
	assert_eq(run.kernel.actor_snapshot(GUEST).hp.amount.native_at_scale(0), 30)
	assert_eq(run.view(GUEST, ready + 81).position.x, 10.0)
	assert_true(run.party.set_guest_connected(GUEST, true, ready + 82))
	assert_true(run.party.can_control(GUEST))
	assert_eq(run.party.step_movement(GUEST, 60, 1.0).x, 10.0)


func test_revival_protection_blocks_hostile_damage_and_only_fatal_automatic_hp_prices() -> void:
	var run := Scenario.new([HOST, GUEST])
	assert_not_null(run.pay(GUEST, 1, 100, false))
	var ready := 1 + RunParty.INITIAL_WAIT
	assert_true(run.close_through(1, ready - 1))
	assert_true(run.party.begin_rescue(HOST, GUEST, ready))
	var revived := ready + 119
	assert_true(run.close_through(ready, revived))
	var blocked := run.hit(ENEMY, GUEST, revived + 1, 100)
	assert_not_null(blocked)
	assert_true(blocked.hits[0].components.is_empty())
	assert_eq(run.kernel.actor_snapshot(GUEST).hp.amount.native_at_scale(0), 30)
	assert_true(run.party.close_tick(revived + 1))
	var refused := run.pay(GUEST, revived + 2, 30, true)
	assert_eq(refused.activations[0].outcome, CombatKernel.ActivationOutcome.SUPPRESSED)
	assert_eq(run.kernel.actor_snapshot(GUEST).resources[&"mana"].native_at_scale(0), 9)
	assert_true(run.party.close_tick(revived + 2))
	var affordable := run.pay(GUEST, revived + 3, 5, true)
	assert_eq(affordable.activations[0].outcome, CombatKernel.ActivationOutcome.PAID)
	assert_eq(run.kernel.actor_snapshot(GUEST).hp.amount.native_at_scale(0), 25)
	assert_true(run.close_through(revived + 3, revived + RunParty.REVIVE_PROTECTION - 1))
	var expiry := revived + RunParty.REVIVE_PROTECTION
	var lethal := run.pay(GUEST, expiry, 25, true)
	assert_eq(lethal.activations[0].outcome, CombatKernel.ActivationOutcome.LETHAL)
	assert_true(run.party.close_tick(expiry))
	assert_eq(run.view(GUEST, expiry).wait_until.tick, expiry + RunParty.INITIAL_WAIT + RunParty.WAIT_INCREMENT)


func test_repeated_deaths_cap_the_wait_without_replenishing_resources() -> void:
	var run := Scenario.new([HOST, GUEST])
	var tick := 1
	for death: int in range(1, 8):
		assert_not_null(run.pay(GUEST, tick, 100 if death == 1 else 30, false))
		assert_true(run.party.close_tick(tick))
		var wait := mini(300 + (death - 1) * 180, 1200)
		var view := run.view(GUEST, tick)
		assert_eq(view.deaths, death)
		assert_eq(view.wait_until.tick, tick + wait)
		var ready := tick + wait
		assert_true(run.close_through(tick + 1, ready - 1))
		assert_true(run.party.begin_rescue(HOST, GUEST, ready))
		tick = ready + 120
		assert_true(run.close_through(ready, tick - 1))
		assert_eq(run.kernel.actor_snapshot(GUEST).resources[&"mana"].native_at_scale(0), 10 - death)


func test_last_disconnected_survivor_dying_removes_grace_immediately() -> void:
	var run := Scenario.new([HOST, GUEST])
	var after_wipe := run.kernel.commit(run.action(GUEST, 1, 100))
	assert_eq(run.admit(after_wipe, ENEMY, 3, true), CombatRootQueue.Result.ACCEPTED)
	assert_true(run.party.set_guest_connected(GUEST, false, 1))
	assert_not_null(run.pay(HOST, 1, 100, false))
	assert_true(run.party.close_tick(1))
	assert_false(run.party.defeated)
	assert_eq(run.kernel.pending_count(), 1)
	assert_not_null(run.hit(ENEMY, GUEST, 2, 100))
	assert_eq(run.party.terminal, CombatKernel.Terminal.DEFEAT)
	assert_eq(run.kernel.pending_count(), 0)
	assert_true(run.party.close_tick(2))
	assert_true(run.view(GUEST, 2).within_grace)
	assert_false(run.view(GUEST, 2).alive)
	assert_true(run.party.defeated)
	assert_false(run.party.close_tick(3))
	assert_eq(run.kernel.actor_snapshot(ENEMY).hp.amount.native_at_scale(0), 100)


func test_roster_keeps_same_group_creator_victory_when_the_last_player_dies() -> void:
	var run := Scenario.new([HOST])
	assert_false(run.party.close_tick(0))
	assert_true(run.kernel.configure_terminal(ENEMY, [HOST]))
	for pair: Array in [[HOST, ENEMY], [ENEMY, HOST]]:
		var output := run.kernel.commit(run.action(pair[0], 1, 100))
		assert_eq(run.admit(output, pair[1], 1, true), CombatRootQueue.Result.ACCEPTED)
		assert_true(run.kernel.finish_delivery(output))
	var terminal := run.resolve(1)
	assert_eq(terminal.terminal, CombatKernel.Terminal.VICTORY)
	assert_eq(run.party.terminal, CombatKernel.Terminal.VICTORY)
	assert_false(run.party.can_control(HOST))
	assert_true(run.party.close_tick(1))
	assert_false(run.party.defeated)
	assert_false(run.party.close_tick(2))


func test_local_encounter_presence_is_inclusive_realm_scoped_and_frozen_once() -> void:
	var run := Scenario.new([HOST, GUEST, ALLY, REMOTE])
	assert_true(run.move(GUEST, 400))
	assert_eq(run.party.step_movement(GUEST, 1000, 1.0).x, 400.0)
	var center := RealmSweep.Point.new(0, 0)
	var encounter := RunEncounterPresence.start(run.party, &"local", FIRST, center, 20.0,
		CombatInstant.at_tick(0))
	var control := RunEncounterPresence.start(run.party, &"opposing", FIRST, center, 20.0,
		CombatInstant.at_tick(0))
	assert_true(run.party.close_tick(1))
	assert_true(run.move(GUEST, 220))
	assert_eq(run.party.step_movement(GUEST, 1000, 1.0).x, 220.0)
	assert_true(encounter.observe(CombatInstant.at_tick(2)))
	assert_true(run.move(ALLY, 220.125))
	assert_eq(run.party.step_movement(ALLY, 1000, 1.0).x, 220.125)
	assert_true(run.party.close_tick(2))
	assert_true(run.party.set_guest_connected(GUEST, false, 3))
	assert_not_null(run.hit(ENEMY, GUEST, 3, 100))
	assert_true(run.party.close_tick(3))
	assert_true(encounter.settle(CombatInstant.at_tick(3)))
	assert_eq(encounter.recipients(), [GUEST, HOST])
	assert_false(encounter.settle(CombatInstant.at_tick(4)))
	assert_true(control.settle(CombatInstant.at_tick(3)))
	assert_eq(control.recipients(), [HOST])


func test_blessing_award_recovers_in_its_original_run_and_stays_out_of_profile_balances() -> void:
	if not OS.has_feature("windows"):
		return
	var run := Scenario.new([HOST, GUEST, ALLY, REMOTE])
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	run.setup.catalog_revision = catalog.revision
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	var preparations: Dictionary[StringName, RunPreparation] = {HOST: prep, GUEST: prep, ALLY: prep, REMOTE: prep}
	var progression := PartyProgression.begin(run.setup, preparations)
	assert_true(run.move(GUEST, 400))
	assert_eq(run.party.step_movement(GUEST, 1000, 1.0).x, 400.0)
	assert_true(run.move(ALLY, 220.125))
	assert_eq(run.party.step_movement(ALLY, 1000, 1.0).x, 220.125)
	var presence := RunEncounterPresence.start(run.party, &"boss/first", FIRST, RealmSweep.Point.new(0, 0), 20.0,
		CombatInstant.at_tick(0))
	var scratch := DirAccess.create_temp("agip-run-blessing")
	var store := BlessingStore.new()
	assert_eq(store.open("host", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var blessing := &"primal_instinct"
	assert_eq(progression.settle_blessing(store, presence, blessing, 1).status, Commit.INVALID)
	assert_true(run.move(GUEST, 220))
	assert_eq(run.party.step_movement(GUEST, 1000, 1.0).x, 220.0)
	assert_true(run.party.close_tick(1))
	assert_true(presence.settle(CombatInstant.at_tick(1)))
	assert_eq(presence.recipients(), [GUEST, HOST])
	assert_eq(progression.settle_blessing(store, presence, blessing, 1).status, Commit.MISSING)
	assert_false(progression.has_blessing(GUEST, blessing))
	assert_true(store.frontier(String(run.setup.run_id)).is_empty())
	store.persist = true
	var saved := progression.settle_blessing(store, presence, blessing, 1)
	assert_eq(saved.status, Commit.COMMITTED)
	assert_true(saved.balances.is_empty())
	assert_true(store.pending_grants().is_empty())
	assert_true(progression.has_blessing(HOST, blessing))
	assert_true(progression.has_blessing(GUEST, blessing))
	assert_false(progression.has_blessing(ALLY, blessing))
	assert_false(progression.has_blessing(REMOTE, blessing))
	assert_eq(progression.settle_blessing(store, presence, &"substitution", 1).status, Commit.CONFLICT)
	assert_true(store.close())
	assert_eq(store.open("host", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var frontier := store.frontier(String(run.setup.run_id))
	assert_eq(frontier.operation, saved.id)
	var resumed := PartyProgression.reopen(run.setup, catalog, frontier)
	assert_eq(resumed.frontier(1).image, frontier.image)
	assert_true(resumed.has_blessing(GUEST, blessing))
	assert_false(resumed.has_blessing(REMOTE, blessing))
	var repeated := resumed.settle_blessing(store, presence, blessing, 2)
	assert_eq(repeated.status, Commit.DUPLICATE)
	assert_eq(repeated.generation, saved.generation)
	run.setup.run_id = &"next-run"
	var next := PartyProgression.begin(run.setup, preparations)
	assert_false(next.has_blessing(HOST, blessing))
	assert_eq(next.settle_blessing(store, presence, blessing, 1).status, Commit.INVALID)
	assert_null(PartyProgression.reopen(run.setup, catalog, frontier))
	assert_true(store.close())


func test_connected_spectator_retains_personal_reward_and_can_follow_a_living_teammate() -> void:
	var run := Scenario.new([HOST, GUEST, REMOTE])
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	run.setup.catalog_revision = catalog.revision
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	var progression := PartyProgression.begin(run.setup, {HOST: prep, GUEST: prep, REMOTE: prep})
	assert_not_null(run.hit(ENEMY, GUEST, 1, 100))
	assert_true(run.party.close_tick(1))
	assert_false(run.party.can_control(GUEST))
	var corpse := RecipientView.Scope.new()
	corpse.seat = GUEST
	corpse.realm = run.view(GUEST, 1).realm
	var other := RecipientView.Scope.new()
	other.seat = REMOTE
	other.realm = run.view(REMOTE, 1).realm
	var follow := RecipientView.spectator_scope(corpse, REMOTE, {REMOTE: other}, run.party.status_ids())
	assert_eq(follow.seat, GUEST)
	assert_eq(follow.realm, SECOND)
	var unrelated := RecipientView.spectator_scope(corpse, &"unknown", {REMOTE: other}, run.party.status_ids())
	assert_eq(unrelated.realm, FIRST)
	assert_eq(progression.grant_xp(&"ordinary", Quantity.from_count(100), 1), PartyProgression.Award.APPLIED)
	var offer := progression.offer(GUEST, 1)
	assert_eq(progression.select(GUEST, 1, offer.options.keys()[0]), RunRewardQueue.Selection.APPLIED)
	assert_not_null(progression.offer(HOST, 1))
	assert_not_null(progression.offer(REMOTE, 1))
	assert_false(run.party.can_control(GUEST))


func test_personal_kill_assist_and_local_entitlement_use_different_facts() -> void:
	var run := Scenario.new([HOST, GUEST, ALLY, REMOTE])
	var credit := RunCombatCredit.new(run.party)
	var local := RunEncounterPresence.start(run.party, &"local", FIRST, RealmSweep.Point.new(0, 0),
		0.0, CombatInstant.at_tick(0))
	var first := run.hit(GUEST, ENEMY, 1, 1)
	assert_true(credit.observe_hit(first.hits[0], first.due, 2))
	assert_true(credit.observe_hit(first.hits[0], first.due, 2))
	assert_true(run.party.close_tick(1))
	var short_lived := run.hit(ALLY, ENEMY, 2, 1)
	assert_true(credit.observe_hit(short_lived.hits[0], short_lived.due, 0))
	assert_true(run.party.close_tick(2))
	var last := run.hit(HOST, ENEMY, 3, 100)
	assert_true(credit.observe_hit(last.hits[0], last.due, 10))
	var kill := credit.settle(last.eliminations[0], last.due)
	assert_eq(kill.killer, HOST)
	assert_eq(kill.assists, [GUEST])
	assert_null(credit.settle(last.eliminations[0], last.due))
	assert_false(credit.observe_hit(first.hits[0], first.due, 2))
	assert_true(run.party.close_tick(3))
	assert_true(local.settle(CombatInstant.at_tick(3)))
	assert_eq(local.recipients(), [ALLY, GUEST, HOST])
