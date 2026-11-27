extends GutTest

const Route := preload("res://tests/unit/test_run_realm_passages.gd").Route
const OUTSIDE := WorldTopology.OVERWORLD
const HALL := &"hall_of_echoes"
const HOST := &"host"
const GUEST := &"guest"
const COLLAPSE := RunParty.COLLAPSE_TICK


func test_idle_hall_registration_at_admitted_entry_matches_full_stepping_around_collapse() -> void:
	for start_tick: int in [COLLAPSE - 1, COLLAPSE]:
		var eager := _arrival_trace(start_tick, false)
		var deferred := _arrival_trace(start_tick, true)
		assert_false(eager.is_empty())
		assert_eq(deferred, eager)
		if eager.is_empty():
			continue
		assert_eq(eager["started"], start_tick < COLLAPSE)
		assert_eq(eager["during_collapse"], RunRealmTrial.Observation.RETAINED)
		assert_eq(eager["after_exit"], RunRealmTrial.Observation.RESET if start_tick < COLLAPSE
			else RunRealmTrial.Observation.RETAINED)
		assert_eq(eager["final_phase"], RunRealmTrial.Phase.DORMANT)


func _arrival_trace(start_tick: int, defer_hall: bool) -> Dictionary:
	var route := Route.new(HALL)
	assert_true(route.begin())
	var activity := _world_for(route)
	if not defer_hall:
		assert_true(activity.register_realm(route.inner))
	# Controlled clock setup leaves four real closed ticks through trial activation.
	var initial := start_tick - 4
	route.authority._closed_tick = initial
	route.party._tick = initial
	activity._tick = initial
	var existing := _spawn_site(OUTSIDE, &"outside", Route.offset(route.handle, 52, 0), initial + 1)
	assert_true(activity.schedule_spawn(existing))
	var arrival := route.inner.module_center(WorldTopology.ENTRY)
	var trial := RunRealmTrial.declare(route.party, route.inner, arrival, 30.0, true, false)
	assert_not_null(trial)
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_party)
	var before := _snapshot(route, activity)
	assert_eq(route.inner.view(GUEST).visible, [])
	assert_eq(activity.snapshot().rng[&"world-spawn/outside"][1], 1)

	# The empty Hall registers at the boundary before the ordinary interaction can publish an arrival.
	if defer_hall:
		assert_true(activity.register_realm(route.inner))
	var enter := route.input(GUEST, PlayerCommand.INTERACT, route.handle)
	assert_true(route.submit(enter))
	assert_true(route.passages.interact(enter))
	var entered := _snapshot(route, activity)
	assert_eq(activity.snapshot().actors[GUEST][0], HALL)
	assert_eq(route.inner.view(GUEST).visible.size(), 1)
	assert_true(route.inner.view(HOST).visible.is_empty())
	assert_true(route.authority.close_tick())
	assert_true(route.authority.closed_party)
	var click := route.input(GUEST, PlayerCommand.INTERACT, arrival)
	assert_eq(click.tick, start_tick)
	assert_true(route.submit(click))
	assert_eq(route.authority.interactions.size(), 1)
	var admitted: RunIntent = route.authority.interactions[0]
	assert_eq(admitted.receipt(), click.receipt())
	var started := trial.start(admitted.seat_id, CombatInstant.at_tick(admitted.tick))
	var activation := _snapshot(route, activity)
	if route.party.closed_tick < COLLAPSE:
		assert_true(route.authority.close_tick())
		assert_true(route.authority.closed_party)
	var at_collapse := trial.observe(CombatInstant.at_tick(route.party.closed_tick))
	assert_true(route.walk_to_exit(GUEST))
	var leave := route.input(GUEST, PlayerCommand.INTERACT, route.inner.module_center(WorldTopology.RETURN_EXIT))
	assert_true(route.submit(leave))
	assert_true(route.passages.interact(leave))
	var after_exit := trial.observe(CombatInstant.at_tick(route.party.closed_tick))
	assert_eq(route.inner.view(GUEST).visible, [])
	assert_eq(activity.snapshot().actors[GUEST][0], OUTSIDE)
	assert_eq(activity.snapshot().rng[&"world-spawn/outside"][1], 1)
	return {"before": before, "arrival": entered, "activation": activation, "started": started,
		"during_collapse": at_collapse, "exit": _snapshot(route, activity), "after_exit": after_exit,
		"final_phase": trial.phase}


func test_authored_spawn_precedes_first_entry_even_without_a_viewer() -> void:
	var active := Route.new(HALL)
	var missed := Route.new(HALL)
	for route: Route in [active, missed]:
		assert_true(route.begin())
		var activity := _world_for(route)
		var at := Route.offset(route.inner.module_center(WorldTopology.ENTRY), 40, 0)
		var site := _spawn_site(HALL, &"hall_resident", at, 1)
		if route == active:
			assert_true(activity.register_realm(route.inner))
			assert_true(activity.schedule_spawn(site))
		else:
			assert_false(activity.schedule_spawn(site))
		assert_true(route.authority.close_tick())
		assert_true(route.authority.closed_party)
		assert_true(route.inner.view(GUEST).visible.is_empty())
		var spawn := &"spawn/13:hall_resident/1"
		assert_eq(activity.snapshot().actors.has(spawn), route == active)
		if route == missed:
			assert_true(activity.register_realm(route.inner))
			assert_false(activity.schedule_spawn(site))
		var enter := route.input(GUEST, PlayerCommand.INTERACT, route.handle)
		assert_true(route.submit(enter))
		assert_true(route.passages.interact(enter))
		assert_eq(activity.snapshot().actors.has(spawn), route == active)
		assert_eq(activity.snapshot().rng.has(&"world-spawn/hall_resident"), route == active)


func _world_for(route: Route) -> WorldActivity:
	var activity := WorldActivity.new(route.kernel, Route.Seed)
	assert_true(activity.register_realm(route.outer))
	assert_true(activity.track_player(HOST))
	assert_true(activity.track_player(GUEST))
	route.authority.activity = activity
	return activity


static func _spawn_site(realm: StringName, id: StringName, at: RealmSweep.Point,
		first_tick: int) -> WorldActivity.SpawnSite:
	var profile := WorldEnemy.Rules.new()
	profile.faction = &"fixture"
	profile.family = &"fixture/arrival"
	profile.hp = Quantity.from_count(20)
	profile.damage = Quantity.from_count(1)
	profile.radius = 4.0
	profile.sight = 16.0
	profile.attack_range = 4.0
	profile.attack_radius = 4.0
	profile.windup_ticks = 1
	profile.recovery_ticks = 1
	var site := WorldActivity.SpawnSite.new()
	site.id = id
	site.realm = realm
	site.rules = profile
	site.first_tick = first_tick
	site.period = 3
	site.limit = 1
	site.positions = [at]
	return site


static func _snapshot(route: Route, activity: WorldActivity) -> Dictionary:
	return {"world": activity.snapshot(), "closed": route.authority.closed_result(),
		"guest": route.inner.view(GUEST), "remote": route.inner.view(HOST)}
