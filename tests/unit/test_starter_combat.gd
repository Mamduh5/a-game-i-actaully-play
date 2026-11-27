extends GutTest

const HOSTILE := 1
const BLOCKER := 2
const FRIEND := 4
const OBJECT := 8
const REALM := &"starter-test"
const HERO := &"hero"
const MANA := &"mana"
const Committed := StarterCombat.Attempt.COMMITTED

class Arena:
	var geometry := RealmGeometry.new(REALM)
	var kernel := CombatKernel.new()
	var rules: StarterCombatRules = load("res://src/catalog/starter_combat.tres")
	var catalog: DefinitionCatalog
	var combat: StarterCombat
	var candidates: Array[PlayerTargeting.Candidate] = []
	var targeting := PlayerTargeting.new()

	func _init(weapon: StringName, hero: StringName = &"H01", short_cooldown: bool = false,
			rune: StringName = &"", second_rune: StringName = &"", unlocked: Dictionary[StringName, bool] = {},
			owner: StringName = HERO) -> void:
		var source: CatalogBundle = load("res://src/catalog/starter_roster.tres")
		catalog = source.compile()
		if short_cooldown:
			rules = rules.duplicate() as StarterCombatRules
			rules.siphon_cooldown = 2
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		var prep := RunPreparation.select(catalog, hero, weapon, [rune, second_rune], slots, unlocked)
		var actor := make_actor(HERO, 100, CombatOrigin.Provenance.SEAT)
		actor.owner = owner
		actor.physical.rating = Quantity.from_count(10)
		actor.magical.rating = Quantity.from_count(10)
		actor.resources[MANA] = Quantity.from_count(10)
		rules.prepare_hero(actor, prep)
		kernel.add_actor(actor)
		geometry.add_circle(HERO, 0, RealmSweep.Point.new(0, 0), 4.0, FRIEND)
		kernel.attach_geometry(geometry, BLOCKER)
		combat = StarterCombat.create(rules, catalog, prep, kernel, geometry, HERO, HOSTILE | OBJECT, HOSTILE, BLOCKER)

	static func make_actor(id: StringName, hp: int, side: CombatOrigin.Provenance) -> CombatantState:
		var actor := CombatantState.new()
		actor.id = id
		actor.owner = id
		actor.life = 1
		actor.realm = REALM
		actor.provenance = side
		actor.max_hp = Quantity.from_count(hp)
		actor.hp = QuantityLayerLedger.Pool.new(actor.max_hp, QuantityErrorBounds.new())
		return actor

	func add(id: StringName, x: float, y: float, hp: int, kind: int = HOSTILE,
			known: bool = true, controller: StringName = &"", resistance: float = 0.0) -> bool:
		var actor := make_actor(id, hp, CombatOrigin.Provenance.SEAT if kind == FRIEND else CombatOrigin.Provenance.SPAWN)
		actor.displacement_resistance = resistance
		if not controller.is_empty():
			actor.controller = controller
			actor.owner = controller
		var candidate := PlayerTargeting.Candidate.new()
		candidate.id = id
		candidate.position = RealmSweep.Point.new(x, y)
		candidate.kind = PlayerTargeting.Kind.HOSTILE if kind == HOSTILE else PlayerTargeting.Kind.CONTAINER
		candidate.known = known
		candidate.compatible = kind != FRIEND
		candidates.append(candidate)
		return kernel.add_actor(actor) and geometry.add_circle(id, 0, candidate.position, 3.0, kind)

	func move(id: StringName, x: float, y: float) -> bool:
		var point := RealmSweep.Point.new(x, y)
		for candidate: PlayerTargeting.Candidate in candidates:
			if candidate.id == id:
				candidate.position = point
				break
		return geometry.commit_circle_pose(id, 0, point)

	func wall(x: float, low_y: float, high_y: float) -> bool:
		var edge := RealmOutline.Edge.new()
		edge.first = RealmSweep.Point.new(x, low_y)
		edge.last = RealmSweep.Point.new(x, high_y)
		return geometry.add_segment(&"wall", 0, edge, BLOCKER, false)

	func attack(tick: int, prices: Dictionary[StringName, Quantity] = {}) -> StarterCombat.Attempt:
		return combat.try_weapon(tick, targeting, candidates, [], prices)

	func settle(tick: int) -> Array[CombatKernel.Hit]:
		var results: Array[CombatKernel.Hit] = []
		var now := CombatInstant.at_tick(tick)
		var next := kernel.next_due()
		while next != null and next.order_against(now) != RealmCircleTime.Order.AFTER:
			var wave := kernel.resolve_next(now)
			if wave.result == CombatKernel.Result.INTERRUPTED:
				return []
			combat.observe_closed_group(wave)
			results.append_array(wave.hits)
			next = kernel.next_due()
		kernel.advance_survival(now)
		return results

	func swing_from(source_id: StringName, target_id: StringName, amount: int, tick: int, hostile: bool = true) -> bool:
		var actor := kernel.actor_snapshot(source_id)
		var action := CombatAction.new()
		action.source = source_id
		action.source_life = actor.life
		action.family = &"witness"
		action.origin = CombatOrigin.new()
		action.origin.owner = actor.owner
		action.origin.provenance = actor.provenance
		action.origin.activation = tick
		action.origin.committed_at = CombatInstant.at_tick(tick)
		var part := CombatAction.Component.new()
		part.base = Quantity.from_count(amount)
		action.components.append(part)
		var held := kernel.commit(action)
		if held.is_empty():
			return false
		var center := geometry.circle_center(target_id, 0)
		for contact: RealmGeometry.Contact in geometry.certify_circle_snapshot(REALM, center, 0.0,
				HOSTILE | FRIEND | OBJECT).contacts:
			if contact.entity == target_id:
				var life := kernel.actor_snapshot(target_id).life
				return kernel.admit_contact(held, 1, REALM, tick, contact, life, hostile) == (
					CombatRootQueue.Result.ACCEPTED) and kernel.finish_delivery(held)
		return false

	func hp(id: StringName) -> Quantity:
		return kernel.actor_snapshot(id).hp.amount

	func layer(id: StringName) -> CombatantState.Barrier:
		for barrier: CombatantState.Barrier in kernel.actor_snapshot(HERO).barriers:
			if barrier.id == id:
				return barrier
		return null


func test_fracture_compresses_only_the_owners_sigil_inside_the_selected_field() -> void:
	for inside: bool in [false, true]:
		var arena := Arena.new(&"W03", &"H04", false, &"", &"", {&"H04": true})
		assert_false(&"H04" in RunPreparation.available(arena.catalog, CatalogEntry.Kind.HERO, {}))
		assert_true(arena.add(&"aim", 100, 0, 200))
		assert_true(arena.add(&"partner", 0, 5, 100, FRIEND))
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		var prep := RunPreparation.select(arena.catalog, &"H01", &"W03", [&"", &""], slots, {})
		var partner := StarterCombat.create(arena.rules, arena.catalog, prep, arena.kernel, arena.geometry,
			&"partner", HOSTILE, HOSTILE, BLOCKER)
		var impacts: Dictionary[StringName, int] = {}
		for tick: int in range(1, 31):
			if tick == 1:
				assert_eq(arena.attack(tick), Committed)
				assert_eq(partner.try_weapon(tick, PlayerTargeting.new(), arena.candidates), Committed)
			if tick == 2:
				assert_eq(arena.combat.try_manual(tick, RealmSweep.Point.new(200, 0)), StarterCombat.Attempt.REJECTED)
				assert_eq(arena.combat.try_manual(tick, RealmSweep.Point.new(100 if inside else 0, 0)), Committed)
			if tick == 3:
				assert_eq(arena.combat.try_manual(tick, RealmSweep.Point.new(100, 0)), StarterCombat.Attempt.REJECTED)
			assert_true(arena.combat.advance(tick))
			assert_true(partner.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				if hit.family != &"W03":
					continue
				assert_false(impacts.has(hit.origin.owner))
				impacts[hit.origin.owner] = tick
		assert_eq(impacts.get(HERO, -1), 13 if inside else 25)
		assert_eq(impacts.get(&"partner", -1), 25)


func test_temporal_echo_rechecks_the_impact_area_after_owner_death_and_mitigates_once() -> void:
	for enters: bool in [false, true]:
		var arena := Arena.new(&"W01", &"H04", false, &"", &"", {&"H04": true})
		assert_true(arena.add(&"aim", 30, 0, 100))
		assert_true(arena.add(&"arrival", 150, 0, 100, HOSTILE, false))
		var defense := CombatantState.Defense.new()
		defense.vulnerability = Quantity.from_count(2)
		assert_true(arena.kernel.set_defense(&"aim", 1, CombatAction.Damage.PHYSICAL, defense))
		assert_eq(arena.attack(1), Committed)
		arena.settle(1)
		assert_eq(arena.hp(&"aim").native_at_scale(0), 60)
		assert_true(arena.move(&"aim", 80, 0))
		assert_true(arena.swing_from(&"aim", HERO, 250, 2))
		arena.settle(2)
		if enters:
			assert_true(arena.move(&"arrival", 34, 0))
		var hits := arena.settle(31)
		assert_eq(hits.size(), 1 if enters else 0)
		if hits.size() == 1:
			assert_eq(hits[0].family, StarterCombatRules.TEMPORAL_ECHO)
			assert_eq(hits[0].origin.owner, HERO)
		assert_eq(arena.hp(&"arrival").native_at_scale(0), 95 if enters else 100)
		assert_null(arena.kernel.next_due())


func test_temporal_echo_from_arrow_preserves_contact_point_and_one_typed_damage_snapshot() -> void:
	var arena := Arena.new(&"W02", &"H04", false, &"", &"", {&"H04": true})
	assert_true(arena.add(&"aim", 34, 0, 100))
	assert_true(arena.add(&"arrival", 150, 0, 100, HOSTILE, false))
	assert_eq(arena.attack(1), Committed)
	var due := -1
	for tick: int in range(1, 41):
		assert_true(arena.combat.advance(tick))
		for hit: CombatKernel.Hit in arena.settle(tick):
			if hit.family == &"W02":
				var cues := arena.kernel.echo_cues(HERO, REALM)
				assert_eq(cues.size(), 1)
				if cues.size() == 1:
					assert_almost_eq(cues[0].center.x, 31.0, 0.000001)
					due = cues[0].due
					cues[0].center.x = 999
				assert_true(arena.move(&"aim", 100, 0))
				assert_true(arena.move(&"arrival", 20, 0))
			else:
				assert_eq(tick, due)
				assert_eq(hit.family, StarterCombatRules.TEMPORAL_ECHO)
				assert_eq(hit.target, &"arrival")
	assert_eq(arena.hp(&"aim").native_at_scale(0), 76)
	assert_eq(arena.hp(&"arrival").native_at_scale(0), 94)
	assert_null(arena.kernel.next_due())


func test_fracture_compresses_owned_echo_and_bleed_when_seat_and_actor_ids_differ() -> void:
	var seat := &"seat_a"
	var arena := Arena.new(&"W01", &"H04", false, &"R01", &"", {&"H04": true}, seat)
	assert_true(arena.add(&"target", 30, 0, 500))
	assert_true(arena.add(&"partner", 0, 4, 100, FRIEND))
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(arena.catalog, &"H01", &"W01", [&"R01", &""], slots, {})
	var partner := StarterCombat.create(arena.rules, arena.catalog, prep, arena.kernel, arena.geometry,
		&"partner", HOSTILE, HOSTILE, BLOCKER)
	var mine: Array[int] = []
	var theirs: Array[int] = []
	var echoes: Array[int] = []
	for tick: int in range(1, 183):
		if tick == 1:
			assert_eq(arena.attack(tick), Committed)
			assert_eq(partner.try_weapon(tick, PlayerTargeting.new(), arena.candidates), Committed)
			assert_eq(arena.combat.try_manual(tick, RealmSweep.Point.new(30, 0)), Committed)
		if tick == 32:
			assert_true(arena.move(&"target", 100, 0))
		assert_true(arena.combat.advance(tick))
		for hit: CombatKernel.Hit in arena.settle(tick):
			if hit.family == &"R01.bleed":
				if hit.origin.owner == seat:
					mine.append(tick)
				else:
					theirs.append(tick)
			if hit.family == StarterCombatRules.TEMPORAL_ECHO:
				assert_eq(hit.origin.owner, seat)
				echoes.append(tick)
		if tick == 2:
			var echo_deadlines: Array[int] = []
			for cue: StarterCombat.Cue in arena.combat.cues():
				if cue.id == StarterCombatRules.TEMPORAL_ECHO:
					echo_deadlines.append(cue.impact)
			assert_eq(echo_deadlines, [30])
	assert_eq(echoes, [16])
	assert_eq(mine, [31, 91, 151])
	assert_eq(theirs, [61, 121, 181])
	assert_null(arena.kernel.next_due())


func test_zero_charge_harmonic_burst_links_one_reached_hostile_and_commits_an_empty_cast() -> void:
	var arena := Arena.new(&"W02", &"H03")
	assert_true(arena.add(&"blocked", 16, 0, 100))
	assert_true(arena.wall(8, -5, 5))
	assert_true(arena.add(&"ally", -7, 0, 100, FRIEND))
	assert_true(arena.add(&"near", -30, 0, 100))
	assert_true(arena.add(&"far", -50, 0, 100))
	assert_eq(arena.combat.try_manual(1), Committed)
	var hits := arena.settle(1)
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_eq(hits[0].target, &"near")
		assert_eq(hits[0].family, StarterCombatRules.HARMONIC_BURST)
		assert_eq(hits[0].origin.owner, HERO)
		assert_eq(hits[0].components[0].kind, CombatAction.Damage.MAGICAL)
	assert_true(arena.move(&"near", -200, 0))
	assert_true(arena.move(&"far", -220, 0))
	var ready := 1 + arena.rules.harmonic_cooldown
	assert_eq(arena.combat.try_manual(ready - 1), StarterCombat.Attempt.REJECTED)
	assert_eq(arena.combat.try_manual(ready), Committed)
	assert_true(arena.settle(ready).is_empty())
	assert_eq(arena.combat.try_manual(ready + 1), StarterCombat.Attempt.REJECTED)
	assert_eq(arena.hp(&"blocked").native_at_scale(0), 100)


func test_conductor_earns_once_per_linked_life_and_spends_only_on_committed_casts() -> void:
	var arena := Arena.new(&"W01", StarterCombatRules.CONDUCTOR)
	for i: int in 7:
		assert_true(arena.add(StringName("foe%d" % i), 30 + i * 3, 0, 10000))
	var tick := 1
	for charges: int in 6:
		assert_eq(arena.combat.resonance, charges)
		assert_eq(arena.combat.try_manual(tick), Committed)
		assert_eq(arena.settle(tick).size(), charges + 1)
		assert_eq(arena.combat.resonance, 0)
		assert_eq(arena.attack(tick + 1), Committed)
		assert_eq(arena.settle(tick + 1).size(), 7)
		var earned := mini(charges + 1, 5)
		assert_eq(arena.combat.resonance, earned)
		assert_eq(arena.combat.try_manual(tick + 2), StarterCombat.Attempt.REJECTED)
		assert_eq(arena.attack(tick + 61), Committed)
		arena.settle(tick + 61)
		assert_eq(arena.combat.resonance, earned)
		tick += arena.rules.harmonic_cooldown
	for i: int in 7:
		assert_true(arena.move(StringName("foe%d" % i), 400 + i * 10, 0))
	assert_eq(arena.combat.try_manual(tick), Committed)
	assert_true(arena.settle(tick).is_empty())
	assert_eq(arena.combat.resonance, 0)


func test_authored_weapons_are_distinct_and_usable_with_a_different_starter_hero() -> void:
	for weapon: StringName in [&"W01", &"W02", &"W03"]:
		var arena := Arena.new(weapon, &"H02")
		assert_not_null(arena.combat)
		assert_null(arena.layer(StarterCombatRules.HARVEST))
		assert_eq(arena.combat.try_manual(1), StarterCombat.Attempt.REJECTED)
		assert_true(arena.add(&"target", 30, 0, 100))
		assert_eq(arena.attack(1), Committed)
	var invalid := Arena.new(&"W01")
	var duplicate := invalid.rules.duplicate() as StarterCombatRules
	duplicate.weapons = [invalid.rules.weapons[0], invalid.rules.weapons[0], invalid.rules.weapons[2]]
	assert_false(duplicate.is_valid_for(invalid.catalog))


func test_sword_cleaves_each_intersecting_enemy_while_moving_and_pays_once() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"aim", 30, 0, 100))
	assert_true(arena.add(&"edge", 42, 60, 100))
	assert_true(arena.add(&"outside", 19, 60, 100))
	assert_true(arena.add(&"rear", -60, 0, 100))
	assert_true(arena.add(&"sealed", 48, -43, 100))
	assert_true(arena.wall(24, -35, -18))
	var controls := PlayerControlState.new()
	controls.apply(PlayerCommand.new(PlayerCommand.MOVE_AXES, 0.0, 1.0))
	var position := controls.step(arena.geometry, HERO, 0, BLOCKER, 100.0, 0.01)
	assert_eq(position.y, 1.0)
	assert_eq(arena.attack(1, {MANA: Quantity.from_count(2)}), Committed)
	assert_true(arena.combat.advance(1))
	var hits := arena.settle(1)
	assert_eq(hits.size(), 2)
	for hit: CombatKernel.Hit in hits:
		assert_eq(hit.family, &"W01")
		assert_eq(hit.origin.activation, 1)
		assert_eq(hit.components[0].kind, CombatAction.Damage.PHYSICAL)
	assert_eq(arena.hp(&"aim").native_at_scale(0), 80)
	assert_eq(arena.hp(&"edge").native_at_scale(0), 80)
	for id: StringName in [&"outside", &"rear", &"sealed"]:
		assert_eq(arena.hp(id).native_at_scale(0), 100)
	assert_eq(arena.kernel.actor_snapshot(HERO).resources[MANA].native_at_scale(0), 8)
	assert_eq(controls.step(arena.geometry, HERO, 0, BLOCKER, 100.0, 0.01).y, 2.0)


func test_bleed_refresh_keeps_first_tick_and_new_stack_waits_until_following_tick() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R01")
	assert_true(arena.add(&"aim", 30, 0, 200))
	for tick: int in [1, 61]:
		if tick == 61:
			for step: int in range(2, tick):
				assert_true(arena.combat.advance(step))
				arena.settle(step)
		assert_eq(arena.attack(tick), Committed)
		assert_true(arena.combat.advance(tick))
		var hits := arena.settle(tick)
		assert_eq(hits.size(), 1 if tick == 1 else 2)
	assert_eq(arena.hp(&"aim").native_at_scale(0), 157)
	for tick: int in [121, 181, 241]:
		var ticks := arena.settle(tick)
		assert_eq(ticks.size(), 2)
		for hit: CombatKernel.Hit in ticks:
			assert_eq(hit.family, &"R01.bleed")
			assert_eq(hit.origin.owner, HERO)
	assert_null(arena.kernel.next_due())
	assert_eq(arena.hp(&"aim").native_at_scale(0), 139)


func test_two_sword_users_bleed_one_target_on_independent_clocks() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R01")
	assert_true(arena.add(&"aim", 30, 0, 200))
	assert_true(arena.add(&"partner", 0, 2, 100, FRIEND))
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(arena.catalog, &"H01", &"W01", [&"R01", &""], slots, {})
	var partner := StarterCombat.create(arena.rules, arena.catalog, prep, arena.kernel, arena.geometry,
		&"partner", HOSTILE, HOSTILE, BLOCKER)
	assert_eq(arena.attack(1), Committed)
	arena.settle(1)
	assert_eq(partner.try_weapon(11, PlayerTargeting.new(), arena.candidates), Committed)
	arena.settle(11)
	for at: int in [61, 71, 121, 131, 181, 191]:
		var hits := arena.settle(at)
		assert_eq(hits.size(), 1)
		if hits.size() == 1:
			assert_eq(hits[0].family, &"R01.bleed")
			assert_eq(hits[0].origin.owner, HERO if at % 60 == 1 else &"partner")
	assert_null(arena.kernel.next_due())


func test_thunder_rupture_consumes_each_secondary_targets_owned_pre_arc_stack_once() -> void:
	for rune: StringName in [&"", &"R01"]:
		var arena := Arena.new(&"W01", &"H01", false, &"R02", rune)
		assert_true(arena.add(&"front", 30, 0, 200))
		assert_true(arena.add(&"flank", 40, 10, 200))
		assert_eq(arena.attack(1), Committed)
		var hits := arena.settle(1)
		var counts: Dictionary[StringName, int] = {}
		for hit: CombatKernel.Hit in hits:
			counts[hit.family] = counts.get(hit.family, 0) + 1
		assert_eq(counts.get(&"W01", 0), 2)
		assert_eq(counts.get(&"R02.lightning", 0), 2)
		assert_eq(counts.get(&"RP01.thunder_rupture", 0), 2 if rune == &"R01" else 0)
		assert_eq(arena.hp(&"front").native_at_scale(0), 164 if rune == &"R01" else 170)
		assert_null(arena.kernel.next_due())


func test_bleed_keeps_committed_offense_after_owner_death_and_uses_live_defense() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R01")
	assert_true(arena.add(&"aim", 30, 0, 200))
	var bonus := QuantityFormula.BonusCategory.new()
	bonus.values = [Quantity.from_count(1)]
	assert_eq(arena.combat.try_weapon(1, arena.targeting, arena.candidates, [bonus]), Committed)
	bonus.values.clear()
	arena.settle(1)
	assert_eq(arena.hp(&"aim").native_at_scale(0), 160)
	assert_true(arena.swing_from(&"aim", HERO, 250, 2))
	arena.settle(2)
	assert_false(arena.kernel.actor_snapshot(HERO).is_alive())
	var defense := CombatantState.Defense.new()
	defense.vulnerability = Quantity.from_count(2)
	assert_true(arena.kernel.set_defense(&"aim", 1, CombatAction.Damage.PHYSICAL, defense))
	var hits := arena.settle(61)
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_eq(hits[0].origin.owner, HERO)
	assert_eq(arena.hp(&"aim").native_at_scale(0), 148)
	defense.immune = true
	assert_true(arena.kernel.set_defense(&"aim", 1, CombatAction.Damage.PHYSICAL, defense))
	arena.settle(121)
	assert_eq(arena.hp(&"aim").native_at_scale(0), 148)


func test_lethal_lightning_rechecks_bleed_before_recording_death_statuses() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R01", &"R02")
	assert_true(arena.add(&"front", 30, 0, 25))
	assert_true(arena.add(&"flank", 40, 10, 100))
	assert_eq(arena.attack(1), Committed)
	var lethal := 0
	for hit: CombatKernel.Hit in arena.settle(1):
		if hit.eliminated:
			lethal += 1
			assert_eq(hit.family, &"R02.lightning")
			assert_false(hit.death_statuses.has(&"R01"))
	assert_eq(lethal, 1)


func test_lightning_cannot_rupture_a_teammates_only_bleed() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R01", &"R02")
	assert_true(arena.add(&"primary", 30, 0, 200))
	assert_true(arena.add(&"secondary", 85, 0, 200))
	assert_true(arena.add(&"partner", 120, 0, 100, FRIEND))
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var prep := RunPreparation.select(arena.catalog, &"H01", &"W01", [&"R01", &""], slots, {})
	var partner := StarterCombat.create(arena.rules, arena.catalog, prep, arena.kernel, arena.geometry,
		&"partner", HOSTILE, HOSTILE, BLOCKER)
	assert_eq(partner.try_weapon(1, PlayerTargeting.new(), arena.candidates), Committed)
	assert_eq(arena.settle(1).size(), 1)
	assert_eq(arena.attack(11), Committed)
	var hits := arena.settle(11)
	assert_eq(hits.size(), 2)
	if hits.size() == 2:
		assert_eq(hits[1].family, &"R02.lightning")
		assert_eq(hits[1].target, &"secondary")
	var ticks := arena.settle(61)
	assert_eq(ticks.size(), 1)
	if ticks.size() == 1:
		assert_eq(ticks[0].origin.owner, &"partner")
		assert_eq(ticks[0].target, &"secondary")


func test_blood_wake_samples_real_motion_only_after_owned_bleed_exists() -> void:
	for resistance: float in [0.0, 1.0]:
		var arena := Arena.new(&"W01", &"H01", false, &"R01", &"R03")
		assert_true(arena.add(&"aim", 30, 0, 250, HOSTILE, true, &"", resistance))
		assert_true(arena.add(&"visitor", 150, 0, 100, HOSTILE, false))
		for tick: int in range(1, 108):
			if tick in [1, 61]:
				assert_eq(arena.attack(tick), Committed)
			if tick in [76, 106]:
				assert_true(arena.move(&"visitor", 60, 2))
			elif tick == 91:
				assert_true(arena.move(&"visitor", 60, 20))
			assert_true(arena.combat.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				if hit.family == &"RP02.blood_wake":
					assert_eq(resistance, 0.0)
					assert_has([76, 91, 106], tick)
		assert_eq(arena.hp(&"visitor").native_at_scale(0), 92 if resistance == 0.0 else 100)
		assert_eq(arena.kernel.next_due().tick, 121)


func test_force_translates_all_body_circles_and_clips_at_an_unstruck_members_wall() -> void:
	var arena := Arena.new(&"W01", &"H01", false, &"R03")
	assert_true(arena.add(&"aim", 30, 0, 100))
	assert_true(arena.geometry.add_circle(&"aim", 1, RealmSweep.Point.new(30, 90), 3, HOSTILE))
	assert_true(arena.wall(44, 84, 96))
	assert_eq(arena.attack(1), Committed)
	var hits := arena.settle(1)
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_not_null(hits[0].displacement)
		assert_eq(hits[0].displacement.stopped_by.size(), 1)
	var primary := arena.geometry.circle_center(&"aim", 0)
	var secondary := arena.geometry.circle_center(&"aim", 1)
	assert_almost_eq(primary.x, 41.0, 0.000001)
	assert_eq(secondary.x, primary.x)
	assert_eq(secondary.y - primary.y, 90.0)


func test_sword_force_uses_the_same_compound_contact_when_slots_register_in_reverse() -> void:
	for reversed: bool in [false, true]:
		var arena := Arena.new(&"W01", &"H01", false, &"R03")
		assert_true(arena.move(HERO, 0, 40))
		var secondary_pose := RealmSweep.Point.new(30, 55)
		if reversed:
			assert_true(arena.geometry.add_circle(&"beast", 1, secondary_pose, 3, HOSTILE))
		assert_true(arena.add(&"beast", 30, 25, 100, HOSTILE, false))
		if not reversed:
			assert_true(arena.geometry.add_circle(&"beast", 1, secondary_pose, 3, HOSTILE))
		assert_true(arena.add(&"aim", 70, 40, 100))
		assert_eq(arena.attack(1), Committed)
		var hits := arena.settle(1)
		var contacted: Array[int] = []
		for hit: CombatKernel.Hit in hits:
			if hit.target == &"beast":
				contacted.append(hit.shape)
		assert_eq(contacted, [0])
		var primary := arena.geometry.circle_center(&"beast", 0)
		var secondary := arena.geometry.circle_center(&"beast", 1)
		assert_almost_eq(primary.y, 16.055728, 0.000001)
		assert_almost_eq(secondary.y - primary.y, 30.0, 0.000001)


func test_force_sword_uses_actual_target_direction_resistance_and_wall_clearance() -> void:
	for rune: StringName in [&"", &"R03"]:
		var arena := Arena.new(&"W01", &"H01", false, rune)
		assert_true(arena.add(&"aim", 15, 0, 100))
		assert_true(arena.add(&"flank", 30, 40, 100, HOSTILE, true, &"", 0.5))
		assert_true(arena.add(&"immune", 48, -24, 100, HOSTILE, true, &"", 1.0))
		assert_true(arena.wall(26, -6, 6))
		assert_eq(arena.attack(1), Committed)
		var hits := arena.settle(1)
		assert_eq(hits.size(), 3)
		var flank := arena.geometry.circle_center(&"flank", 0)
		assert_eq(flank.x, 36.0 if rune == &"R03" else 30.0)
		assert_eq(flank.y, 48.0 if rune == &"R03" else 40.0)
		var aim := arena.geometry.circle_center(&"aim", 0)
		if rune == &"R03":
			assert_gt(aim.x, 15.0)
			assert_lte(aim.x, 23.0)
		else:
			assert_eq(aim.x, 15.0)
		assert_eq(arena.geometry.circle_center(&"immune", 0).x, 48.0)
		for id: StringName in [&"aim", &"flank", &"immune"]:
			assert_eq(arena.hp(id).native_at_scale(0), 80)


func test_force_arrow_keeps_its_heading_and_staff_pushes_from_its_committed_center() -> void:
	for weapon: StringName in [&"W02", &"W03"]:
		var arena := Arena.new(weapon, &"H01", false, &"R03")
		assert_true(arena.add(&"aim", 50, 0, 100))
		assert_true(arena.add(&"interceptor", 20, 80, 100, HOSTILE, false))
		assert_eq(arena.attack(1), Committed)
		assert_true(arena.move(&"aim", 50, 120))
		assert_true(arena.move(&"interceptor", 32 if weapon == &"W02" else 50, 2 if weapon == &"W02" else -18))
		for tick: int in range(1, 26):
			assert_true(arena.combat.advance(tick))
			arena.settle(tick)
		var pose := arena.geometry.circle_center(&"interceptor", 0)
		assert_eq(pose.x, 52.0 if weapon == &"W02" else 50.0)
		assert_eq(pose.y, 2.0 if weapon == &"W02" else -38.0)
		assert_eq(arena.hp(&"interceptor").native_at_scale(0), 76)


func test_lightning_and_storm_relay_choose_from_the_struck_and_displaced_positions() -> void:
	for force: StringName in [&"", &"R03"]:
		for resistance: float in [0.0, 1.0]:
			var arena := Arena.new(&"W02", &"H01", false, &"R02", force)
			assert_true(arena.add(&"primary", 50, 0, 100, HOSTILE, true, &"", resistance))
			assert_true(arena.add(&"first", 30, 32, 100, HOSTILE, false))
			assert_true(arena.add(&"second", 90, 30, 100, HOSTILE, false))
			assert_eq(arena.attack(1), Committed)
			var hits: Array[CombatKernel.Hit] = []
			for tick: int in range(1, 8):
				assert_true(arena.combat.advance(tick))
				hits.append_array(arena.settle(tick))
			var relay := force == &"R03" and resistance == 0.0
			assert_eq(hits.size(), 3 if relay else 2)
			assert_eq(arena.hp(&"primary").native_at_scale(0), 76)
			assert_eq(arena.hp(&"first").native_at_scale(0), 90)
			assert_eq(arena.hp(&"second").native_at_scale(0), 90 if relay else 100)
			for hit: CombatKernel.Hit in hits:
				if hit.target == &"primary":
					continue
				assert_eq(hit.origin.owner, HERO)
				assert_eq(hit.parent, hits[0].event)
				assert_eq(hit.wave, hits[0].wave + 1)
				assert_eq(hit.family, &"R02.lightning" if hit.target == &"first" else &"RP03.storm_relay")
				assert_eq(hit.arc_start.x, 50.0 if hit.target == &"first" else 70.0)
				assert_eq(hit.arc_end.x, 30.0 if hit.target == &"first" else 90.0)


func test_lightning_and_relay_break_equal_distance_ties_by_stable_target_id() -> void:
	for reversed: bool in [false, true]:
		var arena := Arena.new(&"W02", &"H01", false, &"R02", &"R03")
		assert_true(arena.move(HERO, 0, 45))
		assert_true(arena.add(&"primary", 50, 45, 100))
		var ids: Array[StringName] = [&"alpha", &"beta", &"north", &"south"]
		if reversed:
			ids.reverse()
		for id: StringName in ids:
			var initial := id in [&"alpha", &"beta"]
			assert_true(arena.add(id, 40 if initial else 75, 35 if id in [&"alpha", &"north"] else 55,
				100, HOSTILE, false))
		assert_eq(arena.attack(1), Committed)
		var arcs: Dictionary[StringName, StringName] = {}
		for tick: int in range(1, 8):
			assert_true(arena.combat.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				if hit.family != &"W02":
					assert_false(arcs.has(hit.family))
					arcs[hit.family] = hit.target
		assert_eq(arcs.get(&"R02.lightning"), &"alpha")
		assert_eq(arcs.get(&"RP03.storm_relay"), &"north")


func test_sword_cleave_gives_the_same_parent_the_lethal_arc_when_shapes_register_in_reverse() -> void:
	for reversed: bool in [false, true]:
		var arena := Arena.new(&"W01", &"H01", false, &"R02", &"R01")
		assert_true(arena.move(HERO, 0, 40))
		var ids: Array[StringName] = [&"alpha", &"beta"]
		if reversed:
			ids.reverse()
		for id: StringName in ids:
			assert_true(arena.add(id, 60, 18 if id == &"alpha" else 62, 100))
		assert_true(arena.add(&"gamma", 95, 40, 10, HOSTILE, false))
		assert_eq(arena.attack(1), Committed)
		var alpha_event := 0
		var winning_parents: Array[int] = []
		for hit: CombatKernel.Hit in arena.settle(1):
			if hit.family == &"W01" and hit.target == &"alpha":
				assert_eq(hit.origin.delivery_part, 1)
				alpha_event = hit.event
			if hit.family == &"R02.lightning" and hit.target == &"gamma" and hit.eliminated:
				winning_parents.append(hit.parent)
		assert_gt(alpha_event, 0)
		assert_eq(winning_parents, [alpha_event])


func test_lightning_refuses_a_secondary_behind_cover_or_outside_reach() -> void:
	var arena := Arena.new(&"W02", &"H01", false, &"R02")
	assert_true(arena.add(&"primary", 50, 0, 100))
	assert_true(arena.add(&"covered", 78, 12, 100, HOSTILE, false))
	assert_true(arena.add(&"distant", 50, 75, 100, HOSTILE, false))
	assert_true(arena.wall(62, -15, 20))
	assert_eq(arena.attack(1), Committed)
	var hits: Array[CombatKernel.Hit] = []
	for tick: int in range(1, 8):
		assert_true(arena.combat.advance(tick))
		hits.append_array(arena.settle(tick))
	assert_eq(hits.size(), 1)
	assert_eq(arena.hp(&"covered").native_at_scale(0), 100)
	assert_eq(arena.hp(&"distant").native_at_scale(0), 100)


func test_bow_keeps_its_launch_heading_through_a_paid_miss_and_interception() -> void:
	for intercepted: bool in [false, true]:
		var arena := Arena.new(&"W02")
		assert_true(arena.add(&"selected", 100, 0, 100))
		assert_true(arena.add(&"interloper", 55, 60, 100, HOSTILE, false))
		assert_true(arena.add(&"farther", 125, 0, 100, HOSTILE, false))
		if not intercepted:
			assert_true(arena.move(&"farther", 125, -80))
		assert_eq(arena.attack(1, {MANA: Quantity.from_count(2)}), Committed)
		assert_true(arena.combat.advance(1))
		assert_true(arena.settle(1).is_empty())
		assert_true(arena.move(&"selected", 100, 80))
		if intercepted:
			assert_true(arena.move(&"interloper", 55, 0))
		assert_eq(arena.attack(2), StarterCombat.Attempt.REJECTED)
		var received: Array[CombatKernel.Hit] = []
		for tick: int in range(2, 48):
			assert_true(arena.combat.advance(tick))
			received.append_array(arena.settle(tick))
		assert_eq(received.size(), int(intercepted))
		assert_eq(arena.hp(&"selected").native_at_scale(0), 100)
		assert_eq(arena.hp(&"farther").native_at_scale(0), 100)
		assert_eq(arena.hp(&"interloper").native_at_scale(0), 76 if intercepted else 100)
		assert_eq(arena.kernel.actor_snapshot(HERO).resources[MANA].native_at_scale(0), 8)


func test_staff_rejects_sealed_placement_and_uses_frozen_offense_at_a_stationary_sigil() -> void:
	var arena := Arena.new(&"W03")
	assert_true(arena.add(&"selected", 160, 0, 100))
	assert_true(arena.add(&"arrival", 160, 110, 100, HOSTILE, false))
	assert_true(arena.wall(80, -20, 20))
	assert_eq(arena.attack(1, {MANA: Quantity.from_count(3)}), StarterCombat.Attempt.REJECTED)
	assert_eq(arena.kernel.actor_snapshot(HERO).resources[MANA].native_at_scale(0), 10)
	assert_true(arena.geometry.remove_mutable(&"wall", 0))
	var doubled := QuantityFormula.BonusCategory.new()
	doubled.values.append(Quantity.from_count(1))
	assert_eq(arena.combat.try_weapon(1, arena.targeting, arena.candidates, [doubled]), Committed)
	assert_eq(arena.combat.cues()[0].impact, 25)
	assert_eq(arena.combat.cues()[0].reach, 65.0)
	doubled.values.clear()
	assert_true(arena.move(&"selected", 160, -110))
	assert_true(arena.move(&"arrival", 160, 20))
	var defense := CombatantState.Defense.new()
	defense.rating = Quantity.from_count(100)
	assert_true(arena.kernel.set_defense(&"arrival", 1, CombatAction.Damage.MAGICAL, defense))
	for tick: int in range(1, 25):
		assert_true(arena.combat.advance(tick))
		assert_true(arena.settle(tick).is_empty())
	assert_true(arena.combat.advance(25))
	var hits := arena.settle(25)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].components[0].kind, CombatAction.Damage.MAGICAL)
	assert_eq(arena.hp(&"selected").native_at_scale(0), 100)
	assert_eq(arena.hp(&"arrival").native_at_scale(0), 76)


func test_undying_distinguishes_own_ally_and_object_kills_and_caps_personal_harvest() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"ally", 0, 20, 100, FRIEND))
	assert_true(arena.add(&"familiar", 0, -20, 100, FRIEND, true, HERO))
	assert_true(arena.add(&"uncredited", 24, 0, 10))
	assert_true(arena.swing_from(&"ally", &"uncredited", 20, 1))
	assert_eq(arena.settle(1).size(), 1)
	assert_null(arena.layer(StarterCombatRules.HARVEST))
	assert_true(arena.add(&"object", 26, 0, 10, OBJECT))
	assert_true(arena.swing_from(HERO, &"object", 20, 2, false))
	assert_eq(arena.settle(2).size(), 1)
	assert_null(arena.layer(StarterCombatRules.HARVEST))
	assert_true(arena.add(&"familiar_kill", 34, 0, 8))
	assert_true(arena.swing_from(&"familiar", &"familiar_kill", 20, 3))
	arena.settle(3)
	assert_eq(arena.layer(StarterCombatRules.HARVEST).pool.amount.native_at_scale(0), 2)
	for index: int in 18:
		assert_true(arena.add(StringName("crowd_%02d" % index), 42, float(index - 9), 10))
	assert_eq(arena.attack(4), Committed)
	assert_true(arena.combat.advance(4))
	assert_eq(arena.settle(4).size(), 18)
	assert_eq(arena.layer(StarterCombatRules.HARVEST).pool.amount.native_at_scale(0), 30)
	assert_null(arena.layer(StarterCombatRules.HARVEST).expires)


func test_post_death_committed_sigil_eliminates_without_harvest_before_or_after_rescue() -> void:
	var arena := Arena.new(&"W03")
	assert_true(arena.add(&"target", 120, 0, 10))
	assert_true(arena.add(&"slayer", -100, 0, 100, HOSTILE, false))
	assert_eq(arena.attack(1), Committed)
	assert_true(arena.combat.advance(1))
	assert_true(arena.settle(1).is_empty())
	assert_true(arena.swing_from(&"slayer", HERO, 300, 2))
	assert_true(arena.combat.advance(2))
	assert_eq(arena.settle(2).size(), 1)
	assert_eq(arena.hp(HERO).sign_value, 0)
	for tick: int in range(3, 25):
		assert_true(arena.combat.advance(tick))
		assert_true(arena.settle(tick).is_empty())
	assert_true(arena.combat.advance(25))
	var released := arena.settle(25)
	assert_eq(released.size(), 1)
	if released.size() == 1:
		assert_eq(released[0].target, &"target")
		assert_true(released[0].eliminated)
		assert_eq(released[0].granted_barrier, &"")
	assert_null(arena.layer(StarterCombatRules.HARVEST))
	assert_true(arena.kernel.revive_player(HERO, 1, CombatInstant.at_tick(26), Quantity.from_count(5, 1), 60))
	assert_eq(arena.kernel.actor_snapshot(HERO).life, 2)
	assert_null(arena.layer(StarterCombatRules.HARVEST))


func test_same_wave_mutual_elimination_grants_no_life_harvest() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"target", 30, 0, 10))
	assert_eq(arena.attack(1), Committed)
	assert_true(arena.combat.advance(1))
	assert_true(arena.swing_from(&"target", HERO, 300, 1))
	var hits := arena.settle(1)
	assert_eq(hits.size(), 2)
	for hit: CombatKernel.Hit in hits:
		assert_true(hit.eliminated)
		assert_eq(hit.granted_barrier, &"")
	assert_eq(arena.hp(HERO).sign_value, 0)
	assert_eq(arena.hp(&"target").sign_value, 0)
	assert_null(arena.layer(StarterCombatRules.HARVEST))


func test_siphon_converts_actual_hp_and_keeps_temporary_layer_before_harvest() -> void:
	var arena := Arena.new(&"W02")
	assert_true(arena.add(&"sacrificial", 10, 0, 10))
	assert_true(arena.add(&"durable", 50, 0, 100))
	assert_eq(arena.combat.try_manual(1), Committed)
	assert_true(arena.combat.advance(1))
	assert_eq(arena.settle(1).size(), 2)
	assert_eq(arena.layer(StarterCombatRules.SIPHON).pool.amount.native_at_scale(1), 255)
	assert_eq(arena.layer(StarterCombatRules.HARVEST).pool.amount.native_at_scale(0), 2)
	assert_eq(arena.hp(HERO).native_at_scale(0), 100)
	assert_true(arena.combat.advance(2))
	assert_true(arena.swing_from(&"durable", HERO, 33, 2))
	var hits := arena.settle(2)
	assert_eq(hits[0].components[0].barriers[0].id, StarterCombatRules.SIPHON)
	assert_eq(hits[0].components[0].barriers[1].id, StarterCombatRules.HARVEST)
	assert_eq(arena.hp(HERO).native_at_scale(1), 975)


func test_siphon_rejects_weaker_replacement_decays_and_preserves_miss_cooldown() -> void:
	var arena := Arena.new(&"W03", &"H01", true)
	assert_true(arena.add(&"body", 30, 0, 100))
	assert_true(arena.add(&"other", 50, 0, 100))
	assert_eq(arena.combat.try_manual(1), Committed)
	assert_true(arena.combat.advance(1))
	arena.settle(1)
	assert_eq(arena.layer(StarterCombatRules.SIPHON).pool.amount.native_at_scale(0), 36)
	assert_true(arena.move(&"other", 400, 0))
	assert_true(arena.combat.advance(2))
	arena.settle(2)
	assert_eq(arena.combat.try_manual(3), Committed)
	assert_true(arena.combat.advance(3))
	arena.settle(3)
	assert_eq(arena.layer(StarterCombatRules.SIPHON).expires.tick, 241)
	assert_eq(arena.layer(StarterCombatRules.SIPHON).pool.amount.native_at_scale(0), 36)
	assert_true(arena.move(&"body", 400, 0))
	assert_true(arena.combat.advance(4))
	arena.settle(4)
	assert_eq(arena.combat.try_manual(5), Committed)
	assert_true(arena.combat.advance(5))
	assert_true(arena.settle(5).is_empty())
	assert_eq(arena.combat.try_manual(6), StarterCombat.Attempt.REJECTED)
	for tick: int in range(6, 14):
		assert_true(arena.combat.advance(tick))
		arena.settle(tick)
	assert_eq(arena.layer(StarterCombatRules.SIPHON).pool.amount.native_at_scale(0), 35)
