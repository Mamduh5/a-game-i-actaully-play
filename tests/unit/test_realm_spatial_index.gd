extends GutTest


func test_complete_crowded_stack_and_proxy_identity() -> void:
	var index := RealmSpatialIndex.new(&"first")
	var rival := RealmSpatialIndex.new(&"second")
	var stack := _bounds(116, 115, 260, 260)
	for slot: int in 73:
		assert_true(index.register(StringName("actor-%d" % slot), 0, stack))
	assert_true(index.register(&"actor-0", 1, stack))
	assert_false(index.register(&"actor-0", 1, stack))
	assert_true(rival.register(&"rival-0", 0, stack))
	var seam := _bounds(127, 127, 256, 256)
	var conflicts := _keys(index.query(seam))
	assert_eq(conflicts.size(), 74)
	assert_has(conflicts, "actor-0/0")
	assert_has(conflicts, "actor-0/1")
	assert_eq(_keys(rival.query(seam)), ["rival-0/0"])
	assert_false(conflicts.has("rival-0/0"))


func test_displacement_and_removal_are_visible_synchronously_across_a_seam() -> void:
	var index := RealmSpatialIndex.new(&"first")
	var before := _bounds(-129, -2, -128, 0)
	var after := _bounds(128, -2, 129, 0)
	assert_true(index.register(&"wall", 0, before))
	var old_observation := index.query(before)
	assert_true(index.move(&"wall", 0, after))
	assert_eq(_keys(index.query(before)), [])
	assert_eq(_keys(index.query(after)), ["wall/0"])
	assert_eq(old_observation.proxies[0].bounds.west, -129.0)
	assert_false(index.move(&"wall", 0, null))
	assert_eq(_keys(index.query(after)), ["wall/0"])
	assert_true(index.remove(&"wall", 0))
	assert_eq(_keys(index.query(after)), [])


func test_large_bounds_and_queries_do_not_truncate_the_candidate_set() -> void:
	var index := RealmSpatialIndex.new(&"first")
	var long_wall := _bounds(-120_000, 64, 120_000, 64)
	assert_true(index.register(&"long", 0, long_wall))
	assert_true(index.register(&"far-point", 0, _bounds(110_310, 64, 110_310, 64)))
	assert_eq(_keys(index.query(_bounds(110_310, 64, 110_310, 64))), ["far-point/0", "long/0"])
	assert_eq(_keys(index.query(long_wall)), ["far-point/0", "long/0"])
	assert_true(index.move(&"long", 0, _bounds(-500, 0, -500, 0)))
	assert_eq(_keys(index.query(long_wall)), ["far-point/0"])


func test_negative_cells_and_far_thin_bounds_preserve_scalar_precision() -> void:
	var index := RealmSpatialIndex.new(&"far")
	var far := 1_000_000_000_000.0
	var x := far + 0.002
	var edge := _bounds(x, -far, x, -far)
	assert_true(index.register(&"east", 0, edge))
	assert_true(index.register(&"west", 0, _bounds(-x, far, -x, far)))
	assert_eq(_keys(index.query(_bounds(far, -far, far + 0.001, -far))), [])
	assert_eq(_keys(index.query(_bounds(far, -far, x, -far))), ["east/0"])
	assert_eq(_keys(index.query(_bounds(-x, far, -far, far))), ["west/0"])
	var area := RealmBounds.from_sweep(far, -far, far, -far, 0.002)
	assert_true(area.east > x, "The rounded sweep expands outward at the boundary")
	assert_eq(_keys(index.query(area)), ["east/0"])
	assert_null(index.query(_bounds(1e20, 0, 1e20, 0)))
	assert_null(RealmBounds.from_edges(NAN, 0, 1, 1))
	assert_null(RealmBounds.from_edges(2, 0, 1, 1))


func test_grid_candidates_match_an_independent_edge_check() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70042
	var index := RealmSpatialIndex.new(&"oracle")
	var source: Array[Array] = []
	for id: int in 100:
		var x := rng.randi_range(-600, 600)
		var y := rng.randi_range(-600, 600)
		var width := rng.randi_range(0, 320)
		var height := rng.randi_range(0, 320)
		source.append([x, y, x + width, y + height])
		assert_true(index.register(StringName(str(id)), 0, _bounds(x, y, x + width, y + height)))
	for _case: int in 30:
		var x := rng.randi_range(-650, 750)
		var y := rng.randi_range(-650, 750)
		var expected: Array[String] = []
		for id: int in source.size():
			var candidate: Array = source[id]
			var separated: bool = (candidate[2] < x or candidate[0] > x + 173
				or candidate[3] < y or candidate[1] > y + 123)
			if not separated:
				expected.append("%d/0" % id)
		expected.sort()
		assert_eq(_keys(index.query(_bounds(x, y, x + 173, y + 123))), expected)


func _keys(result: RealmSpatialIndex.CandidateSet) -> Array[String]:
	var output: Array[String] = []
	for proxy: RealmSpatialIndex.Proxy in result.proxies:
		output.append("%s/%d" % [proxy.entity, proxy.shape])
	output.sort()
	return output


func _bounds(x0: float, y0: float, x1: float, y1: float) -> RealmBounds:
	return RealmBounds.from_edges(x0, y0, x1, y1)
