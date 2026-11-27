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

	func add(id: StringName, x: float, foes: Array[StringName] = [], hunter: bool = false,
			pursuit_ticks: int = 30) -> bool:
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
			rules.pursuit_ticks = pursuit_ticks
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


func test_world_health_samples_are_detached_and_refresh_after_cap_change() -> void:
	var room := Room.new()
	assert_true(room.enter())
	var old := room.kernel.actor_vitals(Hero)
	assert_null(room.kernel.actor_vitals(&"missing"))
	assert_eq(old.realm, Realm)
	assert_eq(old.life, 1)
	assert_true(room.kernel.change_max_hp(Hero, old.life, Quantity.from_count(30)))
	assert_eq(old.maximum.native_at_scale(0), 20)
	old.hp = Quantity.from_count(1)
	old.realm = &"elsewhere"
	var observed: Array = room.world.snapshot()["actors"][Hero]
	assert_eq(observed[0], Realm)
	assert_eq(observed[2], "20")
	assert_eq(observed[8], ["30", 0])


func test_first_entry_to_idle_realm_matches_early_registration_during_remote_combat() -> void:
	var reference: Array = []
	for defer_registration: bool in [false, true]:
		var room := Room.new()
		assert_true(room.enter())
		assert_true(room.add(Attacker, -24.0, [WorldEnemy.PARTY]))
		var layout := WorldTopology.generate_optional(122, &"hall_of_echoes")
		var interior := WorldExploration.create(layout, [Hero, &"visitor"])
		if not defer_registration:
			assert_true(room.world.register_realm(interior))
		var trace: Array = []
		for tick: int in range(1, 8):
			if tick == 4:
				assert_true(interior.view(&"visitor").explored.is_empty())
				if defer_registration:
					assert_true(room.world.register_realm(interior))
				var arrival := room.kernel.actor_snapshot(Hero)
				arrival.id = &"visitor"
				arrival.owner = arrival.id
				arrival.realm = layout.realm
				var entry := layout.center(WorldTopology.ENTRY)
				assert_true(room.kernel.add_actor(arrival))
				assert_true(interior.geometry().add_circle(arrival.id, 0, entry, 4, WorldActivity.ACTORS))
				assert_true(room.world.track_player(arrival.id))
				assert_true(interior.observe_seat(arrival.id, arrival.realm, entry))
				assert_eq(interior.view(arrival.id).visible.size(), 1)
				assert_true(interior.view(Hero).visible.is_empty())
			assert_not_null(room.world.advance(tick))
			trace.append([room.world.snapshot(), interior.view(&"visitor"), interior.view(Hero)])
		assert_lt(room.kernel.actor_snapshot(Hero).hp.amount.compare(Quantity.from_count(20)), 0)
		if defer_registration:
			assert_eq(trace, reference)
		else:
			reference = trace


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


func test_one_world_strike_reaches_a_multishape_actor_once() -> void:
	var room := Room.new()
	assert_true(room.enter())
	assert_true(room.exploration.geometry().add_circle(Hero, 1, room.point(1.0, 0.0), 3.0, WorldActivity.ACTORS))
	assert_true(room.add(Attacker, -24.0, [WorldEnemy.PARTY]))
	assert_not_null(room.world.advance(1))
	assert_not_null(room.world.advance(2))
	var released := room.world.advance(3)
	assert_not_null(released)
	if released != null and released.combat.size() == 1:
		assert_eq(released.combat[0].hits.size(), 1)
	else:
		fail_test("Expected one closed strike group")
	assert_eq(room.kernel.actor_snapshot(Hero).hp.amount.native_at_scale(0), 16)


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


func test_hunter_keeps_active_memory_over_a_nearby_faction_rival_then_engages_after_expiry() -> void:
	var room := Room.new()
	var floor := room.exploration.geometry()
	assert_true(room.enter())
	assert_true(room.add(&"hunter", -48.0, [&"rival"], true, 1))
	assert_true(floor.commit_circle_pose(&"hunter", 0, room.point(-48.0, 41.0)))
	assert_true(floor.commit_circle_pose(Hero, 0, room.point(56.0, 41.0)))
	assert_not_null(room.world.advance(1))
	var memory: Array = room.world.snapshot().actors[&"hunter"][7][3]
	assert_eq(memory, [Hero, room.point(56.0, 41.0).x, room.point(56.0, 41.0).y, 2])
	assert_true(room.exploration.place_route_solid(&"shut", room.point(0.0, 41.0), 18.0))
	assert_true(room.add(&"rival", -40.0))
	var before := floor.circle_center(&"hunter", 0)
	var rival_at := RealmSweep.Point.new(before.x, before.y - 8.0)
	assert_true(floor.commit_circle_pose(&"rival", 0, rival_at))
	var blocker := floor.certify_frozen_path(Realm, before, floor.circle_center(Hero, 0), 0.0, WorldExploration.BLOCKER)
	assert_false(blocker.contacts.is_empty())
	var sight := floor.certify_frozen_path(Realm, before, rival_at, 0.0, WorldExploration.BLOCKER)
	assert_true(sight.contacts.is_empty() and sight.unresolved.is_empty())
	assert_not_null(room.world.advance(2))
	var pursuing: Array = room.world.snapshot().actors[&"hunter"][7]
	assert_eq(pursuing[3], memory)
	assert_eq(pursuing[4], [])
	var after := floor.circle_center(&"hunter", 0)
	assert_true(after.x != before.x or after.y != before.y)
	rival_at = RealmSweep.Point.new(after.x, after.y - 8.0)
	assert_true(floor.commit_circle_pose(&"rival", 0, rival_at))
	assert_not_null(room.world.advance(3))
	var reengaged: Array = room.world.snapshot().actors[&"hunter"][7]
	assert_eq(reengaged[3], [])
	var strike: Array = reengaged[4]
	assert_eq(strike.size(), 5)
	if strike.size() == 5:
		assert_eq(strike[0], 5)
		assert_eq(strike[3], rival_at.x)
		assert_eq(strike[4], rival_at.y)


func test_hunter_retains_last_seen_pose_after_the_seat_leaves_its_realm() -> void:
	var room := Room.new()
	var floor := room.exploration.geometry()
	assert_true(room.enter())
	assert_true(room.add(&"hunter", -48.0, [], true, 2))
	assert_true(floor.commit_circle_pose(&"hunter", 0, room.point(-48.0, 41.0)))
	assert_true(floor.commit_circle_pose(Hero, 0, room.point(56.0, 41.0)))
	assert_not_null(room.world.advance(1))
	var memory: Array = room.world.snapshot().actors[&"hunter"][7][3]
	assert_eq(memory, [Hero, room.point(56.0, 41.0).x, room.point(56.0, 41.0).y, 3])
	var far_layout := WorldTopology.generate_optional(122, &"hall_of_echoes")
	var far_room := WorldExploration.create(far_layout, [Hero])
	assert_true(room.world.register_realm(far_room))
	assert_true(room.kernel.transfer_player(Hero, 1, floor, far_room.geometry(), far_layout.center(WorldTopology.ENTRY)))
	for tick: int in [2, 3]:
		assert_not_null(room.world.advance(tick))
		assert_eq(room.world.snapshot().actors[&"hunter"][7][3], memory)
	assert_not_null(room.world.advance(4))
	var last: Dictionary = room.world.snapshot().actors
	assert_eq(last[&"hunter"][7][3], [])
	assert_eq(last[&"hunter"][7][4], [])
	assert_eq(last[Hero][0], far_layout.realm)
	assert_eq(last[Hero][2], "20")
