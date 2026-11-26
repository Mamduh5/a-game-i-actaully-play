extends GutTest

const Kind := CatalogEntry.Kind
const Eligibility := CatalogEntry.Eligibility
const Selection := RunRewardQueue.Selection


func test_authored_starter_roster_and_pinned_card_order() -> void:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	assert_not_null(bundle)
	if bundle == null:
		return
	var catalog := bundle.compile()
	assert_true(catalog.is_valid())
	assert_eq(RunPreparation.available(catalog, Kind.HERO, {}), [&"H01", &"H02", &"H03"])
	assert_eq(RunPreparation.available(catalog, Kind.WEAPON, {}), [&"W01", &"W02", &"W03"])
	assert_eq(RunPreparation.available(catalog, Kind.RUNE, {}), [&"R01", &"R02", &"R03"])
	var powers := RunPreparation.available(catalog, Kind.POWER, {})
	assert_eq(powers.size(), 12)
	assert_eq(powers[0], &"P01")
	assert_eq(powers[-1], &"P12")
	assert_eq(catalog.lookup(&"P07").ranks[4], &"recovery_surge")
	assert_eq(bundle.display_names[&"H02"], "The Acrobat")
	var reordered := bundle.entries.duplicate()
	reordered.reverse()
	var reversed := DefinitionCatalog.compile(bundle.revision, reordered)
	var slots := _slots()
	var normal := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots, {})
	var reverse := RunPreparation.select(reversed, &"H01", &"W01", [&"", &""], slots, {})
	var first := RunRewardQueue.begin(normal, RunRandom.new(10), &"guest")
	var second := RunRewardQueue.begin(reverse, RunRandom.new(10), &"guest")
	assert_eq(first.read_offer(first.earn(1)).options.keys(), second.read_offer(second.earn(1)).options.keys())


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


func test_preparation_checkpoint_filters_empty_unlock_keys_and_reopens_valid_access() -> void:
	var catalog := _catalog()
	var slots := _slots()
	slots[0] = &"P13"
	var prepared := RunPreparation.select(catalog, &"H01", &"W01", [&"", &""], slots,
		{&"": true, &"P13": true, &"P14": false})
	assert_not_null(prepared)
	if prepared == null:
		return
	var checkpoint := prepared.checkpoint()
	assert_eq(checkpoint[4], [&"P13"])
	var reopened := RunPreparation.reopen(catalog, checkpoint)
	assert_not_null(reopened)
	if reopened != null:
		assert_eq(reopened.checkpoint(), checkpoint)
		assert_true(&"P13" in reopened.eligible_powers())
		assert_false(&"P14" in reopened.eligible_powers())
	var malformed := checkpoint.duplicate(true)
	malformed[4].append(&"")
	assert_null(RunPreparation.reopen(catalog, malformed))


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


func test_restore_refuses_empty_frozen_power_offers_and_allows_retry() -> void:
	var prepared := _prepare(_slots(10))
	var original := RunRewardQueue.begin(prepared, RunRandom.new(44), &"host")
	var ordinal := original.earn(2)
	var checkpoint := original.checkpoint()
	for legacy: bool in [false, true]:
		var valid := checkpoint.duplicate(true)
		if legacy:
			valid["pending"][0].pop_back()
		var malformed := valid.duplicate(true)
		malformed["pending"][0][2].clear()
		var restored := RunRewardQueue.begin(prepared, RunRandom.new(44), &"host")
		assert_false(restored.restore(malformed, ordinal, 2), "An earned power offer requires a card")
		assert_null(restored.read_offer(ordinal))
		assert_eq(restored.compensate_if_stale(ordinal), Selection.UNKNOWN_REWARD)
		assert_eq(restored.trade_shards().native_at_scale(0), 0)
		assert_true(restored.restore(valid, ordinal, 2), "Invalid input must not consume the restore attempt")
		assert_eq(restored.checkpoint(), checkpoint)


func test_rank_caps_lead_to_diminishing_overflow_and_then_personal_utility() -> void:
	var preparation := _prepare(_slots(10))
	var queue := RunRewardQueue.begin(preparation, RunRandom.new(207), &"host")
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
	for tick: int in range(51, 60):
		var earned := queue.earn(tick)
		var offer := queue.read_offer(earned)
		assert_eq(offer.kind, RunRewardQueue.Kind.OVERFLOW)
		var stat: StringName = offer.options.keys()[0]
		assert_eq(queue.select(earned, stat), Selection.APPLIED)
		assert_eq(queue.overflow_bonus_basis_points(stat), [300, 500, 600][offer.options[stat] - 1])
	var utility := queue.read_offer(queue.earn(60))
	assert_eq(utility.kind, RunRewardQueue.Kind.UTILITY)
	assert_eq(queue.select(utility.ordinal, RunRewardQueue.SHARD_OPTION), Selection.APPLIED)
	assert_eq(queue.trade_shards().native_at_scale(0), 1)
	assert_eq(queue.select(utility.ordinal, RunRewardQueue.SHARD_OPTION), Selection.UNKNOWN_REWARD)
	assert_eq(queue.ranks().size(), 10)
	var restored := RunRewardQueue.begin(preparation, RunRandom.new(207), &"host")
	assert_true(restored.restore(queue.checkpoint(), 60, 60))
	assert_eq(restored.trade_shards().native_at_scale(0), 1)
	for stat: StringName in RunRewardQueue.OVERFLOW_STATS:
		assert_eq(restored.overflow_bonus_basis_points(stat), 600)


func test_all_stale_options_convert_to_one_shard_without_reroll() -> void:
	var queue := RunRewardQueue.begin(_prepare(_slots(10)), RunRandom.new(340), &"host")
	var ordinal := queue.earn(1)
	var old := queue.read_offer(ordinal)
	var outstanding := old.options.keys()
	assert_eq(queue.compensate_if_stale(ordinal), Selection.STALE_OPTION)
	assert_eq(queue.trade_shards().native_at_scale(0), 0)
	for tick: int in range(2, 16):
		var current := queue.read_offer(queue.earn(tick))
		for id: StringName in current.options:
			if id in outstanding:
				assert_eq(queue.select(current.ordinal, id), Selection.APPLIED)
				outstanding.erase(id)
				break
		if outstanding.is_empty():
			break
	assert_true(outstanding.is_empty())
	assert_eq(queue.read_offer(ordinal).options, old.options)
	assert_eq(queue.select(ordinal, old.options.keys()[0]), Selection.COMPENSATED)
	assert_eq(queue.trade_shards().native_at_scale(0), 1)
	assert_null(queue.read_offer(ordinal))
	assert_eq(queue.compensate_if_stale(ordinal), Selection.UNKNOWN_REWARD)
	assert_eq(queue.trade_shards().native_at_scale(0), 1)


func test_party_xp_carries_shares_levels_and_freezes_separate_seat_choices() -> void:
	var prepared := _prepare(_slots(10))
	var setup := _setup()
	assert_null(PartyProgression.begin(setup, {&"host": prepared}))
	var party := PartyProgression.begin(setup, {&"host": prepared, &"guest": prepared})
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


func test_native_frontier_reopens_preparation_frozen_offers_selection_and_seeded_draws() -> void:
	if not OS.has_feature("windows"):
		return
	var scratch := DirAccess.create_temp("agip-run-progression")
	var store := ProfileStore.new()
	assert_eq(store.open("progression", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var setup := _setup()
	var party := PartyProgression.begin(setup, {&"host": _prepare(_slots(10)),
		&"guest": _prepare(_slots(), {&"P13": true})})
	var prepared := ProfileMutation.new()
	prepared.id = "fixture:prepare"
	prepared.rules = String(setup.rules_revision)
	prepared.catalog = String(setup.catalog_revision)
	prepared.frontier = party.frontier(0)
	assert_eq(store.commit(prepared).status, ProfileStore.CommitResult.COMMITTED)
	var fresh := PartyProgression.reopen(setup, _catalog(), store.frontier(String(setup.run_id)))
	assert_not_null(fresh)
	assert_eq(fresh.level(), 1)
	assert_null(fresh.offer(&"host", 1))
	assert_eq(party.grant_xp(&"root", Quantity.from_count(215), 1), PartyProgression.Award.APPLIED)
	var personal := party.offer(&"guest", 1)
	assert_eq(party.select(&"host", 1, party.offer(&"host", 1).options.keys()[0]), Selection.APPLIED)
	var earned := ProfileMutation.new()
	earned.id = "fixture:earn-and-select"
	earned.rules = prepared.rules
	earned.catalog = prepared.catalog
	earned.frontier = party.frontier(2)
	assert_eq(store.commit(earned).status, ProfileStore.CommitResult.COMMITTED)
	assert_true(store.close())
	assert_eq(store.open("progression", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var saved := store.frontier(String(setup.run_id))
	var resumed := PartyProgression.reopen(setup, _catalog(), saved)
	assert_not_null(resumed)
	if resumed == null:
		assert_true(store.close())
		return
	assert_eq(resumed.frontier(2).image, earned.frontier.image)
	assert_eq(resumed.level(), 3)
	assert_eq(resumed.carried_xp().native_at_scale(0), 3)
	assert_eq(resumed.offer(&"guest", 1).options.keys(), personal.options.keys())
	assert_null(resumed.offer(&"host", 1))
	assert_eq(resumed.grant_xp(&"root", Quantity.from_count(215), 3), PartyProgression.Award.DUPLICATE)
	assert_eq(store.commit(earned).status, ProfileStore.CommitResult.DUPLICATE)
	assert_eq(resumed.grant_xp(&"fresh", Quantity.from_count(145), 3), PartyProgression.Award.APPLIED)
	assert_eq(party.grant_xp(&"fresh", Quantity.from_count(145), 3), PartyProgression.Award.APPLIED)
	assert_eq(resumed.frontier(3).image, party.frontier(3).image)
	var legacy: Dictionary = bytes_to_var(saved["image"])
	for queue: Dictionary in legacy["queues"].values():
		queue.erase("overflow")
		queue.erase("shards")
		for row: Array in queue["pending"]:
			row.pop_back()
	var previous_shape := saved.duplicate()
	previous_shape["image"] = var_to_bytes(legacy)
	assert_eq(PartyProgression.reopen(setup, _catalog(), previous_shape).frontier(2).image, earned.frontier.image)
	var malformed: Dictionary = bytes_to_var(saved["image"])
	malformed["level"] = 5
	saved["image"] = var_to_bytes(malformed)
	assert_null(PartyProgression.reopen(setup, _catalog(), saved))
	assert_true(store.close())


func test_xp_requirements_transition_by_level_with_whole_xp_ceiling() -> void:
	for witness: Array in [[1, 100], [2, 112], [19, 3988], [20, 4432], [21, 5319], [22, 6383]]:
		assert_eq(PartyProgression.xp_to_next(witness[0]).native_at_scale(0), witness[1])
	assert_null(PartyProgression.xp_to_next(0))


func test_rank_five_evolution_cards_rotate_and_reciprocal_forms_work_in_both_orders() -> void:
	for first: StringName in [&"E07A", &"E12A"]:
		var preparation := _recipe_preparation([&"", &""])
		var queue := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		_rank_recipe_bases(queue)
		var first_bonus := queue.read_offer(queue.earn(11))
		var second_bonus := queue.read_offer(queue.earn(12))
		assert_eq(first_bonus.fusion, &"")
		assert_eq(second_bonus.fusion, &"")
		assert_true(first_bonus.evolution in [&"E07A", &"E12A"])
		assert_true(second_bonus.evolution in [&"E07A", &"E12A"])
		assert_ne(first_bonus.evolution, second_bonus.evolution)
		assert_eq(queue.active_form(&"P07"), &"P07")
		assert_eq(queue.active_form(&"P12"), &"P12")
		var resumed := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		assert_true(resumed.restore(queue.checkpoint(), 12, 12))
		var rotated := resumed.read_offer(resumed.earn(13))
		assert_eq(rotated.evolution, first_bonus.evolution)
		assert_eq(resumed.read_offer(11).options, first_bonus.options)
		assert_eq(resumed.read_offer(12).options, second_bonus.options)
		var chosen := first_bonus if first_bonus.evolution == first else second_bonus
		var remaining := second_bonus if chosen.ordinal == first_bonus.ordinal else first_bonus
		assert_eq(resumed.select(chosen.ordinal, chosen.evolution), Selection.APPLIED)
		assert_eq(resumed.select(chosen.ordinal, chosen.options.keys()[0]), Selection.UNKNOWN_REWARD)
		assert_eq(resumed.select(remaining.ordinal, remaining.evolution), Selection.APPLIED)
		assert_eq(resumed.active_form(&"P07"), &"E07A")
		assert_eq(resumed.active_form(&"P12"), &"E12A")
		assert_eq(resumed.ranks(), {&"P07": 5, &"P12": 5})
		var restored := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		assert_true(restored.restore(resumed.checkpoint(), 13, 13))
		assert_eq(restored.active_form(&"P07"), &"E07A")
		assert_eq(restored.active_form(&"P12"), &"E12A")
		var fusion_offer := restored.read_offer(restored.earn(14))
		assert_eq(fusion_offer.evolution, &"")
		assert_eq(fusion_offer.fusion, &"F06")
		var other_offer := restored.read_offer(restored.earn(15))
		assert_eq(restored.select(fusion_offer.ordinal, &"F06"), Selection.APPLIED)
		assert_eq(restored.active_form(&"P07"), &"F06")
		assert_eq(restored.active_form(&"P12"), &"F06")
		assert_eq(restored.ranks(), {&"P07": 5, &"P12": 5})
		assert_eq(restored.select(other_offer.ordinal, &"F06"), Selection.STALE_OPTION)
		var fused := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		assert_true(fused.restore(restored.checkpoint(), 15, 15))
		assert_eq(fused.active_form(&"P07"), &"F06")
		assert_eq(fused.active_form(&"P12"), &"F06")
		assert_eq(fused.read_offer(fused.earn(16)).fusion, &"")


func test_selected_alternative_invalidates_its_sibling_and_lost_catalyst_without_reroll() -> void:
	var preparation := _recipe_preparation([&"", &"R02"])
	var queue := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
	_rank_recipe_bases(queue)
	var bonuses: Dictionary[StringName, int] = {}
	for tick: int in range(11, 14):
		var frozen := queue.read_offer(queue.earn(tick))
		bonuses[frozen.evolution] = frozen.ordinal
	assert_eq(bonuses.size(), 3)
	assert_true(bonuses.has(&"E07A"))
	assert_true(bonuses.has(&"E07B"))
	assert_true(bonuses.has(&"E12A"))
	var earlier := queue.read_offer(bonuses[&"E12A"])
	assert_eq(queue.select(bonuses[&"E07B"], &"E07B"), Selection.APPLIED)
	assert_eq(queue.select(bonuses[&"E07A"], &"E07A"), Selection.STALE_OPTION)
	assert_eq(queue.select(earlier.ordinal, &"E12A"), Selection.STALE_OPTION)
	assert_eq(queue.read_offer(earlier.ordinal).options, earlier.options)
	assert_eq(queue.active_form(&"P07"), &"E07B")
	assert_eq(queue.active_form(&"P12"), &"P12")
	assert_eq(queue.read_offer(queue.earn(14)).evolution, &"")
	var incompatible := RunRewardQueue.begin(_recipe_preparation([&"", &""]), RunRandom.new(6), &"host")
	assert_false(incompatible.restore(queue.checkpoint(), 14, 14))


func test_evolution_choices_and_active_slot_survive_native_progression_reopen() -> void:
	if not OS.has_feature("windows"):
		return
	var prep := _recipe_preparation([&"", &""])
	var setup := _setup()
	setup.role = RunSetup.Role.SOLO
	setup.initial_realms = {&"host": &"core"}
	setup.catalog_revision = prep.catalog_revision
	var party := PartyProgression.begin(setup, {&"host": prep})
	for ordinal: int in range(1, 13):
		var need := PartyProgression.xp_to_next(party.level())
		assert_eq(party.grant_xp(StringName("fixture/%d" % ordinal), need, ordinal), PartyProgression.Award.APPLIED)
		if ordinal <= 10:
			assert_eq(party.select(&"host", ordinal, &"P07" if ordinal <= 5 else &"P12"), Selection.APPLIED)
	var chosen := party.offer(&"host", 12)
	var pending := party.offer(&"host", 11)
	assert_eq(party.select(&"host", chosen.ordinal, chosen.evolution), Selection.APPLIED)
	var choice := prep.catalog.lookup(chosen.evolution)
	var mutation := ProfileMutation.new()
	mutation.id = "wp20/evolution"
	mutation.rules = String(setup.rules_revision)
	mutation.catalog = String(setup.catalog_revision)
	mutation.frontier = party.frontier(12)
	var scratch := DirAccess.create_temp("agip-evolution")
	var store := ProfileStore.new()
	assert_eq(store.open("hero", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	assert_eq(store.commit(mutation).status, ProfileStore.CommitResult.COMMITTED)
	assert_true(store.close())
	assert_eq(store.open("hero", scratch.get_current_dir()), ProfileStore.OpenResult.OPENED)
	var recovered := PartyProgression.reopen(setup, prep.catalog, store.frontier(String(setup.run_id)))
	assert_not_null(recovered)
	assert_eq(recovered.frontier(12).image, mutation.frontier.image)
	assert_eq(recovered.active_power_form(&"host", choice.base.id), chosen.evolution)
	assert_eq(recovered.offer(&"host", pending.ordinal).options, pending.options)
	assert_eq(recovered.select(&"host", pending.ordinal, pending.evolution), Selection.APPLIED)
	assert_true(store.close())


func test_fusion_rune_requirements_and_retained_capability_control_the_separate_bonus() -> void:
	for arm: Array in [[false, false], [true, false], [true, true]]:
		var equipped: bool = arm[0]
		var retains: bool = arm[1]
		var runes: Array[StringName] = [&"", &"R02" if equipped else &""]
		var preparation := _recipe_preparation(runes, true, retains)
		var queue := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		_rank_recipe_bases(queue)
		var tick := 10
		for evolution: StringName in [&"E07A", &"E12A"]:
			var acquired := false
			for _attempt: int in 4:
				tick += 1
				var offer := queue.read_offer(queue.earn(tick))
				if offer.evolution == evolution:
					acquired = queue.select(offer.ordinal, evolution) == Selection.APPLIED
					break
			assert_true(acquired)
		for _rank: int in 5:
			tick += 1
			assert_eq(queue.select(queue.earn(tick), &"P03"), Selection.APPLIED)
		tick += 1
		var frozen := queue.read_offer(queue.earn(tick))
		assert_eq(frozen.evolution, &"E03A")
		assert_eq(frozen.fusion, &"F06" if equipped else &"")
		var resumed := RunRewardQueue.begin(preparation, RunRandom.new(6), &"host")
		assert_true(resumed.restore(queue.checkpoint(), tick, tick))
		assert_eq(resumed.read_offer(frozen.ordinal).options, frozen.options)
		if not equipped:
			continue
		tick += 1
		var chosen := resumed.read_offer(resumed.earn(tick))
		assert_eq(resumed.select(chosen.ordinal, &"F06"), Selection.APPLIED)
		assert_eq(resumed.select(chosen.ordinal, &"E03A"), Selection.UNKNOWN_REWARD)
		assert_eq(resumed.read_offer(frozen.ordinal).options, frozen.options)
		assert_eq(resumed.select(frozen.ordinal, &"E03A"), Selection.APPLIED if retains else Selection.STALE_OPTION)


func _rank_recipe_bases(queue: RunRewardQueue) -> void:
	var tick := 0
	for base: StringName in [&"P07", &"P12"]:
		for rank: int in range(1, 6):
			tick += 1
			var offer := queue.read_offer(queue.earn(tick))
			assert_eq(offer.options.get(base), rank)
			assert_eq(queue.select(offer.ordinal, base), Selection.APPLIED)


static func _recipe_preparation(runes: Array[StringName], fusion_controls: bool = false,
		retains: bool = false) -> RunPreparation:
	var bundle: CatalogBundle = load("res://dev/fixtures/catalog_reciprocal.tres")
	var entries: Array[CatalogEntry] = [_entry(&"H01", Kind.HERO), _entry(&"W01", Kind.WEAPON),
		_entry(&"R02", Kind.RUNE)]
	for entry: CatalogEntry in bundle.entries:
		if fusion_controls and entry.id == &"F06":
			var fusion: CatalogEntry = entry.duplicate()
			fusion.fusion_runes = [_recipe_ref(&"R02")]
			if retains:
				fusion.second_component_capabilities = [&"reprisal_pulse"]
			entries.append(fusion)
		else:
			entries.append(entry)
	var alternate := _entry(&"E07B", Kind.EVOLUTION, Eligibility.RUN_RECIPE)
	alternate.lifetime = CatalogEntry.Lifetime.RUN
	alternate.base = _recipe_ref(&"P07")
	alternate.catalyst = _recipe_ref(&"R02")
	entries.append(alternate)
	var candidates := _slots()
	candidates[0] = &"P07"
	candidates[1] = &"P12"
	if fusion_controls:
		var third := _entry(&"P03", Kind.POWER)
		third.ranks = [&"rank1", &"rank2", &"rank3", &"rank4", &"rank5"]
		var third_form := _entry(&"E03A", Kind.EVOLUTION, Eligibility.RUN_RECIPE)
		third_form.lifetime = CatalogEntry.Lifetime.RUN
		third_form.base = _recipe_ref(third.id)
		third_form.catalyst = _recipe_ref(&"P12")
		third_form.catalyst_capability = &"reprisal_pulse"
		entries.append_array([third, third_form])
		candidates[2] = third.id
	return RunPreparation.select(DefinitionCatalog.compile(&"fixture_evolutions", entries),
		&"H01", &"W01", runes, candidates, {&"P07": true, &"P12": true})


static func _recipe_ref(id: StringName) -> CatalogReference:
	var reference := CatalogReference.new()
	reference.target_id = id
	return reference


static func _setup() -> RunSetup:
	var setup := RunSetup.new()
	setup.role = RunSetup.Role.HOST
	setup.run_id = &"fixture"
	setup.authority_id = &"host"
	setup.epoch = 1
	setup.seed = 3
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture_rewards"
	setup.challenge_id = &"normal"
	setup.initial_realms = {&"host": &"core", &"guest": &"optional"}
	return setup


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
