extends SceneTree
## Scripted radius checks through realized seams with the production spatial owner.

const SEEDS: Array[int] = [-9223372036854775807 - 1, -17, 0, 11, 65, 9223372036854775807]
const SEATS: Array[StringName] = [&"walker", &"observer"]
const WALKER_CATEGORY := 2
const STEPS_PER_MODULE := 8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var rows: Array[Dictionary] = []
	for seed: int in SEEDS:
		var overworld := WorldTopology.generate(seed)
		var seam: Array[StringName] = overworld.manifest()["shortcut"]
		var world := WorldExploration.create(overworld, SEATS)
		if world == null or not world.open_shortcut():
			_fail(seed, WorldTopology.OVERWORLD)
			return
		var reopened := WorldExploration.restore(world.checkpoint(), SEATS)
		var shortcut := _trace(overworld, reopened, seam[0], seam[1])
		if shortcut.is_empty() or shortcut["edges"] != 1:
			_fail(seed, WorldTopology.OVERWORLD)
			return
		rows.append(shortcut)
		for realm: StringName in WorldTopology.OPTIONAL_REALMS:
			var layout := WorldTopology.generate_optional(seed, realm)
			var witness := _trace(layout, WorldExploration.create(layout, SEATS),
				WorldTopology.ENTRY, WorldTopology.RETURN_EXIT)
			if witness.is_empty():
				_fail(seed, realm)
				return
			rows.append(witness)
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(rows, "	", true, true))
	print("WP16_ROUTE_PROBE ", rows.size(), " native traversals")
	quit()


func _trace(layout: WorldTopology, world: WorldExploration, first: StringName, last: StringName) -> Dictionary:
	if world == null:
		return {}
	var graph_path := world.route(first, last)
	if graph_path.size() < 2:
		return {}
	var actor := &"walker"
	var spatial := world.geometry()
	var initial := layout.center(first)
	if not spatial.add_circle(actor, 0, initial, WorldExploration.STARTER_RADIUS, WALKER_CATEGORY):
		return {}
	if not world.observe_seat(actor, layout.realm, initial):
		return {}
	var steps := 0
	for index: int in range(1, graph_path.size()):
		var a := layout.center(graph_path[index - 1])
		var b := layout.center(graph_path[index])
		for substep: int in range(1, STEPS_PER_MODULE + 1):
			var t := float(substep) / STEPS_PER_MODULE
			var target := RealmSweep.Point.new(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))
			var trip := spatial.displace_circle(actor, 0, target, WorldExploration.BLOCKER)
			if trip == null or trip.finish.x != target.x or trip.finish.y != target.y:
				return {}
			if not world.observe_seat(actor, layout.realm, trip.finish):
				return {}
			steps += 1
	var comparison := world.view(&"observer")
	var visible: Array = world.view(actor)["visible"]
	var explored: Array = comparison["explored"]
	if visible.size() != 1 or not comparison["visible"].is_empty() or explored.size() != steps + 1:
		return {}
	var serialized := var_to_bytes(world.checkpoint())
	var restored := WorldExploration.restore(bytes_to_var(serialized), SEATS)
	if restored == null or not restored.view(actor)["visible"].is_empty() or restored.view(actor)["explored"] != explored:
		return {}
	return {"seed": str(layout.seed), "realm": layout.realm, "path": graph_path, "edges": graph_path.size() - 1,
		"steps": steps, "explored_cells": explored.size(), "manifest_sha256": JSON.stringify(layout.manifest()).sha256_text()}


func _fail(seed: int, realm: StringName) -> void:
	printerr("Starter route, fog or restore failed at seed %d in %s" % [seed, realm])
	quit(1)
