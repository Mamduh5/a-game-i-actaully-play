extends GutTest

const Arena := preload("res://tests/unit/test_starter_combat.gd").Arena
const PowerRanks := preload("res://tests/unit/test_sketch_familiar.gd")


func test_rank_five_contacts_follow_endpoints_and_losing_one_interval_resets_only_that_enemy() -> void:
	var arena := Arena.new(&"W01")
	assert_false(&"P14" in RunPreparation.available(arena.catalog, CatalogEntry.Kind.POWER, {}))
	assert_true(arena.add(&"first", 20, 0, 500))
	assert_true(arena.add(&"last", 140, 0, 500))
	assert_true(arena.add(&"visitor", 80, 7, 500, 1, false))
	var tether := ArcaneTether.create(&"hero", PowerRanks._earn(arena, 5, &"P14"), arena.kernel, arena.geometry, 1, 2)
	var visitor: Array[int] = []
	var first: Array[int] = []
	for tick: int in range(1, 93):
		if tick == 46:
			assert_true(arena.move(&"last", 140, 60))
		if tick == 61:
			assert_true(arena.move(&"visitor", 80, 29))
		assert_true(tether.advance(tick, arena.candidates))
		for hit: CombatKernel.Hit in arena.settle(tick):
			if hit.target == &"visitor":
				visitor.append(hit.components[0].hp_removed.native_at_scale(0))
			if hit.target == &"first":
				first.append(hit.components[0].hp_removed.native_at_scale(0))
	assert_eq(visitor, [16, 20, 16, 20, 24])
	assert_eq(first, [16, 20, 24, 28, 32, 32])
	assert_true(tether.endpoints().is_empty())


func test_stationary_anchor_and_obstructed_pulse_keep_original_cadence() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"first", 45, 0, 200))
	var tether := ArcaneTether.create(&"hero", PowerRanks._earn(arena, 1, &"P14"), arena.kernel, arena.geometry, 1, 2)
	var ticks: Array[int] = []
	for tick: int in range(1, 48):
		if tick == 10:
			assert_true(arena.move(&"first", 55, 0))
		if tick == 31:
			assert_true(arena.wall(30, -10, 10))
		if tick == 46:
			assert_true(arena.geometry.remove_mutable(&"wall", 0))
		assert_true(tether.advance(tick, arena.candidates))
		for hit: CombatKernel.Hit in arena.settle(tick):
			ticks.append(tick)
			assert_eq(hit.target, &"first")
			assert_eq(hit.components[0].hp_removed.native_at_scale(0), 8)
		assert_eq(tether.endpoints()[1].x, 13.0)
	assert_eq(ticks, [16, 46])
