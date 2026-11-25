extends SceneTree
## Disposable cross-check runner. Reads synthetic operands and emits native outcomes.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var input := FileAccess.open(args[0], FileAccess.READ)
	var evidence := FileAccess.open(args[1], FileAccess.WRITE)
	if input == null or evidence == null:
		quit(2)
		return
	var vectors: Variant = JSON.parse_string(input.get_as_text())
	if not vectors is Array or vectors.is_empty():
		quit(2)
		return
	var results: Array[Dictionary] = []
	for input_row: Dictionary in vectors:
		var left := _read_amount(input_row["left"])
		var right := _read_amount(input_row["right"])
		var values: Array[Quantity] = [
			left.add(right), left.subtract(right), left.multiply(right), Quantity.quantize_ratio(left, right),
		]
		var encoded: Array[String] = []
		for amount: Quantity in values:
			if amount == null:
				quit(1)
				return
			var bytes := QuantityCodec.encode(amount)
			var inspected := QuantityCodec.decode(bytes)
			if inspected == null or inspected.compare(amount) != 0:
				quit(1)
				return
			encoded.append(bytes.hex_encode())
		results.append({"encoded": encoded, "compare": left.compare(right)})
	evidence.store_string(JSON.stringify(results))
	evidence.close()
	print("WP04_NATIVE_VECTORS ", results.size())
	quit(0)


func _read_amount(value: Dictionary) -> Quantity:
	return Quantity.from_canonical(value["negative"], int(value["scale"]), value["magnitude"])
