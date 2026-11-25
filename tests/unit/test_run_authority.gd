extends GutTest

const FixtureRules := preload("res://dev/fixtures/run_authority_fixture_rules.gd")
const Admission := RunAuthority.Admission


func test_only_matching_local_authority_starts_with_a_valid_roster() -> void:
	var setup := _setup()
	var run := FixtureRules.new()
	assert_false(run.start(setup, &"guest"))
	assert_false(run.close_tick())
	assert_eq(run.submit(&"seat-a", _intent(1, 1)), Admission.INACTIVE)
	assert_true(run.start(setup, &"original"))
	assert_false(run.start(setup, &"original"))
	setup.initial_realms[&"seat-b"] = &"side"
	assert_eq(
		run.submit(&"seat-b", _intent(1, 1, &"sample_world", &"seat-b", &"side")),
		Admission.WRONG_SEAT
	)
	assert_false(FixtureRules.new().start(setup, &"original"), "Solo requires one seat")
	setup.role = RunSetup.Role.HOST
	assert_true(FixtureRules.new().start(setup, &"original"))


func test_wrong_envelopes_never_advance_streams_or_replace_the_closed_frontier() -> void:
	var run := _start()
	var intent := _intent(1, 1)
	intent.run_id = &"different"
	assert_eq(run.submit(&"seat-a", intent), Admission.WRONG_RUN)
	intent.run_id = &"run"
	intent.epoch = 1
	assert_eq(run.submit(&"seat-a", intent), Admission.WRONG_EPOCH)
	intent.epoch = 2
	assert_eq(run.submit(&"seat-b", intent), Admission.WRONG_SEAT)
	intent.realm_id = &"unrelated"
	assert_eq(run.submit(&"seat-a", intent), Admission.WRONG_REALM)
	intent.realm_id = &"core"
	intent.tick = 2
	assert_eq(run.submit(&"seat-a", intent), Admission.WRONG_TICK)
	intent.tick = 1
	intent.action = &"unregistered"
	assert_eq(run.submit(&"seat-a", intent), Admission.UNSUPPORTED_ACTION)
	assert_true(run.close_tick())
	assert_eq(run.closed_result()["accepted"].size(), 0)
	assert_eq(run.checkpoint()["random"], {})
	assert_eq(run.submit(&"seat-a", _intent(1, 2)), Admission.WRONG_TICK)
	assert_eq(run.next_tick(), 2)


func test_batch_is_canonical_and_conflicting_duplicates_never_take_effect() -> void:
	var setup := _setup()
	setup.role = RunSetup.Role.HOST
	setup.initial_realms[&"seat-b"] = &"side"
	var first := _start(setup)
	var second := _start(setup)
	var inputs: Array[RunIntent] = [
		_intent(1, 2, &"sample_reward", &"seat-b", &"side"),
		_intent(1, 2),
		_intent(1, 1),
		_intent(1, 2, &"sample_reward"),
	]
	for intent: RunIntent in inputs:
		first.submit(intent.seat_id, intent)
	inputs.reverse()
	for intent: RunIntent in inputs:
		second.submit(intent.seat_id, intent)
	assert_eq(first.submit(&"seat-a", _intent(1, 1)), Admission.DUPLICATE)
	assert_eq(first.closed_result()["accepted"].size(), 0, "Open commands remain unpublished")
	assert_eq(first.checkpoint()["sequences"][&"seat-a"], 0)
	assert_true(first.close_tick())
	assert_true(second.close_tick())
	assert_eq(first.closed_result(), second.closed_result())
	assert_eq(first.checkpoint(), second.checkpoint())
	assert_eq(first.closed_result()["accepted"].size(), 2)
	assert_eq(first.closed_result()["accepted"][0]["seat"], &"seat-a")
	assert_eq(first.closed_result()["accepted"][1]["seat"], &"seat-b")
	assert_eq(first.checkpoint()["identity"]["initial_realms"].keys(), [&"seat-a", &"seat-b"])
	assert_eq(first.checkpoint()["random"].keys(), [&"reward", &"world"])
	assert_eq(first.closed_result()["conflicts"], [{"seat": &"seat-a", "sequence": 2}])
	assert_eq(first.submit(&"seat-a", _intent(2, 2)), Admission.STALE_SEQUENCE)


func test_overflow_discards_only_the_saturating_seats_batch() -> void:
	var setup := _setup()
	setup.role = RunSetup.Role.HOST
	setup.initial_realms[&"seat-b"] = &"side"
	var run := _start(setup)
	var limit := RunAuthority.MAX_OPEN_INTENTS_PER_SEAT
	for sequence: int in range(1, limit + 1):
		run.submit(&"seat-a", _intent(1, sequence))
	assert_eq(run.submit(&"seat-a", _intent(1, limit + 1)), Admission.QUEUE_FULL)
	assert_eq(run.submit(&"seat-a", _intent(1, 1)), Admission.QUEUE_FULL)
	assert_eq(
		run.submit(&"seat-b", _intent(1, 1, &"sample_world", &"seat-b", &"side")),
		Admission.QUEUED
	)
	assert_true(run.close_tick())
	assert_eq(run.closed_result()["overflowed"], [&"seat-a"])
	assert_eq(run.closed_result()["accepted"].size(), 1)
	assert_eq(run.checkpoint()["random"][&"world"][1], 1)
	assert_eq(run.submit(&"seat-a", _intent(2, 1)), Admission.QUEUED)


func test_intent_setup_and_observation_objects_do_not_alias_authority_state() -> void:
	var setup := _setup()
	var run := _start(setup)
	var intent := _intent(1, 1)
	assert_eq(run.submit(&"seat-a", intent), Admission.QUEUED)
	setup.initial_realms.clear()
	intent.action = &"sample_reward"
	run.close_tick()
	var copied := run.closed_result()
	assert_eq(copied["outcomes"][0]["stream"], &"world")
	copied["accepted"][0]["seat"] = &"forged"
	copied["outcomes"].clear()
	var exported := run.checkpoint()
	exported["random"][&"world"][1] = 9000
	exported["identity"]["initial_realms"].clear()
	assert_eq(run.closed_result()["accepted"][0]["seat"], &"seat-a")
	assert_eq(run.closed_result()["outcomes"].size(), 1)
	assert_eq(run.checkpoint()["random"][&"world"][1], 1)
	assert_eq(run.submit(&"seat-a", _intent(2, 2)), Admission.QUEUED)


func test_closed_checkpoint_resumes_rng_and_admission_with_pending_input_excluded() -> void:
	var setup := _setup()
	var original := _start(setup)
	original.submit(&"seat-a", _intent(1, 1))
	original.close_tick()
	original.submit(&"seat-a", _intent(2, 2))
	var saved: Dictionary = bytes_to_var(var_to_bytes(original.checkpoint()))
	var resumed := FixtureRules.new()
	assert_true(resumed.restore(setup, &"original", saved))
	assert_eq(resumed.next_tick(), 2)
	assert_eq(resumed.submit(&"seat-a", _intent(2, 1)), Admission.STALE_SEQUENCE)
	assert_eq(resumed.submit(&"seat-a", _intent(2, 2)), Admission.QUEUED)
	original.close_tick()
	resumed.close_tick()
	assert_eq(resumed.closed_result(), original.closed_result())
	assert_eq(resumed.checkpoint(), original.checkpoint())


func test_checkpoint_rejects_changed_authority_identity_and_malformed_fields() -> void:
	var setup := _setup()
	var original := _start(setup)
	original.submit(&"seat-a", _intent(1, 1))
	original.close_tick()
	var saved := original.checkpoint()
	var target := FixtureRules.new()
	assert_false(target.restore(setup, &"guest", saved))
	setup.epoch += 1
	assert_false(target.restore(setup, &"original", saved))
	setup.epoch -= 1
	var bad := saved.duplicate(true)
	bad["random"][&"world"][1] = -1
	assert_false(target.restore(setup, &"original", bad))
	bad = saved.duplicate(true)
	bad["sequences"].clear()
	assert_false(target.restore(setup, &"original", bad))
	bad = saved.duplicate(true)
	bad["engine"] = "different build"
	assert_false(target.restore(setup, &"original", bad))
	assert_true(target.restore(setup, &"original", saved))


func test_other_stream_draws_do_not_shift_the_world_sequence() -> void:
	var with_rewards := RunRandom.new(426001)
	var world_only := RunRandom.new(426001)
	assert_eq(with_rewards.draw(&"world"), world_only.draw(&"world"))
	with_rewards.draw(&"reward")
	with_rewards.draw(&"reward")
	assert_eq(with_rewards.draw(&"world"), world_only.draw(&"world"))
	assert_eq(with_rewards.checkpoint()[&"world"], world_only.checkpoint()[&"world"])
	assert_ne(with_rewards.checkpoint()[&"world"][0], with_rewards.checkpoint()[&"reward"][0])


func _setup() -> RunSetup:
	var setup := RunSetup.new()
	setup.run_id = &"run"
	setup.authority_id = &"original"
	setup.epoch = 2
	setup.seed = 426001
	setup.rules_revision = &"V42.6/R1"
	setup.catalog_revision = &"fixture"
	setup.challenge_id = &"fixture"
	setup.initial_realms = {&"seat-a": &"core"}
	return setup


func _start(setup: RunSetup = null) -> RunAuthority:
	var run := FixtureRules.new()
	assert_true(run.start(_setup() if setup == null else setup, &"original"))
	return run


func _intent(
		tick: int, sequence: int, action: StringName = &"sample_world",
		seat: StringName = &"seat-a", realm: StringName = &"core"
) -> RunIntent:
	return RunIntent.new(&"run", 2, realm, seat, tick, sequence, action)
