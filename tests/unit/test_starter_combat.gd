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

	func _init(weapon: StringName, hero: StringName = &"H01", short_cooldown: bool = false) -> void:
		var source: CatalogBundle = load("res://src/catalog/starter_roster.tres")
		catalog = source.compile()
		if short_cooldown:
			rules = rules.duplicate() as StarterCombatRules
			rules.siphon_cooldown = 2
		var slots: Array[StringName] = []
		slots.resize(RunPreparation.CANDIDATE_SLOTS)
		slots.fill(&"")
		var prep := RunPreparation.select(catalog, hero, weapon, [&"", &""], slots, {})
		var actor := make_actor(HERO, 100, CombatOrigin.Provenance.SEAT)
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
			known: bool = true, controller: StringName = &"") -> bool:
		var actor := make_actor(id, hp, CombatOrigin.Provenance.SEAT if kind == FRIEND else CombatOrigin.Provenance.SPAWN)
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
