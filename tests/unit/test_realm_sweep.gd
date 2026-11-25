extends GutTest


func test_fast_sweep_hits_thin_segment_and_preserves_an_initial_contact() -> void:
	var a := _point(50, -3)
	var b := _point(50, 3)
	assert_almost_eq(RealmSweep.circle_segment(_point(0, 0), _point(100, 0), 1, a, b), 0.49, 1e-12)
	assert_eq(RealmSweep.circle_segment(_point(50, 0), _point(100, 0), 1, a, b), 0.0)
	assert_eq(RealmSweep.circle_segment(_point(0, 5), _point(100, 5), 1, a, b), RealmSweep.MISS)
	assert_almost_eq(RealmSweep.circle_segment(_point(0, 4), _point(100, 4), 1, a, b), 0.5, 1e-12)


func test_relative_motion_can_create_or_prevent_circle_contact() -> void:
	var start := _point(0, 0)
	var end := _point(20, 0)
	var target := _point(16, 0)
	assert_almost_eq(RealmSweep.moving_circles(start, end, 1, target, _point(6, 0), 1), 14.0 / 30.0, 1e-12)
	assert_eq(RealmSweep.moving_circles(start, end, 1, target, _point(36, 0), 1), RealmSweep.MISS)
	assert_eq(RealmSweep.moving_circles(start, end, 1, _point(1, 0), _point(21, 0), 1), 0.0)


func test_scalar_sweeps_preserve_order_and_contact_at_far_bound() -> void:
	var anchor := 1_000_000_000_000.0
	var start := _point(anchor, -anchor)
	var finish := _point(anchor + 64, -anchor)
	var first := RealmSweep.circle_segment(start, finish, 0.125,
		_point(anchor + 16, -anchor - 4), _point(anchor + 16, -anchor + 4))
	var second := RealmSweep.circle_segment(start, finish, 0.125,
		_point(anchor + 16.0009765625, -anchor - 4), _point(anchor + 16.0009765625, -anchor + 4))
	assert_almost_eq(first, 127.0 / 512.0, 1e-12)
	assert_almost_eq(second, 16257.0 / 65536.0, 1e-12)
	assert_lt(first, second)


func test_authored_polygon_bakes_once_into_a_far_realm_and_indexes_all_edges() -> void:
	var authored := CollisionPolygon2D.new()
	authored.polygon = PackedVector2Array([Vector2(0, -4), Vector2(0, 4), Vector2(1, 4), Vector2(1, -4)])
	authored.position = Vector2(0.125, 0)
	var far := 1_000_000_000_000.0
	var edges := RealmOutline.bake(authored.polygon, authored.transform, _point(far + 8, far))
	authored.free()
	assert_eq(edges.size(), 4)
	if edges.size() != 4:
		return
	var index := RealmSpatialIndex.new(&"module-seam")
	for id: int in edges.size():
		assert_true(index.register(&"baked-wall", id, edges[id].bounds))
	var candidates := index.query(RealmBounds.from_sweep(far, far, far + 16, far, 0))
	assert_eq(candidates.proxies.size(), 2)
	var first := RealmSweep.circle_segment(_point(far, far), _point(far + 16, far), 0,
		edges[0].first, edges[0].last)
	assert_almost_eq(first, 65.0 / 128.0, 1e-12)


func _point(x: float, y: float) -> RealmSweep.Point:
	return RealmSweep.Point.new(x, y)
