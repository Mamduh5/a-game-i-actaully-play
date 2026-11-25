extends SceneTree
## Disposable scene-independent scalar sweep cross-check.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var input := FileAccess.open(args[0], FileAccess.READ)
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if input == null or output == null:
		quit(2)
		return
	var cases: Variant = JSON.parse_string(input.get_as_text())
	if not cases is Array:
		quit(2)
		return
	var results: Array[Dictionary] = []
	var contacts: Array[RealmCircleTime.Contact] = []
	var proof := RealmCircleTime.new()
	for row: Dictionary in cases:
		var start := _point(row["start"])
		var finish := _point(row["finish"])
		var a := _point(row["a"])
		var b := _point(row["b"])
		var radius: float = row["radius"]
		var time: float
		var checked: RealmCircleTime.Contact
		if row["kind"] == "segment":
			time = RealmSweep.circle_segment(start, finish, radius, a, b)
			checked = proof.measure_segment(start, finish, radius, a, b)
		else:
			time = RealmSweep.moving_circles(start, finish, radius, a, b, row["other_radius"])
			checked = proof.measure(start, finish, radius, a, b, row["other_radius"])
		if not is_finite(time):
			quit(1)
			return
		var result := {"time": time}
		if checked != null:
			result["proof"] = {"outcome": checked.outcome, "lower": checked.earliest, "upper": checked.latest}
		if row.has("compare_to"):
			result["order"] = checked.order_against(contacts[int(row["compare_to"])])
		contacts.append(checked)
		results.append(result)
	output.store_string(JSON.stringify(results, "", true, true))
	output.close()
	print("WP07_SWEEP_CASES ", results.size())
	quit(0)


func _point(value: Array) -> RealmSweep.Point:
	return RealmSweep.Point.new(value[0], value[1])
