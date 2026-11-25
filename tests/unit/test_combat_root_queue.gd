extends GutTest


func test_equal_due_roots_survive_reversed_arrival_and_later_roots_stay_pending() -> void:
	var due := CombatInstant.at_tick(11)
	for reversed: bool in [false, true]:
		var queue := CombatRootQueue.new()
		var left := _origin(&"a", 2, 9)
		var right := _origin(&"b", 1, 10)
		var first := right if reversed else left
		var second := left if reversed else right
		assert_eq(queue.admit(first, due), CombatRootQueue.Result.ACCEPTED)
		assert_eq(queue.admit(first, due), CombatRootQueue.Result.REPEATED)
		var stale := queue.earliest_wave()
		assert_eq(queue.admit(second, due), CombatRootQueue.Result.ACCEPTED)
		assert_eq(queue.admit(_origin(&"a", 3, 10), CombatInstant.at_tick(12)), CombatRootQueue.Result.ACCEPTED)
		assert_false(queue.close(stale))
		assert_eq(queue.pending_count(), 3)
		var wave := queue.earliest_wave()
		assert_eq(wave.origins.size(), 2)
		assert_eq(wave.origins[0].owner, &"a")
		assert_eq(wave.origins[1].owner, &"b")
		assert_true(queue.close(wave))
		assert_eq(queue.pending_count(), 1)
		assert_eq(queue.earliest_wave().due.tick, 12)
		assert_eq(queue.admit(_origin(&"c", 1, 10), due), CombatRootQueue.Result.CLOSED_INSTANT)


func test_swept_contacts_in_one_tick_remain_ordered_below_binary64_time_spacing() -> void:
	var spatial := RealmCircleTime.new()
	var origin := RealmSweep.Point.new(0, 0)
	var n := float(1 << 48)
	var finish := RealmSweep.Point.new(4 * n, 0)
	var early := spatial.measure(origin, finish, 0, RealmSweep.Point.new(n, 0), RealmSweep.Point.new(3 * n - 1, 0), 0)
	var late := spatial.measure(origin, finish, 0, RealmSweep.Point.new(n + 1, 0), RealmSweep.Point.new(3 * n - 2, 0), 0)
	assert_eq(early.earliest, late.earliest)
	assert_eq(early.latest, late.latest)
	var queue := CombatRootQueue.new()
	assert_eq(queue.admit(_origin(&"a", 1, 5), CombatInstant.at_contact(5, late)), CombatRootQueue.Result.ACCEPTED)
	assert_eq(queue.admit(_origin(&"z", 1, 5), CombatInstant.at_contact(5, early)), CombatRootQueue.Result.ACCEPTED)
	var wave := queue.earliest_wave()
	assert_eq(wave.origins.size(), 1)
	assert_eq(wave.origins[0].owner, &"z")
	assert_true(queue.close(wave))
	assert_eq(queue.earliest_wave().origins[0].owner, &"a")


func test_tick_endpoint_is_the_following_boundary_and_uncertain_order_leaves_pending_roots_intact() -> void:
	var end := RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT, 1, 1)
	assert_eq(CombatInstant.at_contact(7, end).order_against(CombatInstant.at_tick(8)), RealmCircleTime.Order.SAME)
	var unknown_end := RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT, 0.9, 1)
	assert_null(CombatInstant.at_contact(7, unknown_end))
	var first := RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT, 0.4, 0.6)
	var second := RealmCircleTime.Contact.new(RealmCircleTime.Result.HIT, 0.5, 0.7)
	var queue := CombatRootQueue.new()
	assert_eq(queue.admit(_origin(&"a", 1, 7), CombatInstant.at_contact(7, first)), CombatRootQueue.Result.ACCEPTED)
	assert_eq(queue.admit(_origin(&"b", 1, 7), CombatInstant.at_contact(7, second)), CombatRootQueue.Result.ACCEPTED)
	assert_null(queue.earliest_wave())
	assert_false(queue.close(null))
	assert_eq(queue.pending_count(), 2)
	assert_eq(queue.admit(_origin(&"c", 1, 6), CombatInstant.at_tick(6)), CombatRootQueue.Result.ACCEPTED)
	var certified := queue.earliest_wave()
	assert_not_null(certified)
	if certified != null:
		assert_eq(certified.origins[0].owner, &"c")
		assert_true(queue.close(certified))
	assert_eq(queue.pending_count(), 2)


func test_pr12_prioritizes_authored_priority_and_commitment_before_provenance() -> void:
	var first := _origin(&"z", 1, 3)
	var second := _origin(&"a", 1, 4)
	assert_eq(first.claim_order(second), RealmCircleTime.Order.BEFORE)
	second.priority = 5
	assert_eq(first.claim_order(second), RealmCircleTime.Order.AFTER)
	first.priority = 5
	first.committed_at = CombatInstant.at_tick(4)
	assert_eq(first.claim_order(second), RealmCircleTime.Order.AFTER)


static func _origin(owner: StringName, activation: int, tick: int) -> CombatOrigin:
	var origin := CombatOrigin.new()
	origin.owner = owner
	origin.activation = activation
	origin.committed_at = CombatInstant.at_tick(tick)
	return origin
