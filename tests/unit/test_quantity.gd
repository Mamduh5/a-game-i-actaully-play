extends GutTest


func test_ordinary_counts_normalize_and_use_native_arithmetic() -> void:
	var one := Quantity.from_count(1_000_000, 6)
	var minus := Quantity.from_count(-215, 2)
	_assert_amount(one, "1", 0, 1)
	_assert_amount(one.add(minus), "115", 2, -1)
	_assert_amount(one.subtract(minus), "315", 2, 1)
	_assert_amount(one.multiply(minus), "215", 2, -1)
	_assert_amount(one.subtract(one), "0", 0, 0)
	assert_false(one.add(minus).uses_limbs)
	assert_eq(minus.compare(one), -1)
	assert_eq(minus.compare(Quantity.from_count(-216, 2)), 1)
	assert_eq(Quantity.from_count(-2150, 3).compare(minus), 0)


func test_promotes_before_signed_addition_multiplication_and_scale_alignment() -> void:
	var max_native := Quantity.from_count(Quantity.INT_MAX)
	var one := Quantity.from_count(1)
	var twice := Quantity.from_count(2)
	var next := max_native.add(one)
	_assert_amount(next, "9223372036854775808", 0, 1)
	assert_true(next.uses_limbs)
	assert_false(next.subtract(one).uses_limbs)
	_assert_amount(max_native.multiply(twice), "18446744073709551614", 0, 1)
	var minimum := Quantity.from_count(Quantity.INT_MIN)
	_assert_amount(minimum, "9223372036854775808", 0, -1)
	_assert_amount(minimum.subtract(one), "9223372036854775809", 0, -1)
	_assert_amount(next.add(minimum), "0", 0, 0)
	var tiny := Quantity.from_count(25, 8)
	_assert_amount(max_native.add(tiny), "922337203685477580700000025", 8, 1)
	assert_eq(max_native.compare(max_native.add(tiny)), -1)
	assert_eq(max_native.subtract(tiny).compare(max_native), -1)


func test_widened_product_carry_and_decimal_normalization() -> void:
	var left := Quantity.from_canonical(false, 0, "999999999999999999")
	var right := Quantity.from_canonical(false, 0, "999999999999999999")
	_assert_amount(left.multiply(right), "999999999999999998000000000000000001", 0, 1)
	var half := Quantity.from_count(5, 1)
	var two := Quantity.from_count(2)
	_assert_amount(left.multiply(half).multiply(two), left.magnitude_text(), 0, 1)
	var approaching := Quantity.from_canonical(false, 10, "9999999999999999999999")
	var step := Quantity.from_count(1, 10)
	_assert_amount(approaching.add(step), "1000000000000", 0, 1)


func test_huge_hp_keeps_small_debits_and_survives_binary_and_disk_round_trips() -> void:
	var original := Quantity.from_canonical(false, 0, "1" + "0".repeat(400))
	var one := Quantity.from_count(1)
	var quarter := Quantity.from_count(25, 8)
	var hp := original.subtract(one).subtract(one).add(one)
	_assert_amount(hp, "9".repeat(400), 0, 1)
	for _i: int in 4:
		hp = hp.subtract(quarter)
	hp = hp.add(Quantity.from_count(1, 6))
	assert_eq(hp.compare(original.subtract(one)), 0)
	var encoded := QuantityCodec.encode(hp)
	var decoded := QuantityCodec.decode(encoded)
	assert_eq(decoded.compare(hp), 0)
	assert_eq(QuantityCodec.encode(decoded), encoded)
	var path := "user://wp04-quantity-%d.bin" % OS.get_process_id()
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_buffer(encoded)
	output.store_buffer(QuantityCodec.encode(quarter))
	output.close()
	var input := FileAccess.open(path, FileAccess.READ)
	assert_eq(QuantityCodec.read_value(input).compare(hp), 0)
	assert_eq(QuantityCodec.read_value(input).compare(quarter), 0)
	input.close()
	DirAccess.remove_absolute(path)


func test_codec_and_resource_bounds_fail_explicitly_without_wrapping() -> void:
	for bad: String in ["", "00", "05", "100", "2e4", "+5", "９", " 5"]:
		assert_null(Quantity.from_canonical(false, 1, bad), bad)
	assert_null(Quantity.from_canonical(true, 0, "0"))
	assert_null(Quantity.from_count(1, Quantity.MAX_SCALE + 1))
	var widest := Quantity.from_canonical(false, 0, "9".repeat(Quantity.MAX_DIGITS))
	assert_null(widest.add(Quantity.from_count(1)))
	assert_eq(widest.magnitude_text().length(), Quantity.MAX_DIGITS)
	var smallest := Quantity.from_count(1, Quantity.MAX_SCALE)
	assert_null(smallest.multiply(Quantity.from_count(1, 1)))
	var message := QuantityCodec.encode(Quantity.from_count(100))
	assert_null(QuantityCodec.decode(message.slice(0, -1)))
	var altered := message.duplicate()
	altered[0] = 17
	assert_null(QuantityCodec.decode(altered))
	altered = message.duplicate()
	altered.encode_u32(4, 0xffffffff)
	assert_null(QuantityCodec.decode(altered))
	altered = QuantityCodec.encode(Quantity.from_count(0))
	altered[1] = 1
	assert_null(QuantityCodec.decode(altered))
	altered = message.duplicate()
	altered[8] = 0
	assert_null(QuantityCodec.decode(altered))


func test_ratio_scale_and_rounding_cover_midpoints_and_tiny_transfers() -> void:
	var one := Quantity.from_count(1)
	var two := Quantity.from_count(2)
	var tiny_denominator := Quantity.from_count(4_000_000)
	assert_eq(Quantity.ratio_scale(one, tiny_denominator), 12)
	_assert_amount(Quantity.quantize_ratio(one, tiny_denominator), "25", 8, 1)
	_assert_amount(Quantity.round_ratio(one, two, 0), "0", 0, 0)
	_assert_amount(Quantity.round_ratio(Quantity.from_count(-3), two, 0), "2", 0, -1)
	_assert_amount(Quantity.round_ratio(Quantity.from_count(5), two, 0), "2", 0, 1)
	_assert_amount(Quantity.quantize_ratio(Quantity.from_count(0), tiny_denominator), "0", 0, 0)
	assert_null(Quantity.quantize_ratio(one, Quantity.from_count(0)))


func test_wide_division_checks_intermediates_and_preserves_the_final_quotient() -> void:
	var a := Quantity.from_count(Quantity.INT_MAX)
	var a_times_three := a.multiply(Quantity.from_count(3))
	assert_true(a_times_three.uses_limbs)
	_assert_amount(Quantity.round_ratio(a_times_three, a, 6), "3", 0, 1)
	var large := Quantity.from_canonical(false, 0, "1" + "0".repeat(40))
	var divisor := Quantity.from_canonical(false, 0, "100000000000000000003")
	_assert_amount(Quantity.round_ratio(large, divisor, 3), "99999999999999999997", 0, 1)
	var left := Quantity.from_canonical(false, 0, "9223372036854775808")
	_assert_amount(Quantity.round_ratio(left, Quantity.from_count(8), 0), "1152921504606846976", 0, 1)
	var finer := Quantity.from_count(1, Quantity.MAX_SCALE)
	assert_null(Quantity.quantize_ratio(finer, Quantity.from_count(2)))


func test_thirds_post_cumulatively_and_restore_the_live_frontier() -> void:
	var cursor := QuantityRateCursor.create(Quantity.from_count(1), Quantity.from_count(3))
	assert_eq(cursor.grid, 6)
	_assert_amount(cursor.next_debit(), "333333", 6, 1)
	var bytes := cursor.snapshot()
	var resumed := QuantityRateCursor.restore(bytes)
	assert_eq(resumed.snapshot(), bytes)
	assert_eq(resumed.occurrences, 1)
	_assert_amount(resumed.next_debit(), "333334", 6, 1)
	_assert_amount(resumed.next_debit(), "333333", 6, 1)
	_assert_amount(resumed.posted, "1", 0, 1)
	var damaged := bytes.duplicate()
	damaged[-1] = 53
	assert_null(QuantityRateCursor.restore(damaged))
	var new_stream := QuantityRateCursor.create(Quantity.from_count(1), Quantity.from_count(3))
	_assert_amount(new_stream.next_debit(), "333333", 6, 1)


func _assert_amount(amount: Quantity, digits: String, decimal_scale: int, signum: int) -> void:
	assert_not_null(amount)
	if amount != null:
		assert_eq(amount.magnitude_text(), digits)
		assert_eq(amount.scale, decimal_scale)
		assert_eq(amount.sign_value, signum)
