extends SceneTree
## Deterministic crowded-query witness for the native realm geometry owner.

const CROWD_SIZE := 128
const QUERIES := 500
const CONTACTS := 1
const OTHER_CATEGORY := 2
const REALM := &"outer"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 1 or arguments.size() > 2 or (arguments.size() == 2 and arguments[1] != "certified"):
		quit(2)
		return
	var certified := arguments.size() == 2
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
		if not owner.add_circle(id, 0, center, 0.5, category):
			quit(2)
			return
	var elapsed: Array[int] = []
	var contact_count := 0
	for iteration: int in QUERIES:
		var relocated := ids[1] if iteration % 2 == 0 else ids[2]
		var restored := ids[2] if iteration % 2 == 0 else ids[1]
		if not owner.commit_circle_pose(relocated, 0, off_path) or not owner.commit_circle_pose(restored, 0, center):
			quit(2)
			return
		var start_us := Time.get_ticks_usec()
		var batch := owner.certify_circle_sweep(REALM, start, finish, 0.5, CONTACTS) if certified else (
			owner.sweep_circle(REALM, start, finish, 0.5, CONTACTS))
		elapsed.append(Time.get_ticks_usec() - start_us)
		if not _matches_reference(batch, ids, relocated, certified):
			printerr("Crowded query mismatch at iteration %d" % iteration)
			quit(1)
			return
		contact_count += batch.contacts.size()
	elapsed.sort()
	var report := {
		"queries": QUERIES, "coincident_at_start": CROWD_SIZE, "accepted_contacts": contact_count, "certified": certified,
		"timing_us": {"p50": elapsed[ceili(QUERIES * 0.50) - 1], "p95": elapsed[ceili(QUERIES * 0.95) - 1],
			"p99": elapsed[ceili(QUERIES * 0.99) - 1], "max": elapsed.back()},
	}
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify(report))
	quit(0)


func _matches_reference(batch: RealmGeometry.SweepCandidates, ids: Array[StringName], relocated: StringName,
		certified: bool) -> bool:
	if batch == null or not batch.unresolved.is_empty():
		return false
	var unique: Dictionary[StringName, bool] = {}
	# Center at zero, expanded radius one and a 512-unit straight sweep.
	const EXACT_TOI := 255.0 / 512.0
	for contact: RealmGeometry.Contact in batch.contacts:
		if contact.shape != 0 or unique.has(contact.entity):
			return false
		if certified:
			if contact.proof.earliest > EXACT_TOI or contact.proof.latest < EXACT_TOI:
				return false
		elif contact.time != EXACT_TOI:
			return false
		unique[contact.entity] = true
	for index: int in ids.size():
		if unique.has(ids[index]) != (index % 4 != 0 and ids[index] != relocated):
			return false
	return unique.size() == 95
