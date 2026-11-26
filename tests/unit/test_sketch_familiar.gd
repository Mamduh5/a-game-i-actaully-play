extends GutTest

const Arena := preload("res://tests/unit/test_starter_combat.gd").Arena
const HERO := &"hero"
const FAMILY := &"P02"


static func _earn(arena: Arena, rank: int) -> RunRewardQueue:
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	slots[0] = FAMILY
	var prep := RunPreparation.select(arena.catalog, &"H01", &"W01", [&"", &""], slots, {})
	var rewards := RunRewardQueue.begin(prep, RunRandom.new(17), HERO)
	for tick: int in range(1, 100):
		if rewards.ranks().get(FAMILY, 0) == rank:
			break
		var offer := rewards.earn(tick)
		var options := rewards.read_offer(offer).options
		rewards.select(offer, FAMILY if options.has(FAMILY) else options.keys()[0])
	return rewards


func test_real_rank_picks_change_dart_count_damage_and_penetration() -> void:
	for rank: int in range(0, 6):
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"front", 30, 0, 100))
		assert_true(arena.add(&"rear", 50, 0, 100))
		var rewards := _earn(arena, rank)
		assert_eq(rewards.ranks().get(FAMILY, 0), rank)
		var familiar := SketchFamiliar.create(arena.kernel, arena.geometry, HERO, rewards, 1, 2)
		var hits: Array[CombatKernel.Hit] = []
		for tick: int in range(1, 10):
			assert_true(familiar.advance(tick, arena.candidates))
			hits.append_array(arena.settle(tick))
		var count := 0 if rank == 0 else (1 if rank < 3 else 2)
		var damage := 8 + 2 * int(rank >= 2) + 2 * int(rank >= 4)
		assert_eq(arena.hp(&"front").native_at_scale(0), 100 - damage * count)
		assert_eq(arena.hp(&"rear").native_at_scale(0), 76 if rank == 5 else 100)
		for hit: CombatKernel.Hit in hits:
			assert_eq(hit.origin.owner, HERO)
			assert_eq(hit.family, FAMILY)


func test_in_flight_quills_keep_their_heading_and_walls_stop_piercing() -> void:
	for blocked: bool in [false, true]:
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"aim", 50, 0, 100))
		assert_true(arena.add(&"interceptor", 30, 30, 100, 1, false))
		var familiar := SketchFamiliar.create(arena.kernel, arena.geometry, HERO, _earn(arena, 5), 1, 2)
		assert_true(familiar.advance(1, arena.candidates))
		arena.settle(1)
		assert_eq(familiar.position().x, -3.0)
		if blocked:
			assert_true(arena.wall(22, -20, 20))
		assert_true(arena.move(&"aim", 50, 50))
		assert_true(arena.move(&"interceptor", 30, 0))
		assert_true(arena.move(HERO, 0, 20))
		for tick: int in range(2, 10):
			assert_true(familiar.advance(tick, arena.candidates))
			arena.settle(tick)
		assert_gt(familiar.position().y, 0.0)
		assert_eq(arena.hp(&"aim").native_at_scale(0), 100)
		assert_eq(arena.hp(&"interceptor").native_at_scale(0), 100 if blocked else 76)
