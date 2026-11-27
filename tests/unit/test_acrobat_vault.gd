extends GutTest

const SEAT := &"acrobat"
const RUN := &"c04-vault"
const REALM := WorldTopology.OVERWORLD
const START_X := 62.0
const Y := 128.0


func test_vault_crosses_only_a_low_solid_and_preserves_the_guest_motion_lock() -> void:
	for low: bool in [true, false]:
		var floor := _floor()
		assert_true(floor.place_route_solid(&"obstacle", RealmSweep.Point.new(94, Y), 4.0, null, low))
		var encounter := _acrobat(floor)
		assert_not_null(encounter)
		assert_eq(_submit(encounter, 1, PlayerCommand.MANUAL), RunAuthority.Admission.QUEUED)
		assert_true(encounter.close_tick())
		assert_true(encounter.closed_result().outcomes[0].manual)
		assert_false(encounter.view_for(SEAT).manual_ready)
		var launch := encounter.movement_state(SEAT, 1, 2)
		assert_false(launch.permits_prediction)
		var guest := GuestMovement.new()
		assert_eq(guest.install_baseline(REALM, launch, []), GuestMovement.Acceptance.APPLIED)
		assert_true(guest.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1, 0)).is_empty())
		for tick: int in range(2, 16):
			assert_true(encounter.close_tick())
			assert_eq(encounter.fault(), &"")
		var landing := encounter.movement_state(SEAT, 1, 16)
		assert_true(landing.permits_prediction)
		assert_eq(guest.receive(landing), GuestMovement.Acceptance.APPLIED)
		assert_false(guest.issue(PlayerCommand.new(PlayerCommand.MOVE_AXES, 1, 0)).is_empty())
		assert_almost_eq(landing.position.x, 126.0 if low else 76.0, 0.0001)


func test_a_low_obstacle_still_blocks_walking_and_an_occupied_vault_landing_costs_nothing() -> void:
	var floor := _floor()
	var lane := Y - 40.0
	assert_true(floor.place_route_solid(&"landing", RealmSweep.Point.new(126, lane), 4.0, null, true))
	var encounter := _acrobat(floor, lane)
	assert_not_null(encounter)
	assert_eq(_submit(encounter, 1, PlayerCommand.MANUAL), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	assert_false(encounter.closed_result().outcomes[0].manual)
	assert_true(encounter.view_for(SEAT).manual_ready)
	assert_eq(encounter.view_for(SEAT).player.at.x, START_X)
	assert_eq(_submit(encounter, 2, PlayerCommand.MOVE_TO), RunAuthority.Admission.QUEUED)
	for tick: int in range(2, 43):
		assert_true(encounter.close_tick())
	assert_almost_eq(encounter.view_for(SEAT).player.at.x, 108.0, 0.0001)
	assert_true(floor.remove_route_solid(&"landing"))
	assert_eq(_submit(encounter, 3, PlayerCommand.MANUAL), RunAuthority.Admission.QUEUED)
	assert_true(encounter.close_tick())
	assert_true(encounter.closed_result().outcomes[0].manual)


func test_airborne_ground_only_strike_misses_while_sword_and_airborne_reaching_strike_still_hit() -> void:
	for ground_only: bool in [true, false]:
		var encounter := _acrobat(_floor())
		var foe := WorldEnemy.Rules.new()
		foe.faction = &"fixture"
		foe.foes = [WorldEnemy.PARTY]
		foe.family = &"fixture/height"
		foe.hp = Quantity.from_count(100)
		foe.damage = Quantity.from_count(16)
		foe.radius = 8.0
		foe.sight = 150.0
		foe.attack_range = 100.0
		foe.attack_radius = 32.0
		foe.windup_ticks = 3
		foe.recovery_ticks = 14
		foe.ground_only = ground_only
		assert_true(encounter.place_enemy(&"foe", foe, RealmSweep.Point.new(144, Y)))
		assert_true(encounter.close_tick())
		assert_eq(encounter.view_for(SEAT).threats[0].impact_tick, 4)
		assert_eq(_submit(encounter, 1, PlayerCommand.MANUAL), RunAuthority.Admission.QUEUED)
		for tick: int in range(2, 5):
			assert_true(encounter.close_tick())
		var view := encounter.view_for(SEAT)
		assert_almost_eq(view.player.at.x, START_X + 128.0 / 14.0, 0.0001)
		assert_false(encounter.movement_state(SEAT, 1, 5).permits_prediction)
		assert_eq(view.player.hp.native_at_scale(0), 100 if ground_only else 84)
		assert_eq(view.others[0].hp.native_at_scale(0), 80)
		for tick: int in range(5, 22):
			assert_true(encounter.close_tick())
		assert_true(encounter.movement_state(SEAT, 1, 22).permits_prediction)
		assert_eq(encounter.view_for(SEAT).player.hp.native_at_scale(0), 84 if ground_only else 68)


static func _floor() -> WorldExploration:
	return WorldExploration.create(WorldTopology.generate(3207), [SEAT])


static func _acrobat(floor: WorldExploration, row: float = Y) -> StarterEncounter:
	var bundle: CatalogBundle = load("res://src/catalog/starter_roster.tres")
	var catalog := bundle.compile()
	var setup := RunSetup.new()
	setup.run_id = RUN
	setup.epoch = 1
	setup.seed = 3207
	setup.authority_id = SEAT
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = catalog.revision
	setup.challenge_id = &"normal"
	setup.initial_realms = {SEAT: REALM}
	var slots: Array[StringName] = []
	slots.resize(RunPreparation.CANDIDATE_SLOTS)
	slots.fill(&"")
	var build := StarterEncounter.Build.new()
	build.preparation = RunPreparation.select(catalog, &"H02", &"W01", [&"", &""], slots, {})
	build.powers = RunRewardQueue.begin(build.preparation, RunRandom.new(setup.seed), SEAT)
	build.start = RealmSweep.Point.new(START_X, row)
	build.maximum_hp = Quantity.from_count(100)
	return StarterEncounter.assemble(setup, SEAT, floor, {SEAT: build})


static func _submit(encounter: StarterEncounter, sequence: int, action: StringName) -> RunAuthority.Admission:
	var command := PlayerCommand.new(action, 210, encounter.view_for(SEAT).player.at.y)
	var intent := RunIntent.new(RUN, 1, REALM, SEAT, encounter.next_tick(), sequence, action, command)
	intent.reliable = action == PlayerCommand.MANUAL
	return encounter.submit(SEAT, intent)
