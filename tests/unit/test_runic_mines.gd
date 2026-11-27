extends GutTest

const Arena := preload("res://tests/unit/test_starter_combat.gd").Arena
const FamiliarTest := preload("res://tests/unit/test_sketch_familiar.gd")
const HERO := &"hero"


func test_twin_mines_freeze_placement_rank_and_charge_independently_at_detonation() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"left", -16, 0, 200))
	assert_true(arena.add(&"late", 100, 0, 200))
	var rewards := FamiliarTest._earn(arena, 5, &"P03")
	var mines := RunicMines.create(HERO, rewards, arena.kernel, arena.geometry, 1, 2)
	var postings: Array = []
	for tick: int in range(1, 51):
		if tick == 2:
			assert_true(arena.move(HERO, 50, 30))
		if tick == 50:
			assert_true(arena.move(&"late", 16, 0))
		assert_true(mines.advance(tick))
		for hit: CombatKernel.Hit in arena.settle(tick):
			postings.append([tick, hit.target, hit.family, hit.origin.owner])
	assert_eq(postings, [[13, &"left", &"P03", HERO], [50, &"late", &"P03", HERO], [50, &"left", &"P03", HERO]])
	assert_eq(arena.hp(&"late").native_at_scale(0), 152)
	assert_eq(arena.hp(&"left").native_at_scale(0), 128)
	assert_true(mines.positions().is_empty())


func test_crossing_triggers_at_exact_subtick_and_blast_samples_every_other_trajectory_there() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"entrant", -30, 0, 100))
	assert_true(arena.add(&"tangent", 0, 70, 100))
	assert_true(arena.add(&"outside", 0, 75, 100))
	var mines := RunicMines.create(HERO, FamiliarTest._earn(arena, 1, &"P03"), arena.kernel, arena.geometry, 1, 2)
	for tick: int in range(1, 14):
		if tick == 13:
			assert_true(arena.geometry.stage_circle_motion(&"entrant", 0, RealmSweep.Point.new(30, 0)))
			assert_true(arena.geometry.stage_circle_motion(&"tangent", 0, RealmSweep.Point.new(0, -54)))
			assert_true(arena.geometry.stage_circle_motion(&"outside", 0, RealmSweep.Point.new(0, -49)))
		assert_true(mines.advance(tick))
		arena.settle(tick)
	var next := arena.kernel.next_due()
	assert_not_null(next)
	if next != null:
		assert_almost_eq(next.proof_snapshot().earliest, 0.25, 0.000001)
	var hits := arena.settle(14)
	assert_eq(hits.size(), 2)
	assert_eq(arena.hp(&"entrant").native_at_scale(0), 84)
	assert_eq(arena.hp(&"tangent").native_at_scale(0), 84)
	assert_eq(arena.hp(&"outside").native_at_scale(0), 100)


func test_compression_advances_arming_without_a_charge_wait() -> void:
	var arena := Arena.new(&"W03", &"H04", false, &"", &"", {&"H04": true})
	assert_true(arena.add(&"waiter", 1, 0, 100))
	var rewards := FamiliarTest._earn(arena, 1, &"P03")
	var mines := RunicMines.create(HERO, rewards, arena.kernel, arena.geometry, 1, 2, arena.combat)
	for tick: int in range(1, 8):
		if tick == 1:
			assert_eq(arena.combat.try_manual(tick, RealmSweep.Point.new(0, 0)), StarterCombat.Attempt.COMMITTED)
		assert_true(arena.combat.advance(tick))
		assert_true(mines.advance(tick))
		var hits := arena.settle(tick)
		assert_eq(hits.size(), 1 if tick == 7 else 0)
	assert_eq(arena.hp(&"waiter").native_at_scale(0), 84)


func test_mine_survives_when_an_earlier_root_kills_the_only_expected_entrant() -> void:
	var arena := Arena.new(&"W01")
	assert_true(arena.add(&"entrant", -30, 0, 10))
	assert_true(arena.add(&"bystander", 26, 0, 100))
	var mines := RunicMines.create(HERO, FamiliarTest._earn(arena, 1, &"P03"), arena.kernel, arena.geometry, 1, 2)
	for tick: int in range(1, 13):
		assert_true(mines.advance(tick))
		arena.settle(tick)
	assert_true(arena.geometry.stage_circle_motion(&"entrant", 0, RealmSweep.Point.new(30, 0)))
	assert_true(mines.advance(13))
	assert_true(arena.swing_from(HERO, &"entrant", 15, 13))
	arena.settle(14)
	assert_eq(mines.positions().size(), 1)
	assert_eq(arena.hp(&"bystander").native_at_scale(0), 100)
	assert_true(mines.advance(14))
	assert_true(arena.move(&"bystander", 5, 0))
	assert_true(mines.advance(15))
	arena.settle(15)
	assert_eq(arena.hp(&"bystander").native_at_scale(0), 84)
	assert_true(mines.positions().is_empty())


func test_mine_rechecks_displaced_entrant_and_samples_new_bystanders_at_trigger() -> void:
	for displaced: bool in [false, true]:
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"entrant", -30, 0, 100))
		assert_true(arena.add(&"bystander", 80, 0, 100))
		var mines := RunicMines.create(HERO, FamiliarTest._earn(arena, 1, &"P03"), arena.kernel, arena.geometry, 1, 2)
		for tick: int in range(1, 13):
			assert_true(mines.advance(tick))
			arena.settle(tick)
		assert_true(arena.geometry.stage_circle_motion(&"entrant", 0, RealmSweep.Point.new(30, 0)))
		assert_true(mines.advance(13))
		if displaced:
			assert_true(arena.move(&"entrant", -80, 0))
		assert_true(arena.move(&"bystander", 24, 0))
		arena.settle(14)
		assert_eq(arena.hp(&"bystander").native_at_scale(0), 100 if displaced else 84)
		assert_eq(mines.positions().size(), 1 if displaced else 0)
