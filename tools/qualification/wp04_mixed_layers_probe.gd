extends SceneTree

class Measurements:
	var durations := PackedInt64Array()
	var compact_count := 0
	var interval_count := 0
	var cursor_bytes := 0
	var error_bytes := 0
	var max_static_memory := 0.0

	func summary() -> Dictionary:
		durations.sort()
		var size := durations.size()
		return {"histories": size, "represented_compact_postings": compact_count,
			"interval_pool_postings": interval_count, "peak_cursor_bytes": cursor_bytes,
			"peak_error_checkpoint_bytes": error_bytes, "sampled_global_static_memory_bytes": max_static_memory,
			"native_us_per_history": {"p50": durations[ceili(size * 0.50) - 1],
				"p95": durations[ceili(size * 0.95) - 1], "p99": durations[ceili(size * 0.99) - 1],
				"max": durations[-1]}}

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		quit(2)
		return
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var output := FileAccess.open(arguments[1], FileAccess.WRITE)
	if not rows is Array or rows.is_empty() or output == null:
		quit(2)
		return
	var results: Array[Dictionary] = []
	var measured := Measurements.new()
	for row: Dictionary in rows:
		var result := _run(row, measured)
		if result.is_empty():
			quit(1)
			return
		results.append(result)
	output.store_string(JSON.stringify({"rows": results, "measurement": measured.summary()}))
	output.close()
	print("WP04_MIXED_LAYERS ", results.size())
	quit(0)


func _run(row: Dictionary, measured: Measurements) -> Dictionary:
	var barrier := QuantityLayerLedger.Pool.new(Quantity.from_count(100), QuantityErrorBounds.new())
	var hp := QuantityLayerLedger.Pool.new(Quantity.from_count(int(row["hp"])), QuantityErrorBounds.new())
	var second := QuantityLayerLedger.Pool.new(Quantity.from_count(1), QuantityErrorBounds.new())
	var receipts: Array[Array] = []
	var origins: Array[Quantity] = [Quantity.from_count(0), Quantity.from_count(0), Quantity.from_count(0)]
	var elapsed := 0
	for index: int in row["rates"].size():
		var before_cursor := Time.get_ticks_usec()
		var denominator := int(row["rates"][index])
		var raw := QuantityFraction.create(Quantity.from_count(10), Quantity.from_count(denominator))
		var cursor := QuantityRateCursor.create(raw.numerator, raw.divisor)
		elapsed += Time.get_ticks_usec() - before_cursor
		if cursor == null:
			return {}
		for occurrence: int in 3:
			var before_posting := Time.get_ticks_usec()
			var nominal := cursor.next_debit()
			var hit := QuantityLayerLedger.draft(raw, nominal, [barrier, second], hp, true)
			if hit == null or hit.layers[0].hostile_depletion or hit.hp.spent.sign_value != 0:
				return {}
			barrier = hit.layers[0].after
			var origin := (index + occurrence) % origins.size()
			origins[origin] = origins[origin].add(hit.layers[0].spent)
			elapsed += Time.get_ticks_usec() - before_posting
			measured.compact_count += int(not barrier.amount.uses_limbs and not hit.layers[0].spent.uses_limbs)
			measured.interval_count += int(not barrier.error.is_exact())
			receipts.append([origin, _wire(hit.layers[0].spent)])
			if occurrence == 0:
				var cursor_bytes := cursor.snapshot()
				var error_bytes := barrier.error.snapshot()
				measured.cursor_bytes = maxi(measured.cursor_bytes, cursor_bytes.size())
				measured.error_bytes = maxi(measured.error_bytes, error_bytes.size())
				cursor = QuantityRateCursor.restore(cursor_bytes)
				var rebound := QuantityErrorBounds.restore(error_bytes)
				if cursor == null or rebound == null:
					return {}
				barrier = QuantityLayerLedger.Pool.new(QuantityCodec.decode(QuantityCodec.encode(barrier.amount)), rebound)
	var before_final := Time.get_ticks_usec()
	var final_raw := QuantityFraction.create(Quantity.from_count(int(row["attack"])), Quantity.from_count(1))
	var nominal := Quantity.from_count(int(row["attack"]))
	var final := QuantityLayerLedger.draft(final_raw, nominal, [barrier, second], hp, true)
	if final == null:
		return {}
	var heal_offer := Quantity.from_count(2)
	var healed := QuantityLayerLedger.recovery(QuantityFraction.from_amount(heal_offer), heal_offer, final.hp.after,
			hp.amount, bool(row["excess"]))
	if healed == null:
		return {}
	elapsed += Time.get_ticks_usec() - before_final
	measured.durations.append(elapsed)
	measured.max_static_memory = maxf(measured.max_static_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	var projected: Array[String] = []
	for value: Quantity in [final.layers[0].spent, final.layers[1].spent, final.hp.spent, final.hp.after.amount,
			final.overkill, final.incoming, final.eligible_hostile_hp, healed.hp_restored, healed.hp.amount,
			healed.eligible_excess.amount, healed.discarded, origins[0], origins[1], origins[2]]:
		var image := _wire(value)
		if image.is_empty():
			return {}
		projected.append(image)
	return {"receipts": receipts, "amounts": projected, "lethal": final.lethal,
		"depleted": [final.layers[0].hostile_depletion, final.layers[1].hostile_depletion],
		"first_interval_expired": not barrier.error.is_exact() and barrier.error.replay_size() == 0}


func _wire(amount: Quantity) -> String:
	var bytes := QuantityCodec.encode(amount)
	var decoded := QuantityCodec.decode(bytes)
	return bytes.hex_encode() if decoded != null and decoded.compare(amount) == 0 else ""
