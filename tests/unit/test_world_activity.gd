extends GutTest

const Realm := &"silent_garden"
const Hero := &"hero"
const Attacker := &"wildborn"
const Enemy := &"legion"

class Room:
	var layout := WorldTopology.generate_optional(122, Realm)
	var exploration := WorldExploration.create(layout, [Hero])
	var kernel := CombatKernel.new()
	var world := WorldActivity.new(kernel, 122)
	var center := layout.center(WorldTopology.ENTRY)

	func enter() -> bool:
		var hero := CombatantState.new()
		hero.id = Hero
		hero.owner = Hero
		hero.realm = Realm
		hero.life = 1
		hero.max_hp = Quantity.from_count(20)
		hero.hp = QuantityLayerLedger.Pool.new(hero.max_hp, QuantityErrorBounds.new())
		return (world.register_realm(exploration) and kernel.add_actor(hero)
			and exploration.geometry().add_circle(Hero, 0, point(0, 0), 4, WorldActivity.ACTORS)
			and world.track_player(Hero))

	func point(x: float, y: float) -> RealmSweep.Point:
		return RealmSweep.Point.new(center.x + x, center.y + y)

	func add(id: StringName, x: float, foes: Array[StringName] = [], hunter: bool = false) -> bool:
		var rules := WorldEnemy.Rules.new()
		rules.faction = id
		rules.family = &"fixture"
		rules.foes = foes
		rules.hp = Quantity.from_count(10)
		rules.damage = Quantity.from_count(4)
		rules.radius = 4.0
		rules.sight = 80.0
		rules.attack_range = 48.0
		rules.attack_radius = 4.0
		rules.windup_ticks = 2
		rules.recovery_ticks = 2
		if hunter:
			rules.hunter = true
			rules.sight = 120.0
			rules.stride = 8.0
			rules.attack_range = 8.0
			rules.pursuit_ticks = 30
		return world.introduce_enemy(id, Realm, rules, point(x, 0))

	func hit(source: StringName, target_life: int, ordinal: int, commit_tick: int, due: int) -> bool:
		var state := kernel.actor_snapshot(source)
		var action := CombatAction.new()
		action.source = source
		action.source_life = state.life
		action.family = &"fixture_contact"
		action.origin = CombatOrigin.new()
		action.origin.provenance = state.provenance
		action.origin.owner = source
		action.origin.activation = ordinal
		action.origin.committed_at = CombatInstant.at_tick(commit_tick)
		var component := CombatAction.Component.new()
		component.base = Quantity.from_count(10)
		action.components = [component]
		var delivery := CombatDelivery.activate(kernel, action, Realm)
		if delivery == null:
			return false
		var floor := exploration.geometry()
		var where := floor.circle_center(Enemy, 0)
		var sample := floor.certify_circle_snapshot(Realm, where, 0.0, WorldActivity.ACTORS, source)
		return (sample.contacts.size() == 1 and sample.contacts[0].entity == Enemy
			and delivery.admit(due, sample.contacts[0], target_life, true) == CombatDelivery.Result.ADMITTED
			and delivery.finish())


func test_windup_preserves_its_attack_center_when_the_target_evades() -> void:
	for evades: bool in [false, true]:
		var room := Room.new()
		assert_true(room.enter())
		assert_true(room.add(Attacker, -24.0, [WorldEnemy.PARTY]))
		assert_not_null(room.world.advance(1))
		var windup: Array = room.world.snapshot().actors[Attacker][7][4]
		assert_eq(windup[0], 3)
		if evades:
			var floor := room.exploration.geometry()
			var moved := floor.displace_circle(Hero, 0, room.point(16, 0), WorldExploration.BLOCKER)
			assert_not_null(moved)
		assert_not_null(room.world.advance(2))
		var closed := room.world.advance(3)
		assert_eq(closed.combat.size(), 0 if evades else 1)
		assert_eq(room.kernel.actor_snapshot(Hero).hp.amount.native_at_scale(0), 20 if evades else 16)


func test_reanimated_enemy_has_a_new_life_and_old_contact_creates_no_award() -> void:
	var room := Room.new()
	assert_true(room.enter())
	assert_true(room.add(Attacker, -32.0))
	assert_true(room.add(Enemy, 24.0))
	assert_false(room.world.reanimate(Enemy, 1, Quantity.from_count(5, 1), 2))
	assert_true(room.hit(Hero, 1, 1, 1, 4))
	assert_true(room.hit(Attacker, 1, 1, 1, 2))
	assert_not_null(room.world.advance(1))
	var first := room.world.advance(2)
	assert_eq(first.combat[0].eliminations.size(), 1)
	assert_eq(first.combat[0].eliminations[0].origin.provenance, CombatOrigin.Provenance.SPAWN)
	assert_true(room.world.reanimate(Enemy, 1, Quantity.from_count(5, 1), 2))
	assert_false(room.world.reanimate(Enemy, 1, Quantity.from_count(5, 1), 2))
	var restored := room.kernel.actor_snapshot(Enemy)
	assert_eq(restored.id, Enemy)
	assert_eq(restored.life, 2)
	assert_eq(restored.hp.amount.native_at_scale(0), 5)
	assert_true(room.hit(Hero, 2, 2, 3, 5))
	assert_not_null(room.world.advance(3))
	var stale := room.world.advance(4)
	assert_true(stale.combat[0].eliminations.is_empty())
	assert_false(stale.combat[0].hits[0].accepted)
	assert_eq(room.kernel.actor_snapshot(Enemy).hp.amount.native_at_scale(0), 5)
	var final := room.world.advance(5)
	assert_eq(final.combat[0].eliminations.size(), 1)
	var earned := final.combat[0].eliminations[0]
	assert_eq(earned.target, Enemy)
	assert_eq(earned.target_life, 2)
	assert_eq(earned.origin.provenance, CombatOrigin.Provenance.SEAT)
	assert_eq(earned.origin.owner, Hero)
	assert_eq(room.world.snapshot().defeated_lives[Enemy], 2)


func test_hunter_uses_a_real_route_to_its_last_seen_point_when_vision_is_blocked() -> void:
	var room := Room.new()
	var floor := room.exploration.geometry()
	assert_true(room.enter())
	assert_true(room.add(&"hunter", -48.0, [], true))
	assert_true(floor.commit_circle_pose(&"hunter", 0, room.point(-48.0, 41.0)))
	assert_true(floor.commit_circle_pose(Hero, 0, room.point(56.0, 41.0)))
	assert_not_null(room.world.advance(1))
	var remembered: Array = room.world.snapshot().actors[&"hunter"][7][3]
	assert_eq(remembered[0], Hero)
	assert_true(room.exploration.place_route_solid(&"shut", room.point(0.0, 41.0), 18.0))
	var obstruction := floor.certify_frozen_path(Realm, floor.circle_center(&"hunter", 0),
		floor.circle_center(Hero, 0), 0.0, WorldExploration.BLOCKER)
	assert_false(obstruction.contacts.is_empty())
	assert_not_null(room.world.advance(2))
	assert_eq(room.world.snapshot().actors[&"hunter"][7][3], remembered)
	var around := false
	for tick: int in range(3, 17):
		assert_not_null(room.world.advance(tick))
		var here := floor.circle_center(&"hunter", 0)
		around = around or absf(here.y - room.point(0.0, 41.0).y) >= 8.0
		var contact := floor.certify_circle_snapshot(Realm, here, 4.0, WorldExploration.BLOCKER)
		assert_true(contact.contacts.is_empty() and contact.unresolved.is_empty())
	assert_true(around)
	assert_gt(floor.circle_center(&"hunter", 0).x, room.center.x)
