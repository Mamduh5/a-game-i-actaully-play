extends GutTest

const Kind := CatalogEntry.Kind
const Eligibility := CatalogEntry.Eligibility
const Selection := RunRewardQueue.Selection


func test_preparation_enforces_fixed_slot_counts_distinct_runes_and_profile_access() -> void:
	var catalog := _catalog()
	assert_eq(RunPreparation.available(catalog, Kind.POWER, {}).size(), 12)
	var blanks := _slots()
	for pair: Array in [[&"", &""], [&"", &"R01"], [&"R01", &"R02"]]:
		var typed: Array[StringName] = []
		typed.assign(pair)
		assert_not_null(RunPreparation.select(catalog, &"H01", &"W01", typed, blanks, {}))
	assert_null(RunPreparation.select(catalog, &"H01", &"W01", [&"R01"], blanks, {}))
	assert_null(RunPreparation.select(catalog, &"H01", &"W01", [&"R01", &"R01"], blanks, {}))
	assert_null(RunPreparation.select(catalog, &"H01", &"W01", [&"R01", &"", &"R02"], blanks, {}))
	assert_null(RunPreparation.select(catalog, &"H05", &"W01", [&"", &""], blanks, {&"H05": true}))
	assert_not_null(RunPreparation.select(catalog, &"H05", &"W01", [&"", &""], blanks,
		{&"H05": true, &"W05": true}))
	blanks[0] = &"P13"
	assert_null(RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], blanks, {}))
	var available: Dictionary[StringName, bool] = {&"P13": true}
	var prepared := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], blanks, available)
	assert_not_null(prepared)
	if prepared == null:
		return
	blanks[0] = &"P12"
	available.clear()
	assert_eq(prepared.candidates()[0], &"P13")
	assert_true(&"P13" in prepared.eligible_powers())
	var copy := prepared.candidates()
	copy[0] = &"P01"
	assert_eq(prepared.candidates()[0], &"P13")
	blanks[1] = &"P12"
	assert_null(RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], blanks, {}))


func test_full_prepared_pool_gets_only_its_choices_with_seeded_opportunities() -> void:
	var slots := _slots(10)
	var prepared := _prepare(slots)
	var first := RunRewardQueue.begin(prepared, RunRandom.new(928), &"host")
	var repeated := RunRewardQueue.begin(prepared, RunRandom.new(928), &"host")
	var seen: Dictionary[StringName, bool] = {}
	for tick: int in range(1, 5):
		var reward := first.earn(tick)
		assert_eq(reward, repeated.earn(tick))
		var offer := first.read_offer(reward)
		assert_eq(offer.earned_at, tick)
		assert_eq(offer.options.size(), 3)
		assert_eq(offer.options.keys(), repeated.read_offer(reward).options.keys())
		for id: StringName in offer.options:
			assert_true(id in slots)
			assert_eq(offer.options[id], 1)
			seen[id] = true
	assert_eq(seen.size(), 10)
	assert_true(first.ranks().is_empty(), "Preparing or seeing a power does not acquire it")


func test_blank_slots_draw_only_from_personal_eligible_powers() -> void:
	var locked := _prepare(_slots())
	var unlocked := _prepare(_slots(), {&"P13": true})
	var random := RunRandom.new(77)
	var host := RunRewardQueue.begin(locked, random, &"host")
	var guest := RunRewardQueue.begin(unlocked, random, &"guest")
	var lucky := false
	for tick: int in range(1, 13):
		var host_offer := host.read_offer(host.earn(tick))
		var guest_offer := guest.read_offer(guest.earn(tick))
		assert_false(host_offer.options.has(&"P13"))
		assert_false(guest_offer.options.has(&"P14"))
		lucky = lucky or guest_offer.options.has(&"P13")
	assert_true(lucky)


func test_earned_options_freeze_and_a_selected_reward_cannot_be_spent_twice() -> void:
	var slots := _slots(10)
	var queue := RunRewardQueue.begin(_prepare(slots), RunRandom.new(42), &"host")
	var old := queue.earn(3)
	var old_offer := queue.read_offer(old)
	var id: StringName = old_offer.options.keys()[0]
	var newer := 0
	for tick: int in range(4, 12):
		var candidate := queue.earn(tick)
		if queue.read_offer(candidate).options.has(id):
			newer = candidate
			break
	assert_gt(newer, old)
	assert_eq(queue.select(newer, id), Selection.APPLIED)
	assert_eq(queue.select(newer, id), Selection.UNKNOWN_REWARD)
	assert_eq(queue.select(old, id), Selection.STALE_OPTION)
	assert_eq(queue.select(old, &"P18"), Selection.INVALID_OPTION)
	assert_eq(queue.read_offer(old).options, old_offer.options)
	old_offer.options.clear()
	assert_eq(queue.read_offer(old).options[id], 1)
	var alternate: StringName = queue.read_offer(old).options.keys()[1]
	assert_eq(queue.select(old, alternate), Selection.APPLIED)
	assert_eq(queue.ranks(), {id: 1, alternate: 1})


func test_rank_progression_uses_ten_slots_and_stops_ordinary_options_at_the_individual_caps() -> void:
	var queue := RunRewardQueue.begin(_prepare(_slots(10)), RunRandom.new(207), &"host")
	for tick: int in range(1, 51):
		var reward := queue.earn(tick)
		var offer := queue.read_offer(reward)
		assert_gt(offer.options.size(), 0)
		if offer.options.is_empty():
			return
		var id: StringName = offer.options.keys()[0]
		assert_eq(offer.options[id], int(queue.ranks().get(id, 0)) + 1)
		assert_eq(queue.select(reward, id), Selection.APPLIED)
	assert_eq(queue.ranks().size(), 10)
	for rank: int in queue.ranks().values():
		assert_eq(rank, 5)
	assert_true(queue.read_offer(queue.earn(51)).options.is_empty())


func test_party_xp_carries_shares_levels_and_freezes_separate_seat_choices() -> void:
	var prepared := _prepare(_slots(10))
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = &"fixture"
	setup.authority_id = &"host"
	setup.epoch = 1
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = prepared.catalog_revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"host": &"core", &"guest": &"optional"}
	assert_null(PartyProgression.begin(setup, {&"host": prepared}, RunRandom.new(3)))
	var party := PartyProgression.begin(setup, {&"host": prepared, &"guest": prepared}, RunRandom.new(3))
	assert_eq(party.grant_xp(&"first", Quantity.from_count(99), 1), PartyProgression.Award.APPLIED)
	assert_eq(party.level(), 1)
	assert_null(party.offer(&"guest", 1))
	assert_eq(party.grant_xp(&"second", Quantity.from_count(116), 2), PartyProgression.Award.APPLIED)
	assert_eq(party.level(), 3)
	assert_eq(party.carried_xp().native_at_scale(0), 3)
	assert_eq(party.grant_xp(&"first", Quantity.from_count(99), 3), PartyProgression.Award.DUPLICATE)
	assert_eq(party.grant_xp(&"first", Quantity.from_count(100), 3), PartyProgression.Award.CONFLICT)
	assert_eq(party.level(), 3)
	assert_eq(party.carried_xp().native_at_scale(0), 3)
	assert_null(party.offer(&"outsider", 1))
	assert_null(party.offer(&"host", 3))
	assert_eq(party.offer(&"guest", 2).earned_at, 2)
	var host := party.offer(&"host", 1)
	var guest := party.offer(&"guest", 1)
	assert_ne(host.options.keys(), guest.options.keys())
	assert_eq(party.select(&"host", 1, host.options.keys()[0]), Selection.APPLIED)
	assert_null(party.offer(&"host", 1))
	assert_eq(party.offer(&"guest", 1).options, guest.options)


func test_xp_requirements_transition_by_level_with_whole_xp_ceiling() -> void:
	for witness: Array in [[1, 100], [2, 112], [19, 3988], [20, 4432], [21, 5319], [22, 6383]]:
		assert_eq(PartyProgression.xp_to_next(witness[0]).native_at_scale(0), witness[1])
	assert_null(PartyProgression.xp_to_next(0))


static func _slots(names: int = 0) -> Array[StringName]:
	var result: Array[StringName] = []
	for index: int in RunPreparation.CANDIDATE_SLOTS:
		result.append(StringName("P%02d" % (index + 1)) if index < names else &"")
	return result


static func _prepare(slots: Array[StringName], unlocked: Dictionary[StringName, bool] = {}) -> RunPreparation:
	return RunPreparation.select(_catalog(), &"H01", &"W01", [&"R01", &"R02"], slots, unlocked)


static func _catalog() -> DefinitionCatalog:
	var locked_hero := _entry(&"H05", Kind.HERO, Eligibility.OWNERSHIP)
	var required_weapon := CatalogReference.new()
	required_weapon.target_id = &"W05"
	locked_hero.prerequisites.append(required_weapon)
	var entries: Array[CatalogEntry] = [_entry(&"H01", Kind.HERO), locked_hero,
		_entry(&"W01", Kind.WEAPON), _entry(&"W05", Kind.WEAPON, Eligibility.OWNERSHIP),
		_entry(&"R01", Kind.RUNE), _entry(&"R02", Kind.RUNE)]
	for i: int in range(1, 19):
		var power := _entry(StringName("P%02d" % i), Kind.POWER,
			Eligibility.STARTER if i <= 12 else Eligibility.OWNERSHIP)
		power.ranks = [&"rank1", &"rank2", &"rank3", &"rank4", &"rank5"]
		entries.append(power)
	return DefinitionCatalog.compile(&"fixture_rewards", entries)


static func _entry(id: StringName, kind: CatalogEntry.Kind,
		eligibility: CatalogEntry.Eligibility = Eligibility.STARTER) -> CatalogEntry:
	var entry := CatalogEntry.new()
	entry.id = id
	entry.kind = kind
	entry.eligibility = eligibility
	entry.lifetime = CatalogEntry.Lifetime.PREPARATION
	entry.targeting = CatalogEntry.Targeting.NONE
	entry.source_family = id
	return entry
