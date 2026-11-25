extends SceneTree
## Deterministic crowded-query witness for the native realm geometry owner.

const CROWD_SIZE := 128
const QUERIES := 500
const NEAR_QUERIES := 100
const FIRST_NEAR := 5
const LAST_NEAR := 20
const CONTACTS := 1
const OTHER_CATEGORY := 2
const REALM := &"outer"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode := arguments[1] if arguments.size() == 2 else "estimate"
	if arguments.is_empty() or arguments.size() > 2 or mode not in ["estimate", "certified", "near"]:
		quit(2)
		return
	var certified := mode != "estimate"
	var near := mode == "near"
	var query_count := NEAR_QUERIES if near else QUERIES
	var owner := RealmGeometry.new(REALM)
	var start := RealmSweep.Point.new(-256.0, 0.0)
	var finish := RealmSweep.Point.new(256.0, 0.0)
	var center := RealmSweep.Point.new(0.0, 0.0)
	var off_path := RealmSweep.Point.new(0.0, 300.0)
	var ids: Array[StringName] = []
	for index: int in CROWD_SIZE:
		var id := StringName("body_%d" % index)
		ids.append(id)
		var category := OTHER_CATEGORY if index % 4 == 0 else CONTACTS
		var pose := _near_pose(index) if near and _is_near(index) else center
		if not owner.add_circle(id, 0, pose, 0.5, category):
			quit(2)
			return
	var elapsed: Array[int] = []
	var ordering_elapsed: Array[int] = []
	var contact_count := 0
	for iteration: int in query_count:
		var relocated := ids[1] if iteration % 2 == 0 else ids[2]
		var restored := ids[2] if iteration % 2 == 0 else ids[1]
		if not owner.commit_circle_pose(relocated, 0, off_path) or not owner.commit_circle_pose(restored, 0, center):
			quit(2)
			return
		var start_us := Time.get_ticks_usec()
		var batch := owner.certify_circle_sweep(REALM, start, finish, 0.5, CONTACTS) if certified else (
			owner.sweep_circle(REALM, start, finish, 0.5, CONTACTS))
		elapsed.append(Time.get_ticks_usec() - start_us)
		if not _matches_reference(batch, ids, relocated, certified, near):
			printerr("Crowded query mismatch at iteration %d" % iteration)
			quit(1)
			return
		if near:
			var before_ordering := Time.get_ticks_usec()
			if not _matches_near_order(batch, ids):
				printerr("Crowded near-contact order mismatch at iteration %d" % iteration)
				quit(1)
				return
			ordering_elapsed.append(Time.get_ticks_usec() - before_ordering)
		contact_count += batch.contacts.size()
	var report := {
		"queries": query_count, "registered_collocated_or_clustered": CROWD_SIZE,
		"accepted_contacts": contact_count, "mode": mode, "timing_us": _percentiles(elapsed),
	}
	if near:
		report["near_order_timing_us"] = _percentiles(ordering_elapsed)
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0)


func _matches_reference(batch: RealmGeometry.SweepCandidates, ids: Array[StringName], relocated: StringName,
		certified: bool, near: bool) -> bool:
	if batch == null or not batch.unresolved.is_empty():
		return false
	var unique: Dictionary[StringName, bool] = {}
	# Center at zero, expanded radius one and a 512-unit straight sweep.
	const EXACT_TOI := 255.0 / 512.0
	for contact: RealmGeometry.Contact in batch.contacts:
		if contact.shape != 0 or unique.has(contact.entity):
			return false
		var index := ids.find(contact.entity)
		if near and _is_near(index):
			var position := _near_pose(index)
			var expected := (position.x + 256.0 - sqrt(1.0 - position.y * position.y)) / 512.0
			if expected < contact.proof.earliest or expected > contact.proof.latest:
				return false
		elif certified:
			if contact.proof.earliest > EXACT_TOI or contact.proof.latest < EXACT_TOI:
				return false
		elif contact.time != EXACT_TOI:
			return false
		unique[contact.entity] = true
	for index: int in ids.size():
		if unique.has(ids[index]) != (index % 4 != 0 and ids[index] != relocated):
			return false
	return unique.size() == 95


static func _matches_near_order(batch: RealmGeometry.SweepCandidates, ids: Array[StringName]) -> bool:
	var proofs: Dictionary[StringName, RealmCircleTime.Contact] = {}
	for contact: RealmGeometry.Contact in batch.contacts:
		proofs[contact.entity] = contact.proof
	var previous: RealmCircleTime.Contact
	for index: int in range(FIRST_NEAR, LAST_NEAR):
		if index % 4 == 0:
			continue
		var next: RealmCircleTime.Contact = proofs.get(ids[index])
		if next == null or (previous != null and previous.order_against(next) != RealmCircleTime.Order.BEFORE):
			return false
		previous = next
	return true


static func _is_near(index: int) -> bool:
	return index >= FIRST_NEAR and index < LAST_NEAR


static func _near_pose(index: int) -> RealmSweep.Point:
	return RealmSweep.Point.new(float(index) / float(1 << 52), 0.25)


static func _percentiles(samples: Array[int]) -> Dictionary:
	samples.sort()
	var size := samples.size()
	return {"p50": samples[ceili(size * 0.50) - 1], "p95": samples[ceili(size * 0.95) - 1],
		"p99": samples[ceili(size * 0.99) - 1], "max": samples.back()}
