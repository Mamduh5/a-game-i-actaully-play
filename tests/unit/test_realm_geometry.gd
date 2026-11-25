extends GutTest

const BODY := 1
const BLOCKER := 2


func test_next_sweep_observes_committed_pose_and_removed_blocker() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var initial_center := RealmSweep.Point.new(6.0, 0.0)
	var wall := RealmOutline.Edge.new()
	wall.first = RealmSweep.Point.new(2.0, -2.0)
	wall.last = RealmSweep.Point.new(2.0, 2.0)
	assert_true(geometry.add_circle(&"target", 0, initial_center, 0.5, BODY))
	assert_true(geometry.add_segment(&"door", 0, wall, BLOCKER, false))
	assert_true(geometry.add_segment(&"fixed", 0, wall, BLOCKER, true))

	initial_center.y = 10.0
	wall.first.x = 100.0
	var start := RealmSweep.Point.new(0.0, 0.0)
	var finish := RealmSweep.Point.new(6.0, 0.0)
	var captured := geometry.sweep_circle(&"outer", start, finish, 0.5, BODY | BLOCKER)
	assert_eq(captured.revision, 3)
	assert_eq(captured.contacts.size(), 3)
	var blockers := geometry.sweep_circle(&"outer", start, finish, 0.5, BLOCKER)
	assert_eq(blockers.contacts.size(), 2)
	for contact: RealmGeometry.Contact in blockers.contacts:
		assert_almost_eq(contact.time, 0.25, 1e-14)
	assert_null(geometry.sweep_circle(&"inner", start, finish, 0.5, BODY | BLOCKER))
	assert_false(geometry.remove_mutable(&"fixed", 0))
	assert_false(geometry.commit_circle_pose(&"target", 0, RealmSweep.Point.new(INF, 0.0)))
	assert_eq(geometry.revision, 3)

	assert_true(geometry.commit_circle_pose(&"target", 0, RealmSweep.Point.new(6.0, 4.0)))
	assert_true(geometry.remove_mutable(&"door", 0))
	var next := geometry.sweep_circle(&"outer", start, finish, 0.5, BODY | BLOCKER)
	assert_eq(next.revision, 5)
	assert_eq(next.contacts.size(), 1)
	assert_eq(next.contacts[0].entity, &"fixed")
	assert_eq(captured.contacts.size(), 3)
	var snapshot := geometry.circle_center(&"target", 0)
	snapshot.y = 20.0
	assert_eq(geometry.circle_center(&"target", 0).y, 4.0)


func test_moving_target_is_indexed_across_the_path_until_commit_or_displacement() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var bottom := RealmSweep.Point.new(0.0, 250.0)
	var top := RealmSweep.Point.new(0.0, -250.0)
	var left := RealmSweep.Point.new(-250.0, 0.0)
	var right := RealmSweep.Point.new(250.0, 0.0)
	assert_true(geometry.add_circle(&"crossing", 0, top, 1.0, BODY))
	assert_eq(geometry.sweep_circle(&"outer", left, right, 1.0, BODY).contacts.size(), 0)
	assert_true(geometry.stage_circle_motion(&"crossing", 0, bottom))
	assert_eq(geometry.circle_center(&"crossing", 0).y, -250.0)
	var swept := geometry.sweep_circle(&"outer", left, right, 1.0, BODY)
	assert_eq(swept.contacts.size(), 1)
	assert_almost_eq(swept.contacts[0].time, 0.5 - 2.0 / sqrt(500000.0), 1e-14)
	assert_true(geometry.commit_circle_motion(&"crossing", 0))
	assert_eq(geometry.circle_center(&"crossing", 0).y, 250.0)
	assert_eq(geometry.sweep_circle(&"outer", left, right, 1.0, BODY).contacts.size(), 0)
	assert_true(geometry.stage_circle_motion(&"crossing", 0, top))
	assert_true(geometry.commit_circle_pose(&"crossing", 0, right))
	assert_false(geometry.commit_circle_motion(&"crossing", 0))
	var displaced := geometry.sweep_circle(&"outer", left, right, 1.0, BODY)
	assert_eq(displaced.contacts.size(), 1)
	assert_almost_eq(displaced.contacts[0].time, 0.996, 1e-14)


func test_certified_sweep_orders_far_walls_and_retains_the_tangent_contact() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var far := 1_000_000_000_000.0
	var start := RealmSweep.Point.new(far, -far)
	var finish := RealmSweep.Point.new(far + 64.0, -far)
	for slot: int in [1, 0]:
		var wall := RealmOutline.Edge.new()
		var x := far + 16.0 + float(slot) / 1024.0
		wall.first = RealmSweep.Point.new(x, -far - 4.0)
		wall.last = RealmSweep.Point.new(x, -far + 4.0)
		assert_true(geometry.add_segment(&"wall", slot, wall, BLOCKER, true))
	assert_true(geometry.add_circle(&"tangent", 0, RealmSweep.Point.new(far + 32.0, -far + 0.125), 0.0, BODY))
	var result := geometry.certify_circle_sweep(&"outer", start, finish, 0.125, BODY | BLOCKER)
	assert_eq(result.contacts.size(), 3)
	assert_true(result.unresolved.is_empty())
	var walls: Dictionary[int, RealmGeometry.Contact] = {}
	for contact: RealmGeometry.Contact in result.contacts:
		if contact.entity == &"wall":
			walls[contact.shape] = contact
		else:
			assert_true(contact.proof.earliest <= 0.5 and contact.proof.latest >= 0.5)
	var first := walls[0]
	var second := walls[1]
	assert_eq(first.proof.order_against(second.proof), RealmCircleTime.Order.BEFORE)


func test_displacement_stops_at_thin_wall_and_commits_before_the_child_query() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var far := 1_000_000_000_000.0
	var start := RealmSweep.Point.new(far, -far)
	var finish := RealmSweep.Point.new(far + 64.0, -far)
	assert_true(geometry.add_circle(&"mover", 0, start, 0.125, BODY))
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(far + 16.0, -far - 4.0)
	edge.last = RealmSweep.Point.new(far + 16.0, -far + 4.0)
	assert_true(geometry.add_segment(&"door", 1, edge, BLOCKER, false))
	assert_true(geometry.add_segment(&"door", 0, edge, BLOCKER, false))
	var result := geometry.displace_circle(&"mover", 0, finish, BLOCKER)
	assert_not_null(result)
	if result == null:
		return
	assert_eq(result.revision, 4)
	assert_eq(result.stopped_by.size(), 2)
	assert_eq(result.stopped_by[0].shape, 0)
	assert_eq(result.stopped_by[1].shape, 1)
	assert_lt(result.finish.x, far + 15.875)
	assert_almost_eq(result.finish.x - far, 15.875, 0.001)
	assert_eq(geometry.circle_center(&"mover", 0).x, result.finish.x)
	assert_true(geometry.remove_mutable(&"door", 0))
	assert_true(geometry.remove_mutable(&"door", 1))
	var next := geometry.displace_circle(&"mover", 0, finish, BLOCKER)
	assert_eq(next.revision, 7)
	assert_eq(next.finish.x, finish.x)
	assert_true(next.stopped_by.is_empty())
	assert_eq(result.stopped_by.size(), 2)


func test_displacement_can_retreat_from_initial_overlap_and_holds_ambiguous_path() -> void:
	var geometry := RealmGeometry.new(&"outer")
	var start := RealmSweep.Point.new(-0.5, 0.0)
	assert_true(geometry.add_circle(&"mover", 0, start, 1.0, BODY))
	var edge := RealmOutline.Edge.new()
	edge.first = RealmSweep.Point.new(0.0, -8.0)
	edge.last = RealmSweep.Point.new(0.0, 8.0)
	assert_true(geometry.add_segment(&"wall", 0, edge, BLOCKER, true))
	var into := geometry.displace_circle(&"mover", 0, RealmSweep.Point.new(0.5, 0.0), BLOCKER)
	assert_not_null(into)
	assert_eq(into.finish.x, start.x)
	assert_eq(into.revision, 2)
	assert_eq(into.stopped_by[0].proof.latest, 0.0)
	var retreat := geometry.displace_circle(&"mover", 0, RealmSweep.Point.new(-4.0, 0.0), BLOCKER)
	assert_not_null(retreat)
	assert_eq(retreat.finish.x, -4.0)
	assert_eq(retreat.revision, 3)
	assert_true(retreat.stopped_by.is_empty())
	var ambiguous := RealmGeometry.new(&"outer")
	assert_true(ambiguous.add_circle(&"mover", 0, RealmSweep.Point.new(0.0, 0.0), 5.0, BODY))
	assert_true(ambiguous.add_circle(&"tangent", 0, RealmSweep.Point.new(2.0, 11.0), 0.0, BLOCKER))
	var diagonal := RealmSweep.Point.new(12.0, 16.0)
	var proof := ambiguous.certify_circle_sweep(&"outer", RealmSweep.Point.new(0.0, 0.0), diagonal, 5.0, BLOCKER)
	assert_eq(proof.unresolved.size(), 1)
	assert_eq(proof.unresolved[0].entity, &"tangent")
	assert_null(ambiguous.displace_circle(&"mover", 0, diagonal, BLOCKER))
	assert_eq(ambiguous.revision, 2)
	assert_eq(ambiguous.circle_center(&"mover", 0).x, 0.0)
