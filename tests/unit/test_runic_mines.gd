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


func test_prepared_offense_changes_placement_period_and_base_with_same_arming_and_pressure() -> void:
	for upgraded: bool in [false, true]:
		var upgrades: Dictionary[StringName, int] = {&"manual_cooldown_recovery": 2500}
		if upgraded:
			upgrades[&"base_damage"] = 2500
			upgrades[&"automatic_attack_frequency"] = 2500
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"foe", 100, 0, 200))
		var rewards := FamiliarTest._earn(arena, 5, &"P03", upgrades)
		var mines := RunicMines.create(HERO, rewards, arena.kernel, arena.geometry, 1, 2)
		var activations: Array[int] = []
		var contacts: Array[int] = []
		var damage: Array[int] = []
		for tick: int in range(1, 108):
			if tick == 14:
				assert_true(arena.move(&"foe", -16, 0))
			assert_true(mines.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				activations.append(hit.origin.activation)
				contacts.append(tick)
				damage.append(hit.components[0].hp_removed.native_at_scale(0))
		assert_eq(activations, [1, 73 if upgraded else 91])
		assert_eq(contacts, [14, 85 if upgraded else 103])
		assert_eq(damage, [31, 30] if upgraded else [25, 24])


func test_prepared_twin_mines_fill_the_slot_freed_on_the_previous_tick() -> void:
	for detonate: bool in [false, true]:
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"foe", 190, 30, 200))
		var rewards := FamiliarTest._earn(arena, 5, &"P03", {&"automatic_attack_frequency": 2500})
		var mines := RunicMines.create(HERO, rewards, arena.kernel, arena.geometry, 1, 2)
		var damage_ticks: Array[int] = []
		for tick: int in range(1, 225):
			if tick in [72, 144]:
				assert_true(arena.move(HERO, 60 if tick == 72 else 110, 0))
			if tick == 216:
				assert_true(arena.move(HERO, 155, 0))
			if detonate and tick in [144, 145]:
				assert_true(arena.move(&"foe", -16 if tick == 144 else 190, 0 if tick == 144 else 30))
			assert_true(mines.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				damage_ticks.append(tick)
				assert_eq(hit.origin.activation, 1)
				assert_eq(hit.components[0].hp_removed.native_at_scale(0), 48)
			var positions := mines.positions()
			assert_lte(positions.size(), 4)
			var x_coordinates := positions.map(func(position: RealmSweep.Point) -> float: return position.x)
			match tick:
				73: assert_eq(x_coordinates, [-16.0, 16.0, 44.0, 76.0])
				144: assert_eq(x_coordinates, [16.0, 44.0, 76.0] if detonate else [-16.0, 16.0, 44.0, 76.0])
				145: assert_eq(x_coordinates, [16.0, 44.0, 76.0, 94.0] if detonate else [-16.0, 16.0, 44.0, 76.0])
				152: assert_eq(x_coordinates, [44.0, 76.0, 94.0] if detonate else [44.0, 76.0])
				217: assert_eq(x_coordinates, [44.0, 76.0, 94.0, 139.0] if detonate else [44.0, 76.0, 139.0, 171.0])
				224: assert_eq(x_coordinates, [94.0, 139.0] if detonate else [139.0, 171.0])
		assert_eq(damage_ticks, [144] if detonate else [])


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


func test_committed_mine_after_owner_death_admits_exact_expiry_and_rejects_later_crossing() -> void:
	for exact: bool in [true, false]:
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"entrant", 60, 0, 100))
		assert_true(arena.add(&"survivor", 100, 30, 100, 4))
		var mines := RunicMines.create(HERO, FamiliarTest._earn(arena, 1, &"P03"), arena.kernel, arena.geometry, 1, 2)
		var hit_ticks: Array[int] = []
		for tick: int in range(1, 154):
			if tick == 16:
				assert_true(arena.swing_from(&"entrant", HERO, 250, tick))
			if tick == 151:
				if exact:
					assert_true(arena.move(&"entrant", 15, 0))
				else:
					assert_true(arena.geometry.stage_circle_motion(&"entrant", 0, RealmSweep.Point.new(0, 0)))
			assert_true(mines.advance(tick))
			for hit: CombatKernel.Hit in arena.settle(tick):
				if hit.family == &"P03":
					assert_eq(hit.origin.owner, HERO)
					hit_ticks.append(tick)
		assert_eq(hit_ticks, [151] if exact else [])
		assert_eq(arena.hp(&"entrant").native_at_scale(0), 84 if exact else 100)
		assert_true(mines.positions().is_empty())


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
