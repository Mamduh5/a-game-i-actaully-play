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
