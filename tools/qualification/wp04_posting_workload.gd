extends SceneTree
## Mixed-rate, multi-origin numeric timing fixture. Times exclude evidence encoding.

const RATES: Array[Vector2i] = [Vector2i(1, 3), Vector2i(2, 9), Vector2i(1, 7), Vector2i(7, 13), Vector2i(3, 17)]
const BATCHES := 1000
const EVENTS_PER_BATCH := 100
const MICRO := 1000000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var baseline := _baseline()
	var measured := _native()
	if measured.is_empty() or measured["frontiers"] != baseline["frontiers"]:
		print("WP04_WORKLOAD_FAIL native outcomes disagree with the raw grid baseline")
		quit(1)
		return
	baseline.erase("frontiers")
	measured["baseline"] = baseline
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(measured))
	file.close()
	print("WP04_WORKLOAD ", BATCHES * EVENTS_PER_BATCH, " native postings")
	quit(0)


func _native() -> Dictionary:
	var rates: Array[QuantityFraction] = []
	for rate: Vector2i in RATES:
		rates.append(QuantityFraction.create(Quantity.from_count(rate.x), Quantity.from_count(rate.y)))
	var latencies := PackedInt64Array()
	var frontiers: Array[Array] = []
	var compact_events := 0
	var max_cursor_bytes := 0
	var max_error_bytes := 0
	var peak_objects := 0.0
	for batch: int in BATCHES:
		var hp := Quantity.from_count(100 + batch % 7)
		var errors := QuantityErrorBounds.new()
		var cursor: QuantityRateCursor
		var active: QuantityFraction
		var by_origin: Array[int] = [0, 0, 0, 0]
		var started := Time.get_ticks_usec()
		for event: int in EVENTS_PER_BATCH:
			if event % 3 == 0:
				active = rates[_rate_index(batch, event)]
				cursor = QuantityRateCursor.create(active.numerator, active.divisor)
			var nominal := cursor.next_debit()
			var hit := QuantityThresholdDebit.resolve(hp, errors, active, nominal)
			if hit == null or hit.remaining.sign_value <= 0:
				print("WP04_WORKLOAD unexpected fault or terminal branch at ", batch, "/", event)
				return {}
			hp = hit.remaining
			errors = hit.error
			compact_events += int(not hp.uses_limbs and not hit.debit.uses_limbs)
			by_origin[event % 4] += hit.debit.count_at_scale(6).magnitude_text().to_int()
		latencies.append(Time.get_ticks_usec() - started)
		frontiers.append([hp.count_at_scale(6).magnitude_text(), by_origin])
		max_cursor_bytes = maxi(max_cursor_bytes, cursor.snapshot().size())
		max_error_bytes = maxi(max_error_bytes, errors.snapshot().size())
		peak_objects = maxf(peak_objects, Performance.get_monitor(Performance.OBJECT_COUNT))
	return {"frontiers": frontiers, "timing_us_per_100": _summary(latencies),
		"represented_compact_events": compact_events, "max_cursor_bytes": max_cursor_bytes,
		"max_error_checkpoint_bytes": max_error_bytes, "sampled_global_objects": peak_objects}


func _baseline() -> Dictionary:
	var latencies := PackedInt64Array()
	var frontiers: Array[Array] = []
	for batch: int in BATCHES:
		var hp := (100 + batch % 7) * MICRO
		var rate := Vector2i.ZERO
		var posted := 0
		var by_origin: Array[int] = [0, 0, 0, 0]
		var started := Time.get_ticks_usec()
		for event: int in EVENTS_PER_BATCH:
			var occurrence := event % 3 + 1
			if occurrence == 1:
				rate = RATES[_rate_index(batch, event)]
				posted = 0
			var scaled := rate.x * MICRO * occurrence
			@warning_ignore("integer_division")
			var cumulative := scaled / rate.y
			var remainder := scaled % rate.y
			if remainder * 2 > rate.y or (remainder * 2 == rate.y and cumulative % 2 == 1):
				cumulative += 1
			var debit := cumulative - posted
			hp -= debit
			by_origin[event % 4] += debit
			posted = cumulative
		latencies.append(Time.get_ticks_usec() - started)
		frontiers.append([str(hp), by_origin])
	return {"frontiers": frontiers, "timing_us_per_100": _summary(latencies)}


static func _rate_index(batch: int, event: int) -> int:
	@warning_ignore("integer_division")
	return (batch + event / 3) % RATES.size()


static func _summary(samples: PackedInt64Array) -> Dictionary:
	samples.sort()
	var p50 := ceili(samples.size() * 0.50) - 1
	var p95 := ceili(samples.size() * 0.95) - 1
	var p99 := ceili(samples.size() * 0.99) - 1
	return {"p50": samples[p50], "p95": samples[p95], "p99": samples[p99], "max": samples[-1]}
