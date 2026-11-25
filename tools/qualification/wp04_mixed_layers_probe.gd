extends SceneTree

class Measurements:
	var durations := PackedInt64Array()
	var compact_count := 0
	var interval_count := 0
	var cursor_bytes := 0
	var error_bytes := 0
	var max_static_memory := 0.0
	var frame_intervals := PackedInt64Array()

	func summary() -> Dictionary:
		var result := {"histories": durations.size(), "represented_compact_postings": compact_count,
			"interval_pool_postings": interval_count, "peak_cursor_bytes": cursor_bytes,
			"peak_error_checkpoint_bytes": error_bytes, "sampled_global_static_memory_bytes": max_static_memory,
			"native_us_per_history": _percentiles(durations)}
		if not frame_intervals.is_empty():
			result["rendered_frame_intervals"] = frame_intervals.size()
			result["rendered_inter_frame_us"] = _percentiles(frame_intervals)
		return result

	static func _percentiles(samples: PackedInt64Array) -> Dictionary:
		samples.sort()
		var size := samples.size()
		return {"p50": samples[ceili(size * 0.50) - 1], "p95": samples[ceili(size * 0.95) - 1],
			"p99": samples[ceili(size * 0.99) - 1], "max": samples[-1]}


class WorkloadView:
	extends Node2D

	var step: int

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.86, 0.82, 0.72))
		for index: int in 128:
			var center := Vector2(30 + (index * 67 + step * 3) % 900, 24 + index * 83 % 460)
			draw_circle(center, 7, Color(0.23, 0.29, 0.29))
		draw_string(ThemeDB.fallback_font, Vector2(24, 516), "WP04 numeric workload • %d" % step)


var _rows: Array
var _output: FileAccess
var _results: Array[Dictionary] = []
var _measured := Measurements.new()
var _display: WorkloadView
var _previous_frame: int


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var rendered := arguments.size() == 3 and arguments[2] == "rendered"
	if arguments.size() != 2 and not rendered:
		quit(2)
		return
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	_output = FileAccess.open(arguments[1], FileAccess.WRITE)
	if not rows is Array or rows.is_empty() or _output == null:
		quit(2)
		return
	_rows = rows
	if rendered:
		root.size = Vector2i(960, 540)
		Engine.max_fps = 60
		_display = WorkloadView.new()
		root.add_child(_display)
		process_frame.connect(_render_frame)
		return
	for row: Dictionary in _rows:
		if not _record(row):
			quit(1)
			return
	_finish()


func _render_frame() -> void:
	var now := Time.get_ticks_usec()
	var index := _results.size()
	if index >= 30:
		_measured.frame_intervals.append(now - _previous_frame)
	_previous_frame = now
	if not _record(_rows[index]):
		process_frame.disconnect(_render_frame)
		quit(1)
		return
	_display.step = index + 1
	_display.queue_redraw()
	if _results.size() == _rows.size():
		process_frame.disconnect(_render_frame)
		await RenderingServer.frame_post_draw
		_finish()


func _record(row: Dictionary) -> bool:
	var result := _run(row, _measured)
	if result.is_empty():
		return false
	_results.append(result)
	return true


func _finish() -> void:
	_output.store_string(JSON.stringify({"rows": _results, "measurement": _measured.summary()}))
	_output.close()
	print("WP04_MIXED_LAYERS ", _results.size())
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
	var reserve := QuantityLayerLedger.Pool.new(Quantity.from_count(5), QuantityErrorBounds.new())
	var cap := reserve.amount.add(Quantity.from_count(int(row["reserve_room_tenths"]), 1))
	var converted := QuantityLayerLedger.recovery_to_reserve(QuantityFraction.from_amount(heal_offer),
			heal_offer, final.hp.after, hp.amount, reserve, cap)
	if converted == null:
		return {}
	elapsed += Time.get_ticks_usec() - before_final
	measured.durations.append(elapsed)
	measured.max_static_memory = maxf(measured.max_static_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	var projected: Array[String] = []
	for value: Quantity in [final.layers[0].spent, final.layers[1].spent, final.hp.spent, final.hp.after.amount,
			final.overkill, final.incoming, final.eligible_hostile_hp, healed.hp_restored, healed.hp.amount,
			healed.eligible_excess.amount, healed.discarded, origins[0], origins[1], origins[2],
			converted.reserve_stored, converted.reserve_after.amount, converted.discarded]:
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
