extends GutTest


func test_seeded_manifest_guarantees_all_anchors_and_connected_unique_tiles() -> void:
	var layouts: Dictionary[String, bool] = {}
	var announced_sites: Dictionary[StringName, bool] = {}
	for seed: int in range(-24, 24):
		var topology := WorldTopology.generate(seed)
		var manifest := topology.manifest()
		var origin: StringName = WorldTopology.ANCHORS[0]
		var occupied: Dictionary[Vector2i, bool] = {}
		var found: Dictionary[StringName, bool] = {}
		for module: Dictionary in manifest["modules"]:
			assert_false(occupied.has(module["cell"]), "Duplicate cell in seed %d" % seed)
			occupied[module["cell"]] = true
			found[module["id"]] = true
			announced_sites[module["id"]] = true
			assert_false(topology.route(origin, module["id"]).is_empty(), "Disconnected seed %d" % seed)
		for id: StringName in WorldTopology.ANCHORS:
			assert_true(found.has(id), "Missing anchor in seed %d" % seed)
		assert_true(found.has(WorldTopology.GATEWAY), "Missing gateway in seed %d" % seed)
		assert_eq(topology.manifest(), WorldTopology.generate(seed).manifest())
		layouts[str(manifest["modules"])] = true
	assert_gt(layouts.size(), 12)
	for region: Array in WorldTopology.OPTIONAL:
		for id: StringName in region:
			assert_true(announced_sites.has(id), "Variable site %s never appeared" % id)


func test_start_to_gateway_routes_fit_realized_starter_clearance() -> void:
	const STARTER_RADIUS := 14.0
	for seed: int in [-9223372036854775807 - 1, -17, 0, 11, 65, 9223372036854775807]:
		var topology := WorldTopology.generate(seed)
		var geometry := topology.realize(WorldExploration.BLOCKER)
		assert_not_null(geometry, "Generation failed in seed %d" % seed)
		if geometry == null:
			continue
		for id: StringName in WorldTopology.ANCHORS:
			var route := topology.route(id, WorldTopology.GATEWAY)
			assert_gt(route.size(), 1)
			for index: int in range(1, route.size()):
				var proof := geometry.certify_circle_sweep(WorldTopology.OVERWORLD, topology.center(route[index - 1]),
					topology.center(route[index]), STARTER_RADIUS, WorldExploration.BLOCKER)
				assert_not_null(proof)
				if proof != null:
					assert_true(proof.unresolved.is_empty())
					assert_true(proof.contacts.is_empty(), "Blocked route in seed %d" % seed)


func test_reopened_module_preserves_shortcut_and_shared_exploration_without_visibility_leak() -> void:
	var topology := WorldTopology.generate(193)
	var party: Array[StringName] = [&"a", &"b"]
	var world := WorldExploration.create(topology, party)
	var seam: Array[StringName] = topology.manifest()["shortcut"]
	var first := topology.center(seam[0])
	var second := topology.center(seam[1])
	assert_gt(world.route(seam[0], seam[1]).size(), 2)
	assert_eq(_contacts(world, first, second), 1)
	assert_true(world.observe_seat(&"a", WorldTopology.OVERWORLD, first))
	assert_false(world.observe_seat(&"projectile", WorldTopology.OVERWORLD, second))
	assert_false(world.observe_seat(&"npc", WorldTopology.OVERWORLD, second))
	assert_true(world.view(&"b")["visible"].is_empty())
	assert_eq(world.view(&"b")["explored"].size(), 1)
	assert_true(world.observe_seat(&"b", WorldTopology.OVERWORLD, second))
	assert_false(world.observe_seat(&"b", &"inverted_archive", second))
	assert_true(world.view(&"b")["visible"].is_empty())
	assert_eq(world.view(&"a")["explored"].size(), 2)
	assert_true(world.open_shortcut())
	assert_false(world.open_shortcut())
	assert_eq(_contacts(world, first, second), 0)
	assert_eq(world.route(seam[0], seam[1]).size(), 2)
	var saved := world.checkpoint()
	var restored := WorldExploration.restore(saved, party)
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.checkpoint(), saved)
	assert_true(restored.view(&"a")["visible"].is_empty())
	assert_eq(restored.view(&"a")["explored"].size(), 2)
	assert_eq(_contacts(restored, first, second), 0)
	assert_false(restored.open_shortcut())

	var tampered := saved.duplicate(true)
	tampered["layout"]["modules"][0]["cell"] = Vector2i(999, 999)
	assert_null(WorldExploration.restore(tampered, party))
	tampered = saved.duplicate(true)
	tampered["explored"].append(Vector2i(999, 999))
	assert_null(WorldExploration.restore(tampered, party))


func test_optional_realm_reservations_have_independent_entry_exit_and_fog() -> void:
	var party: Array[StringName] = [&"host", &"guest"]
	for realm: StringName in WorldTopology.OPTIONAL_REALMS:
		for seed: int in [-23, 0, 981]:
			var layout := WorldTopology.generate_optional(seed, realm)
			assert_not_null(layout)
			assert_eq(layout.realm, realm)
			assert_eq(layout.route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT).size(), 4)
			var world := WorldExploration.create(layout, party)
			assert_not_null(world)
			if world == null:
				continue
			assert_eq(world.geometry().realm_id, realm)
			assert_false(layout.has_clearance(world.geometry(), WorldExploration.BLOCKER, 45.0))
			var entry := layout.center(WorldTopology.ENTRY)
			assert_false(world.observe_seat(&"host", WorldTopology.OVERWORLD, entry))
			assert_true(world.view(&"guest")["explored"].is_empty())
			assert_true(world.observe_seat(&"host", realm, entry))
			assert_true(world.view(&"guest")["visible"].is_empty())
			assert_eq(world.view(&"guest")["explored"].size(), 1)
			var saved := world.checkpoint()
			var restored := WorldExploration.restore(saved, party)
			assert_not_null(restored)
			if restored != null:
				assert_eq(restored.checkpoint(), saved)
				assert_true(restored.view(&"host")["visible"].is_empty())
				assert_eq(restored.geometry().realm_id, realm)
	assert_null(WorldTopology.generate_optional(0, &"unknown"))


func test_checkpoint_accepts_legacy_module_order_and_rejects_duplicate_rows() -> void:
	var layout := WorldTopology.generate(-7)
	var saved := layout.manifest()
	var previous_order: Array = saved["modules"]
	previous_order.reverse()
	var reopened := WorldTopology.restore(saved)
	assert_not_null(reopened)
	if reopened != null:
		assert_eq(reopened.manifest(), layout.manifest())
	previous_order[0] = previous_order[1]
	assert_null(WorldTopology.restore(saved))


static func _contacts(visit: WorldExploration, start: RealmSweep.Point, finish: RealmSweep.Point) -> int:
	var proof := visit.geometry().certify_circle_sweep(visit.geometry().realm_id, start, finish, 14.0,
		WorldExploration.BLOCKER)
	return proof.contacts.size() if proof != null and proof.unresolved.is_empty() else -1


func test_route_geometry_recertifies_the_shortcut_after_opening() -> void:
	var layout := WorldTopology.generate(193)
	var world := WorldExploration.create(layout, [&"host"])
	var ends: Array[StringName] = layout.manifest()["shortcut"]
	var before := world.physical_route(ends[0], ends[1])
	assert_gt(before.size(), 1)
	assert_true(world.open_shortcut())
	var after := world.physical_route(ends[0], ends[1])
	assert_gt(after.size(), 1)
	assert_lt(after.size(), before.size())
	for index: int in range(1, after.size()):
		assert_eq(_contacts(world, after[index - 1], after[index]), 0)
	assert_true(world.view(&"host")["explored"].is_empty())


func test_staged_obstacle_preserves_last_exit_and_removal_restores_shorter_physical_route() -> void:
	var layout := WorldTopology.generate_optional(34, &"silent_garden")
	var world := WorldExploration.create(layout, [&"host"])
	var modules := layout.route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
	var entry := layout.center(modules[0])
	var next := layout.center(modules[1])
	var dx := next.x - entry.x
	var dy := next.y - entry.y
	var seam := RealmSweep.Point.new(entry.x + dx * 0.5, entry.y + dy * 0.5)
	var inside := RealmSweep.Point.new(entry.x + dx * 0.25, entry.y + dy * 0.25)
	assert_true(world.place_route_solid(&"alternate_blocker", _alternate_seam(layout, modules[1]), 33.0))
	var base := world.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
	var initial := world.geometry().revision
	assert_gt(base.size(), 1)
	assert_false(world.place_route_solid(&"exit_blocker", seam, 33.0))
	assert_eq(world.geometry().revision, initial)
	assert_null(world.geometry().circle_center(&"exit_blocker", 0))
	assert_true(world.reserve_route_approach(&"body", inside))
	assert_false(world.place_route_solid(&"destructible", inside, 14.0))
	assert_eq(world.geometry().revision, initial)
	assert_true(world.release_route_approach(&"body"))
	assert_true(world.place_route_solid(&"destructible", inside, 14.0))
	assert_eq(world.geometry().revision, initial + 1)
	assert_eq(_contacts(world, entry, next), 1)
	var detour := world.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
	assert_gt(detour.size(), base.size())
	for index: int in range(1, detour.size()):
		assert_eq(_contacts(world, detour[index - 1], detour[index]), 0)
	var saved := world.checkpoint()
	var reopened := WorldExploration.restore(saved, [&"host"])
	assert_not_null(reopened)
	if reopened != null:
		assert_eq(reopened.checkpoint(), saved)
		assert_eq(reopened.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT).size(), detour.size())
	var invalid := saved.duplicate(true)
	invalid["solids"].append(invalid["solids"][0])
	assert_null(WorldExploration.restore(invalid, [&"host"]))
	assert_false(world.remove_route_solid(&"exit_blocker"))
	assert_true(world.remove_route_solid(&"destructible"))
	assert_eq(world.geometry().revision, initial + 2)
	assert_eq(_contacts(world, entry, next), 0)
	assert_eq(world.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT).size(), base.size())
	assert_true(world.view(&"host")["explored"].is_empty())


func test_moved_obstruction_clamps_before_the_last_exit_with_no_physical_hit() -> void:
	var layout := WorldTopology.generate_optional(-4, &"inverted_archive")
	var world := WorldExploration.create(layout, [&"host"])
	var path := layout.route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
	var entry := layout.center(path[0])
	var next := layout.center(path[1])
	var dx := next.x - entry.x
	var dy := next.y - entry.y
	var start := RealmSweep.Point.new(entry.x + dx * 0.2 - dy * 0.25, entry.y + dy * 0.2 + dx * 0.25)
	var seam := RealmSweep.Point.new(entry.x + dx * 0.5, entry.y + dy * 0.5)
	assert_true(world.place_route_solid(&"alternate_blocker", _alternate_seam(layout, path[1]), 33.0))
	var side_start := RealmSweep.Point.new(seam.x - (dx + dy) * 0.09375, seam.y + (dx - dy) * 0.09375)
	var side_end := RealmSweep.Point.new(seam.x + (dx - dy) * 0.09375, seam.y + (dx + dy) * 0.09375)
	assert_true(world.place_route_solid(&"small", side_start, 3.0))
	var crossing := world.move_route_solid(&"small", side_end)
	assert_not_null(crossing)
	if crossing != null:
		assert_false(crossing.route_limited)
		assert_eq(crossing.motion.finish.x, side_end.x)
		assert_eq(crossing.motion.finish.y, side_end.y)
	assert_true(world.remove_route_solid(&"small"))
	assert_true(world.place_route_solid(&"moved", start, 33.0))
	var before := world.geometry().revision
	var movement := world.move_route_solid(&"moved", seam)
	assert_not_null(movement)
	if movement == null:
		return
	assert_true(movement.route_limited)
	assert_true(movement.motion.stopped_by.is_empty())
	assert_gt(world.geometry().revision, before)
	assert_eq(world.geometry().revision, movement.motion.revision)
	var center := world.geometry().circle_center(&"moved", 0)
	assert_eq(center.x, movement.motion.finish.x)
	assert_eq(center.y, movement.motion.finish.y)
	assert_true(center.x != start.x or center.y != start.y)
	assert_true(center.x != seam.x or center.y != seam.y)
	assert_false(world.physical_route(WorldTopology.ENTRY, WorldTopology.RETURN_EXIT).is_empty())


static func _alternate_seam(layout: WorldTopology, main_neighbor: StringName) -> RealmSweep.Point:
	for module: Dictionary in layout.manifest()["modules"]:
		if module["id"] != WorldTopology.ENTRY:
			continue
		for neighbor: StringName in module["neighbors"]:
			if neighbor != main_neighbor:
				var entry := layout.center(WorldTopology.ENTRY)
				var next := layout.center(neighbor)
				return RealmSweep.Point.new((entry.x + next.x) * 0.5, (entry.y + next.y) * 0.5)
	return null
