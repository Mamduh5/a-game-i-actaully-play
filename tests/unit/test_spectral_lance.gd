extends GutTest

const Arena := preload("res://tests/unit/test_starter_combat.gd").Arena
const PowerRanks := preload("res://tests/unit/test_sketch_familiar.gd")
const HERO := &"hero"


func test_lance_rank_changes_real_swept_width_and_only_later_rank_five_hits_ramp() -> void:
	for rank: int in range(1, 6):
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"front", 30, 0, 200))
		assert_true(arena.add(&"edge", 55, 8, 200, 1, false))
		assert_true(arena.add(&"rear", 80, 0, 200))
		assert_true(arena.add(&"covered", 130, 0, 200))
		assert_true(arena.wall(100, -20, 20))
		var lance := SpectralLance.create(HERO, PowerRanks._earn(arena, rank, &"P04"), arena.kernel, arena.geometry, 1, 2)
		for tick: int in range(1, 12):
			assert_true(lance.advance(tick, arena.candidates))
			for hit: CombatKernel.Hit in arena.settle(tick):
				assert_eq(hit.family, &"P04")
				assert_eq(hit.components[0].kind, CombatAction.Damage.MAGICAL)
		var base := 12 + 4 * int(rank >= 2) + 4 * int(rank >= 4)
		assert_eq(arena.hp(&"front").native_at_scale(0), 200 - base)
		assert_eq(arena.hp(&"edge").native_at_scale(0), 200 - (25 if rank == 5 else base) if rank >= 3 else 200)
		assert_eq(arena.hp(&"rear").native_at_scale(0), 170 if rank == 5 else 200 - base)
		assert_eq(arena.hp(&"covered").native_at_scale(0), 200)


func test_ascending_pierce_caps_and_each_spear_starts_fresh() -> void:
	var arena := Arena.new(&"W01")
	for i: int in 6:
		assert_true(arena.add(StringName("target%d" % i), 25 + i * 18, 0, 200))
	var lance := SpectralLance.create(HERO, PowerRanks._earn(arena, 5, &"P04"), arena.kernel, arena.geometry, 1, 2)
	for tick: int in range(1, 91):
		assert_true(lance.advance(tick, arena.candidates))
		arena.settle(tick)
	for i: int in 6:
		assert_eq(arena.hp(StringName("target%d" % i)).native_at_scale(0), 200 - 2 * (20 + 5 * mini(i, 4)))


func test_prepared_offense_rounds_launch_period_up_and_preserves_spear_speed() -> void:
	for upgraded: bool in [false, true]:
		var upgrades: Dictionary[StringName, int] = {&"manual_cooldown_recovery": 2500}
		if upgraded:
			upgrades[&"base_damage"] = 2500
			upgrades[&"automatic_attack_frequency"] = 2500
		var arena := Arena.new(&"W01")
		assert_true(arena.add(&"foe", 30, 0, 200))
		var rewards := PowerRanks._earn(arena, 1, &"P04", upgrades)
		var lance := SpectralLance.create(HERO, rewards, arena.kernel, arena.geometry, 1, 2)
		var activations: Array[int] = []
		var contacts: Array[int] = []
		for tick: int in range(1, 80):
			assert_true(lance.advance(tick, arena.candidates))
			if tick == 1:
				assert_eq(lance.position().x, 15.0)
			for hit: CombatKernel.Hit in arena.settle(tick):
				activations.append(hit.origin.activation)
				contacts.append(tick)
				assert_eq(hit.components[0].hp_removed.native_at_scale(0), 15 if upgraded else 12)
		assert_eq(activations, [1, 59 if upgraded else 73])
		assert_eq(contacts, [3, 61 if upgraded else 75])
