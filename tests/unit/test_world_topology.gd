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
	var blocker_revision := world.geometry().compatible_revision(WorldExploration.BLOCKER)
	assert_true(world.geometry().add_circle(&"host", 0, layout.center(ends[0]), 14.0, 2))
	assert_eq(world.geometry().compatible_revision(WorldExploration.BLOCKER), blocker_revision)
	assert_true(world.open_shortcut())
	assert_gt(world.geometry().compatible_revision(WorldExploration.BLOCKER), blocker_revision)
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


func test_opposing_impulses_use_directional_attenuated_ownership_and_relative_speed() -> void:
	var mover := WorldMomentum.create(2.0, 0.5)
	var receiver := WorldMomentum.create(2.0, 0.0)
	var cause := CombatOrigin.new()
	cause.owner = &"first"
	cause.activation = 1
	cause.committed_at = CombatInstant.at_tick(1)
	var opposing := cause.copy()
	opposing.owner = &"opposing"
	assert_true(mover.apply_impulse(RealmSweep.Point.new(20, 0), cause))
	assert_true(mover.apply_impulse(RealmSweep.Point.new(-8, 0), opposing))
	assert_true(mover.apply_impulse(RealmSweep.Point.new(16, 0), null, &"landslide"))
	assert_false(mover.apply_impulse(RealmSweep.Point.new(20, 0), cause))
	assert_true(mover.attenuate(0.5))
	assert_eq(mover.velocity().x, 3.5)
	assert_true(receiver.apply_impulse(RealmSweep.Point.new(-2, 0), null, &"counter_motion"))
	var toward := RealmSweep.Point.new(1, 0)
	var first := mover.contact(&"receiver", 0, toward, 0.1, receiver)
	assert_not_null(first)
	if first == null:
		return
	assert_eq(first.approach_speed, 4.5)
	assert_eq(first.strength, 10.125)
	assert_eq(first.primary.owner, cause.owner)
	assert_eq(first.participants.size(), 1)
	assert_null(mover.contact(&"receiver", 0, toward, 0.1, receiver))
	assert_true(mover.separate(&"receiver", 0))
	assert_true(receiver.apply_impulse(RealmSweep.Point.new(-7, 0), null, &"crystal_burst"))
	var next := mover.contact(&"receiver", 0, toward, 0.1, receiver)
	assert_not_null(next)
	if next != null:
		assert_null(next.primary)
		assert_eq(next.neutral_cause, &"crystal_burst")
		assert_eq(next.participants[0].owner, cause.owner)


func test_world_push_reports_one_impact_until_the_solid_leaves_the_wall() -> void:
	var layout := WorldTopology.generate_optional(7, &"silent_garden")
	var world := WorldExploration.create(layout, [&"host"])
	var entry := layout.center(WorldTopology.ENTRY)
	var direction := -1.0 if entry.y < WorldTopology.MODULE_SIZE else 1.0
	var start := RealmSweep.Point.new(entry.x, entry.y + direction * 86.0)
	assert_true(world.place_route_solid(&"stone", start, 10.0))
	var momentum := WorldMomentum.create(2.0, 0.0)
	var cause := CombatOrigin.new()
	cause.owner = &"host"
	cause.activation = 1
	cause.committed_at = CombatInstant.at_tick(1)
	assert_true(momentum.apply_impulse(RealmSweep.Point.new(0, direction * 120), cause))
	var into_wall := world.push_route_solid(&"stone", momentum, 1.0, 0.1, 0.25)
	assert_not_null(into_wall)
	if into_wall == null:
		return
	assert_false(into_wall.route_limited)
	assert_eq(into_wall.impacts.size(), 1)
	if into_wall.impacts.size() == 1:
		assert_eq(into_wall.impacts[0].impact.primary.owner, &"host")
		assert_eq(into_wall.impacts[0].impact.strength, 3600.0)
	var still_touching := world.push_route_solid(&"stone", momentum, 1.0, 0.1, 0.25)
	assert_not_null(still_touching)
	if still_touching != null:
		assert_true(still_touching.impacts.is_empty())
	assert_true(momentum.attenuate(0.0))
	assert_true(momentum.apply_impulse(RealmSweep.Point.new(0, -direction * 40), null, &"drift"))
	var away := world.push_route_solid(&"stone", momentum, 1.0, 0.1, 0.25)
	assert_not_null(away)
	if away != null:
		assert_true(away.impacts.is_empty())
	assert_true(momentum.attenuate(0.0))
	assert_true(momentum.apply_impulse(RealmSweep.Point.new(0, direction * 120), null, &"fall"))
	var struck_again := world.push_route_solid(&"stone", momentum, 1.0, 0.1, 0.25)
	assert_not_null(struck_again)
	if struck_again != null:
		assert_eq(struck_again.impacts.size(), 1)
		if struck_again.impacts.size() == 1:
			assert_null(struck_again.impacts[0].impact.primary)
			assert_eq(struck_again.impacts[0].impact.neutral_cause, &"fall")


func test_shortcut_interaction_uses_committed_pose_reach_and_clear_sight() -> void:
	var layout := WorldTopology.generate(193)
	var world := WorldExploration.create(layout, [&"host"])
	var ends: Array[StringName] = layout.manifest()["shortcut"]
	var first := layout.center(ends[0])
	var last := layout.center(ends[1])
	var actor := &"host"
	var realm := layout.realm
	assert_true(world.geometry().add_circle(actor, 0, first, 14.0, 2))
	var press := PlayerCommand.new(PlayerCommand.INTERACT)
	assert_false(world.interact_shortcut(press, realm, actor, 0, 30.0))
	var near := RealmSweep.Point.new(lerpf(first.x, last.x, 0.40625), lerpf(first.y, last.y, 0.40625))
	var shield := RealmSweep.Point.new(lerpf(first.x, last.x, 0.453125), lerpf(first.y, last.y, 0.453125))
	assert_true(world.geometry().commit_circle_pose(actor, 0, near))
	assert_false(world.interact_shortcut(PlayerCommand.new(PlayerCommand.MANUAL), realm, actor, 0, 30.0))
	assert_true(world.place_route_solid(&"shield", shield, 4.0))
	assert_false(world.interact_shortcut(press, realm, actor, 0, 30.0))
	assert_true(world.remove_route_solid(&"shield"))
	assert_false(world.interact_shortcut(press, &"unrelated", actor, 0, 30.0))
	assert_true(world.interact_shortcut(press, realm, actor, 0, 30.0))
	assert_false(world.interact_shortcut(press, realm, actor, 0, 30.0))
	assert_eq(_contacts(world, first, last), 0)


func test_pressure_warning_samples_real_occupants_and_preserves_faction_or_neutral_cause() -> void:
	var layout := WorldTopology.generate_optional(7, &"silent_garden")
	var world := WorldExploration.create(layout, [&"host"])
	var geometry := world.geometry()
	var center := layout.center(WorldTopology.ENTRY)
	var plate := RealmSweep.Point.new(center.x - 60.0, center.y)
	var hazard := WorldPressureHazard.create(layout.realm, &"pressure", plate, 10.0, center, 20.0, 3, 2.0, 2)
	assert_not_null(hazard)
	assert_true(geometry.add_circle(&"stone", 0, plate, 5.0, 4))
	assert_true(geometry.add_circle(&"creature", 0, center, 14.0, 2))
	assert_true(geometry.add_circle(&"protected", 0, center, 14.0, 4))
	assert_true(geometry.add_circle(&"incoming", 0, plate, 5.0, 2))
	assert_true(geometry.stage_circle_motion(&"incoming", 0, center))
	var occupant := WorldPressureHazard.Occupant.new()
	occupant.actor = &"stone"
	occupant.weight = 3.0
	occupant.cause = CombatOrigin.new()
	occupant.cause.provenance = CombatOrigin.Provenance.SPAWN
	occupant.cause.owner = &"ironhide"
	occupant.cause.activation = 1
	occupant.cause.committed_at = CombatInstant.at_tick(1)
	assert_eq(hazard.sample(geometry, CombatInstant.at_tick(1), [occupant]), WorldPressureHazard.SampleResult.WARNED)
	var warning := hazard.warning_snapshot()
	assert_eq(warning.due.tick, 4)
	assert_false(world.can_escape_warning(warning, &"creature", 0, 10.0))
	assert_true(world.can_escape_warning(warning, &"creature", 0, 60.0))
	assert_null(hazard.take_strike(geometry, CombatInstant.at_tick(3)))
	assert_false(hazard.warning_snapshot().cause.owner.is_empty())
	var strike := hazard.take_strike(geometry, CombatInstant.at_tick(4))
	assert_not_null(strike)
	if strike == null:
		return
	assert_eq(strike.warning.cause.owner, &"ironhide")
	assert_eq(strike.warning.cause.provenance, CombatOrigin.Provenance.SPAWN)
	assert_eq(strike.contacts.size(), 1)
	if strike.contacts.size() == 1:
		assert_eq(strike.contacts[0].entity, &"creature")
	assert_null(hazard.take_strike(geometry, CombatInstant.at_tick(4)))
	assert_eq(hazard.sample(geometry, CombatInstant.at_tick(4), [occupant]), WorldPressureHazard.SampleResult.UNCHANGED)
	assert_eq(hazard.sample(geometry, CombatInstant.at_tick(5), []), WorldPressureHazard.SampleResult.UNCHANGED)
	occupant.cause = null
	assert_eq(hazard.sample(geometry, CombatInstant.at_tick(6), [occupant]), WorldPressureHazard.SampleResult.WARNED)
	assert_null(hazard.warning_snapshot().cause)
	assert_eq(hazard.sample(geometry, CombatInstant.at_tick(6), []), WorldPressureHazard.SampleResult.INVALID)


func test_passive_transfer_keeps_actual_contact_and_source_without_added_energy() -> void:
	var layout := WorldTopology.generate_optional(-4, &"inverted_archive")
	var world := WorldExploration.create(layout, [&"host"])
	var center := layout.center(WorldTopology.ENTRY)
	var start := RealmSweep.Point.new(center.x - 40, center.y - 60)
	var receiver_start := RealmSweep.Point.new(center.x - 12, center.y - 60)
	assert_true(world.place_route_solid(&"mover", start, 5.0))
	assert_true(world.place_route_solid(&"receiver", receiver_start, 5.0))
	var mover := WorldMomentum.create(2.0, 0.0)
	var receiver := WorldMomentum.create(2.0, 0.0)
	var origin := CombatOrigin.new()
	origin.owner = &"instigator"
	origin.activation = 1
	origin.committed_at = CombatInstant.at_tick(1)
	assert_true(mover.apply_impulse(RealmSweep.Point.new(60, 0), origin))
	var hit := world.push_route_solid(&"mover", mover, 1.0, 0.1, 0.25, {&"receiver": receiver}, 1.0)
	assert_not_null(hit)
	if hit == null:
		return
	assert_eq(hit.impacts.size(), 1)
	if hit.impacts.size() != 1:
		return
	assert_true(hit.impacts[0].transferred)
	assert_eq(hit.impacts[0].impact.primary.owner, &"instigator")
	assert_eq(hit.impacts[0].impact.strength, 450.0)
	assert_eq(mover.velocity().x, 0.0)
	assert_eq(receiver.velocity().x, 30.0)
	assert_false(mover.transfer(hit.impacts[0].impact, &"mover", 0, 1.0))
	var moved := world.push_route_solid(&"receiver", receiver, 0.5, 0.1, 0.25)
	assert_not_null(moved)
	if moved != null:
		assert_eq(moved.motion.finish.x, receiver_start.x + 15.0)


func test_partial_durability_reopens_and_faction_destruction_releases_its_collider_once() -> void:
	var layout := WorldTopology.generate_optional(34, &"silent_garden")
	var world := WorldExploration.create(layout, [&"host"])
	var entry := layout.center(WorldTopology.ENTRY)
	var center := RealmSweep.Point.new(entry.x + 50.0, entry.y + 40.0)
	assert_true(world.place_route_solid(&"crystal", center, 14.0, Quantity.from_count(5)))
	var start_revision := world.geometry().revision
	var paid := world.damage_route_solid(&"crystal", Quantity.from_count(2), null, &"quake")
	assert_not_null(paid)
	if paid != null:
		assert_false(paid.destroyed)
		assert_eq(paid.neutral_cause, &"quake")
		assert_eq(paid.remaining.native_at_scale(0), 3)
	assert_eq(world.geometry().revision, start_revision)
	var saved := world.checkpoint()
	var reopened := WorldExploration.restore(saved, [&"host"])
	assert_not_null(reopened)
	if reopened == null:
		return
	var cause := CombatOrigin.new()
	cause.owner = &"ironhide"
	cause.activation = 1
	cause.provenance = CombatOrigin.Provenance.SPAWN
	cause.committed_at = CombatInstant.at_tick(3)
	var destroyed := reopened.damage_route_solid(&"crystal", Quantity.from_count(200), cause)
	assert_not_null(destroyed)
	if destroyed == null:
		return
	assert_true(destroyed.destroyed)
	assert_eq(destroyed.paid.native_at_scale(0), 3)
	assert_eq(destroyed.origin.owner, &"ironhide")
	assert_eq(destroyed.origin.provenance, CombatOrigin.Provenance.SPAWN)
	assert_null(reopened.geometry().circle_center(&"crystal", 0))
	assert_null(reopened.damage_route_solid(&"crystal", Quantity.from_count(200), cause))


func test_phase_category_rejects_incompatible_shape_until_exposed() -> void:
	var geometry := RealmGeometry.new(&"realm")
	var start := RealmSweep.Point.new(0, 0)
	var finish := RealmSweep.Point.new(10, 0)
	assert_true(geometry.add_circle(&"burrower", 0, RealmSweep.Point.new(8, 0), 1.0, 4))
	assert_true(geometry.certify_circle_sweep(&"realm", start, finish, 0.0, 2).contacts.is_empty())
	assert_true(geometry.change_category(&"burrower", 0, 2))
	assert_eq(geometry.certify_circle_sweep(&"realm", start, finish, 0.0, 2).contacts.size(), 1)
