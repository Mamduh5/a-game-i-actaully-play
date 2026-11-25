extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if not cases is Array or output == null:
		quit(2)
		return
	var rows: Array[Dictionary] = []
	for row: Dictionary in cases:
		var posted := _post(row)
		if posted.is_empty():
			quit(1)
			return
		rows.append(posted)
	output.store_string(JSON.stringify(rows))
	output.close()
	print("WP04_LEDGER_CASES ", rows.size())
	quit(0)


func _post(row: Dictionary) -> Dictionary:
	var fields: Array[Quantity] = []
	for item: Dictionary in row["amounts"]:
		fields.append(Quantity.from_canonical(item["negative"], int(item["scale"]), item["magnitude"]))
	var layers: Array[Quantity] = [fields[2], fields[3]]
	var damage := QuantityPosting.damage(fields[0], layers, fields[1], row["hostile"])
	if damage == null:
		return {}
	var clamped := QuantityPosting.clamp_capacity(damage.hp_remaining, fields[4])
	if clamped == null:
		return {}
	var healed := QuantityPosting.recovery(fields[5], clamped.amount_after, fields[4], row["excess"])
	if healed == null:
		return {}
	var stored := QuantityPosting.capped_gain(fields[6], fields[7], healed.eligible_excess)
	if stored == null:
		return {}
	var released := QuantityPosting.reserve_release(stored.amount_after, healed.hp_after, fields[4])
	if released == null:
		return {}
	var posted: Array[Quantity] = [
		damage.layers[0].absorbed, damage.layers[0].remaining, damage.layers[1].absorbed, damage.layers[1].remaining,
		damage.hp_removed, damage.hp_remaining, damage.eligible_hostile_hp, damage.overkill,
		clamped.amount_after, clamped.remainder, healed.hp_restored, healed.hp_after, healed.eligible_excess,
		healed.discarded, stored.accepted, stored.amount_after, stored.remainder, released.hp_restored,
		released.hp_after, released.reserve_spent, released.reserve_after,
	]
	var encoded: Array[String] = []
	for value: Quantity in posted:
		var bytes := QuantityCodec.encode(value)
		var decoded := QuantityCodec.decode(bytes)
		if decoded == null or decoded.compare(value) != 0:
			return {}
		encoded.append(bytes.hex_encode())
	return {"amounts": encoded, "depleted": [damage.layers[0].hostile_depletion, damage.layers[1].hostile_depletion],
		"lethal": damage.lethal}
