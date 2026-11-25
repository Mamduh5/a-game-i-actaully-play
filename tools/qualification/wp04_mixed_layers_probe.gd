extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		quit(2)
		return
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var output := FileAccess.open(arguments[1], FileAccess.WRITE)
	if not rows is Array or output == null:
		quit(2)
		return
	var results: Array[Dictionary] = []
	for row: Dictionary in rows:
		var result := _run(row)
		if result.is_empty():
			quit(1)
			return
		results.append(result)
	output.store_string(JSON.stringify(results))
	output.close()
	print("WP04_MIXED_LAYERS ", results.size())
	quit(0)


func _run(row: Dictionary) -> Dictionary:
	var barrier := QuantityLayerLedger.Pool.new(Quantity.from_count(100), QuantityErrorBounds.new())
	var hp := QuantityLayerLedger.Pool.new(Quantity.from_count(int(row["hp"])), QuantityErrorBounds.new())
	var second := QuantityLayerLedger.Pool.new(Quantity.from_count(1), QuantityErrorBounds.new())
	var receipts: Array[Array] = []
	var origins: Array[Quantity] = [Quantity.from_count(0), Quantity.from_count(0), Quantity.from_count(0)]
	for index: int in row["rates"].size():
		var denominator := int(row["rates"][index])
		var raw := QuantityFraction.create(Quantity.from_count(10), Quantity.from_count(denominator))
		var cursor := QuantityRateCursor.create(raw.numerator, raw.divisor)
		if cursor == null:
			return {}
		for occurrence: int in 3:
			var nominal := cursor.next_debit()
			var hit := QuantityLayerLedger.draft(raw, nominal, [barrier, second], hp, true)
			if hit == null or hit.layers[0].hostile_depletion or hit.hp.spent.sign_value != 0:
				return {}
			barrier = hit.layers[0].after
			var origin := (index + occurrence) % origins.size()
			origins[origin] = origins[origin].add(hit.layers[0].spent)
			receipts.append([origin, _wire(hit.layers[0].spent)])
			if occurrence == 0:
				cursor = QuantityRateCursor.restore(cursor.snapshot())
				var rebound := QuantityErrorBounds.restore(barrier.error.snapshot())
				if cursor == null or rebound == null:
					return {}
				barrier = QuantityLayerLedger.Pool.new(QuantityCodec.decode(QuantityCodec.encode(barrier.amount)), rebound)
	var final_raw := QuantityFraction.create(Quantity.from_count(int(row["attack"])), Quantity.from_count(1))
	var nominal := Quantity.from_count(int(row["attack"]))
	var final := QuantityLayerLedger.draft(final_raw, nominal, [barrier, second], hp, true)
	if final == null:
		return {}
	var healed := QuantityPosting.recovery(Quantity.from_count(2), final.hp.after.amount,
			hp.amount, bool(row["excess"]))
	if healed == null:
		return {}
	var projected: Array[String] = []
	for value: Quantity in [final.layers[0].spent, final.layers[1].spent, final.hp.spent, final.hp.after.amount,
			final.overkill, final.incoming, final.eligible_hostile_hp, healed.hp_restored, healed.hp_after,
			healed.eligible_excess, healed.discarded, origins[0], origins[1], origins[2]]:
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
